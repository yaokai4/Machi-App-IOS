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
    // Server-side cursor for the unified-backend feed. Mirrors the Web
    // client's infinite scroll: each "load more" pulls the NEXT remote page
    // into SwiftData instead of endlessly re-reading the local cache.
    private var remoteCursor: String?
    private var remoteHasMore = false
    // Every post id currently in `posts` — appended pages are filtered
    // against this so a shifted local window can never show a duplicate.
    private var loadedIds = Set<String>()

    func loadInitial(context: ModelContext, currentUser: UserEntity, postStore: PostStore, clearExisting: Bool = false) async {
        let previousPage = currentPage
        let previousCanLoadMore = canLoadMore
        let previousCursor = remoteCursor
        let previousRemoteHasMore = remoteHasMore
        let previousLoadedIds = loadedIds
        currentPage = 0
        canLoadMore = true
        remoteCursor = nil
        remoteHasMore = false
        loadedIds = []
        if clearExisting {
            posts = []
            authors = [:]
            mediaByPostId = [:]
        }
        let didLoad = await loadPage(context: context, currentUser: currentUser, postStore: postStore, reset: true)
        if !didLoad, !clearExisting, !posts.isEmpty {
            currentPage = previousPage
            canLoadMore = previousCanLoadMore
            remoteCursor = previousCursor
            remoteHasMore = previousRemoteHasMore
            loadedIds = previousLoadedIds
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
            loadedIds = Set(posts.map(\.id))
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
            loadedIds = Set(posts.map(\.id))
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
            // the same SwiftData store transparently. On reset that's page 1;
            // on "load more" we advance the server cursor so infinite scroll
            // keeps serving NEW content instead of recycling the local cache.
            if KaiXBackend.token != nil {
                if reset {
                    await syncFromRemote(context: context, cursor: nil)
                } else if remoteHasMore {
                    await syncFromRemote(context: context, cursor: remoteCursor)
                }
            }

            let repository = PostRepository(context: context)
            let page = try await repository.fetchPage(mode: mode, currentUserId: currentUser.id, page: currentPage, pageSize: KaiXConfig.pageSize)
            // Belt-and-braces: even if the local window shifted (new posts
            // synced in above us), an id can never appear twice in the list.
            let appended = page.filter { !loadedIds.contains($0.id) }
            posts = balanceOfficialRuns(reset ? page : posts + appended)
            loadedIds = Set(posts.map(\.id))
            postStore.setFeed(posts, append: false)
            currentPage += 1
            canLoadMore = page.count == KaiXConfig.pageSize
                || (KaiXBackend.token != nil && remoteHasMore)
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

    /// Pull one page of the unified KaiX backend feed and upsert into
    /// SwiftData, advancing the server cursor. Best-effort: a failure just
    /// falls back to the local cache, so the App stays usable offline.
    private func syncFromRemote(context: ModelContext, cursor: String?) async {
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
            let page = try await RemoteSyncService.shared.syncFeed(
                mode: apiMode,
                cursor: cursor,
                country: region?.countryCode,
                province: cityScoped ? (region?.provinceCode.isEmpty == true ? nil : region?.provinceCode) : nil,
                city: cityScoped ? region?.cityCode : nil,
                context: context
            )
            remoteCursor = page.nextCursor
            remoteHasMore = page.nextCursor != nil && !page.ids.isEmpty
        } catch {
            // Silent — the local fallback below still produces a usable
            // feed. Keep the previous cursor state so a transient network
            // error doesn't permanently stop remote pagination.
        }
    }

    private func balanceOfficialRuns(_ input: [PostEntity]) -> [PostEntity] {
        var output = input
        var previousKey = ""
        var runCount = 0

        for index in output.indices {
            let key = officialFeedKey(for: output[index])
            if !key.isEmpty && key == previousKey && runCount >= 2 {
                if let swapIndex = output[(index + 1)...].firstIndex(where: { officialFeedKey(for: $0) != key }) {
                    output.swapAt(index, swapIndex)
                }
            }
            let nextKey = officialFeedKey(for: output[index])
            if nextKey.isEmpty {
                previousKey = ""
                runCount = 0
            } else if nextKey == previousKey {
                runCount += 1
            } else {
                previousKey = nextKey
                runCount = 1
            }
        }
        return output
    }

    private func officialFeedKey(for post: PostEntity) -> String {
        guard post.isSeedContent else { return "" }
        switch post.contentType {
        case .question:
            return "assistant"
        case .event, .news, .local_info:
            return post.country == "jp" && post.city == "tokyo" ? "tokyo_editorial" : "japan_life_editorial"
        case .service, .merchant, .coupon:
            return "local_life_editorial"
        case .guide, .housing, .roommate, .job_seek, .job_post, .referral, .warning:
            return "japan_life_editorial"
        default:
            return post.seedAuthorType.isEmpty ? "assistant" : post.seedAuthorType
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
