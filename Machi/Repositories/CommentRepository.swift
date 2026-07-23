import Foundation
import SwiftData

@MainActor
final class CommentRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchComments(postId: String) async throws -> [CommentEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            return try await KaiXAPIClient.shared.comments(postId: postId).map(ServerEntityFactory.comment(from:))
        }
        return try context.fetch(FetchDescriptor<CommentEntity>(
            predicate: #Predicate { $0.postId == postId && $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.likeCount, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        ))
    }

    func toggleLike(comment: CommentEntity) async throws {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            // Optimistic, same shape as PostStore.setLike: flip locally first so
            // the heart turns red the instant it's tapped (weak-network taps used
            // to sit dead for 1-2s), roll back if the request fails. CommentEntity
            // is a SwiftData @Model (Observable), so the row re-renders on mutation.
            let previousLiked = comment.isLikedByCurrentUser
            let previousCount = comment.likeCount
            let next = !previousLiked
            comment.isLikedByCurrentUser = next
            comment.likeCount = max(0, previousCount + (next ? 1 : -1))
            do {
                try await KaiXAPIClient.shared.setCommentLike(comment.id, next)
            } catch {
                comment.isLikedByCurrentUser = previousLiked
                comment.likeCount = previousCount
                throw error
            }
            return
        }
        comment.isLikedByCurrentUser.toggle()
        comment.likeCount = max(0, comment.likeCount + (comment.isLikedByCurrentUser ? 1 : -1))
        try context.save()
    }

    /// Mark/unmark a comment as the accepted best answer. Server enforces that
    /// only the question author may do this and that there is one per question.
    func acceptAnswer(comment: CommentEntity, on: Bool) async throws {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            try await KaiXAPIClient.shared.acceptAnswer(comment.id, on)
            comment.isAccepted = on
            return
        }
        comment.isAccepted = on
        try context.save()
    }
}
