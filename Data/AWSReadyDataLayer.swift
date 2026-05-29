import Foundation
import SwiftData

struct KXPagedResult<Item> {
    let items: [Item]
    let nextCursor: String?
    let hasMore: Bool
}

struct KXPostDTO: Codable, Hashable, Sendable {
    let id: String
    let authorId: String
    let content: String
    let updatedAt: Date
    let deletedAt: Date?
    let cursor: String?
    let repostOfPostId: String?
}

struct KXUserDTO: Codable, Hashable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarURL: String
    let coverURL: String
    let bio: String
    let location: String
    let isVerified: Bool
    let role: String
    let followerCount: Int
    let followingCount: Int
    let updatedAt: Date
    let deletedAt: Date?
    let cursor: String?
}

struct KXCommentDTO: Codable, Hashable, Sendable {
    let id: String
    let postId: String
    let authorId: String
    let content: String
    let parentCommentId: String?
    let likeCount: Int
    let updatedAt: Date
    let deletedAt: Date?
    let cursor: String?
}

struct KXMediaDTO: Codable, Hashable, Sendable {
    let id: String
    let ownerId: String
    let type: String
    let localURL: String
    let remoteURL: String
    let thumbnailURL: String
    let width: Double
    let height: Double
    let duration: Double
    let uploadState: String
    let uploadProgress: Double
    let updatedAt: Date
    let deletedAt: Date?
    let cursor: String?
}

struct KXNotificationDTO: Codable, Hashable, Sendable {
    let id: String
    let type: String
    let actorId: String
    let targetPostId: String?
    let targetCommentId: String?
    let content: String
    let isRead: Bool
    let updatedAt: Date
    let deletedAt: Date?
    let cursor: String?
}

struct KXConversationDTO: Codable, Hashable, Sendable {
    let id: String
    let participantIds: [String]
    let lastMessage: String
    let lastMessageAt: Date
    let unreadCount: Int
    let updatedAt: Date
    let deletedAt: Date?
    let cursor: String?
}

struct KXMessageDTO: Codable, Hashable, Sendable {
    let id: String
    let conversationId: String
    let senderId: String
    let content: String
    let mediaIds: [String]
    let createdAt: Date
    let updatedAt: Date
    let status: String
    let deletedAt: Date?
    let cursor: String?
}

protocol KXRemoteDataSource {
    associatedtype DTO

    func fetchPage(cursor: String?, limit: Int) async throws -> KXPagedResult<DTO>
    func push(_ dto: DTO) async throws -> DTO
    func delete(remoteId: String) async throws
}

protocol KXLocalDataSource {
    associatedtype Entity

    func fetchPage(cursor: String?, limit: Int) async throws -> KXPagedResult<Entity>
    func upsert(_ entity: Entity) async throws
    func markDeleted(id: String, at date: Date) async throws
}

protocol KXPostRepositorying {
    func fetchFeed(cursor: String?, limit: Int, forceRefresh: Bool) async throws -> KXPagedResult<KXPost>
    func fetchPost(id: String) async throws -> KXPost?
    func retrySync(postId: String) async throws
}

@MainActor
struct RepositoryContainer {
    let context: ModelContext

    var users: UserRepository { UserRepository(context: context) }
    var posts: PostRepository { PostRepository(context: context) }
    var comments: CommentRepository { CommentRepository(context: context) }
    var messages: MessageRepository { MessageRepository(context: context) }
    var notifications: NotificationRepository { NotificationRepository(context: context) }
    var topics: TopicRepository { TopicRepository(context: context) }
}

enum KXPostMapper {
    static func domain(from entity: PostEntity) -> KXPost {
        KXPost(
            id: entity.id,
            remoteId: entity.remoteId,
            authorId: entity.authorId,
            content: entity.content,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            syncStatus: entity.syncStatus,
            cursor: entity.cursor,
            repostOfPostId: entity.repostOfPostId
        )
    }

    static func dto(from entity: PostEntity) -> KXPostDTO {
        KXPostDTO(
            id: entity.remoteId ?? entity.id,
            authorId: entity.authorId,
            content: entity.content,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            cursor: entity.cursor,
            repostOfPostId: entity.repostOfPostId
        )
    }

    static func apply(_ dto: KXPostDTO, to entity: PostEntity) {
        entity.remoteId = dto.id
        entity.authorId = dto.authorId
        entity.content = dto.content
        entity.updatedAt = dto.updatedAt
        entity.deletedAt = dto.deletedAt
        entity.cursor = dto.cursor
        entity.repostOfPostId = dto.repostOfPostId
        entity.syncStatus = dto.deletedAt == nil ? .synced : .deleted
    }
}

