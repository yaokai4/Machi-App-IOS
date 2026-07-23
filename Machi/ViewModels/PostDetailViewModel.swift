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
    @Published var transientPostError: String?
    /// Ids of comments the current user posted in THIS detail session (newest
    /// first). The view pins them to the top of the list so a fresh 0-like
    /// comment isn't immediately buried by the "hot" sort — the classic
    /// "did my comment fail to post?" moment. Cleared whenever the thread is
    /// re-fetched from the server, so a refresh restores natural ordering.
    @Published private(set) var sessionCommentIds: [String] = []

    func load(context: ModelContext, postId: String, currentUser: UserEntity, postStore: PostStore, commentStore: CommentStore? = nil) async {
        let cachedPost = postStore.post(id: postId)
        let hasVisiblePost = post?.id == postId || cachedPost != nil
        if let cachedPost, post?.id != postId {
            post = cachedPost
            state = .loaded
            let cachedComments = commentStore?.commentsByPostId[postId] ?? []
            comments = cachedComments
            commentState = commentStore?.loadingStateByPostId[postId]
                ?? (cachedComments.isEmpty && cachedPost.commentCount > 0
                    ? .loading
                    : CommentLoadState.resolved(commentCount: cachedPost.commentCount, loadedComments: cachedComments))
        }
        if !hasVisiblePost {
            state = .loading
            commentState = .idle
            commentStore?.setLoadingState(.loading, postId: postId)
            post = nil
            originalPost = nil
            author = nil
            originalAuthor = nil
            comments = []
            sessionCommentIds = []
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

            // View counting is telemetry, not content — fire-and-forget so it
            // never adds an RTT to the critical path of first render.
            Task { try? await postRepository.incrementView(post: loadedPost) }

            if comments.isEmpty {
                commentState = .loading
            }

            // 冷开详情曾是 6-7 次串行往返的瀑布(author → media → 原帖链 →
            // comments 逐个 await),弱网 500ms RTT 下评论要 3-4 秒才出现。
            // fetchPost 之后这四路互不依赖,并发发出,首屏压到 ~2×RTT。
            let userRepository = UserRepository(context: context)
            async let authorFetch = try? userRepository.fetchUser(id: loadedPost.authorId)
            async let mediaFetch = try? postRepository.fetchMedia(postId: canonicalPostId)
            async let originalFetch = loadOriginalBundle(
                context: context,
                repostOfPostId: loadedPost.repostOfPostId,
                currentUser: currentUser
            )
            async let commentsFetch = loadCommentsResult(context: context, postId: canonicalPostId)

            author = (await authorFetch) ?? nil
            if let loadedMedia = await mediaFetch {
                media = loadedMedia
            } else if !hasVisiblePost {
                media = []
            }

            if let bundle = await originalFetch {
                originalPost = bundle.post
                postStore.register(bundle.post)
                originalAuthor = bundle.author
                originalMedia = bundle.media
            } else {
                originalPost = nil
                originalAuthor = nil
                originalMedia = []
            }

            switch await commentsFetch {
            case .success(let loadedComments):
                sessionCommentIds = []
                comments = loadedComments
                commentState = CommentLoadState.resolved(commentCount: loadedPost.commentCount, loadedComments: comments)
                commentStore?.setComments(comments, postId: canonicalPostId, expectedCount: loadedPost.commentCount)
                do {
                    let users = try await userRepository.fetchUsers(ids: Set(comments.map(\.authorId)).union([loadedPost.authorId]))
                    commentAuthors = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
                } catch {
                    // Author lookups failing shouldn't hide the comments — rows
                    // degrade to the "unknown user" placeholder name.
                }
            case .failure(let error):
                commentState = .failed(error.kaixUserMessage)
                commentStore?.setLoadingState(commentState, postId: canonicalPostId)
            }
        } catch {
            if error.isKaiXResourceNotFound {
                post = nil
                state = .empty
                return
            }
            if hasVisiblePost {
                transientPostError = error.kaixUserMessage
                state = .loaded
            } else {
                state = .error(error.kaixUserMessage)
            }
        }
    }

    /// Original-post bundle for a repost, loaded as one unit (post → author +
    /// media concurrently). Degrades to nil instead of throwing: a deleted or
    /// unreachable original should render the wrapper without the quote card,
    /// not error out the whole detail page.
    private func loadOriginalBundle(
        context: ModelContext,
        repostOfPostId: String?,
        currentUser: UserEntity
    ) async -> (post: PostEntity, author: UserEntity?, media: [MediaEntity])? {
        guard let originalPostId = repostOfPostId else { return nil }
        let postRepository = PostRepository(context: context)
        guard let originalPost = try? await postRepository.fetchPost(id: originalPostId, currentUserId: currentUser.id) else {
            return nil
        }
        async let authorFetch = try? UserRepository(context: context).fetchUser(id: originalPost.authorId)
        async let mediaFetch = try? postRepository.fetchMedia(postId: originalPost.id)
        return (originalPost, (await authorFetch) ?? nil, (await mediaFetch) ?? [])
    }

    /// Comments fetch wrapped in a Result so it can run under `async let`
    /// while preserving the error message for `commentState = .failed(...)`.
    private func loadCommentsResult(context: ModelContext, postId: String) async -> Result<[CommentEntity], Error> {
        do {
            return .success(try await CommentRepository(context: context).fetchComments(postId: postId))
        } catch {
            return .failure(error)
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
            sessionCommentIds = []
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
        sessionCommentIds.insert(optimisticComment.id, at: 0)
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
            if let index = sessionCommentIds.firstIndex(of: optimisticComment.id) {
                sessionCommentIds[index] = saved.id
            }
            commentStore?.replaceComment(id: optimisticComment.id, with: saved)
            failedCommentDraft = nil
            commentState = CommentLoadState.resolved(commentCount: post.commentCount, loadedComments: comments)
        } catch {
            comments.removeAll { $0.id == optimisticComment.id }
            sessionCommentIds.removeAll { $0 == optimisticComment.id }
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
        sessionCommentIds.removeAll { $0 == comment.id }
        // Authoritative count of what actually left the loaded thread (parent +
        // its loaded replies) so post.commentCount, the list, and CommentStore
        // all move by the same amount — a plain SwiftData descendant fetch is
        // empty in production and would only decrement the header by 1.
        let removedCount = previousComments.count - comments.count
        commentStore?.removeComment(comment)
        do {
            try await postStore.deleteComment(context: context, comment: comment, removedCount: removedCount)
            commentState = CommentLoadState.resolved(commentCount: post.commentCount, loadedComments: comments)
        } catch {
            comments = previousComments
            commentState = previousState
            transientCommentError = error.kaixUserMessage
            commentStore?.setComments(previousComments, postId: post.id, expectedCount: post.commentCount)
            commentStore?.setLoadingState(commentState, postId: post.id)
        }
    }

    /// The post the on-screen interaction bar and counts refer to. For a
    /// plain (non-quote) repost, PostCardView renders the ORIGINAL, so
    /// like/bookmark/repost must target the original too — otherwise taps
    /// toggle the wrapper while the visible counts belong to the original.
    var interactionTarget: PostEntity? {
        if let original = originalPost, let post, post.previewText.isEmpty {
            return original
        }
        return post
    }

    func toggleLike(context: ModelContext, currentUser: UserEntity, postStore: PostStore) async {
        guard let target = interactionTarget else { return }
        do {
            try await postStore.toggleLike(context: context, postId: target.id, currentUser: currentUser)
        } catch {
            transientPostError = error.kaixUserMessage
        }
    }

    func toggleBookmark(context: ModelContext, currentUser: UserEntity, postStore: PostStore) async {
        guard let target = interactionTarget else { return }
        do {
            try await postStore.toggleBookmark(context: context, postId: target.id, currentUser: currentUser)
        } catch {
            transientPostError = error.kaixUserMessage
        }
    }

    func repost(context: ModelContext, currentUser: UserEntity, postStore: PostStore) async {
        guard let target = interactionTarget else { return }
        do {
            try await postStore.toggleRepost(context: context, postId: target.id, currentUser: currentUser)
        } catch {
            transientPostError = error.kaixUserMessage
        }
    }

    func quoteRepost(context: ModelContext, currentUser: UserEntity, content: String, postStore: PostStore) async {
        guard let target = interactionTarget else { return }
        do {
            _ = try await postStore.quoteRepost(context: context, postId: target.id, currentUser: currentUser, content: content)
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

    /// Accept (or un-accept) an answer as the best answer for a question post.
    /// Only meaningful when the current user authored the question.
    func acceptAnswer(context: ModelContext, comment: CommentEntity) async {
        let next = !comment.isAccepted
        do {
            try await CommentRepository(context: context).acceptAnswer(comment: comment, on: next)
            if next {
                // One accepted answer per question — clear any previous one locally.
                for other in comments where other.id != comment.id && other.isAccepted {
                    other.isAccepted = false
                }
            }
            // Reassign so the @Published array republishes (badge + reorder reflect immediately).
            comments = comments
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
            sessionCommentIds = []
            state = .empty
            commentState = .idle
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
