import SwiftUI
import UIKit

/// Machi AI — the original in-app assistant for Japan life, study, work, and
/// using Machi. To the user this is entirely Machi's own feature: no provider,
/// model, or "powered by" is ever shown. Warm, trustworthy, advisor-grade.
struct GuideAIChatView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel: GuideAIViewModel
    @FocusState private var inputFocused: Bool
    @State private var showHistory = false
    @State private var containerWidth: CGFloat = UIScreen.main.bounds.width
    /// messageId → 已提交的评价。必须放在父视图:行视图在 LazyVStack 里滚出屏
    /// 即被回收,行内 @State 归零后已评价的消息恢复成未评价样式,还能对同一条
    /// 消息连发相反评价,污染反馈数据。
    @State private var feedbackByMessage: [String: String] = [:]

    let currentUser: UserEntity
    /// 场景快捷问题带入的预填文本(来自 .guideAI(prompt:) 路由载荷)。
    let initialPrompt: String?
    @State private var didApplyInitialPrompt = false

    init(currentUser: UserEntity, initialPrompt: String? = nil) {
        self.currentUser = currentUser
        self.initialPrompt = initialPrompt
        let lang = AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? AppLanguage.system.rawValue)
        _viewModel = StateObject(wrappedValue: GuideAIViewModel(language: lang))
    }

    var body: some View {
        ZStack {
            KXColor.livingBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(KXColor.livingInk.opacity(0.06))
                conversation
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in containerWidth = newValue }
            }
        )
        .toolbar(.hidden, for: .navigationBar)
        .kxEnableSwipeBack()
        .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
        .task { viewModel.loadBootstrap(isGuest: currentUser.isGuest) }
        .onAppear {
            // 场景快捷问题预填:只应用一次,且不覆盖用户已输入的草稿。
            if !didApplyInitialPrompt, let prompt = initialPrompt,
               viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.inputText = prompt
                inputFocused = true
            }
            didApplyInitialPrompt = true
        }
        .sheet(isPresented: $showHistory) {
            GuideAIHistorySheet(
                language: language,
                conversations: viewModel.conversations,
                onSelect: { id in
                    showHistory = false
                    viewModel.loadConversation(id: id)
                },
                onNew: {
                    showHistory = false
                    viewModel.startNewConversation()
                },
                onDelete: { id in
                    Task {
                        try? await KaiXAPIClient.shared.deleteGuideAIConversation(id: id)
                        viewModel.refreshConversations()
                        if viewModel.conversationId == id { viewModel.startNewConversation() }
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: KXSpacing.md) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(KXColor.livingInk)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(guideText(language, "返回", "戻る", "Back"))

            HStack(spacing: 10) {
                GuideAIAvatar(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Machi AI")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(KXColor.livingInk)
                    Text(guideText(language,
                                   "日本生活・升学・就职助手",
                                   "日本生活・進学・就職アシスタント",
                                   "Japan life, study & career assistant"))
                        .font(.caption2)
                        .foregroundStyle(KXColor.livingMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(KXColor.livingAccent)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(guideText(language, "历史会话", "履歴", "History"))
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, KXSpacing.sm)
    }

    // MARK: - conversation body

    @ViewBuilder
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !viewModel.hasMessages {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { message in
                            GuideAIMessageRow(
                                message: message,
                                language: language,
                                maxBubbleWidth: containerWidth,
                                feedback: feedbackByMessage[message.id],
                                onCopy: { copy(message.content) },
                                onFeedback: { rating in
                                    guard feedbackByMessage[message.id] == nil else { return }
                                    feedbackByMessage[message.id] = rating
                                    viewModel.submitFeedback(messageId: message.id, rating: rating)
                                },
                                onOpenSource: { source in open(source) }
                            )
                            .id(message.id)
                        }
                    }

                    if viewModel.quotaReached {
                        GuideAIQuotaCard(
                            language: language,
                            isMember: viewModel.membershipActive,
                            message: viewModel.quotaMessage,
                            onUpgrade: { router.open(.guideMemberResources, in: .guide) }
                        )
                        .padding(.top, KXSpacing.xs)
                    }

                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, 14)
                .padding(.bottom, KXSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy, animated: true) }
            .onChange(of: viewModel.isSending) { _, _ in scrollToBottom(proxy, animated: true) }
            .onChange(of: viewModel.quotaReached) { _, reached in if reached { scrollToBottom(proxy, animated: true) } }
        }
    }

    // MARK: - empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                GuideAIAvatar(size: 52)
                Text(guideText(language,
                               "在日本遇到的问题，先问 Machi AI",
                               "日本での困りごとは、まず Machi AI に",
                               "Stuck in Japan? Ask Machi AI first"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(KXColor.livingInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(guideText(language,
                               "手续、租房、升学、就职、日语学习和 Machi 使用，都可以从一个清晰答案开始。",
                               "手続き・住まい・進学・就職・日本語学習、そして Machi の使い方まで、ひとつの明快な答えから。",
                               "Paperwork, housing, study, work, Japanese, and using Machi — start from one clear answer."))
                    .font(.subheadline)
                    .foregroundStyle(KXColor.livingMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous).stroke(KXColor.livingAccentSoft, lineWidth: 1))

            usageStatusLine

            Text(guideText(language, "试试这样问", "こんな質問から", "Try asking"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KXColor.livingMuted)

            FlowChips(items: promptChips) { chip in
                viewModel.sendSuggestion(chip, currentUser: currentUser)
            }

            if let disclaimer = viewModel.disclaimer, !disclaimer.isEmpty {
                Text(disclaimer)
                    .font(.caption2)
                    .foregroundStyle(KXColor.livingMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, KXSpacing.xxs)
            }
        }
    }

    /// One quiet line of quota context: members see a member badge, free users
    /// (and guests) see today's remaining server-authoritative count. Hidden
    /// while the count is unknown (nil) so nothing flashes before bootstrap.
    @ViewBuilder
    private var usageStatusLine: some View {
        if viewModel.membershipActive {
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundStyle(KXColor.livingAccent)
                Text(guideText(language, "Machi 会员", "Machi メンバー", "Machi member"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(KXColor.livingMuted)
            }
        } else if let remaining = viewModel.remainingFreeUses {
            Text(guideText(language,
                           "今日还可咨询 \(remaining) 次",
                           "本日はあと \(remaining) 回相談できます",
                           remaining == 1 ? "1 question left today" : "\(remaining) questions left today"))
                .font(.caption2)
                .foregroundStyle(KXColor.livingMuted)
        }
    }

    /// #2: an always-present quota pill above the composer. Members see a member
    /// badge; free users (and guests) see today's remaining server-authoritative
    /// count, with an inline upgrade link once the count runs low (≤2). Hidden
    /// while the quota card is already showing, and while the count is unknown
    /// (pre-bootstrap) for non-members so nothing flashes.
    @ViewBuilder
    private var quotaPill: some View {
        if !viewModel.quotaReached {
            if viewModel.membershipActive {
                HStack(spacing: 5) {
                    Image(systemName: "crown.fill")
                        .kxScaledFont(10)
                        .foregroundStyle(KXColor.livingAccent)
                    Text(guideText(language, "Machi 会员 · 更高每日额度", "Machi メンバー · 1日の枠アップ", "Machi member · higher daily limit"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KXColor.livingMuted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, KXSpacing.xs)
            } else if let remaining = viewModel.remainingFreeUses {
                let low = remaining <= 2
                HStack(spacing: 6) {
                    Image(systemName: low ? "bolt.slash.fill" : "bolt.fill")
                        .kxScaledFont(10)
                        .foregroundStyle(low ? KXColor.livingWarm : KXColor.livingAccent)
                    Text(guideText(language,
                                   "今日还可咨询 \(remaining) 次",
                                   "本日はあと \(remaining) 回相談できます",
                                   remaining == 1 ? "1 question left today" : "\(remaining) questions left today"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(KXColor.livingMuted)
                    if low {
                        Button {
                            router.open(.guideMemberResources, in: .guide)
                        } label: {
                            Text(guideText(language, "升级会员", "会員登録", "Upgrade"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(KXColor.livingAccent)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, KXSpacing.xs)
                .transition(.opacity)
            }
        }
    }

    private var promptChips: [String] {
        // Server-curated suggestions from bootstrap take priority; the local
        // list below is the offline / older-backend fallback.
        let served = viewModel.suggestions.map(\.title).filter { !$0.isEmpty }
        if !served.isEmpty { return served }
        return [
            guideText(language, "刚来日本第一周要办什么？", "来日初週は何を手続きする？", "What to set up in my first week?"),
            guideText(language, "租房初期费用怎么看？", "賃貸の初期費用はどう見る？", "How do move-in costs work?"),
            guideText(language, "留学生找兼职要注意什么？", "留学生バイトの注意点は？", "Part-time work tips for students?"),
            guideText(language, "大学院申请第一步做什么？", "大学院出願の第一歩は？", "First step for grad school?"),
            guideText(language, "日企面试常见问题有哪些？", "日本企業の面接でよく聞かれる？", "Common Japanese interview questions?"),
            guideText(language, "履历书和职务经歴書有什么区别？", "履歴書と職務経歴書の違いは？", "Rirekisho vs shokumu-keirekisho?"),
            guideText(language, "签证更新前要准备什么？", "ビザ更新前に何を準備する？", "What to prep before a visa renewal?"),
            guideText(language, "Machi Guide 怎么用？", "Machi Guide はどう使う？", "How do I use Machi Guide?"),
        ]
    }

    // MARK: - input bar

    private var inputBar: some View {
        VStack(spacing: KXSpacing.sm) {
            quotaPill

            if let error = viewModel.errorMessage, !error.isEmpty {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(KXColor.livingWarm)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(KXColor.livingInk)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button(guideText(language, "重试", "再試行", "Retry")) {
                        viewModel.clearError()
                        viewModel.retryLastFailed()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.livingAccent)
                }
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, KXSpacing.sm)
                .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !viewModel.abilities.isEmpty && !viewModel.quotaReached {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: KXSpacing.sm) {
                        ForEach(viewModel.abilities) { ability in
                            let on = viewModel.activeAbility == ability.key
                            let locked = (ability.memberOnly ?? false) && !viewModel.membershipActive
                            Button {
                                viewModel.selectAbility(ability)
                            } label: {
                                HStack(spacing: KXSpacing.xs) {
                                    if locked {
                                        Image(systemName: "lock.fill").kxScaledFont(10)
                                    } else if on {
                                        Image(systemName: "checkmark").kxScaledFont(10, weight: .bold)
                                    }
                                    Text(ability.title).font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, KXSpacing.md)
                                .padding(.vertical, 7)
                                .foregroundStyle(on ? KXColor.livingAccent : KXColor.livingMuted)
                                .background(
                                    Capsule().fill(on ? KXColor.livingAccent.opacity(0.14) : KXColor.livingSurface)
                                )
                                .overlay(
                                    Capsule().stroke(on ? KXColor.livingAccent.opacity(0.5) : KXColor.livingInk.opacity(0.08),
                                                     lineWidth: on ? 1.2 : 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, KXSpacing.xxs)
                }
            }

            HStack(alignment: .bottom, spacing: 9) {
                TextField(
                    inputPlaceholder,
                    text: $viewModel.inputText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .lineLimit(1...5)
                .font(.body)
                .foregroundStyle(KXColor.livingInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous)
                        .stroke(inputFocused ? KXColor.livingAccent.opacity(0.5) : KXColor.livingInk.opacity(0.08),
                                lineWidth: inputFocused ? 1.3 : 0.8)
                )
                .disabled(viewModel.quotaReached)

                sendButton
            }
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, 10)
        .background(
            KXColor.livingBackground.opacity(0.96)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            LinearGradient(colors: [KXColor.livingInk.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 1)
        }
        .animation(.snappy(duration: 0.2), value: viewModel.errorMessage)
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isSending && !viewModel.quotaReached
    }

    /// Composer placeholder adapts to the active member ability.
    private var inputPlaceholder: String {
        switch viewModel.activeAbility {
        case "resume_polish":
            return guideText(language,
                             "粘贴你的履历书 / 职务経歴書 / 自己PR / 志望动机…",
                             "履歴書・職務経歴書・自己PR・志望動機を貼り付け…",
                             "Paste your resume / shokumu-keirekisho / PR to polish…")
        case "mock_interview":
            return guideText(language,
                             "告诉我你应聘的行业 / 职位，开始模拟面试…",
                             "応募する業界・職種を教えて、模擬面接を開始…",
                             "Tell me the role you're applying for to start the mock interview…")
        default:
            return guideText(language,
                             "问问日本生活、升学、就职或 Machi 使用问题…",
                             "日本生活・進学・就職や Machi の使い方を質問…",
                             "Ask about life, study, work in Japan, or using Machi…")
        }
    }

    private var sendButton: some View {
        Button {
            inputFocused = false
            viewModel.sendCurrentInput(currentUser: currentUser)
        } label: {
            ZStack {
                Circle()
                    .fill(canSend ? KXColor.livingAccent : KXColor.livingMuted.opacity(0.3))
                    .frame(width: 44, height: 44)
                if viewModel.isSending {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .kxScaledFont(17, weight: .semibold)
                        // Ink follows the enabled accent fill (near-black on the
                        // brightened dark-mode teal); disabled keeps the muted
                        // translucent fill's original white glyph.
                        .foregroundStyle(canSend ? KXColor.onTint(KXColor.livingAccent) : Color.white)
                        .offset(x: -1, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel(guideText(language, "发送", "送信", "Send"))
    }

    // MARK: - actions

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    private func open(_ source: KaiXGuideAISourceDTO) {
        guard let route = source.kxRoute else { return }
        router.open(route, in: .guide)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { action() }
        } else {
            action()
        }
    }

    private static let bottomAnchor = "machi-ai-bottom"
}

// MARK: - Machi AI avatar (M + sparkle, brand accent)

private struct GuideAIAvatar: View {
    var size: CGFloat = 34

    var body: some View {
        MachiAIMark(size: size)
            .shadow(color: KXColor.livingAccent.opacity(0.28), radius: 5, y: 2)
    }
}

// MARK: - one message row (user or assistant)

private struct GuideAIMessageRow: View {
    let message: GuideAIChatMessage
    let language: AppLanguage
    let maxBubbleWidth: CGFloat
    /// 该消息已提交的评价,由父视图持有(行内 @State 会随 LazyVStack 回收丢失)。
    let feedback: String?
    let onCopy: () -> Void
    let onFeedback: (String) -> Void
    let onOpenSource: (KaiXGuideAISourceDTO) -> Void

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: maxBubbleWidth * 0.18)
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(KXColor.onTint(KXColor.livingAccent))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(KXColor.livingAccent, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                    // Cap the bubble width so very long / unbroken input (URLs, long
                    // tokens) wraps instead of pushing content off-screen.
                    .frame(maxWidth: maxBubbleWidth * 0.82, alignment: .trailing)
                    .opacity(message.failed ? 0.55 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if message.failed {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(KXColor.livingWarm)
                                .offset(x: 4, y: 4)
                        }
                    }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                    Text("Machi AI")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(KXColor.livingMuted)
                }
                if message.isPending {
                    GuideAITypingDots()
                        .padding(.horizontal, 14)
                        .padding(.vertical, KXSpacing.md)
                        .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                } else {
                    MachiAIMarkdownText(text: message.content)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous).stroke(KXColor.livingInk.opacity(0.05), lineWidth: 0.8))

                    if let sources = message.sources.nonEmpty {
                        GuideAISourcesView(language: language, sources: sources, onOpen: onOpenSource)
                    }
                    actionRow
                }
            }
            .frame(maxWidth: maxBubbleWidth * 0.9, alignment: .leading)
        }
    }

    private var actionRow: some View {
        HStack(spacing: KXSpacing.lg) {
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .accessibilityLabel(guideText(language, "复制", "コピー", "Copy"))

            Button {
                onFeedback("helpful")
            } label: {
                Image(systemName: feedback == "helpful" ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .disabled(feedback != nil)   // 已评价即锁定,防止重复/矛盾提交
            .accessibilityLabel(guideText(language, "有帮助", "役に立った", "Helpful"))

            Button {
                onFeedback("not_helpful")
            } label: {
                Image(systemName: feedback == "not_helpful" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .disabled(feedback != nil)
            .accessibilityLabel(guideText(language, "没帮助", "役に立たなかった", "Not helpful"))
        }
        .font(.footnote)
        .foregroundStyle(KXColor.livingMuted)
        .buttonStyle(.plain)
        .padding(.leading, KXSpacing.xxs)
        .padding(.top, 1)
    }
}

// MARK: - typing indicator (three bouncing dots)

private struct GuideAITypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(KXColor.livingMuted)
                    .frame(width: 7, height: 7)
                    .opacity(animating ? 1 : 0.3)
                    .scaleEffect(animating ? 1 : 0.6)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.18),
                        value: animating
                    )
            }
        }
        // Guard the perpetual bounce behind Reduce Motion + UITest idle (same as
        // KXSpinner/KXShimmer) — a repeatForever animation never lets XCUITest
        // reach an idle snapshot, and it ignores the accessibility switch.
        .onAppear {
            guard !reduceMotion, !KXRuntime.isUITesting else { return }
            animating = true
        }
        .accessibilityLabel("Machi AI")
    }
}

// MARK: - lightweight Markdown rendering for Machi AI answers

/// Renders the assistant's Markdown (headings / bullets / numbered lists /
/// **bold**) as native SwiftUI instead of showing raw `###` / `**` markers.
/// Dependency-free: block-level parsing by line + inline bold via
/// AttributedString. Falls back to plain text on any parse hiccup.
private struct MachiAIMarkdownText: View {
    let text: String

    private struct Block: Identifiable {
        let id = UUID()
        enum Kind { case heading, bullet, numbered, body, gap }
        let kind: Kind
        let content: String
        let marker: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            ForEach(blocks) { block in
                switch block.kind {
                case .gap:
                    Color.clear.frame(height: 3)
                case .heading:
                    inline(block.content)
                        .font(.callout.weight(.bold))
                        .padding(.top, KXSpacing.xxs)
                case .bullet:
                    HStack(alignment: .top, spacing: KXSpacing.sm) {
                        Circle().fill(KXColor.livingAccent)
                            .frame(width: 5, height: 5)
                            .padding(.top, KXSpacing.sm)
                        inline(block.content)
                    }
                case .numbered:
                    HStack(alignment: .top, spacing: KXSpacing.sm) {
                        Text(block.marker ?? "•")
                            .font(.body.weight(.bold))
                            .foregroundStyle(KXColor.livingAccent)
                        inline(block.content)
                    }
                case .body:
                    inline(block.content)
                }
            }
        }
    }

    @ViewBuilder
    private func inline(_ string: String) -> some View {
        Text(Self.attributed(string))
            .font(.body)
            .foregroundStyle(KXColor.livingInk)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func attributed(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for raw in normalized.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if out.last?.kind != .gap, !out.isEmpty {
                    out.append(Block(kind: .gap, content: "", marker: nil))
                }
                continue
            }
            if let heading = Self.stripHeading(line) {
                out.append(Block(kind: .heading, content: heading, marker: nil))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                let content = String(line.dropFirst(2))
                // A bare "- " (empty bullet) renders the raw line rather than an
                // empty bullet row.
                out.append(Block(kind: content.isEmpty ? .body : .bullet,
                                 content: content.isEmpty ? line : content, marker: nil))
            } else if let range = line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) {
                let marker = line[line.startIndex..<range.upperBound].trimmingCharacters(in: .whitespaces)
                out.append(Block(kind: .numbered, content: String(line[range.upperBound...]), marker: marker))
            } else {
                out.append(Block(kind: .body, content: line, marker: nil))
            }
        }
        while out.last?.kind == .gap { out.removeLast() }
        return out
    }

    private static func stripHeading(_ line: String) -> String? {
        for prefix in ["#### ", "### ", "## ", "# "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }
}

// MARK: - Guide reference sources

private struct GuideAISourcesView: View {
    let language: AppLanguage
    let sources: [KaiXGuideAISourceDTO]
    let onOpen: (KaiXGuideAISourceDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(guideText(language, "Machi Guide 参考", "Machi Guide 参考", "From Machi Guide"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(KXColor.livingMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KXSpacing.sm) {
                    ForEach(sources) { source in
                        Button { onOpen(source) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: source.kxIcon)
                                    .font(.caption2)
                                Text(source.title ?? "")
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                if source.kxRoute != nil {
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            .foregroundStyle(KXColor.livingAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(KXColor.livingAccentSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(source.kxRoute == nil)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.top, KXSpacing.xxs)
    }
}

// MARK: - quota card

private struct GuideAIQuotaCard: View {
    let language: AppLanguage
    let isMember: Bool
    let message: String?
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: KXSpacing.sm) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(KXColor.livingAccent)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.livingInk)
            }
            Text(message ?? detailText)
                .font(.footnote)
                .foregroundStyle(KXColor.livingMuted)
                .fixedSize(horizontal: false, vertical: true)
            if !isMember {
                HStack(spacing: 10) {
                    Button(action: onUpgrade) {
                        Text(guideText(language, "查看 Machi 会员", "Machi 会員を見る", "See Machi membership"))
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(KXColor.onTint(KXColor.livingAccent))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(KXColor.livingAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Text(guideText(language, "明天再来", "また明日", "Come back tomorrow"))
                        .font(.footnote)
                        .foregroundStyle(KXColor.livingMuted)
                }
            }
        }
        .padding(KXSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous).stroke(KXColor.livingAccentSoft, lineWidth: 1))
    }

    private var title: String {
        isMember
            ? guideText(language, "今天先到这里", "今日はここまで", "That's all for today")
            : guideText(language, "今日免费咨询已用完", "本日の無料相談は終了", "Today's free questions are used up")
    }

    private var detailText: String {
        isMember
            ? guideText(language,
                        "Machi AI 今天的使用次数已用完，明天可以继续咨询。",
                        "Machi AI の本日のご利用は終了しました。明日また相談できます。",
                        "Machi AI is done for today. You can continue tomorrow.")
            : guideText(language,
                        "明天可以继续使用 Machi AI。开通会员后，可以获得更多 AI 咨询和 Guide 资料权益。",
                        "明日また Machi AI を利用できます。会員になると、より多くの AI 相談と Guide 特典が使えます。",
                        "Machi AI resets tomorrow. Membership unlocks more AI help and Guide perks.")
    }
}

// MARK: - history sheet

private struct GuideAIHistorySheet: View {
    let language: AppLanguage
    let conversations: [KaiXGuideAIConversationDTO]
    let onSelect: (String) -> Void
    let onNew: () -> Void
    let onDelete: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onNew) {
                        Label(guideText(language, "新对话", "新しい会話", "New chat"), systemImage: "plus.circle.fill")
                            .foregroundStyle(KXColor.livingAccent)
                    }
                }
                if conversations.isEmpty {
                    Section {
                        Text(guideText(language, "还没有历史会话", "履歴はまだありません", "No conversations yet"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section(guideText(language, "最近会话", "最近の会話", "Recent")) {
                        ForEach(conversations) { conversation in
                            Button { onSelect(conversation.id) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(conversation.title?.nonEmpty ?? guideText(language, "对话", "会話", "Conversation"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if let preview = conversation.lastMessagePreview?.nonEmpty {
                                        Text(preview)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { onDelete(conversation.id) } label: {
                                    Label(guideText(language, "删除", "削除", "Delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(guideText(language, "历史会话", "履歴", "History"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - small layout + DTO helpers

/// Wrapping chip layout that flows onto multiple lines (no horizontal scroll).
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlexibleChipLayout(spacing: KXSpacing.sm, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(KXColor.livingInk)
                        .lineLimit(1)
                        .padding(.horizontal, KXSpacing.md)
                        .padding(.vertical, KXSpacing.sm)
                        .background(KXColor.livingSurface, in: Capsule())
                        .overlay(Capsule().stroke(KXColor.livingAccentSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal flow layout so prompt chips wrap to new lines on any screen width.
private struct FlexibleChipLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? UIScreen.main.bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

private extension KaiXGuideAISourceDTO {
    /// Map a public source locator to an in-app Guide route (nil = not navigable).
    var kxRoute: KXRoute? {
        guard let route else { return nil }
        let kind = (route.kind ?? type ?? "").lowercased()
        switch kind {
        case "article", "guide_article":
            if let slug = route.slug?.nonEmpty { return .guideArticle(slug: slug) }
        case "product", "guide_product":
            if let slug = route.slug?.nonEmpty { return .guideProduct(slug: slug) }
        case "school", "guide_school":
            if let id = route.id?.nonEmpty { return .guideSchool(id: id) }
        case "company", "guide_company":
            if let id = route.id?.nonEmpty { return .guideCompany(id: id) }
        default:
            return nil
        }
        return nil
    }

    var kxIcon: String {
        switch (type ?? route?.kind ?? "").lowercased() {
        case let value where value.contains("school"): return "graduationcap.fill"
        case let value where value.contains("company"): return "building.2.fill"
        case let value where value.contains("product"): return "doc.richtext.fill"
        case let value where value.contains("faq"): return "questionmark.circle.fill"
        default: return "book.fill"
        }
    }
}
