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
            if reset, KaiXBackend.token != nil {
                _ = try? await RemoteSyncService.shared.syncFeed(
                    mode: channel == .hot ? .hot : .recommend,
                    country: region.countryCode,
                    province: region.provinceCode.isEmpty ? nil : region.provinceCode,
                    city: region.cityCode,
                    contentTypes: channel.contentTypes,
                    context: context
                )
            }
            let repository = PostRepository(context: context)
            let page = try await repository.fetchCityPage(
                region: region,
                channel: channel,
                currentUserId: currentUser.id,
                page: currentPage,
                pageSize: KaiXConfig.pageSize
            )
            if reset {
                posts = page
            } else {
                posts.append(contentsOf: page)
            }
            postStore.register(posts)
            currentPage += 1
            canLoadMore = page.count == KaiXConfig.pageSize
            try await hydrate(context: context, repository: repository, currentUser: currentUser, postStore: postStore)
            state = posts.isEmpty ? .empty : .loaded
        } catch {
            state = posts.isEmpty ? .error(error.kaixUserMessage) : .loaded
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
