import Foundation
import Combine
import SwiftData

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var mode: TimelineMode = .recommend
    @Published var posts: [PostEntity] = []
    @Published var authors: [String: UserEntity] = [:]
    @Published var recommendedUsers: [UserEntity] = []
    @Published var mediaByPostId: [String: [MediaEntity]] = [:]
    @Published var state: ScreenState = .idle
    @Published var isLoadingMore = false
    @Published var canLoadMore = true

    private var currentPage = 0

    func loadInitial(context: ModelContext, currentUser: UserEntity, postStore: PostStore, clearExisting: Bool = false) async {
        let previousPage = currentPage
        let previousCanLoadMore = canLoadMore
        currentPage = 0
        canLoadMore = true
        if clearExisting {
            posts = []
            authors = [:]
            mediaByPostId = [:]
        }
        let didLoad = await loadPage(context: context, currentUser: currentUser, postStore: postStore, reset: true)
        if !didLoad, !clearExisting, !posts.isEmpty {
            currentPage = previousPage
            canLoadMore = previousCanLoadMore
        }
    }

    func loadMoreIfNeeded(context: ModelContext, currentUser: UserEntity, post: PostEntity?, postStore: PostStore) async {
        guard canLoadMore, !isLoadingMore else { return }
        guard post == nil || post?.id == posts.last?.id else { return }
        _ = await loadPage(context: context, currentUser: currentUser, postStore: postStore, reset: false)
    }

    func refresh(context: ModelContext, currentUser: UserEntity, postStore: PostStore) async {
        await loadInitial(context: context, currentUser: currentUser, postStore: postStore)
    }

    func toggleLike(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore) async {
        do {
            postStore.register(post)
            // PostStore.toggleLike handles both the local SwiftData mutation
            // and the unified-backend write-through (when token is present),
            // so callers don't need to duplicate that here.
            try await postStore.toggleLike(context: context, postId: post.id, currentUser: currentUser)
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func toggleBookmark(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore) async {
        do {
            postStore.register(post)
            try await postStore.toggleBookmark(context: context, postId: post.id, currentUser: currentUser)
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func repost(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore) async {
        do {
            postStore.register(post)
            try await postStore.toggleRepost(context: context, postId: post.id, currentUser: currentUser)
            authors[currentUser.id] = currentUser
            posts = postStore.posts(for: postStore.feedIds)
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func quoteRepost(context: ModelContext, post: PostEntity, currentUser: UserEntity, content: String, postStore: PostStore) async {
        do {
            postStore.register(post)
            _ = try await postStore.quoteRepost(context: context, postId: post.id, currentUser: currentUser, content: content)
            authors[currentUser.id] = currentUser
            posts = postStore.posts(for: postStore.feedIds)
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func follow(context: ModelContext, currentUser: UserEntity, target: UserEntity, postStore: PostStore, userStore: UserStore? = nil) async {
        do {
            let isFollowing = try await UserRepository(context: context).toggleFollow(currentUser: currentUser, targetUser: target)
            userStore?.register([currentUser, target])
            userStore?.setFollowing(isFollowing, userId: target.id)
            userStore?.updateCounts(userId: currentUser.id, followers: currentUser.followerCount, following: currentUser.followingCount)
            userStore?.updateCounts(userId: target.id, followers: target.followerCount, following: target.followingCount)
            await loadInitial(context: context, currentUser: currentUser, postStore: postStore)
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    private func loadPage(context: ModelContext, currentUser: UserEntity, postStore: PostStore, reset: Bool) async -> Bool {
        if reset {
            if posts.isEmpty {
                state = .loading
            }
        } else {
            isLoadingMore = true
        }
        defer { isLoadingMore = false }

        do {
            // When the unified backend is reachable (token present), pull the
            // freshest feed from the API and upsert into SwiftData so iOS and
            // Web stay in lockstep. The existing local query then reads from
            // the same SwiftData store transparently.
            if reset, KaiXBackend.token != nil {
                await syncFromRemote(context: context, postStore: postStore)
            }

            let repository = PostRepository(context: context)
            let page = try await repository.fetchPage(mode: mode, currentUserId: currentUser.id, page: currentPage, pageSize: KaiXConfig.pageSize)
            if reset {
                posts = page
            } else {
                posts.append(contentsOf: page)
            }
            postStore.setFeed(posts, append: false)
            currentPage += 1
            canLoadMore = page.count == KaiXConfig.pageSize
            try await hydrate(
                context: context,
                repository: repository,
                currentUser: currentUser,
                postStore: postStore,
                reset: reset,
                refreshRecommendations: reset || recommendedUsers.isEmpty
            )
            state = posts.isEmpty ? .empty : .loaded
            return true
        } catch {
            if posts.isEmpty {
                state = .error(error.kaixUserMessage)
            } else {
                state = .loaded
            }
            return false
        }
    }

    /// Pull the latest feed from the unified KaiX backend and upsert
    /// into SwiftData. Best-effort: a failure just falls back to the
    /// local cache, so the App stays usable offline.
    private func syncFromRemote(context: ModelContext, postStore: PostStore) async {
        do {
            let apiMode: KaiXAPIClient.FeedMode
            switch mode {
            case .recommend: apiMode = .recommend
            case .local:     apiMode = .local
            case .following: apiMode = .following
            case .hot:       apiMode = .hot
            }
            // All primary feeds stay inside the account's selected
            // country. The `.local` tab narrows that further to the
            // current city.
            let region = RegionStore.shared.current
            let cityScoped = mode == .local
            _ = try await RemoteSyncService.shared.syncFeed(
                mode: apiMode,
                country: region?.countryCode,
                province: cityScoped ? (region?.provinceCode.isEmpty == true ? nil : region?.provinceCode) : nil,
                city: cityScoped ? region?.cityCode : nil,
                context: context
            )
        } catch {
            // Silent — the local fallback below still produces a usable feed.
        }
    }

    private func hydrate(
        context: ModelContext,
        repository: PostRepository,
        currentUser: UserEntity,
        postStore: PostStore,
        reset: Bool,
        refreshRecommendations: Bool
    ) async throws {
        let originalIds = Set(posts.compactMap(\.repostOfPostId))
        let cachedOriginalPosts = originalIds.compactMap { postStore.post(id: $0) }
        let cachedOriginalIds = Set(cachedOriginalPosts.map(\.id))
        let missingOriginalIds = originalIds.subtracting(cachedOriginalIds)
        let fetchedOriginalPosts: [PostEntity]
        if missingOriginalIds.isEmpty {
            fetchedOriginalPosts = []
        } else {
            fetchedOriginalPosts = try await repository.fetchPosts(ids: missingOriginalIds, currentUserId: currentUser.id)
            postStore.register(fetchedOriginalPosts)
        }
        let originalPosts = cachedOriginalPosts + fetchedOriginalPosts
        let userRepository = UserRepository(context: context)
        let hydratedPosts = posts + originalPosts
        let authorIds = Set(hydratedPosts.map(\.authorId))
        let missingAuthorIds = authorIds.subtracting(Set(authors.keys))
        let authorIdsToFetch = reset ? authorIds : missingAuthorIds
        if !authorIdsToFetch.isEmpty {
            let postAuthors = try await userRepository.fetchUsers(ids: authorIdsToFetch)
            authors.merge(Dictionary(uniqueKeysWithValues: postAuthors.map { ($0.id, $0) })) { _, new in new }
        }
        if refreshRecommendations {
            recommendedUsers = try await userRepository.fetchRecommendedUsers(excluding: currentUser.id, limit: 10)
        }
        let postsNeedingMedia: [PostEntity]
        if reset {
            postsNeedingMedia = hydratedPosts
        } else {
            let knownMediaPostIds = Set(mediaByPostId.keys)
            postsNeedingMedia = hydratedPosts.filter { !knownMediaPostIds.contains($0.id) }
        }
        if !postsNeedingMedia.isEmpty {
            var fetchedMedia = try await repository.fetchMedia(for: postsNeedingMedia)
            for post in postsNeedingMedia where fetchedMedia[post.id] == nil {
                fetchedMedia[post.id] = []
            }
            if reset {
                mediaByPostId = fetchedMedia
            } else {
                mediaByPostId.merge(fetchedMedia) { _, new in new }
            }
        } else if reset {
            mediaByPostId = [:]
        }
    }
}
