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
            if KaiXBackend.token != nil {
                let response = try await KaiXAPIClient.shared.notifications(kind: "all")
                notifications = response.items.map(Self.entity(from:))
                rebuildGroupedNotifications()
                notificationStore?.setNotifications(notifications)
                notificationStore?.setUnreadCount(response.unread_count)
                var actorMap: [String: UserEntity] = [:]
                for dto in response.items.compactMap(\.actor) {
                    actorMap[dto.id] = UserRepository.entity(from: dto)
                }
                let missingActorIds = Set(notifications.map(\.actorId)).subtracting(actorMap.keys)
                if !missingActorIds.isEmpty {
                    let users = try await UserRepository(context: context).fetchUsers(ids: missingActorIds)
                    for user in users {
                        actorMap[user.id] = user
                    }
                }
                actors = actorMap
                state = notifications.isEmpty ? .empty : .loaded
                notificationStore?.setLoadingState(state)
                return
            }
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
        notificationStore?.setUnreadCount(0)
        do {
            let serverUnread: Int?
            if KaiXBackend.token != nil {
                serverUnread = try await KaiXAPIClient.shared.markNotificationsRead(all: true)
            } else {
                serverUnread = try await NotificationRepository(context: context).markAllRead()
            }
            // Calibrate to the server's authoritative count (it may be > 0 if a
            // new notification landed between the fetch and this action).
            if let serverUnread { notificationStore?.setUnreadCount(serverUnread) }
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
            let serverUnread = try await NotificationRepository(context: context).markRead(notification)
            notificationStore?.setNotifications(notifications)
            if let serverUnread { notificationStore?.setUnreadCount(serverUnread) }
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
            let serverUnread = try await NotificationRepository(context: context).markRead(aggregate.notifications)
            notificationStore?.setNotifications(notifications)
            if let serverUnread { notificationStore?.setUnreadCount(serverUnread) }
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
            let serverUnread: Int?
            if shouldMarkRead {
                serverUnread = try await NotificationRepository(context: context).markRead(aggregate.notifications)
            } else {
                serverUnread = try await NotificationRepository(context: context).markUnread(aggregate.notifications)
            }
            notificationStore?.setNotifications(notifications)
            if let serverUnread { notificationStore?.setUnreadCount(serverUnread) }
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

    private static func entity(from dto: KaiXNotificationDTO) -> NotificationEntity {
        NotificationEntity(
            id: dto.id,
            type: NotificationType(rawValue: dto.type) ?? .system,
            actorId: dto.actor?.id ?? dto.actor_id,
            targetPostId: dto.target_post_id,
            targetCommentId: dto.target_comment_id,
            targetListingId: dto.target_listing_id,
            targetConversationId: dto.target_conversation_id,
            content: dto.content ?? "",
            isRead: dto.is_read,
            createdAt: parseDate(dto.created_at) ?? .now,
            remoteId: dto.id,
            syncStatus: .synced
        )
    }

    // Delegate to the cached KXDateParsing formatters instead of allocating a
    // fresh ISO8601DateFormatter on every call (hot path during list decode).
    private static func parseDate(_ raw: String?) -> Date? { KXDateParsing.parse(raw) }
}

struct AggregatedNotification: Identifiable {
    let id: String
    let notifications: [NotificationEntity]
    let latest: NotificationEntity
    let actorIds: [String]

    var type: NotificationType { latest.type }
    var targetPostId: String? { latest.targetPostId }
    var targetCommentId: String? { latest.targetCommentId }
    var targetListingId: String? { latest.targetListingId }
    var targetConversationId: String? { latest.targetConversationId }
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
        case .message, .listingInquiry:
            // One row per conversation, so parallel chats never collapse
            // into each other.
            return "\(notification.typeRaw)|\(notification.targetConversationId ?? notification.id)"
        case .savedSearch, .favoritePriceDrop, .favoriteClosed:
            // One row per matched/affected listing (server dedupes per
            // user+listing).
            return "\(notification.typeRaw)|\(notification.targetListingId ?? notification.id)"
        case .followDigest:
            // Batched follow summary — collapse all into one digest row.
            return notification.typeRaw
        case .cityDigest, .system:
            return "\(notification.typeRaw)|\(notification.id)"
        }
    }
}
