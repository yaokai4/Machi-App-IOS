import Foundation
import Combine
import SwiftData


@MainActor
final class PostStore: ObservableObject {
    @Published private(set) var postsById: [String: PostEntity] = [:]
    @Published private(set) var feedIds: [String] = []
    @Published private(set) var followingFeedIds: [String] = []
    @Published private(set) var hotIds: [String] = []
    @Published private(set) var searchResultIds: [String] = []
    @Published private(set) var profilePostIds: [String: [String]] = [:]
    @Published private(set) var likedPostIds: [String] = []
    @Published private(set) var bookmarkedPostIds: [String] = []
    @Published private(set) var repostedPostIds: [String] = []
    @Published private(set) var mediaPostIds: [String] = []
    @Published private(set) var draftIds: [String] = []

    private var pendingActions = Set<String>()

    /// Wipe every cached post + derived id list on logout / account switch so
    /// the next account's feeds, likes, bookmarks, drafts and per-user liked
    /// state can never be seeded from the previous account's cache.
    func reset() {
        postsById = [:]
        feedIds = []
        followingFeedIds = []
        hotIds = []
        searchResultIds = []
        profilePostIds = [:]
        likedPostIds = []
        bookmarkedPostIds = []
        repostedPostIds = []
        mediaPostIds = []
        draftIds = []
        pendingActions = []
    }

    func register(_ post: PostEntity) {
        postsById[post.id] = post
    }

    func register(_ posts: [PostEntity]) {
        guard !posts.isEmpty else { return }
        // Mutate in place instead of snapshotting the whole dictionary — the
        // old `var updated = postsById` copied the growing cache on every
        // pagination page (O(N²) over a long scroll). Subscript writes on the
        // @Published dict coalesce into a single view update per run loop.
        for post in posts {
            postsById[post.id] = post
        }
    }

    func post(id: String) -> PostEntity? {
        postsById[id]
    }

    func posts(for ids: [String]) -> [PostEntity] {
        ids.compactMap { postsById[$0] }
    }

    func setFeed(_ posts: [PostEntity], append: Bool = false) {
        register(posts)
        let ids = posts.map(\.id)
        feedIds = append ? deduplicated(feedIds + ids) : ids
    }

    func setFollowingFeed(_ posts: [PostEntity], append: Bool = false) {
        register(posts)
        let ids = posts.map(\.id)
        followingFeedIds = append ? deduplicated(followingFeedIds + ids) : ids
    }

    func setHot(_ posts: [PostEntity]) {
        register(posts)
        hotIds = posts.map(\.id)
    }

    func setSearchResults(_ posts: [PostEntity]) {
        register(posts)
        searchResultIds = posts.map(\.id)
    }

    func setProfilePosts(_ posts: [PostEntity], userId: String) {
        register(posts)
        profilePostIds[userId] = posts.map(\.id)
    }

    func setMediaPosts(_ posts: [PostEntity]) {
        register(posts)
        mediaPostIds = posts.map(\.id)
    }

    func setDrafts(_ posts: [PostEntity]) {
        register(posts)
        draftIds = posts.map(\.id)
    }

    func insertPublishedPost(_ post: PostEntity, currentUserId: String) {
        insertPostLocally(post, currentUserId: currentUserId)
        refreshDerivedIds()
    }

    func refreshDerivedIds() {
        // Single pass over the cache instead of four filter+sort sweeps —
        // this runs on every like/bookmark/repost tap, so keep it lean.
        var liked: [PostEntity] = []
        var bookmarked: [PostEntity] = []
        var reposted: [PostEntity] = []
        var drafts: [PostEntity] = []
        for post in postsById.values {
            if post.isLikedByCurrentUser { liked.append(post) }
            if post.isBookmarkedByCurrentUser { bookmarked.append(post) }
            if post.isRepostedByCurrentUser { reposted.append(post) }
            if post.status == .draft { drafts.append(post) }
        }
        let byRecency: (PostEntity, PostEntity) -> Bool = { $0.updatedAt > $1.updatedAt }
        likedPostIds = liked.sorted(by: byRecency).map(\.id)
        bookmarkedPostIds = bookmarked.sorted(by: byRecency).map(\.id)
        repostedPostIds = reposted.sorted(by: byRecency).map(\.id)
        draftIds = drafts.sorted(by: byRecency).map(\.id)
    }

    func likePost(context: ModelContext, postId: String, currentUser: UserEntity) async throws {
        try await setLike(context: context, postId: postId, currentUserId: currentUser.id, isLiked: true)
    }

