import Foundation
import SwiftData

@Model
final class NotificationEntity {
    @Attribute(.unique) var id: String
    var typeRaw: String
    var actorId: String
    var targetPostId: String?
    var targetCommentId: String?
    var content: String
    var isRead: Bool
    var createdAt: Date
    var updatedAt: Date
    var remoteId: String?
    var syncStatusRaw: String
    var deletedAt: Date?
    var cursor: String?

    init(
        id: String = UUID().uuidString,
        type: NotificationType,
        actorId: String,
        targetPostId: String? = nil,
        targetCommentId: String? = nil,
        content: String,
        isRead: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        remoteId: String? = nil,
        syncStatus: SyncStatus = .local,
        deletedAt: Date? = nil,
        cursor: String? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.actorId = actorId
        self.targetPostId = targetPostId
        self.targetCommentId = targetCommentId
        self.content = content
        self.isRead = isRead
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.remoteId = remoteId
        self.syncStatusRaw = syncStatus.rawValue
        self.deletedAt = deletedAt
        self.cursor = cursor
    }
}

extension NotificationEntity {
    var type: NotificationType {
        get { NotificationType(rawValue: typeRaw) ?? .system }
        set { typeRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .local }
        set {
            syncStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}
