import Combine
import SwiftUI

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
                    .background(((item.passed ?? false) ? KXColor.livingAccent : KXColor.livingWarm).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            if err.error.code == "MEMBER_REQUIRED" {
                upgradeMessage = err.error.message
            } else if err.error.code == "no_questions" {
                upgradeMessage = guideText(language, "该模考暂无可用题目。", "この模試には利用可能な問題がありません。", "This exam has no questions yet.")
            } else {
                upgradeMessage = err.error.message
            }
        } catch {
            upgradeMessage = guideText(language, "无法开始考试，请稍后再试。", "試験を開始できません。", "Couldn't start the exam.")
        }
    }
}

/// A live, optionally-timed exam session. Each answer is saved server-side as the
/// user progresses; submitting grades and pushes to the result review.
struct GuideJLPTExamSessionView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    let start: KaiXJLPTExamStartResponse

    @State private var cursor = 0
    @State private var answers: [String: Int] = [:]   // questionId -> selected
    @State private var remaining: Int = 0
    @State private var timedOut = false
    @State private var submitting = false
    @State private var submitFailed = false
    @State private var result: KaiXJLPTExamResult?
    @State private var pushResult = false
    /// Question ids whose live per-answer save failed — re-flushed before submit
    /// so a dropped save isn't graded as unanswered.
    @State private var unsavedAnswers: Set<String> = []

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var questions: [KaiXJLPTQuestionDTO] { start.questions ?? [] }
    private var isTimed: Bool { (start.durationSeconds ?? 0) > 0 }

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
                GuideJLPTExamResultView(result: r)
            }
        }
        .onAppear { remaining = start.durationSeconds ?? 0 }
        .onReceive(timer) { _ in
            guard isTimed, !timedOut, result == nil else { return }
            if remaining > 0 {
                remaining -= 1
            } else if !submitting {
                timedOut = true
                Task { await submit() }
            }
        }
    }

    @ViewBuilder
    private var sessionBody: some View {
        let q = questions[cursor]
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(KXColor.livingAccent, in: Capsule())
                } else {
                    Button(action: { Task { await submit() } }) {
                        HStack {
                            if submitting { ProgressView().controlSize(.small).tint(.white) }
                            Text(guideText(language, "交卷", "提出", "Submit")).font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(.white)
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

    private func submit() async {
        guard let sid = start.sessionId, !submitting, result == nil else { return }
        submitting = true
        submitFailed = false
        await flushUnsavedAnswers()
        do {
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

/// Post-submit scored breakdown. Answers revealed; correct/incorrect per question.
struct GuideJLPTExamResultView: View {
    @Environment(\.appLanguage) private var language
    let result: KaiXJLPTExamResult

    var body: some View {
        ScrollView {
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
