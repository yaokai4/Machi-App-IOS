import SwiftUI

/// 开始自测 — pick a level + section, draw a batch of questions, answer one at a
/// time. Submitting a question grades it server-side (`/attempt`), flips the card
/// to reveal the answer + explanation, and unlocks a member "AI 讲解" button
/// (`/explain`). Runs through the batch, then offers a fresh batch.
///
/// Compliance: original / licensed questions, not official past papers.
struct GuideJLPTPracticeView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    var initialLevel: JLPTLevel = .n5

    @State private var level: JLPTLevel = .n5
    @State private var section: JLPTSection = .all
    @State private var questions: [KaiXJLPTQuestionDTO] = []
    @State private var cursor = 0
    @State private var membershipActive = false

    // per-question state
    @State private var selectedIndex: Int?
    @State private var revealed = false
    @State private var correctIndex: Int?
    @State private var explanation: String?
    @State private var aiExplanation: String?
    @State private var explaining = false

    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var submitting = false
    @State private var submitFailed = false
    @State private var sessionId = UUID().uuidString
    @State private var upgradeMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                content
            }
            .padding(16)
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(guideText(language, "题库自测", "問題演習", "Practice"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            level = initialLevel
            await load()
        }
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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            JLPTLevelPicker(selection: $level)
            JLPTSectionPicker(selection: $section)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jlptSurface(radius: KXRadius.hero)
        .onChange(of: level) { _, _ in Task { await load() } }
        .onChange(of: section) { _, _ in Task { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            JLPTStateView(title: guideText(language, "正在抽题…", "問題を取得中…", "Drawing questions…"), isLoading: true)
                .frame(minHeight: 320)
        } else if loadFailed {
            JLPTStateView(systemImage: "wifi.slash",
                          title: guideText(language, "加载失败", "読み込みに失敗しました", "Couldn't load"),
                          actionTitle: guideText(language, "重试", "再試行", "Retry"),
                          action: { Task { await load() } })
                .frame(minHeight: 320)
        } else if questions.isEmpty {
            JLPTStateView(systemImage: "tray",
                          title: guideText(language, "该范围暂无题目", "この範囲の問題はまだありません", "No questions in this scope"),
                          message: guideText(language, "换个等级或科目试试。", "レベルや科目を変えてみてください。", "Try another level or section."))
                .frame(minHeight: 320)
        } else if cursor >= questions.count {
            batchDoneView
        } else {
            questionArea
        }
    }

    private var currentQuestion: KaiXJLPTQuestionDTO? {
        cursor < questions.count ? questions[cursor] : nil
    }

    @ViewBuilder
    private var questionArea: some View {
        if let q = currentQuestion {
            VStack(alignment: .leading, spacing: 16) {
                JLPTQuestionCard(
                    question: q,
                    index: cursor,
                    total: questions.count,
                    selectedIndex: $selectedIndex,
                    revealed: revealed,
                    correctIndex: correctIndex,
                    explanation: explanation,
                    onExplain: { Task { await explain(q) } },
                    isMember: membershipActive,
                    explaining: explaining,
                    explanationText: aiExplanation
                )

                if !revealed {
                    JLPTPrimaryButton(
                        title: guideText(language, "提交", "回答する", "Submit"),
                        icon: "paperplane.fill",
                        loading: submitting,
                        enabled: selectedIndex != nil,
                        action: { Task { await submitAnswer(q) } })
                    if submitFailed {
                        Text(guideText(language, "提交失败,请检查网络后重试。", "送信に失敗しました。接続を確認して再試行してください。", "Submit failed — check your connection and try again."))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    JLPTPrimaryButton(
                        title: cursor + 1 < questions.count
                            ? guideText(language, "下一题", "次の問題", "Next")
                            : guideText(language, "完成本组", "このセットを終える", "Finish set"),
                        trailingArrow: true,
                        action: advance)
                }

                JLPTComplianceNote()
            }
        }
    }

    private var batchDoneView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(KXColor.livingAccentSoft).frame(width: 76, height: 76)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(KXColor.livingAccent)
            }
            Text(guideText(language, "本组已完成！", "このセットが完了！", "Set complete!"))
                .font(.title3.weight(.bold))
                .foregroundStyle(KXColor.livingInk)
            Text(guideText(language, "保持节奏，连续打卡更容易上分。", "この調子で続けましょう。", "Keep the streak going."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: { Task { await load() } }) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.clockwise").font(.subheadline.weight(.bold))
                    Text(guideText(language, "再来一组", "もう一セット", "Another set"))
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(KXColor.onAccent)
                .padding(.horizontal, 24).padding(.vertical, 13)
                .background(KXColor.livingAccent, in: Capsule())
                .shadow(color: KXColor.livingAccent.opacity(0.24), radius: 8, y: 3)
            }
            .buttonStyle(KXPressableStyle(scale: 0.96))
            NavigationLink {
                GuideJLPTReviewView(initialLevel: level)
            } label: {
                Text(guideText(language, "去错题本", "間違いノートへ", "Review book"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(KXColor.livingAccent)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: data

    private func resetQuestionState() {
        selectedIndex = nil
        revealed = false
        correctIndex = nil
        explanation = nil
        aiExplanation = nil
        explaining = false
        submitFailed = false
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        cursor = 0
        sessionId = UUID().uuidString
        resetQuestionState()
        do {
            let resp = try await KaiXAPIClient.shared.jlptPractice(level: level.rawValue, section: section.wire)
            questions = resp.questions ?? []
            membershipActive = resp.membershipActive ?? false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func submitAnswer(_ q: KaiXJLPTQuestionDTO) async {
        guard let sel = selectedIndex, !submitting else { return }
        submitting = true
        submitFailed = false
        defer { submitting = false }
        do {
            let result = try await KaiXAPIClient.shared.jlptAttempt(
                questionId: q.id, selectedIndex: sel, sessionId: sessionId, sourceKind: "practice")
            correctIndex = result.correctIndex
            explanation = result.explanation
            revealed = true
        } catch {
            // We can't grade locally (practice never ships the answer key), so
            // surface a retryable error instead of silently swallowing it — the
            // card stays on the question with the Submit button live, and a
            // visible "submit failed, retry" hint tells the user why nothing
            // happened. (Reusing `loadFailed` here would tear down the whole
            // question area into the full-screen retry state and lose the card.)
            submitFailed = true
        }
    }

    private func advance() {
        cursor += 1
        resetQuestionState()
    }

    private func explain(_ q: KaiXJLPTQuestionDTO) async {
        guard !explaining else { return }
        explaining = true
        defer { explaining = false }
        do {
            let resp = try await KaiXAPIClient.shared.jlptExplain(questionId: q.id, language: serverLanguage)
            aiExplanation = resp.explanation
        } catch let err as KaiXAPIError {
            let code = err.error.code
            if code == "AI_QUOTA_EXCEEDED" || code == "http_403" || code.contains("QUOTA") || code == "MEMBER_REQUIRED" {
                upgradeMessage = guideText(language,
                    "今日免费讲解已用完，开通会员即可无限次 AI 讲解并使用 Pro 模型。",
                    "本日の無料解説が上限に達しました。会員になると AI 解説が無制限＆Proモデルになります。",
                    "You've used today's free explanations. Membership unlocks unlimited AI explanations on the Pro model.")
            } else {
                upgradeMessage = err.error.message
            }
        } catch {
            upgradeMessage = guideText(language, "讲解暂时不可用，请稍后再试。", "解説は現在利用できません。", "Explanation is unavailable right now.")
        }
    }

    private var serverLanguage: String {
        switch language {
        case .ja: return "ja"
        case .en: return "en"
        default: return "zh-CN"
        }
    }
}
