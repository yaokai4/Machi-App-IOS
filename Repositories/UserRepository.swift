import Foundation
import SwiftData

@MainActor
final class UserRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchUsers() async throws -> [UserEntity] {
        try context.fetch(FetchDescriptor<UserEntity>(sortBy: [SortDescriptor(\.displayName)]))
    }

    func fetchUsers(ids: Set<String>) async throws -> [UserEntity] {
        guard !ids.isEmpty else { return [] }
        let idList = Array(ids)
        return try context.fetch(FetchDescriptor<UserEntity>(
            predicate: #Predicate { idList.contains($0.id) },
            sortBy: [SortDescriptor(\.displayName)]
        ))
    }

    func fetchRecommendedUsers(excluding userId: String, limit: Int = 12) async throws -> [UserEntity] {
        var descriptor = FetchDescriptor<UserEntity>(
            predicate: #Predicate { $0.id != userId },
            sortBy: [SortDescriptor(\.followerCount, order: .reverse), SortDescriptor(\.displayName)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func fetchUser(id: String) async throws -> UserEntity? {
        var descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.id == id })
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
        guard normalized.isEmpty == false, password.count >= 6 else {
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
        user.displayName = trimmedName
        user.bio = trimmedBio
        user.location = trimmedLocation
        user.updatedAt = .now
        try context.save()
        // Persist to the unified backend so the Web client picks up the
        // change on the next refresh.
        if KaiXBackend.token != nil {
            Task.detached {
                _ = try? await KaiXAPIClient.shared.updateMe([
                    "display_name": trimmedName,
                    "bio": trimmedBio,
                    "location": trimmedLocation,
                ])
            }
        }
    }

    func updateUsername(user: UserEntity, username: String) async throws {
        let normalized = username.normalizedUsername
        guard normalized.isEmpty == false else {
            throw RepositoryError.validationFailed
        }
        guard normalized != user.username else { return }

        var descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.username == normalized })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first, existing.id != user.id {
            throw RepositoryError.duplicate
        }

        user.username = normalized
        user.updatedAt = .now
        try context.save()

        if KaiXBackend.token != nil {
            Task.detached {
                _ = try? await KaiXAPIClient.shared.updateMe(["handle": normalized])
            }
        }
    }

    func isFollowing(followerId: String, followingId: String) async throws -> Bool {
        var descriptor = FetchDescriptor<FollowEntity>(predicate: #Predicate {
            $0.followerId == followerId && $0.followingId == followingId
        })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty == false
    }

    func followingIds(for userId: String) async throws -> Set<String> {
        let follows = try context.fetch(FetchDescriptor<FollowEntity>(
            predicate: #Predicate { $0.followerId == userId }
        ))
        return Set(follows.map(\.followingId))
    }

    func fetchFollowers(userId: String) async throws -> [UserEntity] {
        let follows = try context.fetch(FetchDescriptor<FollowEntity>(
            predicate: #Predicate { $0.followingId == userId }
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
        let follows = try context.fetch(FetchDescriptor<FollowEntity>(
            predicate: #Predicate { $0.followerId == userId }
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
        let followerId = currentUser.id
        let followingId = targetUser.id
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
            // Mirror to the unified backend so the Web client sees it too.
            if KaiXBackend.token != nil {
                Task.detached { try? await KaiXAPIClient.shared.setFollow(followingId, false) }
            }
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
        if KaiXBackend.token != nil {
            Task.detached { try? await KaiXAPIClient.shared.setFollow(followingId, true) }
        }
        return true
    }

    func deleteAccount(user: UserEntity) async throws {
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
