import SwiftData
import SwiftUI

struct MessagesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
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
            MessagesHeaderView(title: L("messages", language), unreadCount: notificationStore.unreadCount) {
                isShowingNotifications = true
            }

            inboxModePicker

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load(context: modelContext, currentUser: currentUser, messageStore: messageStore)
        }
        .task(id: mode) {
            if mode == .contacts {
                await loadContacts()
            }
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
            NewConversationView(currentUser: currentUser) { user in
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
            LoadingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(spacing: 8) {
            ForEach(MessageInboxMode.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        mode = item
                    }
                } label: {
                    Label(item.title(language), systemImage: item.icon)
                        .font(.subheadline.weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(mode == item ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(mode == item ? KXColor.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(KXColor.cardBackground.opacity(0.78), in: Capsule())
        .overlay(Capsule().stroke(KXColor.separator, lineWidth: 0.7))
        .padding(.horizontal, KXSpacing.screen)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var contactsContent: some View {
        switch contactsState {
        case .loading, .idle:
            LoadingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .padding(.bottom, 2)

                ForEach(contacts) { user in
                    Button {
                        openConversation(with: user)
                    } label: {
                        MessageContactCard(user: user)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, KXSpacing.sm)
            .padding(.bottom, chrome.bottomContentPadding + 24)
        }
        .refreshable { await loadContacts() }
    }

    private var contactsEmptyContent: some View {
        ScrollView {
            KXStatePanel(
                title: L("mutualFriendsEmptyTitle", language),
                subtitle: L("mutualFriendsOnly", language),
                systemImage: "person.2",
                accent: KXColor.accent
            )
            .padding(.horizontal, KaiXTheme.horizontalPadding)
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
        .refreshable {
            await viewModel.load(context: modelContext, currentUser: currentUser, messageStore: messageStore)
        }
    }

    private var emptyContent: some View {
        ScrollView {
            KXStatePanel(
                title: L("emptyMessages", language),
                subtitle: L("newConversationsHere", language),
                systemImage: "envelope.open",
                accent: KXColor.accent
            )
            .padding(.horizontal, KaiXTheme.horizontalPadding)
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

private struct MessagesHeaderView: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let unreadCount: Int
    let onOpenNotifications: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 32, weight: .semibold))
            Spacer()
            Button(action: onOpenNotifications) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .kxGlassCircle()
                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.system(size: unreadCount > 9 ? 7.5 : 8.5, weight: .black))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .padding(.horizontal, unreadCount > 9 ? 3 : 0)
                            .background(Color(red: 0.93, green: 0.16, blue: 0.34), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.92), lineWidth: 1.1))
                            .offset(x: 4, y: -3)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("notifications", language))
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, 8)
        .padding(.bottom, 12)
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
                    EmptyStateView(title: L("mutualFriendsEmptyTitle", language), subtitle: L("mutualFriendsOnly", language), systemImage: "person.2")
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
                                            .padding(.horizontal, 8)
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
                        .padding(KaiXTheme.horizontalPadding)
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
                .padding(.horizontal, 8)
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
        HStack(spacing: 11) {
            Button {
                if let id = peer?.id {
                    onOpenProfile(id)
                } else {
                    onOpenThread()
                }
            } label: {
                AvatarView(user: peer, size: 48)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(.green)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color(.systemBackground).opacity(0.78), lineWidth: 2))
                    }
            }
            .buttonStyle(.plain)

            Button(action: onOpenThread) {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(peer?.displayName ?? L("unknownUser", language))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            KXUserBadge(user: peer)
                            Spacer()
                            Text(DateFormatterUtils.relativeText(from: thread.lastMessageAt, language: language))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 6) {
                            if let previewIcon {
                                Image(systemName: previewIcon)
                            }
                            Text(previewText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(minWidth: 20, minHeight: 20)
                            .padding(.horizontal, thread.unreadCount > 9 ? 5 : 0)
                            .background(KXColor.accent, in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.82), lineWidth: 1))
                            .shadow(color: KXColor.accent.opacity(0.18), radius: 4, y: 1.5)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .kxGlassSurface(radius: KXRadius.md)
    }

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
