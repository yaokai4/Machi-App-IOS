import Foundation

enum CommentLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)

    static func resolved(commentCount: Int, loadedComments: [CommentEntity]) -> CommentLoadState {
        // The loaded comments are the source of truth for display. A stale
        // server `commentCount` (comments later hidden/deleted, or a count that
        // includes filtered replies) must NOT surface as a scary
        // "评论数据正在同步，请重试" wall — that false positive showed up far too
        // often. Empty list ⇒ just show the empty state; genuine fetch failures
        // are surfaced upstream as the view-model's `.error` state instead.
        loadedComments.isEmpty ? .empty : .loaded
    }
}
