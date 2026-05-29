import Foundation

struct KXPost: Identifiable, Hashable, Sendable {
    let id: String
    let remoteId: String?
    let authorId: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let syncStatus: SyncStatus
    let cursor: String?
    let repostOfPostId: String?
}

struct KXUser: Identifiable, Hashable, Sendable {
    let id: String
    let remoteId: String?
    let username: String
    let displayName: String
    let avatarURL: String
    let bio: String
    let updatedAt: Date
    let deletedAt: Date?
    let syncStatus: SyncStatus
    let cursor: String?
}

struct KXComment: Identifiable, Hashable, Sendable {
    let id: String
    let remoteId: String?
    let postId: String
    let authorId: String
    let content: String
    let parentCommentId: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let syncStatus: SyncStatus
    let cursor: String?
}

struct KXRepost: Identifiable, Hashable, Sendable {
    let id: String
    let remoteId: String?
    let postId: String
    let authorId: String
    let quotePostId: String?
    let createdAt: Date
    let deletedAt: Date?
    let syncStatus: SyncStatus
}

struct KXMedia: Identifiable, Hashable, Sendable {
    let id: String
    let remoteId: String?
    let ownerId: String
    let type: MediaType
    let localURL: String
    let remoteURL: String
    let thumbnailURL: String
    let updatedAt: Date
    let deletedAt: Date?
    let syncStatus: SyncStatus
    let cursor: String?
}

struct KXNotification: Identifiable, Hashable, Sendable {
    let id: String
    let remoteId: String?
    let type: NotificationType
    let actorId: String
    let targetPostId: String?
    let targetCommentId: String?
    let createdAt: Date
    let isRead: Bool
    let syncStatus: SyncStatus
}

struct KXConversation: Identifiable, Hashable, Sendable {
    let id: String
    let remoteId: String?
    let participantIds: [String]
    let updatedAt: Date
    let deletedAt: Date?
    let syncStatus: SyncStatus
    let cursor: String?
}

struct KXMessage: Identifiable, Hashable, Sendable {
    let id: String
    let remoteId: String?
    let conversationId: String
    let senderId: String
    let content: String
    let mediaIds: [String]
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let syncStatus: SyncStatus
}
