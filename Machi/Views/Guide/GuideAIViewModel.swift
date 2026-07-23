import Combine
import Foundation

/// Role of a single Machi AI chat bubble.
enum GuideAIRole: String, Equatable {
    case user
    case assistant
}

/// Local UI model for one chat bubble. Distinct from the wire DTO so we can
/// represent transient client-only states (a pending "typing" assistant bubble,
/// a failed user turn, a streaming partial answer) without round-tripping the
/// server.
struct GuideAIChatMessage: Identifiable, Equatable {
    let id: String
    let role: GuideAIRole
    var content: String
    var createdAt: Date
    var isPending: Bool
    var failed: Bool
    var sources: [KaiXGuideAISourceDTO]
    /// 用户点了「停止生成」或流中断:保留已收到的部分并标注「已停止」。
    /// 该消息 id 仍是本地 UUID(没有服务端 id),不能对它提交评价。
    var stopped: Bool = false
    /// 「重新回答」后旧答案折叠保留(视图可点开查看)。
    var collapsed: Bool = false
}

/// Drives `GuideAIChatView`. All limit/membership state is server-authoritative
/// (mirrored here for UI only); the client never decides quota. Everything the
/// user sees is "Machi AI" — no provider/model is ever referenced.
@MainActor
final class GuideAIViewModel: ObservableObject {
    @Published var messages: [GuideAIChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    /// 会员引导横幅(锁定能力 / 服务端要求会员)。与 `errorMessage` 分离:
    /// 会员引导不是错误,不能配 ⚠️ 图标和(此处必然无效的)「重试」按钮。
    @Published var upsellMessage: String?
    @Published var quotaMessage: String?
    @Published var conversations: [KaiXGuideAIConversationDTO] = []
    @Published var suggestions: [KaiXGuideAISuggestionDTO] = []
    @Published var abilities: [KaiXGuideAIAbilityDTO] = []
    /// done 事件带回的追问建议(≤3 条),点按即发送;新一轮发送时清空。
    @Published var followupSuggestions: [String] = []
    /// Selected member-only ability (resume polish / mock interview), or nil for
    /// general chat. Server-authoritative — the gate is re-checked server-side.
    @Published var activeAbility: String?
    @Published var conversationId: String?
    @Published var membershipActive: Bool = false
    @Published var remainingFreeUses: Int?
    @Published var upgradeSuggested: Bool = false
    @Published var disclaimer: String?
    /// True once the daily quota is hit — the view shows the soft limit card.
    @Published private(set) var quotaReached: Bool = false
    /// 正在打开一条历史会话(视图渲染加载指示;`isLoading` 仍归 bootstrap 用)。
    @Published private(set) var isLoadingConversation: Bool = false
    /// 正在流式渲染的 assistant 气泡 id(首个 delta 到达时设置)。视图用它做
    /// 「锚定回答开头」的一次性滚动。
    @Published private(set) var streamingMessageId: String?
    /// 每收到一个流式 delta +1;视图据此做「仅当用户在底部时轻跟随」滚动。
    @Published private(set) var deltaTick: Int = 0
    /// 每完成一条回答 +1(流式与旧整段路径都算),视图用作答案到达的触感触发器。
    @Published private(set) var completedAnswerCount: Int = 0
    /// 旧整段回退路径完成的回答 id:答案是"砰"地整段到达的,视图滚动锚定到
    /// 它的开头(流式路径在首个 delta 时已锚定,不再触发)。
    @Published private(set) var legacyAnswerAnchorId: String?

    let language: AppLanguage
    private let country: String
    private var lastFailedText: String?
    private weak var lastUser: UserEntity?
    /// 打开历史会话失败时记下会话 id,让错误横幅的「重试」真正重放
    /// `loadConversation`(此前 `retryLastFailed` 在这种失败下是无操作的死按钮)。
    private var pendingRetryConversationId: String?
    /// 当前发送(流式或整段)的任务,「停止生成」取消它。
    private var sendTask: Task<Void, Never>?
    /// 仅当用户明确点了「停止生成」时,取消后才把问题放回输入框
    ///(切换会话等隐式取消不应污染输入框)。
    private var userRequestedStop = false
    /// True while the screen is used signed-out. Guests never see the
    /// member-oriented quota card / disabled composer — they get the login
    /// prompt instead — so the `quotaReached` computations skip them.
    private var isGuestSession = false

    /// Lifetime count of guest questions asked from this device — the soft
    /// local gate for "first question free, then sign in". The server stays
    /// authoritative on top via the X-Machi-Guest-Id daily quota.
    private static let guestQuestionCountKey = "machi-ai-guest-question-count"
    private var guestQuestionCount: Int {
        get { UserDefaults.standard.integer(forKey: Self.guestQuestionCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.guestQuestionCountKey) }
    }

    init(language: AppLanguage, country: String = "jp") {
        self.language = language
        self.country = country
    }

    var hasMessages: Bool { !messages.isEmpty }

    /// 错误横幅是否有可重试的动作(没有就渲染「关闭」而不是死按钮)。
    var canRetry: Bool { lastFailedText != nil || pendingRetryConversationId != nil }

    private var serverLanguage: String {
        switch language {
        case .ja: return "ja"
        case .en: return "en"
        default: return "zh-CN"
        }
    }

    // MARK: - loading

    func loadBootstrap(isGuest: Bool = false) {
        guard !isLoading else { return }
        isGuestSession = isGuest
        isLoading = true
        Task {
            defer { isLoading = false }  // never get stuck loading, even if cancelled
            // Guests bootstrap too (server supports X-Machi-Guest-Id); any
            // failure is swallowed and the view falls back to local chips.
            if let resp = try? await KaiXAPIClient.shared.guideAIBootstrap(
                country: country, language: serverLanguage,
                guestId: isGuest ? GuestSession.stableClientId : nil
            ) {
                membershipActive = resp.membershipActive ?? false
                remainingFreeUses = (resp.membershipActive == true) ? nil : resp.remainingFreeUses
                suggestions = resp.suggestions ?? []
                abilities = resp.abilities ?? []
                if let text = resp.disclaimer, !text.isEmpty { disclaimer = text }
                quotaReached = !isGuest && (membershipActive == false) && (remainingFreeUses ?? 1) <= 0
            }
            // Guests have no server-side history (401 by design) — skip it.
            if !isGuest, let convResp = try? await KaiXAPIClient.shared.guideAIConversations() {
                conversations = convResp.items ?? []
            }
        }
    }

    func refreshConversations() {
        Task {
            if let convResp = try? await KaiXAPIClient.shared.guideAIConversations() {
                conversations = convResp.items ?? []
            }
        }
    }

    func loadConversation(id: String) {
        guard !isLoadingConversation else { return }
        // 打开别的会话 = 隐式放弃当前生成(不是用户点「停止」,不回填输入框)。
        sendTask?.cancel()
        isLoadingConversation = true
        errorMessage = nil
        upsellMessage = nil
        followupSuggestions = []
        Task {
            defer { isLoadingConversation = false }  // never get stuck, even if cancelled
            do {
                let resp = try await KaiXAPIClient.shared.guideAIMessages(conversationId: id)
                pendingRetryConversationId = nil
                conversationId = resp.conversation?.id ?? id
                messages = (resp.items ?? []).map { dto in
                    GuideAIChatMessage(
                        id: dto.id,
                        role: dto.role == "user" ? .user : .assistant,
                        content: dto.content,
                        createdAt: Self.parseDate(dto.createdAt),
                        isPending: false,
                        failed: false,
                        sources: dto.sources ?? []
                    )
                }
            } catch {
                // 记住失败的会话 id:错误横幅的「重试」重放本方法。
                pendingRetryConversationId = id
                errorMessage = genericErrorText
            }
        }
    }

    /// Reset to a fresh conversation (keeps suggestions / membership state).
    func startNewConversation() {
        sendTask?.cancel()
        conversationId = nil
        messages = []
        quotaMessage = nil
        quotaReached = !isGuestSession && (membershipActive == false) && (remainingFreeUses ?? 1) <= 0
        errorMessage = nil
        upsellMessage = nil
        followupSuggestions = []
        activeAbility = nil
        lastFailedText = nil
        pendingRetryConversationId = nil
    }

    // MARK: - sending

    func sendCurrentInput(currentUser: UserEntity) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Keep the typed text if the guest gate is about to intercept — clearing
        // before the guest check (the old bug) lost the message and still showed
        // the login sheet, so after signing in the composer was empty. A guest's
        // first taster question really sends, so it clears like any other.
        guard !(currentUser.isGuest && guestQuestionCount >= 1) else {
            send(text: text, currentUser: currentUser)
            return
        }
        inputText = ""
        send(text: text, currentUser: currentUser)
    }

