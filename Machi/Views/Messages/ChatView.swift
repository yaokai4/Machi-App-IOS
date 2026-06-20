import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ChatBootstrapView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var thread: MessageThreadEntity?
    @State private var errorMessage: String?

    let currentUser: UserEntity
    let peer: UserEntity

    var body: some View {
        Group {
            if let thread {
                ChatView(thread: thread, currentUser: currentUser, peer: peer)
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) {
                    Task { await loadThread() }
                }
            } else {
                LoadingView()
            }
        }
        .task {
            await loadThread()
        }
    }

    private func loadThread() async {
        do {
            thread = try await MessageRepository(context: modelContext).getOrCreateThread(
                currentUserId: currentUser.id,
                peerUserId: peer.id
            )
        } catch {
            errorMessage = error.kaixUserMessage
        }
    }
}

struct ConversationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var thread: MessageThreadEntity?
    @State private var peer: UserEntity?
    @State private var state: ScreenState = .idle

    let conversationId: String
    let currentUser: UserEntity

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                LoadingView()
            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await load() }
                }
            case .empty:
                EmptyStateView(title: L("emptyMessages", language), subtitle: L("newConversationsHere", language), systemImage: "envelope")
            case .loaded:
                if let thread {
                    ChatView(thread: thread, currentUser: currentUser, peer: peer)
                }
            }
        }
        .task(id: conversationId) {
            await load()
        }
    }

    private func load() async {
        state = .loading
        do {
            if KaiXBackend.token != nil {
                let repository = MessageRepository(context: modelContext)
                guard let loadedThread = try await repository.fetchThreads(currentUserId: currentUser.id).first(where: { $0.id == conversationId }) else {
                    state = .empty
                    return
                }
                thread = loadedThread
                if let peerId = repository.peerUserId(in: loadedThread, currentUserId: currentUser.id) {
                    if let cachedPeer = repository.cachedPeers()[peerId] {
                        peer = cachedPeer
                    } else {
                        peer = try? await UserRepository(context: modelContext).fetchUser(id: peerId)
                    }
                }
                state = .loaded
                return
            }
            var descriptor = FetchDescriptor<MessageThreadEntity>(
                predicate: #Predicate { $0.id == conversationId }
            )
            descriptor.fetchLimit = 1
            guard let loadedThread = try modelContext.fetch(descriptor).first else {
                state = .empty
                return
            }
            thread = loadedThread
            if let peerId = MessageRepository(context: modelContext).peerUserId(in: loadedThread, currentUserId: currentUser.id) {
                peer = try await UserRepository(context: modelContext).fetchUser(id: peerId)
            }
            state = .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}

struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var messageStore: MessageStore
    @StateObject private var viewModel = ChatViewModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isShowingDeleteThreadConfirm = false
    @State private var actionMessage: String?

    let thread: MessageThreadEntity
    let currentUser: UserEntity
    let peer: UserEntity?

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            if viewModel.isShowingSearchTools {
                chatSearchTools
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                switch viewModel.state {
                case .loading, .idle:
                    LoadingView()
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await viewModel.load(context: modelContext, thread: thread, messageStore: messageStore) }
                    }
                case .empty, .loaded:
                    messageList
                }
            }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let noticeMessage = actionMessage ?? viewModel.errorMessage {
                    KXInlineNotice(message: noticeMessage) {
                        actionMessage = nil
                        viewModel.errorMessage = nil
                    }
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                draftMediaPreview
                ChatInputBar(
                    pickerItems: $pickerItems,
                    text: $viewModel.inputText,
                    mediaDrafts: viewModel.mediaDrafts,
                    isSending: viewModel.isSending,
                    canSend: viewModel.canSend,
                    send: { Task { await viewModel.send(context: modelContext, thread: thread, currentUser: currentUser, messageStore: messageStore) } }
                )
            }
        }
        .task(id: thread.id) {
            await loadAndMarkRead()
            await pollMessagesLoop()
        }
        .onChange(of: messageStore.conversationsById[thread.id]?.lastMessageAt) { _, _ in
            guard !viewModel.hasActiveFilters else { return }
            Task { await loadAndMarkRead() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXConversationShouldRefresh)) { note in
            guard !viewModel.hasActiveFilters else { return }
            let conversationId = note.userInfo?["conversationId"] as? String
            guard conversationId == nil || conversationId == thread.id else { return }
            Task { await loadAndMarkRead() }
        }
        .onChange(of: pickerItems) { _, newValue in
            Task {
                var failedToLoad = false
                for item in newValue {
                    let videoContentType = item.supportedContentTypes.first { $0.conforms(to: .movie) }
                    if videoContentType != nil {
                        guard let picked = try? await item.loadTransferable(type: PickedVideoFile.self) else {
                            failedToLoad = true
                            continue
                        }
                        await viewModel.addVideo(fileURL: picked.url, contentType: videoContentType, language: language, messageStore: messageStore)
                    } else {
                        guard let data = try? await item.loadTransferable(type: Data.self) else {
                            failedToLoad = true
                            continue
                        }
                        await viewModel.addMedia(data: data, isVideo: false, language: language, messageStore: messageStore)
                    }
                }
                if failedToLoad {
                    viewModel.errorMessage = L("mediaFailed", language)
                }
                pickerItems = []
            }
        }
        .confirmationDialog(L("deleteConversation", language), isPresented: $isShowingDeleteThreadConfirm, titleVisibility: .visible) {
            Button(L("deleteConversation", language), role: .destructive) {
                Task { await deleteThread() }
            }
            Button(L("cancel", language), role: .cancel) {}
        }
    }

    private func loadAndMarkRead() async {
        await viewModel.load(context: modelContext, thread: thread, messageStore: messageStore)
        guard !viewModel.hasActiveFilters else { return }
        try? await MessageRepository(context: modelContext).markThreadRead(thread)
        messageStore.setUnreadCount(0, conversationId: thread.id)
    }

    private func pollMessagesLoop() async {
        guard KaiXBackend.token != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !viewModel.hasActiveFilters else { continue }
            await loadAndMarkRead()
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)

            Button {
                if let peer {
                    router.open(.profile(userId: peer.id))
                }
            } label: {
                HStack(spacing: 10) {
                    AvatarView(user: peer, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(peer?.displayName ?? L("messages", language))
                                .font(.headline.weight(.semibold))
                            KXUserBadge(user: peer)
                        }
                        Text("@\(peer?.username ?? L("unknownUser", language))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    viewModel.isShowingSearchTools.toggle()
                }
            } label: {
                Image(systemName: viewModel.isShowingSearchTools ? "magnifyingglass.circle.fill" : "magnifyingglass")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(viewModel.hasActiveFilters ? KXColor.accent : .primary)
                    .frame(width: 38, height: 38)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("chatSearch", language))

            Menu {
                Button {
                    UIPasteboard.general.string = peer.map { "@\($0.username)" } ?? thread.id
                    actionMessage = L("profileCopied", language)
                } label: {
                    Label(L("copyLink", language), systemImage: "doc.on.doc")
                }

                Button(L("reportUser", language), role: .destructive) {
                    actionMessage = L("reportRecorded", language)
                }

                Button(L("deleteConversation", language), role: .destructive) {
                    isShowingDeleteThreadConfirm = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .kxGlassCircle()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private func deleteThread() async {
        do {
            try await MessageRepository(context: modelContext).deleteThread(thread)
            messageStore.removeConversation(thread.id)
            dismiss()
        } catch {
            actionMessage = error.kaixUserMessage
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        KXMessageBubble(
                            message: message,
                            mediaItems: viewModel.mediaByMessageId[message.id] ?? [],
                            isMine: message.senderId == currentUser.id,
                            peer: peer,
                            onDelete: {
                                Task { await viewModel.deleteMessage(context: modelContext, thread: thread, message: message, messageStore: messageStore) }
                            },
                            onRetry: {
                                Task { await viewModel.retryMessage(context: modelContext, thread: thread, message: message, messageStore: messageStore) }
                            },
                            onOpenPeer: {
                                if let peer {
                                    router.open(.profile(userId: peer.id))
                                }
                            }
                        )
                        .id(message.id)
                    }
                    Color.clear
                        .frame(height: viewModel.mediaDrafts.isEmpty ? 92 : 176)
                        .id(ChatBottomAnchor.id)
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                scrollToLatest(proxy, animated: false)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToLatest(proxy, animated: true)
            }
            .onChange(of: viewModel.messages.last?.id) { _, _ in
                scrollToLatest(proxy, animated: true)
            }
            .onChange(of: viewModel.state) { _, newState in
                if newState == .loaded {
                    scrollToLatest(proxy, animated: false)
                }
            }
            .onChange(of: viewModel.mediaDrafts.count) { _, _ in
                scrollToLatest(proxy, animated: true)
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !viewModel.messages.isEmpty else { return }
        let action = {
            proxy.scrollTo(ChatBottomAnchor.id, anchor: .bottom)
        }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.snappy(duration: 0.22)) {
                    action()
                }
            } else {
                action()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            action()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            action()
        }
    }

    @ViewBuilder
    private var draftMediaPreview: some View {
        if !viewModel.mediaDrafts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.mediaDrafts) { draft in
                        ZStack(alignment: .topTrailing) {
                            CachedMediaImageView(url: draft.thumbnailURL)
                                .frame(width: 82, height: 82)
                                .clipShape(RoundedRectangle(cornerRadius: 14))

                            if draft.type == .video {
                                Image(systemName: "play.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(.black.opacity(0.68))
                                    .clipShape(Circle())
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                                    .padding(6)
                            }

                            Button {
                                viewModel.removeMedia(draft, messageStore: messageStore)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.75))
                            }
                            .padding(5)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .kxGlassBar()
        }
    }

    private var chatSearchTools: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("chatSearchPlaceholder", language), text: $viewModel.searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.load(context: modelContext, thread: thread, messageStore: messageStore) }
                    }
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        Task { await viewModel.load(context: modelContext, thread: thread, messageStore: messageStore) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("clear", language))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .kxGlassCapsule()

            HStack(spacing: 10) {
                DatePicker(
                    L("chatJumpToDate", language),
                    selection: Binding(
                        get: { viewModel.selectedDay ?? Date() },
                        set: { date in
                            viewModel.selectedDay = date
                            Task { await viewModel.load(context: modelContext, thread: thread, messageStore: messageStore) }
                        }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .font(.caption.weight(.semibold))

                Spacer()

                if viewModel.hasActiveFilters {
                    Button {
                        viewModel.clearFilters()
                        Task { await viewModel.load(context: modelContext, thread: thread, messageStore: messageStore) }
                    } label: {
                        Text(L("clearFilters", language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .kxGlassCapsule()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .kxGlassBar()
        .overlay(alignment: .bottom) {
            Divider().opacity(0.24)
        }
    }
}

struct KXMessageBubble: View {
    @Environment(\.appLanguage) private var language
    let message: MessageEntity
    let mediaItems: [MediaEntity]
    let isMine: Bool
    let peer: UserEntity?
    let onDelete: () -> Void
    let onRetry: () -> Void
    let onOpenPeer: () -> Void

    var body: some View {
        let contentType = message.resolvedType(mediaItems: mediaItems)

        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 52) }

            if !isMine {
                Button(action: onOpenPeer) {
                    AvatarView(user: peer, size: 32)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                if !mediaItems.isEmpty {
                    MediaGridView(mediaItems: mediaItems)
                        .frame(maxWidth: contentType == .video ? 236 : 216)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            if message.status == .sending {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.black.opacity(0.20))
                                KXSpinner(size: 24, lineWidth: 2.6, tint: .white)
                            } else if message.status == .failed {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.black.opacity(0.22))
                                Button(action: onRetry) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("retry", language))
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(KXColor.separator.opacity(isMine ? 0.10 : 0.22), lineWidth: 0.6)
                        )
                        .compositingGroup()
                        .shadow(color: KXColor.glassShadow.opacity(isMine ? 0.14 : 0.22), radius: 8, y: 3)
                        .accessibilityLabel(contentType == .video ? "视频消息" : "图片消息")
                }

                if let visibleContent = message.visibleContent {
                    Text(visibleContent)
                        .font(.body)
                        .foregroundStyle(isMine ? .white : .primary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(isMine ? KXColor.accent : KXColor.cardBackground)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isMine ? Color.clear : KXColor.separator, lineWidth: 0.6)
                        )
                        .shadow(color: isMine ? Color.clear : KXColor.glassShadow.opacity(0.65), radius: 5, y: 2)
                }

                HStack(spacing: 5) {
                    Text(DateFormatterUtils.relativeText(from: message.createdAt, language: language))
                    if isMine {
                        Text(message.status == .failed ? L("sendFailed", language) : L("sent", language))
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            if !isMine { Spacer(minLength: 52) }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label(L("delete", language), systemImage: "trash")
            }
        }
    }
}

private struct ChatInputBar: View {
    @Environment(\.appLanguage) private var language
    @Binding var pickerItems: [PhotosPickerItem]
    @Binding var text: String
    let mediaDrafts: [MediaDraft]
    let isSending: Bool
    let canSend: Bool
    let send: () -> Void

    var body: some View {
        let hasVideo = mediaDrafts.contains { $0.type == .video }
        let imageCount = mediaDrafts.filter { $0.type == .image }.count
        let remainingImageSlots = Swift.max(1, KaiXConfig.maxImageItemsPerPost - imageCount)
        HStack(alignment: .bottom, spacing: 9) {
            HStack(spacing: 5) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: remainingImageSlots, matching: .images) {
                    ChatInputToolIcon(systemImage: "photo", disabled: hasVideo || imageCount >= KaiXConfig.maxImageItemsPerPost)
                }
                .disabled(hasVideo || imageCount >= KaiXConfig.maxImageItemsPerPost)

                PhotosPicker(selection: $pickerItems, maxSelectionCount: KaiXConfig.maxVideoItemsPerPost, matching: .videos) {
                    ChatInputToolIcon(systemImage: "video", disabled: !mediaDrafts.isEmpty)
                }
                .disabled(!mediaDrafts.isEmpty)
            }
            .frame(height: 42)

            TextField(L("messagePlaceholder", language), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit {
                    if canSend && !isSending {
                        send()
                    }
                }
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(KXColor.elevatedBackground.opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(KXColor.separator.opacity(0.24), lineWidth: 0.7)
                )

            Button {
                guard canSend, !isSending else { return }
                send()
            } label: {
                if isSending {
                    KXSpinner(size: 18, lineWidth: 2.2, tint: canSend ? .white : KXColor.accent)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.bold))
                }
            }
            .frame(width: 44, height: 44)
            .foregroundStyle(canSend ? .white : KXColor.accent.opacity(0.38))
            .background {
                Circle()
                    .fill(canSend ? KXColor.accent : KXColor.accent.opacity(0.08))
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(canSend ? Color.clear : KXColor.accent.opacity(0.12), lineWidth: 0.8))
            .shadow(color: canSend ? KXColor.accent.opacity(0.18) : .clear, radius: 10, y: 4)
            .disabled(!canSend || isSending)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 31, style: .continuous)
                .fill(KXColor.cardBackground.opacity(0.92))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 31, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 31, style: .continuous)
                        .stroke(KXColor.separator.opacity(0.24), lineWidth: 0.7)
                )
                .shadow(color: KXColor.glassShadow.opacity(0.34), radius: 16, y: 7)
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(KXColor.pageBackground.opacity(0.72))
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [KXColor.separator.opacity(0.38), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 1)
        }
    }
}

private enum ChatBottomAnchor {
    static let id = "chat-bottom-anchor"
}

private struct ChatInputToolIcon: View {
    let systemImage: String
    let disabled: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(disabled ? KXColor.livingMuted.opacity(0.42) : KXColor.accent)
            .frame(width: 34, height: 38)
            .background {
                Circle()
                    .fill(disabled ? KXColor.softBackground.opacity(0.28) : KXColor.accent.opacity(0.09))
            }
            .overlay(Circle().stroke(KXColor.separator.opacity(disabled ? 0.10 : 0.18), lineWidth: 0.7))
            .contentShape(Circle())
    }
}
