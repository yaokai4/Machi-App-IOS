import SwiftData
import SwiftUI

struct NotificationsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var notificationStore: NotificationStore
    @StateObject private var viewModel = NotificationsViewModel()
    @State private var filter = NotificationFilter.all

    let currentUser: UserEntity

    private var filteredNotifications: [AggregatedNotification] {
        viewModel.groupedNotifications.filter { filter.includes($0.type) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterPicker

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Pull the freshest server notifications first so the list the
            // user just opened isn't stale, then render from SwiftData.
            if KaiXBackend.token != nil {
                await RemoteSyncService.shared.syncNotifications(context: modelContext)
            }
            await viewModel.load(context: modelContext, notificationStore: notificationStore)
        }
        .onAppear {
            // Don't banner over the list the user is currently reading.
            SystemNotificationService.shared.suppressBanners = true
        }
        .onDisappear {
            SystemNotificationService.shared.suppressBanners = false
        }
        .alert(L("error", language), isPresented: Binding(
            get: { viewModel.transientError != nil },
            set: { if !$0 { viewModel.transientError = nil } }
        )) {
            Button(L("ok", language), role: .cancel) {}
        } message: {
            Text(viewModel.transientError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading, .idle:
            LoadingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            emptyContent
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load(context: modelContext, notificationStore: notificationStore) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if filteredNotifications.isEmpty {
                emptyContent
            } else {
                notificationList
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L("notifications", language))
                .font(KXTypography.largeTitle)
            Spacer()
            Button {
                Task { await viewModel.markAllRead(context: modelContext, notificationStore: notificationStore) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.md)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private var notificationList: some View {
        List {
            Section {
                ForEach(filteredNotifications) { item in
                    NotificationCard(
                        notification: item,
                        actors: viewModel.actors,
                        onOpenProfile: { actorId in
                            router.open(.profile(userId: actorId))
                        },
                        onOpenTarget: {
                            Task { await viewModel.markRead(context: modelContext, aggregate: item, notificationStore: notificationStore) }
                            if let route = route(for: item) {
                                router.open(route)
                            } else {
                                router.routeErrorMessage = L("postDeletedHelp", language)
                            }
                        },
                        onMarkRead: {
                            Task { await viewModel.markRead(context: modelContext, aggregate: item, notificationStore: notificationStore) }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: KXSpacing.screen, bottom: 4, trailing: KXSpacing.screen))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(context: modelContext, aggregate: item, notificationStore: notificationStore) }
                        } label: {
                            Label(L("delete", language), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            Task { await viewModel.toggleRead(context: modelContext, aggregate: item, notificationStore: notificationStore) }
                        } label: {
                            Label(item.isRead ? L("markUnread", language) : L("markRead", language), systemImage: item.isRead ? "envelope.badge" : "envelope.open")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, KXSpacing.xs, for: .scrollContent)
        .contentMargins(.bottom, chrome.bottomContentPadding, for: .scrollContent)
        .refreshable {
            await viewModel.load(context: modelContext, notificationStore: notificationStore)
        }
    }

    private var emptyContent: some View {
        ScrollView {
            KXStatePanel(
                title: L("emptyNotifications", language),
                subtitle: L("notificationsHere", language),
                systemImage: "bell.badge",
                accent: .orange
            )
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 34)
            .padding(.bottom, chrome.bottomContentPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .refreshable {
            await viewModel.load(context: modelContext, notificationStore: notificationStore)
        }
    }

    private var filterPicker: some View {
        KXSegmentedControl(NotificationFilter.allCases, selection: $filter, itemMinWidth: 54, itemHeight: 32) { item in
            Text(item.title(language))
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.vertical, 10)
    }

    private func route(for item: AggregatedNotification) -> KXRoute? {
        if (item.type == .message || item.type == .listingInquiry),
           let conversationId = item.targetConversationId {
            return .conversation(conversationId: conversationId)
        }
        if let postId = item.targetPostId {
            switch item.type {
            case .comment, .reply:
                return .postDetailComment(postId: postId, commentId: item.targetCommentId)
            default:
                return .postDetail(postId: postId)
            }
        }
        if item.type == .follow, let actorId = item.actorIds.first {
            return .profile(userId: actorId)
        }
        return nil
    }
}

private struct NotificationCard: View {
    @Environment(\.appLanguage) private var language
    let notification: AggregatedNotification
    let actors: [String: UserEntity]
    let onOpenProfile: (String) -> Void
    let onOpenTarget: () -> Void
    let onMarkRead: () -> Void

    private var primaryActor: UserEntity? {
        notification.actorIds.compactMap { actors[$0] }.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.md) {
            Button {
                if let actorId = primaryActor?.id {
                    onOpenProfile(actorId)
                }
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(user: primaryActor, size: KXAvatarSize.md)
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(color)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(KaiXTheme.cardBackground, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)

            Button(action: onOpenTarget) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if !notification.isRead {
                            Circle()
                                .fill(.blue)
                                .frame(width: 7, height: 7)
                        }
                    }

                    Text(notification.content)
                        .font(KXTypography.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text(DateFormatterUtils.relativeText(from: notification.createdAt, language: language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            markReadControl
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.md)
    }

    @ViewBuilder
    private var markReadControl: some View {
        if notification.isRead {
            Label(L("markViewed", language), systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.bold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(.thinMaterial, in: Capsule())
        } else {
            Button(action: onMarkRead) {
                Label(L("markViewed", language), systemImage: "checkmark.circle")
                    .font(.caption2.weight(.bold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(KXColor.accent)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(KXColor.accent.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("markViewed", language))
        }
    }

    private var title: String {
        let name = primaryActor?.displayName ?? "Machi"
        let extra = max(0, notification.actorIds.count - 1)
        let actorText = actorSummary(name: name, extra: extra)
        switch notification.type {
        case .like: return "\(actorText) \(L("notifLiked", language))"
        case .repost: return "\(actorText) \(L("notifReposted", language))"
        case .comment: return "\(actorText) \(L("notifCommented", language))"
        case .reply: return "\(actorText) \(L("notifReplied", language))"
        case .follow: return "\(actorText) \(L("notifFollowed", language))"
        case .mention: return "\(actorText) \(L("notifMentioned", language))"
        case .bookmark: return "\(actorText) \(L("notifBookmarked", language))"
        case .message: return "\(actorText) \(L("notifMessaged", language))"
        case .listingInquiry: return "\(actorText) \(L("notifInquired", language))"
        case .system: return L("systemNotification", language)
        }
    }

    private func actorSummary(name: String, extra: Int) -> String {
        guard extra > 0 else { return name }
        switch language {
        case .ja:
            return "\(name) 他\(extra)人"
        case .en:
            return "\(name) and \(extra) others"
        case .system, .zh:
            return "\(name) 等 \(extra) 人"
        }
    }

    private var icon: String {
        switch notification.type {
        case .like: "heart.fill"
        case .repost: "arrow.2.squarepath"
        case .comment: "bubble.left.fill"
        case .reply: "arrowshape.turn.up.left.fill"
        case .follow: "person.badge.plus"
        case .mention: "at"
        case .bookmark: "bookmark.fill"
        case .message: "envelope.fill"
        case .listingInquiry: "tag.fill"
        case .system: "bell.fill"
        }
    }

    private var color: Color {
        switch notification.type {
        case .like: .pink
        case .repost: .green
        case .comment: .blue
        case .reply: .cyan
        case .follow: .purple
        case .mention: .indigo
        case .bookmark: .orange
        case .message: .teal
        case .listingInquiry: .mint
        case .system: .secondary
        }
    }
}

private enum NotificationFilter: String, CaseIterable, Identifiable {
    case all
    case interactions
    case comments
    case follows
    case system

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .all: L("all", language)
        case .interactions: L("interactionNotifications", language)
        case .comments: L("comments", language)
        case .follows: L("follow", language)
        case .system: L("system", language)
        }
    }

    func includes(_ type: NotificationType) -> Bool {
        switch self {
        case .all: true
        case .interactions: [.like, .repost, .bookmark, .mention].contains(type)
        case .comments: [.comment, .reply].contains(type)
        case .follows: type == .follow
        case .system: type == .system
        }
    }
}
