import Foundation
import SwiftData

@MainActor
final class MessageRepository {
    private let context: ModelContext
    private static var cachedPeersById: [String: UserEntity] = [:]
    private static var cachedMediaByConversationId: [String: [String: [MediaEntity]]] = [:]
    private static var signedAttachmentURLCache: [String: SignedAttachmentURLCacheItem] = [:]
    /// Hard ceiling so a long messaging session that opens many distinct
    /// attachments can't grow this in-memory cache without bound.
    private static let signedAttachmentCacheCap = 200

    private struct SignedAttachmentURLCacheItem {
        let url: String
        let expiresAt: Date
    }

    /// Keep the signed-URL cache bounded: drop expired entries first, then, if
    /// still over the cap, keep only the freshest (latest-expiring) ones.
    private static func pruneSignedAttachmentCacheIfNeeded(now: Date) {
        signedAttachmentURLCache = signedAttachmentURLCache.filter { $0.value.expiresAt > now }
        guard signedAttachmentURLCache.count > signedAttachmentCacheCap else { return }
        let freshest = signedAttachmentURLCache
            .sorted { $0.value.expiresAt > $1.value.expiresAt }
            .prefix(signedAttachmentCacheCap)
        signedAttachmentURLCache = Dictionary(uniqueKeysWithValues: freshest.map { ($0.key, $0.value) })
    }

    init(context: ModelContext) {
        self.context = context
    }

