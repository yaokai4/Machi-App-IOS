import Foundation
import Combine
import SwiftData

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var notifications: [NotificationEntity] = []
    @Published var actors: [String: UserEntity] = [:]
    @Published private(set) var groupedNotifications: [AggregatedNotification] = []
    @Published var state: ScreenState = .idle
    @Published var transientError: String?

    private func rebuildGroupedNotifications() {
        let groups = Dictionary(grouping: notifications) { notification in
            AggregatedNotification.groupKey(for: notification)
        }
        groupedNotifications = groups.values
            .compactMap { AggregatedNotification(notifications: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func load(context: ModelContext, notificationStore: NotificationStore? = nil) async {
        let hasCachedContent = !notifications.isEmpty
        if !hasCachedContent {
            state = .loading
            notificationStore?.setLoadingState(.loading)
        }
        do {
            notifications = try await NotificationRepository(context: context).fetchNotifications()
            rebuildGroupedNotifications()
            notificationStore?.setNotifications(notifications)
            let users = try await UserRepository(context: context).fetchUsers(ids: Set(notifications.map(\.actorId)))
            actors = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            state = notifications.isEmpty ? .empty : .loaded
            notificationStore?.setLoadingState(state)
        } catch {
            if hasCachedContent {
                transientError = error.kaixUserMessage
                state = .loaded
                notificationStore?.setLoadingState(.loaded)
            } else {
                state = .error(error.kaixUserMessage)
                notificationStore?.setLoadingState(state)
            }
        }
    }

    func markAllRead(context: ModelContext, notificationStore: NotificationStore? = nil) async {
        let previous = notifications.map { ($0, $0.isRead) }
        notifications.forEach { $0.isRead = true }
        rebuildGroupedNotifications()
        notificationStore?.setNotifications(notifications)
        do {
            try await NotificationRepository(context: context).markAllRead()
            // Mirror to the unified backend so the badge on Web disappears too.
            if KaiXBackend.token != nil {
                Task.detached { try? await KaiXAPIClient.shared.markNotificationsRead(all: true) }
            }
        } catch {
            previous.forEach { $0.0.isRead = $0.1 }
            rebuildGroupedNotifications()
            notificationStore?.setNotifications(notifications)
            transientError = error.kaixUserMessage
        }
    }

    func markRead(context: ModelContext, notification: NotificationEntity, notificationStore: NotificationStore? = nil) async {
        let previous = notification.isRead
        notification.isRead = true
        rebuildGroupedNotifications()
        notificationStore?.setNotifications(notifications)
        do {
            try await NotificationRepository(context: context).markRead(notification)
        } catch {
            notification.isRead = previous
            rebuildGroupedNotifications()
            notificationStore?.setNotifications(notifications)
            transientError = error.kaixUserMessage
        }
    }

    func markRead(context: ModelContext, aggregate: AggregatedNotification, notificationStore: NotificationStore? = nil) async {
        let previous = aggregate.notifications.map { ($0, $0.isRead) }
        aggregate.notifications.forEach { $0.isRead = true }
        rebuildGroupedNotifications()
        notificationStore?.setNotifications(notifications)
        do {
            try await NotificationRepository(context: context).markRead(aggregate.notifications)
        } catch {
            previous.forEach { $0.0.isRead = $0.1 }
            rebuildGroupedNotifications()
            notificationStore?.setNotifications(notifications)
            transientError = error.kaixUserMessage
        }
    }

    func toggleRead(context: ModelContext, aggregate: AggregatedNotification, notificationStore: NotificationStore? = nil) async {
        let shouldMarkRead = !aggregate.isRead
        let previous = aggregate.notifications.map { ($0, $0.isRead) }
        aggregate.notifications.forEach { $0.isRead = shouldMarkRead }
        rebuildGroupedNotifications()
        notificationStore?.setNotifications(notifications)
        do {
            if shouldMarkRead {
                try await NotificationRepository(context: context).markRead(aggregate.notifications)
            } else {
                try await NotificationRepository(context: context).markUnread(aggregate.notifications)
            }
        } catch {
            previous.forEach { $0.0.isRead = $0.1 }
            rebuildGroupedNotifications()
            notificationStore?.setNotifications(notifications)
            transientError = error.kaixUserMessage
        }
    }

    func delete(context: ModelContext, aggregate: AggregatedNotification, notificationStore: NotificationStore? = nil) async {
        let removedIds = Set(aggregate.notifications.map(\.id))
        let previousNotifications = notifications
        notifications.removeAll { removedIds.contains($0.id) }
        rebuildGroupedNotifications()
        notificationStore?.setNotifications(notifications)
        state = notifications.isEmpty ? .empty : .loaded

        do {
            try await NotificationRepository(context: context).delete(aggregate.notifications)
        } catch {
            notifications = previousNotifications
            rebuildGroupedNotifications()
            notificationStore?.setNotifications(notifications)
            state = notifications.isEmpty ? .empty : .loaded
            transientError = error.kaixUserMessage
        }
    }
}

struct AggregatedNotification: Identifiable {
    let id: String
    let notifications: [NotificationEntity]
    let latest: NotificationEntity
    let actorIds: [String]

    var type: NotificationType { latest.type }
    var targetPostId: String? { latest.targetPostId }
    var targetCommentId: String? { latest.targetCommentId }
    var content: String { latest.content }
    var createdAt: Date { latest.createdAt }
    var isRead: Bool { notifications.allSatisfy(\.isRead) }

    init?(notifications: [NotificationEntity]) {
        guard let latest = notifications.sorted(by: { $0.createdAt > $1.createdAt }).first else { return nil }
        self.latest = latest
        self.notifications = notifications
        self.id = Self.groupKey(for: latest)
        var seen = Set<String>()
        self.actorIds = notifications
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { notification in
                seen.insert(notification.actorId).inserted ? notification.actorId : nil
            }
    }

    static func groupKey(for notification: NotificationEntity) -> String {
        switch notification.type {
        case .like, .repost, .comment, .reply, .bookmark, .mention:
            return "\(notification.typeRaw)|\(notification.targetPostId ?? "none")"
        case .follow:
            return notification.typeRaw
        case .system:
            return "\(notification.typeRaw)|\(notification.id)"
        }
    }
}
