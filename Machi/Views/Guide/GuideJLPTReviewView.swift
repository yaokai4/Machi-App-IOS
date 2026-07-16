import SwiftUI

/// 错题本 — questions the user last got wrong. Each is re-answerable: the review
/// payload already reveals `answerIndex`+`explanation`, so we grade locally for an
/// instant flip, and also record the attempt (`sourceKind=review`) so a now-correct
/// answer drops it from the book on the next load and counts toward the streak.
///
/// Compliance: original / licensed questions, not official past papers.
struct GuideJLPTReviewView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

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
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                Toggle(isOn: $levelFilterOn) {
                    HStack(spacing: KXSpacing.sm) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KXColor.livingAccent)
                        Text(guideText(language, "仅看 \(level.rawValue)", "\(level.rawValue) のみ", "\(level.rawValue) only"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.livingInk)
                    }
                }
                .tint(KXColor.livingAccent)
                .onChange(of: levelFilterOn) { _, _ in Task { await load() } }

                if levelFilterOn {
                    JLPTLevelPicker(selection: $level)
                        .onChange(of: level) { _, _ in Task { await load() } }
                }
            }
            .padding(14)
            .jlptSurface(radius: KXRadius.hero)

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
                // I1-4:重做揭晓后仍不懂,带着题干去 Machi AI 追问。
                if answered[q.id] != nil {
                    Button {
                        router.open(.guideAI(prompt: aiFollowUpPrompt(q)))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text(guideText(language, "继续问 Machi AI", "続けて Machi AI に質問", "Keep asking Machi AI"))
                        }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, KXSpacing.xs)
                    }
                    .buttonStyle(.plain)
                }
            }

            JLPTComplianceNote()
        }
        .padding(KXSpacing.lg)
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

    /// I1-4 预填提示词:题干截前 80 字(与练习页同口径)。
    private func aiFollowUpPrompt(_ q: KaiXJLPTQuestionDTO) -> String {
        let stem = String(q.stem.replacingOccurrences(of: "\n", with: " ").prefix(80))
        return guideText(language,
            "我在 JLPT \(q.level) 错题本里重做这道题：「\(stem)」，请帮我讲讲相关知识点，帮我彻底弄懂。",
            "JLPT \(q.level) の間違いノートでこの問題を解き直しています：「\(stem)」。関連する知識点を教えて、しっかり理解させてください。",
            "I'm redoing this question from my JLPT \(q.level) review book: \"\(stem)\". Please explain the underlying point so I really get it.")
    }
}
