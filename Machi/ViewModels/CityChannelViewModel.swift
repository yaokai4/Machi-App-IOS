import Combine
import Foundation
import SwiftData

@MainActor
final class CityChannelViewModel: ObservableObject {
    @Published var channel: CityChannel = .recommend
    @Published var region: KaiXRegionDirectory.Region?
    @Published var posts: [PostEntity] = []
    @Published var authors: [String: UserEntity] = [:]
    @Published var mediaByPostId: [String: [MediaEntity]] = [:]
    @Published var state: ScreenState = .idle
    @Published var isLoadingMore = false
    @Published var canLoadMore = true
    // 互动(赞/藏/转/引用)失败的瞬态错误,与 HomeViewModel 同一模式。绝不写
    // `state`:一次交互失败曾把整个已加载频道 Feed 换成全屏错误页(丢滚动
    // 位置)。视图以 toast 呈现并在展示后清回 nil;只有初始加载失败且 posts
    // 为空时才允许进入 .error(见 loadPage 的 catch)。
    @Published var transientError: String?

    private var currentPage = 0
    // Server cursor state — identical protocol to HomeViewModel. When the
    // remote page is available the list renders exactly those ids in server
    // order; the local offset query is only the offline fallback.
    private var remoteCursor: String?
    private var remoteHasMore = false
    private var pendingRemoteBundle: ServerEntityFactory.PostBundle?
    // The server ANSWERED and the page was genuinely empty (a channel with no
    // content yet, or the empty terminating page that follows a full page whose
    // next_cursor was non-nil). Distinct from "sync failed" (bundle nil, flag
    // false): without this marker loadPage falls through to the local else
    // branch, which in production re-issues the same cursor-less /api/feed
    // (page 1) just to learn "empty" again — and a full first page re-flips
    // canLoadMore back to true, turning a multi-page channel into a
    // re-fetch-first-page loop at the bottom. Mirrors HomeViewModel.
    private var pendingRemoteBundleIsEmptyPage = false
    // Ids already in `posts`, so an appended page can never repeat a row.
    private var loadedIds = Set<String>()

    /// Drop deleted posts (and their local reposts) in response to
    /// `.kaiXPostRemoved` — same ghost-card fix as HomeViewModel.
    func removePosts(ids: [String]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        posts.removeAll { idSet.contains($0.id) }
        loadedIds.subtract(idSet)
    }
    // Re-entrancy guard, identical in spirit to HomeViewModel: the channel view
    // fires loadInitial from .task plus onChange(channel/region) handlers that
    // can overlap. loadPage suspends at `await syncFromRemote`, so two
    // interleaved calls both reset the cursor/loadedIds and mix pages. Serialize:
    // a second call while one is in flight queues a single follow-up pass that
    // always reloads the latest selected channel.
    private var isLoadingInitial = false
    private var pendingInitialReload = false
    private var pendingInitialClearExisting = false

    func configure(regionCode: String, channel: CityChannel = .recommend) {
        region = KaiXRegionDirectory.resolve(regionCode: regionCode)
        self.channel = channel
    }

