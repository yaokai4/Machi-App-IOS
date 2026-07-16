import SwiftData
import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
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
            // Seed from the already-synced NotificationStore so re-opening the
            // sheet renders instantly instead of flashing a full-screen spinner
            // and re-fetching; load() then refreshes silently in the background.
            await viewModel.hydrate(from: notificationStore, context: modelContext)
            await viewModel.load(context: modelContext, notificationStore: notificationStore)
        }
        .onAppear {
            // Don't banner over the list the user is currently reading.
            SystemNotificationService.shared.suppressBanners = true
        }
        .onDisappear {
            SystemNotificationService.shared.suppressBanners = false
        }
        .overlay(alignment: .top) {
            if let message = viewModel.transientError {
                KXInlineNotice(message: message, tint: .orange) {
                    viewModel.transientError = nil
                }
                .padding(.top, 76)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading, .idle:
            // I2-5 首载骨架:通知行也是「头像 + 两行」,复用会话骨架行保持
            // 列表节奏,替代整屏 spinner(hydrate 命中缓存时根本走不到这里)。
            ScrollView {
                LazyVStack(spacing: KXSpacing.sm) {
                    ForEach(0..<6, id: \.self) { _ in
                        ConversationSkeletonRow()
                            .kxGlassSurface(radius: KXRadius.lg)
                    }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, KXSpacing.md)
            }
            .scrollDisabled(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .empty:
            emptyContent
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load(context: modelContext, notificationStore: notificationStore) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if filteredNotifications.isEmpty {
                // The state machine only reaches .loaded when the inbox is
                // non-empty, so an empty *filtered* set means the active filter
                // matched nothing — show filter-specific copy, not "no
                // notifications at all" (which would contradict the All tab).
                filteredEmptyContent
            } else {
                notificationList
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L("notifications", language))
                // 与 MessagesView 大标题一致,随 Dynamic Type 缩放(原冻结字号 token 不缩放)。
                .kxScaledFont(32, relativeTo: .largeTitle, weight: .bold)
            Spacer()
            Button {
                Task {
                    await viewModel.markAllRead(context: modelContext, notificationStore: notificationStore)
                    dismiss()
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("markAllRead", language))
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.xl)
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
                            openNotification(item, route: .profile(userId: actorId))
                        },
                        onOpenTarget: {
                            if let route = route(for: item) {
                                openNotification(item, route: route)
                            } else {
                                // Target-less announcements and malformed legacy
                                // rows are acknowledgements, not navigation errors.
                                // Never show an alarming modal merely because a
                                // server row has no longer-valid deep-link target.
                                markReadInBackground(item)
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 5, leading: KXSpacing.screen, bottom: 5, trailing: KXSpacing.screen))
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
                        if !item.isRead {
                            Button {
                                Task { await viewModel.markRead(context: modelContext, aggregate: item, notificationStore: notificationStore) }
                            } label: {
                                Label(L("markRead", language), systemImage: "envelope.open")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, KXSpacing.xs, for: .scrollContent)
        .contentMargins(.bottom, chrome.bottomContentPadding + 24, for: .scrollContent)
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
            .padding(.horizontal, KXSpacing.screen)
            .padding(.top, 34)
            .padding(.bottom, chrome.bottomContentPadding + 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .refreshable {
            await viewModel.load(context: modelContext, notificationStore: notificationStore)
        }
    }

    private var filteredEmptyContent: some View {
        ScrollView {
            KXStatePanel(
                title: L("noFilteredNotifications", language),
                subtitle: L("noFilteredNotificationsHint", language),
                systemImage: "line.3.horizontal.decrease.circle",
                accent: .orange
            )
            .padding(.horizontal, KXSpacing.screen)
            .padding(.top, 34)
            .padding(.bottom, chrome.bottomContentPadding + 24)
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
        .padding(.horizontal, KXSpacing.screen)
        .padding(.vertical, 10)
    }

    private func route(for item: AggregatedNotification) -> KXRoute? {
        NotificationRouteResolver.route(
            type: item.type,
            actorId: item.actorIds.first,
            currentUserId: currentUser.id,
            postId: item.targetPostId,
            commentId: item.targetCommentId,
            listingId: item.targetListingId,
            conversationId: item.targetConversationId
        )
    }

    private func openNotification(_ item: AggregatedNotification, route: KXRoute) {
        // Navigate first — the tap must feel instant. Marking read is
        // fire-and-forget: awaiting it here held the navigation hostage for a
        // full network round-trip (1–3s of dead tap on a weak connection).
        let tab = NotificationRouteResolver.preferredTab(for: route)
        dismiss()
        chrome.select(tab)
        router.setActiveTab(tab)
        router.open(route, in: tab)
        markReadInBackground(item)
    }

    private func markReadInBackground(_ item: AggregatedNotification) {
        guard !item.isRead else { return }
        Task {
            await viewModel.markRead(context: modelContext, aggregate: item, notificationStore: notificationStore)
        }
    }
}

private struct NotificationCard: View {
    @Environment(\.appLanguage) private var language
    let notification: AggregatedNotification
    let actors: [String: UserEntity]
    let onOpenProfile: (String) -> Void
    let onOpenTarget: () -> Void

    private var primaryActor: UserEntity? {
        notification.actorIds.compactMap { actors[$0] }.first
    }

    private var isUnread: Bool { !notification.isRead }

    var body: some View {
        HStack(alignment: .center, spacing: KXSpacing.md) {
            // Avatar → opens the actor's profile.
            Button {
                if let actorId = primaryActor?.id {
                    onOpenProfile(actorId)
                }
            } label: {
                avatar
            }
            .buttonStyle(.plain)
            .accessibilityLabel(primaryActor?.displayName ?? "Machi")

            // The entire remaining row → opens the related content. The hit
            // shape is the full rectangle so taps land anywhere, not just on
            // the glyphs.
            Button(action: onOpenTarget) {
                HStack(alignment: .center, spacing: KXSpacing.sm) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(isUnread ? .bold : .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if !notification.content.isEmpty {
                            Text(notification.content)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Text(DateFormatterUtils.relativeText(from: notification.createdAt, language: language))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isUnread {
                        Circle()
                            .fill(KXColor.accent)
                            .frame(width: 9, height: 9)
                            .shadow(color: KXColor.accent.opacity(0.45), radius: 3, y: 1)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Unread is otherwise conveyed only visually (accent rail/dot, bold
            // title). Speak it so VoiceOver can distinguish read from unread.
            .accessibilityValue(isUnread ? L("unread", language) : "")
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .background(cardBackground)
        .overlay(alignment: .leading) {
            // A slim accent rail marks unread items at a glance, the way Mail
            // does — far cleaner than a "已读/未读" pill on every single row.
            if isUnread {
                RoundedRectangle(cornerRadius: KXRadius.xxs, style: .continuous)
                    .fill(KXColor.accent)
                    .frame(width: 3.5)
                    .padding(.vertical, KXSpacing.md)
                    .padding(.leading, 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .stroke(isUnread ? KXColor.accent.opacity(0.16) : KXColor.separator.opacity(0.35), lineWidth: 0.6)
        )
        .shadow(color: KXColor.glassShadow.opacity(isUnread ? 0.16 : 0.07), radius: isUnread ? 9 : 5, y: 3)
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarView(user: primaryActor, size: KXAvatarSize.md)
            // Floating type badge: a soft gradient pill at the avatar's corner
            // with a colored shadow, instead of a flat solid circle.
            Image(systemName: icon)
                .kxScaledFont(9, weight: .black)
                .foregroundStyle(KXColor.onTint(color))
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [color.opacity(0.92), color],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .overlay(Circle().stroke(KXColor.elevatedBackground, lineWidth: 2))
                .shadow(color: color.opacity(0.32), radius: 2.5, y: 1)
                .offset(x: 3, y: 3)
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isUnread {
            // Unread rows lift off the page with a faint accent wash.
            KXColor.accent.opacity(0.06)
        } else {
            KXColor.cardBackground
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
        // No meaningful actor — the "actor" is just the listing's seller.
        case .savedSearch: return L("notifSavedSearch", language)
        case .favoritePriceDrop: return L("notifFavoritePriceDrop", language)
        case .favoriteClosed: return L("notifFavoriteClosed", language)
        case .followDigest: return L("notifFollowDigest", language)
        case .cityDigest: return L("notifCityDigest", language)
        // Admin broadcasts carry their own custom title; fall back to the
        // generic "系统通知" only when none was set.
        case .system:
            return notification.customTitle.isEmpty ? L("systemNotification", language) : notification.customTitle
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
        case .savedSearch: "sparkle.magnifyingglass"
        case .favoritePriceDrop: "arrow.down.circle.fill"
        case .favoriteClosed: "xmark.circle.fill"
        case .followDigest: "person.2.fill"
        case .cityDigest: "building.2.fill"
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
        case .savedSearch: .yellow
        case .favoritePriceDrop: .green
        case .favoriteClosed: .red
        case .followDigest: .purple
        case .cityDigest: .blue
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
        case .follows: type == .follow || type == .followDigest
        // Saved-search matches + favorite (price drop / closed) + city digests are
        // non-social announcements — grouped under System so they surface under a
        // filter, not just "All". (message / listing_inquiry are intentionally
        // All-only: they are DM-backed and belong to the Messages tab.)
        case .system: [.system, .savedSearch, .favoritePriceDrop, .favoriteClosed, .cityDigest].contains(type)
        }
    }
}