enum KXUserMapper {
    static func domain(from entity: UserEntity) -> KXUser {
        KXUser(
            id: entity.id,
            remoteId: entity.remoteId,
            username: entity.username,
            displayName: entity.displayName,
            avatarURL: entity.avatarURL,
            bio: entity.bio,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            syncStatus: entity.syncStatus,
            cursor: entity.cursor
        )
    }

    static func dto(from entity: UserEntity) -> KXUserDTO {
        KXUserDTO(
            id: entity.remoteId ?? entity.id,
            username: entity.username,
            displayName: entity.displayName,
            avatarURL: entity.avatarURL,
            coverURL: entity.coverURL,
            bio: entity.bio,
            location: entity.location,
            isVerified: entity.isVerified,
            role: entity.role.rawValue,
            followerCount: entity.followerCount,
            followingCount: entity.followingCount,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            cursor: entity.cursor
        )
    }

    static func apply(_ dto: KXUserDTO, to entity: UserEntity) {
        entity.remoteId = dto.id
        entity.username = dto.username.normalizedUsername
        entity.displayName = dto.displayName
        entity.avatarURL = dto.avatarURL
        entity.coverURL = dto.coverURL
        entity.bio = dto.bio
        entity.location = dto.location
        entity.isVerified = dto.isVerified
        entity.role = UserRole(rawValue: dto.role) ?? .member
        entity.followerCount = dto.followerCount
        entity.followingCount = dto.followingCount
        entity.updatedAt = dto.updatedAt
        entity.deletedAt = dto.deletedAt
        entity.cursor = dto.cursor
        entity.syncStatus = dto.deletedAt == nil ? .synced : .deleted
    }
}

enum KXCommentMapper {
    static func domain(from entity: CommentEntity) -> KXComment {
        KXComment(
            id: entity.id,
            remoteId: entity.remoteId,
            postId: entity.postId,
            authorId: entity.authorId,
            content: entity.content,
            parentCommentId: entity.parentCommentId,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            syncStatus: entity.syncStatus,
            cursor: entity.cursor
        )
    }

    static func dto(from entity: CommentEntity) -> KXCommentDTO {
        KXCommentDTO(
            id: entity.remoteId ?? entity.id,
            postId: entity.postId,
            authorId: entity.authorId,
            content: entity.content,
            parentCommentId: entity.parentCommentId,
            likeCount: entity.likeCount,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            cursor: entity.cursor
        )
    }

    static func apply(_ dto: KXCommentDTO, to entity: CommentEntity) {
        entity.remoteId = dto.id
        entity.postId = dto.postId
        entity.authorId = dto.authorId
        entity.content = dto.content
        entity.parentCommentId = dto.parentCommentId
        entity.likeCount = dto.likeCount
        entity.updatedAt = dto.updatedAt
        entity.deletedAt = dto.deletedAt
        entity.cursor = dto.cursor
        entity.syncStatus = dto.deletedAt == nil ? .synced : .deleted
    }
}

enum KXMediaMapper {
    static func domain(from entity: MediaEntity) -> KXMedia {
        KXMedia(
            id: entity.id,
            remoteId: entity.remoteId,
            ownerId: entity.postId,
            type: entity.type,
            localURL: entity.localURL,
            remoteURL: entity.remoteURL,
            thumbnailURL: entity.thumbnailURL,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            syncStatus: entity.syncStatus,
            cursor: entity.cursor
        )
    }

    static func dto(from entity: MediaEntity) -> KXMediaDTO {
        KXMediaDTO(
            id: entity.remoteId ?? entity.id,
            ownerId: entity.postId,
            type: entity.type.rawValue,
            localURL: entity.localURL,
            remoteURL: entity.remoteURL,
            thumbnailURL: entity.thumbnailURL,
            width: entity.width,
            height: entity.height,
            duration: entity.duration,
            uploadState: entity.uploadState.rawValue,
            uploadProgress: entity.uploadProgress,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            cursor: entity.cursor
        )
    }

    static func apply(_ dto: KXMediaDTO, to entity: MediaEntity) {
        entity.remoteId = dto.id
        entity.postId = dto.ownerId
        entity.type = MediaType(rawValue: dto.type) ?? .image
        entity.localURL = dto.localURL
        entity.remoteURL = dto.remoteURL
        entity.thumbnailURL = dto.thumbnailURL
        entity.width = dto.width
        entity.height = dto.height
        entity.duration = dto.duration
        entity.uploadState = UploadState(rawValue: dto.uploadState) ?? .local
        entity.uploadProgress = dto.uploadProgress
        entity.updatedAt = dto.updatedAt
        entity.deletedAt = dto.deletedAt
        entity.cursor = dto.cursor
        entity.syncStatus = dto.deletedAt == nil ? .synced : .deleted
    }
}

