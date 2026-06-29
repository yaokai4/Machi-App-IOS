import Foundation
import SwiftData

@MainActor
final class UserRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchUsers() async throws -> [UserEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            return try await KaiXAPIClient.shared.trending().users
                .map(Self.entity(from:))
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
        return try context.fetch(FetchDescriptor<UserEntity>(sortBy: [SortDescriptor(\.displayName)]))
    }

    func fetchUsers(ids: Set<String>) async throws -> [UserEntity] {
        let normalizedIds = Self.nonEmptyIds(ids)
        guard !normalizedIds.isEmpty else { return [] }
        var remoteUsers: [UserEntity] = []
        for id in normalizedIds {
            if let dto = try? await KaiXAPIClient.shared.userDetail(id) {
                remoteUsers.append(Self.entity(from: dto))
            }
        }
        if !remoteUsers.isEmpty || !KaiXRuntimeFlags.allowLocalStoreFallback {
            return Self.uniqueUsers(remoteUsers)
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        }
        let idList = normalizedIds
        return try context.fetch(FetchDescriptor<UserEntity>(
            predicate: #Predicate { idList.contains($0.id) },
            sortBy: [SortDescriptor(\.displayName)]
        ))
    }

    func fetchRecommendedUsers(excluding userId: String, limit: Int = 12) async throws -> [UserEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            return Array(try await KaiXAPIClient.shared.trending().users
                .map(Self.entity(from:))
                .filter { $0.id != userId }
                .prefix(limit))
        }
        var descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate { $0.id != userId },
            sortBy: [SortDescriptor(\.followerCount, order: .reverse), SortDescriptor(\.displayName)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func fetchUser(id: String) async throws -> UserEntity? {
        let userId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userId.isEmpty else { return nil }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            return Self.entity(from: try await KaiXAPIClient.shared.userDetail(userId))
        }
        var descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.id == userId })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func login(username: String, password: String) async throws -> UserEntity? {
        let normalized = username.normalizedUsername
        var descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.username == normalized })
        descriptor.fetchLimit = 1
        guard let user = try context.fetch(descriptor).first else { return nil }
        guard PasswordHasher.verify(password, storedHash: user.passwordHash) else { return nil }

        if PasswordHasher.needsUpgrade(user.passwordHash) {
            user.passwordHash = PasswordHasher.hash(password)
            user.updatedAt = .now
            try context.save()
        }
        return user
    }

    func register(username: String, displayName: String, password: String, region: KaiXRegionDirectory.Region? = nil) async throws -> UserEntity {
        let normalized = username.normalizedUsername
        guard normalized.isEmpty == false, password.count >= AuthValidation.passwordMinLength else {
            throw RepositoryError.validationFailed
        }

        var descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.username == normalized })
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else {
            throw RepositoryError.duplicate
        }

        let user = UserEntity(
            username: normalized,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            bio: "",
            location: region?.cityName ?? "",
            passwordHash: PasswordHasher.hash(password),
            avatarSymbol: "person.fill",
            avatarColorName: "indigo",
            country: region?.countryCode ?? "",
            province: region?.provinceCode ?? "",
            city: region?.cityCode ?? "",
            currentRegionCode: region?.regionCode ?? "",
            recentRegionCodesRaw: region.map { $0.regionCode } ?? ""
        )
        context.insert(user)
        try context.save()
        return user
    }

    func updateProfile(user: UserEntity, displayName: String, bio: String, location: String) async throws {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if KaiXBackend.token != nil {
            let updated = try await KaiXAPIClient.shared.updateMe([
                "display_name": trimmedName,
                "bio": trimmedBio,
                "location": trimmedLocation,
            ])
            Self.apply(updated, to: user)
            return
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { throw RepositoryError.authenticationRequired }
        user.displayName = trimmedName
        user.bio = trimmedBio
        user.location = trimmedLocation
        user.updatedAt = .now
        try context.save()
    }

    func updateUsername(user: UserEntity, username: String) async throws {
        let normalized = username.normalizedUsername
        guard normalized.isEmpty == false else {
            throw RepositoryError.validationFailed
        }
        guard normalized != user.username else { return }

        if KaiXBackend.token != nil {
            let updated = try await KaiXAPIClient.shared.updateMe(["handle": normalized])
            Self.apply(updated, to: user)
            return
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { throw RepositoryError.authenticationRequired }

        var descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.username == normalized })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first, existing.id != user.id {
            throw RepositoryError.duplicate
        }

        user.username = normalized
        user.updatedAt = .now
        try context.save()

    }

    func isFollowing(followerId: String, followingId: String) async throws -> Bool {
        let targetId = followingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetId.isEmpty else { return false }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let dto = try await KaiXAPIClient.shared.userDetail(targetId)
            return dto.is_following ?? dto.isFollowing ?? false
        }
        var descriptor = FetchDescriptor<FollowEntity>(predicate: #Predicate {
            $0.followerId == followerId && $0.followingId == targetId
        })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty == false
    }

    func followingIds(for userId: String) async throws -> Set<String> {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return [] }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            return Set(try await KaiXAPIClient.shared.following(id).map(\.id))
        }
        let follows = try context.fetch(FetchDescriptor<FollowEntity>(
            predicate: #Predicate { $0.followerId == id }
        ))
        return Set(follows.map(\.followingId))
    }

    func fetchFollowers(userId: String) async throws -> [UserEntity] {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return [] }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            return Self.uniqueUsers(try await KaiXAPIClient.shared.followers(id)
                .map(Self.entity(from:))
            )
            .sorted {
                    if $0.followerCount == $1.followerCount {
                        return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                    }
                    return $0.followerCount > $1.followerCount
                }
        }
        let follows = try context.fetch(FetchDescriptor<FollowEntity>(
            predicate: #Predicate { $0.followingId == id }
        ))
        let ids = Set(follows.map(\.followerId))
        return try await fetchUsers(ids: ids)
            .sorted {
                if $0.followerCount == $1.followerCount {
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                return $0.followerCount > $1.followerCount
            }
    }

    func fetchFollowing(userId: String) async throws -> [UserEntity] {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return [] }
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            return Self.uniqueUsers(try await KaiXAPIClient.shared.following(id)
                .map(Self.entity(from:))
            )
            .sorted {
                    if $0.followerCount == $1.followerCount {
                        return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                    }
                    return $0.followerCount > $1.followerCount
                }
        }
        let follows = try context.fetch(FetchDescriptor<FollowEntity>(
            predicate: #Predicate { $0.followerId == id }
        ))
        let ids = Set(follows.map(\.followingId))
        return try await fetchUsers(ids: ids)
            .sorted {
                if $0.followerCount == $1.followerCount {
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                return $0.followerCount > $1.followerCount
            }
    }

    func toggleFollow(currentUser: UserEntity, targetUser: UserEntity) async throws -> Bool {
        let followerId = currentUser.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let followingId = targetUser.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !followerId.isEmpty, !followingId.isEmpty else { throw RepositoryError.validationFailed }
        if KaiXBackend.token != nil {
            let alreadyFollowing = try await isFollowing(followerId: followerId, followingId: followingId)
            let nextValue = !alreadyFollowing
            try await KaiXAPIClient.shared.setFollow(followingId, nextValue)
            currentUser.followingCount = max(0, currentUser.followingCount + (nextValue ? 1 : -1))
            targetUser.followerCount = max(0, targetUser.followerCount + (nextValue ? 1 : -1))
            return nextValue
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { throw RepositoryError.authenticationRequired }
        var descriptor = FetchDescriptor<FollowEntity>(predicate: #Predicate {
            $0.followerId == followerId && $0.followingId == followingId
        })
        descriptor.fetchLimit = 1

        let alreadyFollowing = try context.fetch(descriptor).first != nil

        if alreadyFollowing, let existing = try context.fetch(descriptor).first {
            context.delete(existing)
            currentUser.followingCount = max(0, currentUser.followingCount - 1)
            targetUser.followerCount = max(0, targetUser.followerCount - 1)
            currentUser.updatedAt = .now
            targetUser.updatedAt = .now
            try context.save()
            return false
        }

        context.insert(FollowEntity(followerId: followerId, followingId: followingId))
        currentUser.followingCount += 1
        targetUser.followerCount += 1
        currentUser.updatedAt = .now
        targetUser.updatedAt = .now
        if NotificationPreferenceService.isEnabled(.follow, recipientUserId: followingId) {
            context.insert(NotificationEntity(type: .follow, actorId: followerId, content: "开始关注你"))
        }
        try context.save()
        return true
    }

    static func entity(from dto: KaiXUserDTO) -> UserEntity {
        let entity = UserEntity(
            id: dto.id,
            username: dto.handle,
            displayName: dto.display_name,
            email: dto.email ?? "",
            avatarURL: dto.avatar_url ?? dto.avatarUrl ?? "",
            coverURL: dto.cover_url ?? "",
            bio: dto.bio ?? "",
            location: dto.location ?? "",
            joinDate: parseDate(dto.joined_at ?? dto.created_at ?? dto.createdAt) ?? .now,
            isVerified: dto.is_verified ?? false,
            role: UserRole(rawValue: dto.role ?? "") ?? .member,
            followerCount: dto.follower_count ?? dto.followerCount ?? 0,
            followingCount: dto.following_count ?? dto.followingCount ?? 0,
            createdAt: parseDate(dto.created_at ?? dto.createdAt) ?? .now,
            updatedAt: parseDate(dto.updated_at ?? dto.updatedAt) ?? .now,
            passwordHash: "",
            avatarSymbol: dto.avatar_symbol ?? "person.fill",
            avatarColorName: dto.avatar_color ?? "indigo",
            remoteId: dto.id,
            syncStatus: .synced,
            country: dto.country ?? "",
            province: dto.province ?? "",
            city: dto.city ?? "",
            currentRegionCode: dto.current_region_code ?? "",
            recentRegionCodesRaw: (dto.recent_region_codes ?? []).joined(separator: "|"),
            membershipLevel: dto.membership_tier ?? "free",
            totalHeat: dto.total_heat ?? 0,
            creatorBadge: dto.creator_badge ?? "",
            isOfficial: dto.is_official ?? dto.isOfficial ?? false,
            officialRole: dto.official_role ?? dto.officialRole ?? "",
            customTagsRaw: (dto.custom_tags ?? []).joined(separator: "|"),
            listingCountsRaw: encodeListingCounts(dto.listing_counts ?? [:]),
            isMerchant: dto.is_merchant ?? false,
            merchantVerified: dto.merchant_verified ?? false,
            profileViewCount: dto.profile_view_count ?? 0,
            isVerifiedMember: dto.is_verified_member ?? dto.isVerifiedMember ?? false,
            verifiedMemberUntil: parseDate(dto.verified_member_until ?? dto.verifiedMemberUntil),
            membershipStatus: dto.membership_status ?? dto.membershipStatus ?? "inactive",
            membershipPlanKey: dto.membership_plan_key ?? dto.membershipPlanKey ?? "",
            appLanguage: dto.app_language ?? "",
            contentLanguagePreference: dto.content_language_preference ?? "",
            preferredContentLanguagesRaw: dto.preferred_content_languages ?? ""
        )
        entity.dmPrivacy = dto.dm_privacy ?? "everyone"
        return entity
    }

    static func uniqueUsers(_ users: [UserEntity]) -> [UserEntity] {
        var seen = Set<String>()
        return users.filter { seen.insert($0.id).inserted }
    }

    static func nonEmptyIds(_ ids: Set<String>) -> [String] {
        var seen = Set<String>()
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted()
    }

    static func apply(_ dto: KaiXUserDTO, to user: UserEntity) {
        let updated = entity(from: dto)
        apply(updated, to: user)
        user.remoteId = dto.id
        user.syncStatus = .synced
    }

    static func apply(_ updated: UserEntity, to user: UserEntity) {
        user.username = updated.username
        user.displayName = updated.displayName
        user.email = updated.email
        user.avatarURL = updated.avatarURL
        user.coverURL = updated.coverURL
        user.bio = updated.bio
        user.location = updated.location
        user.isVerified = updated.isVerified
        user.role = updated.role
        user.followerCount = updated.followerCount
        user.followingCount = updated.followingCount
        user.avatarSymbol = updated.avatarSymbol
        user.avatarColorName = updated.avatarColorName
        user.country = updated.country
        user.province = updated.province
        user.city = updated.city
        user.currentRegionCode = updated.currentRegionCode
        user.recentRegionCodesRaw = updated.recentRegionCodesRaw
        user.membershipLevel = updated.membershipLevel
        user.totalHeat = updated.totalHeat
        user.creatorBadge = updated.creatorBadge
        user.isOfficial = updated.isOfficial
        user.officialRole = updated.officialRole
        user.customTagsRaw = updated.customTagsRaw
        user.listingCountsRaw = updated.listingCountsRaw
        user.isMerchant = updated.isMerchant
        user.merchantVerified = updated.merchantVerified
        user.profileViewCount = updated.profileViewCount
        user.isVerifiedMember = updated.isVerifiedMember
        user.verifiedMemberUntil = updated.verifiedMemberUntil
        user.membershipStatus = updated.membershipStatus
        user.membershipPlanKey = updated.membershipPlanKey
        user.appLanguage = updated.appLanguage
        user.contentLanguagePreference = updated.contentLanguagePreference
        user.preferredContentLanguagesRaw = updated.preferredContentLanguagesRaw
        user.dmPrivacy = updated.dmPrivacy
        user.remoteId = updated.remoteId
        user.syncStatus = .synced
        user.updatedAt = .now
    }

    private static func encodeListingCounts(_ value: [String: Int]) -> String {
        guard !value.isEmpty, let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // Delegates to the cached KXDateParsing formatters (see ServerEntityFactory)
    // — no per-call ISO8601DateFormatter/DateFormatter allocation on the hot path.
    private static func parseDate(_ raw: String?) -> Date? { KXDateParsing.parse(raw) }

    func deleteAccount(user: UserEntity) async throws {
        if KaiXBackend.token != nil {
            try await KaiXAPIClient.shared.deleteMe()
            return
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { throw RepositoryError.authenticationRequired }
        let userId = user.id
        let authoredPosts = try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.authorId == userId }
        ))
        let authoredPostIds = Set(authoredPosts.map(\.id))
        let authoredPostIdList = Array(authoredPostIds)

        let repostedPostIds = Set(authoredPosts.compactMap(\.repostOfPostId))
        if !repostedPostIds.isEmpty {
            let repostedPostIdList = Array(repostedPostIds)
            let repostedPosts = try context.fetch(FetchDescriptor<PostEntity>(
                predicate: #Predicate { repostedPostIdList.contains($0.id) }
            ))
            for post in repostedPosts {
                post.repostCount = max(0, post.repostCount - 1)
                HeatScoreService.shared.refresh(post)
            }
        }
        let reposts = try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.repostOfPostId != nil }
        ))
        for post in reposts where authoredPostIds.contains(post.repostOfPostId ?? "") {
            context.delete(post)
        }

        let comments = try context.fetch(FetchDescriptor<CommentEntity>())
        var deletedCommentIds = Set(comments.filter { $0.authorId == userId || authoredPostIds.contains($0.postId) }.map(\.id))
        var foundNestedReplies = true
        while foundNestedReplies {
            foundNestedReplies = false
            for comment in comments where !deletedCommentIds.contains(comment.id) {
                if let parentId = comment.parentCommentId, deletedCommentIds.contains(parentId) {
                    deletedCommentIds.insert(comment.id)
                    foundNestedReplies = true
                }
            }
        }
        let affectedPostIds = Set(comments.compactMap { comment -> String? in
            guard !authoredPostIds.contains(comment.postId) else { return nil }
            if deletedCommentIds.contains(comment.id) {
                return comment.postId
            }
            return nil
        })
        let affectedPostIdList = Array(affectedPostIds)
        let affectedPosts = try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { affectedPostIdList.contains($0.id) }
        ))
        let affectedPostsById = Dictionary(uniqueKeysWithValues: affectedPosts.map { ($0.id, $0) })
        for comment in comments where deletedCommentIds.contains(comment.id) {
            if !authoredPostIds.contains(comment.postId),
               let post = affectedPostsById[comment.postId] {
                post.commentCount = max(0, post.commentCount - 1)
                HeatScoreService.shared.refresh(post)
            }
            context.delete(comment)
        }

        let postMedia = authoredPostIdList.isEmpty ? [] : try context.fetch(FetchDescriptor<MediaEntity>(
            predicate: #Predicate { authoredPostIdList.contains($0.postId) }
        ))
        for item in postMedia {
            context.delete(item)
        }

        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>())
        for notification in notifications where notification.actorId == userId || authoredPostIds.contains(notification.targetPostId ?? "") {
            context.delete(notification)
        }

        let follows = try context.fetch(FetchDescriptor<FollowEntity>(
            predicate: #Predicate { $0.followerId == userId || $0.followingId == userId }
        ))
        for follow in follows {
            if follow.followerId == userId,
               let target = try await fetchUser(id: follow.followingId) {
                target.followerCount = max(0, target.followerCount - 1)
            }
            if follow.followingId == userId,
               let follower = try await fetchUser(id: follow.followerId) {
                follower.followingCount = max(0, follower.followingCount - 1)
            }
            context.delete(follow)
        }

        let threads = try context.fetch(FetchDescriptor<MessageThreadEntity>())
            .filter { $0.participantIds.contains(userId) }
        let deletedThreadIds = Set(threads.map(\.id))
        let deletedThreadIdList = Array(deletedThreadIds)
        let messages = try context.fetch(FetchDescriptor<MessageEntity>(
            predicate: #Predicate { deletedThreadIdList.contains($0.threadId) || $0.senderId == userId }
        ))
        let deletedMessageIds = Set(messages.map(\.id))
        for message in messages {
            context.delete(message)
        }
        for thread in threads {
            context.delete(thread)
        }
        let deletedMessageIdList = Array(deletedMessageIds)
        let messageMedia = deletedMessageIdList.isEmpty ? [] : try context.fetch(FetchDescriptor<MediaEntity>(
            predicate: #Predicate { deletedMessageIdList.contains($0.postId) }
        ))
        for item in messageMedia {
            context.delete(item)
        }

        for post in authoredPosts {
            context.delete(post)
        }
        context.delete(user)

        try context.save()
        try await TopicRepository(context: context).rebuildFromPosts()
    }
}
