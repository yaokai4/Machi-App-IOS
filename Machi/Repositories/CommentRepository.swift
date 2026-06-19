import Foundation
import SwiftData

@MainActor
final class CommentRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchComments(postId: String) async throws -> [CommentEntity] {
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
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
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            let next = !comment.isLikedByCurrentUser
            try await KaiXAPIClient.shared.setCommentLike(comment.id, next)
            comment.isLikedByCurrentUser = next
            comment.likeCount = max(0, comment.likeCount + (next ? 1 : -1))
            return
        }
        comment.isLikedByCurrentUser.toggle()
        comment.likeCount = max(0, comment.likeCount + (comment.isLikedByCurrentUser ? 1 : -1))
        try context.save()
    }
}