    func unlikePost(context: ModelContext, postId: String, currentUser: UserEntity) async throws {
        try await setLike(context: context, postId: postId, currentUserId: currentUser.id, isLiked: false)
    }

    func toggleLike(context: ModelContext, postId: String, currentUser: UserEntity) async throws {
        guard let post = postsById[postId] else { throw RepositoryError.notFound }
        try await setLike(context: context, postId: postId, currentUserId: currentUser.id, isLiked: !post.isLikedByCurrentUser)
    }

    func bookmarkPost(context: ModelContext, postId: String, currentUser: UserEntity) async throws {
        try await setBookmark(context: context, postId: postId, currentUserId: currentUser.id, isBookmarked: true)
    }

    func unbookmarkPost(context: ModelContext, postId: String, currentUser: UserEntity) async throws {
        try await setBookmark(context: context, postId: postId, currentUserId: currentUser.id, isBookmarked: false)
    }

    func toggleBookmark(context: ModelContext, postId: String, currentUser: UserEntity) async throws {
        guard let post = postsById[postId] else { throw RepositoryError.notFound }
        try await setBookmark(context: context, postId: postId, currentUserId: currentUser.id, isBookmarked: !post.isBookmarkedByCurrentUser)
    }

    @discardableResult
    func repostPost(context: ModelContext, postId: String, currentUser: UserEntity) async throws -> PostEntity? {
        try await setRepost(context: context, postId: postId, currentUserId: currentUser.id, isReposted: true)
    }

    func undoRepost(context: ModelContext, postId: String, currentUser: UserEntity) async throws {
        _ = try await setRepost(context: context, postId: postId, currentUserId: currentUser.id, isReposted: false)
    }

    @discardableResult
    func toggleRepost(context: ModelContext, postId: String, currentUser: UserEntity) async throws -> PostEntity? {
        guard let post = postsById[postId] else { throw RepositoryError.notFound }
        return try await setRepost(context: context, postId: postId, currentUserId: currentUser.id, isReposted: !post.isRepostedByCurrentUser)
    }

    func quoteRepost(context: ModelContext, postId: String, currentUser: UserEntity, content: String) async throws -> PostEntity {
        let key = "quoteRepost:\(postId)"
        guard beginAction(key) else { throw RepositoryError.duplicate }
        defer { endAction(key) }

        guard let post = postsById[postId] else { throw RepositoryError.notFound }
        let oldCount = post.repostCount
        post.repostCount = max(0, oldCount + 1)
        HeatScoreService.shared.refresh(post)

        do {
            let quote = try await PostRepository(context: context).quoteRepost(
                post: post,
                currentUserId: currentUser.id,
                content: content,
                countAlreadyUpdated: true
            )
            register(quote)
            insertPostLocally(quote, currentUserId: currentUser.id)
            return quote
        } catch {
            post.repostCount = oldCount
            HeatScoreService.shared.refresh(post)
            throw error
        }
    }

    func updateCommentCount(postId: String, delta: Int) {
        guard let post = postsById[postId] else { return }
        post.commentCount = max(0, post.commentCount + delta)
        HeatScoreService.shared.refresh(post)
    }

    func addComment(
        context: ModelContext,
        postId: String,
        currentUser: UserEntity,
        content: String,
        parentCommentId: String?
    ) async throws -> CommentEntity {
        guard let post = postsById[postId] else { throw RepositoryError.notFound }
        return try await PostRepository(context: context).addComment(
            post: post,
            authorId: currentUser.id,
            content: content,
            parentCommentId: parentCommentId,
            commentCountAlreadyUpdated: true
        )
    }

    func deleteComment(context: ModelContext, comment: CommentEntity, removedCount: Int? = nil) async throws {
        let parentId = comment.id
        // In production the comment thread lives only in memory — the server is
        // the source of truth and comments are never inserted into SwiftData —
        // so this local relation fetch returns 0 and would under-count the
        // delete by every reply (post.commentCount drops by 1 while the list
        // loses parent + N replies). Prefer the caller's authoritative removed
        // count (parent + the replies it actually pruned from the loaded
        // thread, matching CommentStore's own book-keeping); fall back to the
        // local relation only for callers that don't track the in-memory thread.
        let localDescendants = (try? context.fetch(FetchDescriptor<CommentEntity>(
            predicate: #Predicate { $0.parentCommentId == parentId }
        )))?.count ?? 0
        let delta = -(removedCount ?? (1 + localDescendants))
        updateCommentCount(postId: comment.postId, delta: delta)
        do {
            try await PostRepository(context: context).deleteComment(comment: comment, commentCountAlreadyUpdated: true)
        } catch {
            updateCommentCount(postId: comment.postId, delta: -delta)
            throw error
        }
    }

