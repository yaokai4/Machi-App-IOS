import Foundation
import Combine
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var threads: [MessageThreadEntity] = []
    @Published var peers: [String: UserEntity] = [:]
    @Published var state: ScreenState = .idle
    @Published var transientError: String? {
        // 任何新错误默认视为"需要用户处理"(删除/标记失败等);只有 load 的
        // catch 会随后把它标记回 transient,允许下一次成功刷新自动清除。
        didSet { if transientError != oldValue { transientErrorIsLoadFailure = false } }
    }
    /// False while the app is backgrounded so the 8s inbox poll skips network
    /// work (battery + server load). Mirrors ChatViewModel.isForeground.
    var isForeground = true
    /// 在途守卫 + 尾随合流:8s 轮询/回前台/切 Tab/刷新通知/下拉刷新会并发触发
    /// load,重叠请求纯属浪费。在途时记一笔,当前这轮结束后补跑一次。
    private var isLoading = false
    private var needsReload = false
    /// transientError 是否由 load 失败设置——只有这类横幅在恢复后自动消失。
    private var transientErrorIsLoadFailure = false

    func load(context: ModelContext, currentUser: UserEntity, messageStore: MessageStore? = nil) async {
        if isLoading {
            needsReload = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        repeat {
            needsReload = false
            await performLoad(context: context, currentUser: currentUser, messageStore: messageStore)
        } while needsReload
    }

    private func performLoad(context: ModelContext, currentUser: UserEntity, messageStore: MessageStore?) async {
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
            // 一次瞬时网络抖动留下的横幅在恢复后自动消失,不再永久钉着。
            if transientErrorIsLoadFailure { transientError = nil }
        } catch {
            if hasCachedContent {
                transientError = error.kaixUserMessage
                transientErrorIsLoadFailure = true
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
    @Published var errorMessage: String? {
        // 任何新错误默认视为"需要用户处理"(send/媒体失败要陪着 .failed 气泡);
        // 只有 load 的 catch 会随后把它标记回 transient,允许成功刷新自动清除。
        didSet { if errorMessage != oldValue { errorMessageIsLoadFailure = false } }
    }
    /// 己方消息中"对方已读"的消息 id 集合(服务端 is_read),驱动气泡的已读回执。
    @Published var readMessageIds: Set<String> = []
    /// 更早历史页的服务端游标(上一页响应的 next_cursor)。nil = 已到最早或
    /// 分页链尚未建立。只在两处写入:整页加载重建列表时(上下文重置/无历史
    /// 前缀)与 loadEarlier 成功翻页时——3s 轮询的最新页响应在已有历史前缀时
    /// 绝不覆盖它,否则「查看更早」会退回去重复翻已加载的页。
    @Published var earlierCursor: String?
    /// 顶部「查看更早的消息」是否在途,驱动顶部小 spinner + 防重入。
    @Published var isLoadingEarlier = false
    /// 更早页加载失败 → 顶部轻量重试条(绝不掀翻整个会话视图)。
    @Published var earlierLoadFailed = false
    /// 已通过「查看更早的消息」prepend 到头部的历史条数。ChatView 用
    /// (messages.count - earlierPrependedCount) 作气泡插入动画的触发值:历史
    /// prepend 时两者同增、差值不变 → 不触发"80 条历史从底部滑入"的视觉噪音;
    /// 尾部收发/删除仍正常动画。
    @Published var earlierPrependedCount = 0
    /// 分页链所属上下文(会话 id + 搜索 + 日期)。上下文变化(切会话/改过滤器/
    /// 账号切换后重开)时整页加载会整体重建列表并重置游标,历史前缀不跨上下文
    /// 保留——同一个 ChatViewModel 实例被复用到另一会话时,旧会话消息绝不会
    /// 被当作"历史前缀"错保进新列表。
    private var paginationContextKey: String?
    /// errorMessage 是否由 load 失败设置——只有这类横幅在下一次成功刷新时自动
    /// 清除,否则 3s 轮询一次瞬时抖动的"网络错误"会永久钉在输入栏上方。
    private var errorMessageIsLoadFailure = false
    /// 在途守卫 + 尾随合流:3s 轮询/回前台/store lastMessageAt/刷新通知四路
    /// Task 互不协调,重叠 load 既重复打网络,二段媒体解析交错时旧 resolveMedia
    /// 结果还可能后落地闪错媒体。在途时记一笔,结束后用最新 query/day 补跑。
    private var isLoading = false
    private var needsReload = false

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaDrafts.isEmpty
    }

    var hasActiveFilters: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDay != nil
    }

    /// 返回值:本次调用是否真正执行了一次(成功的)服务端加载。被在途守卫合流
    /// 掉的调用返回 false——调用方(如"新消息"锚点解析)据此避免拿缓存半成品
    /// 当服务端真相。
    @discardableResult
    func load(context: ModelContext, thread: MessageThreadEntity, messageStore: MessageStore? = nil) async -> Bool {
        if isLoading {
            needsReload = true
            return false
        }
        isLoading = true
        defer { isLoading = false }
        var succeeded = false
        repeat {
            needsReload = false
            succeeded = await performLoad(context: context, thread: thread, messageStore: messageStore)
        } while needsReload
        return succeeded
    }

    private func performLoad(context: ModelContext, thread: MessageThreadEntity, messageStore: MessageStore?) async -> Bool {
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
            // Two-phase: render the text bubbles (+ public media) immediately,
            // then sign private attachments asynchronously and patch them in.
            // A multi-image thread no longer blanks the whole conversation while
            // N signing round-trips complete.
            let (fetched, pending, fetchedCursor) = try await repository.fetchMessagesTextFirst(
                threadId: thread.id,
                query: searchQuery,
                day: selectedDay.map(Self.serverDayString)
            )
            // Preserve any local `.failed` send the server has no record of, so
            // this wholesale refresh — the 3s poll, scene-phase / notification
            // pulls — never silently drops a failed bubble and its tap-to-retry
            // affordance (which would re-manifest the original silent-send bug).
            // applyServerWindow then keeps any paged-in earlier history in front
            // (the newest-page window must not wipe it) and manages the cursor.
            let merged = Self.mergePreservingFailed(fetched, into: messages)
            applyServerWindow(merged: merged, fetched: fetched, nextCursor: fetchedCursor, threadId: thread.id)
            messageStore?.setMessages(messages, conversationId: thread.id)
            let ids = Set(messages.map(\.id))
            mediaByMessageId = try await repository.fetchMedia(threadId: thread.id, messageIds: ids)
            // 服务端每条消息都带 is_read(过去被丢弃)——发布已读集合供气泡
            // 渲染己方消息的已读回执。
            readMessageIds = repository.readMessageIds(threadId: thread.id)
            state = messages.isEmpty ? .empty : .loaded
            // 轮询恢复正常后自动清掉 load 自己挂上的瞬时错误横幅
            // (send 失败的横幅不动,要陪着 .failed 气泡直到用户处理)。
            if errorMessageIsLoadFailure { errorMessage = nil }

            // Second pass: sign the pending attachments and patch the media in
            // without disturbing the already-rendered text.
            if !pending.isEmpty {
                let resolved = await repository.resolveMedia(threadId: thread.id, pending: pending)
                // Guard against a racing refresh having moved on: only apply if
                // the thread's message set still matches what we published.
                let visibleIds = Set(messages.map(\.id))
                mediaByMessageId = resolved.filter { visibleIds.contains($0.key) }
            }
            return true
        } catch {
            if hasCachedContent {
                errorMessage = error.kaixUserMessage
                errorMessageIsLoadFailure = true
                state = .loaded
            } else {
                state = .error(error.kaixUserMessage)
            }
            return false
        }
    }

    func clearFilters() {
        searchQuery = ""
        selectedDay = nil
    }

    /// 把「最新一页」的服务端窗口落到 messages 上。
    /// - 上下文变化(切会话/改搜索/改日期):整体替换 + 重置游标与历史计数。
    /// - 上下文未变:保留已翻出的更早历史前缀——prepend 的历史页既不参与
    ///   failed 合并窗口,也不能被 3s 轮询 / 发送后刷新的整页窗口抹掉。同时把
    ///   被新消息挤出 80 条窗口的旧尾部消息顺势并入前缀,消息不会凭空消失。
    /// - 游标只在没有历史前缀时才跟随最新页响应:有前缀时,最新页的
    ///   next_cursor 指向比已加载历史更新的位置,采纳它会让「查看更早」重复
    ///   翻已有页;保留旧游标恰好紧接当前最早一条,语义正确。
    private func applyServerWindow(
        merged: [MessageEntity],
        fetched: [MessageEntity],
        nextCursor fetchedCursor: String?,
        threadId: String
    ) {
        let contextKey = Self.paginationContext(
            threadId: threadId,
            query: searchQuery,
            day: selectedDay.map(Self.serverDayString)
        )
        if contextKey != paginationContextKey {
            paginationContextKey = contextKey
            messages = merged
            earlierCursor = fetchedCursor
            earlierPrependedCount = 0
            earlierLoadFailed = false
            return
        }
        // 服务端返回空窗口 = 会话在服务端已被清空,本地前缀不该幸存。
        guard let windowStart = fetched.first?.createdAt else {
            messages = merged
            earlierCursor = fetchedCursor
            earlierPrependedCount = 0
            return
        }
        // merged 已含 fetched + 幸存的 .failed 气泡;前缀只保留严格早于本页
        // 窗口、且不在 merged 里的服务端消息(.failed 由 mergePreservingFailed
        // 全权处理,这里排除以免内容级去重刚丢弃的失败气泡被复活)。
        let mergedIds = Set(merged.map(\.id))
        let preserved = messages.filter {
            !mergedIds.contains($0.id) && $0.status != .failed && $0.createdAt < windowStart
        }
        messages = preserved + merged
        if preserved.isEmpty { earlierCursor = fetchedCursor }
    }

    private static func paginationContext(threadId: String, query: String, day: String?) -> String {
        "\(threadId)|\(query.trimmingCharacters(in: .whitespacesAndNewlines))|\(day ?? "")"
    }

    /// 加载更早的历史页(顶部「查看更早的消息」)。历史页做纯 prepend(按 id
    /// 去重),绝不经过 mergePreservingFailed——失败气泡逻辑与分页互不干扰;
    /// 轮询/发送路径也继续只操作尾部窗口。返回 prepend 前的原首条消息 id,
    /// 视图用它把阅读位置钉回原处(scrollTo anchor: .top);返回 nil = 无需锚定
    /// (在途/游标已失效/去重后为空/加载失败)。
    func loadEarlier(context: ModelContext, thread: MessageThreadEntity, messageStore: MessageStore? = nil) async -> String? {
        guard let cursor = earlierCursor, !isLoadingEarlier else { return nil }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }
        do {
            let repository = MessageRepository(context: context)
            let page = try await repository.fetchEarlierMessages(
                threadId: thread.id,
                query: searchQuery,
                day: selectedDay.map(Self.serverDayString),
                cursor: cursor
            )
            // 网络往返期间上下文可能已重建(切会话/改过滤器):游标不再是当前
            // 链上的这一枚就丢弃结果,防止旧上下文的历史 prepend 进新列表。
            guard earlierCursor == cursor else { return nil }
            earlierLoadFailed = false
            let existingIds = Set(messages.map(\.id))
            let fresh = page.messages.filter { !existingIds.contains($0.id) }
            let anchorId = messages.first?.id
            earlierCursor = page.nextCursor
            guard !fresh.isEmpty else { return nil }
            messages = fresh + messages
            earlierPrependedCount += fresh.count
            if let media = try? await repository.fetchMedia(threadId: thread.id, messageIds: Set(messages.map(\.id))) {
                mediaByMessageId = media
            }
            readMessageIds = repository.readMessageIds(threadId: thread.id)
            messageStore?.setMessages(messages, conversationId: thread.id)
            return anchorId
        } catch is CancellationError {
            return nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return nil }
            // 顶部轻量重试,不动 state、不掀翻已加载的会话内容。
            earlierLoadFailed = true
            return nil
        }
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
        // The user pulled this draft out of the composer — its staged files are
        // now dead scratch. Delete them off the main actor.
        Task.detached(priority: .utility) { await UploadService.shared.cleanupDraftFiles(draft) }
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

        // Stable idempotency key: for a text-only send it's the optimistic
        // bubble id (so a user-triggered retry re-uses it); for a media send
        // (no optimistic bubble) derive one from the draft ids so a double-tap
        // can't create two rows.
        let sendKey = optimisticId ?? "media-\(drafts.map(\.id).sorted().joined(separator: "-"))"
        do {
            let repository = MessageRepository(context: context)
            let message = try await repository.sendMessage(
                thread: thread,
                senderId: currentUser.id,
                content: trimmed,
                mediaDrafts: drafts,
                idempotencyKey: "message-send-\(sendKey)",
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
            // 发送成功:清掉遗留的错误横幅(旧失败气泡自身的重试入口仍在)。
            errorMessage = nil
            messageStore?.setMessages(messages, conversationId: thread.id)
            messageStore?.removeFromQueue(message.id)
            drafts.forEach { messageStore?.removeUpload($0.id) }
            // Send landed — the staged upload copies for these drafts are done.
            let sentDrafts = drafts
            Task.detached(priority: .utility) {
                for draft in sentDrafts { await UploadService.shared.cleanupDraftFiles(draft) }
            }

            if KaiXBackend.token != nil {
                await refreshFromServer(repository: repository, thread: thread, currentUser: currentUser, messageStore: messageStore)
            }
        } catch {
            // Keep the bubble visible but mark it failed so the user can retry,
            // instead of silently dropping the text they typed.
            if let optimisticId {
                if let idx = messages.firstIndex(where: { $0.id == optimisticId }) {
                    messages[idx].status = .failed
                    messages = messages   // republish: MessageEntity is a reference type
                } else {
                    // A concurrent wholesale refresh dropped the optimistic
                    // bubble while the send was in flight (only `.failed`
                    // survives mergePreservingFailed, not `.sending`). Re-append
                    // it as `.failed` from the captured text — a failed send
                    // must never vanish silently along with the cleared input.
                    // Reuse `optimisticId` as the bubble id (NOT a fresh UUID) so
                    // a later retry derives the SAME idempotency key
                    // ("message-send-\(optimisticId)") the in-flight send used —
                    // otherwise, if that original POST actually landed but its
                    // response was lost, the retry's different key would insert a
                    // duplicate server row instead of reconciling the same one.
                    let failed = MessageEntity(
                        id: optimisticId,
                        threadId: thread.id,
                        senderId: currentUser.id,
                        content: trimmed,
                        status: .failed
                    )
                    messages.append(failed)
                    mediaByMessageId[failed.id] = []
                }
                messageStore?.setMessages(messages, conversationId: thread.id)
            }
            errorMessage = error.kaixUserMessage
            state = messages.isEmpty ? .empty : .loaded
        }
    }

    func deleteMessage(context: ModelContext, thread: MessageThreadEntity, message: MessageEntity, messageStore: MessageStore? = nil) async {
        // A `.failed` bubble is a purely local, client-id-only optimistic send —
        // the server has no record of it. Delete it locally with no round-trip
        // (which would 404 / clobber unrelated state) so tap-to-dismiss on a
        // failed send is instant and always succeeds.
        if message.status == .failed {
            messages.removeAll { $0.id == message.id }
            mediaByMessageId[message.id] = nil
            messageStore?.setMessages(messages, conversationId: thread.id)
            state = messages.isEmpty ? .empty : .loaded
            return
        }

        let previousMessages = messages
        let previousMedia = mediaByMessageId
        messages.removeAll { $0.id == message.id }
        mediaByMessageId[message.id] = nil
        messageStore?.setMessages(messages, conversationId: thread.id)
        state = messages.isEmpty ? .empty : .loaded
        do {
            let repository = MessageRepository(context: context)
            try await repository.deleteMessage(message, in: thread)
            // Server delete returns early without recomputing the thread preview
            // (production messages live only here in the VM), so refresh it from
            // the remaining loaded messages and push it into the store — else the
            // conversation list keeps showing the just-deleted last message until
            // the next fetchThreads poll.
            repository.refreshThreadPreview(thread, remaining: messages, mediaByMessageId: mediaByMessageId)
            messageStore?.upsertConversation(thread)
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
                // Reuse the failed bubble's id as the idempotency key so this
                // retry reconciles the same server row rather than inserting a
                // duplicate (the original send used this same derived key).
                let sent = try await repository.sendMessage(
                    thread: thread,
                    senderId: message.senderId,
                    content: text,
                    mediaDrafts: [],
                    idempotencyKey: "message-send-\(failedId)"
                )
                if let idx = messages.firstIndex(where: { $0.id == failedId }) {
                    messages[idx] = sent
                    mediaByMessageId[failedId] = nil
                } else {
                    messages.append(sent)
                }
                mediaByMessageId[sent.id] = []
                state = .loaded
                // 重试成功:自动收起之前发送失败留下的错误横幅。
                errorMessage = nil
                messageStore?.setMessages(messages, conversationId: thread.id)
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == failedId }) {
                    messages[idx].status = .failed
                    messages = messages
                } else {
                    // The bubble was `.sending` during the retry, so a
                    // concurrent refresh could have swept it (only `.failed`
                    // survives mergePreservingFailed). Re-append it as `.failed`
                    // so the tap-to-retry affordance never silently disappears.
                    // Reuse `failedId` as the id (NOT a fresh UUID) so a further
                    // retry derives the SAME idempotency key
                    // ("message-send-\(failedId)") this retry used — a fresh id
                    // would give the next retry a different key and insert a
                    // duplicate server row if this attempt's POST actually landed.
                    let failed = MessageEntity(
                        id: failedId,
                        threadId: thread.id,
                        senderId: message.senderId,
                        content: text,
                        status: .failed
                    )
                    messages.append(failed)
                    mediaByMessageId[failed.id] = []
                }
                messageStore?.setMessages(messages, conversationId: thread.id)
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
            errorMessage = nil
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

    /// Merge freshly-fetched server messages with any local `.failed` sends
    /// the server has no record of, keeping them visible (and retryable) after
    /// a wholesale refresh. A failed send has a client-generated id that never
    /// appears in the server payload, so without this a background refresh would
    /// delete the bubble before the user could tap retry. Only `.failed` is
    /// preserved: an in-flight `.sending` bubble is transient — the 3s poll is
    /// `isSending`-guarded, and if a scene-phase / notification pull drops it,
    /// `send`/`retryMessage` reconcile the server row by id with an append
    /// fallback, so nothing is lost. Preserving `.sending` here would instead
    /// risk a client-id/server-id duplicate.
    private static func mergePreservingFailed(
        _ fetched: [MessageEntity],
        into current: [MessageEntity]
    ) -> [MessageEntity] {
        let failedLocal = current.filter { $0.status == .failed }
        guard !failedLocal.isEmpty else { return fetched }
        let fetchedIds = Set(fetched.map(\.id))
        var survivors = failedLocal.filter { !fetchedIds.contains($0.id) }
        guard !survivors.isEmpty else { return fetched }
        // Content-level dedup: if the server actually delivered a message that
        // matches a still-`.failed` local bubble, the send *did* land — drop the
        // stale failed twin so the user doesn't see "delivered" and "发送失败"
        // side by side. The optimistic bubble carries a client id the server
        // never had, so id-matching alone can't catch this.
        //
        // We detect the landing by a NEWLY fetched server row (an id we didn't
        // already have on screen) from the same sender with identical text.
        // This is clock-source-independent — the old `abs(server.createdAt -
        // failed.createdAt) < 120` compared a client-clock optimistic bubble
        // against a server-clock row, so a device clock skewed >120s from the
        // server broke the match and the failed twin lingered next to the
        // delivered copy. A wide client-clock recency guard keeps an ancient
        // failed bubble from being dropped against an unrelated later send of
        // the same text.
        let existingIds = Set(current.map(\.id))
        let now = Date()
        survivors = survivors.filter { failed in
            let text = failed.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return true }
            guard now.timeIntervalSince(failed.createdAt) < 3600 else { return true }
            let hasFreshServerTwin = fetched.contains { server in
                server.senderId == failed.senderId
                    && !existingIds.contains(server.id)
                    && server.content.trimmingCharacters(in: .whitespacesAndNewlines) == text
            }
            return !hasFreshServerTwin
        }
        guard !survivors.isEmpty else { return fetched }
        return (fetched + survivors).sorted { $0.createdAt < $1.createdAt }
    }

    private func refreshFromServer(
        repository: MessageRepository,
        thread: MessageThreadEntity,
        currentUser: UserEntity,
        messageStore: MessageStore?
    ) async {
        guard !hasActiveFilters else { return }
        do {
            let page = try await repository.fetchMessagesPage(threadId: thread.id)
            // Same failed-send preservation as `load`: a later successful send
            // must not wipe an earlier, still-failed bubble off the screen.
            // applyServerWindow additionally keeps paged-in earlier history in
            // front — a send at the bottom must not evict the scrolled-back
            // pages (nor clobber the pagination cursor).
            let mergedMessages = Self.mergePreservingFailed(page.messages, into: messages)
            applyServerWindow(merged: mergedMessages, fetched: page.messages, nextCursor: page.nextCursor, threadId: thread.id)
            let latestMedia = try await repository.fetchMedia(
                threadId: thread.id,
                messageIds: Set(messages.map(\.id))
            )
            mediaByMessageId = latestMedia
            readMessageIds = repository.readMessageIds(threadId: thread.id)
            state = messages.isEmpty ? .empty : .loaded
            messageStore?.setMessages(messages, conversationId: thread.id)
            if let latestThread = try await repository.fetchThreads(currentUserId: currentUser.id).first(where: { $0.id == thread.id }) {
                messageStore?.upsertConversation(latestThread)
            }
        } catch {
            // Sending already succeeded; keep the optimistic message visible.
        }
    }
}
