import Foundation
import Combine
import SwiftData

@MainActor
final class PostDetailViewModel: ObservableObject {
    @Published var post: PostEntity?
    @Published var originalPost: PostEntity?
    @Published var author: UserEntity?
    @Published var originalAuthor: UserEntity?
    @Published var comments: [CommentEntity] = []
    @Published var commentAuthors: [String: UserEntity] = [:]
    @Published var media: [MediaEntity] = []
    @Published var originalMedia: [MediaEntity] = []
    @Published var state: ScreenState = .idle
    @Published var commentState: CommentLoadState = .idle
    @Published var commentText = ""
    @Published var failedCommentDraft: PendingCommentDraft?
    @Published var transientCommentError: String?
    @Published var transientPostMessage: String?
    @Published var transientPostError: String?

    func load(context: ModelContext, postId: String, currentUser: UserEntity, postStore: PostStore, commentStore: CommentStore? = nil) async {
        let hasCachedPost = post?.id == postId
        if !hasCachedPost {
            state = .loading
            commentState = .idle
            commentStore?.setLoadingState(.loading, postId: postId)
            post = nil
            originalPost = nil
            author = nil
            originalAuthor = nil
            comments = []
            commentAuthors = [:]
            media = []
            originalMedia = []
        }
        do {
            let postRepository = PostRepository(context: context)
            guard let loadedPost = try await postRepository.fetchPost(id: postId, currentUserId: currentUser.id) else {
                state = .empty
                return
            }
            guard loadedPost.status.isPubliclyVisible else {
                state = .empty
                return
            }
            postStore.register(loadedPost)
            post = loadedPost
            state = .loaded
            let canonicalPostId = loadedPost.id

            try? await postRepository.incrementView(post: loadedPost)

            do {
                author = try await UserRepository(context: context).fetchUser(id: loadedPost.authorId)
            } catch {
                author = nil
            }

            do {
                media = try await postRepository.fetchMedia(postId: canonicalPostId)
            } catch {
                if !hasCachedPost {
                    media = []
                }
            }

            originalPost = nil
            originalAuthor = nil
            originalMedia = []
            if let originalPostId = loadedPost.repostOfPostId,
               let loadedOriginalPost = try await postRepository.fetchPost(id: originalPostId, currentUserId: currentUser.id) {
                originalPost = loadedOriginalPost
                postStore.register(loadedOriginalPost)
                originalAuthor = try? await UserRepository(context: context).fetchUser(id: loadedOriginalPost.authorId)
                originalMedia = (try? await postRepository.fetchMedia(postId: loadedOriginalPost.id)) ?? []
            }

            if comments.isEmpty {
                commentState = .loading
            }
            do {
                comments = try await CommentRepository(context: context).fetchComments(postId: canonicalPostId)
                commentState = CommentLoadState.resolved(commentCount: loadedPost.commentCount, loadedComments: comments)
                commentStore?.setComments(comments, postId: canonicalPostId, expectedCount: loadedPost.commentCount)
                let users = try await UserRepository(context: context).fetchUsers(ids: Set(comments.map(\.authorId)).union([loadedPost.authorId]))
                commentAuthors = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            } catch {
                commentState = .failed(error.kaixUserMessage)
                commentStore?.setLoadingState(commentState, postId: canonicalPostId)
            }
        } catch {
            if hasCachedPost {
                transientPostError = error.kaixUserMessage
                state = .loaded
            } else {
                state = .error(error.kaixUserMessage)
            }
        }
    }

    func reloadComments(context: ModelContext, commentStore: CommentStore? = nil) async {
        guard let post else { return }
        if comments.isEmpty {
            commentState = .loading
            commentStore?.setLoadingState(.loading, postId: post.id)
        }
        do {
            comments = try await CommentRepository(context: context).fetchComments(postId: post.id)
            commentState = CommentLoadState.resolved(commentCount: post.commentCount, loadedComments: comments)
            commentStore?.setComments(comments, postId: post.id, expectedCount: post.commentCount)
        } catch {
            commentState = .failed(error.kaixUserMessage)
            commentStore?.setLoadingState(commentState, postId: post.id)
        }
    }

