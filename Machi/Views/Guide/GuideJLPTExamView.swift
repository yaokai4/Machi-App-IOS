import Combine
import SwiftUI
import UIKit

private func jlptResumeAnswerMap(_ answers: [KaiXJLPTExamResumeAnswer]) -> [String: Int] {
    answers.reduce(into: [:]) { result, answer in
        guard let questionId = answer.questionId,
              let selectedIndex = answer.selectedIndex,
              selectedIndex >= 0 else { return }
        result[questionId] = selectedIndex
    }
}

/// 模拟考试 — exam list → timed session (answer each question, per-question saved
/// server-side) → submit → scored breakdown with answers revealed. Also lists
/// past sessions for 回看. Member-only exams surface an upgrade prompt.
///
/// Compliance: original / licensed questions, not official past papers.
struct GuideJLPTExamView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    var initialLevel: JLPTLevel? = nil

    @State private var levelFilterOn: Bool
    @State private var level: JLPTLevel
    @State private var exams: [KaiXJLPTExam] = []
    @State private var history: [KaiXJLPTExamHistoryItem] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var starting: String?
    @State private var upgradeMessage: String?
    /// 非会员类的开考失败(题目缺失/网络/服务端错误)——走中性弹窗,不带会员 CTA。
    @State private var startErrorMessage: String?
    /// Machi 币不足开考——弹窗带「去充值」直达钱包。
    @State private var coinInsufficient = false
    /// 触发余额不足的原始错误，用来读出 requiredCoins/balance 并告诉用户还差多少。
    @State private var coinInsufficientError: KaiXAPIError?
    @State private var showWalletSheet = false
    @State private var pendingStartIntent: JLPTExamStartIntent?

    // active session pushed via navigation
    @State private var activeStart: KaiXJLPTExamStartResponse?
    @State private var activeStartReceipt: JLPTExamStartReceipt?
    @State private var pushSession = false
    // 分科整卷:点父卷进入分段流转。
    @State private var activePaperId: String?
    @State private var pushPaper = false

    init(initialLevel: JLPTLevel? = nil) {
        self.initialLevel = initialLevel
        _levelFilterOn = State(initialValue: initialLevel != nil)
        _level = State(initialValue: initialLevel ?? .n3)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                Toggle(isOn: $levelFilterOn) {
                    Text(guideText(language, "按等级筛选", "レベルで絞り込む", "Filter by level"))
                        .font(.footnote.weight(.semibold)).foregroundStyle(KXColor.livingInk)
                }
                .tint(KXColor.livingAccent)
                .onChange(of: levelFilterOn) { _, _ in Task { await load() } }
                if levelFilterOn {
                    JLPTLevelPicker(selection: $level)
                        .onChange(of: level) { _, _ in Task { await load() } }
                }
                content
            }
            .padding(KXSpacing.lg)
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(guideText(language, "模拟考试", "模擬試験", "Mock exams"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $pushSession) {
            if let start = activeStart, let receipt = activeStartReceipt {
                GuideJLPTExamSessionView(start: start, startReceipt: receipt)
            }
        }
        .navigationDestination(isPresented: $pushPaper) {
            if let pid = activePaperId {
                GuideJLPTPaperFlowView(paperId: pid)
            }
        }
        .task { await load() }
        .alert(guideText(language, "会员专享", "会員限定", "Members only"),
               isPresented: Binding(get: { upgradeMessage != nil }, set: { if !$0 { upgradeMessage = nil } })) {
            Button(guideText(language, "查看会员", "会員を見る", "See membership")) {
                router.open(.guideMemberResources, in: .guide)
            }
            Button(guideText(language, "以后再说", "あとで", "Later"), role: .cancel) {}
        } message: {
            Text(upgradeMessage ?? "")
        }
        .alert(guideText(language, "无法开始考试", "試験を開始できません", "Couldn't start the exam"),
               isPresented: Binding(get: { startErrorMessage != nil }, set: { if !$0 { startErrorMessage = nil } })) {
            Button(guideText(language, "好", "OK", "OK"), role: .cancel) {}
        } message: {
            Text(startErrorMessage ?? "")
        }
        .alert(guideText(language, "Machi 币不足", "Machi コイン不足", "Not enough coins"),
               isPresented: $coinInsufficient) {
            Button(guideText(language, "去充值", "チャージする", "Top up")) { showWalletSheet = true }
            Button(guideText(language, "以后再说", "あとで", "Later"), role: .cancel) {}
        } message: {
            Text(JLPTExamCopy.insufficientCoins(error: coinInsufficientError, language: language))
        }
        .sheet(isPresented: $showWalletSheet) {
            NavigationStack { WalletView() }
        }
        .sheet(item: $pendingStartIntent) { intent in
            JLPTExamStartConfirmationView(
                intent: intent,
                isStarting: starting != nil,
                onConfirm: { Task { await confirmStart(intent) } },
                onWallet: {
                    pendingStartIntent = nil
                    showWalletSheet = true
                },
                onMembership: {
                    pendingStartIntent = nil
                    router.open(.guideMemberResources, in: .guide)
                }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            JLPTStateView(title: guideText(language, "正在加载模考…", "模試を読み込み中…", "Loading exams…"), isLoading: true)
                .frame(minHeight: 320)
        } else if loadFailed {
            JLPTStateView(systemImage: "wifi.slash",
                          title: guideText(language, "加载失败", "読み込みに失敗しました", "Couldn't load"),
                          actionTitle: guideText(language, "重试", "再試行", "Retry"),
                          action: { Task { await load() } })
                .frame(minHeight: 320)
        } else {
            if exams.isEmpty {
                JLPTStateView(systemImage: "doc.text.magnifyingglass",
                              title: guideText(language, "暂无可用模考", "利用可能な模試がありません", "No exams available"),
                              message: guideText(language, "题库补充后即可开考。", "問題が追加されると受験できます。", "Exams open once the bank is filled."))
                    .frame(minHeight: 260)
            } else {
                ForEach(exams) { exam in examRow(exam) }
            }
            if !history.isEmpty {
                JLPTSectionHeader(title: guideText(language, "历史成绩", "受験履歴", "History"))
                    .padding(.top, 6)
                ForEach(history) { item in historyRow(item) }
            }
            JLPTComplianceNote()
        }
    }

    private func examRow(_ exam: KaiXJLPTExam) -> some View {
        Button {
            if exam.isPaper ?? false {
                activePaperId = exam.id
                pushPaper = true
            } else {
                Task { await prepareStart(exam) }
            }
        } label: {
            HStack(spacing: KXSpacing.md) {
                JLPTLevelBadge(level: exam.level ?? "", size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(exam.title ?? "")
                            .font(.subheadline.weight(.bold)).foregroundStyle(KXColor.livingInk)
                        if exam.isMemberOnly ?? false {
                            Image(systemName: "crown.fill").font(.caption2).foregroundStyle(KXColor.livingWarm)
                        }
                    }
                    HStack(spacing: 6) {
                        if (exam.isPaper ?? false), let sc = exam.sectionCount, sc > 0 {
                            examMetaChip(icon: "square.stack.3d.up.fill", text: guideText(language, "分科 \(sc) 科", "分野別 \(sc) 科", "\(sc) sections"))
                        }
                        examMetaChip(icon: "list.number", text: "\(exam.questionCount ?? 0)")
                        if (exam.durationSeconds ?? 0) > 0 {
                            examMetaChip(icon: "clock", text: minuteText(exam.durationSeconds ?? 0))
                        }
                        if (exam.isPaper ?? false) || exam.scoreMode == "jlpt_scaled" {
                            // 全真卷/分科卷:JLPT 官方计分结构出缩放分,不适用 0-100 合格线。
                            examMetaChip(icon: "chart.bar.fill", text: guideText(language, "JLPT 标准出分", "JLPT 準拠採点", "JLPT-style scoring"))
                        } else {
                            examMetaChip(icon: "checkmark.seal", text: guideText(language, "合格 \(exam.passScore ?? 60)", "合格 \(exam.passScore ?? 60)", "≥\(exam.passScore ?? 60)"))
                        }
                        if let cost = exam.coinCost, cost > 0 {
                            coinChip(cost: cost, member: exam.coinCostMember)
                        }
                    }
                }
                Spacer(minLength: 0)
                if starting == exam.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.onAccent)
                        .frame(width: 34, height: 34)
                        .background(KXColor.livingAccent, in: Circle())
                        .shadow(color: KXColor.livingAccent.opacity(0.24), radius: 6, y: 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .jlptSurface(radius: KXRadius.hero)
        }
        .buttonStyle(KXPressableStyle(scale: 0.98))
        .disabled(starting != nil)
    }

    private func examMetaChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).kxScaledFont(9, weight: .bold)
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(KXColor.livingMuted)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(KXColor.livingSoft, in: Capsule())
    }

    /// Machi 币价 chip:开考消耗,琥珀色区别于中性 meta chip;附会员价。
    private func coinChip(cost: Int, member: Int?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "circle.hexagongrid.fill").kxScaledFont(9, weight: .bold)
            Text("\(cost)").font(.caption2.weight(.bold))
            if let member, member < cost {
                Text(guideText(language, "· 会员 \(member)", "· 会員 \(member)", "· Member \(member)"))
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.orange.opacity(0.14), in: Capsule())
    }

    private func historyRow(_ item: KaiXJLPTExamHistoryItem) -> some View {
        // 全真卷显示缩放总分(0-120,按笔试参考线判色);普通卷维持 0-100 百分比。
        let displayScore = item.scaled?.writtenTotal ?? item.score ?? 0
        let displayPassed = item.scaled?.passedWrittenReference ?? item.passed ?? false
        return NavigationLink {
            GuideJLPTExamReviewView(sessionId: item.sessionId, title: item.title ?? "")
        } label: {
            HStack(spacing: KXSpacing.md) {
                // Score chip — passing = accent tile, failing = warm tile.
                Text("\(displayScore)")
                    .kxScaledFont(17, weight: .black, design: .rounded)
                    .foregroundStyle(displayPassed ? KXColor.livingAccent : KXColor.livingWarm)
                    .frame(width: 44, height: 44)
                    .background((displayPassed ? KXColor.livingAccent : KXColor.livingWarm).opacity(0.12), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title ?? item.level ?? "")
                        .font(.subheadline.weight(.bold)).foregroundStyle(KXColor.livingInk)
                    if let scaled = item.scaled {
                        Text(guideText(language, "笔试 \(scaled.writtenTotal ?? 0)/\(scaled.writtenMax ?? 120) · 答对 \(item.correct ?? 0)/\(item.total ?? 0)", "筆記 \(scaled.writtenTotal ?? 0)/\(scaled.writtenMax ?? 120)・正解 \(item.correct ?? 0)/\(item.total ?? 0)", "Written \(scaled.writtenTotal ?? 0)/\(scaled.writtenMax ?? 120) · \(item.correct ?? 0)/\(item.total ?? 0) correct"))
                            .font(.caption2.weight(.medium)).foregroundStyle(KXColor.livingMuted)
                    } else {
                        Text(guideText(language, "\(item.correct ?? 0)/\(item.total ?? 0) 正确", "\(item.correct ?? 0)/\(item.total ?? 0) 正解", "\(item.correct ?? 0)/\(item.total ?? 0) correct"))
                            .font(.caption2.weight(.medium)).foregroundStyle(KXColor.livingMuted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(KXColor.livingMuted)
                    .frame(width: 24, height: 24)
                    .background(KXColor.livingSoft, in: Circle())
            }
            .padding(KXSpacing.md)
            .frame(maxWidth: .infinity)
            .jlptSurface(radius: KXRadius.hero)
        }
        .buttonStyle(KXPressableStyle(scale: 0.98))
    }

    private func minuteText(_ seconds: Int) -> String {
        let m = seconds / 60
        return guideText(language, "\(m) 分钟", "\(m) 分", "\(m) min")
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            async let examsResp = KaiXAPIClient.shared.jlptExams(level: levelFilterOn ? level.rawValue : nil)
            async let historyResp = try? KaiXAPIClient.shared.jlptExamHistory(level: levelFilterOn ? level.rawValue : nil)
            exams = try await examsResp.exams ?? []
            history = await historyResp?.sessions ?? []
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func prepareStart(_ exam: KaiXJLPTExam) async {
        guard starting == nil else { return }
        starting = exam.id
        defer { starting = nil }
        do {
            let preflight = try await KaiXAPIClient.shared.jlptExamPreflight(examId: exam.id)
            pendingStartIntent = JLPTExamStartIntent(preflight: preflight)
        } catch let err as KaiXAPIError {
            // 只有会员/配额类错误才弹「会员专享」+「查看会员」;题目缺失/网络等
            // 通用失败走中性弹窗,否则把无关错误伪装成会员墙、误导用户去买会员。
            let code = err.error.code.lowercased()
            if code == "member_required" || code.contains("quota") {
                upgradeMessage = err.error.message
            } else if code == "exam_insufficient_coins" || code == "insufficient_coins" {
                coinInsufficientError = err
                coinInsufficient = true
            } else if code == "no_questions" {
                startErrorMessage = guideText(language, "该模考暂无可用题目。", "この模試には利用可能な問題がありません。", "This exam has no questions yet.")
            } else {
                startErrorMessage = err.error.message
            }
        } catch {
            startErrorMessage = guideText(language, "无法开始考试，请稍后再试。", "試験を開始できません。", "Couldn't start the exam.")
        }
    }

    private func confirmStart(_ intent: JLPTExamStartIntent) async {
        guard starting == nil else { return }
        starting = intent.examId
        defer { starting = nil }
        do {
            let response = try await KaiXAPIClient.shared.jlptExamStart(
                examId: intent.examId,
                confirmedChargeCoins: intent.confirmedChargeCoins,
                idempotencyKey: intent.idempotencyKey
            )
            pendingStartIntent = nil
            activeStart = response
            activeStartReceipt = JLPTExamStartReceipt(intent: intent)
            pushSession = true
        } catch let error as KaiXAPIError {
            switch JLPTExamRecoveryPolicy.action(for: error) {
            case .refreshPrice:
                do {
                    let refreshed = try await KaiXAPIClient.shared.jlptExamPreflight(
                        examId: intent.examId
                    )
                    pendingStartIntent = intent.refreshing(with: refreshed)
                    startErrorMessage = guideText(language, "价格已更新，请按新价格重新确认。", "価格が更新されました。新しい価格をご確認ください。", "The price changed. Review and confirm the updated charge.")
                } catch {
                    startErrorMessage = guideText(language, "无法刷新价格，请稍后重试。", "価格を更新できません。後でもう一度お試しください。", "Couldn't refresh the price. Try again later.")
                }
            case .openWallet:
                pendingStartIntent = nil
                coinInsufficientError = error
                coinInsufficient = true
            case .openMembership:
                pendingStartIntent = nil
                upgradeMessage = error.error.message
            default:
                startErrorMessage = error.error.message
            }
        } catch {
            startErrorMessage = guideText(language, "无法开始考试，请稍后再试。", "試験を開始できません。", "Couldn't start the exam.")
        }
    }
}

/// Authoritative server price/access confirmation shared by standalone exams
/// and full-paper sections. The app never starts or charges from list metadata.
private struct JLPTExamStartConfirmationView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    let intent: JLPTExamStartIntent
    let isStarting: Bool
    let onConfirm: () -> Void
    let onWallet: () -> Void
    let onMembership: () -> Void

    private var preflight: KaiXJLPTExamPreflight { intent.preflight }
    private var needsWallet: Bool { !preflight.canStart && preflight.shortfall > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    VStack(alignment: .leading, spacing: 8) {
                        JLPTEyebrow(text: guideText(language, "开考确认", "受験確認", "Start confirmation"))
                        Text(JLPTExamCopy.startConfirmation(preflight: preflight, language: language))
                            .kxScaledFont(20, relativeTo: .title3, weight: .bold, design: .rounded)
                            .foregroundStyle(KXColor.livingInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 0) {
                        confirmationRow(
                            title: guideText(language, "本次扣除", "今回の消費", "Charge now"),
                            value: preflight.requiredCoins == 0
                                ? guideText(language, "免费 / 已解锁", "無料 / 解除済み", "Free / unlocked")
                                : "\(preflight.requiredCoins) Machi Coins"
                        )
                        Divider().padding(.leading, KXSpacing.md)
                        confirmationRow(
                            title: guideText(language, "当前余额", "現在の残高", "Current balance"),
                            value: "\(preflight.balance)"
                        )
                        Divider().padding(.leading, KXSpacing.md)
                        confirmationRow(
                            title: guideText(language, "会员价", "会員価格", "Member price"),
                            value: "\(preflight.memberCoinCost)"
                        )
                        if preflight.shortfall > 0 {
                            Divider().padding(.leading, KXSpacing.md)
                            confirmationRow(
                                title: guideText(language, "还差", "不足", "Shortfall"),
                                value: "\(preflight.shortfall)",
                                valueColor: KXColor.livingWarm
                            )
                        }
                    }
                    .jlptSurface(radius: KXRadius.lg)

                    if preflight.oneTimePaperPayment {
                        Label(
                            guideText(language, "本次为整卷一次性扣款；后续科目不会重复扣款。", "全科目分を一度だけ消費し、後続科目では再度消費しません。", "This is a one-time charge for the full paper; later sections are not charged again."),
                            systemImage: "checkmark.shield.fill"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KXColor.livingAccent)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(guideText(language, "退款与异常处理", "返金・エラー対応", "Refunds and failed starts"))
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(KXColor.livingInk)
                        Text(JLPTExamCopy.refundPolicy(language: language))
                            .font(.footnote)
                            .foregroundStyle(KXColor.livingMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !preflight.disclaimer.isEmpty {
                        JLPTComplianceNote(text: preflight.disclaimer)
                    }

                    Button {
                        if preflight.canStart { onConfirm() }
                        else if needsWallet { onWallet() }
                        else { onMembership() }
                    } label: {
                        HStack {
                            if isStarting { ProgressView().controlSize(.small) }
                            Text(preflight.canStart
                                ? guideText(language, "确认并开始", "確認して開始", "Confirm and start")
                                : needsWallet
                                    ? guideText(language, "去充值", "チャージする", "Top up")
                                    : guideText(language, "查看会员方案", "会員プランを見る", "View membership"))
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(KXColor.onTint(KXColor.livingAccent))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(KXColor.livingAccent, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    }
                    .buttonStyle(KXPressableStyle(scale: 0.98))
                    .disabled(isStarting)
                }
                .padding(KXSpacing.lg)
            }
            .background(KXColor.livingBackground.ignoresSafeArea())
            .navigationTitle(guideText(language, "开考确认", "受験確認", "Start confirmation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(guideText(language, "取消", "キャンセル", "Cancel")) { dismiss() }
                        .disabled(isStarting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isStarting)
    }

    private func confirmationRow(
        title: String,
        value: String,
        valueColor: Color = KXColor.livingInk
    ) -> some View {
        HStack {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(KXColor.livingMuted)
            Spacer()
            Text(value).font(.footnote.weight(.bold)).foregroundStyle(valueColor)
        }
        .padding(KXSpacing.md)
    }
}

enum JLPTExamSessionContentState: Equatable {
    case empty
    case result
    case timeUp
    case answering
    case submitting

    static func resolve(
        questionCount: Int,
        cursor: Int,
        timedOut: Bool,
        submitting: Bool,
        hasResult: Bool
    ) -> Self {
        if hasResult { return .result }
        if questionCount <= 0 { return .empty }
        if submitting { return .submitting }
        if timedOut { return .timeUp }
        if cursor < questionCount { return .answering }
        return .submitting
    }
}

struct JLPTExamSessionPresentationState: Equatable {
    var leaveConfirmationPresented = false
    var unsyncedConfirmationPresented = false
    var answerSheetPresented = false

    mutating func beginSubmitting() {
        leaveConfirmationPresented = false
        unsyncedConfirmationPresented = false
        answerSheetPresented = false
    }
}

enum JLPTExamSessionInteractionPolicy {
    static func shouldGuardExit(
        questionCount: Int,
        answerCount: Int,
        submitting: Bool,
        hasResult: Bool
    ) -> Bool {
        guard !hasResult, questionCount > 0 else { return false }
        return submitting || answerCount > 0
    }

    static func canExit(submitting: Bool) -> Bool {
        !submitting
    }
}

/// A live, optionally-timed exam session. Every tap is first persisted in the
/// local outbox, then saved server-side in revision order. Submit sends the full
/// ordered answer snapshot and replaces the session with its result.
struct GuideJLPTExamSessionView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let start: KaiXJLPTExamStartResponse
    let startReceipt: JLPTExamStartReceipt
    /// 分科整卷模式:交卷后回调让父卷流转推进到下一科/合并成绩。
    /// 单卷模式(默认 nil)则在当前页面用结果内容替换答题内容。
    var onSectionSubmitted: ((KaiXJLPTExamResult) -> Void)? = nil
    var onRecovery: ((JLPTExamRecoveryAction) -> Void)? = nil

    @StateObject private var answerSaver: JLPTExamAnswerSaveCoordinator

    @State private var cursor = 0
    @State private var answers: [String: Int] = [:]   // questionId -> selected
    @State private var remaining: Int = 0
    /// 倒计时的绝对锚点。此前用「每秒 -1」的本地 tick,主 RunLoop Timer 在后台
    /// 挂起即暂停,切后台查词典可无限延时;现在每个 tick 都从 deadline 重算。
    @State private var deadline: Date?
    @State private var timedOut = false
    @State private var submitting = false
    @State private var submitFailed = false
    @State private var submitErrorMessage: String?
    @State private var result: KaiXJLPTExamResult?
    /// 交卷边界仍在本地 outbox 的题数。仅当服务端明确返回截止且拒收快照时，
    /// 结果页才据此提示这些答案可能未计入；不能提前声称已保存或必定按未答判分。
    @State private var unsyncedAtSubmit = 0
    /// 退出确认、未同步确认和答题卡都是覆盖在会话之上的遗留交互层；
    /// 进入提交态时必须在同一个 MainActor 转换中一起关闭。
    @State private var presentation = JLPTExamSessionPresentationState()
    /// B15-D 中断恢复:服务端在 start 返回了未完成的旧会话时,把已答题灌回本地
    /// 并提示用户。只在首次 onAppear 执行,避免返回本页时覆盖更新的本地作答。
    @State private var didRestoreResumed = false
    @State private var showResumedNotice = false

    init(
        start: KaiXJLPTExamStartResponse,
        startReceipt: JLPTExamStartReceipt,
        onSectionSubmitted: ((KaiXJLPTExamResult) -> Void)? = nil,
        onRecovery: ((JLPTExamRecoveryAction) -> Void)? = nil
    ) {
        self.start = start
        self.startReceipt = startReceipt
        self.onSectionSubmitted = onSectionSubmitted
        self.onRecovery = onRecovery
        let sessionId = start.sessionId ?? "invalid-session"
        let serverAnswers = jlptResumeAnswerMap(start.answers ?? [])
        let coordinator = JLPTExamAnswerSaveCoordinator(
            sessionId: sessionId,
            serverAnswers: serverAnswers,
            answerRevision: start.answerRevision ?? 0
        ) { request in
            try await KaiXAPIClient.shared.jlptExamAnswer(request)
        }
        _answerSaver = StateObject(wrappedValue: coordinator)
        _answers = State(initialValue: coordinator.currentAnswers)
        if let questions = start.questions, !questions.isEmpty {
            _cursor = State(initialValue:
                questions.firstIndex(where: { coordinator.currentAnswers[$0.id] == nil })
                    ?? (questions.count - 1)
            )
        }
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var questions: [KaiXJLPTQuestionDTO] { start.questions ?? [] }
    private var isTimed: Bool { (start.durationSeconds ?? 0) > 0 }
    private var listeningPolicy: JLPTListeningRuntimePolicy {
        JLPTListeningRuntimePolicy.resolve(
            serverPolicy: start.listeningPolicy,
            context: isTimed ? .liveTimedExam : .nonExam
        )
    }
    private var unsavedAnswers: Set<String> { answerSaver.unsavedQuestionIDs }
    private var contentState: JLPTExamSessionContentState {
        .resolve(
            questionCount: questions.count,
            cursor: cursor,
            timedOut: timedOut,
            submitting: submitting,
            hasResult: result != nil
        )
    }
    /// 已作答且未出分时,一次误滑/误点返回会静默丢弃整场考试(无续考入口),
    /// 所以此时必须拦截返回并弹确认。
    private var shouldGuardExit: Bool {
        JLPTExamSessionInteractionPolicy.shouldGuardExit(
            questionCount: questions.count,
            answerCount: answers.count,
            submitting: submitting,
            hasResult: result != nil
        )
    }

    var body: some View {
        sessionContent
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(contentState == .result
                         ? guideText(language, "考试结果", "試験結果", "Result")
                         : start.title ?? guideText(language, "模拟考试", "模擬試験", "Mock exam"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            restoreResumedSessionIfNeeded()
            if isTimed, deadline == nil {
                // 恢复的会话用服务端算出的剩余秒数锚定 deadline(服务端是计时
                // 权威,杀进程重开不再满时重来);全新会话仍用满时长。
                let full = start.durationSeconds ?? 0
                let seconds = (start.resumed ?? false)
                    ? min(max(0, start.remainingSeconds ?? full), full)
                    : full
                deadline = Date().addingTimeInterval(TimeInterval(seconds))
            }
            syncClock()
        }
        .onReceive(timer) { _ in syncClock() }
        // 回前台立即按真实流逝时间重算,而不是等下一个 tick。
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { syncClock() }
        }
        // 系统返回按钮 + 边滑手势都要拦:KXSwipeBackEnabler 全局放开了 pop 手势,
        // 单靠 navigationBarBackButtonHidden 挡不住误滑。
        .navigationBarBackButtonHidden(shouldGuardExit)
        .background(KXExamPopGestureBlocker(blocked: shouldGuardExit))
        .toolbar {
            if shouldGuardExit {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        guard JLPTExamSessionInteractionPolicy.canExit(submitting: submitting) else { return }
                        presentation.leaveConfirmationPresented = true
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(guideText(language, "返回", "戻る", "Back"))
                    .disabled(submitting)
                }
            }
        }
        .confirmationDialog(
            guideText(language, "退出考试？", "試験を終了しますか？", "Leave the exam?"),
            isPresented: $presentation.leaveConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(guideText(language, "退出（可稍后继续）", "終了（あとで再開できます）", "Leave (you can resume)"), role: .destructive) {
                guard JLPTExamSessionInteractionPolicy.canExit(submitting: submitting) else { return }
                dismiss()
            }
            Button(guideText(language, "继续作答", "回答を続ける", "Keep going"), role: .cancel) {}
        } message: {
            Text(JLPTExamCopy.exitMessage(
                isTimed: isTimed,
                pendingAnswerCount: unsavedAnswers.count,
                language: language
            ))
        }
        .sheet(isPresented: $presentation.answerSheetPresented) {
            JLPTAnswerSheetView(
                questions: questions,
                answers: answers,
                current: cursor,
                onJump: { idx in
                    guard !submitting else { return }
                    cursor = idx
                    presentation.answerSheetPresented = false
                },
                onSubmit: {
                    submit()
                }
            )
            .disabled(submitting)
            .allowsHitTesting(!submitting)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch contentState {
        case .result:
            if let result {
                GuideJLPTExamResultView(
                    result: result,
                    unsyncedCount: unsyncedAtSubmit,
                    onExit: { dismiss() }
                )
            }
        case .empty:
            ScrollView {
                JLPTStateView(systemImage: "tray", title: guideText(language, "本卷暂无题目", "問題がありません", "No questions"))
            }
        case .timeUp:
            ScrollView {
                // Time's up: show a reachable submit/retry state instead of
                // leaving the user stranded on whatever question they were on
                // with a frozen 0:00 clock and the only Submit button hidden on
                // the last page.
                timeUpState
            }
        case .answering:
            ScrollView {
                sessionBody
            }
        case .submitting:
            ScrollView {
                JLPTStateView(title: guideText(language, "正在交卷…", "採点中…", "Submitting…"), isLoading: true)
            }
        }
    }

    /// B15-D:start 返回 resumed 时把服务端已保存的作答灌回本地状态,并把光标
    /// 移到第一道未答题。这些答案本就在服务端,不进 unsavedAnswers 重发队列。
    private func restoreResumedSessionIfNeeded() {
        guard !didRestoreResumed else { return }
        didRestoreResumed = true
        answers = answerSaver.currentAnswers
        guard (start.resumed ?? false) || !answers.isEmpty else { return }
        if !questions.isEmpty {
            cursor = questions.firstIndex(where: { answers[$0.id] == nil }) ?? (questions.count - 1)
        }
        showResumedNotice = true
    }

    /// 以 deadline 为锚重算剩余时间；归零时立即提交完整快照。服务端零宽限，
    /// 是否接收快照只由 deadlineExpired / snapshotAccepted 结果决定。
    private func syncClock() {
        guard isTimed, !timedOut, result == nil, let deadline else { return }
        remaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
        if remaining <= 0, !submitting {
            timedOut = true
            submit()
        }
    }

    @ViewBuilder
    private var sessionBody: some View {
        let q = questions[cursor]
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            if showResumedNotice {
                resumedNotice
            }
            HStack(spacing: 10) {
                ProgressView(value: Double(cursor), total: Double(max(1, questions.count)))
                    .tint(KXColor.livingAccent)
                Text("\(cursor + 1)/\(questions.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(KXColor.livingMuted)
                // 全真卷按科目顺序组卷:当前科目常驻可见,考生随时知道自己在
                // 「文字·語彙 / 文法 / 読解」的哪一段。
                if let sectionLabel = q.sectionLabel, !sectionLabel.isEmpty {
                    Text(sectionLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(KXColor.livingAccentSoft, in: Capsule())
                        .lineLimit(1)
                }
                Button {
                    presentation.answerSheetPresented = true
                } label: {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                        .frame(width: 28, height: 28)
                        .background(KXColor.livingAccentSoft, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(guideText(language, "答题卡", "解答一覧", "Answer sheet"))
                if isTimed {
                    let urgent = remaining <= 60
                    Label(clockText, systemImage: "clock.fill")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(urgent ? .red : KXColor.livingAccent)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background((urgent ? Color.red : KXColor.livingAccent).opacity(0.12), in: Capsule())
                }
            }

            JLPTQuestionCard(
                question: q,
                index: cursor,
                total: questions.count,
                selectedIndex: Binding(
                    get: { answers[q.id] },
                    set: { newValue in
                        guard let v = newValue, !submitting else { return }
                        guard answerSaver.enqueue(questionId: q.id, selectedIndex: v) else { return }
                        answers[q.id] = v
                    }
                ),
                revealed: false,
                correctIndex: nil,
                explanation: nil,
                listeningPolicy: listeningPolicy,
                playbackIdentity: JLPTListeningPlaybackIdentity(
                    sessionId: start.sessionId ?? "",
                    questionId: q.id
                )
            )
            .disabled(submitting)

            HStack(spacing: 10) {
                if cursor > 0 {
                    Button(action: { cursor -= 1 }) {
                        Image(systemName: "chevron.left")
                        Text(guideText(language, "上一题", "前へ", "Prev")).font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KXColor.livingAccent)
                    .padding(.horizontal, KXSpacing.lg).padding(.vertical, 11)
                    .background(KXColor.livingAccentSoft, in: Capsule())
                }
                Spacer(minLength: 0)
                if cursor + 1 < questions.count {
                    Button(action: { cursor += 1 }) {
                        Text(guideText(language, "下一题", "次へ", "Next")).font(.subheadline.weight(.bold))
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KXColor.onTint(KXColor.livingAccent))
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(KXColor.livingAccent, in: Capsule())
                } else {
                    Button(action: { submit() }) {
                        HStack {
                            if submitting { ProgressView().controlSize(.small).tint(KXColor.onTint(KXColor.livingAccent)) }
                            Text(guideText(language, "交卷", "提出", "Submit")).font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(KXColor.onTint(KXColor.livingAccent))
                        .padding(.horizontal, KXSpacing.xl).padding(.vertical, 11)
                        .background(KXColor.livingAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(submitting)
                }
            }

            if submitFailed {
                Text(submitErrorMessage ?? guideText(language, "交卷失败,请检查网络后重试。", "提出に失敗しました。接続を確認して再試行してください。", "Submit failed — check your connection and try again."))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            JLPTComplianceNote()
        }
        .padding(KXSpacing.lg)
    }

    /// 轻量续考提示——恢复旧会话时展示,数秒后自动淡出,也可手动关闭。
    private var resumedNotice: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: "arrow.uturn.forward.circle.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(KXColor.livingAccent)
            Text(guideText(language, "已恢复上次未完成的考试", "前回の未完了の試験を再開しました", "Resumed your unfinished exam"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KXColor.livingInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                withAnimation { showResumedNotice = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(KXColor.livingMuted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(guideText(language, "关闭提示", "閉じる", "Dismiss"))
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .transition(.opacity)
        .task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            withAnimation { showResumedNotice = false }
        }
    }

    /// Shown once the clock hits 0:00. Auto-submit runs; if it fails the user
    /// gets a reachable "submit again" button that doesn't depend on paging to
    /// the last question.
    @ViewBuilder
    private var timeUpState: some View {
        if submitting {
            JLPTStateView(title: guideText(language, "时间到,正在交卷…", "時間切れ、採点中…", "Time's up — submitting…"), isLoading: true)
        } else {
            JLPTStateView(
                systemImage: "clock.badge.exclamationmark",
                title: guideText(language, "时间到", "時間切れ", "Time's up"),
                message: submitFailed
                    ? guideText(language, "交卷失败,请检查网络后重试。", "提出に失敗しました。接続を確認して再試行してください。", "Submit failed — check your connection and try again.")
                    : guideText(language, "正在为你交卷…", "採点を準備しています…", "Preparing your results…"),
                actionTitle: guideText(language, "重新交卷", "もう一度提出", "Submit again"),
                action: { submit() }
            )
        }
    }

    private var clockText: String {
        let m = remaining / 60, s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Synchronous MainActor entry: lock interaction and dismiss every legacy
    /// presentation before any answer flush or grading await can yield.
    private func submit() {
        guard let sid = start.sessionId, !submitting, result == nil else { return }
        submitting = true
        presentation.beginSubmitting()
        submitFailed = false
        submitErrorMessage = nil

        Task { await finishSubmit(sessionId: sid) }
    }

    private func finishSubmit(sessionId sid: String) async {
        let unsavedAfterFlush = await answerSaver.sealAndFlush()
        do {
            unsyncedAtSubmit = unsavedAfterFlush.count
            let baseRevision = answerSaver.authoritativeRevision
            let submission = KaiXJLPTExamSubmitRequest(
                sessionId: sid,
                answersSnapshot: answerSaver.orderedSnapshot(questionIDs: questions.map(\.id)),
                baseRevision: baseRevision,
                revision: baseRevision + 1
            )
            let r = try await KaiXAPIClient.shared.jlptExamSubmit(submission)
            result = r
            answerSaver.clearDraft()
            // 分科模式:交卷后回调让父卷推进;单卷模式由 result 替换答题内容。
            if let onSectionSubmitted {
                onSectionSubmitted(r)
            }
        } catch let error as KaiXAPIError {
            answerSaver.reopen()
            let action = JLPTExamRecoveryPolicy.action(for: error)
            switch action {
            case .restoreAnswers:
                await restoreAuthoritativeSession()
            case .restorePaper, .showPaperResult:
                // 整卷类恢复一律冒泡给父卷处理：子会话不知道整卷的阶段状态。
                onRecovery?(action)
            case .openWallet:
                submitErrorMessage = JLPTExamCopy.insufficientCoins(error: error, language: language)
                submitFailed = true
            case .openMembership:
                submitErrorMessage = guideText(language, "当前权限不足，请返回后查看会员方案。", "受験権限がありません。戻って会員プランをご確認ください。", "This exam requires membership access. Return to review the available plan.")
                submitFailed = true
            case .refreshPrice, .retry:
                submitErrorMessage = error.error.message
                submitFailed = true
            }
        } catch {
            // Leave the session open and surface the failure so a timed-out
            // auto-submit doesn't look like a frozen exam with no way forward.
            answerSaver.reopen()
            submitFailed = true
            submitErrorMessage = guideText(language, "交卷失败,请检查网络后重试。", "提出に失敗しました。接続を確認して再試行してください。", "Submit failed — check your connection and try again.")
        }
        submitting = false
    }

    private func restoreAuthoritativeSession() async {
        guard let sessionId = start.sessionId, !sessionId.isEmpty else {
            markRecoveryIdentityFailure()
            return
        }
        do {
            let preflight = try await KaiXAPIClient.shared.jlptExamPreflight(
                examId: startReceipt.examId
            )
            guard JLPTExamResumeIdentityPolicy.acceptsPreflight(
                receipt: startReceipt,
                expectedSessionId: sessionId,
                resumeSessionId: preflight.resumeSessionId,
                preflightExamId: preflight.examId,
                requiredCoins: preflight.requiredCoins
            ) else {
                markRecoveryIdentityFailure()
                return
            }
            let restored = try await KaiXAPIClient.shared.jlptExamStart(
                examId: startReceipt.examId,
                confirmedChargeCoins: startReceipt.confirmedChargeCoins,
                idempotencyKey: startReceipt.idempotencyKey
            )
            guard JLPTExamResumeIdentityPolicy.acceptsResponse(
                receipt: startReceipt,
                expectedSessionId: sessionId,
                expectedQuestionIDs: questions.map(\.id),
                responseSessionId: restored.sessionId,
                responseExamId: restored.examId,
                resumed: restored.resumed,
                responseQuestionIDs: restored.questions?.map(\.id)
            ) else {
                markRecoveryIdentityFailure()
                return
            }
            let serverAnswers = jlptResumeAnswerMap(restored.answers ?? [])
            answerSaver.mergeAuthoritative(
                serverAnswers: serverAnswers,
                answerRevision: restored.answerRevision ?? 0
            )
            answers = answerSaver.currentAnswers
            cursor = questions.firstIndex(where: { answers[$0.id] == nil })
                ?? max(0, questions.count - 1)
            showResumedNotice = true
            submitErrorMessage = guideText(language, "已按服务器进度恢复，请确认答案后重新交卷。", "サーバーの進捗から復元しました。回答を確認して再提出してください。", "Server progress was restored. Review your answers, then submit again.")
            submitFailed = true
        } catch {
            submitErrorMessage = guideText(language, "无法恢复服务器进度，请返回后重新进入考试。", "サーバーの進捗を復元できません。戻って試験に入り直してください。", "Couldn't restore server progress. Leave and re-enter the exam.")
            submitFailed = true
        }
    }

    private func markRecoveryIdentityFailure() {
        submitErrorMessage = guideText(
            language,
            "服务器返回的考试身份与当前会话不一致。为避免新建或重复扣费，本次未合并答案；请退出后重新进入原考试。",
            "サーバーの試験情報が現在のセッションと一致しません。新規受験や二重課金を防ぐため回答は統合していません。終了して元の試験に入り直してください。",
            "The server returned a different exam session. No answers were merged, preventing a new attempt or duplicate charge. Leave and re-enter the original exam."
        )
        submitFailed = true
    }
}

/// Parent-paper flow. The server-owned attempt decides the active section and
/// supports both the N1/N2 two-section shape and the N3/N4/N5 three-section shape.
struct GuideJLPTPaperFlowView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    let paperId: String

    @State private var detail: KaiXJLPTPaperDetail?
    @State private var isLoading = true
    @State private var loadFailed = false
    private enum Phase { case intro, section, betweenBreak, result }
    @State private var phase: Phase = .intro
    @State private var idx = 0
    @State private var activeStart: KaiXJLPTExamStartResponse?
    @State private var activeStartReceipt: JLPTExamStartReceipt?
    @State private var paperAttempt: KaiXJLPTPaperAttempt?
    @State private var attemptId = ""
    @State private var pendingStartIntent: JLPTExamStartIntent?
    @State private var starting = false
    @State private var startError: String?
    @State private var coinInsufficient = false
    /// 触发余额不足的原始错误，用来读出 requiredCoins/balance 并告诉用户还差多少。
    @State private var coinInsufficientError: KaiXAPIError?
    @State private var showWalletSheet = false

    private var sections: [KaiXJLPTExam] { detail?.sections ?? [] }
    private var sectionIDs: [String] { sections.map(\.id) }

    private func minutes(_ seconds: Int) -> String {
        guideText(language, "\(seconds / 60) 分钟", "\(seconds / 60) 分", "\(seconds / 60) min")
    }

    var body: some View {
        Group {
            if phase == .section, let start = activeStart, let receipt = activeStartReceipt {
                GuideJLPTExamSessionView(
                    start: start,
                    startReceipt: receipt,
                    onSectionSubmitted: applySubmittedSection,
                    onRecovery: applyRecovery
                )
            } else if phase == .result {
                GuideJLPTPaperResultView(
                    paperId: paperId,
                    attemptId: attemptId,
                    onExit: { dismiss() }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: KXSpacing.lg) {
                        if isLoading {
                            JLPTStateView(title: guideText(language, "正在加载…", "読み込み中…", "Loading…"), isLoading: true)
                                .frame(minHeight: 320)
                        } else if loadFailed || detail == nil {
                            JLPTStateView(systemImage: "wifi.slash",
                                          title: guideText(language, "加载失败", "読み込みに失敗しました", "Couldn't load"),
                                          actionTitle: guideText(language, "重试", "再試行", "Retry"),
                                          action: { Task { await load() } })
                                .frame(minHeight: 320)
                        } else if phase == .intro {
                            intro
                        } else {
                            betweenBreak
                        }
                    }
                    .padding(KXSpacing.lg)
                }
                .background(KXColor.livingBackground.ignoresSafeArea())
            }
        }
        .navigationTitle(detail?.paper.title ?? guideText(language, "全真模考", "本番形式模試", "Full mock exam"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(guideText(language, "无法开始科目", "科目を開始できません", "Couldn't start section"),
               isPresented: Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })) {
            Button(guideText(language, "好", "OK", "OK"), role: .cancel) {}
        } message: { Text(startError ?? "") }
        .alert(guideText(language, "Machi 币不足", "Machi コイン不足", "Not enough coins"),
               isPresented: $coinInsufficient) {
            Button(guideText(language, "去充值", "チャージする", "Top up")) { showWalletSheet = true }
            Button(guideText(language, "以后再说", "あとで", "Later"), role: .cancel) {}
        } message: {
            Text(JLPTExamCopy.insufficientCoins(error: coinInsufficientError, language: language))
        }
        .sheet(isPresented: $showWalletSheet) {
            NavigationStack { WalletView() }
        }
        .sheet(item: $pendingStartIntent) { intent in
            JLPTExamStartConfirmationView(
                intent: intent,
                isStarting: starting,
                onConfirm: { Task { await confirmSectionStart(intent) } },
                onWallet: {
                    pendingStartIntent = nil
                    showWalletSheet = true
                },
                onMembership: {
                    pendingStartIntent = nil
                    router.open(.guideMemberResources, in: .guide)
                }
            )
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                JLPTEyebrow(text: "JLPT · \(detail?.paper.level ?? "")")
                Text(detail?.paper.title ?? "")
                    .kxScaledFont(22, relativeTo: .title3, weight: .bold, design: .rounded)
                    .foregroundStyle(KXColor.livingInk)
                Text(JLPTExamCopy.paperStructure(sectionCount: sections.count, language: language))
                    .font(.footnote).foregroundStyle(KXColor.livingMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { i, section in
                    HStack(spacing: KXSpacing.md) {
                        Text("\(i + 1)")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(KXColor.livingAccent)
                            .frame(width: 34, height: 34)
                            .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(section.title ?? section.sectionLabel ?? "")
                                .font(.subheadline.weight(.bold)).foregroundStyle(KXColor.livingInk)
                            Text("\(section.questionCount ?? 0) \(guideText(language, "题", "問", "Q")) · \(minutes(section.durationSeconds ?? 0))"
                                 + ((section.section == "listening") ? " · " + guideText(language, "含听力音频", "音声あり", "with audio") : ""))
                                .font(.caption2.weight(.medium)).foregroundStyle(KXColor.livingMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .jlptSurface(radius: KXRadius.lg)
                }
            }
            startButton(title: attemptId.isEmpty
                ? guideText(language, "检查价格并开始", "価格を確認して開始", "Check price and start")
                : guideText(language, "恢复当前科目", "現在の科目を再開", "Resume current section")) {
                Task { await prepareSectionStart(requestedExamId: detail?.paper.id ?? paperId) }
            }
            JLPTComplianceNote(text: detail?.disclaimer)
        }
    }

    private var betweenBreak: some View {
        let current = sections.indices.contains(idx) ? sections[idx] : nil
        return VStack(alignment: .leading, spacing: KXSpacing.lg) {
            JLPTEyebrow(text: detail?.paper.title ?? "")
            VStack(spacing: 12) {
                Text(guideText(language, "第 \(idx + 1) / \(sections.count) 科", "\(idx + 1) / \(sections.count) 科目", "Section \(idx + 1) / \(sections.count)"))
                    .font(.caption.weight(.bold)).foregroundStyle(KXColor.livingAccent)
                Text(current?.title ?? "")
                    .kxScaledFont(20, relativeTo: .title3, weight: .bold, design: .rounded)
                    .foregroundStyle(KXColor.livingInk)
                Text(current?.section == "listening"
                     ? JLPTExamCopy.listeningHint(language: language)
                     : "\(current?.questionCount ?? 0) \(guideText(language, "题", "問", "Q")) · \(minutes(current?.durationSeconds ?? 0))")
                    .font(.footnote.weight(.medium)).foregroundStyle(KXColor.livingMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                startButton(title: guideText(language, "检查并开始本科目", "確認してこの科目を開始", "Check and start this section")) {
                    guard let current else { return }
                    Task { await prepareSectionStart(requestedExamId: current.id) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .jlptSurface(radius: KXRadius.sheet, elevated: true)
            JLPTComplianceNote(text: detail?.disclaimer)
        }
    }

    private func startButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: KXSpacing.sm) {
                if starting { ProgressView().controlSize(.small).tint(KXColor.onTint(KXColor.livingAccent)) }
                Image(systemName: "graduationcap.fill")
                Text(title).font(.subheadline.weight(.bold))
            }
            .foregroundStyle(KXColor.onTint(KXColor.livingAccent))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(KXColor.livingAccent, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .shadow(color: KXColor.livingAccent.opacity(0.24), radius: 10, y: 4)
        }
        .buttonStyle(KXPressableStyle(scale: 0.98))
        .disabled(starting || sections.isEmpty)
    }

    private func prepareSectionStart(
        requestedExamId: String,
        retaining idempotencyKey: String? = nil
    ) async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        do {
            let preflight = try await KaiXAPIClient.shared.jlptExamPreflight(examId: requestedExamId)
            configureStartIntent(
                from: preflight,
                requestedExamId: requestedExamId,
                idempotencyKey: idempotencyKey
            )
        } catch let error as KaiXAPIError {
            handleStartError(error)
        } catch {
            startError = guideText(language, "无法读取当前科目与价格，请稍后再试。", "現在の科目と価格を取得できません。", "Couldn't load the current section and price.")
        }
    }

    private func configureStartIntent(
        from preflight: KaiXJLPTExamPreflight,
        requestedExamId: String,
        idempotencyKey: String?
    ) {
        let progress = preflight.paperAttempt
        if let progress {
            paperAttempt = progress
            attemptId = progress.id
            if progress.status.lowercased() == "completed" {
                pendingStartIntent = nil
                phase = .result
                return
            }
        }
        let resolvedIndex = JLPTPaperProgressResolver.index(
            sectionExamIDs: sectionIDs,
            currentSectionExamId: progress?.currentSectionExamId ?? preflight.currentSectionExamId,
            currentSectionIndex: progress?.currentSectionIndex ?? 0
        )
        idx = resolvedIndex
        let target = sections.indices.contains(resolvedIndex)
            ? sections[resolvedIndex]
            : sections.first(where: { $0.id == requestedExamId })
        guard let target else {
            startError = guideText(language, "服务器返回的当前科目不在本卷中。", "サーバーの現在科目がこの模試にありません。", "The server's current section is not part of this paper.")
            return
        }
        if let idempotencyKey {
            pendingStartIntent = JLPTExamStartIntent(
                preflight: preflight,
                examId: target.id,
                idempotencyKey: idempotencyKey
            )
        } else {
            pendingStartIntent = JLPTExamStartIntent(preflight: preflight, examId: target.id)
        }
    }

    private func confirmSectionStart(_ intent: JLPTExamStartIntent) async {
        guard !starting else { return }
        starting = true
        defer { starting = false }
        do {
            let response = try await KaiXAPIClient.shared.jlptExamStart(
                examId: intent.examId,
                confirmedChargeCoins: intent.confirmedChargeCoins,
                idempotencyKey: intent.idempotencyKey
            )
            if let progress = response.paperAttempt {
                paperAttempt = progress
                attemptId = progress.id
                idx = JLPTPaperProgressResolver.index(
                    sectionExamIDs: sectionIDs,
                    currentSectionExamId: progress.currentSectionExamId,
                    currentSectionIndex: progress.currentSectionIndex
                )
            } else if let matched = sectionIDs.firstIndex(of: intent.examId) {
                idx = matched
            }
            pendingStartIntent = nil
            activeStart = response
            activeStartReceipt = JLPTExamStartReceipt(intent: intent)
            phase = .section
        } catch let error as KaiXAPIError {
            let action = JLPTExamRecoveryPolicy.action(for: error)
            switch action {
            case .refreshPrice, .restorePaper:
                do {
                    let refreshed = try await KaiXAPIClient.shared.jlptExamPreflight(examId: intent.examId)
                    configureStartIntent(
                        from: refreshed,
                        requestedExamId: intent.examId,
                        idempotencyKey: intent.idempotencyKey
                    )
                    startError = guideText(language, "考试状态已更新，请重新确认当前科目与价格。", "試験状態が更新されました。現在の科目と価格をご確認ください。", "Exam state changed. Confirm the refreshed section and price.")
                } catch {
                    startError = guideText(language, "无法刷新考试状态，请稍后重试。", "試験状態を更新できません。", "Couldn't refresh the exam state.")
                }
            default:
                handleStartError(error)
            }
        } catch {
            startError = guideText(language, "无法开始科目，请稍后再试。", "科目を開始できません。", "Couldn't start the section.")
        }
    }

    private func handleStartError(_ error: KaiXAPIError) {
        switch JLPTExamRecoveryPolicy.action(for: error) {
        case let .showPaperResult(recoveredAttemptId):
            // 整卷已交完：服务端已把 attempt 放在 detail 里，直接进成绩页。
            // 只弹「已完成」会把用户留在 intro/休息页，无路可走。
            pendingStartIntent = nil
            if let recoveredAttemptId, !recoveredAttemptId.isEmpty {
                attemptId = recoveredAttemptId
            }
            activeStart = nil
            activeStartReceipt = nil
            phase = .result
            Task { await refreshProgress(after: paperId) }
        case .openWallet:
            pendingStartIntent = nil
            coinInsufficientError = error
            coinInsufficient = true
        case .openMembership:
            pendingStartIntent = nil
            router.open(.guideMemberResources, in: .guide)
        default:
            startError = error.error.message
        }
    }

    private func applySubmittedSection(_ result: KaiXJLPTExamResult) {
        guard let progress = result.paperAttempt else {
            activeStart = nil
            activeStartReceipt = nil
            phase = .betweenBreak
            Task { await refreshProgress(after: result.examId ?? paperId) }
            return
        }
        apply(progress: progress)
    }

    private func apply(progress: KaiXJLPTPaperAttempt) {
        paperAttempt = progress
        attemptId = progress.id
        if progress.status.lowercased() == "completed" {
            activeStart = nil
            activeStartReceipt = nil
            phase = .result
            return
        }
        idx = JLPTPaperProgressResolver.index(
            sectionExamIDs: sectionIDs,
            currentSectionExamId: progress.currentSectionExamId,
            currentSectionIndex: progress.currentSectionIndex
        )
        activeStart = nil
        activeStartReceipt = nil
        phase = .betweenBreak
    }

    private func applyRecovery(_ action: JLPTExamRecoveryAction) {
        guard case let .restorePaper(currentSectionExamId, currentSectionIndex, recoveredAttemptId) = action else { return }
        if let recoveredAttemptId { attemptId = recoveredAttemptId }
        idx = JLPTPaperProgressResolver.index(
            sectionExamIDs: sectionIDs,
            currentSectionExamId: currentSectionExamId,
            currentSectionIndex: currentSectionIndex
        )
        activeStart = nil
        activeStartReceipt = nil
        phase = .betweenBreak
        Task { await refreshProgress(after: currentSectionExamId ?? paperId) }
    }

    private func refreshProgress(after requestedExamId: String) async {
        do {
            let preflight = try await KaiXAPIClient.shared.jlptExamPreflight(examId: requestedExamId)
            if let progress = preflight.paperAttempt {
                apply(progress: progress)
            } else {
                idx = JLPTPaperProgressResolver.index(
                    sectionExamIDs: sectionIDs,
                    currentSectionExamId: preflight.currentSectionExamId,
                    currentSectionIndex: 0
                )
                phase = .betweenBreak
            }
        } catch {
            startError = guideText(language, "无法恢复整卷进度，请重试。", "模試の進捗を復元できません。再試行してください。", "Couldn't restore paper progress. Try again.")
        }
    }

    private func load() async {
        guard detail == nil else { return }
        isLoading = true
        loadFailed = false
        do {
            detail = try await KaiXAPIClient.shared.jlptPaper(paperId: paperId)
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

/// 分科整卷合并成绩:笔试缩放分(JLPTScaledScorePanel)+ 聴解百分比 + 各科回看。
struct GuideJLPTPaperResultView: View {
    @Environment(\.appLanguage) private var language
    let paperId: String
    let attemptId: String
    var onExit: () -> Void

    @State private var result: KaiXJLPTPaperResult?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KXSpacing.lg) {
                if isLoading {
                    JLPTStateView(title: guideText(language, "正在合并成绩…", "採点を集計中…", "Tallying results…"), isLoading: true)
                        .frame(minHeight: 320)
                } else if loadFailed || result == nil {
                    JLPTStateView(systemImage: "wifi.slash",
                                  title: guideText(language, "加载失败", "読み込みに失敗しました", "Couldn't load"),
                                  actionTitle: guideText(language, "重试", "再試行", "Retry"),
                                  action: { Task { await load() } })
                } else if let r = result {
                    let official = r.officialScore.flatMap {
                        JLPTOfficialScorePresentation.make(score: $0, language: language)
                    }
                    let passed = official?.passedReference
                        ?? r.scaled?.passedWrittenReference
                        ?? false
                    JLPTEyebrow(text: "JLPT · \(official?.level ?? r.level ?? "") · " + guideText(language, "成绩", "結果", "Result"))
                    Text(passed
                         ? (official == nil
                            ? guideText(language, "达到笔试参考线！", "筆記参考ライン到達！", "Reached the written reference line!")
                            : guideText(language, "达到全卷参考线！", "総合参考ライン到達！", "Reached the full-paper reference line!"))
                         : guideText(language, "再接再厉", "次回に向けて", "Keep going"))
                        .kxScaledFont(24, relativeTo: .title2, weight: .heavy, design: .rounded)
                        .foregroundStyle(KXColor.livingInk)

                    if let official {
                        JLPTOfficialScorePanel(presentation: official)
                    } else {
                        // Compatibility only: older servers expose separate
                        // written scaled + listening percentage blocks.
                        if let scaled = r.scaled {
                            JLPTScaledScorePanel(scaled: scaled)
                        }
                        if let l = r.listening {
                            VStack(alignment: .leading, spacing: 6) {
                                JLPTEyebrow(text: guideText(language, "聴解（参考）", "聴解（参考）", "Listening (reference)"))
                                Text(guideText(language, "答对 \(l.correct ?? 0)/\(l.total ?? 0) · 得分 \(l.score ?? 0)", "正解 \(l.correct ?? 0)/\(l.total ?? 0) · \(l.score ?? 0)点", "\(l.correct ?? 0)/\(l.total ?? 0) correct · \(l.score ?? 0)"))
                                    .font(.subheadline.weight(.bold)).foregroundStyle(KXColor.livingInk)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .jlptSurface(radius: KXRadius.lg)
                        }
                    }
                    ForEach(r.sections ?? []) { s in
                        if s.done ?? false, let sid = s.sessionId {
                            NavigationLink {
                                GuideJLPTExamReviewView(sessionId: sid, title: s.title ?? s.sectionLabel ?? "")
                            } label: {
                                sectionRow(s)
                            }
                            .buttonStyle(KXPressableStyle(scale: 0.98))
                        } else {
                            sectionRow(s)
                        }
                    }
                    Button(action: onExit) {
                        Label(guideText(language, "返回模考列表", "一覧へ戻る", "Back to exams"), systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(KXColor.livingAccentSoft, in: Capsule())
                            .foregroundStyle(KXColor.livingAccent)
                    }
                    .buttonStyle(.plain)
                    JLPTComplianceNote(text: r.disclaimer)
                }
            }
            .padding(KXSpacing.lg)
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(guideText(language, "考试结果", "試験結果", "Result"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func sectionRow(_ s: KaiXJLPTPaperResultSection) -> some View {
        HStack(spacing: KXSpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title ?? s.sectionLabel ?? "")
                    .font(.subheadline.weight(.bold)).foregroundStyle(KXColor.livingInk)
                Text((s.done ?? false)
                     ? guideText(language, "答对 \(s.correct ?? 0)/\(s.total ?? 0)", "正解 \(s.correct ?? 0)/\(s.total ?? 0)", "\(s.correct ?? 0)/\(s.total ?? 0) correct")
                     : guideText(language, "未完成", "未完了", "Not done"))
                    .font(.caption2.weight(.medium)).foregroundStyle(KXColor.livingMuted)
            }
            Spacer(minLength: 0)
            if (s.done ?? false), s.sessionId != nil {
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(KXColor.livingMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .jlptSurface(radius: KXRadius.lg)
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            result = try await KaiXAPIClient.shared.jlptPaperResult(
                paperId: paperId,
                attemptId: attemptId
            )
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

/// Localized full-paper score panel. Labels and the equating disclaimer come
/// exclusively from the validated presentation model, never server copy.
private struct JLPTOfficialScorePanel: View {
    @Environment(\.appLanguage) private var language
    let presentation: JLPTOfficialScorePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    JLPTEyebrow(text: guideText(language, "全卷参考分", "総合参考スコア", "Full-paper reference score"))
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(presentation.total)")
                            .kxScaledFont(30, relativeTo: .largeTitle, weight: .black, design: .rounded)
                        Text("/ \(presentation.totalMax)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.livingMuted)
                    }
                    .foregroundStyle(KXColor.livingInk)
                }
                Spacer(minLength: KXSpacing.md)
                Label(
                    presentation.passedReference
                        ? guideText(language, "参考合格", "参考合格", "Reference pass")
                        : guideText(language, "未达参考线", "参考ライン未到達", "Below reference line"),
                    systemImage: presentation.passedReference ? "checkmark.seal.fill" : "arrow.up.right.circle.fill"
                )
                .font(.caption.weight(.bold))
                .foregroundStyle(presentation.passedReference ? KXColor.livingAccent : KXColor.livingWarm)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(guideText(
                language,
                "全卷参考分 \(presentation.total) 分，共 \(presentation.totalMax) 分，参考合格线 \(presentation.passLine) 分",
                "総合参考スコア \(presentation.total) 点、\(presentation.totalMax) 点満点、参考合格ライン \(presentation.passLine) 点",
                "Full-paper reference score \(presentation.total) out of \(presentation.totalMax), reference pass line \(presentation.passLine)"
            ))

            Divider().overlay(JLPTStyle.hairline)

            ForEach(presentation.divisions) { division in
                HStack(spacing: KXSpacing.md) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(division.label)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.livingInk)
                        Text(guideText(
                            language,
                            "原始 \(division.raw)/\(division.rawMax) · 区分线 \(division.sectionMin)",
                            "素点 \(division.raw)/\(division.rawMax)・区分基準 \(division.sectionMin)",
                            "Raw \(division.raw)/\(division.rawMax) · minimum \(division.sectionMin)"
                        ))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(KXColor.livingMuted)
                    }
                    Spacer(minLength: 0)
                    Text("\(division.scaled)/\(division.scaledMax)")
                        .font(.headline.weight(.black).monospacedDigit())
                        .foregroundStyle(division.passed ? KXColor.livingAccent : KXColor.livingWarm)
                    Image(systemName: division.passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(division.passed ? KXColor.livingAccent : KXColor.livingWarm)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(guideText(
                    language,
                    "\(division.label)，参考分 \(division.scaled) 分，共 \(division.scaledMax) 分，区分线 \(division.sectionMin) 分",
                    "\(division.label)、参考 \(division.scaled) 点、\(division.scaledMax) 点満点、区分基準 \(division.sectionMin) 点",
                    "\(division.label), reference score \(division.scaled) out of \(division.scaledMax), section minimum \(division.sectionMin)"
                ))
            }

            Text(presentation.referenceNote)
                .font(.caption)
                .foregroundStyle(KXColor.livingMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(presentation.referenceNote)
        }
        .padding(18)
        .jlptSurface(radius: KXRadius.hero, elevated: true)
    }
}

/// 答题卡:整卷跳题面板。按科目分组展示题号格,已答=实心、当前=描边、未答=
/// 浅底;底部常驻交卷按钮(带未答数),模拟真实考试的「检查—交卷」动线。
private struct JLPTAnswerSheetView: View {
    @Environment(\.appLanguage) private var language
    let questions: [KaiXJLPTQuestionDTO]
    let answers: [String: Int]
    let current: Int
    let onJump: (Int) -> Void
    let onSubmit: () -> Void

    private var unansweredCount: Int {
        questions.filter { answers[$0.id] == nil }.count
    }

    /// 按 sectionLabel 连续分段(卷面本就按科目排序)。
    private var sections: [(label: String, range: Range<Int>)] {
        var out: [(String, Range<Int>)] = []
        var start = 0
        for (i, q) in questions.enumerated() {
            let label = q.sectionLabel ?? ""
            if i == 0 { continue }
            let prev = questions[i - 1].sectionLabel ?? ""
            if label != prev {
                out.append((prev, start..<i))
                start = i
            }
        }
        if !questions.isEmpty {
            out.append((questions.last?.sectionLabel ?? "", start..<questions.count))
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    HStack {
                        Text(guideText(language, "答题卡", "解答一覧", "Answer sheet"))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(KXColor.livingInk)
                        Spacer(minLength: 0)
                        Text(guideText(language, "未答 \(unansweredCount)", "未回答 \(unansweredCount)", "\(unansweredCount) unanswered"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(unansweredCount > 0 ? KXColor.livingWarm : KXColor.livingMuted)
                    }
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 8) {
                            if !section.label.isEmpty {
                                Text(section.label)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(KXColor.livingAccent)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                                ForEach(Array(section.range), id: \.self) { idx in
                                    cell(idx)
                                }
                            }
                        }
                    }
                }
                .padding(KXSpacing.lg)
            }
            Divider()
            Button(action: onSubmit) {
                Text(unansweredCount > 0
                    ? guideText(language, "交卷（还有 \(unansweredCount) 题未答）", "提出（未回答 \(unansweredCount) 問）", "Submit (\(unansweredCount) unanswered)")
                    : guideText(language, "交卷看成绩", "提出して採点", "Submit for score"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(KXColor.livingAccent, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            }
            .buttonStyle(KXPressableStyle(scale: 0.98))
            .padding(KXSpacing.lg)
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
    }

    private func cell(_ idx: Int) -> some View {
        let q = questions[idx]
        let answered = answers[q.id] != nil
        let isCurrent = idx == current
        return Button {
            onJump(idx)
        } label: {
            Text("\(idx + 1)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(answered ? KXColor.onAccent : KXColor.livingInk)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(
                    answered ? KXColor.livingAccent : KXColor.livingSoft,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(KXColor.livingInk.opacity(0.55), lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(guideText(language, "第 \(idx + 1) 题", "第 \(idx + 1) 問", "Question \(idx + 1)") + (answered ? guideText(language, "，已作答", "、回答済み", ", answered") : guideText(language, "，未作答", "、未回答", ", unanswered")))
    }
}

/// 拦截系统 pop 手势:KXSwipeBackEnabler 把 interactivePopGestureRecognizer 的
/// delegate 全局改成「栈深 > 1 即放行」,所以考试中要挡误滑只能直接禁用手势本身;
/// 离场(交卷显示结果 / 确认退出)时恢复,不影响其他页面。
private struct KXExamPopGestureBlocker: UIViewControllerRepresentable {
    var blocked: Bool

    func makeUIViewController(context: Context) -> BlockerViewController { BlockerViewController() }

    func updateUIViewController(_ controller: BlockerViewController, context: Context) {
        controller.blocked = blocked
        controller.apply()
    }

    final class BlockerViewController: UIViewController {
        var blocked = false
        private weak var gesture: UIGestureRecognizer?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // 无论因何离场都恢复手势,避免把整个导航栈的边滑返回卡死。
            gesture?.isEnabled = true
        }

        func apply() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let g = self.navigationController?.interactivePopGestureRecognizer else { return }
                self.gesture = g
                g.isEnabled = !self.blocked
            }
        }
    }
}

/// Post-submit scored breakdown. Answers revealed; correct/incorrect per question.
struct GuideJLPTExamResultView: View {
    @Environment(\.appLanguage) private var language
    let result: KaiXJLPTExamResult
    /// 交卷边界仍在本地 outbox 的题数；只有服务端明确拒绝截止后快照时才展示。
    var unsyncedCount: Int = 0
    var onExit: () -> Void

    private var submissionNotice: String {
        JLPTExamCopy.submissionNotice(
            deadlineExpired: result.deadlineExpired ?? false,
            snapshotAccepted: result.snapshotAccepted ?? false,
            pendingAnswerCount: unsyncedCount,
            language: language
        )
    }

    var body: some View {
        ScrollView {
            if !submissionNotice.isEmpty {
                HStack(alignment: .top, spacing: KXSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(KXColor.livingWarm)
                    Text(submissionNotice)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KXColor.livingInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(KXColor.livingWarm.opacity(0.10), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.livingWarm.opacity(0.24), lineWidth: 0.8))
                .padding(.horizontal, KXSpacing.lg)
                .padding(.top, KXSpacing.lg)
            }
            JLPTExamResultContent(result: result)
            Button(action: onExit) {
                Label(guideText(language, "返回模考列表", "一覧へ戻る", "Back to exams"), systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(KXColor.livingAccentSoft, in: Capsule())
                    .foregroundStyle(KXColor.livingAccent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("jlpt.exam.result.backToExams")
            .padding(.horizontal, KXSpacing.lg)
            .padding(.bottom, KXSpacing.lg)
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(guideText(language, "考试结果", "試験結果", "Result"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The result body without a scroll wrapper, so it can be embedded directly in a
/// parent ScrollView (回看) without nesting scroll views.
struct JLPTExamResultContent: View {
    @Environment(\.appLanguage) private var language
    let result: KaiXJLPTExamResult

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            // 全真卷(score_mode='jlpt_scaled')按官方计分结构出缩放分;
            // 普通练习卷维持 0-100 百分比环。
            if let scaled = result.scaled {
                JLPTScaledScorePanel(scaled: scaled, correct: result.correct, total: result.total)
            } else {
                scoreCard
            }
            // 语境内成交（转化最高的坑位）：交卷时刻按本次最弱分区推荐一件
            // 付费资料，sheet 就地打开、不打断学习会话。
            JLPTExamUpsellCard(result: result)
            ForEach(Array((result.questions ?? []).enumerated()), id: \.element.id) { idx, q in
                JLPTQuestionCard(
                    question: q,
                    index: idx,
                    total: (result.questions ?? []).count,
                    selectedIndex: .constant(q.selectedIndex),
                    revealed: true,
                    correctIndex: q.answerIndex,
                    explanation: q.explanation
                )
            }
            JLPTComplianceNote(text: result.disclaimer)
        }
        .padding(KXSpacing.lg)
    }

    private var scoreCard: some View {
        let passed = result.passed ?? false
        let total = max(1, result.total ?? 1)
        let frac = Double(result.correct ?? 0) / Double(total)
        return VStack(spacing: 14) {
            JLPTEyebrow(text: guideText(language, "考试结果", "試験結果", "Result"))
            JLPTScoreRing(score: result.score ?? 0, fraction: frac, passed: passed, size: 140)
            Text(guideText(language, "答对 \(result.correct ?? 0)/\(result.total ?? 0)", "正解 \(result.correct ?? 0)/\(result.total ?? 0)", "\(result.correct ?? 0)/\(result.total ?? 0) correct"))
                .font(.subheadline.weight(.bold)).foregroundStyle(KXColor.livingMuted)
            JLPTPassPill(passed: passed,
                         title: passed
                            ? guideText(language, "达到合格线 \(result.passScore ?? 60)", "合格ライン \(result.passScore ?? 60) 到達", "Passed · ≥\(result.passScore ?? 60)")
                            : guideText(language, "未达合格线 \(result.passScore ?? 60)", "合格ライン \(result.passScore ?? 60) 未達", "Below \(result.passScore ?? 60)"))
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .jlptSurface(radius: KXRadius.sheet, elevated: true)
    }
}

/// JLPT 标准出分面板(全真卷)：笔试缩放总分(0-120) + 各科分条(0-60 或合并
/// 0-120,带基准点刻度) + 参考合格判定。不含聴解,note 免责必须展示 ——
/// 绝不暗示与官方成绩等价。
struct JLPTScaledScorePanel: View {
    @Environment(\.appLanguage) private var language
    let scaled: KaiXJLPTScaledResult
    var correct: Int? = nil
    var total: Int? = nil

    private var passRef: Bool { scaled.passedWrittenReference ?? false }

    /// JLPT 的两道门:总分达参考线 + 每科过基准点。总分够了却栽在某科基准点上
    /// 是真实且常见的落榜方式 —— 此时必须说清是「科目」而不是「总分」不够,
    /// 否则分数明明 ≥ 参考线却写「未达参考线」,考生会以为出分算错了。
    private var verdictTitle: String {
        let line = scaled.passLineWritten ?? 0
        if passRef {
            return guideText(language,
                             "达到笔试参考线 \(line)",
                             "筆記参考ライン \(line) 到達",
                             "Reached written reference line \(line)")
        }
        let failed = (scaled.scales ?? []).filter { !($0.passed ?? false) }
        let totalReached = (scaled.writtenTotal ?? 0) >= line
        if totalReached, !failed.isEmpty {
            let zh = failed.map { $0.label ?? "" }.joined(separator: "・")
            let en = failed.map { $0.label ?? "" }.joined(separator: " / ")
            return guideText(language,
                             "总分达线，但「\(zh)」未过基准点",
                             "合計は到達、ただし「\(zh)」が基準点未満",
                             "Total reached, but \(en) is below its section minimum")
        }
        return guideText(language,
                         "未达笔试参考线 \(line)",
                         "筆記参考ライン \(line) 未達",
                         "Below written reference line \(line)")
    }

    var body: some View {
        VStack(spacing: 14) {
            JLPTEyebrow(text: guideText(language, "JLPT 标准出分 · 笔试参考", "JLPT 準拠スコア・筆記参考", "JLPT-style written score"))

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text("\(scaled.writtenTotal ?? 0)")
                    .kxScaledFont(52, relativeTo: .largeTitle, weight: .black, design: .rounded)
                    .foregroundStyle(passRef ? KXColor.livingAccent : KXColor.livingWarm)
                    .contentTransition(.numericText())
                Text("/ \(scaled.writtenMax ?? 120)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(KXColor.livingMuted)
            }

            JLPTPassPill(passed: passRef, title: verdictTitle)

            if let correct, let total, total > 0 {
                Text(guideText(language, "答对 \(correct)/\(total)", "正解 \(correct)/\(total)", "\(correct)/\(total) correct"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KXColor.livingMuted)
            }

            VStack(spacing: 12) {
                ForEach(scaled.scales ?? [], id: \.key) { scale in
                    scaleRow(scale)
                }
            }
            .padding(.top, 2)

            if let note = scaled.note, !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(KXColor.livingMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .jlptSurface(radius: KXRadius.sheet, elevated: true)
    }

    private func scaleRow(_ scale: KaiXJLPTScaledScale) -> some View {
        let scaledScore = scale.scaled ?? 0
        let scaledMax = max(1, scale.scaledMax ?? 60)
        let sectionMin = scale.sectionMin ?? 0
        let passed = scale.passed ?? false
        let tint = passed ? KXColor.livingAccent : KXColor.livingWarm
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(scale.label ?? scale.key ?? "")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(KXColor.livingInk)
                Spacer(minLength: 8)
                Text("\(scaledScore)")
                    .font(.subheadline.weight(.black).monospacedDigit())
                    .foregroundStyle(tint)
                + Text(" / \(scaledMax)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(KXColor.livingMuted)
            }
            // 分数条 + 基准点刻度:一眼看出「过没过 19/60(或 38/120)」。
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(KXColor.livingSoft)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, w * CGFloat(scaledScore) / CGFloat(scaledMax)))
                    if sectionMin > 0 {
                        Rectangle()
                            .fill(KXColor.livingInk.opacity(0.35))
                            .frame(width: 2)
                            .offset(x: w * CGFloat(sectionMin) / CGFloat(scaledMax) - 1)
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            HStack {
                if let raw = scale.raw, let rawMax = scale.rawMax {
                    Text(guideText(language, "答对 \(raw)/\(rawMax)", "正解 \(raw)/\(rawMax)", "\(raw)/\(rawMax) correct"))
                }
                Spacer(minLength: 0)
                if sectionMin > 0 {
                    Text(guideText(language, "基准点 \(sectionMin)", "基準点 \(sectionMin)", "Section min \(sectionMin)"))
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(KXColor.livingMuted)
        }
    }
}

/// 弱项推荐卡：从 questions[].section + correct 客户端计算本次最弱分区，
/// 优先推荐 slug 含本级别（如 "n2"）的 JLPT 付费 SKU，无匹配退回第一件；
/// 一件付费 SKU 都没有则整卡不渲染。点击以 sheet 打开商品详情就地购买。
struct JLPTExamUpsellCard: View {
    @Environment(\.appLanguage) private var language
    let result: KaiXJLPTExamResult
    @State private var product: KaiXGuideProductDTO?
    @State private var weakestLabel = ""
    @State private var showDetail = false

    var body: some View {
        Group {
            if let product {
                Button {
                    // C-2 客户端漏斗:推荐卡点击。
                    Task { await KaiXAPIClient.shared.funnelEvent("upsell_click", entityType: "guide_product", entityId: product.slug, props: ["placement": "exam_result"]) }
                    showDetail = true
                } label: {
                    HStack(alignment: .top, spacing: KXSpacing.md) {
                        Image(systemName: "target")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(weakestLabel.isEmpty
                                ? guideText(language, "针对性提升", "弱点を強化", "Level up your weak spots")
                                : guideText(language, "「\(weakestLabel)」丢分较多", "「\(weakestLabel)」で失点が多め", "Most points lost in \(weakestLabel)"))
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(KXColor.livingMuted)
                            Text(product.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(KXColor.livingInk)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Text("¥\(product.price)")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(KXColor.accent)
                                if let member = product.memberPrice, member > 0, member < product.price {
                                    Text(guideText(language, "会员 ¥\(member)", "会員 ¥\(member)", "Members ¥\(member)"))
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(KXColor.accentSoft, in: Capsule())
                                        .foregroundStyle(KXColor.accent)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.livingMuted)
                            .padding(.top, 6)
                    }
                    .padding(16)
                    .jlptSurface(radius: KXRadius.lg)
                }
                .buttonStyle(.fullArea)
                .contentShape(Rectangle())
            }
        }
        .task { await load() }
        .sheet(isPresented: $showDetail) {
            if let product {
                NavigationStack { GuideProductDetailView(slug: product.slug) }
            }
        }
    }

    private func load() async {
        guard product == nil else { return }
        let resp = try? await KaiXAPIClient.shared.guideProducts(country: "jp", categoryKey: "jlpt", pageSize: 50)
        let paid = (resp?.items ?? []).filter { !$0.isFree && !$0.isComingSoon && !$0.isService }
        guard !paid.isEmpty else { return }
        let level = (result.level ?? "").lowercased()
        product = paid.first { !level.isEmpty && $0.slug.lowercased().contains(level) } ?? paid.first
        weakestLabel = weakestSection() ?? ""
        // C-2 客户端漏斗:推荐卡真正渲染出 SKU 才算一次曝光(load 有 product==nil
        // 防重,同一张结果卡只报一次)。
        if let slug = product?.slug {
            Task { await KaiXAPIClient.shared.funnelEvent("upsell_view", entityType: "guide_product", entityId: slug, props: ["placement": "exam_result"]) }
        }
    }

    /// The section that lost the most points this session (label for copy).
    private func weakestSection() -> String? {
        var wrong: [String: (count: Int, label: String)] = [:]
        for q in result.questions ?? [] {
            let isCorrect = q.correct ?? (q.selectedIndex != nil && q.selectedIndex == q.answerIndex)
            guard !isCorrect else { continue }
            let cur = wrong[q.section] ?? (0, q.sectionLabel ?? q.section)
            wrong[q.section] = (cur.count + 1, cur.label)
        }
        return wrong.max { $0.value.count < $1.value.count }?.value.label
    }
}

/// 回看 a past session (fetches the full session review).
struct GuideJLPTExamReviewView: View {
    @Environment(\.appLanguage) private var language
    let sessionId: String
    let title: String

    @State private var result: KaiXJLPTExamResult?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            if isLoading {
                JLPTStateView(title: guideText(language, "正在加载回看…", "読み込み中…", "Loading…"), isLoading: true)
            } else if loadFailed {
                JLPTStateView(systemImage: "wifi.slash",
                              title: guideText(language, "加载失败", "読み込みに失敗しました", "Couldn't load"),
                              actionTitle: guideText(language, "重试", "再試行", "Retry"),
                              action: { Task { await load() } })
            } else if let r = result {
                JLPTExamResultContent(result: r)
            }
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(title.isEmpty ? guideText(language, "回看", "見直し", "Review") : title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            result = try await KaiXAPIClient.shared.jlptExamSession(sessionId: sessionId)
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}
