import Foundation
import SwiftData

@MainActor
final class NotificationRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchNotifications() async throws -> [NotificationEntity] {
        try deduplicateExactNotifications()
        var descriptor = FetchDescriptor<NotificationEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        return try context.fetch(descriptor)
    }

    func markAllRead() async throws {
        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>())
        notifications.forEach { $0.isRead = true }
        try context.save()
    }

    func markRead(_ notification: NotificationEntity) async throws {
        notification.isRead = true
        try context.save()
    }

    func markRead(_ notifications: [NotificationEntity]) async throws {
        notifications.forEach { $0.isRead = true }
        try context.save()
    }

    func markUnread(_ notifications: [NotificationEntity]) async throws {
        notifications.forEach { $0.isRead = false }
        try context.save()
    }

    func delete(_ notification: NotificationEntity) async throws {
        context.delete(notification)
        try context.save()
    }

    func delete(_ notifications: [NotificationEntity]) async throws {
        notifications.forEach(context.delete)
        try context.save()
    }

    private func deduplicateExactNotifications() throws {
        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
        let grouped = Dictionary(grouping: notifications) {
            "\($0.typeRaw)|\($0.actorId)|\($0.targetPostId ?? "none")|\($0.targetCommentId ?? "none")"
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
}