    func updatePost(context: ModelContext, postId: String, content: String) async throws {
        let key = "updatePost:\(postId)"
        guard beginAction(key) else { return }
        defer { endAction(key) }

        guard let post = postsById[postId] else { throw RepositoryError.notFound }
        let oldContent = post.content
        let oldHashtags = post.hashtags
        let oldUpdatedAt = post.updatedAt
        post.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        post.hashtags = post.content.extractedHashtags
        post.updatedAt = .now

        do {
            try await PostRepository(context: context).updatePost(post: post, content: content)
            register(post)
        } catch {
            post.content = oldContent
            post.hashtags = oldHashtags
            post.updatedAt = oldUpdatedAt
            throw error
        }
    }

    func deletePost(context: ModelContext, postId: String) async throws {
        let key = "deletePost:\(postId)"
        guard beginAction(key) else { return }
        defer { endAction(key) }

        guard let post = postsById[postId] else { throw RepositoryError.notFound }
        let previousPosts = postsById
        let previousFeedIds = feedIds
        let previousFollowingFeedIds = followingFeedIds
        let previousHotIds = hotIds
        let previousSearchResultIds = searchResultIds
        let previousProfilePostIds = profilePostIds
        let previousLikedPostIds = likedPostIds
        let previousBookmarkedPostIds = bookmarkedPostIds
        let previousRepostedPostIds = repostedPostIds
        let previousMediaPostIds = mediaPostIds
        let previousDraftIds = draftIds

        let localRepostIds = postsById.values
            .filter { $0.repostOfPostId == postId }
            .map(\.id)
        ([postId] + localRepostIds).forEach(removePostLocally)

        do {
            try await PostRepository(context: context).deletePost(post: post)
            // 广播删除:feed/城市频道列表以 `?? post` 回退渲染,PostStore 忘掉该
            // 实体后 HomeViewModel.posts 仍强引用它 → 详情页删除会留可点击幽灵卡。
            // 让各列表从自己的 posts/loadedIds 里同步剔除(与房间/活动删除同模式)。
            NotificationCenter.default.post(name: .kaiXPostRemoved, object: nil,
                                            userInfo: ["ids": [postId] + localRepostIds])
        } catch {
            postsById = previousPosts
            feedIds = previousFeedIds
            followingFeedIds = previousFollowingFeedIds
            hotIds = previousHotIds
            searchResultIds = previousSearchResultIds
            profilePostIds = previousProfilePostIds
            likedPostIds = previousLikedPostIds
            bookmarkedPostIds = previousBookmarkedPostIds
            repostedPostIds = previousRepostedPostIds
            mediaPostIds = previousMediaPostIds
            draftIds = previousDraftIds
            throw error
        }
    }

    private func setLike(context: ModelContext, postId: String, currentUserId: String, isLiked: Bool) async throws {
        let key = "like:\(postId)"
        guard beginAction(key) else { return }
        defer { endAction(key) }

        guard let post = postsById[postId] else { throw RepositoryError.notFound }
        let oldIsLiked = post.isLikedByCurrentUser
        let oldCount = post.likeCount

        guard oldIsLiked != isLiked else { return }
        post.isLikedByCurrentUser = isLiked
        post.likeCount = max(0, oldCount + (isLiked ? 1 : -1))
        HeatScoreService.shared.refresh(post)
        refreshDerivedIds()

        do {
            try await PostRepository(context: context).setLike(
                post: post,
                isLiked: isLiked,
                currentUserId: currentUserId,
                countAlreadyUpdated: true
            )
        } catch {
            post.isLikedByCurrentUser = oldIsLiked
            post.likeCount = oldCount
            HeatScoreService.shared.refresh(post)
            refreshDerivedIds()
            throw error
        }
    }

    private func setBookmark(context: ModelContext, postId: String, currentUserId: String, isBookmarked: Bool) async throws {
        let key = "bookmark:\(postId)"
        guard beginAction(key) else { return }
        defer { endAction(key) }

        guard let post = postsById[postId] else { throw RepositoryError.notFound }
        let oldIsBookmarked = post.isBookmarkedByCurrentUser
        let oldCount = post.bookmarkCount

        guard oldIsBookmarked != isBookmarked else { return }
        post.isBookmarkedByCurrentUser = isBookmarked
        post.bookmarkCount = max(0, oldCount + (isBookmarked ? 1 : -1))
        HeatScoreService.shared.refresh(post)
        refreshDerivedIds()

        do {
            try await PostRepository(context: context).setBookmark(
                post: post,
                isBookmarked: isBookmarked,
                currentUserId: currentUserId,
                countAlreadyUpdated: true
            )
        } catch {
            post.isBookmarkedByCurrentUser = oldIsBookmarked
            post.bookmarkCount = oldCount
            HeatScoreService.shared.refresh(post)
            refreshDerivedIds()
            throw error
        }
    }

