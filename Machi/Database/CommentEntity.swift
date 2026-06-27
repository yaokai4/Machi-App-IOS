import Foundation
import SwiftData

@Model
final class CommentEntity {
    @Attribute(.unique) var id: String
    var postId: String
    var authorId: String
    var content: String
    var parentCommentId: String?
    var likeCount: Int
    var isLikedByCurrentUser: Bool
    var createdAt: Date
    var updatedAt: Date
    var remoteId: String?
    var syncStatusRaw: String
    var deletedAt: Date?
    var cursor: String?
    /// Whether the question author marked this answer as the accepted best answer.
    /// Defaulted so SwiftData lightweight migration backfills existing rows.
    var isAccepted: Bool = false

    init(
        id: String = UUID().uuidString,
        postId: String,
        authorId: String,
        content: String,
        parentCommentId: String? = nil,
        likeCount: Int = 0,
        isLikedByCurrentUser: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        remoteId: String? = nil,
        syncStatus: SyncStatus = .local,
        deletedAt: Date? = nil,
        cursor: String? = nil,
        isAccepted: Bool = false
    ) {
        self.id = id
        self.postId = postId
        self.authorId = authorId
        self.content = content
        self.parentCommentId = parentCommentId
        self.likeCount = likeCount
        self.isLikedByCurrentUser = isLikedByCurrentUser
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteId = remoteId
        self.syncStatusRaw = syncStatus.rawValue
        self.deletedAt = deletedAt
        self.cursor = cursor
        self.isAccepted = isAccepted
    }
}

extension CommentEntity {
    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .local }
        set {
            syncStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}
