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
        transientError = nil

        let userId = user.id
        let repository = PostRepository(context: context)
        var sectionErrors: [String] = []

        if user.isGuest {
            authoredPosts = []
            repliedPosts = []
            likedPosts = []
            bookmarkedPosts = []
            mediaPosts = []
            posts = []
            authors = [user.id: user]
            mediaByPostId = [:]
            postCount = 0
            replyCount = 0
            likeCount = 0
            bookmarkCount = 0
            mediaCount = 0
            draftCount = 0
            totalHeat = 0
            savedByOthersCount = 0
            contentTypeCounts = [:]
            postStore?.setProfilePosts([], userId: userId)
            state = .empty
            return
        }

        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            if let remoteUser = try? await UserRepository(context: context).fetchUser(id: userId) {
                UserRepository.apply(remoteUser, to: user)
            }
        }

        do {
            authoredPosts = Self.uniquePosts(try await repository.fetchPosts(authorId: userId))
        } catch {
            if !hasCachedContent { authoredPosts = [] }
            sectionErrors.append(error.kaixUserMessage)
        }

        do {
            repliedPosts = Self.uniquePosts(try await repository.fetchRepliedPosts(authorId: userId))
        } catch {
            if !hasCachedContent { repliedPosts = [] }
            sectionErrors.append(error.kaixUserMessage)
        }

        do {
            mediaPosts = Self.uniquePosts(try await repository.fetchMediaPosts(authorId: userId))
        } catch {
            if !hasCachedContent { mediaPosts = [] }
            sectionErrors.append(error.kaixUserMessage)
        }

        let authenticatedCurrentUserId = AuthService.shared.currentUserId
        let canLoadPrivateProfileData = KaiXBackend.token != nil && !authenticatedCurrentUserId.isEmpty && authenticatedCurrentUserId == userId
        do {
            likedPosts = Self.uniquePosts(try await repository.fetchLikedPosts(userId: userId))
        } catch {
            if !hasCachedContent { likedPosts = [] }
            sectionErrors.append(error.kaixUserMessage)
        }

        if canLoadPrivateProfileData {
            do {
                bookmarkedPosts = Self.uniquePosts(try await repository.fetchBookmarkedPosts())
            } catch {
                if !hasCachedContent { bookmarkedPosts = [] }
                sectionErrors.append(error.kaixUserMessage)
            }
        } else {
            bookmarkedPosts = []
        }

        var hydratedById: [String: PostEntity] = [:]
        for post in authoredPosts + repliedPosts + likedPosts + bookmarkedPosts + mediaPosts {
            hydratedById[post.id] = post
        }

        if !hydratedById.isEmpty {
            let originalIds = Set(hydratedById.values.compactMap(\.repostOfPostId))
            if let originalPosts = try? await repository.fetchPosts(ids: originalIds, currentUserId: userId) {
                for post in originalPosts {
                    hydratedById[post.id] = post
                }
            }
        }

        let hydratedPosts = Array(hydratedById.values)
        postStore?.register(hydratedPosts)
        postStore?.setProfilePosts(authoredPosts, userId: userId)

        let fetchedUsers = (try? await UserRepository(context: context).fetchUsers(ids: Set(hydratedPosts.map(\.authorId)).union([userId]))) ?? [user]
        var nextAuthors: [String: UserEntity] = [user.id: user]
        for fetchedUser in fetchedUsers {
            nextAuthors[fetchedUser.id] = fetchedUser
        }
        authors = nextAuthors

        var nextMediaByPostId = (try? await repository.fetchMedia(for: hydratedPosts)) ?? [:]
        for mediaPost in mediaPosts where nextMediaByPostId[mediaPost.id] == nil {
            nextMediaByPostId[mediaPost.id] = []
        }
        mediaByPostId = nextMediaByPostId
        if mediaPosts.isEmpty {
            mediaPosts = authoredPosts.filter { !(mediaByPostId[$0.id] ?? []).isEmpty }
        }

        postCount = authoredPosts.count
        totalHeat = authoredPosts.reduce(0) { $0 + $1.heatScore }
        contentTypeCounts = Dictionary(grouping: authoredPosts, by: \.contentType)
            .mapValues(\.count)
        savedByOthersCount = authoredPosts.reduce(0) { $0 + $1.bookmarkCount }
        likeCount = likedPosts.count
        bookmarkCount = bookmarkedPosts.count
        mediaCount = mediaItemCount(in: mediaPosts)
        replyCount = repliedPosts.count
        if canLoadPrivateProfileData, let drafts = try? await repository.fetchDrafts(authorId: userId) {
            draftCount = drafts.count
        } else {
            draftCount = 0
        }

        refreshSelectedPosts()
        if let firstError = sectionErrors.first {
            transientError = firstError
        }
        state = posts.isEmpty ? .empty : .loaded
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

        if profileUser.id == currentUser.id, let insertedPost, insertedPost.id != changedPost.id {
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
        mediaCount = mediaItemCount(in: mediaPosts)

        refreshSelectedPosts()
        postStore?.setProfilePosts(authoredPosts, userId: profileUser.id)
        state = .loaded
    }

    private func refreshSelectedPosts() {
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
    }

    private func prependIfNeeded(_ post: PostEntity, to posts: inout [PostEntity]) {
        posts.removeAll { $0.id == post.id }
        posts.insert(post, at: 0)
    }

    private func mediaItemCount(in posts: [PostEntity]) -> Int {
        posts.reduce(0) { total, post in
            let count = mediaByPostId[post.id]?.count ?? 0
            return total + max(count, 1)
        }
    }

    private static func uniquePosts(_ posts: [PostEntity]) -> [PostEntity] {
        var seen = Set<String>()
        return posts.filter { seen.insert($0.id).inserted }
    }
}
