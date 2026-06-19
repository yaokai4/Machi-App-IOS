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
        .task {
            await viewModel.load(context: modelContext, thread: thread, messageStore: messageStore)
            try? await MessageRepository(context: modelContext).markThreadRead(thread)
            messageStore.setUnreadCount(0, conversationId: thread.id)
        }
        .onChange(of: pickerItems) { _, newValue in
            Task {
                for item in newValue {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    let videoContentType = item.supportedContentTypes.first { $0.conforms(to: .movie) }
                    await viewModel.addMedia(data: data, isVideo: videoContentType != nil, contentType: videoContentType, language: language, messageStore: messageStore)
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
        .alert(L("ok", language), isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button(L("ok", language), role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
        .alert(L("error", language), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button(L("ok", language), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
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
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.vertical, 10)
                .padding(.bottom, KXSpacing.lg)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastId = viewModel.messages.last?.id {
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
            }
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

    var body: some View {
        let contentType = message.resolvedType(mediaItems: mediaItems)

        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 52) }

            if !isMine {
                AvatarView(user: peer, size: 32)
            }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                if !mediaItems.isEmpty {
                    MediaGridView(mediaItems: mediaItems)
                        .frame(maxWidth: 216)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay {
                            if message.status == .sending {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .fill(.black.opacity(0.20))
                                KXSpinner(size: 24, lineWidth: 2.6, tint: .white)
                            } else if message.status == .failed {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
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
        HStack(spacing: 8) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: remainingImageSlots, matching: .images) {
                Image(systemName: "photo")
                    .font(.headline.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .disabled(hasVideo || imageCount >= KaiXConfig.maxImageItemsPerPost)

            PhotosPicker(selection: $pickerItems, maxSelectionCount: KaiXConfig.maxVideoItemsPerPost, matching: .videos) {
                Image(systemName: "video")
                    .font(.headline.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .disabled(!mediaDrafts.isEmpty)

            TextField(L("messagePlaceholder", language), text: $text, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())

            Button(action: send) {
                if isSending {
                    KXSpinner(size: 18, lineWidth: 2.2, tint: .white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(width: 36, height: 36)
            .foregroundStyle(canSend ? .white : .secondary)
            .background {
                Circle()
                    .fill(canSend ? KXColor.accent : Color(.tertiarySystemGroupedBackground))
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(KXColor.separator, lineWidth: canSend ? 0 : 0.6))
            .disabled(!canSend || isSending)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .kxGlassBar()
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }
}
