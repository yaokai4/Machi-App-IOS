import Foundation
import SwiftData

@MainActor
enum DataIntegrityRepairer {
    static func repair(context: ModelContext) throws {
        try repairPostStatistics(context: context)
        try repairMessageBodies(context: context)
        try removeDuplicateReposts(context: context)
        try removeDuplicateNotifications(context: context)
        try clampFutureDates(context: context)
        try context.save()
    }

    private static func repairPostStatistics(context: ModelContext) throws {
        let posts = try context.fetch(FetchDescriptor<PostEntity>())
        let comments = try context.fetch(FetchDescriptor<CommentEntity>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
        let commentCounts = Dictionary(grouping: comments, by: \.postId).mapValues(\.count)

        for post in posts {
            post.likeCount = max(0, post.likeCount)
            post.repostCount = max(0, post.repostCount)
            post.bookmarkCount = max(0, post.bookmarkCount)
            post.viewCount = max(0, post.viewCount)
            post.commentCount = commentCounts[post.id] ?? 0
            HeatScoreService.shared.refresh(post)
        }
    }

    private static func removeDuplicateReposts(context: ModelContext) throws {
        let reposts = try context.fetch(FetchDescriptor<PostEntity>())
            .filter { $0.repostOfPostId != nil }
        let grouped = Dictionary(grouping: reposts) {
            "\($0.authorId)|\($0.repostOfPostId ?? "")"
        }

        for items in grouped.values where items.count > 1 {
            let duplicates = items.sorted { $0.createdAt < $1.createdAt }.dropFirst()
            for duplicate in duplicates {
                if let targetId = duplicate.repostOfPostId,
                   let target = try fetchPost(id: targetId, context: context) {
                    target.repostCount = max(0, target.repostCount - 1)
                    HeatScoreService.shared.refresh(target)
                }
                context.delete(duplicate)
            }
        }
    }

    private static func repairMessageBodies(context: ModelContext) throws {
        let messages = try context.fetch(FetchDescriptor<MessageEntity>())
        let media = try context.fetch(FetchDescriptor<MediaEntity>())
        let mediaByMessageId = Dictionary(grouping: media, by: \.postId)

        for message in messages {
            guard !message.mediaItemIds.isEmpty else { continue }
            message.content = sanitizedMessageContent(message.content)
        }

        let latestMessages = Dictionary(
            grouping: messages,
            by: \.threadId
        ).compactMapValues { items in
            items.sorted { $0.createdAt > $1.createdAt }.first
        }

        for thread in try context.fetch(FetchDescriptor<MessageThreadEntity>()) {
            if let latest = latestMessages[thread.id] {
                thread.lastMessage = previewText(
                    content: latest.visibleContent ?? "",
                    media: mediaByMessageId[latest.id] ?? []
                )
                thread.lastMessageAt = latest.createdAt
            } else {
                thread.lastMessage = sanitizedThreadPreview(thread.lastMessage)
            }
        }
    }

    private static func sanitizedMessageContent(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isMediaPlaceholderOnly { return "" }
        return trimmed
            .replacingOccurrences(of: "[图片] [图片]", with: "[图片]")
            .replacingOccurrences(of: "[视频] [视频]", with: "[视频]")
    }

    private static func sanitizedThreadPreview(_ content: String) -> String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[图片] [图片]", with: "[图片]")
            .replacingOccurrences(of: "[视频] [视频]", with: "[视频]")
    }

    private static func previewText(content: String, media: [MediaEntity]) -> String {
        guard let first = media.first else { return content }
        let label = first.type == .video ? "[视频]" : "[图片]"
        return content.isEmpty ? label : "\(label) \(content)"
    }

    private static func removeDuplicateNotifications(context: ModelContext) throws {
        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        let grouped = Dictionary(grouping: notifications) {
            "\($0.typeRaw)|\($0.actorId)|\($0.targetPostId ?? "none")"
        }

        for items in grouped.values where items.count > 1 {
            for duplicate in items.dropFirst() {
                context.delete(duplicate)
            }
        }
    }

    private static func clampFutureDates(context: ModelContext) throws {
        let now = Date()
        for post in try context.fetch(FetchDescriptor<PostEntity>()) where post.createdAt > now {
            post.createdAt = now
            post.updatedAt = now
        }
        for comment in try context.fetch(FetchDescriptor<CommentEntity>()) where comment.createdAt > now {
            comment.createdAt = now
        }
        for notification in try context.fetch(FetchDescriptor<NotificationEntity>()) where notification.createdAt > now {
            notification.createdAt = now
        }
    }

    private static func fetchPost(id: String, context: ModelContext) throws -> PostEntity? {
        var descriptor = FetchDescriptor<PostEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

private extension String {
    var isMediaPlaceholderOnly: Bool {
        let compact = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        return compact == "[图片]" || compact == "[视频]" || compact == "[視頻]" || compact == "[image]" || compact == "[video]"
    }
}
