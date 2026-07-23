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
    /// 配额升级入口直达会员购买页（此前跳会员资料库，转化路径多一跳）。
    @State private var showMembershipSheet = false
    @State private var containerWidth: CGFloat = UIScreen.main.bounds.width
    /// messageId → 已提交的评价。必须放在父视图:行视图在 LazyVStack 里滚出屏
    /// 即被回收,行内 @State 归零后已评价的消息恢复成未评价样式,还能对同一条
    /// 消息连发相反评价,污染反馈数据。
    @State private var feedbackByMessage: [String: String] = [:]
    /// C-4 faq 溯源 chip 的落点 sheet(FAQ 无独立路由)。
    @State private var faqSource: KaiXGuideAISourceDTO?
    /// 轻量浮层提示(「已复制」等),自动消失。
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?
    /// 复制触感触发器。
    @State private var copyTick = 0
    /// 点踩原因选择的目标消息 id(非 nil 时弹 confirmationDialog)。
    @State private var dislikeTargetId: String?
    /// 「重新回答」后被折叠的旧答案中,用户手动展开的那些。放在父视图:
    /// 行内 @State 会随 LazyVStack 回收丢失。
    @State private var expandedOldAnswers: Set<String> = []
    /// 底部哨兵可见性:流式期间「仅当用户本就在底部时轻跟随」的依据。
    @State private var isNearBottom = true
    /// 流式开始后用户是否手动滚动过。没有滚动 = 保持锚定在回答开头,
    /// 绝不自动滚底;用户自己滚到底部后才轻跟随。
    @State private var userScrolledSinceStreamStart = false

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
        // 轻量 toast(「已复制」等),悬浮在输入栏上方,不挡点按。
        .overlay(alignment: .bottom) {
            if let toast = toastText {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KXColor.livingBackground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(KXColor.livingInk.opacity(0.9), in: Capsule())
                    .padding(.bottom, KXSpacing.md)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // 全链路触感:复制成功 / 发送 / 答案到达 / 评价 / 配额用尽。
        .sensoryFeedback(.success, trigger: copyTick)
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.isSending) { _, sending in sending }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.completedAnswerCount)
        .sensoryFeedback(.selection, trigger: feedbackByMessage)
        .sensoryFeedback(.warning, trigger: viewModel.quotaReached) { _, reached in reached }
        // 点踩先问原因(不准确 / 过时 / 无关 / 其他),选择后才提交。
        .confirmationDialog(
            guideText(language, "这条回答哪里没帮到你？", "この回答のどこが良くなかったですか？", "What was wrong with this answer?"),
            isPresented: Binding(
                get: { dislikeTargetId != nil },
                set: { if !$0 { dislikeTargetId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(guideText(language, "不准确", "情報が不正確", "Inaccurate")) { submitDislike("inaccurate") }
            Button(guideText(language, "信息过时", "情報が古い", "Outdated")) { submitDislike("outdated") }
            Button(guideText(language, "与问题无关", "質問と関係ない", "Not relevant")) { submitDislike("irrelevant") }
            Button(guideText(language, "其他原因", "その他", "Other")) { submitDislike("other") }
            Button(guideText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
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
                    // 删除失败要让用户知道(此前 try? 静默吞错,行不消失也无提示)。
                    // 返回成功与否,由 sheet 就地弹 alert 提示——根视图的 toast 会被
                    // 展开的 sheet 盖住,用户看不到。
                    do {
                        try await KaiXAPIClient.shared.deleteGuideAIConversation(id: id)
                        viewModel.refreshConversations()
                        if viewModel.conversationId == id { viewModel.startNewConversation() }
                        return true
                    } catch {
                        return false
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMembershipSheet) {
            NavigationStack { MembershipView(currentUser: currentUser) }
        }
        .sheet(item: $faqSource) { source in
            GuideAIFAQSheet(language: language, source: source)
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

    /// 抽成独立方法:15+ 参数带多个闭包的初始化直接内联会让类型检查器超时,
    /// 把 canRegenerate 提成局部 let 后编译器可分段求解。
    @ViewBuilder
    private func messageRow(_ message: GuideAIChatMessage) -> some View {
        let canRegenerate = message.role == .assistant && !message.collapsed
            && !viewModel.isSending && !viewModel.quotaReached
        GuideAIMessageRow(
            message: message,
            language: language,
            maxBubbleWidth: containerWidth,
            feedback: feedbackByMessage[message.id],
            isExpandedOldAnswer: expandedOldAnswers.contains(message.id),
            isStreaming: viewModel.streamingMessageId == message.id,
            canRegenerate: canRegenerate,
            onCopy: { copy(message.content) },
            onFeedback: { rating in
                guard feedbackByMessage[message.id] == nil else { return }
                if rating == "not_helpful" {
                    // 点踩先问原因,选完才提交(见 confirmationDialog)。
                    dislikeTargetId = message.id
                } else {
                    feedbackByMessage[message.id] = rating
                    viewModel.submitFeedback(messageId: message.id, rating: rating)
                }
            },
            onRegenerate: {
                viewModel.regenerate(assistantMessageId: message.id, currentUser: currentUser)
            },
            onToggleOldAnswer: { toggleOldAnswer(message.id) },
            onOpenSource: { source in open(source) }
        )
    }

    @ViewBuilder
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !viewModel.hasMessages {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }

                    // done 事件带回的追问建议:把单轮问答接成多轮。
                    if !viewModel.isSending, !viewModel.quotaReached,
                       !viewModel.followupSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: KXSpacing.sm) {
                            Text(guideText(language, "继续追问", "続けて聞く", "Keep asking"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(KXColor.livingMuted)
                            FlowChips(items: viewModel.followupSuggestions) { chip in
                                viewModel.sendSuggestion(chip, currentUser: currentUser)
                            }
                        }
                        .padding(.top, KXSpacing.xxs)
                        .transition(.opacity)
                    }

                    if viewModel.quotaReached {
                        GuideAIQuotaCard(
                            language: language,
                            isMember: viewModel.membershipActive,
                            message: viewModel.quotaMessage,
                            onUpgrade: { showMembershipSheet = true }
                        )
                        .padding(.top, KXSpacing.xs)
                    }

                    Color.clear.frame(height: 1)
                        .id(Self.bottomAnchor)
                        // 底部哨兵:在视口内 = 用户就在底部(轻跟随的前提)。
                        .onAppear { isNearBottom = true }
                        .onDisappear { isNearBottom = false }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, 14)
                .padding(.bottom, KXSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            // 记录流式期间的手动滚动:只有用户自己滚过、且当前就在底部,
            // delta 到达才轻跟随;否则严格保持锚定在回答开头。
            .simultaneousGesture(
                DragGesture(minimumDistance: 12).onChanged { _ in
                    if viewModel.isSending { userScrolledSinceStreamStart = true }
                }
            )
            // 打开历史会话的加载指示(此前 isLoading 从未被视图消费,零反馈)。
            .overlay(alignment: .top) {
                if viewModel.isLoadingConversation {
                    HStack(spacing: KXSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text(guideText(language, "正在打开会话…", "会話を読み込み中…", "Opening conversation…"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(KXColor.livingMuted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(KXColor.livingSurface, in: Capsule())
                    .overlay(Capsule().stroke(KXColor.livingInk.opacity(0.06), lineWidth: 0.8))
                    .padding(.top, KXSpacing.sm)
                    .transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.2), value: viewModel.isLoadingConversation)
            // 只在消息数增加时滚到底(发送 / 打开历史);替换与删除不触发。
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                if newCount > oldCount { scrollToBottom(proxy, animated: true) }
            }
            // 流式开始:一次性锚定到回答开头,长答案从头读起;此后绝不自动滚底。
            .onChange(of: viewModel.streamingMessageId) { _, newValue in
                guard let newValue else { return }
                userScrolledSinceStreamStart = false
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .top)
                }
            }
            // delta 轻跟随:仅当用户流式开始后自己滚动过、且当前就在底部。
            .onChange(of: viewModel.deltaTick) { _, _ in
                if isNearBottom && userScrolledSinceStreamStart {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            // 旧整段回退路径:答案"砰"地整段到达时锚定它的开头(而不是滚到底)。
            .onChange(of: viewModel.legacyAnswerAnchorId) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .top)
                }
            }
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
                            showMembershipSheet = true
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

            // 会员引导横幅(锁定能力等):中性样式,皇冠 + 直达开通,
            // 不再挪用 ⚠️ 错误横幅和此处必然无效的「重试」按钮。
            if let upsell = viewModel.upsellMessage, !upsell.isEmpty {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(KXColor.livingAccent)
                    Text(upsell)
                        .font(.caption)
                        .foregroundStyle(KXColor.livingInk)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        viewModel.upsellMessage = nil
                        showMembershipSheet = true
                    } label: {
                        Text(guideText(language, "开通会员", "会員になる", "Join"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.onTint(KXColor.livingAccent))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(KXColor.livingAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        viewModel.upsellMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(KXColor.livingMuted)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(guideText(language, "关闭", "閉じる", "Dismiss"))
                }
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, KXSpacing.sm)
                .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.livingAccentSoft, lineWidth: 1))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let error = viewModel.errorMessage, !error.isEmpty {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(KXColor.livingWarm)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(KXColor.livingInk)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if viewModel.canRetry {
                        Button(guideText(language, "重试", "再試行", "Retry")) {
                            viewModel.clearError()
                            viewModel.retryLastFailed()
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                    } else {
                        // 无可重试动作时给「关闭」,不再渲染无操作的死按钮。
                        Button {
                            viewModel.clearError()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KXColor.livingMuted)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(guideText(language, "关闭", "閉じる", "Dismiss"))
                    }
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
        .animation(.snappy(duration: 0.2), value: viewModel.upsellMessage)
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

    /// 发送中变为「停止生成」:随时可逃,不再被弱网当 40 秒人质。
    @ViewBuilder
    private var sendButton: some View {
        if viewModel.isSending {
            Button {
                viewModel.stopStreaming()
            } label: {
                ZStack {
                    Circle()
                        .fill(KXColor.livingAccent.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(KXColor.livingAccent.opacity(0.5), lineWidth: 1.2)
                        .frame(width: 44, height: 44)
                    Image(systemName: "stop.fill")
                        .kxScaledFont(15, weight: .semibold)
                        .foregroundStyle(KXColor.livingAccent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(guideText(language, "停止生成", "生成を停止", "Stop generating"))
        } else {
            Button {
                inputFocused = false
                viewModel.sendCurrentInput(currentUser: currentUser)
            } label: {
                ZStack {
                    Circle()
                        .fill(canSend ? KXColor.livingAccent : KXColor.livingMuted.opacity(0.3))
                        .frame(width: 44, height: 44)
                    Image(systemName: "paperplane.fill")
                        .kxScaledFont(17, weight: .semibold)
                        // Ink follows the enabled accent fill (near-black on the
                        // brightened dark-mode teal); disabled keeps the muted
                        // translucent fill's original white glyph.
                        .foregroundStyle(canSend ? KXColor.onTint(KXColor.livingAccent) : Color.white)
                        .offset(x: -1, y: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(guideText(language, "发送", "送信", "Send"))
        }
    }

    // MARK: - actions

    private func copy(_ text: String) {
        // 复制纯文本(去掉 ###/** 等原始 markdown 记号,保留列表结构)。
        UIPasteboard.general.string = Self.plainCopyText(text)
        copyTick += 1
        showToast(guideText(language, "已复制", "コピーしました", "Copied"))
    }

    /// 把回答的 markdown 转为适合粘贴的纯文本。
    private static func plainCopyText(_ markdown: String) -> String {
        var text = markdown.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: #"(?m)^#{1,4}\s+"#, with: "", options: .regularExpression)
        return text
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) { toastText = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { toastText = nil }
        }
    }

    private func submitDislike(_ reason: String) {
        guard let id = dislikeTargetId else { return }
        dislikeTargetId = nil
        guard feedbackByMessage[id] == nil else { return }
        feedbackByMessage[id] = "not_helpful"
        viewModel.submitFeedback(messageId: id, rating: "not_helpful", reason: reason)
    }

    private func toggleOldAnswer(_ id: String) {
        withAnimation(.snappy(duration: 0.22)) {
            if expandedOldAnswers.contains(id) {
                expandedOldAnswers.remove(id)
            } else {
                expandedOldAnswers.insert(id)
            }
        }
    }

    private func open(_ source: KaiXGuideAISourceDTO) {
        // C-4:faq 项没有独立详情页,就地弹完整问答 sheet;其余走路由。
        if source.kxFaqId != nil {
            faqSource = source
            return
        }
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
    /// 「重新回答」后旧答案默认折叠,父视图持有展开态。
    let isExpandedOldAnswer: Bool
    /// 该条正在流式接收 delta:隐藏操作栏,避免对半截答案复制/评价/再生成。
    let isStreaming: Bool
    /// 可对该条发起「重新回答」(assistant / 非折叠 / 不在发送中 / 未超额)。
    let canRegenerate: Bool
    let onCopy: () -> Void
    let onFeedback: (String) -> Void
    let onRegenerate: () -> Void
    let onToggleOldAnswer: () -> Void
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
                if message.isPending && message.content.isEmpty {
                    // 首个 delta 到达前的等待:三点跳动。流式开始后 content 非空,
                    // 直接渲染正文,delta 追加即打字机效果。
                    GuideAITypingDots()
                        .padding(.horizontal, 14)
                        .padding(.vertical, KXSpacing.md)
                        .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                } else if message.collapsed && !isExpandedOldAnswer {
                    // 「重新回答」产生的旧答案:默认折叠成一行,点开才展开。
                    Button(action: onToggleOldAnswer) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(guideText(language, "旧回答 · 点开查看", "以前の回答 · タップで表示", "Previous answer · tap to view"))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                        }
                        .font(.footnote)
                        .foregroundStyle(KXColor.livingMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(KXColor.livingSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    MachiAIMarkdownText(text: message.content)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous).stroke(KXColor.livingInk.opacity(0.05), lineWidth: 0.8))
                        .opacity(message.collapsed ? 0.72 : 1)

                    if message.stopped {
                        Text(guideText(language, "已停止", "停止しました", "Stopped"))
                            .font(.caption2)
                            .foregroundStyle(KXColor.livingMuted)
                            .padding(.leading, KXSpacing.xxs)
                    }

                    if let sources = message.sources.nonEmpty {
                        GuideAISourcesView(language: language, sources: sources, onOpen: onOpenSource)
                    }
                    // 流式进行中不出操作栏:半截答案不该被复制/评价/再生成。
                    if !isStreaming {
                        if message.collapsed {
                            Button(action: onToggleOldAnswer) {
                                Label(guideText(language, "收起", "折りたたむ", "Collapse"), systemImage: "chevron.up")
                                    .font(.footnote)
                                    .foregroundStyle(KXColor.livingMuted)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, KXSpacing.xxs)
                        } else {
                            actionRow
                        }
                    }
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

            // 已停止 / 中断的回答只有本地 UUID(无服务端 messageId),对它提交
            // 评价会把假 id 发给服务端,因此不出赞/踩(复制、重新回答仍可用)。
            if !message.stopped {
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

            if canRegenerate {
                Button(action: onRegenerate) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(guideText(language, "重新回答", "回答し直す", "Regenerate"))
            }
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
                                if let badge = source.kxPriceBadge(language) {
                                    Text(badge)
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(KXColor.livingSurface, in: Capsule())
                                }
                                if source.kxNavigable {
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
                        .disabled(!source.kxNavigable)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.top, KXSpacing.xxs)
    }
}

// MARK: - FAQ source sheet (C-4)

/// FAQ 溯源 chip 的落点:FAQ 无独立详情路由,就地展示完整问答。溯源卡只带
/// 服务端截断的摘要(答案 80 字),这里用统一 Guide 搜索(scope=faq)按原问题
/// 回捞全文并以 id 匹配;搜不到时退回摘要,绝不空白。
private struct GuideAIFAQSheet: View {
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage
    let source: KaiXGuideAISourceDTO

    @State private var fullAnswer: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    Text(source.title ?? "")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(KXColor.livingInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if isLoading, fullAnswer == nil {
                        HStack(spacing: KXSpacing.sm) {
                            ProgressView()
                            Text(guideText(language, "正在加载…", "読み込み中…", "Loading…"))
                                .font(.footnote)
                                .foregroundStyle(KXColor.livingMuted)
                        }
                    } else {
                        Text(fullAnswer ?? source.subtitle ?? "")
                            .font(.body)
                            .foregroundStyle(KXColor.livingInk)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(KXSpacing.screen)
            }
            .background(KXColor.livingBackground.ignoresSafeArea())
            .navigationTitle(guideText(language, "常见问题", "よくある質問", "FAQ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(guideText(language, "完成", "完了", "Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await loadFullAnswer() }
    }

    private func loadFullAnswer() async {
        defer { isLoading = false }
        guard let question = source.title?.nonEmpty else { return }
        let serverLanguage: String = {
            switch language {
            case .ja: return "ja"
            case .en: return "en"
            default: return "zh-CN"
            }
        }()
        guard let resp = try? await KaiXAPIClient.shared.guideSearch(
                language: serverLanguage, keyword: question, scope: "faq"),
              let faqs = resp.groups.faq, !faqs.isEmpty else { return }
        let match = faqs.first { $0.id == source.kxFaqId } ?? faqs.first
        if let answer = match?.answer.nonEmpty { fullAnswer = answer }
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
    /// 返回删除是否成功;失败时就地弹 alert(根视图 toast 会被 sheet 盖住)。
    let onDelete: (String) async -> Bool
    @State private var showDeleteFailed = false

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
                                Button(role: .destructive) {
                                    Task { if await onDelete(conversation.id) == false { showDeleteFailed = true } }
                                } label: {
                                    Label(guideText(language, "删除", "削除", "Delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(guideText(language, "历史会话", "履歴", "History"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                guideText(language, "删除失败", "削除できませんでした", "Couldn't delete"),
                isPresented: $showDeleteFailed
            ) {
                Button(guideText(language, "好", "OK", "OK"), role: .cancel) {}
            } message: {
                Text(guideText(language, "请检查网络后重试。", "通信状況を確認して再度お試しください。", "Check your connection and try again."))
            }
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

    /// C-4:faq 项无独立详情路由,带 id 时就地弹完整问答 sheet(替代此前
    /// default → nil 造成的 chip 永久禁用)。
    var kxFaqId: String? {
        let kind = (route?.kind ?? type ?? "").lowercased()
        guard kind.contains("faq") else { return nil }
        return route?.id?.nonEmpty
    }

    /// True when tapping the chip leads somewhere (route push or FAQ sheet).
    var kxNavigable: Bool { kxRoute != nil || kxFaqId != nil }

    /// C-4 导购价签(仅 product 项):is_free 优先,其次 price_points;
    /// 旧 payload 两键缺省 → nil,chip 保持原样。
    func kxPriceBadge(_ language: AppLanguage) -> String? {
        let kind = (type ?? route?.kind ?? "").lowercased()
        guard kind.contains("product") else { return nil }
        if is_free == true { return guideText(language, "免费", "無料", "Free") }
        if let points = price_points, points > 0 {
            return guideText(language, "\(points) 币", "\(points) コイン", "\(points) coins")
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
