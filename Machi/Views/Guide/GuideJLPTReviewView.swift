import SwiftUI

/// 错题本 — questions the user last got wrong. Each is re-answerable: the review
/// payload already reveals `answerIndex`+`explanation`, so we grade locally for an
/// instant flip, and also record the attempt (`sourceKind=review`) so a now-correct
/// answer drops it from the book on the next load and counts toward the streak.
///
/// Compliance: original / licensed questions, not official past papers.
struct GuideJLPTReviewView: View {
    @Environment(\.appLanguage) private var language

    var initialLevel: JLPTLevel? = nil

    @State private var levelFilterOn: Bool
    @State private var level: JLPTLevel
    @State private var questions: [KaiXJLPTQuestionDTO] = []
    /// questionId -> selected index (once answered locally).
    @State private var answered: [String: Int] = [:]
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var sessionId = UUID().uuidString

    init(initialLevel: JLPTLevel? = nil) {
        self.initialLevel = initialLevel
        _levelFilterOn = State(initialValue: initialLevel != nil)
        _level = State(initialValue: initialLevel ?? .n5)
    }

    var body: some View {
        ScrollView {
            if isLoading {
                JLPTStateView(title: guideText(language, "正在加载错题…", "間違いを読み込み中…", "Loading review…"), isLoading: true)
            } else if loadFailed {
                JLPTStateView(systemImage: "wifi.slash",
                              title: guideText(language, "加载失败", "読み込みに失敗しました", "Couldn't load"),
                              actionTitle: guideText(language, "重试", "再試行", "Retry"),
                              action: { Task { await load() } })
            } else if questions.isEmpty {
                JLPTStateView(systemImage: "checkmark.seal",
                              title: guideText(language, "错题本是空的", "間違いノートは空です", "Your review book is empty"),
                              message: guideText(language, "先去题库做几道题，答错的会自动进来。", "まず演習をすると、間違えた問題がここに集まります。", "Do some practice — wrong answers land here automatically."))
            } else {
                content
            }
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(guideText(language, "错题本", "間違いノート", "Review book"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $levelFilterOn) {
                Text(guideText(language, "仅看 \(level.rawValue)", "\(level.rawValue) のみ", "\(level.rawValue) only"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KXColor.livingInk)
            }
            .tint(KXColor.livingAccent)
            .onChange(of: levelFilterOn) { _, _ in Task { await load() } }

            if levelFilterOn {
                JLPTLevelPicker(selection: $level)
                    .onChange(of: level) { _, _ in Task { await load() } }
            }

            ForEach(Array(questions.enumerated()), id: \.element.id) { idx, q in
                JLPTQuestionCard(
                    question: q,
                    index: idx,
                    total: questions.count,
                    selectedIndex: Binding(
                        get: { answered[q.id] },
                        set: { newValue in
                            guard answered[q.id] == nil, let v = newValue else { return }
                            answered[q.id] = v
                            Task { await record(q, selected: v) }
                        }
                    ),
                    revealed: answered[q.id] != nil,
                    correctIndex: q.answerIndex,
                    explanation: q.explanation
                )
            }

            JLPTComplianceNote()
        }
        .padding(16)
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        answered = [:]
        sessionId = UUID().uuidString
        do {
            let resp = try await KaiXAPIClient.shared.jlptReview(level: levelFilterOn ? level.rawValue : nil)
            questions = resp.questions ?? []
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    /// Persist the re-attempt so a corrected answer leaves the book next load.
    private func record(_ q: KaiXJLPTQuestionDTO, selected: Int) async {
        _ = try? await KaiXAPIClient.shared.jlptAttempt(
            questionId: q.id, selectedIndex: selected, sessionId: sessionId, sourceKind: "review")
    }
}