    func fetchThreads(currentUserId: String) async throws -> [MessageThreadEntity] {
        if KaiXBackend.token != nil {
            let conversations = try await KaiXAPIClient.shared.conversations()
            var peers: [String: UserEntity] = [:]
            let threads = conversations.map { dto -> MessageThreadEntity in
                if let peer = dto.peer {
                    peers[peer.id] = UserRepository.entity(from: peer)
                }
                return Self.thread(from: dto)
            }
            Self.cachedPeersById.merge(peers) { _, new in new }
            return threads
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { return [] }
        return try context.fetch(FetchDescriptor<MessageThreadEntity>(
            sortBy: [SortDescriptor(\.lastMessageAt, order: .reverse)]
        ))
        .filter { $0.participantIds.contains(currentUserId) }
    }

    func fetchMessages(threadId: String, query: String = "", day: String? = nil) async throws -> [MessageEntity] {
        if KaiXBackend.token != nil {
            let messages = try await KaiXAPIClient.shared.messages(threadId, query: query, day: day)
            var mediaByMessage: [String: [MediaEntity]] = [:]
            var entities: [MessageEntity] = []
            for dto in messages {
                let mappedMedia = await Self.resolvedMediaItems(from: dto)
                mediaByMessage[dto.id] = mappedMedia
                let entity = Self.message(from: dto, mediaIds: mappedMedia.map(\.id))
                entities.append(entity)
            }
            Self.cachedMediaByConversationId[threadId] = mediaByMessage
            return entities
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { return [] }
        return try context.fetch(FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.threadId == threadId },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    func fetchMedia(threadId: String, messageIds: Set<String>) async throws -> [String: [MediaEntity]] {
        if KaiXBackend.token != nil {
            let cached = Self.cachedMediaByConversationId[threadId] ?? [:]
            return cached.filter { messageIds.contains($0.key) }
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { return [:] }
        guard !messageIds.isEmpty else { return [:] }
        let idList = Array(messageIds)
        let media = try context.fetch(FetchDescriptor<MediaEntity>(
            predicate: #Predicate { idList.contains($0.postId) },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        return Dictionary(grouping: media, by: \.postId)
    }

    func getOrCreateThread(currentUserId: String, peerUserId: String) async throws -> MessageThreadEntity {
        if KaiXBackend.token != nil {
            let dto = try await KaiXAPIClient.shared.openConversation(with: peerUserId)
            if let peer = dto.peer {
                Self.cachedPeersById[peer.id] = UserRepository.entity(from: peer)
            }
            return Self.thread(from: dto)
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { throw RepositoryError.authenticationRequired }
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
        mediaDrafts: [MediaDraft] = [],
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> MessageEntity {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false || mediaDrafts.isEmpty == false else { throw RepositoryError.validationFailed }

        if KaiXBackend.token != nil {
            var attachmentIds: [String] = []
            let total = Swift.max(1, mediaDrafts.count)
            for (index, draft) in mediaDrafts.enumerated() {
                // Map each attachment's own 0…1 upload into its slice of the
                // overall send so the UI can show one continuous progress.
                let base = Double(index) / Double(total)
                let span = 1.0 / Double(total)
                let fileId = try await Self.uploadMessageAttachment(draft, threadId: thread.id) { fraction in
                    onProgress?(base + span * Swift.min(Swift.max(fraction, 0), 1))
                }
                attachmentIds.append(fileId)
            }
            onProgress?(1)
            let dto = try await KaiXAPIClient.shared.sendMessage(thread.id, content: trimmed, attachmentIds: attachmentIds)
            let mappedMedia = await Self.resolvedMediaItems(from: dto)
            Self.cachedMediaByConversationId[thread.id, default: [:]][dto.id] = mappedMedia
            let message = Self.message(from: dto, mediaIds: mappedMedia.map(\.id))
            thread.lastMessage = Self.previewText(content: trimmed, mediaTypes: mappedMedia.map(\.type))
            thread.lastMessageAt = message.createdAt
            thread.updatedAt = .now
            return message
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { throw RepositoryError.authenticationRequired }

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
        return message
    }

    private static func uploadMessageAttachment(
        _ draft: MediaDraft,
        threadId: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> String {
        let metadata: [String: String]?
        if draft.type == .video {
            // The poster is tiny — reserve the first 8% of the bar for it so
            // the long video upload owns the visible remainder.
            let thumbnailData = try await loadFileData(at: draft.thumbnailURL)
            let cover = try await KaiXAPIClient.shared.uploadFile(
                data: thumbnailData,
                mime: "image/jpeg",
                fileName: "\(draft.id)-cover.jpg",
                purpose: "video_thumbnail",
                entityType: "message",
                threadId: threadId,
                width: Int(draft.width.rounded()),
                height: Int(draft.height.rounded())
            ) { progress in
                onProgress?(Swift.min(0.08, progress * 0.08))
            }
            metadata = [
                "thumbnailFileId": cover.file.id,
                "posterFileId": cover.file.id
            ]
        } else {
            metadata = nil
        }

        let purpose = draft.type == .video ? "message_video" : "message_image"
        let uploaded: (file: KaiXUploadedFileDTO, media: KaiXMediaDTO)
        if draft.type == .video {
            uploaded = try await KaiXAPIClient.shared.uploadFile(
                fileURL: draft.localURL,
                mime: draft.contentType,
                fileName: draft.fileName,
                purpose: purpose,
                entityType: "message",
                threadId: threadId,
                width: Int(draft.width.rounded()),
                height: Int(draft.height.rounded()),
                duration: draft.duration,
                metadata: metadata
            ) { progress in
                onProgress?(0.08 + Swift.min(Swift.max(progress, 0), 1) * 0.92)
            }
        } else {
            let data = try await loadFileData(at: draft.localURL)
            uploaded = try await KaiXAPIClient.shared.uploadFile(
                data: data,
                mime: draft.contentType,
                fileName: draft.fileName,
                purpose: purpose,
                entityType: "message",
                threadId: threadId,
                width: Int(draft.width.rounded()),
                height: Int(draft.height.rounded()),
                duration: draft.duration,
                metadata: metadata
            ) { progress in
                onProgress?(Swift.min(Swift.max(progress, 0), 1))
            }
        }
        return uploaded.file.id
    }

    private static func loadFileData(at url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: url)
        }.value
    }

    func markThreadRead(_ thread: MessageThreadEntity) async throws {
        if KaiXBackend.token != nil {
            try await KaiXAPIClient.shared.markConversationRead(thread.id)
            thread.unreadCount = 0
            return
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { throw RepositoryError.authenticationRequired }
        thread.unreadCount = 0
        thread.updatedAt = .now
        try context.save()
    }

    func markThreadUnread(_ thread: MessageThreadEntity) async throws {
        if KaiXBackend.token != nil {
            try await KaiXAPIClient.shared.markConversationRead(thread.id, isRead: false)
            thread.unreadCount = max(1, thread.unreadCount)
            thread.updatedAt = .now
            return
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { throw RepositoryError.authenticationRequired }
        thread.unreadCount = max(1, thread.unreadCount)
        thread.updatedAt = .now
        try context.save()
    }

    func deleteThread(_ thread: MessageThreadEntity) async throws {
        if KaiXBackend.token != nil {
            try await KaiXAPIClient.shared.deleteConversation(thread.id)
            Self.cachedMediaByConversationId[thread.id] = nil
            return
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { throw RepositoryError.authenticationRequired }
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
        if KaiXBackend.token != nil {
            try await KaiXAPIClient.shared.deleteMessage(message.id)
            Self.cachedMediaByConversationId[thread.id]?[message.id] = nil
            return
        }
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { throw RepositoryError.authenticationRequired }
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

    func cachedPeers() -> [String: UserEntity] {
        Self.cachedPeersById
    }

    private static func thread(from dto: KaiXConversationDTO) -> MessageThreadEntity {
        let last = dto.last_message
        let lastMedia = last.map { mediaItems(from: $0) } ?? []
        return MessageThreadEntity(
            id: dto.id,
            participantIds: dto.participants.isEmpty ? [dto.participant_a, dto.participant_b] : dto.participants,
            lastMessage: previewText(content: last?.content ?? "", mediaTypes: lastMedia.map(\.type)),
            lastMessageAt: parseDate(last?.created_at) ?? parseDate(dto.updated_at) ?? .now,
            unreadCount: dto.unread_count,
            updatedAt: parseDate(dto.updated_at) ?? .now,
            remoteId: dto.id,
            syncStatus: .synced
        )
    }

    private static func message(from dto: KaiXMessageDTO, mediaIds: [String]) -> MessageEntity {
        MessageEntity(
            id: dto.id,
            threadId: dto.conversation_id,
            senderId: dto.sender_id,
            content: dto.content,
            mediaItemIds: mediaIds,
            createdAt: parseDate(dto.created_at) ?? .now,
            updatedAt: parseDate(dto.created_at) ?? .now,
            status: .sent,
            remoteId: dto.id,
            syncStatus: .synced
        )
    }

    private static func resolvedMediaItems(from dto: KaiXMessageDTO) async -> [MediaEntity] {
        guard let attachments = dto.attachments, !attachments.isEmpty else {
            return mediaItems(from: dto)
        }
        var signedURLs: [String: String] = [:]
        let now = Date()
        for attachment in attachments {
            let publicSource = attachment.publicUrl ?? attachment.cdnUrl ?? attachment.url ?? ""
            let needsSignedURL = attachment.needsSignedUrl == true || publicSource.isEmpty
            guard needsSignedURL else { continue }
            let cacheKey = "\(dto.id):\(attachment.id)"
            if let cached = signedAttachmentURLCache[cacheKey], cached.expiresAt > now {
                signedURLs[attachment.id] = cached.url
                continue
            }
            if let signedURL = try? await KaiXAPIClient.shared.messageAttachmentViewUrl(
                messageId: dto.id,
                attachmentId: attachment.id
            ), !signedURL.isEmpty {
                signedURLs[attachment.id] = signedURL
                signedAttachmentURLCache[cacheKey] = SignedAttachmentURLCacheItem(
                    url: signedURL,
                    expiresAt: now.addingTimeInterval(240)
                )
                Self.pruneSignedAttachmentCacheIfNeeded(now: now)
            }
        }
        return mediaItems(from: dto, signedAttachmentURLs: signedURLs)
    }

    private static func mediaItems(from dto: KaiXMessageDTO, signedAttachmentURLs: [String: String] = [:]) -> [MediaEntity] {
        let legacy = (dto.media ?? []).map { media -> MediaEntity in
            MediaEntity(
                id: media.id,
                postId: dto.id,
                type: media.normalizedType == "video" ? .video : .image,
                remoteURL: media.sourceURLString,
                mediumURL: media.mediumURLString,
                originalURL: media.sourceURLString,
                thumbnailURL: media.posterURLString.isEmpty ? media.thumbnailURLString : media.posterURLString,
                width: Double(media.width ?? 0),
                height: Double(media.height ?? 0),
                duration: media.duration_seconds ?? media.durationSeconds ?? media.duration ?? 0,
                fileSize: media.file_size ?? media.fileSize ?? media.byte_size ?? 0,
                mimeType: media.content_type ?? media.contentType ?? media.mime ?? "",
                uploadState: .uploaded,
                uploadProgress: 1,
                createdAt: parseDate(media.created_at ?? media.createdAt) ?? .now,
                remoteId: media.id,
                syncStatus: .synced
            )
        }
        let attachments = (dto.attachments ?? []).map { att -> MediaEntity in
            let rawType = (att.attachment_type ?? att.type).lowercased()
            let mimeType = (att.content_type ?? att.contentType ?? att.mime ?? "").lowercased()
            let mediaType: MediaType = rawType == "video" || mimeType.hasPrefix("video/") ? .video : .image
            let signedSource = signedAttachmentURLs[att.id] ?? ""
            let publicSource = att.publicUrl ?? att.cdnUrl ?? att.url ?? ""
            let source = signedSource.isEmpty ? publicSource : signedSource
            let poster = att.posterUrl ?? att.poster_url ?? att.thumbnailUrl ?? att.thumbnail_url ?? att.thumbUrl ?? att.thumb_url ?? ""
            let thumb = mediaType == .video ? poster : (poster.isEmpty ? source : poster)
            return MediaEntity(
                id: att.id,
                postId: dto.id,
                type: mediaType,
                remoteURL: source,
                mediumURL: source,
                originalURL: source,
                thumbnailURL: thumb,
                width: Double(att.width ?? 0),
                height: Double(att.height ?? 0),
                duration: att.duration_seconds ?? att.durationSeconds ?? att.duration ?? 0,
                fileSize: att.file_size ?? att.fileSize ?? att.byte_size ?? 0,
                mimeType: att.content_type ?? att.contentType ?? att.mime ?? "",
                uploadState: .uploaded,
                uploadProgress: 1,
                createdAt: parseDate(att.created_at ?? att.createdAt) ?? .now,
                remoteId: att.id,
                syncStatus: .synced
            )
        }
        return legacy + attachments
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    private static func previewText(content: String, mediaTypes: [MediaType]) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstType = mediaTypes.first else { return trimmed }
        let mediaLabel = firstType == .video ? "[视频]" : "[图片]"
        return trimmed.isEmpty ? mediaLabel : "\(mediaLabel) \(trimmed)"
    }
}
