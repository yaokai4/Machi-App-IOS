import Foundation

enum CommentLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)

    static func resolved(commentCount: Int, loadedComments: [CommentEntity]) -> CommentLoadState {
        if loadedComments.isEmpty {
            return commentCount == 0
                ? .empty
                : .failed("commentSyncError")
        }
        return .loaded
    }
}
