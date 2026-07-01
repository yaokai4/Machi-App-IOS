import Combine
import Foundation

/// Role of a single Machi AI chat bubble.
enum GuideAIRole: String, Equatable {
    case user
    case assistant
}

/// Local UI model for one chat bubble. Distinct from the wire DTO so we can
/// represent transient client-only states (a pending "typing" assistant bubble,
/// a failed user turn) without round-tripping the server.
struct GuideAIChatMessage: Identifiable, Equatable {
    let id: String
    let role: GuideAIRole
    var content: String
    var createdAt: Date
    var isPending: Bool
    var failed: Bool
    var sources: [KaiXGuideAISourceDTO]
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
    @Published var quotaMessage: String?
    @Published var conversations: [KaiXGuideAIConversationDTO] = []
    @Published var suggestions: [KaiXGuideAISuggestionDTO] = []
    @Published var abilities: [KaiXGuideAIAbilityDTO] = []
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

    let language: AppLanguage
    private let country: String
    private var lastFailedText: String?
    private weak var lastUser: UserEntity?

    init(language: AppLanguage, country: String = "jp") {
        self.language = language
        self.country = country
    }

    var hasMessages: Bool { !messages.isEmpty }

    private var serverLanguage: String {
        switch language {
        case .ja: return "ja"
        case .en: return "en"
        default: return "zh-CN"
        }
    }

    // MARK: - loading

    func loadBootstrap() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }  // never get stuck loading, even if cancelled
            if let resp = try? await KaiXAPIClient.shared.guideAIBootstrap(country: country, language: serverLanguage) {
                membershipActive = resp.membershipActive ?? false
                remainingFreeUses = (resp.membershipActive == true) ? nil : resp.remainingFreeUses
                suggestions = resp.suggestions ?? []
                abilities = resp.abilities ?? []
                if let text = resp.disclaimer, !text.isEmpty { disclaimer = text }
                quotaReached = (membershipActive == false) && (remainingFreeUses ?? 1) <= 0
            }
            if let convResp = try? await KaiXAPIClient.shared.guideAIConversations() {
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
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let resp = try await KaiXAPIClient.shared.guideAIMessages(conversationId: id)
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
                errorMessage = genericErrorText
            }
            isLoading = false
        }
    }

    /// Reset to a fresh conversation (keeps suggestions / membership state).
    func startNewConversation() {
        conversationId = nil
        messages = []
        quotaMessage = nil
        quotaReached = (membershipActive == false) && (remainingFreeUses ?? 1) <= 0
        errorMessage = nil
        activeAbility = nil
        lastFailedText = nil
    }

    // MARK: - sending

    func sendCurrentInput(currentUser: UserEntity) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Keep the typed text if the guest gate is about to intercept — clearing
        // before the guest check (the old bug) lost the message and still showed
        // the login sheet, so after signing in the composer was empty.
        guard !currentUser.isGuest else {
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

    func send(text: String, currentUser: UserEntity) {
        guard !isSending else { return }
        // Guests can browse but must sign in to use Machi AI.
        if currentUser.isGuest {
            GuestGate.shared.requireLogin(guideText(
                language,
                "登录后可以使用 Machi AI 继续咨询日本生活、升学和就职问题。",
                "ログインすると Machi AI で日本生活・進学・就職の相談を続けられます。",
                "Sign in to keep asking Machi AI about life, study, and work in Japan."
            ))
            return
        }
        lastUser = currentUser
        errorMessage = nil

        let userMessage = GuideAIChatMessage(
            id: UUID().uuidString, role: .user, content: text, createdAt: Date(),
            isPending: false, failed: false, sources: []
        )
        let pendingId = UUID().uuidString
        let typing = GuideAIChatMessage(
            id: pendingId, role: .assistant, content: "", createdAt: Date(),
            isPending: true, failed: false, sources: []
        )
        messages.append(userMessage)
        messages.append(typing)
        isSending = true

        Task {
            defer { isSending = false }  // always clears, even on cancellation
            do {
                let resp = try await KaiXAPIClient.shared.sendGuideAIMessage(
                    conversationId: conversationId, message: text,
                    country: country, language: serverLanguage, category: nil,
                    ability: activeAbility
                )
                applyChatResponse(resp, pendingId: pendingId, userMessageId: userMessage.id, text: text)
            } catch let apiError as KaiXAPIError {
                handleFailure(apiError, pendingId: pendingId, userMessageId: userMessage.id, text: text)
            } catch {
                handleFailure(nil, pendingId: pendingId, userMessageId: userMessage.id, text: text)
            }
        }
    }

    func retryLastFailed() {
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

    func submitFeedback(messageId: String, rating: String) {
        Task {
            _ = try? await KaiXAPIClient.shared.sendGuideAIFeedback(messageId: messageId, rating: rating)
        }
    }

    // MARK: - private

    private func applyChatResponse(_ resp: KaiXGuideAIChatResponse, pendingId: String, userMessageId: String, text: String) {
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
        }
        quotaMessage = nil
        quotaReached = (membershipActive == false) && (remainingFreeUses ?? 1) <= 0
        // Keep the side list fresh so a new thread appears in history.
        refreshConversations()
    }

    private func handleFailure(_ apiError: KaiXAPIError?, pendingId: String, userMessageId: String, text: String?) {
        messages.removeAll { $0.id == pendingId }
        if let idx = messages.firstIndex(where: { $0.id == userMessageId }) {
            messages[idx].failed = true
        }
        if let text { lastFailedText = text }

        switch apiError?.error.code {
        case "AI_QUOTA_EXCEEDED":
            quotaReached = true
            quotaMessage = apiError?.error.message
            if membershipActive == false {
                remainingFreeUses = 0
                upgradeSuggested = true
            }
        case "AI_MEMBER_ABILITY_REQUIRED":
            // Members-only ability requested without membership: drop back to
            // general chat and surface the upgrade prompt.
            activeAbility = nil
            errorMessage = apiError?.error.message ?? genericErrorText
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
            errorMessage = guideText(
                language,
                "「\(ability.title)」是 Machi 会员专属能力，开通会员即可使用。",
                "「\(ability.title)」は Machi メンバー限定機能です。メンバーになると利用できます。",
                "“\(ability.title)” is a Machi members-only ability. Become a member to use it."
            )
            upgradeSuggested = true
            return
        }
        errorMessage = nil
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

    // Delegate to the shared cached KXDateParsing formatters; falls back to
    // `now` to preserve this call site's non-optional contract.
    private static func parseDate(_ raw: String?) -> Date { KXDateParsing.parse(raw) ?? Date() }
}