enum KXNotificationMapper {
    static func domain(from entity: NotificationEntity) -> KXNotification {
        KXNotification(
            id: entity.id,
            remoteId: entity.remoteId,
            type: entity.type,
            actorId: entity.actorId,
            targetPostId: entity.targetPostId,
            targetCommentId: entity.targetCommentId,
            createdAt: entity.createdAt,
            isRead: entity.isRead,
            syncStatus: entity.syncStatus
        )
    }

    static func dto(from entity: NotificationEntity) -> KXNotificationDTO {
        KXNotificationDTO(
            id: entity.remoteId ?? entity.id,
            type: entity.type.rawValue,
            actorId: entity.actorId,
            targetPostId: entity.targetPostId,
            targetCommentId: entity.targetCommentId,
            content: entity.content,
            isRead: entity.isRead,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            cursor: entity.cursor
        )
    }

    static func apply(_ dto: KXNotificationDTO, to entity: NotificationEntity) {
        entity.remoteId = dto.id
        entity.type = NotificationType(rawValue: dto.type) ?? .system
        entity.actorId = dto.actorId
        entity.targetPostId = dto.targetPostId
        entity.targetCommentId = dto.targetCommentId
        entity.content = dto.content
        entity.isRead = dto.isRead
        entity.updatedAt = dto.updatedAt
        entity.deletedAt = dto.deletedAt
        entity.cursor = dto.cursor
        entity.syncStatus = dto.deletedAt == nil ? .synced : .deleted
    }
}

enum KXConversationMapper {
    static func domain(from entity: MessageThreadEntity) -> KXConversation {
        KXConversation(
            id: entity.id,
            remoteId: entity.remoteId,
            participantIds: entity.participantIds,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            syncStatus: entity.syncStatus,
            cursor: entity.cursor
        )
    }

    static func dto(from entity: MessageThreadEntity) -> KXConversationDTO {
        KXConversationDTO(
            id: entity.remoteId ?? entity.id,
            participantIds: entity.participantIds,
            lastMessage: entity.lastMessage,
            lastMessageAt: entity.lastMessageAt,
            unreadCount: entity.unreadCount,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            cursor: entity.cursor
        )
    }

    static func apply(_ dto: KXConversationDTO, to entity: MessageThreadEntity) {
        entity.remoteId = dto.id
        entity.participantIds = dto.participantIds
        entity.lastMessage = dto.lastMessage
        entity.lastMessageAt = dto.lastMessageAt
        entity.unreadCount = dto.unreadCount
        entity.updatedAt = dto.updatedAt
        entity.deletedAt = dto.deletedAt
        entity.cursor = dto.cursor
        entity.syncStatus = dto.deletedAt == nil ? .synced : .deleted
    }
}

enum KXMessageMapper {
    static func domain(from entity: MessageEntity) -> KXMessage {
        KXMessage(
            id: entity.id,
            remoteId: entity.remoteId,
            conversationId: entity.threadId,
            senderId: entity.senderId,
            content: entity.content,
            mediaIds: entity.mediaItemIds,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            deletedAt: entity.deletedAt,
            syncStatus: entity.syncStatus
        )
    }

    static func dto(from entity: MessageEntity) -> KXMessageDTO {
        KXMessageDTO(
            id: entity.remoteId ?? entity.id,
            conversationId: entity.threadId,
            senderId: entity.senderId,
            content: entity.content,
            mediaIds: entity.mediaItemIds,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            status: entity.status.rawValue,
            deletedAt: entity.deletedAt,
            cursor: entity.cursor
        )
    }

    static func apply(_ dto: KXMessageDTO, to entity: MessageEntity) {
        entity.remoteId = dto.id
        entity.threadId = dto.conversationId
        entity.senderId = dto.senderId
        entity.content = dto.content
        entity.mediaItemIds = dto.mediaIds
        entity.updatedAt = dto.updatedAt
        entity.status = MessageStatus(rawValue: dto.status) ?? .sent
        entity.deletedAt = dto.deletedAt
        entity.cursor = dto.cursor
        entity.syncStatus = dto.deletedAt == nil ? .synced : .deleted
    }
}
