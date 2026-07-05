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

    private var currentPage = 0
    // Server cursor state — identical protocol to HomeViewModel. When the
    // remote page is available the list renders exactly those ids in server
    // order; the local offset query is only the offline fallback.
    private var remoteCursor: String?
    private var remoteHasMore = false
    private var pendingRemoteBundle: ServerEntityFactory.PostBundle?
    // Ids already in `posts`, so an appended page can never repeat a row.
    private var loadedIds = Set<String>()
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
        currentPage = 0
        canLoadMore = true
        remoteCursor = nil
        remoteHasMore = false
        pendingRemoteBundle = nil
        loadedIds = []
        if clearExisting {
            posts = []
            authors = [:]
            mediaByPostId = [:]
        }
        await loadPage(context: context, currentUser: currentUser, postStore: postStore, region: region, channel: requestedChannel, reset: true)
    }

    func loadMoreIfNeeded(context: ModelContext, currentUser: UserEntity, post: PostEntity?, postStore: PostStore) async {
        guard let region, canLoadMore, !isLoadingMore, !isLoadingInitial else { return }
        guard post == nil || post?.id == posts.last?.id else { return }
        await loadPage(context: context, currentUser: currentUser, postStore: postStore, region: region, channel: channel, reset: false)
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
            state = .error(error.kaixUserMessage)
        }
    }

    func toggleBookmark(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore) async {
        do {
            postStore.register(post)
            try await postStore.toggleBookmark(context: context, postId: post.id, currentUser: currentUser)
            posts = posts.map { $0 }
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func repost(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore) async {
        do {
            postStore.register(post)
            _ = try await postStore.toggleRepost(context: context, postId: post.id, currentUser: currentUser)
            posts = posts.map { $0 }
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func quoteRepost(context: ModelContext, post: PostEntity, currentUser: UserEntity, content: String, postStore: PostStore) async {
        do {
            postStore.register(post)
            _ = try await postStore.quoteRepost(context: context, postId: post.id, currentUser: currentUser, content: content)
            posts = posts.map { $0 }
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    private func loadPage(
        context: ModelContext,
        currentUser: UserEntity,
        postStore: PostStore,
        region: KaiXRegionDirectory.Region,
        channel requestedChannel: CityChannel,
        reset: Bool
    ) async {
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
            guard requestedChannel == channel else { return }
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
            } else {
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
            guard requestedChannel == channel else { return }
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
            canLoadMore = usedRemotePage
                ? (remoteHasMore || (requestedChannel == .hot && KaiXRuntimeFlags.allowLocalStoreFallback))
                : page.count == KaiXConfig.pageSize
            try await hydrate(context: context, repository: repository, currentUser: currentUser, postStore: postStore)
            guard requestedChannel == channel else { return }
            state = posts.isEmpty ? .empty : .loaded
        } catch {
            guard requestedChannel == channel else { return }
            state = posts.isEmpty ? .error(error.kaixUserMessage) : .loaded
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
        } catch {
            guard requestedChannel == channel else { return }
            pendingRemoteBundle = nil
        }
    }

    private func hydrate(context: ModelContext, repository: PostRepository, currentUser: UserEntity, postStore: PostStore) async throws {
        let originalPosts = try await repository.fetchPosts(
            ids: Set(posts.compactMap(\.repostOfPostId)),
            currentUserId: currentUser.id
        )
        let hydratedPosts = posts + originalPosts
        postStore.register(hydratedPosts)
        let users = try await UserRepository(context: context).fetchUsers(ids: Set(hydratedPosts.map(\.authorId)))
        authors = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
        mediaByPostId = try await repository.fetchMedia(for: hydratedPosts)
    }
}
