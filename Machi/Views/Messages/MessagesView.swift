import SwiftData
import SwiftUI

struct MessagesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var messageStore: MessageStore
    @EnvironmentObject private var notificationStore: NotificationStore
    @StateObject private var viewModel = MessagesViewModel()
    @State private var mode = MessageInboxMode.conversations
    @State private var isShowingNewConversation = false
    @State private var isShowingNotifications = false
    @State private var contacts: [UserEntity] = []
    @State private var contactsQuery = ""
    @State private var contactsState: ScreenState = .idle

    let currentUser: UserEntity

    var body: some View {
        VStack(spacing: 0) {
            MessagesHeaderView(
                title: L("messages", language),
                // Bell reflects social (like/comment/follow/message) unread only,
                // not every notification kind — matches what tapping it opens.
                unreadCount: notificationStore.socialUnreadCount,
                onNewDirect: {
                    // Starting a DM requires an account: gate the "+" for guests.
                    if currentUser.isGuest {
                        GuestGate.shared.requireLogin(guestMessagesReason)
                    } else {
                        isShowingNewConversation = true
                    }
                },
                onOpenNotifications: { isShowingNotifications = true }
            )

            if currentUser.isGuest {
                GuestMessagesPanel(language: language) {
                    GuestGate.shared.requireLogin(guestMessagesReason)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                inboxModePicker

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: currentUser.id) {
            // Guests have no inbox to load or poll — the panel is a static CTA.
            guard !currentUser.isGuest else { return }
            await refreshInbox()
            await pollInboxLoop()
        }
        .task(id: mode) {
            if mode == .contacts {
                await loadContacts()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXConversationShouldRefresh)) { _ in
            guard mode == .conversations else { return }
            Task { await refreshInbox() }
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.isForeground = (phase == .active)
            if phase == .active, mode == .conversations { Task { await refreshInbox() } }
        }
        .onChange(of: chrome.selectedTab) { _, tab in
            // Coming back to the messages tab: pull once right away instead of
            // waiting up to 8s for the (tab-paused) poll loop's next tick.
            if tab == .messages, mode == .conversations { Task { await refreshInbox() } }
        }
        .overlay(alignment: .top) {
            if let message = viewModel.transientError {
                KXInlineNotice(message: message) {
                    viewModel.transientError = nil
                }
                .padding(.top, 70)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $isShowingNewConversation) {
            NewConversationView(currentUser: currentUser, onMeetPeople: openDiscoverPeople) { user in
                Task {
                    do {
                        let thread = try await MessageRepository(context: modelContext).getOrCreateThread(
                            currentUserId: currentUser.id,
                            peerUserId: user.id
                        )
                        await viewModel.load(context: modelContext, currentUser: currentUser, messageStore: messageStore)
                        isShowingNewConversation = false
                        router.open(.conversation(conversationId: thread.id))
                    } catch {
                        viewModel.transientError = error.kaixUserMessage
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingNotifications) {
            NavigationStack {
                NotificationsView(currentUser: currentUser)
                    .kxRouteDestinations(currentUser: currentUser)
            }
            .presentationDragIndicator(.visible)
        }
    }

    private var guestMessagesReason: String {
        KXListingCopy.pickText(
            language,
            "登录后可以私信房东、卖家和朋友",
            "ログインすると大家さん・出品者・友だちにメッセージを送れます",
            "Log in to message landlords, sellers and friends"
        )
    }

    private func refreshInbox() async {
        await viewModel.load(context: modelContext, currentUser: currentUser, messageStore: messageStore)
    }

    private func pollInboxLoop() async {
        guard KaiXBackend.token != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(8))
            // Only poll the live conversation list while foregrounded AND while
            // the messages tab is actually on screen — hidden tabs keep their
            // views (and this .task) alive, so without the tab guard the inbox
            // poll would keep hitting the server forever after switching away.
            guard !Task.isCancelled,
                  mode == .conversations,
                  viewModel.isForeground,
                  chrome.selectedTab == .messages else { continue }
            await refreshInbox()
        }
    }

    @ViewBuilder
    private var content: some View {
        if mode == .contacts {
            contactsContent
        } else {
            conversationContent
        }
    }

    @ViewBuilder
    private var conversationContent: some View {
        switch viewModel.state {
        case .loading, .idle:
            // Conversation-shaped skeleton (avatar + two lines) instead of a bare
            // centre spinner, so the inbox reads as "filling in".
            ScrollView {
                LazyVStack(spacing: KXSpacing.sm) {
                    ForEach(0..<5, id: \.self) { _ in
                        ConversationSkeletonRow()
                            .kxGlassSurface(radius: KXRadius.lg)
                    }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, KXSpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .empty:
            emptyContent
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.load(context: modelContext, currentUser: currentUser, messageStore: messageStore) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if viewModel.threads.isEmpty {
                emptyContent
            } else {
                conversationList
            }
        }
    }

    private var inboxModePicker: some View {
        HStack(spacing: KXSpacing.sm) {
            ForEach(MessageInboxMode.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        mode = item
                    }
                } label: {
                    Label(item.title(language), systemImage: item.icon)
                        .font(.subheadline.weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(mode == item ? KXColor.onAccent : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(mode == item ? KXColor.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(KXSpacing.xs)
        .background(KXColor.cardBackground.opacity(0.78), in: Capsule())
        .overlay(Capsule().stroke(KXColor.separator, lineWidth: 0.7))
        .padding(.horizontal, KXSpacing.screen)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var contactsContent: some View {
        switch contactsState {
        case .loading, .idle:
            // 联系人也是「头像 + 两行」的行,首载复用会话骨架而不是裸 spinner。
            ScrollView {
                LazyVStack(spacing: KXSpacing.sm) {
                    ForEach(0..<5, id: \.self) { _ in
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
            contactsEmptyContent
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await loadContacts() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            contactsList
        }
    }

    private var contactsList: some View {
        ScrollView {
            LazyVStack(spacing: KXSpacing.sm) {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L("searchPlaceholderShort", language), text: $contactsQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await loadContacts() } }
                    if !contactsQuery.isEmpty {
                        Button {
                            contactsQuery = ""
                            Task { await loadContacts() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("clear", language))
                    }
                }
                .padding(.horizontal, KXSpacing.md)
                .frame(height: 42)
                .kxGlassCapsule()
                .padding(.bottom, KXSpacing.xxs)

                ForEach(contacts) { user in
                    Button {
                        openConversation(with: user)
                    } label: {
                        MessageContactCard(user: user)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.top, KXSpacing.sm)
            .padding(.bottom, chrome.bottomContentPadding + 24)
        }
        .refreshable { await loadContacts() }
    }

    private var contactsEmptyContent: some View {
        ScrollView {
            VStack(spacing: KXSpacing.md) {
                KXStatePanel(
                    title: L("mutualFriendsEmptyTitle", language),
                    subtitle: L("mutualFriendsOnly", language),
                    systemImage: "person.2",
                    accent: KXColor.accent
                )
                MeetPeopleCTAButton(language: language, action: openDiscoverPeople)
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.top, 34)
            .padding(.bottom, chrome.bottomContentPadding + 24)
        }
        .refreshable { await loadContacts() }
    }

    private var conversationList: some View {
        List {
            Section {
                ForEach(viewModel.threads) { thread in
                    let peer = peer(for: thread)
                    MessageConversationCard(
                        thread: thread,
                        peer: peer,
                        onOpenThread: {
                            router.open(.conversation(conversationId: thread.id))
                        },
                        onOpenProfile: { userId in
                            router.open(.profile(userId: userId))
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: KXSpacing.screen, bottom: 6, trailing: KXSpacing.screen))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteThread(context: modelContext, thread: thread, messageStore: messageStore) }
                        } label: {
                            Label(L("delete", language), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            Task { await viewModel.toggleRead(context: modelContext, thread: thread, messageStore: messageStore) }
                        } label: {
                            Label(thread.unreadCount > 0 ? L("markRead", language) : L("markUnread", language), systemImage: thread.unreadCount > 0 ? "envelope.open" : "envelope.badge")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, KXSpacing.md, for: .scrollContent)
        .contentMargins(.bottom, chrome.bottomContentPadding + 24, for: .scrollContent)
        .kxReadableWidth()
        .refreshable {
            await viewModel.load(context: modelContext, currentUser: currentUser, messageStore: messageStore)
        }
    }

    private var emptyContent: some View {
        ScrollView {
            VStack(spacing: KXSpacing.md) {
                EmptyStateView(
                    title: L("emptyMessages", language),
                    subtitle: L("newConversationsHere", language),
                    systemImage: "envelope.open",
                    illustration: .messages
                )
                MeetPeopleCTAButton(language: language, action: openDiscoverPeople)
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.top, 34)
            .padding(.bottom, chrome.bottomContentPadding + 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .refreshable {
            await viewModel.load(context: modelContext, currentUser: currentUser, messageStore: messageStore)
        }
    }

    private func peer(for thread: MessageThreadEntity) -> UserEntity? {
        guard let id = MessageRepository(context: modelContext).peerUserId(in: thread, currentUserId: currentUser.id) else {
            return nil
        }
        return viewModel.peers[id]
    }

    private func loadContacts() async {
        contactsState = contacts.isEmpty ? .loading : .loaded
        do {
            let remoteUsers = try await KaiXAPIClient.shared.mutualMessageFriends(query: contactsQuery, limit: 100)
            contacts = UserRepository.uniqueUsers(remoteUsers.map(UserRepository.entity(from:)))
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            contactsState = contacts.isEmpty ? .empty : .loaded
        } catch {
            if contacts.isEmpty {
                contactsState = .error(error.kaixUserMessage)
            } else {
                contactsState = .loaded
                viewModel.transientError = error.kaixUserMessage
            }
        }
    }

    /// 消息死胡同的出口:互关才能私信的限制不变(防骚扰的产品决策),但每个
    /// 空态都给一条「去发现页认识同城的人」的通道,而不是把用户困在空收件箱里。
    /// 跳转走既有约定(chrome.select + router.setActiveTab,同 SettingsView /
    /// ProfileView 的跨 Tab CTA),并先 popToRoot 保证落在发现页首屏。
    private func openDiscoverPeople() {
        isShowingNewConversation = false
        router.popToRoot(.search)
        chrome.select(.search)
        router.setActiveTab(.search)
    }

    private func openConversation(with user: UserEntity) {
        Task {
            do {
                let thread = try await MessageRepository(context: modelContext).getOrCreateThread(
                    currentUserId: currentUser.id,
                    peerUserId: user.id
                )
                await viewModel.load(context: modelContext, currentUser: currentUser, messageStore: messageStore)
                router.open(.conversation(conversationId: thread.id))
            } catch {
                viewModel.transientError = error.kaixUserMessage
            }
        }
    }
}

private enum MessageInboxMode: String, CaseIterable, Identifiable {
    case conversations
    case contacts

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .conversations: "bubble.left.and.bubble.right"
        case .contacts: "person.2"
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .conversations: L("messageConversations", language)
        case .contacts: L("messageContacts", language)
        }
    }
}

/// Conversation-row skeleton (avatar + two text lines) shown while the inbox
/// loads its first page — mirrors DiscoverView's HotBoardSkeletonRow style.
/// Internal on purpose: the same "avatar + two lines" shape也是通知列表和
/// 联系人列表的首载骨架(I2-5)。
struct ConversationSkeletonRow: View {
    var body: some View {
        HStack(spacing: 11) {
            Circle().fill(KXColor.softBackground).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: KXRadius.xxs).fill(KXColor.softBackground).frame(width: 150, height: 13)
                RoundedRectangle(cornerRadius: KXRadius.xxs).fill(KXColor.softBackground).frame(width: 210, height: 10)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, KXSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// 「去认识同城的人」— the way out of the messages dead-end. DM stays
/// mutual-follow-gated (anti-harassment product decision); this button gives
/// every "no conversations / no mutual friends yet" state a forward path to
/// the Discover page where people can actually be met first.
private struct MeetPeopleCTAButton: View {
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KXSpacing.xs) {
                Image(systemName: "person.2.wave.2")
                    .font(.subheadline.weight(.bold))
                Text(KXListingCopy.pickText(language, "去认识同城的人", "同じ街の人と出会う", "Meet people in your city"))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(KXColor.onAccent)
            .padding(.horizontal, 24)
            .frame(height: 44)
            .background(KXColor.accent, in: Capsule())
            .shadow(color: KXColor.accent.opacity(0.22), radius: 8, y: 3)
        }
        .buttonStyle(KXPressableStyle())
    }
}

/// Guest-mode panel for the messages tab: DMs need an account, so instead of an
/// empty inbox we show a clear, three-language CTA that routes to login.
private struct GuestMessagesPanel: View {
    let language: AppLanguage
    let onLogin: () -> Void

    private func text(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    var body: some View {
        VStack(spacing: KXSpacing.lg) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .kxScaledFont(44, weight: .light)
                .foregroundStyle(KXColor.accent.opacity(0.85))
            Text(text("登录后即可开始私信", "ログインしてメッセージを始めよう", "Log in to start messaging"))
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(text(
                "登录后可以私信房东、卖家和朋友，第一时间收到回复。",
                "ログインすると、大家さん・出品者・友だちにメッセージを送り、返信をすぐに受け取れます。",
                "Log in to message landlords, sellers and friends and get replies right away."
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, KXSpacing.sm)
            Button(action: onLogin) {
                Text(L("login", language))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.onAccent)
                    .padding(.horizontal, 30)
                    .frame(height: 46)
                    .background(KXColor.accent, in: Capsule())
                    .shadow(color: KXColor.accent.opacity(0.24), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.top, KXSpacing.xs)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, KXSpacing.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MessagesHeaderView: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let unreadCount: Int
    var onNewDirect: () -> Void = {}
    let onOpenNotifications: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .kxScaledFont(32, relativeTo: .largeTitle, weight: .semibold)
            Spacer()
            Button(action: onNewDirect) {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("msgNewDirect", language))
            Button(action: onOpenNotifications) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .kxGlassCircle()
                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.system(size: unreadCount > 9 ? 9 : 10, weight: .black))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .padding(.horizontal, unreadCount > 9 ? 3 : 0)
                            .background(KXColor.badge, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.92), lineWidth: 1.1))
                            .offset(x: 4, y: -3)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("notifications", language))
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.md)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }
}

private struct NewConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var users: [UserEntity] = []
    @State private var query = ""
    @State private var state: ScreenState = .idle

    let currentUser: UserEntity
    /// Dead-end escape hatch: "no mutual friends yet" offers a route to the
    /// Discover page (host dismisses this sheet and switches tabs).
    var onMeetPeople: (() -> Void)? = nil
    let onSelect: (UserEntity) -> Void

    private var filteredUsers: [UserEntity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return users }
        let username = trimmed.normalizedUsername
        return users.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
            || $0.username.localizedCaseInsensitiveContains(username)
            || $0.bio.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading, .idle:
                    LoadingView()
                case .empty:
                    // ScrollView keeps EmptyStateView compact so the CTA sits
                    // right under the copy instead of pinning to screen bottom.
                    ScrollView {
                        VStack(spacing: KXSpacing.md) {
                            EmptyStateView(title: L("mutualFriendsEmptyTitle", language), subtitle: L("mutualFriendsOnly", language), systemImage: "person.2")
                            if let onMeetPeople {
                                MeetPeopleCTAButton(language: language, action: onMeetPeople)
                            }
                        }
                        .padding(.horizontal, KXSpacing.screen)
                        .padding(.top, 34)
                    }
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await load() }
                    }
                case .loaded:
                    ScrollView {
                        LazyVStack(spacing: KXSpacing.sm) {
                            HStack(spacing: KXSpacing.sm) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField(L("searchPlaceholder", language), text: $query)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.search)
                                    .onSubmit { Task { await load() } }
                                if !query.isEmpty {
                                    Button {
                                        query = ""
                                        Task { await load() }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L("clear", language))
                                }
                            }
                            .padding(.horizontal, KXSpacing.md)
                            .frame(height: 42)
                            .kxGlassCapsule()

                            if filteredUsers.isEmpty {
                                EmptyStateView(title: L("mutualFriendsEmptyTitle", language), subtitle: L("mutualFriendsOnly", language), systemImage: "person.2")
                                if let onMeetPeople {
                                    MeetPeopleCTAButton(language: language, action: onMeetPeople)
                                }
                            }

                            ForEach(filteredUsers) { user in
                                Button {
                                    onSelect(user)
                                } label: {
                                    HStack(spacing: KXSpacing.md) {
                                        AvatarView(user: user, size: KXAvatarSize.md)
                                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                                            HStack(spacing: KXSpacing.xs) {
                                                Text(user.displayName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                KXUserBadge(user: user)
                                            }
                                            Text("@\(user.username)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Text(L("mutualFriendBadge", language))
                                            .font(.caption2.weight(.black))
                                            .foregroundStyle(KXColor.accent)
                                            .padding(.horizontal, KXSpacing.sm)
                                            .frame(height: 24)
                                            .background(KXColor.accent.opacity(0.10), in: Capsule())
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary.opacity(0.6))
                                    }
                                    .padding(KXSpacing.md)
                                    .kxGlassSurface(radius: KXRadius.md)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(KXSpacing.screen)
                        .padding(.top, KXSpacing.md)
                    }
                }
            }
            .kxPageBackground()
            .navigationTitle(L("newMessage", language))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("cancel", language)) {
                        dismiss()
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            let remoteUsers = try await KaiXAPIClient.shared.mutualMessageFriends(query: query, limit: 50)
            users = UserRepository.uniqueUsers(remoteUsers.map(UserRepository.entity(from:)))
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            state = users.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}

private struct MessageContactCard: View {
    @Environment(\.appLanguage) private var language
    let user: UserEntity

    var body: some View {
        HStack(spacing: KXSpacing.md) {
            AvatarView(user: user, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(user.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    KXUserBadge(user: user)
                }
                Text("@\(user.username)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(L("mutualFriendBadge", language))
                .font(.caption2.weight(.black))
                .foregroundStyle(KXColor.accent)
                .padding(.horizontal, KXSpacing.sm)
                .frame(height: 24)
                .background(KXColor.accent.opacity(0.10), in: Capsule())
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KXColor.accent)
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.md)
    }
}

private struct MessageConversationCard: View {
    @Environment(\.appLanguage) private var language
    let thread: MessageThreadEntity
    let peer: UserEntity?
    let onOpenThread: () -> Void
    let onOpenProfile: (String) -> Void

    var body: some View {
        Button(action: onOpenThread) {
            HStack(spacing: 11) {
                Color.clear
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)

                conversationSummary
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, KXSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
            .kxGlassSurface(radius: KXRadius.lg)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(text("打开会话", "会話を開く", "Open conversation"))
        .overlay(alignment: .leading) {
            Button {
                if let id = peer?.id {
                    onOpenProfile(id)
                } else {
                    onOpenThread()
                }
            } label: {
                // No presence dot: we don't have a real-time presence system,
                // so a green "online" dot would be a fake online status.
                AvatarView(user: peer, size: 48)
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .accessibilityLabel(peer?.displayName ?? L("unknownUser", language))
        }
    }

    private var conversationSummary: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(peer?.displayName ?? L("unknownUser", language))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    KXUserBadge(user: peer)
                    Spacer()
                    Text(DateFormatterUtils.conversationTimestamp(thread.lastMessageAt, language: language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isUnread ? KXColor.accent : .secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                HStack(spacing: 5) {
                    if let previewIcon {
                        Image(systemName: previewIcon)
                            .font(.caption2)
                            .foregroundStyle(isUnread ? KXColor.accent : .secondary)
                    }
                    Text(previewText)
                        .font(.subheadline.weight(isUnread ? .medium : .regular))
                        .foregroundStyle(isUnread ? .primary : .secondary)
                        .lineLimit(1)
                }
            }

            if thread.unreadCount > 0 {
                let unreadText = thread.unreadCount > 99 ? "99+" : "\(thread.unreadCount)"
                Text(unreadText)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(KXColor.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minWidth: 20, minHeight: 20)
                    .padding(.horizontal, unreadText.count > 1 ? 5 : 0)
                    .background(KXColor.accent, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.82), lineWidth: 1))
                    .shadow(color: KXColor.accent.opacity(0.18), radius: 4, y: 1.5)
            }
        }
    }

    private var accessibilityTitle: String {
        let name = peer?.displayName ?? L("unknownUser", language)
        if thread.unreadCount > 0 {
            return "\(name), \(thread.unreadCount) \(text("条未读消息", "件の未読メッセージ", "unread messages")), \(previewText)"
        }
        return "\(name), \(previewText)"
    }

    private func text(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    private var isUnread: Bool { thread.unreadCount > 0 }

    private var previewIcon: String? {
        if isImagePlaceholder { return "photo" }
        if isVideoPlaceholder { return "play.rectangle" }
        return nil
    }

    private var previewText: String {
        if isImagePlaceholder { return L("images", language) }
        if isVideoPlaceholder { return L("videos", language) }
        return thread.lastMessage
    }

    private var isImagePlaceholder: Bool {
        let compact = normalizedPreview
        return compact == "[图片]" || compact == "[圖片]" || compact == "[image]"
    }

    private var isVideoPlaceholder: Bool {
        let compact = normalizedPreview
        return compact == "[视频]" || compact == "[視頻]" || compact == "[video]"
    }

    private var normalizedPreview: String {
        thread.lastMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}
