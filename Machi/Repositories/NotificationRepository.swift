import Foundation
import SwiftData

@MainActor
final class NotificationRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchNotifications() async throws -> [NotificationEntity] {
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            guard KaiXBackend.token != nil else { return [] }
            let response = try await KaiXAPIClient.shared.notifications(kind: "all")
            return response.items.map(Self.entity(from:))
        }
        try deduplicateExactNotifications()
        var descriptor = FetchDescriptor<NotificationEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        return try context.fetch(descriptor)
    }

    func markAllRead() async throws {
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            guard KaiXBackend.token != nil else { return }
            try await KaiXAPIClient.shared.markNotificationsRead(all: true)
            return
        }
        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>())
        notifications.forEach { $0.isRead = true }
        try context.save()
    }

    func markRead(_ notification: NotificationEntity) async throws {
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            notification.isRead = true
            guard KaiXBackend.token != nil else { return }
            try await KaiXAPIClient.shared.markNotificationsRead(ids: [notification.remoteId ?? notification.id])
            return
        }
        notification.isRead = true
        try context.save()
    }

    func markRead(_ notifications: [NotificationEntity]) async throws {
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            notifications.forEach { $0.isRead = true }
            guard KaiXBackend.token != nil else { return }
            try await KaiXAPIClient.shared.markNotificationsRead(ids: notifications.map { $0.remoteId ?? $0.id })
            return
        }
        notifications.forEach { $0.isRead = true }
        try context.save()
    }

    func markUnread(_ notifications: [NotificationEntity]) async throws {
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            notifications.forEach { $0.isRead = false }
            return
        }
        notifications.forEach { $0.isRead = false }
        try context.save()
    }

    func delete(_ notification: NotificationEntity) async throws {
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            guard KaiXBackend.token != nil else { return }
            try await KaiXAPIClient.shared.deleteNotification(notification.remoteId ?? notification.id)
            return
        }
        context.delete(notification)
        try context.save()
    }

    func delete(_ notifications: [NotificationEntity]) async throws {
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            guard KaiXBackend.token != nil else { return }
            for notification in notifications {
                try await KaiXAPIClient.shared.deleteNotification(notification.remoteId ?? notification.id)
            }
            return
        }
        notifications.forEach(context.delete)
        try context.save()
    }

    private func deduplicateExactNotifications() throws {
        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        let grouped = Dictionary(grouping: notifications) {
            "\($0.typeRaw)|\($0.actorId)|\($0.targetPostId ?? "none")|\($0.targetCommentId ?? "none")|\($0.targetConversationId ?? "none")"
        }
        var didDelete = false
        for items in grouped.values where items.count > 1 {
            for duplicate in items.dropFirst() {
                context.delete(duplicate)
                didDelete = true
            }
        }
        if didDelete {
            try context.save()
        }
    }

    private static func entity(from dto: KaiXNotificationDTO) -> NotificationEntity {
        NotificationEntity(
            id: dto.id,
            type: NotificationType(rawValue: dto.type) ?? .system,
            actorId: dto.actor?.id ?? dto.actor_id,
            targetPostId: dto.target_post_id,
            targetCommentId: dto.target_comment_id,
            targetConversationId: dto.target_conversation_id,
            content: dto.content ?? "",
            isRead: dto.is_read,
            createdAt: parseDate(dto.created_at) ?? .now,
            remoteId: dto.id,
            syncStatus: .synced
        )
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
}
