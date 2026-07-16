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
    /// "以下是新消息" 分割线锚定的消息 id。首次服务端加载完成时一次性解析并固定
    /// (见 resolveNewMessageAnchorIfNeeded)——原先是对实时变化的 messages 做
    /// 尾部偏移的计算属性,每来一条新消息分割线就向下漂移,搜索/日期过滤结果里
    /// 还会凭空出现一条语义错误的分割线。
    @State private var newMessageAnchorId: String?
    @State private var didResolveNewMessageAnchor = false
    /// 本会话所在的宿主 Tab(导航总是压进当前选中的 Tab)。所有刷新/已读路径都
    /// 以 isChatVisible 为前置——隐藏 Tab 会保留视图和 .task,不加守卫的话,
    /// 全局同步一更新 lastMessageAt,藏在别的 Tab 里的会话就会把新消息静默标记
    /// 已读,用户失去全部未读信号。
    @State private var hostTab: AppTab?
    /// 用户是否停留在消息列表底部附近。只有贴近底部(或新消息是自己发的)才自动
    /// 滚底;正在回看历史时绝不拽走视口(微信/iMessage 同款行为)。
    @State private var isNearBottom = true
    /// 用户回看历史期间到达的新消息数,驱动"↓ N 条新消息"悬浮胶囊。
    @State private var pendingNewMessages = 0
    /// 窗口宽度缓存,喂给每个气泡的 maxWidth。曾是 KXMessageBubble 里每次 body
    /// 求值都遍历 UIApplication.connectedScenes 的计算属性(滚动热路径,参照
    /// CityListingChannelView.screenWidth 的修法);滚动几何回调会在 Split View /
    /// Stage Manager 尺寸变化时刷新它。
    @State private var windowWidth: CGFloat = ChatView.resolveWindowWidth()

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
                        // 走 loadAndMarkRead:恢复后既解析"新消息"锚点,也补上
                        // 可见状态下的已读上报(用户此刻正盯着这个会话)。
                        Task { await loadAndMarkRead() }
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
            // The tab this chat lives on: navigation always pushes onto the
            // currently-selected tab, so every refresh path can pause itself
            // while the user is on another tab (a chat left open on a hidden
            // tab used to keep polling the server forever).
            hostTab = chrome.selectedTab
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
            // waiting up to 4s for the next poll tick. Never mid-send — the
            // wholesale refresh would clobber the optimistic `.sending` bubble
            // (and its failure path) before `send` reconciles it. Never while
            // this chat's tab is hidden (isChatVisible) — 隐藏 Tab 的刷新会顺手
            // 把新消息标成已读,吞掉未读信号。
            if phase == .active, KaiXBackend.token != nil, !viewModel.hasActiveFilters, !viewModel.isSending, isChatVisible {
                Task { await loadAndMarkRead() }
            }
        }
        .onChange(of: messageStore.conversationsById[thread.id]?.lastMessageAt) { _, _ in
            // isChatVisible:全局 12s 通知同步会在新 DM 到达时更新 lastMessageAt,
            // 隐藏 Tab 上存活的会话若因此刷新,会把该消息静默标记已读(P1)。
            guard !viewModel.hasActiveFilters, !viewModel.isSending, isChatVisible else { return }
            Task { await loadAndMarkRead() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXConversationShouldRefresh)) { note in
            guard !viewModel.hasActiveFilters, !viewModel.isSending, isChatVisible else { return }
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
        // A send failure (bubble flipped to `.failed`, or a compose error)
        // buzzes an error haptic so the user notices without watching the screen.
        .sensoryFeedback(.error, trigger: viewModel.errorMessage) { _, new in
            new != nil
        }
    }

    /// 会话是否真正"在屏上":App 在前台且宿主 Tab 被选中。隐藏 Tab 会保留视图
    /// (和 .task),所以所有推送式刷新与已读上报都必须以此为前置,否则用户切走
    /// 后到达的新消息会被静默标记已读(轮询循环使用同一判定)。
    private var isChatVisible: Bool {
        viewModel.isForeground && (hostTab.map { chrome.selectedTab == $0 } ?? true)
    }

    private func loadAndMarkRead() async {
        let previousLatestId = viewModel.messages.last?.id
        let didLoadFresh = await viewModel.load(context: modelContext, thread: thread, messageStore: messageStore)
        if didLoadFresh {
            resolveNewMessageAnchorIfNeeded()
        }
        guard !viewModel.hasActiveFilters else { return }
        // 已读回执只在会话真正可见时上报——隐藏 Tab 的刷新绝不能吞掉未读信号。
        guard isChatVisible else { return }
        // 且只在确有新的未读需要确认时才 POST:原先每次 3s 轮询都无条件写服务器
        // (每个打开的会话 20 次/分钟冗余写,后端是 2 核 2G 单机)。
        let latest = viewModel.messages.last
        let sawNewPeerMessage = didLoadFresh
            && previousLatestId != nil
            && latest != nil
            && latest?.id != previousLatestId
            && latest?.senderId != currentUser.id
        let unread = messageStore.unreadCounts[thread.id] ?? thread.unreadCount
        guard unread > 0 || sawNewPeerMessage else { return }
        do {
            try await MessageRepository(context: modelContext).markThreadRead(thread)
            messageStore.setUnreadCount(0, conversationId: thread.id)
        } catch {
            // 失败时不再本地清零:离线清零会让角标先清、下一次全局同步又弹回来
            // (闪烁且与服务器脱钩)。保留本地未读,等下一次可见刷新重试。
        }
    }

    /// 首次服务端加载完成时,把"以下是新消息"锚点一次性解析成具体消息 id 并
    /// 固定,之后新消息到达也不再漂移。过滤(搜索/日期)激活时不解析——结果集
    /// 的尾部偏移毫无意义。
    private func resolveNewMessageAnchorIfNeeded() {
        guard !didResolveNewMessageAnchor,
              viewModel.state == .loaded,
              !viewModel.hasActiveFilters else { return }
        didResolveNewMessageAnchor = true
        guard unreadAtOpen > 0, viewModel.messages.count >= unreadAtOpen else { return }
        let candidate = viewModel.messages[viewModel.messages.count - unreadAtOpen]
        guard candidate.senderId != currentUser.id else { return }
        newMessageAnchorId = candidate.id
    }

    private func pollMessagesLoop() async {
        guard KaiXBackend.token != nil else { return }
        while !Task.isCancelled {
            // I2-4 轮询分级:会话可见时 4s 一档(收件箱保持 8s);推送到达走
            // kaiXConversationShouldRefresh 立即刷新,所以无需更激进的间隔。
            try? await Task.sleep(for: .seconds(4))
            // Skip the network round-trip while backgrounded, while this chat's
            // tab isn't the one on screen (hidden tabs keep their views — and
            // their .task — alive), while the user is filtering (search/date),
            // or mid-send — polling during a send can momentarily clobber the
            // optimistic pending bubble.
            guard !Task.isCancelled,
                  !viewModel.hasActiveFilters,
                  !viewModel.isSending,
                  isChatVisible else { continue }
            await loadAndMarkRead()
        }
    }

    private static func resolveWindowWidth() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.width }
            .first ?? UIScreen.main.bounds.width
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
            .accessibilityLabel(KXListingCopy.pickText(language, "返回", "戻る", "Back"))

            Button {
                if let peer {
                    router.open(.profile(userId: peer.id))
                }
            } label: {
                HStack(spacing: 10) {
                    AvatarView(user: peer, size: 38)
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        HStack(spacing: KXSpacing.xs) {
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

                if peer != nil {
                    // C3/H1: real report + a Block reachable at the point of abuse
                    // (Apple 1.2 expects block discoverable inside the DM, not only
                    // on the profile).
                    Button(role: .destructive) { reportPeer() } label: {
                        Label(L("reportUser", language), systemImage: "flag")
                    }
                    Button(role: .destructive) { blockPeer() } label: {
                        Label(L("blockUser", language), systemImage: "hand.raised.slash")
                    }
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
            .accessibilityLabel(language == .ja ? "その他" : language == .en ? "More" : "更多")
        }
        .padding(.horizontal, KXSpacing.lg)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, 10)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private func reportPeer() {
        guard let peer else { return }
        if currentUser.isGuest { GuestGate.shared.requireLogin(L("guestReasonMessage", language)); return }
        Task {
            do {
                try await KaiXAPIClient.shared.reportUser(peer.id, reason: "harassment")
                actionMessage = L("reportRecorded", language)
            } catch {
                actionMessage = error.kaixUserMessage
            }
        }
    }

    private func blockPeer() {
        guard let peer else { return }
        if currentUser.isGuest { GuestGate.shared.requireLogin(L("guestReasonMessage", language)); return }
        Task {
            do {
                try await KaiXAPIClient.shared.setBlock(peer.id, true)
                let key = KXBlocklist.storageKey(for: currentUser.id)
                var ids = Set((UserDefaults.standard.string(forKey: key) ?? "").split(separator: "|").map(String.init))
                ids.insert(peer.id)
                UserDefaults.standard.set(ids.sorted().joined(separator: "|"), forKey: key)
                actionMessage = L("userBlocked", language)
                // Leave the conversation after blocking — the composer would only
                // 403 on send now (server enforces the block), so keeping it open
                // is misleading. Pop back to the messages list.
                try? await Task.sleep(nanoseconds: 350_000_000)
                dismiss()
            } catch {
                actionMessage = error.kaixUserMessage
            }
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
                LazyVStack(spacing: KXSpacing.sm) {
                    earlierMessagesHeader(proxy: proxy)
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
                                isReadByPeer: viewModel.readMessageIds.contains(message.id),
                                bubbleMaxWidth: windowWidth * 0.74,
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
                            // New bubbles slide up from the bottom (anchored to
                            // the sender's side) and fade + scale in; removed
                            // ones fade out. Gives sending/receiving a natural
                            // "message arrives" feel instead of a hard pop.
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom)
                                        .combined(with: .opacity)
                                        .combined(with: .scale(
                                            scale: 0.97,
                                            anchor: message.senderId == currentUser.id ? .bottomTrailing : .bottomLeading
                                        )),
                                    removal: .opacity
                                )
                            )
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
                        // 贴底哨兵:锚点进出可视区近似"贴近底部"。部署目标是
                        // iOS 17,不能用 iOS 18 的 onScrollGeometryChange;
                        // 与 SocialRoomDetailView 的哨兵探测同模式。
                        .onAppear {
                            isNearBottom = true
                            pendingNewMessages = 0
                        }
                        .onDisappear { isNearBottom = false }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, 10)
                .padding(.bottom, KXSpacing.md)
                .kxReadableWidth()
                // Drive the bubble insertion/removal transitions off the message
                // count so appends/deletes animate rather than snap. 减去已
                // prepend 的历史条数:「查看更早的消息」翻页时两者同增、差值
                // 不变,80 条历史不会齐刷刷从底部滑入;尾部收发/删除照常动画。
                .animation(KXMotion.tap, value: viewModel.messages.count - viewModel.earlierPrependedCount)
            }
            .scrollDismissesKeyboard(.interactively)
            // 气泡最大宽度跟随滚动容器宽度(Split View / Stage Manager 尺寸变化
            // 也能更新),替代原先每个气泡 body 都遍历 connectedScenes 的开销。
            // onGeometryChange 自 iOS 16 可用,替代 iOS 18 的 onScrollGeometryChange。
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                if width > 0 { windowWidth = width }
            }
            .onAppear {
                scrollToLatest(proxy, animated: false)
            }
            // 单触发器:原先 count 与 last?.id 两个 onChange 都调 scrollToLatest,
            // 一条新消息 = 2×3 次滚动动画;last?.id 已覆盖收发/删尾场景。
            .onChange(of: viewModel.messages.last?.id) { _, _ in
                guard let latest = viewModel.messages.last else { return }
                if viewModel.hasActiveFilters || isNearBottom || latest.senderId == currentUser.id {
                    pendingNewMessages = 0
                    scrollToLatest(proxy, animated: true)
                } else {
                    // 用户正在回看历史:不打断,改为"↓ N 条新消息"悬浮胶囊。
                    pendingNewMessages += 1
                }
            }
            .onChange(of: viewModel.state) { _, newState in
                if newState == .loaded {
                    scrollToLatest(proxy, animated: false)
                }
            }
            .onChange(of: viewModel.mediaDrafts.count) { _, _ in
                scrollToLatest(proxy, animated: true)
            }
            .overlay(alignment: .bottom) {
                if pendingNewMessages > 0 {
                    newMessagesPill {
                        pendingNewMessages = 0
                        scrollToLatest(proxy, animated: true)
                    }
                }
            }
        }
    }

    /// 列表顶部的「查看更早的消息」区:有游标时给按钮,在途转小 spinner,失败
    /// 给轻量重试(不掀翻会话),翻完(游标空且确实翻过页)显示「已到最早」。
    /// 与 SocialRoomDetailView 的 loadEarlier 同模式。
    @ViewBuilder
    private func earlierMessagesHeader(proxy: ScrollViewProxy) -> some View {
        if viewModel.isLoadingEarlier {
            KXSpinner(size: 16, lineWidth: 2, tint: KXColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        } else if viewModel.earlierLoadFailed {
            Button {
                loadEarlier(proxy: proxy)
            } label: {
                Text(KXListingCopy.pickText(
                    language,
                    "更早消息加载失败，点击重试",
                    "以前のメッセージを読み込めませんでした。タップして再試行",
                    "Couldn't load earlier messages — tap to retry"
                ))
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.heat)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if viewModel.earlierCursor != nil {
            Button {
                loadEarlier(proxy: proxy)
            } label: {
                Text(KXListingCopy.pickText(language, "查看更早的消息", "以前のメッセージ", "Earlier messages"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if viewModel.earlierPrependedCount > 0 {
            Text(KXListingCopy.pickText(language, "已到最早的消息", "これ以上前のメッセージはありません", "Beginning of conversation"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }

    private func loadEarlier(proxy: ScrollViewProxy) {
        Task {
            guard let anchorId = await viewModel.loadEarlier(context: modelContext, thread: thread, messageStore: messageStore) else { return }
            // prepend 会把原有内容顶下去:等这帧布局落地后把原首条钉回顶部,
            // 保持阅读位置不跳。尾部自动滚底只认 last?.id(prepend 不改变它)
            // 且 isNearBottom 此刻为 false,不会互相打架。
            try? await Task.sleep(for: .milliseconds(80))
            proxy.scrollTo(anchorId, anchor: .top)
        }
    }

    /// 悬浮"↓ N 条新消息"胶囊:回看历史时新消息不再强制滚底,点按跳到最新。
    private func newMessagesPill(onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .font(.caption.weight(.bold))
                Text(newMessagesPillText)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(KXColor.onAccent)
            .padding(.horizontal, KXSpacing.md)
            .frame(height: 32)
            .background(KXColor.accent, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
            .shadow(color: KXColor.accent.opacity(0.28), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.bottom, KXSpacing.sm)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityLabel(newMessagesPillText)
    }

    private var newMessagesPillText: String {
        let count = pendingNewMessages
        return KXListingCopy.pickText(
            language,
            "\(count) 条新消息",
            "新着メッセージ\(count)件",
            count == 1 ? "1 new message" : "\(count) new messages"
        )
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
        // 单次兜底:等插入动画/键盘布局落定后再钉一次底。原先是 3 连发
        // (立即 + 0.08s + 0.28s)× 双触发器 = 一条消息最多 6 次滚动事务。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            action()
        }
    }

    /// Flattens the message array into a render list with day separators and
    /// the new-message divider interleaved. Computed once per body pass; cheap
    /// (a single linear walk, no per-row work in the bubble itself).
    /// 搜索/日期过滤时跳过分割线——结果集里的"新消息"锚点没有语义。
    private var timelineItems: [ChatTimelineItem] {
        var result: [ChatTimelineItem] = []
        let calendar = Calendar.current
        var lastDay: Date?
        let anchor = viewModel.hasActiveFilters ? nil : newMessageAnchorId
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
                HStack(spacing: KXSpacing.sm) {
                    ForEach(viewModel.mediaDrafts) { draft in
                        draftChip(draft)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, KXSpacing.sm)
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
            .clipShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
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
                        RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                            .fill(.black.opacity(0.46))
                        ChatUploadProgressRing(progress: progress)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
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
                    .accessibilityLabel(L("delete", language))
                    .padding(KXSpacing.xs)
                }
            }
    }

    private var chatSearchTools: some View {
        VStack(spacing: 9) {
            HStack(spacing: KXSpacing.sm) {
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
            .padding(.horizontal, KXSpacing.md)
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
        .padding(.horizontal, KXSpacing.lg)
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
    /// 己方消息对方是否已读(服务端 is_read)。驱动脚注"已发送 → 已读"。
    let isReadByPeer: Bool
    /// Cap long text bubbles at ~74% of the app's window so they read like chat
    /// bubbles and never run edge-to-edge. 由 ChatView 缓存的窗口宽度算好传入
    /// ——曾是每次气泡 body 求值都遍历 UIApplication.connectedScenes 的计算
    /// 属性(滚动热路径上的重复系统调用)。
    let bubbleMaxWidth: CGFloat
    let peer: UserEntity?
    let onDelete: () -> Void
    let onRetry: () -> Void
    let onOpenPeer: () -> Void

    private var retryLabel: String { language == .ja ? "再送信" : language == .en ? "Retry" : "点击重试" }
    private var sendingLabel: String { language == .ja ? "送信中…" : language == .en ? "Sending…" : "发送中…" }
    private var readLabel: String { language == .ja ? "既読" : language == .en ? "Read" : "已读" }

    var body: some View {
        let contentType = message.resolvedType(mediaItems: mediaItems)

        HStack(alignment: .top, spacing: KXSpacing.sm) {
            if isMine { Spacer(minLength: 52) }

            if !isMine {
                Button(action: onOpenPeer) {
                    AvatarView(user: peer, size: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(peer?.displayName ?? L("profile", language))
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                if !mediaItems.isEmpty {
                    MediaGridView(mediaItems: mediaItems)
                        .frame(maxWidth: contentType == .video ? 236 : 216)
                        .clipShape(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                        .overlay {
                            if message.status == .sending {
                                RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                                    .fill(.black.opacity(0.20))
                                KXSpinner(size: 24, lineWidth: 2.6, tint: .white)
                            } else if message.status == .failed {
                                RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
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
                            RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                                .stroke(KXColor.separator.opacity(isMine ? 0.10 : 0.22), lineWidth: 0.6)
                        )
                        .compositingGroup()
                        .shadow(color: KXColor.glassShadow.opacity(isMine ? 0.14 : 0.22), radius: 8, y: 3)
                        .accessibilityLabel(contentType == .video
                            ? KXListingCopy.pickText(language, "视频消息", "動画メッセージ", "Video message")
                            : KXListingCopy.pickText(language, "图片消息", "画像メッセージ", "Image message"))
                }

                if let visibleContent = message.visibleContent {
                    Text(visibleContent)
                        .font(.body)
                        .foregroundStyle(isMine ? KXColor.onAccent : .primary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background {
                            RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                                .fill(isMine
                                      ? AnyShapeStyle(LinearGradient(
                                            colors: [KXColor.accent, KXColor.accent.opacity(0.86)],
                                            startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(KXColor.cardBackground))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
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
                            // 服务端一直返回 is_read,过去被映射层丢弃——已读回执
                            // 数据链路本就存在,只差呈现。
                            Text(isReadByPeer ? readLabel : L("sent", language)).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, KXSpacing.xs)
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
    @State private var sendTapCount = 0
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
        .padding(.bottom, KXSpacing.sm)
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
                    RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous)
                        .fill(KXColor.elevatedBackground.opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous)
                        .stroke(KXColor.separator.opacity(0.24), lineWidth: 0.7)
                )

            emojiButton
            sendButton
        }
        .padding(.horizontal, 9)
        .padding(.vertical, KXSpacing.sm)
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
            sendTapCount &+= 1
            send()
        } label: {
            if isSending {
                KXSpinner(size: 18, lineWidth: 2.2, tint: canSend ? KXColor.onAccent : KXColor.accent)
            } else {
                Image(systemName: "paperplane.fill")
                    .font(.subheadline.weight(.bold))
            }
        }
        .frame(width: 44, height: 44)
        .foregroundStyle(canSend ? KXColor.onAccent : KXColor.accent.opacity(0.38))
        .background {
            Circle()
                .fill(canSend ? KXColor.accent : KXColor.accent.opacity(0.08))
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(canSend ? Color.clear : KXColor.accent.opacity(0.12), lineWidth: 0.8))
        .shadow(color: canSend ? KXColor.accent.opacity(0.18) : .clear, radius: 10, y: 4)
        .disabled(!canSend || isSending)
        // A light tap when a send fires — a subtle "it went" confirmation.
        .sensoryFeedback(.impact(weight: .light), trigger: sendTapCount)
        .accessibilityLabel(L("send", language))
    }

    private func attachTray(remainingImageSlots: Int, imageDisabled: Bool, videoDisabled: Bool) -> some View {
        HStack(spacing: KXSpacing.md) {
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
        .padding(.horizontal, KXSpacing.sm)
        .padding(.top, KXSpacing.xxs)
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
                    RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                        .fill(disabled ? KXColor.softBackground.opacity(0.4) : KXColor.accent.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
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
            .padding(.vertical, KXSpacing.xs)
            .background(KXColor.softBackground.opacity(0.9), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, KXSpacing.xxs)
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
        HStack(spacing: KXSpacing.sm) {
            line
            Text(language == .ja ? "ここから新着メッセージ" : language == .en ? "New messages" : "以下是新消息")
                .font(.caption2.weight(.bold))
                .foregroundStyle(KXColor.accent)
                .fixedSize()
            line
        }
        .padding(.horizontal, KXSpacing.sm)
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
                HStack(alignment: .bottom, spacing: KXSpacing.sm) {
                    if r.mine { Spacer(minLength: 52) }
                    if !r.mine { Circle().fill(KXColor.softBackground).frame(width: 32, height: 32) }
                    RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                        .fill(KXColor.softBackground)
                        .frame(width: UIScreen.main.bounds.width * r.w, height: 40)
                    if !r.mine { Spacer(minLength: 52) }
                }
            }
            Spacer()
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// Calm empty state for a conversation with no messages yet.
private struct ChatEmptyView: View {
    let language: AppLanguage
    var body: some View {
        VStack(spacing: KXSpacing.md) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .kxScaledFont(38, weight: .light)
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
        VStack(spacing: KXSpacing.md) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .kxScaledFont(34, weight: .light)
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
                .kxScaledFont(11, weight: .heavy)
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: 44, height: 44)
        .animation(.easeOut(duration: 0.2), value: clamped)
    }
}

