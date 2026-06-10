import Foundation
import SwiftData

/// Bridge between the unified KaiX backend and the existing
/// SwiftData-based iOS persistence layer.
///
/// The App's screens read from SwiftData entities (`UserEntity`,
/// `PostEntity`, `CommentEntity`, …). To put iOS on the same data
/// source as Web without rewriting every Repository, this service
/// pulls fresh records from `/api/*` and upserts them into SwiftData
/// (mirroring `remoteId == server id`). It is intended to be invoked
/// from the existing `HomeViewModel.refresh()` / pull-to-refresh and
/// from app launch.
///
/// All inserts are idempotent: matching `remoteId` updates the
/// existing entity rather than duplicating it.
@MainActor
final class RemoteSyncService {
    static let shared = RemoteSyncService()

    private let api = KaiXAPIClient.shared
    private let iso = ISO8601DateFormatter()

    init() {
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    /// Decode an ISO8601 timestamp emitted by the backend. Returns nil
    /// when the input is nil or unparseable; callers decide on a
    /// sensible per-field fallback.
    private func parsedDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = iso.date(from: s) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Decode an ISO8601 timestamp emitted by the backend. Falls back
    /// to `.now` when missing — appropriate for "last seen" style
    /// fields, NOT for immutable fields like joinDate.
    private func date(_ s: String?) -> Date {
        parsedDate(s) ?? .now
    }

    // MARK: - login

    /// Authenticate against the unified backend and upsert the user
    /// into SwiftData. Persists the token in `KaiXBackend.token` so
    /// subsequent calls carry it automatically.
    @discardableResult
    func loginAndSync(handle: String, password: String, captchaId: String? = nil, captchaCode: String? = nil, context: ModelContext) async throws -> UserEntity {
        let response = try await api.login(handle: handle, password: password, captchaId: captchaId, captchaCode: captchaCode)
        let entity = upsertUser(response.user, context: context)
        AuthService.shared.persistSession(user: entity)
        try? context.save()
        Task { await self.bootstrap(context: context) }
        return entity
    }

    /// Register a brand-new account against the unified backend and
    /// upsert into SwiftData.
    @discardableResult
    func registerAndSync(handle: String, displayName: String, password: String, email: String? = nil, code: String? = nil, region: KaiXRegionDirectory.Region, appLanguage: AppLanguage? = nil, context: ModelContext) async throws -> UserEntity {
        let response = try await api.register(handle: handle, displayName: displayName, password: password, email: email, code: code, region: region, appLanguage: appLanguage)
        let entity = upsertUser(response.user, context: context)
        AuthService.shared.persistSession(user: entity)
        try? context.save()
        return entity
    }

    /// Pull a full bootstrap payload (current user, recent feed,
    /// notifications, conversations) on app launch / after login so
    /// SwiftData reflects what the server has — same data the Web
    /// client sees.
    func bootstrap(context: ModelContext) async {
        do {
            let payload = try await api.bootstrap()
            _ = upsertUser(payload.user, context: context)
            for post in payload.feed {
                if let author = post.author { _ = upsertUser(author, context: context) }
                _ = upsertPost(post, context: context)
            }
            try? context.save()
        } catch let apiError as KaiXAPIError {
            // 401 / 403 should be visible to the app so it can route to
            // login. `KaiXAPIClient.request` already wipes the bearer
            // and posts `kaiXSessionInvalidated`; logging out locally
            // here just keeps the two stores aligned.
            if apiError.error.code == "unauthorized" || apiError.error.code.hasPrefix("http_401") {
                AuthService.shared.logout()
            }
            // Other API errors are not retryable from here; leave the
            // local cache as-is so the UI can keep working offline.
        } catch {
            // Pure transport errors (DNS / TLS / timeout) — fall back
            // to the local SwiftData cache silently.
        }
    }

    /// Wire-level follow/unfollow that talks to the unified backend.
    /// Local SwiftData FollowEntity should be reconciled by the
    /// caller; the source of truth is the server.
    func follow(_ targetUserId: String, on: Bool) async throws {
        try await api.setFollow(targetUserId, on)
    }

    /// Send a comment through the unified API and upsert into
    /// SwiftData so other open screens see it right away.
    @discardableResult
    func sendComment(postId: String, content: String, parentId: String? = nil, replyToUserId: String? = nil, context: ModelContext) async throws -> CommentEntity {
        let dto = try await api.createComment(postId: postId, content: content, parentId: parentId, replyToUserId: replyToUserId)
        if let author = dto.author { _ = upsertUser(author, context: context) }
        let entity = upsertComment(dto, context: context)
        try? context.save()
        return entity
    }

    /// Mirror a profile edit to the server.
    @discardableResult
    func updateProfile(displayName: String, bio: String, location: String, context: ModelContext) async throws -> UserEntity {
        let patch = [
            "display_name": displayName,
            "bio": bio,
            "location": location,
        ]
        let dto = try await api.updateMe(patch)
        let entity = upsertUser(dto, context: context)
        try? context.save()
        return entity
    }

    /// Mirror the server's notifications (others liking / commenting on /
    /// following YOU) into SwiftData so the in-app list and the system
    /// banners both see them. Returns the entities that are NEW to this
    /// device and still unread — the caller forwards those to
    /// `SystemNotificationService` so each one banners exactly once.
    @discardableResult
    func syncNotifications(context: ModelContext) async -> [NotificationEntity] {
        do {
            let response = try await api.notifications()
            var fresh: [NotificationEntity] = []
            for dto in response.items {
                if let actor = dto.actor { _ = upsertUser(actor, context: context) }
                let (entity, isNew) = upsertNotification(dto, context: context)
                if isNew, !entity.isRead {
                    fresh.append(entity)
                }
            }
            try? context.save()
            return fresh
        } catch {
            return []
        }
    }

    @discardableResult
    func upsertNotification(_ dto: KaiXNotificationDTO, context: ModelContext) -> (NotificationEntity, isNew: Bool) {
        let serverId = dto.id
        // Translate server-side target ids to the local entity ids the UI
        // navigates with (posts composed on this device keep a local UUID
        // and carry the server id in `remoteId`).
        let localPostId = dto.target_post_id.flatMap { fetchPost(remoteId: $0, context: context)?.id ?? $0 }
        let localActorId = dto.actor.map { fetchUser(remoteId: $0.id, context: context)?.id ?? $0.id } ?? dto.actor_id

        if let existing = fetchNotification(remoteId: serverId, context: context) {
            existing.isRead = dto.is_read
            existing.content = dto.content ?? existing.content
            existing.targetPostId = localPostId ?? existing.targetPostId
            existing.targetCommentId = dto.target_comment_id ?? existing.targetCommentId
            existing.syncStatus = .synced
            return (existing, false)
        }
        let entity = NotificationEntity(
            id: serverId,
            type: NotificationType(rawValue: dto.type) ?? .system,
            actorId: localActorId,
            targetPostId: localPostId,
            targetCommentId: dto.target_comment_id,
            content: dto.content ?? "",
            isRead: dto.is_read,
            createdAt: parsedDate(dto.created_at) ?? .now,
            remoteId: serverId,
            syncStatus: .synced
        )
        context.insert(entity)
        return (entity, true)
    }

    private func fetchNotification(remoteId: String, context: ModelContext) -> NotificationEntity? {
        var descriptor = FetchDescriptor<NotificationEntity>(
            predicate: #Predicate { $0.remoteId == remoteId || $0.id == remoteId }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Send a DM message through the unified API.
    @discardableResult
    func sendMessage(conversationId: String, content: String, mediaIds: [String] = [], attachmentIds: [String] = []) async throws -> KaiXMessageDTO {
        try await api.sendMessage(conversationId, content: content, mediaIds: mediaIds, attachmentIds: attachmentIds)
    }

    /// One synced page of the server feed: the upserted local post ids in
    /// server order, plus the cursor for the next page (nil when the server
    /// has no more).
    struct FeedSyncPage {
        let ids: [String]
        let nextCursor: String?
    }

    /// Upsert one page of the server feed into SwiftData. Pass `cursor`
    /// from the previous page's `nextCursor` to keep paging — this is the
    /// same cursor protocol the Web client uses, so infinite scroll stays
    /// in lockstep across platforms instead of recycling the local cache.
    @discardableResult
    func syncFeed(
        mode: KaiXAPIClient.FeedMode = .recommend,
        cursor: String? = nil,
        country: String? = nil,
        province: String? = nil,
        city: String? = nil,
        contentTypes: [ContentType]? = nil,
        context: ModelContext
    ) async throws -> FeedSyncPage {
        let response = try await api.feed(
            mode: mode,
            cursor: cursor,
            country: country,
            province: province,
            city: city,
            contentTypes: contentTypes
        )
        // Hydrate authors first so post entities can link by author id.
        var authorIds = Set<String>()
        for post in response.items {
            if let author = post.author { _ = upsertUser(author, context: context); authorIds.insert(author.id) }
            if let inner = post.original_post?.author { _ = upsertUser(inner, context: context); authorIds.insert(inner.id) }
        }
        let ids = response.items.map { upsertPost($0, context: context).id }
        try? context.save()
        return FeedSyncPage(ids: ids, nextCursor: response.next_cursor)
    }

    /// Pull a single post + its comments and mirror into SwiftData.
    func syncPostDetail(_ postId: String, context: ModelContext) async throws {
        async let postTask = api.post(postId)
        async let commentsTask = api.comments(postId: postId)
        let (post, comments) = try await (postTask, commentsTask)
        if let author = post.author { _ = upsertUser(author, context: context) }
        _ = upsertPost(post, context: context)
        for comment in comments {
            if let author = comment.author { _ = upsertUser(author, context: context) }
            _ = upsertComment(comment, context: context)
        }
        try? context.save()
    }

    /// Pull the current user's settings and surface them to callers
    /// (e.g. SettingsViewModel) for display.
    func loadSettings() async throws -> KaiXSettingsDTO {
        try await api.settings()
    }

    // MARK: - upsert helpers

    @discardableResult
    func upsertUser(_ dto: KaiXUserDTO, context: ModelContext) -> UserEntity {
        let serverId = dto.id
        if let existing = fetchUser(remoteId: serverId, context: context) {
            existing.username = dto.handle
            existing.displayName = dto.display_name
            existing.email = dto.email ?? existing.email
            existing.bio = dto.bio ?? existing.bio
            existing.location = dto.location ?? existing.location
            existing.avatarSymbol = dto.avatar_symbol ?? existing.avatarSymbol
            existing.avatarColorName = dto.avatar_color ?? existing.avatarColorName
            existing.avatarURL = dto.avatar_url ?? existing.avatarURL
            existing.coverURL = dto.cover_url ?? existing.coverURL
            existing.isVerified = dto.is_verified ?? existing.isVerified
            existing.followerCount = dto.follower_count ?? existing.followerCount
            existing.followingCount = dto.following_count ?? existing.followingCount
            existing.updatedAt = date(dto.updated_at ?? dto.created_at)
            // Only refresh joinDate when the server actually carries
            // it. Older code used the `date()` helper here, which
            // returns `.now` on nil and would silently rewrite every
            // existing user's join date to today whenever the server
            // omitted the field.
            if let joined = parsedDate(dto.joined_at) {
                existing.joinDate = joined
            }
            // Region fields (phase 1). Only overwrite when the server
            // actually carries a value so a partial response (e.g. an
            // older endpoint that didn't surface region yet) can't
            // wipe out the user's selection.
            if let v = dto.country  { existing.country  = v }
            if let v = dto.province { existing.province = v }
            if let v = dto.city     { existing.city     = v }
            if let v = dto.current_region_code { existing.currentRegionCode = v }
            if let v = dto.recent_region_codes { existing.recentRegionCodes = v }
            if let v = dto.membership_tier { existing.membershipLevel = v }
            if let v = dto.total_heat { existing.totalHeat = v }
            if let v = dto.creator_badge { existing.creatorBadge = v }
            if let v = dto.is_merchant { existing.isMerchant = v }
            if let v = dto.merchant_verified { existing.merchantVerified = v }
            if let v = dto.profile_view_count { existing.profileViewCount = v }
            if let v = dto.is_verified_member { existing.isVerifiedMember = v }
            if let v = dto.membership_status { existing.membershipStatus = v }
            if let v = dto.membership_plan_key { existing.membershipPlanKey = v }
            if let v = dto.verified_member_until { existing.verifiedMemberUntil = parsedDate(v) }
            if let v = dto.app_language { existing.appLanguage = v }
            if let v = dto.content_language_preference { existing.contentLanguagePreference = v }
            if let v = dto.preferred_content_languages { existing.preferredContentLanguagesRaw = v }
            existing.remoteId = serverId
            existing.syncStatus = .synced
            return existing
        }
        // For brand-new entities, prefer joined_at, then created_at,
        // and only as a last resort fall back to now.
        let joinDate = parsedDate(dto.joined_at) ?? parsedDate(dto.created_at) ?? .now
        let entity = UserEntity(
            id: serverId,
            username: dto.handle,
            displayName: dto.display_name,
            email: dto.email ?? "",
            avatarURL: dto.avatar_url ?? "",
            coverURL: dto.cover_url ?? "",
            bio: dto.bio ?? "",
            location: dto.location ?? "",
            joinDate: joinDate,
            isVerified: dto.is_verified ?? false,
            role: .member,
            followerCount: dto.follower_count ?? 0,
            followingCount: dto.following_count ?? 0,
            createdAt: date(dto.created_at),
            updatedAt: date(dto.updated_at),
            passwordHash: "",
            avatarSymbol: dto.avatar_symbol ?? "person.fill",
            avatarColorName: dto.avatar_color ?? "indigo",
            remoteId: serverId,
            syncStatus: .synced,
            country: dto.country ?? "",
            province: dto.province ?? "",
            city: dto.city ?? "",
            currentRegionCode: dto.current_region_code ?? "",
            recentRegionCodesRaw: (dto.recent_region_codes ?? []).joined(separator: "|"),
            membershipLevel: dto.membership_tier ?? "free",
            totalHeat: dto.total_heat ?? 0,
            creatorBadge: dto.creator_badge ?? "",
            isMerchant: dto.is_merchant ?? false,
            merchantVerified: dto.merchant_verified ?? false,
            profileViewCount: dto.profile_view_count ?? 0,
            isVerifiedMember: dto.is_verified_member ?? false,
            verifiedMemberUntil: parsedDate(dto.verified_member_until),
            membershipStatus: dto.membership_status ?? "inactive",
            membershipPlanKey: dto.membership_plan_key ?? "",
            appLanguage: dto.app_language ?? "",
            contentLanguagePreference: dto.content_language_preference ?? "",
            preferredContentLanguagesRaw: dto.preferred_content_languages ?? ""
        )
        context.insert(entity)
        return entity
    }

    @discardableResult
    func upsertPost(_ dto: KaiXPostDTO, context: ModelContext) -> PostEntity {
        let serverId = dto.id
        if let existing = fetchPost(remoteId: serverId, context: context) {
            existing.authorId = dto.author_id
            existing.content = dto.content
            existing.updatedAt = date(dto.updated_at)
            existing.commentCount = dto.comment_count
            existing.repostCount = dto.repost_count
            existing.likeCount = dto.like_count
            existing.bookmarkCount = dto.bookmark_count
            existing.viewCount = dto.view_count
            existing.heatScore = dto.heat_score
            existing.isLikedByCurrentUser = dto.liked
            existing.isBookmarkedByCurrentUser = dto.bookmarked
            existing.isRepostedByCurrentUser = dto.reposted
            existing.hashtags = dto.tags
            existing.repostOfPostId = dto.repost_of_id
            existing.remoteId = serverId
            existing.syncStatus = .synced
            if let v = dto.country     { existing.country = v }
            if let v = dto.province    { existing.province = v }
            if let v = dto.city        { existing.city = v }
            if let v = dto.region_code { existing.regionCode = v }
            if let v = dto.content_type, let ct = ContentType(rawValue: v) { existing.contentType = ct }
            if let v = dto.attributes  { existing.attributesRaw = Self.encodeAttributes(v) }
            if let v = dto.status, let status = PostStatus(rawValue: v) { existing.statusRaw = status.rawValue }
            if let v = dto.report_count { existing.reportCount = v }
            if let v = dto.is_boosted { existing.isBoosted = v }
            if let v = dto.boost_weight { existing.boostWeight = v }
            if let v = dto.boosted_until { existing.boostedUntil = parsedDate(v) }
            if let v = dto.language { existing.language = v }
            if let v = dto.is_seed_content { existing.isSeedContent = v }
            if let v = dto.seed_author_type { existing.seedAuthorType = v }
            syncMedia(dto.media, postId: serverId, context: context)
            if let original = dto.original_post {
                syncMedia(original.media, postId: original.id, context: context)
            }
            return existing
        }
        let entity = PostEntity(
            id: serverId,
            authorId: dto.author_id,
            content: dto.content,
            createdAt: date(dto.created_at),
            updatedAt: date(dto.updated_at),
            commentCount: dto.comment_count,
            repostCount: dto.repost_count,
            likeCount: dto.like_count,
            bookmarkCount: dto.bookmark_count,
            viewCount: dto.view_count,
            heatScore: dto.heat_score,
            isLikedByCurrentUser: dto.liked,
            isBookmarkedByCurrentUser: dto.bookmarked,
            isRepostedByCurrentUser: dto.reposted,
            status: dto.status.flatMap(PostStatus.init(rawValue:)) ?? .published,
            hashtags: dto.tags,
            repostOfPostId: dto.repost_of_id,
            remoteId: serverId,
            syncStatus: .synced,
            country: dto.country ?? "",
            province: dto.province ?? "",
            city: dto.city ?? "",
            regionCode: dto.region_code ?? "",
            contentType: dto.content_type.flatMap(ContentType.init(rawValue:)) ?? .dynamic,
            attributesRaw: dto.attributes.map(Self.encodeAttributes) ?? "",
            reportCount: dto.report_count ?? 0,
            isBoosted: dto.is_boosted ?? false,
            boostWeight: dto.boost_weight ?? 0,
            boostedUntil: dto.boosted_until.flatMap { parsedDate($0) },
            language: dto.language ?? "",
            isSeedContent: dto.is_seed_content ?? false,
            seedAuthorType: dto.seed_author_type ?? ""
        )
        context.insert(entity)
        syncMedia(dto.media, postId: serverId, context: context)
        if let original = dto.original_post {
            syncMedia(original.media, postId: original.id, context: context)
        }
        return entity
    }

    private func syncMedia(_ items: [KaiXMediaDTO], postId: String, context: ModelContext) {
        let descriptor = FetchDescriptor<MediaEntity>(
            predicate: #Predicate { $0.postId == postId }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let incomingIds = Set(items.map(\.id))

        for stale in existing where stale.remoteId != nil && !incomingIds.contains(stale.remoteId ?? stale.id) {
            context.delete(stale)
        }

        for dto in items {
            let remoteId = dto.remote_id ?? dto.remoteId ?? dto.id
            let entity = existing.first { $0.remoteId == remoteId || $0.id == dto.id }
            let mediaType: MediaType = dto.normalizedType == "video" ? .video : .image
            let preview = mediaType == .video ? dto.posterURLString : dto.thumbnailURLString
            if let entity {
                entity.postId = postId
                entity.type = mediaType
                entity.remoteURL = dto.sourceURLString
                entity.thumbnailURL = preview
                entity.width = Double(dto.width ?? 0)
                entity.height = Double(dto.height ?? 0)
                entity.duration = dto.durationSeconds ?? dto.duration_seconds ?? dto.duration ?? 0
                entity.uploadState = .uploaded
                entity.uploadProgress = 1
                entity.updatedAt = .now
                entity.remoteId = remoteId
                entity.syncStatus = .synced
                entity.deletedAt = nil
            } else {
                context.insert(MediaEntity(
                    id: dto.id,
                    postId: postId,
                    type: mediaType,
                    remoteURL: dto.sourceURLString,
                    thumbnailURL: preview,
                    width: Double(dto.width ?? 0),
                    height: Double(dto.height ?? 0),
                    duration: dto.durationSeconds ?? dto.duration_seconds ?? dto.duration ?? 0,
                    uploadState: .uploaded,
                    uploadProgress: 1,
                    createdAt: parsedDate(dto.created_at) ?? .now,
                    updatedAt: .now,
                    remoteId: remoteId,
                    syncStatus: .synced
                ))
            }
        }
    }

    /// Re-encode the typed DTO attributes back to a JSON string so
    /// they can live on the SwiftData column the same way the server
    /// stores them. Stable key order keeps diff/debug noise low.
    fileprivate static func encodeAttributes(_ map: [String: KaiXAttributeValue]) -> String {
        var plain: [String: Any] = [:]
        for (k, v) in map {
            switch v.kind {
            case .string(let s): plain[k] = s
            case .double(let n): plain[k] = n
            case .bool(let b):   plain[k] = b
            case .null:          continue
            }
        }
        guard !plain.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: plain, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    @discardableResult
    func upsertComment(_ dto: KaiXCommentDTO, context: ModelContext) -> CommentEntity {
        let serverId = dto.id
        if let existing = fetchComment(remoteId: serverId, context: context) {
            existing.content = dto.content
            existing.likeCount = dto.like_count
            existing.isLikedByCurrentUser = dto.liked
            existing.updatedAt = date(dto.updated_at)
            existing.remoteId = serverId
            existing.syncStatus = .synced
            return existing
        }
        let entity = CommentEntity(
            id: serverId,
            postId: dto.post_id,
            authorId: dto.author_id,
            content: dto.content,
            parentCommentId: dto.parent_comment_id,
            likeCount: dto.like_count,
            isLikedByCurrentUser: dto.liked,
            createdAt: date(dto.created_at),
            updatedAt: date(dto.updated_at),
            remoteId: serverId,
            syncStatus: .synced
        )
        context.insert(entity)
        return entity
    }

    // MARK: - fetch helpers

    private func fetchUser(remoteId: String, context: ModelContext) -> UserEntity? {
        let descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.remoteId == remoteId || $0.id == remoteId })
        return try? context.fetch(descriptor).first
    }

    private func fetchPost(remoteId: String, context: ModelContext) -> PostEntity? {
        let descriptor = FetchDescriptor<PostEntity>(predicate: #Predicate { $0.remoteId == remoteId || $0.id == remoteId })
        return try? context.fetch(descriptor).first
    }

    private func fetchComment(remoteId: String, context: ModelContext) -> CommentEntity? {
        let descriptor = FetchDescriptor<CommentEntity>(predicate: #Predicate { $0.remoteId == remoteId || $0.id == remoteId })
        return try? context.fetch(descriptor).first
    }
}
