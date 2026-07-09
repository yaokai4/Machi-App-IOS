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
    // 互动(赞/藏/转/引用/关注)失败的瞬态错误。绝不写 `state`:一次交互失败
    // 曾把整个已加载 feed 换成全屏错误页(丢滚动位置,弱网下点个赞满屏内容
    // 瞬间消失)。视图以 toast 呈现并在展示后清回 nil;只有初始加载失败且
    // posts 为空时才允许进入 .error(见 loadPage 的 catch)。
    @Published var transientError: String?

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

    /// Drop deleted posts (and their local reposts) from this feed in response to
    /// `.kaiXPostRemoved`, so a delete from the detail page doesn't leave a ghost
    /// card that the `?? post` fallback would keep rendering.
    func removePosts(ids: [String]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        posts.removeAll { idSet.contains($0.id) }
        loadedIds.subtract(idSet)
    }

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
        // Never page while an initial load / reload is in flight: it resets the
        // cursor + loadedIds mid-stream, so a concurrent append would double-count
        // the page or interleave two feeds.
        guard canLoadMore, !isLoadingMore, !isLoadingInitial else { return }
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
            transientError = error.kaixUserMessage
        }
    }

    func toggleBookmark(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore) async {
        do {
            postStore.register(post)
            try await postStore.toggleBookmark(context: context, postId: post.id, currentUser: currentUser)
        } catch {
            transientError = error.kaixUserMessage
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
            transientError = error.kaixUserMessage
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
            transientError = error.kaixUserMessage
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
            transientError = error.kaixUserMessage
        }
    }

    private func loadPage(context: ModelContext, currentUser: UserEntity, mode requestedMode: TimelineMode, postStore: PostStore, reset: Bool) async -> Bool {
        // Same-city feed with no city chosen yet: don't hit the network — the
        // server's `local` mode 400s without a region, which would strand the
        // user on a network-error page instead of the "pick a city" prompt.
        // Short-circuit to the empty state (HomeTimelineView renders
        // localPickRegionState for .local + nil region), mirroring the local-
        // store fallback's `guard region else { return [] }`.
        if requestedMode == .local, RegionStore.shared.current == nil {
            if requestedMode == mode {
                posts = []
                loadedIds = []
                postStore.setFeed([], append: false)
                canLoadMore = false
                state = .empty
            }
            return true
        }
        if reset {
            if posts.isEmpty {
                // Stale-while-revalidate: paint the last cached feed instantly so
                // a slow-but-working network (e.g. 国内 4G to the Hong Kong edge)
                // no longer leaves the user staring at a skeleton. The live
                // refresh below replaces these posts in place once it arrives —
                // picking up any deletes/edits — so nothing is stale for long; it
                // just appears immediately instead of only after the round trip.
                let cached = await KaiXFeedCache.loadAsync(key: feedCacheKey(for: requestedMode, region: RegionStore.shared.current))
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
                // 生产(远程)模式下 fetchPage 不接游标、永远请求第 1 页。加载更多
                // 时游标同步失败后再走它,等于对刚失败的首页请求原样重发:失败时
                // 用户白等双倍超时;"成功"时整页几乎全被 loadedIds 滤掉,还会因
                // 首页满页把 canLoadMore 误判回 true。这里保留游标直接退出,
                // 下次触底用同一 cursor 重试;本地 page 语义只留给
                // allowLocalStoreFallback 构建(测试/UI 测试)。
                if !reset, KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
                    return false
                }
                page = try await repository.fetchPage(mode: requestedMode, currentUserId: currentUser.id, page: currentPage, pageSize: KaiXConfig.pageSize)
            }
            guard requestedMode == mode else { return true }
            // Belt-and-braces: even if the local window shifted (new posts
            // synced in above us), an id can never appear twice in the list.
            let appended = page.filter { !loadedIds.contains($0.id) }
            if reset {
                posts = balanceOfficialRuns(page)
            } else {
                // 打散只作用于新追加的区段:对全列表重跑会把已上屏(用户正看着)
                // 的行与下方新页内容 swapAt,分页触发的瞬间卡片在手指下跳变。
                // 旧列表末尾 2 条只读传入作 run 上下文,跨页边界的官方连发仍能
                // 被检测,但已渲染前缀绝不移动。
                posts += balanceOfficialRuns(appended, previousTail: Array(posts.suffix(2)))
            }
            loadedIds = Set(posts.map(\.id))
            postStore.setFeed(posts, append: false)
            currentPage += 1
            // Hot has no server cursor (single ranked page) — after it,
            // deterministic local windows keep deeper browsing alive.
            if canLoadMore {
                // Hot has no server cursor (single ranked page). Deeper browsing
                // via deterministic local windows only exists in the local-store
                // fallback build; in production `fetchPage(.hot)` re-requests the
                // same first page with no cursor, so keeping canLoadMore true
                // there just re-pulls an all-duplicate page on every scroll-to-
                // bottom. Only preserve the hot "load more" when the local
                // fallback can actually serve deeper windows.
                canLoadMore = usedRemotePage
                    ? (remoteHasMore || (requestedMode == .hot && KaiXRuntimeFlags.allowLocalStoreFallback))
                    : (page.count == KaiXConfig.pageSize || remoteHasMore)
            }
            if !usedCachedSnapshotPage {
                try await hydrate(
                    context: context,
                    repository: repository,
                    currentUser: currentUser,
                    postStore: postStore,
                    reset: reset
                )
            }
            state = posts.isEmpty ? .empty : .loaded
            // 推荐用户(/api/trending)只服务「关注」空态,与 feed 本身无关 ——
            // 它曾在 hydrate 关键路径上串行 await,冷启动无缓存时首屏骨架要
            // 白等一个与 feed 无关的 RTT,且每个 tab 的每次下拉刷新都多打一次
            // trending。改为 posts 落地、state 置好之后按需异步补齐。
            if requestedMode == .following, posts.isEmpty {
                refreshRecommendedUsers(context: context, currentUser: currentUser)
            }
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
        // 热榜 now follows the selected city from the top region chip,
        // so the extra city/country/all row is no longer needed.
        let region = RegionStore.shared.current
        // 缓存键必须与请求参数取自同一 region 快照:请求在途时用户切换城市
        // 的话,await 之后再重读 RegionStore 会把【旧城市】的响应落到
        // 【新城市】的键下,之后新城市的 SWR 首绘 / 离线兜底会把污染快照
        // 当新城内容画出来(最长缓存 3 天)。所以键在发请求前就算好,
        // 成功落盘和失败回读用的都是同一个键。
        let cacheKey = feedCacheKey(for: requestedMode, region: region)
        do {
            let apiMode: KaiXAPIClient.FeedMode
            switch requestedMode {
            case .recommend: apiMode = .recommend
            case .local:     apiMode = .local
            case .following: apiMode = .following
            case .hot:       apiMode = .hot
            }
            let cityScoped = requestedMode == .local || requestedMode == .hot
            let page = try await KaiXAPIClient.shared.feed(
                mode: apiMode,
                cursor: cursor,
                regionCode: cityScoped ? region?.regionCode : nil,
                country: region?.countryCode,
                province: cityScoped ? (region?.provinceCode.isEmpty == true ? nil : region?.provinceCode) : nil,
                city: cityScoped ? region?.cityCode : nil
            )
            // await 之后复校 mode 与 region:唯一让位点是上面的网络 await。若「触底
            // 加载更多在途」时用户切了城市/模式,晚到的旧城页绝不能写进已被
            // loadInitial(clearExisting) 清空的新城状态(否则新城会渲染旧城内容,
            // 新城无缓存且请求失败时还会持久残留)。与 CityChannelViewModel.syncFromRemote
            // 的 `guard requestedChannel == channel` 对称。
            guard requestedMode == mode,
                  RegionStore.shared.current?.regionCode == region?.regionCode else { return }
            remoteCursor = page.next_cursor
            remoteHasMore = page.next_cursor != nil && !page.items.isEmpty
            pendingRemoteBundle = page.items.isEmpty ? nil : ServerEntityFactory.postBundle(from: page.items)
            pendingRemoteBundleIsCachedSnapshot = false
            // Remember "server said empty" so loadPage doesn't re-request.
            pendingRemoteBundleIsEmptyPage = page.items.isEmpty
            // Snapshot the first page so a future offline cold launch can still
            // show something instead of a blank feed. Best-effort, never blocks.
            if cursor == nil {
                KaiXFeedCache.save(page.items, key: cacheKey)
            }
        } catch {
            // Silent — the local fallback below still produces a usable feed.
            // 同样复校 mode/region:失败回读用的是发请求前捕获的 cacheKey(旧城键),
            // 城市已切换时不能把旧城快照回填进新城状态。
            guard requestedMode == mode,
                  RegionStore.shared.current?.regionCode == region?.regionCode else { return }
            // On a cold first page, fall back to the last good server snapshot
            // so an offline launch is not blank. 但只在【空 feed】时抢救:否则
            // 离线下拉刷新(clearExisting=false,posts 已深度分页到几十条)会被
            // ≤40 条/最长 3 天的陈旧快照整体覆盖并禁用"加载更多"。posts 非空时
            // 保持 bundle 为 nil,让 loadPage reset 经 repository 再抛错 →
            // loadInitialPass 回滚到刷新前的实况列表与分页(与城市频道一致)。
            if cursor == nil, posts.isEmpty {
                let cachedItems = await KaiXFeedCache.loadAsync(key: cacheKey)
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

    // region 由调用方显式传入(而不是在这里读 RegionStore.shared.current):
    // syncFromRemote 的键必须来自发请求前捕获的同一 region 快照,await 之后
    // 重读会在城市切换竞态下把旧城 feed 写进新城的缓存键。
    private func feedCacheKey(for mode: TimelineMode, region: KaiXRegionDirectory.Region?) -> String {
        let cityScoped = mode == .local || mode == .hot
        let province = cityScoped ? (region?.provinceCode.isEmpty == true ? "" : region?.provinceCode ?? "") : ""
        let city = cityScoped ? (region?.cityCode ?? "") : ""
        let regionCode = cityScoped ? (region?.regionCode ?? "") : ""
        // Scope the on-disk feed snapshot to the current account (the guest
        // sentinel gets its own stable bucket): the 关注 tab and per-user
        // like/bookmark state differ by account, so one account's cached feed
        // must never be painted for the next after a logout / switch. logout
        // also clears the folder; this is belt-and-braces for any snapshot
        // written before the wipe.
        let userScope = AuthService.shared.currentUserId.isEmpty ? "guest" : AuthService.shared.currentUserId
        return [
            "home",
            userScope,
            mode.rawValue,
            region?.countryCode ?? "",
            province,
            city,
            regionCode
        ].joined(separator: "_")
    }

    private func balanceOfficialRuns(_ input: [PostEntity], previousTail: [PostEntity] = []) -> [PostEntity] {
        var output = input
        var previousKey = ""
        var runCount = 0

        // 用已上屏的尾部预热 run 状态(只读、绝不参与交换),这样一段官方内容
        // 连发即使跨越分页边界也会在新区段的开头触发打散。
        for post in previousTail {
            let key = officialFeedKey(for: post)
            if key.isEmpty {
                previousKey = ""
                runCount = 0
            } else if key == previousKey {
                runCount += 1
            } else {
                previousKey = key
                runCount = 1
            }
        }

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

    // 关注空态的推荐用户异步补齐任务;新一轮开始前取消上一轮,防止旧响应
    // 迟到覆盖新数据。
    private var recommendedUsersTask: Task<Void, Never>?

    /// 按需拉取「关注」空态的推荐用户。失败静默(装饰性内容,绝不升级为
    /// 错误页);不 await,不阻塞 loadPage 的返回。
    private func refreshRecommendedUsers(context: ModelContext, currentUser: UserEntity) {
        recommendedUsersTask?.cancel()
        let excludedUserId = currentUser.id
        recommendedUsersTask = Task { [weak self] in
            let users = (try? await UserRepository(context: context).fetchRecommendedUsers(excluding: excludedUserId, limit: 10)) ?? []
            guard let self, !Task.isCancelled, !users.isEmpty else { return }
            self.recommendedUsers = users
        }
    }

    private func hydrate(
        context: ModelContext,
        repository: PostRepository,
        currentUser: UserEntity,
        postStore: PostStore,
        reset: Bool
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
