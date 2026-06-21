import Foundation
import Combine
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var threads: [MessageThreadEntity] = []
    @Published var peers: [String: UserEntity] = [:]
    @Published var state: ScreenState = .idle
    @Published var transientError: String?
    /// False while the app is backgrounded so the 8s inbox poll skips network
    /// work (battery + server load). Mirrors ChatViewModel.isForeground.
    var isForeground = true

    func load(context: ModelContext, currentUser: UserEntity, messageStore: MessageStore? = nil) async {
        let hasCachedContent = !threads.isEmpty
        if !hasCachedContent {
            state = .loading
        }
        do {
            let repository = MessageRepository(context: context)
            threads = try await repository.fetchThreads(currentUserId: currentUser.id)
            messageStore?.setConversations(threads)
            if KaiXBackend.token != nil {
                peers = repository.cachedPeers()
            } else {
                let users = try await UserRepository(context: context).fetchUsers()
                peers = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            }
            state = threads.isEmpty ? .empty : .loaded
        } catch {
            if hasCachedContent {
                transientError = error.kaixUserMessage
                state = .loaded
            } else {
                state = .error(error.kaixUserMessage)
            }
        }
    }

    func deleteThread(context: ModelContext, thread: MessageThreadEntity, messageStore: MessageStore? = nil) async {
        let previousThreads = threads
        let previousMessages = messageStore?.messagesByConversationId[thread.id]
        threads.removeAll { $0.id == thread.id }
        messageStore?.removeConversation(thread.id)
        state = threads.isEmpty ? .empty : .loaded
        do {
            try await MessageRepository(context: context).deleteThread(thread)
        } catch {
            threads = previousThreads
            messageStore?.setConversations(previousThreads)
            if let previousMessages {
                messageStore?.setMessages(previousMessages, conversationId: thread.id)
            }
            state = threads.isEmpty ? .empty : .loaded
            transientError = error.kaixUserMessage
        }
    }

    func toggleRead(context: ModelContext, thread: MessageThreadEntity, messageStore: MessageStore? = nil) async {
        let oldValue = thread.unreadCount
        let shouldMarkRead = thread.unreadCount > 0
        thread.unreadCount = shouldMarkRead ? 0 : 1
        messageStore?.setUnreadCount(thread.unreadCount, conversationId: thread.id)
        do {
            if shouldMarkRead {
                try await MessageRepository(context: context).markThreadRead(thread)
            } else {
                try await MessageRepository(context: context).markThreadUnread(thread)
            }
        } catch {
            thread.unreadCount = oldValue
            messageStore?.setUnreadCount(oldValue, conversationId: thread.id)
            transientError = error.kaixUserMessage
        }
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [MessageEntity] = []
    @Published var mediaByMessageId: [String: [MediaEntity]] = [:]
    @Published var mediaDrafts: [MediaDraft] = []
    @Published var inputText = ""
    @Published var searchQuery = ""
    @Published var selectedDay: Date?
    @Published var isShowingSearchTools = false
    @Published var state: ScreenState = .idle
    @Published var isSending = false
    /// Set false when the app leaves the foreground so the chat's 3s poll loop
    /// skips network work while backgrounded (battery + server load).
    var isForeground = true
    /// Overall 0…1 progress while a message's media is uploading to S3, or
    /// nil when there is no in-flight media upload. Drives the ring on the
    /// draft thumbnails.
    @Published var sendUploadProgress: Double?
    @Published var errorMessage: String?

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaDrafts.isEmpty
    }

    var hasActiveFilters: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDay != nil
    }

    func load(context: ModelContext, thread: MessageThreadEntity, messageStore: MessageStore? = nil) async {
        // Cache-first: seed from the in-memory conversation cache so the chat
        // shows its last messages instantly instead of a blank "加载中" spinner
        // while the network round-trips. The fetch below then reconciles.
        if messages.isEmpty, !hasActiveFilters,
           let cached = messageStore?.messagesByConversationId[thread.id], !cached.isEmpty {
            messages = cached
            state = .loaded
        }
        let hasCachedContent = !messages.isEmpty
        if !hasCachedContent {
            state = .loading
        }
        do {
            let repository = MessageRepository(context: context)
            messages = try await repository.fetchMessages(
                threadId: thread.id,
                query: searchQuery,
                day: selectedDay.map(Self.serverDayString)
            )
            messageStore?.setMessages(messages, conversationId: thread.id)
            let ids = Set(messages.map(\.id))
            mediaByMessageId = try await repository.fetchMedia(threadId: thread.id, messageIds: ids)
            state = messages.isEmpty ? .empty : .loaded
        } catch {
            if hasCachedContent {
                errorMessage = error.kaixUserMessage
                state = .loaded
            } else {
                state = .error(error.kaixUserMessage)
            }
        }
    }

    func clearFilters() {
        searchQuery = ""
        selectedDay = nil
    }

    func addMedia(data: Data, isVideo: Bool, contentType: UTType? = nil, language: AppLanguage, messageStore: MessageStore? = nil) async {
        errorMessage = nil
        let hasVideo = mediaDrafts.contains { $0.type == .video }
        let imageCount = mediaDrafts.filter { $0.type == .image }.count
        if isVideo {
            guard mediaDrafts.isEmpty else {
                errorMessage = L(hasVideo ? "mediaVideoLimit" : "mediaMixNotAllowed", language)
                state = messages.isEmpty ? .empty : .loaded
                return
            }
        } else {
            guard !hasVideo else {
                errorMessage = L("mediaMixNotAllowed", language)
                state = messages.isEmpty ? .empty : .loaded
                return
            }
            guard imageCount < KaiXConfig.maxImageItemsPerPost else {
                errorMessage = L("mediaImageLimit", language)
                state = messages.isEmpty ? .empty : .loaded
                return
            }
        }
        do {
            let draft = isVideo
                ? try await UploadService.shared.prepareVideo(data: data, contentType: contentType)
                : try await UploadService.shared.prepareImage(data: data)
            let uploadLimit = isVideo ? KaiXConfig.maxMessageVideoBytes : KaiXConfig.maxMessageImageBytes
            guard draft.uploadFileSize <= uploadLimit else {
                errorMessage = L("mediaTooLarge", language)
                state = messages.isEmpty ? .empty : .loaded
                return
            }
            if isVideo, draft.duration > KaiXConfig.maxMessageVideoDuration {
                errorMessage = L("messageVideoDurationLimit", language)
                state = messages.isEmpty ? .empty : .loaded
                return
            }
            mediaDrafts.append(draft)
            messageStore?.enqueueUpload(draft)
            if case .idle = state {
                state = messages.isEmpty ? .empty : .loaded
            }
        } catch {
            errorMessage = L("mediaFailed", language)
            state = messages.isEmpty ? .empty : .loaded
        }
    }

    func addVideo(fileURL: URL, contentType: UTType? = nil, language: AppLanguage, messageStore: MessageStore? = nil) async {
        errorMessage = nil
        guard mediaDrafts.isEmpty else {
            errorMessage = L(mediaDrafts.contains { $0.type == .video } ? "mediaVideoLimit" : "mediaMixNotAllowed", language)
            state = messages.isEmpty ? .empty : .loaded
            return
        }
        do {
            let draft = try await UploadService.shared.prepareVideo(fileURL: fileURL, contentType: contentType)
            guard draft.uploadFileSize <= KaiXConfig.maxMessageVideoBytes else {
                errorMessage = L("mediaTooLarge", language)
                state = messages.isEmpty ? .empty : .loaded
                return
            }
            if draft.duration > KaiXConfig.maxMessageVideoDuration {
                errorMessage = L("messageVideoDurationLimit", language)
                state = messages.isEmpty ? .empty : .loaded
                return
            }
            mediaDrafts.append(draft)
            messageStore?.enqueueUpload(draft)
            if case .idle = state {
                state = messages.isEmpty ? .empty : .loaded
            }
        } catch UploadService.UploadError.mediaTooLarge {
            errorMessage = L("mediaTooLarge", language)
            state = messages.isEmpty ? .empty : .loaded
        } catch {
            errorMessage = L("mediaFailed", language)
            state = messages.isEmpty ? .empty : .loaded
        }
    }

    func removeMedia(_ draft: MediaDraft, messageStore: MessageStore? = nil) {
        mediaDrafts.removeAll { $0.id == draft.id }
        messageStore?.removeUpload(draft.id)
    }

    func send(context: ModelContext, thread: MessageThreadEntity, currentUser: UserEntity, messageStore: MessageStore? = nil) async {
        // `!isSending` blocks a double-tap / double-submit from spawning two
        // server inserts (the button + onSubmit can both fire under fat-finger).
        guard canSend, !isSending else { return }
        let drafts = mediaDrafts
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        sendUploadProgress = drafts.isEmpty ? nil : 0
        defer {
            isSending = false
            sendUploadProgress = nil
        }

        // Optimistic pending bubble for text-only sends: the message shows
        // instantly as `.sending`, then reconciles to the server row (`.sent`)
        // or flips to `.failed` (tap-to-retry). Media sends keep their draft
        // preview + upload-progress ring as their live feedback instead.
        var optimisticId: String?
        if drafts.isEmpty {
            let pending = MessageEntity(
                threadId: thread.id,
                senderId: currentUser.id,
                content: trimmed,
                status: .sending
            )
            optimisticId = pending.id
            messages.append(pending)
            mediaByMessageId[pending.id] = []
            inputText = ""
            state = .loaded
            messageStore?.setMessages(messages, conversationId: thread.id)
        }

        do {
            let repository = MessageRepository(context: context)
            let message = try await repository.sendMessage(
                thread: thread,
                senderId: currentUser.id,
                content: trimmed,
                mediaDrafts: drafts,
                onProgress: { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.isSending else { return }
                        self.sendUploadProgress = Swift.min(Swift.max(fraction, 0.01), 0.99)
                    }
                }
            )
            messageStore?.enqueueSending(message)
            if drafts.isEmpty == false {
                inputText = ""
                mediaDrafts = []
            }
            let messageId = message.id
            let sentMediaById = (try? await MessageRepository(context: context).fetchMedia(threadId: thread.id, messageIds: [messageId])) ?? [:]
            let media = sentMediaById[messageId] ?? []
            if let optimisticId, let idx = messages.firstIndex(where: { $0.id == optimisticId }) {
                messages[idx] = message
                mediaByMessageId[optimisticId] = nil
            } else {
                messages.append(message)
            }
            mediaByMessageId[message.id] = media
            state = .loaded
            messageStore?.setMessages(messages, conversationId: thread.id)
            messageStore?.removeFromQueue(message.id)
            drafts.forEach { messageStore?.removeUpload($0.id) }

            if KaiXBackend.token != nil {
                await refreshFromServer(repository: repository, thread: thread, currentUser: currentUser, messageStore: messageStore)
            }
        } catch {
            // Keep the bubble visible but mark it failed so the user can retry,
            // instead of silently dropping the text they typed.
            if let optimisticId, let idx = messages.firstIndex(where: { $0.id == optimisticId }) {
                messages[idx].status = .failed
                messages = messages   // republish: MessageEntity is a reference type
                messageStore?.setMessages(messages, conversationId: thread.id)
            }
            errorMessage = error.kaixUserMessage
            state = messages.isEmpty ? .empty : .loaded
        }
    }

    func deleteMessage(context: ModelContext, thread: MessageThreadEntity, message: MessageEntity, messageStore: MessageStore? = nil) async {
        let previousMessages = messages
        let previousMedia = mediaByMessageId
        messages.removeAll { $0.id == message.id }
        mediaByMessageId[message.id] = nil
        messageStore?.setMessages(messages, conversationId: thread.id)
        state = messages.isEmpty ? .empty : .loaded
        do {
            try await MessageRepository(context: context).deleteMessage(message, in: thread)
        } catch {
            messages = previousMessages
            mediaByMessageId = previousMedia
            messageStore?.setMessages(previousMessages, conversationId: thread.id)
            state = messages.isEmpty ? .empty : .loaded
            errorMessage = error.kaixUserMessage
        }
    }

    func retryMessage(context: ModelContext, thread: MessageThreadEntity, message: MessageEntity, messageStore: MessageStore? = nil) async {
        guard message.status == .failed else { return }

        // Server-backed retry: re-send the failed text bubble through the API
        // and reconcile it in place. (Media failures keep their draft in the
        // composer, so "retry" there is just pressing send again.)
        if KaiXBackend.token != nil {
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isSending else { return }
            let failedId = message.id
            isSending = true
            defer { isSending = false }
            if let idx = messages.firstIndex(where: { $0.id == failedId }) {
                messages[idx].status = .sending
                messages = messages
            }
            do {
                let repository = MessageRepository(context: context)
                let sent = try await repository.sendMessage(thread: thread, senderId: message.senderId, content: text, mediaDrafts: [])
                if let idx = messages.firstIndex(where: { $0.id == failedId }) {
                    messages[idx] = sent
                    mediaByMessageId[failedId] = nil
                } else {
                    messages.append(sent)
                }
                mediaByMessageId[sent.id] = []
                state = .loaded
                messageStore?.setMessages(messages, conversationId: thread.id)
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == failedId }) {
                    messages[idx].status = .failed
                    messages = messages
                }
                errorMessage = error.kaixUserMessage
            }
            return
        }

        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            errorMessage = RepositoryError.authenticationRequired.kaixUserMessage
            return
        }
        let previousStatus = message.status
        message.status = .sending
        isSending = true
        defer { isSending = false }
        do {
            try context.save()
            message.status = .sent
            thread.lastMessageAt = message.createdAt
            thread.updatedAt = .now
            try context.save()
            if messages.contains(where: { $0.id == message.id }) == false {
                messages.append(message)
                messages.sort { $0.createdAt < $1.createdAt }
            }
            state = messages.isEmpty ? .empty : .loaded
            messageStore?.setMessages(messages, conversationId: thread.id)
        } catch {
            message.status = previousStatus
            errorMessage = error.kaixUserMessage
        }
    }

    private static func serverDayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func refreshFromServer(
        repository: MessageRepository,
        thread: MessageThreadEntity,
        currentUser: UserEntity,
        messageStore: MessageStore?
    ) async {
        guard !hasActiveFilters else { return }
        do {
            let latestMessages = try await repository.fetchMessages(threadId: thread.id)
            let latestMedia = try await repository.fetchMedia(
                threadId: thread.id,
                messageIds: Set(latestMessages.map(\.id))
            )
            messages = latestMessages
            mediaByMessageId = latestMedia
            state = latestMessages.isEmpty ? .empty : .loaded
            messageStore?.setMessages(latestMessages, conversationId: thread.id)
            if let latestThread = try await repository.fetchThreads(currentUserId: currentUser.id).first(where: { $0.id == thread.id }) {
                messageStore?.upsertConversation(latestThread)
            }
        } catch {
            // Sending already succeeded; keep the optimistic message visible.
        }
    }
}