    func sendComment(context: ModelContext, currentUser: UserEntity, postStore: PostStore, commentStore: CommentStore? = nil, parentCommentId: String? = nil) async {
        guard let post else { return }
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transientCommentError = nil

        let optimisticComment = CommentEntity(
            id: "optimistic-\(UUID().uuidString)",
            postId: post.id,
            authorId: currentUser.id,
            content: trimmed,
            parentCommentId: parentCommentId,
            createdAt: .now
        )
        comments.insert(optimisticComment, at: 0)
        commentStore?.insertOptimistic(optimisticComment)
        commentAuthors[currentUser.id] = currentUser
        commentText = ""
        postStore.updateCommentCount(postId: post.id, delta: 1)
        commentState = .loaded

        do {
            let saved = try await postStore.addComment(
                context: context,
                postId: post.id,
                currentUser: currentUser,
                content: trimmed,
                parentCommentId: parentCommentId
            )
            if let index = comments.firstIndex(where: { $0.id == optimisticComment.id }) {
                comments[index] = saved
            }
            commentStore?.replaceComment(id: optimisticComment.id, with: saved)
            failedCommentDraft = nil
            commentState = CommentLoadState.resolved(commentCount: post.commentCount, loadedComments: comments)
        } catch {
            comments.removeAll { $0.id == optimisticComment.id }
            commentStore?.removeComment(optimisticComment)
            postStore.updateCommentCount(postId: post.id, delta: -1)
            commentText = trimmed
            failedCommentDraft = PendingCommentDraft(content: trimmed, parentCommentId: parentCommentId)
            transientCommentError = error.kaixUserMessage
            commentState = CommentLoadState.resolved(commentCount: post.commentCount, loadedComments: comments)
            commentStore?.setLoadingState(commentState, postId: post.id)
        }
    }

    func retryFailedComment(context: ModelContext, currentUser: UserEntity, postStore: PostStore, commentStore: CommentStore? = nil) async {
        guard let draft = failedCommentDraft else { return }
        commentText = draft.content
        await sendComment(
            context: context,
            currentUser: currentUser,
            postStore: postStore,
            commentStore: commentStore,
            parentCommentId: draft.parentCommentId
        )
    }

    func deleteComment(context: ModelContext, comment: CommentEntity, postStore: PostStore, commentStore: CommentStore? = nil) async {
        guard let post else { return }
        let previousComments = comments
        let previousState = commentState
        transientCommentError = nil
        comments.removeAll { $0.id == comment.id || $0.parentCommentId == comment.id }
        commentStore?.removeComment(comment)
        do {
            try await postStore.deleteComment(context: context, comment: comment)
            commentState = CommentLoadState.resolved(commentCount: post.commentCount, loadedComments: comments)
        } catch {
            comments = previousComments
            commentState = previousState
            transientCommentError = error.kaixUserMessage
            commentStore?.setComments(previousComments, postId: post.id, expectedCount: post.commentCount)
            commentStore?.setLoadingState(commentState, postId: post.id)
        }
    }

    func toggleLike(context: ModelContext, currentUser: UserEntity, postStore: PostStore) async {
        guard let post else { return }
        do {
            try await postStore.toggleLike(context: context, postId: post.id, currentUser: currentUser)
        } catch {
            transientPostError = error.kaixUserMessage
        }
    }

    func toggleBookmark(context: ModelContext, currentUser: UserEntity, postStore: PostStore) async {
        guard let post else { return }
        do {
            try await postStore.toggleBookmark(context: context, postId: post.id, currentUser: currentUser)
        } catch {
            transientPostError = error.kaixUserMessage
        }
    }

    func repost(context: ModelContext, currentUser: UserEntity, postStore: PostStore) async {
        guard let post else { return }
        do {
            try await postStore.toggleRepost(context: context, postId: post.id, currentUser: currentUser)
        } catch {
            transientPostError = error.kaixUserMessage
        }
    }

    func quoteRepost(context: ModelContext, currentUser: UserEntity, content: String, postStore: PostStore) async {
        guard let post else { return }
        do {
            _ = try await postStore.quoteRepost(context: context, postId: post.id, currentUser: currentUser, content: content)
        } catch {
            transientPostError = error.kaixUserMessage
        }
    }

    func toggleCommentLike(context: ModelContext, comment: CommentEntity) async {
        do {
            try await CommentRepository(context: context).toggleLike(comment: comment)
        } catch {
            transientCommentError = error.kaixUserMessage
        }
    }

    func updatePost(context: ModelContext, content: String, postStore: PostStore) async -> Bool {
        guard let post else { return false }
        transientPostError = nil
        do {
            try await postStore.updatePost(context: context, postId: post.id, content: content)
            self.post = postStore.post(id: post.id) ?? post
            transientPostMessage = "帖子已更新。"
            return true
        } catch {
            transientPostError = error.kaixUserMessage
            return false
        }
    }

    func deletePost(context: ModelContext, postStore: PostStore) async -> Bool {
        guard let post else { return false }
        transientPostError = nil
        do {
            try await postStore.deletePost(context: context, postId: post.id)
            self.post = nil
            originalPost = nil
            author = nil
            originalAuthor = nil
            comments = []
            commentAuthors = [:]
            media = []
            originalMedia = []
            state = .empty
            commentState = .idle
            transientPostMessage = "帖子已删除。"
            return true
        } catch {
            transientPostError = error.kaixUserMessage
            return false
        }
    }
}

struct PendingCommentDraft: Equatable {
    let content: String
    let parentCommentId: String?
}
