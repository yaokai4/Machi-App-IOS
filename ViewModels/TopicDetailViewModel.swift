import Combine
import SwiftData
import SwiftUI

@MainActor
final class TopicDetailViewModel: ObservableObject {
    @Published var state: ScreenState = .idle
    @Published var topic: TopicEntity?
    @Published var posts: [PostEntity] = []
    @Published var authors: [String: UserEntity] = [:]
    @Published var mediaByPostId: [String: [MediaEntity]] = [:]

    func load(context: ModelContext, topicName: String, postStore: PostStore? = nil) async {
        state = .loading
        do {
            let topicRepository = TopicRepository(context: context)
            let postRepository = PostRepository(context: context)
            topic = try await topicRepository.fetchTopic(name: topicName)
            let loadedPosts = try await postRepository.fetchPosts(topic: topicName)
            let originalPosts = try await postRepository.fetchPosts(
                ids: Set(loadedPosts.compactMap(\.repostOfPostId))
            )
            let hydratedPosts = loadedPosts + originalPosts
            let users = try await UserRepository(context: context).fetchUsers(ids: Set(hydratedPosts.map(\.authorId)))
            posts = loadedPosts
            postStore?.register(hydratedPosts)
            authors = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            mediaByPostId = try await postRepository.fetchMedia(for: hydratedPosts)
            state = loadedPosts.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func toggleLike(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore? = nil) async {
        do {
            if let postStore {
                postStore.register(post)
                try await postStore.toggleLike(context: context, postId: post.id, currentUser: currentUser)
            } else {
                try await PostRepository(context: context).toggleLike(post: post, currentUserId: currentUser.id)
            }
            posts = posts.map { $0 }
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func toggleBookmark(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore? = nil) async {
        do {
            if let postStore {
                postStore.register(post)
                try await postStore.toggleBookmark(context: context, postId: post.id, currentUser: currentUser)
            } else {
                try await PostRepository(context: context).toggleBookmark(post: post, currentUserId: currentUser.id)
            }
            posts = posts.map { $0 }
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func repost(context: ModelContext, post: PostEntity, currentUser: UserEntity, postStore: PostStore? = nil) async {
        do {
            if let postStore {
                postStore.register(post)
                try await postStore.toggleRepost(context: context, postId: post.id, currentUser: currentUser)
            } else {
                _ = try await PostRepository(context: context).repost(post: post, currentUserId: currentUser.id)
            }
            posts = posts.map { $0 }
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    func quoteRepost(context: ModelContext, post: PostEntity, currentUser: UserEntity, content: String, postStore: PostStore? = nil) async {
        do {
            if let postStore {
                postStore.register(post)
                _ = try await postStore.quoteRepost(context: context, postId: post.id, currentUser: currentUser, content: content)
            } else {
                _ = try await PostRepository(context: context).quoteRepost(post: post, currentUserId: currentUser.id, content: content)
            }
            posts = posts.map { $0 }
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}
