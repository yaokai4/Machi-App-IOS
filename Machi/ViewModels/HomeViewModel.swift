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
    // client's infinite scroll: each "load more" pulls the next API page
    // instead of re-reading a local database window.
    private var remoteCursor: String?
    private var remoteHasMore = false
    // The page syncFromRemote just pulled, in server order. When present,
    // the visible list follows the server's cursor pagination exactly (the
    // same protocol Web uses) — local offset paging is only the offline
    // fallback. Paging a multi-source local cache by offset is what made
    // the home feed visibly repeat content: other tabs keep inserting
    // rows between windows, so window N+1 could re-serve window N's posts.
    private var pendingRemoteBundle: ServerEntityFactory.PostBundle?
    private var pendingRemoteBundleIsCachedSnapshot = false
    // The server ANSWERED and the page was genuinely empty (e.g. a guest's
    // 关注 tab). Distinct from "sync failed" (bundle nil, flag false): without
    // this marker loadPage fell through to repository.fetchPage, which in
    // remote mode fired a SECOND identical /api/feed request just to learn
    // "empty" again — every empty feed cost two round trips.
    private var pendingRemoteBundleIsEmptyPage = false
    // Every post id currently in `posts` — appended pages are filtered
    // against this so a shifted local window can never show a duplicate.
    private var loadedIds = Set<String>()
    // Re-entrancy guard: HomeTimelineView fires loadInitial from .task plus four
    // onChange handlers (mode/refreshToken/region/language) that can overlap. The
    // method suspends at `await syncFromRemote`, so two interleaved calls used to
    // both reset the cursor/loadedIds and double-increment the page → mixed or
    // duplicated feeds. Serialize: a second call while one is in flight no-ops.
    // Important: a mode switch while a load is in flight must not be dropped.
    // We queue one follow-up pass and always reload the latest selected mode.
    private var isLoadingInitial = false
    private var pendingInitialReload = false
    private var pendingInitialClearExisting = false

    func loadInitial(context: ModelContext, currentUser: UserEntity, postStore: PostStore, clearExisting: Bool = false) async {
        if isLoadingInitial {
            pendingInitialReload = true
            pendingInitialClearExisting = pendingInitialClearExisting || clearExisting
            return
        }
        isLoadingInitial = true
        defer { isLoadingInitial = false }
        var nextClearExisting = clearExisting
        while true {
            pendingInitialReload = false
            let requestedMode = mode
            await loadInitialPass(
                context: context,
                currentUser: currentUser,
                postStore: postStore,
                mode: requestedMode,
                clearExisting: nextClearExisting
            )
            let modeChangedDuringLoad = requestedMode != mode
            nextClearExisting = pendingInitialClearExisting || modeChangedDuringLoad
            pendingInitialClearExisting = false
            guard pendingInitialReload || modeChangedDuringLoad else { break }
        }
    }

    private func loadInitialPass(
        context: ModelContext,
        currentUser: UserEntity,
        postStore: PostStore,
        mode requestedMode: TimelineMode,
        clearExisting: Bool
    ) async {
        let previousPage = currentPage
        let previousCanLoadMore = canLoadMore
        let previousCursor = remoteCursor
        let previousRemoteHasMore = remoteHasMore
        let previousLoadedIds = loadedIds
        currentPage = 0
        canLoadMore = true
        remoteCursor = nil
        remoteHasMore = false
        pendingRemoteBundle = nil
        pendingRemoteBundleIsCachedSnapshot = false
        pendingRemoteBundleIsEmptyPage = false
        loadedIds = []
        if clearExisting {
            posts = []
            authors = [:]
            mediaByPostId = [:]
        }
        let didLoad = await loadPage(context: context, currentUser: currentUser, mode: requestedMode, postStore: postStore, reset: true)
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
        _ = await loadPage(context: context, currentUser: currentUser, mode: mode, postStore: postStore, reset: false)
    }

    func refresh(context: ModelContext, currentUser: UserEntity, postStore: PostStore) async {
        await loadInitial(context: context, currentUser: currentUser, postStore: postStore)
    }

    func toggleLike(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore) async {
        do {
            postStore.register(post)
            // PostStore.toggleLike handles the optimistic UI mutation and
            // authoritative backend write-through in one place.
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

    private func loadPage(context: ModelContext, currentUser: UserEntity, mode requestedMode: TimelineMode, postStore: PostStore, reset: Bool) async -> Bool {
        if reset {
            if posts.isEmpty {
                // Stale-while-revalidate: paint the last cached feed instantly so
                // a slow-but-working network (e.g. 国内 4G to the Hong Kong edge)
                // no longer leaves the user staring at a skeleton. The live
                // refresh below replaces these posts in place once it arrives —
                // picking up any deletes/edits — so nothing is stale for long; it
                // just appears immediately instead of only after the round trip.
                let cached = await KaiXFeedCache.loadAsync(key: feedCacheKey(for: requestedMode))
                if !cached.isEmpty {
                    let bundle = ServerEntityFactory.postBundle(from: cached)
                    authors.merge(bundle.authors) { _, fresh in fresh }
                    mediaByPostId.merge(bundle.mediaByPostId) { _, fresh in fresh }
                    postStore.register(bundle.allPosts)
                    if requestedMode == mode {
                        posts = balanceOfficialRuns(bundle.orderedPosts)
                        loadedIds = Set(posts.map(\.id))
                        postStore.setFeed(posts, append: false)
                        state = .loaded
                    }
                } else {
                    state = .loading
                }
            }
        } else {
            isLoadingMore = true
        }
        defer { isLoadingMore = false }

        do {
            // Pull the freshest feed from the API so iOS and Web stay in
            // lockstep. On reset that's page 1; on "load more" we advance
            // the server cursor so infinite scroll keeps serving new content
            // instead of recycling a local cache window.
            // Pull the public feed for EVERYONE, including guests. The
            // backend serves GET /api/feed unauthenticated (verified: 200
            // with content), and a logged-out browser landing on an empty
            // 首页 — while 发现 was full of city content — was the app's
            // worst first impression. Best-effort: syncFromRemote swallows
            // failures and falls back to repository handling, so offline (and
            // a guest's empty 关注 tab) degrade gracefully.
            if reset {
                await syncFromRemote(context: context, mode: requestedMode, cursor: nil)
            } else if remoteHasMore {
                await syncFromRemote(context: context, mode: requestedMode, cursor: remoteCursor)
            }

            let repository = PostRepository(context: context)
            let page: [PostEntity]
            let usedRemotePage: Bool
            var usedCachedSnapshotPage = false
            if let bundle = pendingRemoteBundle {
                // Server-paged path: render exactly the page the cursor
                // returned, in server order. The local store is not used as
                // the paginator or source of truth in production.
                pendingRemoteBundle = nil
                usedRemotePage = !pendingRemoteBundleIsCachedSnapshot
                usedCachedSnapshotPage = pendingRemoteBundleIsCachedSnapshot
                pendingRemoteBundleIsCachedSnapshot = false
                page = bundle.orderedPosts
                authors.merge(bundle.authors) { _, fresh in fresh }
                mediaByPostId.merge(bundle.mediaByPostId) { _, fresh in fresh }
                postStore.register(bundle.allPosts)
                if usedCachedSnapshotPage {
                    canLoadMore = false
                }
            } else if pendingRemoteBundleIsEmptyPage {
                // The server answered with a truly empty page — render it as
                // such instead of falling through to repository.fetchPage,
                // which (in remote mode) re-issued the same feed request.
                // canLoadMore mirrors the old outcome for an empty page:
                // page.count < pageSize and remoteHasMore == false ⇒ false.
                pendingRemoteBundleIsEmptyPage = false
                usedRemotePage = true
                page = []
                canLoadMore = false
            } else {
                usedRemotePage = false
                page = try await repository.fetchPage(mode: requestedMode, currentUserId: currentUser.id, page: currentPage, pageSize: KaiXConfig.pageSize)
            }
            guard requestedMode == mode else { return true }
            // Belt-and-braces: even if the local window shifted (new posts
            // synced in above us), an id can never appear twice in the list.
            let appended = page.filter { !loadedIds.contains($0.id) }
            posts = balanceOfficialRuns(reset ? page : posts + appended)
            loadedIds = Set(posts.map(\.id))
            postStore.setFeed(posts, append: false)
            currentPage += 1
            // Hot has no server cursor (single ranked page) — after it,
            // deterministic local windows keep deeper browsing alive.
            if canLoadMore {
                canLoadMore = usedRemotePage
                    ? (remoteHasMore || requestedMode == .hot)
                    : (page.count == KaiXConfig.pageSize || remoteHasMore)
            }
            if !usedCachedSnapshotPage {
                try await hydrate(
                    context: context,
                    repository: repository,
                    currentUser: currentUser,
                    postStore: postStore,
                    reset: reset,
                    refreshRecommendations: reset || recommendedUsers.isEmpty
                )
            }
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

    /// Pull one page of the unified KaiX backend feed and advance the server
    /// cursor. Best-effort: a failure leaves the current on-screen content in
    /// place instead of interrupting scrolling.
    private func syncFromRemote(context: ModelContext, mode requestedMode: TimelineMode, cursor: String?) async {
        do {
            let apiMode: KaiXAPIClient.FeedMode
            switch requestedMode {
            case .recommend: apiMode = .recommend
            case .local:     apiMode = .local
            case .following: apiMode = .following
            case .hot:       apiMode = .hot
            }
            // 热榜 now follows the selected city from the top region chip,
            // so the extra city/country/all row is no longer needed.
            let region = RegionStore.shared.current
            let cityScoped = requestedMode == .local || requestedMode == .hot
            let page = try await KaiXAPIClient.shared.feed(
                mode: apiMode,
                cursor: cursor,
                regionCode: cityScoped ? region?.regionCode : nil,
                country: region?.countryCode,
                province: cityScoped ? (region?.provinceCode.isEmpty == true ? nil : region?.provinceCode) : nil,
                city: cityScoped ? region?.cityCode : nil
            )
            remoteCursor = page.next_cursor
            remoteHasMore = page.next_cursor != nil && !page.items.isEmpty
            pendingRemoteBundle = page.items.isEmpty ? nil : ServerEntityFactory.postBundle(from: page.items)
            pendingRemoteBundleIsCachedSnapshot = false
            // Remember "server said empty" so loadPage doesn't re-request.
            pendingRemoteBundleIsEmptyPage = page.items.isEmpty
            // Snapshot the first page so a future offline cold launch can still
            // show something instead of a blank feed. Best-effort, never blocks.
            if cursor == nil {
                KaiXFeedCache.save(page.items, key: feedCacheKey(for: requestedMode))
            }
        } catch {
            // Silent — the local fallback below still produces a usable feed.
            // On a cold first page, fall back to the last good server snapshot
            // so an offline launch is not blank.
            if cursor == nil {
                let cachedItems = await KaiXFeedCache.loadAsync(key: feedCacheKey(for: requestedMode))
                pendingRemoteBundle = cachedItems.isEmpty ? nil : ServerEntityFactory.postBundle(from: cachedItems)
                pendingRemoteBundleIsCachedSnapshot = pendingRemoteBundle != nil
            } else {
                pendingRemoteBundle = nil
                pendingRemoteBundleIsCachedSnapshot = false
            }
            // A FAILED sync is not an empty page — keep the local fallback path.
            pendingRemoteBundleIsEmptyPage = false
            // Keep the previous cursor state so a transient network error
            // doesn't permanently stop remote pagination.
        }
    }

    private func feedCacheKey(for mode: TimelineMode) -> String {
        let region = RegionStore.shared.current
        let cityScoped = mode == .local || mode == .hot
        let province = cityScoped ? (region?.provinceCode.isEmpty == true ? "" : region?.provinceCode ?? "") : ""
        let city = cityScoped ? (region?.cityCode ?? "") : ""
        let regionCode = cityScoped ? (region?.regionCode ?? "") : ""
        return [
            "home",
            mode.rawValue,
            region?.countryCode ?? "",
            province,
            city,
            regionCode
        ].joined(separator: "_")
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
        // Missing-only on reset too: the server feed response embeds each
        // post's author and loadPage merged those fresh entries into `authors`
        // before hydrate runs, so re-fetching every author here repeated one
        // HTTP round trip per distinct author on every refresh. Only ids the
        // page bundle didn't cover are fetched. First load is unchanged —
        // `authors` starts empty, so "missing" == "all".
        let authorIdsToFetch = missingAuthorIds
        if !authorIdsToFetch.isEmpty {
            let postAuthors = try await userRepository.fetchUsers(ids: authorIdsToFetch)
            authors.merge(Dictionary(uniqueKeysWithValues: postAuthors.map { ($0.id, $0) })) { _, new in new }
        }
        if refreshRecommendations {
            recommendedUsers = try await userRepository.fetchRecommendedUsers(excluding: currentUser.id, limit: 10)
        }
        // Missing-only media hydration on reset too: the feed bundle already
        // delivered an entry (possibly []) for every post on the page and
        // loadPage merged it into `mediaByPostId`, so re-fetching media for
        // every post cost one HTTP round trip PER POST per refresh (the feed's
        // N+1). Only posts without a known entry are fetched now; on reset the
        // map is then rebuilt to exactly the hydrated ids, preserving the old
        // behavior of pruning entries left over from the previous feed.
        let knownMediaPostIds = Set(mediaByPostId.keys)
        let postsNeedingMedia = hydratedPosts.filter { !knownMediaPostIds.contains($0.id) }
        var fetchedMedia: [String: [MediaEntity]] = [:]
        if !postsNeedingMedia.isEmpty {
            fetchedMedia = try await repository.fetchMedia(for: postsNeedingMedia)
            for post in postsNeedingMedia where fetchedMedia[post.id] == nil {
                fetchedMedia[post.id] = []
            }
        }
        if reset {
            var rebuilt: [String: [MediaEntity]] = [:]
            rebuilt.reserveCapacity(hydratedPosts.count)
            for post in hydratedPosts {
                rebuilt[post.id] = fetchedMedia[post.id] ?? mediaByPostId[post.id] ?? []
            }
            mediaByPostId = rebuilt
        } else if !fetchedMedia.isEmpty {
            mediaByPostId.merge(fetchedMedia) { _, new in new }
        }
    }
}
