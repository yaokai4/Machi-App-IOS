import Foundation
import SwiftData

@Model
final class MessageThreadEntity {
    @Attribute(.unique) var id: String
    var participantIdsRaw: String
    var lastMessage: String
    var lastMessageAt: Date
    var unreadCount: Int
    var updatedAt: Date
    var remoteId: String?
    var syncStatusRaw: String
    var deletedAt: Date?
    var cursor: String?

    init(
        id: String = UUID().uuidString,
        participantIds: [String],
        lastMessage: String = "",
        lastMessageAt: Date = .now,
        unreadCount: Int = 0,
        updatedAt: Date = .now,
        remoteId: String? = nil,
        syncStatus: SyncStatus = .local,
        deletedAt: Date? = nil,
        cursor: String? = nil
    ) {
        self.id = id
        self.participantIdsRaw = participantIds.joined(separator: "|")
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
        self.updatedAt = updatedAt
        self.remoteId = remoteId
        self.syncStatusRaw = syncStatus.rawValue
        self.deletedAt = deletedAt
        self.cursor = cursor
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .local }
        set {
            syncStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}

extension MessageThreadEntity {
    var participantIds: [String] {
        get { participantIdsRaw.split(separator: "|").map(String.init) }
        set {
            participantIdsRaw = newValue.joined(separator: "|")
            updatedAt = .now
        }
    }
}

@Model
final class MessageEntity {
    @Attribute(.unique) var id: String
    var threadId: String
    var senderId: String
    var content: String
    var mediaItemIdsRaw: String
    var createdAt: Date
    var updatedAt: Date
    var statusRaw: String
    var remoteId: String?
    var syncStatusRaw: String
    var deletedAt: Date?
    var cursor: String?

    init(
        id: String = UUID().uuidString,
        threadId: String,
        senderId: String,
        content: String,
        mediaItemIds: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        status: MessageStatus = .sent,
        remoteId: String? = nil,
        syncStatus: SyncStatus = .local,
        deletedAt: Date? = nil,
        cursor: String? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.senderId = senderId
        self.content = content
        self.mediaItemIdsRaw = mediaItemIds.joined(separator: "|")
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.statusRaw = status.rawValue
        self.remoteId = remoteId
        self.syncStatusRaw = syncStatus.rawValue
        self.deletedAt = deletedAt
        self.cursor = cursor
    }
}

extension MessageEntity {
    var mediaItemIds: [String] {
        get { mediaItemIdsRaw.split(separator: "|").map(String.init) }
        set { mediaItemIdsRaw = newValue.joined(separator: "|") }
    }

    var status: MessageStatus {
        get { MessageStatus(rawValue: statusRaw) ?? .sent }
        set { statusRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .local }
        set {
            syncStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var type: MessageContentType {
        if senderId == "system" { return .system }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasVisibleText = !trimmed.isEmpty && !trimmed.isMediaPlaceholderOnly
        let hasMedia = !mediaItemIds.isEmpty

        switch (hasVisibleText, hasMedia) {
        case (true, true):
            return .mixed
        case (false, true):
            return .image
        case (true, false):
            return .text
        case (false, false):
            return .text
        }
    }

    func resolvedType(mediaItems: [MediaEntity]) -> MessageContentType {
        if senderId == "system" { return .system }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasVisibleText = !trimmed.isEmpty && !trimmed.isMediaPlaceholderOnly
        guard !mediaItems.isEmpty else { return hasVisibleText ? .text : .text }
        guard !hasVisibleText else { return .mixed }
        return mediaItems.allSatisfy { $0.type == .video } ? .video : .image
    }

    var visibleContent: String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !mediaItemIds.isEmpty && trimmed.isMediaPlaceholderOnly {
            return nil
        }
        return trimmed
    }
}

private extension String {
    var isMediaPlaceholderOnly: Bool {
        let compact = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        return compact == "[图片]" || compact == "[視頻]" || compact == "[视频]" || compact == "[image]" || compact == "[video]"
    }
}
