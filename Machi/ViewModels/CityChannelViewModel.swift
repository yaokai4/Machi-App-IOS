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

    func configure(regionCode: String, channel: CityChannel = .recommend) {
        region = KaiXRegionDirectory.resolve(regionCode: regionCode)
        self.channel = channel
    }

    func loadInitial(context: ModelContext, currentUser: UserEntity, postStore: PostStore, clearExisting: Bool = false) async {
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
        await loadPage(context: context, currentUser: currentUser, postStore: postStore, region: region, reset: true)
    }

    func loadMoreIfNeeded(context: ModelContext, currentUser: UserEntity, post: PostEntity?, postStore: PostStore) async {
        guard let region, canLoadMore, !isLoadingMore else { return }
        guard post == nil || post?.id == posts.last?.id else { return }
        await loadPage(context: context, currentUser: currentUser, postStore: postStore, region: region, reset: false)
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
                await syncFromRemote(context: context, region: region, cursor: reset ? nil : remoteCursor)
            }
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
                    channel: channel,
                    currentUserId: currentUser.id,
                    page: currentPage,
                    pageSize: KaiXConfig.pageSize
                )
            }
            let appended = page.filter { !loadedIds.contains($0.id) }
            posts = reset ? page : posts + appended
            loadedIds = Set(posts.map(\.id))
            postStore.register(posts)
            currentPage += 1
            // Hot has no server cursor (single ranked page) — after it,
            // deterministic local windows keep deeper browsing alive.
            canLoadMore = usedRemotePage
                ? (remoteHasMore || channel == .hot)
                : page.count == KaiXConfig.pageSize
            try await hydrate(context: context, repository: repository, currentUser: currentUser, postStore: postStore)
            state = posts.isEmpty ? .empty : .loaded
        } catch {
            state = posts.isEmpty ? .error(error.kaixUserMessage) : .loaded
        }
    }

    /// Pull one server page for this city/channel and remember its ids +
    /// cursor. Best-effort: on failure the local cache keeps the view alive.
    private func syncFromRemote(context: ModelContext, region: KaiXRegionDirectory.Region, cursor: String?) async {
        do {
            let page = try await KaiXAPIClient.shared.feed(
                mode: channel == .hot ? .hot : .recommend,
                cursor: cursor,
                regionCode: region.regionCode,
                country: region.countryCode,
                province: region.provinceCode.isEmpty ? nil : region.provinceCode,
                city: region.cityCode,
                contentTypes: channel.contentTypes
            )
            remoteCursor = page.next_cursor
            remoteHasMore = page.next_cursor != nil && !page.items.isEmpty
            pendingRemoteBundle = page.items.isEmpty ? nil : ServerEntityFactory.postBundle(from: page.items)
        } catch {
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
