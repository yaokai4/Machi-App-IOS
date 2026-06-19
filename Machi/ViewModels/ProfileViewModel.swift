import Foundation
import Combine
import SwiftData

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var segment: ProfileSegment = .posts
    @Published var posts: [PostEntity] = []
    @Published var authoredPosts: [PostEntity] = []
    @Published var repliedPosts: [PostEntity] = []
    @Published var likedPosts: [PostEntity] = []
    @Published var bookmarkedPosts: [PostEntity] = []
    @Published var mediaPosts: [PostEntity] = []
    @Published var authors: [String: UserEntity] = [:]
    @Published var mediaByPostId: [String: [MediaEntity]] = [:]
    @Published var postCount = 0
    @Published var replyCount = 0
    @Published var likeCount = 0
    @Published var bookmarkCount = 0
    @Published var mediaCount = 0
    @Published var draftCount = 0
    @Published var totalHeat: Double = 0
    @Published var savedByOthersCount = 0
    @Published var contentTypeCounts: [ContentType: Int] = [:]
    @Published var state: ScreenState = .idle
    @Published var transientError: String?

    func load(context: ModelContext, user: UserEntity, postStore: PostStore? = nil) async {
        let hasCachedContent = !authoredPosts.isEmpty || !repliedPosts.isEmpty || !likedPosts.isEmpty || !mediaPosts.isEmpty
        if !hasCachedContent {
            state = .loading
        }
        do {
            let userId = user.id
            let draftStatus = PostStatus.draft.rawValue
            if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
                if let remoteUser = try await UserRepository(context: context).fetchUser(id: userId) {
                    UserRepository.apply(remoteUser, to: user)
                }
            }
            let repository = PostRepository(context: context)
            authoredPosts = try await repository.fetchPosts(authorId: user.id)
            repliedPosts = try await repository.fetchRepliedPosts(authorId: user.id)
            likedPosts = try await repository.fetchLikedPosts()
            bookmarkedPosts = try await repository.fetchBookmarkedPosts()
            postStore?.register(authoredPosts + repliedPosts + likedPosts + bookmarkedPosts)
            let authoredMedia = try await repository.fetchMedia(for: authoredPosts)
            mediaPosts = authoredPosts.filter { authoredMedia[$0.id]?.isEmpty == false }

            postCount = authoredPosts.count
            totalHeat = authoredPosts.reduce(0) { $0 + $1.heatScore }
            contentTypeCounts = Dictionary(grouping: authoredPosts, by: \.contentType)
                .mapValues(\.count)
            savedByOthersCount = authoredPosts.reduce(0) { $0 + $1.bookmarkCount }
            likeCount = likedPosts.count
            bookmarkCount = bookmarkedPosts.count
            mediaCount = authoredMedia.values.reduce(0) { $0 + $1.count }
            replyCount = try context.fetch(FetchDescriptor<CommentEntity>(
                predicate: #Predicate { $0.authorId == userId && $0.deletedAt == nil }
            )).count
            draftCount = try context.fetch(FetchDescriptor<PostEntity>(
                predicate: #Predicate { $0.authorId == userId && $0.statusRaw == draftStatus }
            )).count

            switch segment {
            case .posts:
                posts = authoredPosts
            case .replies:
                posts = repliedPosts
            case .media:
                posts = mediaPosts
            case .likes:
                posts = likedPosts
            case .bookmarks:
                posts = bookmarkedPosts
            }
            var hydratedById: [String: PostEntity] = [:]
            for post in authoredPosts + repliedPosts + likedPosts + bookmarkedPosts + mediaPosts {
                hydratedById[post.id] = post
            }
            let originalPosts = try await repository.fetchPosts(
                ids: Set(hydratedById.values.compactMap(\.repostOfPostId)),
                currentUserId: user.id
            )
            for post in originalPosts {
                hydratedById[post.id] = post
            }
            let hydratedPosts = Array(hydratedById.values)
            postStore?.register(hydratedPosts)
            postStore?.setProfilePosts(authoredPosts, userId: user.id)
            let users = try await UserRepository(context: context).fetchUsers(ids: Set(hydratedPosts.map(\.authorId)).union([user.id]))
            authors = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            mediaByPostId = try await repository.fetchMedia(for: hydratedPosts)
            state = posts.isEmpty ? .empty : .loaded
        } catch {
            if hasCachedContent {
                transientError = error.kaixUserMessage
                state = .loaded
            } else {
                state = .error(error.kaixUserMessage)
            }
        }
    }

    func toggleLike(context: ModelContext, post: PostEntity, currentUser: UserEntity, profileUser: UserEntity, postStore: PostStore? = nil) async {
        do {
            if let postStore {
                postStore.register(post)
                try await postStore.toggleLike(context: context, postId: post.id, currentUser: currentUser)
            } else {
                try await PostRepository(context: context).toggleLike(post: post, currentUserId: currentUser.id)
            }
            syncInteractionState(changedPost: post, currentUser: currentUser, profileUser: profileUser, postStore: postStore)
        } catch {
            transientError = error.kaixUserMessage
        }
    }

    func toggleBookmark(context: ModelContext, post: PostEntity, currentUser: UserEntity, profileUser: UserEntity, postStore: PostStore? = nil) async {
        do {
            if let postStore {
                postStore.register(post)
                try await postStore.toggleBookmark(context: context, postId: post.id, currentUser: currentUser)
            } else {
                try await PostRepository(context: context).toggleBookmark(post: post, currentUserId: currentUser.id)
            }
            syncInteractionState(changedPost: post, currentUser: currentUser, profileUser: profileUser, postStore: postStore)
        } catch {
            transientError = error.kaixUserMessage
        }
    }

    func repost(context: ModelContext, post: PostEntity, currentUser: UserEntity, profileUser: UserEntity, postStore: PostStore? = nil) async {
        do {
            let repost: PostEntity?
            if let postStore {
                postStore.register(post)
                repost = try await postStore.toggleRepost(context: context, postId: post.id, currentUser: currentUser)
            } else {
                repost = try await PostRepository(context: context).repost(post: post, currentUserId: currentUser.id)
            }
            syncInteractionState(changedPost: post, currentUser: currentUser, profileUser: profileUser, insertedPost: repost, postStore: postStore)
        } catch {
            transientError = error.kaixUserMessage
        }
    }

    func quoteRepost(context: ModelContext, post: PostEntity, currentUser: UserEntity, profileUser: UserEntity, content: String, postStore: PostStore? = nil) async {
        do {
            let quote: PostEntity
            if let postStore {
                postStore.register(post)
                quote = try await postStore.quoteRepost(context: context, postId: post.id, currentUser: currentUser, content: content)
            } else {
                quote = try await PostRepository(context: context).quoteRepost(post: post, currentUserId: currentUser.id, content: content)
            }
            syncInteractionState(changedPost: post, currentUser: currentUser, profileUser: profileUser, insertedPost: quote, postStore: postStore)
        } catch {
            transientError = error.kaixUserMessage
        }
    }

    private func syncInteractionState(
        changedPost: PostEntity,
        currentUser: UserEntity,
        profileUser: UserEntity,
        insertedPost: PostEntity? = nil,
        postStore: PostStore? = nil
    ) {
        postStore?.register(changedPost)

        if changedPost.isLikedByCurrentUser {
            prependIfNeeded(changedPost, to: &likedPosts)
        } else {
            likedPosts.removeAll { $0.id == changedPost.id }
        }

        if changedPost.isBookmarkedByCurrentUser {
            prependIfNeeded(changedPost, to: &bookmarkedPosts)
        } else {
            bookmarkedPosts.removeAll { $0.id == changedPost.id }
        }

        if changedPost.isRepostedByCurrentUser == false {
            authoredPosts.removeAll {
                $0.authorId == currentUser.id
                && $0.repostOfPostId == changedPost.id
                && $0.previewText.isEmpty
            }
        }

        if profileUser.id == currentUser.id, let insertedPost {
            postStore?.register(insertedPost)
            prependIfNeeded(insertedPost, to: &authoredPosts)
            authors[currentUser.id] = currentUser
            mediaByPostId[insertedPost.id] = mediaByPostId[insertedPost.id] ?? []
        }

        postCount = authoredPosts.count
        totalHeat = authoredPosts.reduce(0) { $0 + $1.heatScore }
        contentTypeCounts = Dictionary(grouping: authoredPosts, by: \.contentType)
            .mapValues(\.count)
        savedByOthersCount = authoredPosts.reduce(0) { $0 + $1.bookmarkCount }
        likeCount = likedPosts.count
        bookmarkCount = bookmarkedPosts.count
        mediaPosts = authoredPosts.filter { mediaByPostId[$0.id]?.isEmpty == false }
        mediaCount = mediaByPostId.values.reduce(0) { $0 + $1.count }

        switch segment {
        case .posts:
            posts = authoredPosts
        case .replies:
            posts = repliedPosts
        case .media:
            posts = mediaPosts
        case .likes:
            posts = likedPosts
        case .bookmarks:
            posts = bookmarkedPosts
        }
        postStore?.setProfilePosts(authoredPosts, userId: profileUser.id)
        state = .loaded
    }

    private func prependIfNeeded(_ post: PostEntity, to posts: inout [PostEntity]) {
        posts.removeAll { $0.id == post.id }
        posts.insert(post, at: 0)
    }
}
