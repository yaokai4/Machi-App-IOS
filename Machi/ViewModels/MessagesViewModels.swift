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
    @Published var errorMessage: String?

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaDrafts.isEmpty
    }

    var hasActiveFilters: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDay != nil
    }

    func load(context: ModelContext, thread: MessageThreadEntity, messageStore: MessageStore? = nil) async {
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

    func removeMedia(_ draft: MediaDraft, messageStore: MessageStore? = nil) {
        mediaDrafts.removeAll { $0.id == draft.id }
        messageStore?.removeUpload(draft.id)
    }

    func send(context: ModelContext, thread: MessageThreadEntity, currentUser: UserEntity, messageStore: MessageStore? = nil) async {
        guard canSend else { return }
        let drafts = mediaDrafts
        isSending = true
        defer { isSending = false }
        do {
            let repository = MessageRepository(context: context)
            let message = try await repository.sendMessage(
                thread: thread,
                senderId: currentUser.id,
                content: inputText,
                mediaDrafts: drafts
            )
            messageStore?.enqueueSending(message)
            inputText = ""
            mediaDrafts = []
            let messageId = message.id
            let sentMediaById = (try? await MessageRepository(context: context).fetchMedia(threadId: thread.id, messageIds: [messageId])) ?? [:]
            let media = sentMediaById[messageId] ?? []
            messages.append(message)
            mediaByMessageId[message.id] = media
            state = .loaded
            messageStore?.setMessages(messages, conversationId: thread.id)
            messageStore?.removeFromQueue(message.id)
            drafts.forEach { messageStore?.removeUpload($0.id) }

            if KaiXBackend.token != nil {
                await refreshFromServer(repository: repository, thread: thread, currentUser: currentUser, messageStore: messageStore)
            }
        } catch {
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
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            errorMessage = RepositoryError.authenticationRequired.kaixUserMessage
            return
        }
        guard message.status == .failed else { return }
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