    func loadInitial(context: ModelContext, currentUser: UserEntity, postStore: PostStore, clearExisting: Bool = false) async {
        guard region != nil else {
            state = .empty
            return
        }
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
            let requestedChannel = channel
            await loadInitialPass(
                context: context,
                currentUser: currentUser,
                postStore: postStore,
                channel: requestedChannel,
                clearExisting: nextClearExisting
            )
            let channelChangedDuringLoad = requestedChannel != channel
            nextClearExisting = pendingInitialClearExisting || channelChangedDuringLoad
            pendingInitialClearExisting = false
            guard pendingInitialReload || channelChangedDuringLoad else { break }
        }
    }

    private func loadInitialPass(
        context: ModelContext,
        currentUser: UserEntity,
        postStore: PostStore,
        channel requestedChannel: CityChannel,
        clearExisting: Bool
    ) async {
        guard let region else {
            state = .empty
            return
        }
        // 失败恢复(与 HomeViewModel.loadInitialPass 同一模式):下拉刷新
        // (clearExisting=false)会先无条件清空 loadedIds/cursor,若刷新
        // 网络失败而 posts 保留旧内容,loadedIds 永久为空——网络恢复后
        // loadMore 走无游标第 1 页请求,对空集合过滤后整页追加成重复帖
        // (ForEach 收到重复 Identifiable id)。刷新失败时把分页状态整体
        // 回滚到刷新前,让旧列表继续正常分页。
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
        pendingRemoteBundleIsEmptyPage = false
        loadedIds = []
        if clearExisting {
            posts = []
            authors = [:]
            mediaByPostId = [:]
        }
        let didLoad = await loadPage(context: context, currentUser: currentUser, postStore: postStore, region: region, channel: requestedChannel, reset: true)
        if !didLoad, !clearExisting, !posts.isEmpty {
            currentPage = previousPage
            canLoadMore = previousCanLoadMore
            remoteCursor = previousCursor
            remoteHasMore = previousRemoteHasMore
            loadedIds = previousLoadedIds
        }
    }

    func loadMoreIfNeeded(context: ModelContext, currentUser: UserEntity, post: PostEntity?, postStore: PostStore) async {
        guard let region, canLoadMore, !isLoadingMore, !isLoadingInitial else { return }
        guard post == nil || post?.id == posts.last?.id else { return }
        _ = await loadPage(context: context, currentUser: currentUser, postStore: postStore, region: region, channel: channel, reset: false)
    }

    func refresh(context: ModelContext, currentUser: UserEntity, postStore: PostStore) async {
        await loadInitial(context: context, currentUser: currentUser, postStore: postStore, clearExisting: false)
    }

    func toggleLike(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore) async {
        do {
            postStore.register(post)
            try await postStore.toggleLike(context: context, postId: post.id, currentUser: currentUser)
            posts = posts.map { $0 }
        } catch {
            transientError = error.kaixUserMessage
        }
    }

    func toggleBookmark(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore) async {
        do {
            postStore.register(post)
            try await postStore.toggleBookmark(context: context, postId: post.id, currentUser: currentUser)
            posts = posts.map { $0 }
        } catch {
            transientError = error.kaixUserMessage
        }
    }

    func repost(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore) async {
        do {
            postStore.register(post)
            _ = try await postStore.toggleRepost(context: context, postId: post.id, currentUser: currentUser)
            posts = posts.map { $0 }
        } catch {
            transientError = error.kaixUserMessage
        }
    }

    func quoteRepost(context: ModelContext, post: PostEntity, currentUser: UserEntity, content: String, postStore: PostStore) async {
        do {
            postStore.register(post)
            _ = try await postStore.quoteRepost(context: context, postId: post.id, currentUser: currentUser, content: content)
            posts = posts.map { $0 }
        } catch {
            transientError = error.kaixUserMessage
        }
    }

    /// 返回本次分页是否成功落地(与 HomeViewModel.loadPage 同约定):
    /// 失败返回 false,loadInitialPass 据此回滚刷新前的分页状态;
    /// 频道已切换的中途丢弃视为"已处理"返回 true(序列化的 loadInitial
    /// 会用 clearExisting 重载新频道,不需要回滚旧状态)。
    private func loadPage(
        context: ModelContext,
        currentUser: UserEntity,
        postStore: PostStore,
        region: KaiXRegionDirectory.Region,
        channel requestedChannel: CityChannel,
        reset: Bool
    ) async -> Bool {
        if reset {
            if posts.isEmpty { state = .loading }
        } else {
            isLoadingMore = true
        }
        defer { isLoadingMore = false }

        do {
            // Advance the server cursor on every page (reset → page 1),
            // not just on reset — "load more" used to re-read only the
            // local cache, so deep scrolling recycled stale content.
            // Guests included: the city feed is public (GET /api/feed is
            // served unauthenticated), so a logged-out user opening a city
            // channel sees real content instead of an empty page. Best-effort
            // — falls back to the local cache on any failure.
            if reset || remoteHasMore {
                await syncFromRemote(context: context, region: region, channel: requestedChannel, cursor: reset ? nil : remoteCursor)
            }
            // The user switched channels while this request was in flight — the
            // serialized loadInitial will reload the new channel, so drop this
            // page instead of writing another channel's posts into `posts`.
            guard requestedChannel == channel else { return true }
            let repository = PostRepository(context: context)
            let page: [PostEntity]
            let usedRemotePage: Bool
            if let bundle = pendingRemoteBundle {
                pendingRemoteBundle = nil
                usedRemotePage = true
                page = bundle.orderedPosts
                authors.merge(bundle.authors) { _, fresh in fresh }
                mediaByPostId.merge(bundle.mediaByPostId) { _, fresh in fresh }
                postStore.register(bundle.allPosts)
            } else if pendingRemoteBundleIsEmptyPage {
                // The server answered with a genuinely empty page — render it as
                // such instead of falling through to fetchCityPage, which in
                // production re-issues the same cursor-less /api/feed just to
                // learn "empty" again (and a full first page would re-flip
                // canLoadMore back to true, looping the bottom of a multi-page
                // channel). canLoadMore is forced false here; the formula below
                // is guarded by `if canLoadMore` so it won't re-enable it.
                // Mirrors HomeViewModel:269.
                pendingRemoteBundleIsEmptyPage = false
                usedRemotePage = true
                page = []
                canLoadMore = false
            } else {
                // 生产(远程)模式下 fetchCityPage 不接游标、永远请求第 1 页。触底加载
                // 更多时游标同步失败后再走它,等于对刚失败的首页请求原样重发:失败时
                // 用户白等双倍超时;"成功"时整页几乎全被 loadedIds 滤空,还会因首页满页
                // 把 canLoadMore 误判回 true。这里保留游标直接退出,下次触底用同一
                // cursor 重试;本地 page 语义只留给 allowLocalStoreFallback 构建
                // (测试/UI 测试)。与 HomeViewModel:287 对等。
                if !reset, KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
                    return false
                }
                usedRemotePage = false
                page = try await repository.fetchCityPage(
                    region: region,
                    channel: requestedChannel,
                    currentUserId: currentUser.id,
                    page: currentPage,
                    pageSize: KaiXConfig.pageSize
                )
            }
            // Re-check after the local fallback's await too — the channel could
            // have flipped during fetchCityPage.
            guard requestedChannel == channel else { return true }
            let appended = page.filter { !loadedIds.contains($0.id) }
            posts = reset ? page : posts + appended
            loadedIds = Set(posts.map(\.id))
            postStore.register(posts)
            currentPage += 1
            // Hot has no server cursor (single ranked page). Deeper local-window
            // browsing only exists in the local-store fallback build; in
            // production `fetchCityPage(.hot)` re-requests the same first page
            // with no cursor, so keeping canLoadMore true there re-pulls an
            // all-duplicate page on every scroll-to-bottom. Only keep the hot
            // "load more" where the local fallback can serve deeper windows.
            // Guarded by `if canLoadMore` so the empty-page branch above can
            // force it false without this formula re-enabling it (parity with
            // HomeViewModel:310). Every real path reaching here has canLoadMore
            // == true (reset sets it true; loadMore is gated on it), so this
            // only suppresses the empty-page case.
            if canLoadMore {
                canLoadMore = usedRemotePage
                    ? (remoteHasMore || (requestedChannel == .hot && KaiXRuntimeFlags.allowLocalStoreFallback))
                    : page.count == KaiXConfig.pageSize
            }
            try await hydrate(context: context, repository: repository, currentUser: currentUser, postStore: postStore, reset: reset)
            guard requestedChannel == channel else { return true }
            state = posts.isEmpty ? .empty : .loaded
            return true
        } catch {
            guard requestedChannel == channel else { return true }
            state = posts.isEmpty ? .error(error.kaixUserMessage) : .loaded
            return false
        }
    }

    /// Pull one server page for this city/channel and remember its ids +
    /// cursor. Best-effort: on failure the local cache keeps the view alive.
    private func syncFromRemote(context: ModelContext, region: KaiXRegionDirectory.Region, channel requestedChannel: CityChannel, cursor: String?) async {
        do {
            let page = try await KaiXAPIClient.shared.feed(
                mode: requestedChannel == .hot ? .hot : .recommend,
                cursor: cursor,
                regionCode: region.regionCode,
                country: region.countryCode,
                province: region.provinceCode.isEmpty ? nil : region.provinceCode,
                city: region.cityCode,
                contentTypes: requestedChannel.contentTypes
            )
            // A late-arriving response for a channel the user already left must
            // not clobber the new channel's cursor / pending bundle.
            guard requestedChannel == channel else { return }
            remoteCursor = page.next_cursor
            remoteHasMore = page.next_cursor != nil && !page.items.isEmpty
            pendingRemoteBundle = page.items.isEmpty ? nil : ServerEntityFactory.postBundle(from: page.items)
            // Remember "server said empty" so loadPage renders the empty page
            // instead of re-requesting it through fetchCityPage.
            pendingRemoteBundleIsEmptyPage = page.items.isEmpty
        } catch {
            guard requestedChannel == channel else { return }
            pendingRemoteBundle = nil
            // A FAILED sync is not an empty page — keep the local fallback path.
            pendingRemoteBundleIsEmptyPage = false
        }
    }

    // Missing-only 水合(与 HomeViewModel.hydrate 同一修复):feed bundle 已内嵌
    // 每帖的作者与媒体并在 loadPage 里 merge 过,这里只补 bundle 没覆盖的缺口。
    // 旧实现对【全部累计 posts】整体重取——生产模式 fetchMedia(for:) 是逐帖顺序
    // GET /api/posts/{id},第 k 页要发 ~k×pageSize 个串行请求(整个会话 O(N²)),
    // 期间 isLoadingMore 一直为 true 阻塞分页;同时 authors 全量替换会在单个
    // userDetail 静默失败时把已有作者丢成「未知用户」。
    private func hydrate(context: ModelContext, repository: PostRepository, currentUser: UserEntity, postStore: PostStore, reset: Bool) async throws {
        let originalIds = Set(posts.compactMap(\.repostOfPostId))
        let cachedOriginalPosts = originalIds.compactMap { postStore.post(id: $0) }
        let missingOriginalIds = originalIds.subtracting(Set(cachedOriginalPosts.map(\.id)))
        let fetchedOriginalPosts: [PostEntity]
        if missingOriginalIds.isEmpty {
            fetchedOriginalPosts = []
        } else {
            fetchedOriginalPosts = try await repository.fetchPosts(ids: missingOriginalIds, currentUserId: currentUser.id)
            postStore.register(fetchedOriginalPosts)
        }
        let originalPosts = cachedOriginalPosts + fetchedOriginalPosts
        let hydratedPosts = posts + originalPosts
        postStore.register(hydratedPosts)
        // 只补缺失作者并 merge,绝不整体替换——保住 bundle 已内嵌的作者。
        let missingAuthorIds = Set(hydratedPosts.map(\.authorId)).subtracting(Set(authors.keys))
        if !missingAuthorIds.isEmpty {
            let fetchedAuthors = try await UserRepository(context: context).fetchUsers(ids: missingAuthorIds)
            authors.merge(Dictionary(uniqueKeysWithValues: fetchedAuthors.map { ($0.id, $0) })) { _, new in new }
        }
        // bundle 提供过的条目(含空数组)视为已知,只为没有条目的帖子取媒体;
        // reset 时按水合后的 id 集重建,保留旧行为里"清掉上一轮残留"的语义。
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
