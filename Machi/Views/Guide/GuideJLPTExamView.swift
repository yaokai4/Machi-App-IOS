import Combine
import SwiftUI
import UIKit

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

    // active session pushed via navigation
    @State private var activeStart: KaiXJLPTExamStartResponse?
    @State private var pushSession = false

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
            if let start = activeStart {
                GuideJLPTExamSessionView(start: start)
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
            Task { await start(exam) }
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
                        examMetaChip(icon: "list.number", text: "\(exam.questionCount ?? 0)")
                        if (exam.durationSeconds ?? 0) > 0 {
                            examMetaChip(icon: "clock", text: minuteText(exam.durationSeconds ?? 0))
                        }
                        examMetaChip(icon: "checkmark.seal", text: guideText(language, "合格 \(exam.passScore ?? 60)", "合格 \(exam.passScore ?? 60)", "≥\(exam.passScore ?? 60)"))
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

    private func historyRow(_ item: KaiXJLPTExamHistoryItem) -> some View {
        NavigationLink {
            GuideJLPTExamReviewView(sessionId: item.sessionId, title: item.title ?? "")
        } label: {
            HStack(spacing: KXSpacing.md) {
                // Score chip — passing = accent tile, failing = warm tile.
                Text("\(item.score ?? 0)")
                    .kxScaledFont(17, weight: .black, design: .rounded)
                    .foregroundStyle((item.passed ?? false) ? KXColor.livingAccent : KXColor.livingWarm)
                    .frame(width: 44, height: 44)
                    .background(((item.passed ?? false) ? KXColor.livingAccent : KXColor.livingWarm).opacity(0.12), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title ?? item.level ?? "")
                        .font(.subheadline.weight(.bold)).foregroundStyle(KXColor.livingInk)
                    Text(guideText(language, "\(item.correct ?? 0)/\(item.total ?? 0) 正确", "\(item.correct ?? 0)/\(item.total ?? 0) 正解", "\(item.correct ?? 0)/\(item.total ?? 0) correct"))
                        .font(.caption2.weight(.medium)).foregroundStyle(KXColor.livingMuted)
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

    private func start(_ exam: KaiXJLPTExam) async {
        guard starting == nil else { return }
        starting = exam.id
        defer { starting = nil }
        do {
            let resp = try await KaiXAPIClient.shared.jlptExamStart(examId: exam.id)
            activeStart = resp
            pushSession = true
        } catch let err as KaiXAPIError {
            // 只有会员/配额类错误才弹「会员专享」+「查看会员」;题目缺失/网络等
            // 通用失败走中性弹窗,否则把无关错误伪装成会员墙、误导用户去买会员。
            if err.error.code == "MEMBER_REQUIRED" || err.error.code.contains("QUOTA") {
                upgradeMessage = err.error.message
            } else if err.error.code == "no_questions" {
                startErrorMessage = guideText(language, "该模考暂无可用题目。", "この模試には利用可能な問題がありません。", "This exam has no questions yet.")
            } else {
                startErrorMessage = err.error.message
            }
        } catch {
            startErrorMessage = guideText(language, "无法开始考试，请稍后再试。", "試験を開始できません。", "Couldn't start the exam.")
        }
    }
}

/// A live, optionally-timed exam session. Each answer is saved server-side as the
/// user progresses; submitting grades and pushes to the result review.
struct GuideJLPTExamSessionView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let start: KaiXJLPTExamStartResponse

    @State private var cursor = 0
    @State private var answers: [String: Int] = [:]   // questionId -> selected
    @State private var remaining: Int = 0
    /// 倒计时的绝对锚点。此前用「每秒 -1」的本地 tick,主 RunLoop Timer 在后台
    /// 挂起即暂停,切后台查词典可无限延时;现在每个 tick 都从 deadline 重算。
    @State private var deadline: Date?
    @State private var timedOut = false
    @State private var submitting = false
    @State private var submitFailed = false
    @State private var result: KaiXJLPTExamResult?
    @State private var pushResult = false
    /// Question ids whose live per-answer save failed — re-flushed before submit
    /// so a dropped save isn't graded as unanswered.
    @State private var unsavedAnswers: Set<String> = []
    /// 交卷时仍未同步到服务端的题数——结果页据此提示这些题按未答判分。
    @State private var unsyncedAtSubmit = 0
    @State private var showLeaveConfirm = false
    @State private var showUnsyncedConfirm = false
    /// B15-D 中断恢复:服务端在 start 返回了未完成的旧会话时,把已答题灌回本地
    /// 并提示用户。只在首次 onAppear 执行,避免返回本页时覆盖更新的本地作答。
    @State private var didRestoreResumed = false
    @State private var showResumedNotice = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var questions: [KaiXJLPTQuestionDTO] { start.questions ?? [] }
    private var isTimed: Bool { (start.durationSeconds ?? 0) > 0 }
    /// 已作答且未出分时,一次误滑/误点返回会静默丢弃整场考试(无续考入口),
    /// 所以此时必须拦截返回并弹确认。
    private var shouldGuardExit: Bool {
        result == nil && !answers.isEmpty && !questions.isEmpty
    }

    var body: some View {
        ScrollView {
            if questions.isEmpty {
                JLPTStateView(systemImage: "tray", title: guideText(language, "本卷暂无题目", "問題がありません", "No questions"))
            } else if timedOut && result == nil {
                // Time's up: show a reachable submit/retry state instead of
                // leaving the user stranded on whatever question they were on
                // with a frozen 0:00 clock and the only Submit button hidden on
                // the last page.
                timeUpState
            } else if cursor < questions.count {
                sessionBody
            } else {
                JLPTStateView(title: guideText(language, "正在交卷…", "採点中…", "Submitting…"), isLoading: true)
            }
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(start.title ?? guideText(language, "模拟考试", "模擬試験", "Mock exam"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $pushResult) {
            if let r = result {
                GuideJLPTExamResultView(result: r, unsyncedCount: unsyncedAtSubmit)
            }
        }
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
                    Button { showLeaveConfirm = true } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel(guideText(language, "返回", "戻る", "Back"))
                }
            }
        }
        .confirmationDialog(
            guideText(language, "退出考试？", "試験を終了しますか？", "Leave the exam?"),
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button(guideText(language, "退出（可稍后继续）", "終了（あとで再開できます）", "Leave (you can resume)"), role: .destructive) {
                dismiss()
            }
            Button(guideText(language, "继续作答", "回答を続ける", "Keep going"), role: .cancel) {}
        } message: {
            // B15-D 起服务端支持续考:已答题保留在服务端,重新进入同一模考即恢复。
            Text(isTimed
                ? guideText(language,
                            "已作答的题目已保存，但计时不会暂停；在时间用尽前重新进入本模考即可继续。",
                            "回答済みの内容は保存されますが、タイマーは止まりません。制限時間内に再入室すれば続きから受験できます。",
                            "Your answers are saved, but the clock keeps running — re-enter this exam before time runs out to continue.")
                : guideText(language,
                            "已作答的题目已保存，重新进入本模考即可继续。",
                            "回答済みの内容は保存されています。再入室すれば続きから受験できます。",
                            "Your answers are saved — re-enter this exam to continue."))
        }
        .confirmationDialog(
            guideText(language, "还有 \(unsavedAnswers.count) 题答案未同步", "\(unsavedAnswers.count) 問の回答が未同期です", "\(unsavedAnswers.count) answers not synced"),
            isPresented: $showUnsyncedConfirm,
            titleVisibility: .visible
        ) {
            Button(guideText(language, "重试同步并交卷", "再同期して提出", "Retry sync & submit")) {
                Task { await submit() }
            }
            Button(guideText(language, "仍然交卷（未同步按未答计）", "このまま提出（未同期は未回答扱い）", "Submit anyway (unsynced = unanswered)"), role: .destructive) {
                Task { await submit(force: true) }
            }
            Button(guideText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(guideText(language, "网络不稳定，这些题的答案还没有传到服务器，直接交卷会按未答判分。", "通信が不安定なため一部の回答が未送信です。このまま提出すると未回答として採点されます。", "Some answers haven't reached the server yet; submitting now grades them as unanswered."))
        }
    }

    /// B15-D:start 返回 resumed 时把服务端已保存的作答灌回本地状态,并把光标
    /// 移到第一道未答题。这些答案本就在服务端,不进 unsavedAnswers 重发队列。
    private func restoreResumedSessionIfNeeded() {
        guard !didRestoreResumed else { return }
        didRestoreResumed = true
        guard start.resumed ?? false else { return }
        for a in start.answers ?? [] {
            guard let qid = a.questionId, let sel = a.selectedIndex, sel >= 0 else { continue }
            if answers[qid] == nil { answers[qid] = sel }
        }
        if !questions.isEmpty {
            cursor = questions.firstIndex(where: { answers[$0.id] == nil }) ?? (questions.count - 1)
        }
        showResumedNotice = true
    }

    /// 以 deadline 为锚重算剩余时间;归零时自动交卷(超时场景跳过未同步确认)。
    private func syncClock() {
        guard isTimed, !timedOut, result == nil, let deadline else { return }
        remaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
        if remaining <= 0, !submitting {
            timedOut = true
            Task { await submit() }
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
                        guard let v = newValue else { return }
                        answers[q.id] = v
                        Task { await save(q, selected: v) }
                    }
                ),
                revealed: false,
                correctIndex: nil,
                explanation: nil
            )

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
                    Button(action: { Task { await submit() } }) {
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
                Text(guideText(language, "交卷失败,请检查网络后重试。", "提出に失敗しました。接続を確認して再試行してください。", "Submit failed — check your connection and try again."))
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
                action: { Task { await submit() } }
            )
        }
    }

    private var clockText: String {
        let m = remaining / 60, s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    private func save(_ q: KaiXJLPTQuestionDTO, selected: Int) async {
        guard let sid = start.sessionId else { return }
        do {
            try await KaiXAPIClient.shared.jlptExamAnswer(sessionId: sid, questionId: q.id, selectedIndex: selected)
            unsavedAnswers.remove(q.id)
        } catch {
            // Remember the failed save so it can be re-flushed at submit time —
            // otherwise a single dropped save (transient network) is graded as
            // unanswered and the score is silently, unexplainably low.
            unsavedAnswers.insert(q.id)
        }
    }

    /// Best-effort re-send of any answers whose live save failed, using the
    /// selections we still hold locally, so the server grades what the user
    /// actually chose. Runs before submit. (The fully robust fix is a whole-
    /// paper answers snapshot on submit — that needs a backend endpoint.)
    private func flushUnsavedAnswers() async {
        guard let sid = start.sessionId else { return }
        for qid in Array(unsavedAnswers) {
            guard let selected = answers[qid] else { unsavedAnswers.remove(qid); continue }
            do {
                try await KaiXAPIClient.shared.jlptExamAnswer(sessionId: sid, questionId: qid, selectedIndex: selected)
                unsavedAnswers.remove(qid)
            } catch {
                // Keep it marked; submit still proceeds best-effort.
            }
        }
    }

    private func submit(force: Bool = false) async {
        guard let sid = start.sessionId, !submitting, result == nil else { return }
        submitting = true
        submitFailed = false
        await flushUnsavedAnswers()
        // 重发后仍有未同步答案:非超时且未强制时先让用户决定(重试 / 仍然交卷),
        // 否则用户明明选了答案却被静默按未答判分,成绩偏低且不可解释。
        if !force, !timedOut, !unsavedAnswers.isEmpty {
            submitting = false
            showUnsyncedConfirm = true
            return
        }
        do {
            unsyncedAtSubmit = unsavedAnswers.count
            let r = try await KaiXAPIClient.shared.jlptExamSubmit(sessionId: sid)
            result = r
            pushResult = true
        } catch {
            // Leave the session open and surface the failure so a timed-out
            // auto-submit doesn't look like a frozen exam with no way forward.
            submitFailed = true
        }
        submitting = false
    }
}

/// 拦截系统 pop 手势:KXSwipeBackEnabler 把 interactivePopGestureRecognizer 的
/// delegate 全局改成「栈深 > 1 即放行」,所以考试中要挡误滑只能直接禁用手势本身;
/// 离场(交卷推结果页 / 确认退出)时恢复,不影响其他页面。
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
    /// 交卷时未能同步到服务器的题数(best-effort 提交)——必须如实标注,
    /// 否则弱网下成绩静默偏低,用户无从得知原因。
    var unsyncedCount: Int = 0

    var body: some View {
        ScrollView {
            if unsyncedCount > 0 {
                HStack(alignment: .top, spacing: KXSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(KXColor.livingWarm)
                    Text(guideText(language,
                                   "有 \(unsyncedCount) 题的答案因网络原因未能上传，已按未答判分。",
                                   "通信の問題で \(unsyncedCount) 問の回答が送信できず、未回答として採点されました。",
                                   "\(unsyncedCount) answers couldn't be uploaded and were graded as unanswered."))
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
            scoreCard
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