    private func setRepost(context: ModelContext, postId: String, currentUserId: String, isReposted: Bool) async throws -> PostEntity? {
        let key = "repost:\(postId)"
        guard beginAction(key) else { return nil }
        defer { endAction(key) }

        guard let post = postsById[postId] else { throw RepositoryError.notFound }
        let oldIsReposted = post.isRepostedByCurrentUser
        let oldCount = post.repostCount
        let previousPosts = postsById
        let previousFeedIds = feedIds
        let previousFollowingFeedIds = followingFeedIds
        let previousHotIds = hotIds
        let previousSearchResultIds = searchResultIds
        let previousProfilePostIds = profilePostIds
        let previousRepostedPostIds = repostedPostIds

        guard oldIsReposted != isReposted else { return ordinaryRepost(for: postId, currentUserId: currentUserId) }
        post.isRepostedByCurrentUser = isReposted
        post.repostCount = max(0, oldCount + (isReposted ? 1 : -1))
        HeatScoreService.shared.refresh(post)
        refreshDerivedIds()

        do {
            let repost = try await PostRepository(context: context).setRepost(
                post: post,
                isReposted: isReposted,
                currentUserId: currentUserId,
                countAlreadyUpdated: true
            )
            if let repost {
                register(repost)
                insertPostLocally(repost, currentUserId: currentUserId)
            } else if !isReposted {
                removeOrdinaryRepostsLocally(originalPostId: postId, currentUserId: currentUserId)
            }
            return repost
        } catch {
            post.isRepostedByCurrentUser = oldIsReposted
            post.repostCount = oldCount
            postsById = previousPosts
            feedIds = previousFeedIds
            followingFeedIds = previousFollowingFeedIds
            hotIds = previousHotIds
            searchResultIds = previousSearchResultIds
            profilePostIds = previousProfilePostIds
            repostedPostIds = previousRepostedPostIds
            HeatScoreService.shared.refresh(post)
            refreshDerivedIds()
            throw error
        }
    }

    private func deduplicated(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func removePostLocally(_ postId: String) {
        postsById[postId] = nil
        feedIds.removeAll { $0 == postId }
        followingFeedIds.removeAll { $0 == postId }
        hotIds.removeAll { $0 == postId }
        searchResultIds.removeAll { $0 == postId }
        likedPostIds.removeAll { $0 == postId }
        bookmarkedPostIds.removeAll { $0 == postId }
        repostedPostIds.removeAll { $0 == postId }
        mediaPostIds.removeAll { $0 == postId }
        draftIds.removeAll { $0 == postId }
        for key in profilePostIds.keys {
            profilePostIds[key]?.removeAll { $0 == postId }
        }
    }

    private func insertPostLocally(_ post: PostEntity, currentUserId: String) {
        register(post)
        feedIds = deduplicated([post.id] + feedIds)
        if post.authorId == currentUserId {
            followingFeedIds = deduplicated([post.id] + followingFeedIds)
            profilePostIds[currentUserId] = deduplicated([post.id] + (profilePostIds[currentUserId] ?? []))
        }
        if post.repostOfPostId != nil {
            repostedPostIds = deduplicated([post.id] + repostedPostIds)
        }
    }

    private func ordinaryRepost(for originalPostId: String, currentUserId: String) -> PostEntity? {
        postsById.values.first { post in
            post.authorId == currentUserId
            && post.repostOfPostId == originalPostId
            && post.previewText.isEmpty
        }
    }

    private func removeOrdinaryRepostsLocally(originalPostId: String, currentUserId: String) {
        let ids = postsById.values
            .filter {
                $0.authorId == currentUserId
                && $0.repostOfPostId == originalPostId
                && $0.previewText.isEmpty
            }
            .map(\.id)
        ids.forEach(removePostLocally)
    }

    private func beginAction(_ key: String) -> Bool {
        pendingActions.insert(key).inserted
    }

    private func endAction(_ key: String) {
        pendingActions.remove(key)
    }
}
