import Foundation
import SwiftData

@MainActor
final class MessageRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchThreads(currentUserId: String) async throws -> [MessageThreadEntity] {
        return try context.fetch(FetchDescriptor<MessageThreadEntity>(
            sortBy: [SortDescriptor(\.lastMessageAt, order: .reverse)]
        ))
        .filter { $0.participantIds.contains(currentUserId) }
    }

    func fetchMessages(threadId: String) async throws -> [MessageEntity] {
        try context.fetch(FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.threadId == threadId },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    func getOrCreateThread(currentUserId: String, peerUserId: String) async throws -> MessageThreadEntity {
        let threads = try context.fetch(FetchDescriptor<MessageThreadEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
        let expectedParticipants = Set([currentUserId, peerUserId])
        if let existing = threads.first(where: {
            let ids = Set($0.participantIds)
            return ids == expectedParticipants && $0.participantIds.count == expectedParticipants.count
        }) {
            return existing
        }

        let thread = MessageThreadEntity(
            participantIds: [currentUserId, peerUserId],
            lastMessage: "开始新的对话",
            lastMessageAt: .now,
            unreadCount: 0
        )
        context.insert(thread)
        try context.save()
        return thread
    }

    func sendMessage(
        thread: MessageThreadEntity,
        senderId: String,
        content: String,
        mediaDrafts: [MediaDraft] = []
    ) async throws -> MessageEntity {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false || mediaDrafts.isEmpty == false else { throw RepositoryError.validationFailed }

        let message = MessageEntity(
            threadId: thread.id,
            senderId: senderId,
            content: trimmed,
            status: .sending
        )
        context.insert(message)
        var mediaIds: [String] = []
        for draft in mediaDrafts {
            mediaIds.append(draft.id)
            context.insert(MediaEntity(
                id: draft.id,
                postId: message.id,
                type: draft.type,
                localURL: draft.localURL.path,
                thumbnailURL: draft.thumbnailURL.path,
                width: draft.width,
                height: draft.height,
                duration: draft.duration,
                uploadState: .local,
                uploadProgress: 1
            ))
        }
        message.mediaItemIds = mediaIds
        thread.lastMessage = Self.previewText(content: trimmed, mediaTypes: mediaDrafts.map(\.type))
        thread.lastMessageAt = message.createdAt
        thread.updatedAt = .now
        try context.save()

        message.status = .sent
        try context.save()
        // Mirror to unified backend so the recipient sees the message
        // on Web in real-time via SSE.
        if KaiXBackend.token != nil {
            let participants = thread.participantIds
            let peerId = participants.first(where: { $0 != senderId })
            let messageText = trimmed
            if let peerId {
                let mediaPaths: [(MediaType, URL)] = mediaDrafts.map { ($0.type, $0.localURL) }
                Task.detached {
                    do {
                        let conv = try await KaiXAPIClient.shared.openConversation(with: peerId)
                        var remoteMediaIds: [String] = []
                        for (type, url) in mediaPaths {
                            guard let data = try? Data(contentsOf: url) else { continue }
                            let mime = type == .video ? "video/mp4" : "image/jpeg"
                            if let dto = try? await KaiXAPIClient.shared.uploadMedia(data: data, mime: mime) {
                                remoteMediaIds.append(dto.id)
                            }
                        }
                        _ = try? await KaiXAPIClient.shared.sendMessage(conv.id, content: messageText, mediaIds: remoteMediaIds)
                    } catch {
                        // Best-effort; local message is already saved.
                    }
                }
            }
        }
        return message
    }

    func markThreadRead(_ thread: MessageThreadEntity) async throws {
        thread.unreadCount = 0
        thread.updatedAt = .now
        try context.save()
    }

    func markThreadUnread(_ thread: MessageThreadEntity) async throws {
        thread.unreadCount = max(1, thread.unreadCount)
        thread.updatedAt = .now
        try context.save()
    }

    func deleteThread(_ thread: MessageThreadEntity) async throws {
        let threadId = thread.id
        let messages = try context.fetch(FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.threadId == threadId }
        ))
        let messageIds = Array(Set(messages.map(\.id)))
        let media = messageIds.isEmpty ? [] : try context.fetch(FetchDescriptor<MediaEntity>(
            predicate: #Predicate { messageIds.contains($0.postId) }
        ))
        media.forEach(context.delete)
        messages.forEach(context.delete)
        context.delete(thread)
        try context.save()
    }

    func deleteMessage(_ message: MessageEntity, in thread: MessageThreadEntity) async throws {
        let messageId = message.id
        let media = try context.fetch(FetchDescriptor<MediaEntity>(
            predicate: #Predicate { $0.postId == messageId }
        ))
        media.forEach(context.delete)
        context.delete(message)

        let remaining = try await fetchMessages(threadId: thread.id)
        if let last = remaining.last {
            let lastId = last.id
            let lastMedia = try context.fetch(FetchDescriptor<MediaEntity>(
                predicate: #Predicate { $0.postId == lastId }
            ))
            thread.lastMessage = Self.previewText(content: last.content, mediaTypes: lastMedia.map(\.type))
            thread.lastMessageAt = last.createdAt
        } else {
            thread.lastMessage = ""
            thread.lastMessageAt = .now
        }
        thread.updatedAt = .now
        try context.save()
    }

    func peerUserId(in thread: MessageThreadEntity, currentUserId: String) -> String? {
        thread.participantIds.first { $0 != currentUserId }
    }

    private static func previewText(content: String, mediaTypes: [MediaType]) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstType = mediaTypes.first else { return trimmed }
        let mediaLabel = firstType == .video ? "[视频]" : "[图片]"
        return trimmed.isEmpty ? mediaLabel : "\(mediaLabel) \(trimmed)"
    }
}
