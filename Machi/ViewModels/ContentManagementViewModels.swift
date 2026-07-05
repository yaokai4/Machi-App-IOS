import Combine
import Foundation
import SwiftData

@MainActor
final class SavedContentViewModel: ObservableObject {
    @Published var posts: [PostEntity] = []
    @Published var mediaByPostId: [String: [MediaEntity]] = [:]
    @Published var authors: [String: UserEntity] = [:]
    @Published var state: ScreenState = .idle

    func loadBookmarks(context: ModelContext, postStore: PostStore? = nil) async {
        state = .loading
        do {
            let repository = PostRepository(context: context)
            posts = try await repository.fetchBookmarkedPosts()
            postStore?.register(posts)
            try await hydrate(context: context, posts: posts)
            state = posts.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func loadMediaPosts(context: ModelContext, currentUser: UserEntity, postStore: PostStore? = nil) async {
        state = .loading
        do {
            let repository = PostRepository(context: context)
            let authored = try await repository.fetchPosts(authorId: currentUser.id)
            let media = try await repository.fetchMedia(for: authored)
            posts = authored.filter { media[$0.id]?.isEmpty == false }
            postStore?.register(posts)
            mediaByPostId = media
            let users = try await UserRepository(context: context).fetchUsers(ids: Set(posts.map(\.authorId)))
            authors = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            state = posts.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func loadAuthoredPosts(context: ModelContext, currentUser: UserEntity, postStore: PostStore? = nil) async {
        state = .loading
        do {
            let repository = PostRepository(context: context)
            posts = try await repository.fetchPosts(authorId: currentUser.id)
            postStore?.register(posts)
            mediaByPostId = try await repository.fetchMedia(for: posts)
            let users = try await UserRepository(context: context).fetchUsers(ids: Set(posts.map(\.authorId)))
            authors = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            state = posts.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func toggleLike(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore? = nil, reload: @escaping () async -> Void) async {
        do {
            if let postStore {
                postStore.register(post)
                try await postStore.toggleLike(context: context, postId: post.id, currentUser: currentUser)
            } else {
                try await PostRepository(context: context).toggleLike(post: post, currentUserId: currentUser.id)
            }
            await reload()
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func toggleBookmark(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore? = nil, reload: @escaping () async -> Void) async {
        do {
            if let postStore {
                postStore.register(post)
                try await postStore.toggleBookmark(context: context, postId: post.id, currentUser: currentUser)
            } else {
                try await PostRepository(context: context).toggleBookmark(post: post, currentUserId: currentUser.id)
            }
            await reload()
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func repost(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore? = nil, reload: @escaping () async -> Void) async {
        do {
            if let postStore {
                postStore.register(post)
                try await postStore.toggleRepost(context: context, postId: post.id, currentUser: currentUser)
            } else {
                _ = try await PostRepository(context: context).repost(post: post, currentUserId: currentUser.id)
            }
            await reload()
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func quoteRepost(context: ModelContext, post: PostEntity, currentUser: UserEntity, content: String, postStore: PostStore? = nil, reload: @escaping () async -> Void) async {
        do {
            if let postStore {
                postStore.register(post)
                _ = try await postStore.quoteRepost(context: context, postId: post.id, currentUser: currentUser, content: content)
            } else {
                _ = try await PostRepository(context: context).quoteRepost(post: post, currentUserId: currentUser.id, content: content)
            }
            await reload()
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    private func hydrate(context: ModelContext, posts: [PostEntity]) async throws {
        let repository = PostRepository(context: context)
        mediaByPostId = try await repository.fetchMedia(for: posts)
        let users = try await UserRepository(context: context).fetchUsers(ids: Set(posts.map(\.authorId)))
        authors = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
    }
}

@MainActor
final class DraftsViewModel: ObservableObject {
    @Published var drafts: [PostEntity] = []
    @Published var mediaByPostId: [String: [MediaEntity]] = [:]
    @Published var state: ScreenState = .idle

    func load(context: ModelContext, currentUser: UserEntity) async {
        state = .loading
        do {
            let repository = PostRepository(context: context)
            drafts = try await repository.fetchDrafts(authorId: currentUser.id)
            mediaByPostId = try await repository.fetchMedia(for: drafts)
            state = drafts.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func publish(context: ModelContext, draft: PostEntity, currentUser: UserEntity) async {
        do {
            try await PostRepository(context: context).publishDraft(post: draft)
            await load(context: context, currentUser: currentUser)
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func updateAndPublish(context: ModelContext, draft: PostEntity, content: String, currentUser: UserEntity) async {
        do {
            let repository = PostRepository(context: context)
            try await repository.updateDraft(post: draft, content: content)
            try await repository.publishDraft(post: draft)
            await load(context: context, currentUser: currentUser)
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func delete(context: ModelContext, draft: PostEntity, currentUser: UserEntity) async {
        do {
            try await PostRepository(context: context).deletePost(post: draft)
            await load(context: context, currentUser: currentUser)
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}
