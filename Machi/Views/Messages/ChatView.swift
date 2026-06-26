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
    @EnvironmentObject private var messageStore: MessageStore
    @State private var thread: MessageThreadEntity?
    @State private var peer: UserEntity?
    @State private var state: ScreenState = .idle

    let conversationId: String
    let currentUser: UserEntity

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ChatSkeletonView()
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
        // Cache-first: if this conversation is already in the in-memory store
        // (tapped from the list, or seen this session), render the chat
        // instantly instead of waiting on a full conversations fetch. ChatView
        // then seeds cached messages + refreshes from the server.
        if thread == nil, let cached = messageStore.conversationsById[conversationId] {
            let repository = MessageRepository(context: modelContext)
            thread = cached
            if let peerId = repository.peerUserId(in: cached, currentUserId: currentUser.id) {
                peer = repository.cachedPeers()[peerId]
            }
            state = .loaded
            return
        }
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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var messageStore: MessageStore
    @StateObject private var viewModel = ChatViewModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isShowingDeleteThreadConfirm = false
    @State private var actionMessage: String?
    /// Unread count captured when the chat opens, before we mark it read — used
    /// to place the "以下是新消息" divider above the first message that arrived
    /// since the user last looked at this thread.
    @State private var unreadAtOpen = 0
    @State private var didCaptureUnread = false

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
                    // No cache yet → chat-shaped skeleton (not a bare spinner),
                    // so the page reads as "a chat that's filling in" instantly.
                    ChatSkeletonView()
                case .error(let message):
                    ChatLoadErrorView(message: message) {
                        Task { await viewModel.load(context: modelContext, thread: thread, messageStore: messageStore) }
                    }
                case .empty:
                    ChatEmptyView(language: language)
                case .loaded:
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
            if !didCaptureUnread {
                unreadAtOpen = messageStore.conversationsById[thread.id]?.unreadCount ?? thread.unreadCount
                didCaptureUnread = true
            }
            await loadAndMarkRead()
            await pollMessagesLoop()
        }
        .onChange(of: scenePhase) { _, phase in
            viewModel.isForeground = (phase == .active)
            // Coming back to the foreground: pull once immediately instead of
            // waiting up to 3s for the next poll tick.
            if phase == .active, KaiXBackend.token != nil, !viewModel.hasActiveFilters {
                Task { await loadAndMarkRead() }
            }
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
            // Skip the network round-trip while backgrounded, while the user is
            // filtering (search/date), or mid-send — polling during a send can
            // momentarily clobber the optimistic pending bubble.
            guard !Task.isCancelled, !viewModel.hasActiveFilters, viewModel.isForeground, !viewModel.isSending else { continue }
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
                    ForEach(timelineItems) { item in
                        switch item.kind {
                        case .day(let date):
                            ChatDaySeparator(date: date, language: language)
                        case .newDivider:
                            ChatNewMessagesDivider(language: language)
                        case .message(let message):
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
                    }
                    // The bottom input bar is attached via .safeAreaInset, which
                    // already insets the scroll content above it (and above the
                    // draft preview). A small anchor is all that's needed —
                    // the old 92/176 spacer double-counted and floated the last
                    // bubble far above the keyboard.
                    Color.clear
                        .frame(height: 8)
                        .id(ChatBottomAnchor.id)
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .kxReadableWidth()
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

    /// First message that arrived since the user last read this thread, used to
    /// anchor the "以下是新消息" divider. The unread count captured at open
    /// points at the tail of the timeline; we only show the divider when that
    /// message is from the peer (you never get a "new" banner for your own).
    private var newMessageAnchorId: String? {
        guard unreadAtOpen > 0, viewModel.messages.count >= unreadAtOpen else { return nil }
        let candidate = viewModel.messages[viewModel.messages.count - unreadAtOpen]
        guard candidate.senderId != currentUser.id else { return nil }
        return candidate.id
    }

    /// Flattens the message array into a render list with day separators and
    /// the new-message divider interleaved. Computed once per body pass; cheap
    /// (a single linear walk, no per-row work in the bubble itself).
    private var timelineItems: [ChatTimelineItem] {
        var result: [ChatTimelineItem] = []
        let calendar = Calendar.current
        var lastDay: Date?
        let anchor = newMessageAnchorId
        for message in viewModel.messages {
            let day = calendar.startOfDay(for: message.createdAt)
            if lastDay != day {
                result.append(ChatTimelineItem(kind: .day(day)))
                lastDay = day
            }
            if let anchor, message.id == anchor {
                result.append(ChatTimelineItem(kind: .newDivider))
            }
            result.append(ChatTimelineItem(kind: .message(message)))
        }
        return result
    }

    @ViewBuilder
    private var draftMediaPreview: some View {
        if !viewModel.mediaDrafts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.mediaDrafts) { draft in
                        draftChip(draft)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .kxGlassBar()
        }
    }

    private func draftChip(_ draft: MediaDraft) -> some View {
        // Every affordance is an overlay on the fixed 82×82 thumbnail. The old
        // play badge used `.frame(maxWidth/maxHeight: .infinity)` inside the
        // ZStack, which — proposed an unbounded width by the horizontal
        // ScrollView — exploded the chip to full size (the stray floating play
        // button). Overlays stay clamped to the thumbnail.
        let isUploading = viewModel.isSending && viewModel.sendUploadProgress != nil
        return CachedMediaImageView(url: draft.thumbnailURL)
            .frame(width: 82, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if draft.type == .video {
                    Image(systemName: "play.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.62), in: Circle())
                        .padding(5)
                }
            }
            .overlay {
                if isUploading, let progress = viewModel.sendUploadProgress {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.black.opacity(0.46))
                        ChatUploadProgressRing(progress: progress)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(KXColor.separator.opacity(0.22), lineWidth: 0.6)
            )
            .overlay(alignment: .topTrailing) {
                if !isUploading {
                    Button {
                        viewModel.removeMedia(draft, messageStore: messageStore)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.white, .black.opacity(0.75))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
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

    /// Cap long text bubbles at ~74% of the screen so they read like chat
    /// bubbles and never run edge-to-edge.
    private var bubbleMaxWidth: CGFloat { UIScreen.main.bounds.width * 0.74 }

    private var retryLabel: String { language == .ja ? "再送信" : language == .en ? "Retry" : "点击重试" }
    private var sendingLabel: String { language == .ja ? "送信中…" : language == .en ? "Sending…" : "发送中…" }

    var body: some View {
        let contentType = message.resolvedType(mediaItems: mediaItems)

        HStack(alignment: .top, spacing: 8) {
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
                                .fill(isMine
                                      ? AnyShapeStyle(LinearGradient(
                                            colors: [KXColor.accent, KXColor.accent.opacity(0.86)],
                                            startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(KXColor.cardBackground))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isMine ? Color.clear : KXColor.separator, lineWidth: 0.6)
                        )
                        .shadow(color: isMine ? Color.clear : KXColor.glassShadow.opacity(0.65), radius: 5, y: 2)
                        .frame(maxWidth: bubbleMaxWidth, alignment: isMine ? .trailing : .leading)
                        .textSelection(.enabled)
                }

                HStack(spacing: 5) {
                    Text(DateFormatterUtils.relativeText(from: message.createdAt, language: language))
                        .foregroundStyle(.secondary)
                    if isMine {
                        switch message.status {
                        case .failed:
                            Button(action: onRetry) {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                    Text(L("sendFailed", language))
                                    Text(retryLabel).underline()
                                }
                                .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        case .sending:
                            Text(sendingLabel).foregroundStyle(.secondary)
                        default:
                            Text(L("sent", language)).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption2.weight(.semibold))
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

    @State private var isShowingAttachTray = false
    @State private var isShowingEmoji = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        let hasVideo = mediaDrafts.contains { $0.type == .video }
        let imageCount = mediaDrafts.filter { $0.type == .image }.count
        let remainingImageSlots = Swift.max(1, KaiXConfig.maxImageItemsPerPost - imageCount)
        let imageDisabled = hasVideo || imageCount >= KaiXConfig.maxImageItemsPerPost
        let videoDisabled = !mediaDrafts.isEmpty

        VStack(spacing: 9) {
            if isShowingAttachTray {
                attachTray(remainingImageSlots: remainingImageSlots, imageDisabled: imageDisabled, videoDisabled: videoDisabled)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if isShowingEmoji {
                ChatEmojiPanel { emoji in text += emoji }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            inputRow
        }
        .onChange(of: mediaDrafts.count) { _, count in
            // A draft landed — collapse the tray so the preview/composer is clean.
            if count > 0, isShowingAttachTray {
                withAnimation(.snappy(duration: 0.18)) { isShowingAttachTray = false }
            }
        }
        .onChange(of: inputFocused) { _, focused in
            // Typing replaces the emoji panel with the keyboard (no overlap).
            if focused, isShowingEmoji {
                withAnimation(.snappy(duration: 0.18)) { isShowingEmoji = false }
            }
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

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 9) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isShowingAttachTray.toggle()
                    if isShowingAttachTray { isShowingEmoji = false }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(KXColor.accent)
                    .rotationEffect(.degrees(isShowingAttachTray ? 45 : 0))
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language == .ja ? "メディアを追加" : language == .en ? "Add media" : "添加媒体")

            TextField(L("messagePlaceholder", language), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($inputFocused)
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

            emojiButton
            sendButton
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
    }

    private var emojiButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                isShowingEmoji.toggle()
                if isShowingEmoji {
                    isShowingAttachTray = false
                    // Drop the keyboard so the emoji panel takes its place.
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } else {
                    inputFocused = true
                }
            }
        } label: {
            Image(systemName: isShowingEmoji ? "keyboard" : "face.smiling")
                .font(.title3.weight(.semibold))
                .foregroundStyle(KXColor.accent)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language == .ja ? "絵文字" : language == .en ? "Emoji" : "表情")
    }

    private var sendButton: some View {
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

    private func attachTray(remainingImageSlots: Int, imageDisabled: Bool, videoDisabled: Bool) -> some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: remainingImageSlots, matching: .images) {
                ChatAttachTile(
                    icon: "photo.fill",
                    title: language == .ja ? "写真" : language == .en ? "Photo" : "照片",
                    disabled: imageDisabled
                )
            }
            .disabled(imageDisabled)

            PhotosPicker(selection: $pickerItems, maxSelectionCount: KaiXConfig.maxVideoItemsPerPost, matching: .videos) {
                ChatAttachTile(
                    icon: "video.fill",
                    title: language == .ja ? "動画" : language == .en ? "Video" : "视频",
                    disabled: videoDisabled
                )
            }
            .disabled(videoDisabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }
}

/// One tile in the composer's "+" attachment tray (照片 / 视频).
private struct ChatAttachTile: View {
    let icon: String
    let title: String
    let disabled: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(disabled ? KXColor.livingMuted.opacity(0.5) : KXColor.accent)
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(disabled ? KXColor.softBackground.opacity(0.4) : KXColor.accent.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(KXColor.separator.opacity(0.2), lineWidth: 0.7)
                )
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(disabled ? .secondary : .primary)
        }
    }
}

private enum ChatBottomAnchor {
    static let id = "chat-bottom-anchor"
}

/// One row in the rendered chat timeline: a day separator, the new-message
/// divider, or an actual message bubble.
private struct ChatTimelineItem: Identifiable {
    enum Kind {
        case day(Date)
        case newDivider
        case message(MessageEntity)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .day(let date): return "day-\(Int(date.timeIntervalSince1970))"
        case .newDivider: return "new-divider"
        case .message(let message): return "msg-\(message.id)"
        }
    }
}

/// Centered date pill (今天 / 昨天 / 6月20日) shown above each day's first
/// message — the WeChat-style time grouping.
private struct ChatDaySeparator: View {
    let date: Date
    let language: AppLanguage

    var body: some View {
        Text(Self.label(date, language))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(KXColor.softBackground.opacity(0.9), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    static func label(_ date: Date, _ language: AppLanguage) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return language == .ja ? "今日" : language == .en ? "Today" : "今天"
        }
        if calendar.isDateInYesterday(date) {
            return language == .ja ? "昨日" : language == .en ? "Yesterday" : "昨天"
        }
        let sameYear = calendar.isDate(date, equalTo: .now, toGranularity: .year)
        let template = language == .en ? (sameYear ? "MMMd" : "yMMMd") : (sameYear ? "Md" : "yMd")
        return DateFormatterUtils.localizedTemplateString(
            template,
            localeID: DateFormatterUtils.localeID(for: language),
            date: date
        )
    }
}

/// "以下是新消息" divider above the first message received since last read.
private struct ChatNewMessagesDivider: View {
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            line
            Text(language == .ja ? "ここから新着メッセージ" : language == .en ? "New messages" : "以下是新消息")
                .font(.caption2.weight(.bold))
                .foregroundStyle(KXColor.accent)
                .fixedSize()
            line
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private var line: some View {
        Rectangle()
            .fill(KXColor.accent.opacity(0.28))
            .frame(height: 1)
    }
}

/// Chat-shaped skeleton shown only when a conversation has no cached messages
/// yet — alternating bubble placeholders so opening a chat reads as "filling
/// in" rather than a frozen centre spinner. Pure shapes + redaction = cheap.
private struct ChatSkeletonView: View {
    private let rows: [(mine: Bool, w: CGFloat)] = [
        (false, 0.60), (false, 0.40), (true, 0.52), (false, 0.72), (true, 0.34), (false, 0.46)
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .bottom, spacing: 8) {
                    if r.mine { Spacer(minLength: 52) }
                    if !r.mine { Circle().fill(KXColor.softBackground).frame(width: 32, height: 32) }
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(KXColor.softBackground)
                        .frame(width: UIScreen.main.bounds.width * r.w, height: 40)
                    if !r.mine { Spacer(minLength: 52) }
                }
            }
            Spacer()
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// Calm empty state for a conversation with no messages yet.
private struct ChatEmptyView: View {
    let language: AppLanguage
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(KXColor.livingMuted.opacity(0.5))
            Text(language == .ja ? "まだメッセージはありません。話しかけてみましょう。"
                 : language == .en ? "No messages yet — say hello."
                 : "这里还没有消息，开始聊聊吧。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Non-intrusive load-failure state. The composer below stays usable so the
/// user can still send once the network recovers.
private struct ChatLoadErrorView: View {
    let message: String
    let onRetry: () -> Void
    @Environment(\.appLanguage) private var language
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(language == .ja ? "メッセージを読み込めませんでした"
                 : language == .en ? "Couldn't load messages" : "消息暂时加载失败")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Button(action: onRetry) {
                Text(language == .ja ? "再試行" : language == .en ? "Retry" : "点击重试")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .padding(.horizontal, 22).frame(height: 42)
                    .background(KXColor.accent.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Determinate ring shown over a draft thumbnail while its media streams to
/// S3 — the WeChat-style "uploading NN%" affordance.
private struct ChatUploadProgressRing: View {
    let progress: Double

    private var clamped: Double { Swift.min(Swift.max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.26), lineWidth: 3)
            Circle()
                .trim(from: 0, to: Swift.max(0.02, clamped))
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(clamped * 100))%")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: 44, height: 44)
        .animation(.easeOut(duration: 0.2), value: clamped)
    }
}