    /// Fill the composer from a suggestion/prompt chip and send immediately.
    func sendSuggestion(_ text: String, currentUser: UserEntity) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send(text: trimmed, currentUser: currentUser)
    }

    /// 「重新回答」:折叠旧答案,用原问题 + 当前 ability 重发一轮
    /// (不重复追加用户气泡)。
    func regenerate(assistantMessageId: String, currentUser: UserEntity) {
        guard !isSending, !quotaReached else { return }
        guard let idx = messages.firstIndex(where: { $0.id == assistantMessageId }),
              messages[idx].role == .assistant else { return }
        guard let question = messages[..<idx].last(where: { $0.role == .user })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !question.isEmpty else { return }
        // 游客门先于折叠检查:被登录墙拦下时不动任何消息状态。
        if currentUser.isGuest, guestQuestionCount >= 1 {
            GuestGate.shared.requireLogin(guestLoginPrompt)
            return
        }
        messages[idx].collapsed = true
        send(text: question, currentUser: currentUser, appendUserMessage: false)
    }

    /// 取消当前生成。已收到的部分保留并标注「已停止」;一字未收则撤掉
    /// 气泡、把问题放回输入框。
    func stopStreaming() {
        guard isSending else { return }
        userRequestedStop = true
        sendTask?.cancel()
    }

    func send(text: String, currentUser: UserEntity, appendUserMessage: Bool = true) {
        guard !isSending else { return }
        isGuestSession = currentUser.isGuest
        // Guests get exactly one taster question on this device (the server
        // enforces the real per-day guest quota via X-Machi-Guest-Id); from
        // the second question on they must sign in.
        if currentUser.isGuest, guestQuestionCount >= 1 {
            GuestGate.shared.requireLogin(guestLoginPrompt)
            return
        }
        lastUser = currentUser
        errorMessage = nil
        upsellMessage = nil
        followupSuggestions = []
        userRequestedStop = false

        var userMessageId: String?
        if appendUserMessage {
            let userMessage = GuideAIChatMessage(
                id: UUID().uuidString, role: .user, content: text, createdAt: Date(),
                isPending: false, failed: false, sources: []
            )
            messages.append(userMessage)
            userMessageId = userMessage.id
        }
        let pendingId = UUID().uuidString
        let typing = GuideAIChatMessage(
            id: pendingId, role: .assistant, content: "", createdAt: Date(),
            isPending: true, failed: false, sources: []
        )
        messages.append(typing)
        isSending = true

        let guestId = currentUser.isGuest ? GuestSession.stableClientId : nil
        sendTask = Task {
            defer {
                // 原有防御逻辑保留:任何路径(含取消)都复位发送态。
                isSending = false
                streamingMessageId = nil
                sendTask = nil
            }
            do {
                try await performSend(text: text, guestId: guestId,
                                      pendingId: pendingId, userMessageId: userMessageId)
            } catch is CancellationError {
                finalizeStopped(pendingId: pendingId, userMessageId: userMessageId, originalText: text)
            } catch let urlError as URLError where urlError.code == .cancelled {
                finalizeStopped(pendingId: pendingId, userMessageId: userMessageId, originalText: text)
            } catch let apiError as KaiXAPIError {
                handleFailure(apiError, pendingId: pendingId, userMessageId: userMessageId, text: text)
            } catch {
                if Task.isCancelled {
                    finalizeStopped(pendingId: pendingId, userMessageId: userMessageId, originalText: text)
                } else {
                    handleFailure(nil, pendingId: pendingId, userMessageId: userMessageId, text: text)
                }
            }
        }
    }

    /// 流式优先;404 回退整段 POST(旧服务端);200 非流式就地整段消费。
    private func performSend(text: String, guestId: String?,
                             pendingId: String, userMessageId: String?) async throws {
        do {
            let outcome = try await KaiXAPIClient.shared.streamGuideAIMessage(
                conversationId: conversationId, message: text,
                country: country, language: serverLanguage, category: nil,
                ability: activeAbility, guestId: guestId
            )
            switch outcome {
            case .legacy(let resp):
                applyChatResponse(resp, pendingId: pendingId, userMessageId: userMessageId, text: text)
            case .stream(let events):
                var receivedDelta = false
                for try await event in events {
                    switch event {
                    case .delta(let chunk):
                        guard !chunk.isEmpty else { continue }
                        appendDelta(chunk, pendingId: pendingId)
                        receivedDelta = true
                    case .done(let done):
                        finalizeStream(done, pendingId: pendingId, userMessageId: userMessageId, text: text)
                        return
                    case .error(let code, let message):
                        let resolved = message.isEmpty ? genericErrorText : message
                        if receivedDelta {
                            // 已有部分内容:保留 + 标注,只在横幅提示,不整体作废。
                            markInterrupted(pendingId: pendingId)
                            errorMessage = resolved
                        } else {
                            throw KaiXAPIError(error: .init(code: code, message: resolved))
                        }
                        return
                    }
                }
                // 流断在 done 之前:有内容按停止收尾,没内容按失败处理。
                if receivedDelta {
                    markInterrupted(pendingId: pendingId)
                    errorMessage = genericErrorText
                } else {
                    throw KaiXAPIError(error: .init(code: "ai_stream_interrupted", message: genericErrorText))
                }
            }
        } catch is KaiXGuideAIStreamUnsupported {
            // 旧服务端(404,消息未被处理):回退整段 POST,行为与升级前一致。
            let resp = try await KaiXAPIClient.shared.sendGuideAIMessage(
                conversationId: conversationId, message: text,
                country: country, language: serverLanguage, category: nil,
                ability: activeAbility, guestId: guestId
            )
            applyChatResponse(resp, pendingId: pendingId, userMessageId: userMessageId, text: text)
        }
    }

    func retryLastFailed() {
        // 打开历史会话失败的重试:重放 loadConversation(此前是死按钮)。
        if let cid = pendingRetryConversationId {
            pendingRetryConversationId = nil
            loadConversation(id: cid)
            return
        }
        guard let text = lastFailedText else { return }
        guard let user = lastUser else {
            errorMessage = genericErrorText
            return
        }
        // Drop the failed user bubble; send() re-appends a fresh one.
        if let idx = messages.lastIndex(where: { $0.role == .user && $0.failed }) {
            messages.remove(at: idx)
        }
        lastFailedText = nil
        send(text: text, currentUser: user)
    }

    func clearError() {
        errorMessage = nil
    }

    /// `reason` 仅点踩时携带(不准确 / 过时 / 无关 / 其他)。
    func submitFeedback(messageId: String, rating: String, reason: String? = nil) {
        Task {
            _ = try? await KaiXAPIClient.shared.sendGuideAIFeedback(messageId: messageId, rating: rating, reason: reason)
        }
    }

    // MARK: - streaming private

    private func appendDelta(_ chunk: String, pendingId: String) {
        guard let idx = messages.firstIndex(where: { $0.id == pendingId }) else { return }
        if messages[idx].isPending { messages[idx].isPending = false }
        messages[idx].content += chunk
        if streamingMessageId != pendingId { streamingMessageId = pendingId }
        deltaTick += 1
    }

    private func finalizeStream(_ done: KaiXGuideAIStreamDone, pendingId: String,
                                userMessageId: String?, text: String) {
        // 气泡已不在(切换了会话等):一切都是陈旧信息,整体丢弃。
        guard let idx = messages.firstIndex(where: { $0.id == pendingId }) else { return }
        let content = messages[idx].content
        guard !content.isEmpty else {
            // done 前没有任何 delta(异常响应):按失败处理,可重试。
            handleFailure(nil, pendingId: pendingId, userMessageId: userMessageId, text: text)
            return
        }
        if let cid = done.conversationId, !cid.isEmpty { conversationId = cid }
        if let quota = done.quota {
            membershipActive = quota.membershipActive ?? membershipActive
            remainingFreeUses = (quota.membershipActive == true) ? nil : (quota.remainingFreeUses ?? remainingFreeUses)
            upgradeSuggested = quota.upgradeSuggested ?? false
        }
        // 换上服务端消息 id(评价接口需要它);没有就保留本地 id。
        let finalId = (done.messageId?.isEmpty == false ? done.messageId : nil) ?? pendingId
        messages[idx] = GuideAIChatMessage(
            id: finalId, role: .assistant, content: content, createdAt: Date(),
            isPending: false, failed: false, sources: messages[idx].sources
        )
        followupSuggestions = Array(done.suggestions.prefix(3))
        completedAnswerCount += 1
        quotaMessage = nil
        quotaReached = !isGuestSession && (membershipActive == false) && (remainingFreeUses ?? 1) <= 0
        if lastUser?.isGuest == true {
            // Taster question consumed — the next attempt hits the login gate.
            guestQuestionCount += 1
        } else {
            // Keep the side list fresh so a new thread appears in history.
            refreshConversations()
        }
    }

    /// 流被服务端错误 / 断连打断,但已有部分内容:保留并标注「已停止」。
    private func markInterrupted(pendingId: String) {
        guard let idx = messages.firstIndex(where: { $0.id == pendingId }) else { return }
        messages[idx].isPending = false
        messages[idx].stopped = true
        if lastUser?.isGuest == true { guestQuestionCount += 1 }
    }

    /// 用户取消(或隐式取消)后的收尾。
    private func finalizeStopped(pendingId: String, userMessageId: String?, originalText: String) {
        guard let idx = messages.firstIndex(where: { $0.id == pendingId }) else { return }
        if messages[idx].content.isEmpty {
            // 一字未收:撤掉气泡;明确点了「停止」的话把问题放回输入框。
            messages.remove(at: idx)
            if userRequestedStop {
                if let userMessageId,
                   let userIdx = messages.firstIndex(where: { $0.id == userMessageId }) {
                    messages.remove(at: userIdx)
                }
                if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputText = originalText
                }
            }
        } else {
            messages[idx].isPending = false
            messages[idx].stopped = true
            if lastUser?.isGuest == true { guestQuestionCount += 1 }
        }
        userRequestedStop = false
    }

    // MARK: - private

    private func applyChatResponse(_ resp: KaiXGuideAIChatResponse, pendingId: String,
                                   userMessageId: String?, text: String) {
        conversationId = resp.conversationId ?? conversationId
        if let usage = resp.usage {
            membershipActive = usage.membershipActive ?? membershipActive
            remainingFreeUses = (usage.membershipActive == true) ? nil : (usage.remainingFreeUses ?? remainingFreeUses)
            upgradeSuggested = usage.upgradeSuggested ?? false
        }
        guard let message = resp.message else {
            // 200 with no message → treat as failure, but thread the original text
            // so the inline Retry button can actually resend (it was a no-op before).
            handleFailure(nil, pendingId: pendingId, userMessageId: userMessageId, text: text)
            return
        }
        if let idx = messages.firstIndex(where: { $0.id == pendingId }) {
            messages[idx] = GuideAIChatMessage(
                id: message.id, role: .assistant, content: message.content,
                createdAt: Self.parseDate(message.createdAt), isPending: false, failed: false,
                sources: message.sources ?? []
            )
            // 整段到达的答案:视图滚动锚定到它的开头(而不是滚到底)。
            legacyAnswerAnchorId = message.id
        }
        completedAnswerCount += 1
        quotaMessage = nil
        quotaReached = !isGuestSession && (membershipActive == false) && (remainingFreeUses ?? 1) <= 0
        if lastUser?.isGuest == true {
            // Taster question consumed — the next attempt hits the login gate.
            guestQuestionCount += 1
        } else {
            // Keep the side list fresh so a new thread appears in history.
            refreshConversations()
        }
    }

    private func handleFailure(_ apiError: KaiXAPIError?, pendingId: String,
                               userMessageId: String?, text: String?) {
        messages.removeAll { $0.id == pendingId }
        if let userMessageId, let idx = messages.firstIndex(where: { $0.id == userMessageId }) {
            messages[idx].failed = true
        }
        if let text { lastFailedText = text }

        switch apiError?.error.code {
        case "AI_QUOTA_EXCEEDED":
            // A guest hitting the server-side taster cap (e.g. a reinstall
            // reset the local count) goes to sign-in, not the member card.
            if lastUser?.isGuest == true {
                guestQuestionCount = max(guestQuestionCount, 1)
                GuestGate.shared.requireLogin(apiError?.error.message ?? guestLoginPrompt)
                return
            }
            quotaReached = true
            quotaMessage = apiError?.error.message
            if membershipActive == false {
                remainingFreeUses = 0
                upgradeSuggested = true
            }
        case "AI_MEMBER_ABILITY_REQUIRED":
            // Members-only ability requested without membership: drop back to
            // general chat and surface the upsell banner (NOT the error banner —
            // 会员引导不是网络错误,也没有可重试的动作).
            activeAbility = nil
            upsellMessage = apiError?.error.message ?? memberAbilityUpsellText
            upgradeSuggested = true
        case "AI_UNAVAILABLE":
            errorMessage = apiError?.error.message ?? genericErrorText
        default:
            errorMessage = apiError?.error.message ?? genericErrorText
        }
    }

    /// Toggle a Machi AI ability. Non-members tapping a members-only ability get
    /// an upgrade prompt instead of activating it (the server re-checks anyway).
    func selectAbility(_ ability: KaiXGuideAIAbilityDTO) {
        if (ability.memberOnly ?? false) && !membershipActive {
            // 中性会员引导(皇冠 + 开通按钮),不再挪用 ⚠️ 错误横幅 + 死「重试」。
            upsellMessage = guideText(
                language,
                "「\(ability.title)」是 Machi 会员专属能力，开通会员即可使用。",
                "「\(ability.title)」は Machi メンバー限定機能です。メンバーになると利用できます。",
                "“\(ability.title)” is a Machi members-only ability. Become a member to use it."
            )
            upgradeSuggested = true
            return
        }
        errorMessage = nil
        upsellMessage = nil
        activeAbility = (activeAbility == ability.key) ? nil : ability.key
    }

    private var genericErrorText: String {
        guideText(
            language,
            "网络好像不太稳定，请稍后再试。",
            "通信が不安定なようです。少し待ってから再度お試しください。",
            "The connection seems unstable. Please try again shortly."
        )
    }

    /// 服务端未附带文案时,会员能力横幅的默认引导语。
    private var memberAbilityUpsellText: String {
        guideText(
            language,
            "这是 Machi 会员专属能力，开通会员即可使用。",
            "こちらは Machi メンバー限定機能です。メンバーになると利用できます。",
            "This is a Machi members-only ability. Become a member to use it."
        )
    }

    /// Reason line on the login sheet once a guest's taster question is spent.
    private var guestLoginPrompt: String {
        guideText(
            language,
            "登录后可以使用 Machi AI 继续咨询日本生活、升学和就职问题。",
            "ログインすると Machi AI で日本生活・進学・就職の相談を続けられます。",
            "Sign in to keep asking Machi AI about life, study, and work in Japan."
        )
    }

    // Delegate to the shared cached KXDateParsing formatters; falls back to
    // `now` to preserve this call site's non-optional contract.
    private static func parseDate(_ raw: String?) -> Date { KXDateParsing.parse(raw) ?? Date() }
}
