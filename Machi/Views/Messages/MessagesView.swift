import SwiftData
import SwiftUI

struct MessagesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var messageStore: MessageStore
    @StateObject private var viewModel = MessagesViewModel()
    @State private var isShowingNewConversation = false

    let currentUser: UserEntity

    var body: some View {
        VStack(spacing: 0) {
            MessagesHeaderView(title: L("messages", language)) {
                isShowingNewConversation = true
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load(context: modelContext, currentUser: currentUser, messageStore: messageStore)
        }
        .alert(L("error", language), isPresented: Binding(
            get: { viewModel.transientError != nil },
            set: { if !$0 { viewModel.transientError = nil } }
        )) {
            Button(L("ok", language), role: .cancel) {}
        } message: {
            Text(viewModel.transientError ?? "")
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

    private var conversationList: some View {
        List {
            Section {
                ForEach(viewModel.threads) { thread in
                    let peer = peer(for: thread)
                    Button {
                        router.open(.conversation(conversationId: thread.id))
                    } label: {
                        MessageConversationCard(thread: thread, peer: peer)
                    }
                    .buttonStyle(.plain)
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
        .contentMargins(.bottom, chrome.bottomContentPadding, for: .scrollContent)
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
            .padding(.bottom, chrome.bottomContentPadding)
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
}

private struct MessagesHeaderView: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let onCompose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 32, weight: .semibold))
            Spacer()
            Button(action: onCompose) {
                Image(systemName: "square.and.pencil")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("newMessage", language))
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
            let remoteUsers = try await KaiXAPIClient.shared.mutualMessageFriends(limit: 50)
            users = remoteUsers
                .map(UserRepository.entity(from:))
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            state = users.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}

private struct MessageConversationCard: View {
    @Environment(\.appLanguage) private var language
    let thread: MessageThreadEntity
    let peer: UserEntity?

    var body: some View {
        HStack(spacing: 11) {
            AvatarView(user: peer, size: 48)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(.green)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color(.systemBackground).opacity(0.78), lineWidth: 2))
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(peer?.displayName ?? L("unknownUser", language))
                        .font(.subheadline.weight(.semibold))
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.blue)
                    .clipShape(Circle())
            }
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
