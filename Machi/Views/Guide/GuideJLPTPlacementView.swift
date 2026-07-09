import SwiftUI

/// 30 秒测水平 — a short mixed-section placement quiz. Answers post to
/// `/placement/submit`, which returns a rule-based recommended level, per-section
/// accuracy, weak sections, and a suggested daily study time. From the result the
/// user can jump into that level's practice or generate a study plan.
///
/// Compliance: placement questions are Machi original / licensed, not official
/// past papers (see `JLPTComplianceNote`).
struct GuideJLPTPlacementView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    @State private var questions: [KaiXJLPTQuestionDTO] = []
    @State private var answers: [String: Int] = [:]   // questionId -> selectedIndex
    @State private var result: KaiXJLPTPlacementResult?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var submitting = false
    @State private var submitFailed = false

    var body: some View {
        ScrollView {
            if isLoading {
                JLPTStateView(title: guideText(language, "正在准备定级题…", "レベル判定を準備中…", "Preparing the placement quiz…"),
                              isLoading: true)
            } else if loadFailed {
                JLPTStateView(systemImage: "wifi.slash",
                              title: guideText(language, "加载失败", "読み込みに失敗しました", "Couldn't load"),
                              actionTitle: guideText(language, "重试", "再試行", "Retry"),
                              action: { Task { await load() } })
            } else if let result {
                resultView(result)
            } else if questions.isEmpty {
                JLPTStateView(systemImage: "tray",
                              title: guideText(language, "暂无定级题目", "判定用の問題がまだありません", "No placement questions yet"),
                              message: guideText(language, "题库补充后即可开始定级。", "問題が追加されると判定できます。", "Placement opens once the bank is filled."))
            } else {
                quizView
            }
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(guideText(language, "定级测试", "レベル判定", "Placement"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: quiz

    private var answeredCount: Int { answers.count }
    private var allAnswered: Bool { answeredCount >= questions.count && !questions.isEmpty }

    private var quizView: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(KXColor.livingAccent)
                        .frame(width: 42, height: 42)
                        .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    Text(guideText(language, "凭直觉作答，不会做就跳过——我们据此推荐等级。",
                                   "直感で回答してください。分からなければ飛ばしてOK。結果からレベルを提案します。",
                                   "Answer by instinct; skip what you don't know. We recommend a level from your answers."))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(KXColor.livingMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: KXSpacing.sm) {
                    ProgressView(value: Double(answeredCount), total: Double(max(1, questions.count)))
                        .tint(KXColor.livingAccent)
                    Text("\(answeredCount)/\(questions.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(KXColor.livingMuted)
                }
            }
            .padding(KXSpacing.lg)
            .jlptSurface(radius: KXRadius.hero)

            ForEach(Array(questions.enumerated()), id: \.element.id) { idx, q in
                JLPTQuestionCard(
                    question: q,
                    index: idx,
                    total: questions.count,
                    selectedIndex: Binding(
                        get: { answers[q.id] },
                        set: { if let v = $0 { answers[q.id] = v } }
                    ),
                    revealed: false,
                    correctIndex: nil,
                    explanation: nil
                )
            }

            if submitFailed {
                HStack(alignment: .top, spacing: KXSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(KXColor.livingWarm)
                    Text(guideText(language, "提交失败，请检查网络后重试——你的答案已保留。",
                                   "提出に失敗しました。通信を確認して再試行してください。回答は保持されています。",
                                   "Submit failed. Check your connection and try again — your answers are kept."))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KXColor.livingInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(13)
                .background(KXColor.livingWarm.opacity(0.10), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.livingWarm.opacity(0.24), lineWidth: 0.8))
            }

            JLPTPrimaryButton(
                title: submitFailed
                    ? guideText(language, "重试提交", "再試行", "Retry submit")
                    : guideText(language, "提交并查看结果", "提出して結果を見る", "Submit & see result"),
                icon: submitFailed ? "arrow.clockwise" : "checkmark.circle.fill",
                loading: submitting,
                enabled: answeredCount > 0,
                action: { Task { await submit() } })

            JLPTComplianceNote()
        }
        .padding(KXSpacing.lg)
    }

    // MARK: result

    @ViewBuilder
    private func resultView(_ r: KaiXJLPTPlacementResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // 级别大徽章 hero.
            VStack(spacing: KXSpacing.md) {
                JLPTEyebrow(text: guideText(language, "定级结果", "判定結果", "Your level"))
                JLPTLevelBadge(level: r.recommendedLevel ?? "N5", size: 92)
                Text(guideText(language, "推荐备考等级", "おすすめ学習レベル", "Recommended level"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KXColor.livingMuted)
                Text(JLPTLevel.from(r.recommendedLevel).tierName(language))
                    .font(.title.weight(.black))
                    .foregroundStyle(KXColor.livingInk)
                if let mins = r.suggestedDailyMinutes {
                    Label(guideText(language, "建议每天约 \(mins) 分钟", "1日あたり約 \(mins) 分", "~\(mins) min/day"),
                          systemImage: "clock.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                        .padding(.horizontal, KXSpacing.md).padding(.vertical, 7)
                        .background(KXColor.livingAccentSoft, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .jlptSurface(radius: KXRadius.sheet, elevated: true)

            if let breakdown = r.sectionBreakdown, !breakdown.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    JLPTSectionHeader(title: guideText(language, "各部分正确率", "セクション別正答率", "Accuracy by section"))
                    ForEach(breakdown) { s in
                        JLPTAccuracyBar(label: s.label ?? s.section,
                                        accuracy: s.accuracy ?? 0,
                                        total: s.total ?? 0,
                                        correct: s.correct ?? 0)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .jlptSurface(radius: KXRadius.hero)
            }

            if let weak = r.weakSections, !weak.isEmpty {
                let names = weak.compactMap { code in JLPTSection(rawValue: code)?.label(language) }
                if !names.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "target")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.livingWarm)
                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                            Text(guideText(language, "薄弱环节", "弱点", "Focus areas"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KXColor.livingWarm)
                            Text(names.joined(separator: "、"))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(KXColor.livingInk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(KXColor.livingWarm.opacity(0.09), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.livingWarm.opacity(0.22), lineWidth: 0.8))
                }
            }

            VStack(spacing: 10) {
                NavigationLink {
                    GuideJLPTPracticeView(initialLevel: JLPTLevel.from(r.recommendedLevel))
                } label: {
                    ctaLabel(icon: "play.fill",
                             title: guideText(language, "开始 \(r.recommendedLevel ?? "N5") 题库练习",
                                              "\(r.recommendedLevel ?? "N5") の練習を始める",
                                              "Start \(r.recommendedLevel ?? "N5") practice"),
                             filled: true)
                }
                .buttonStyle(KXPressableStyle(scale: 0.98))

                Button {
                    // 「生成学习计划」必须落到学习计划生成器:此前错落到 .guidePlan
                    // (普通 Todo 列表),定级→学习计划的核心转化链路断裂。
                    router.open(.guideStudyPlan(level: r.recommendedLevel), in: .guide)
                } label: {
                    ctaLabel(icon: "calendar",
                             title: guideText(language, "生成学习计划", "学習計画を作る", "Generate study plan"),
                             filled: false)
                }
                .buttonStyle(KXPressableStyle(scale: 0.98))

                Button {
                    result = nil
                    answers = [:]
                    submitFailed = false
                    Task { await load() }
                } label: {
                    Text(guideText(language, "重新测一次", "もう一度測る", "Test again"))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(KXColor.livingMuted)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            JLPTComplianceNote()
        }
        .padding(KXSpacing.lg)
    }

    private func ctaLabel(icon: String, title: String, filled: Bool) -> some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: icon).font(.subheadline.weight(.bold))
            Text(title).font(.subheadline.weight(.bold))
            Spacer(minLength: 0)
            Image(systemName: "arrow.right").font(.subheadline.weight(.bold))
        }
        .foregroundStyle(filled ? KXColor.onAccent : KXColor.livingAccent)
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(filled ? KXColor.livingAccent : KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(filled ? Color.clear : JLPTStyle.accentRim, lineWidth: 0.8))
        .shadow(color: filled ? KXColor.livingAccent.opacity(0.22) : .clear, radius: 9, y: 3)
    }

    // MARK: data

    private func load() async {
        isLoading = true
        loadFailed = false
        submitFailed = false
        do {
            let resp = try await KaiXAPIClient.shared.jlptPlacementStart()
            questions = resp.questions ?? []
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func submit() async {
        guard !submitting else { return }
        submitting = true
        submitFailed = false
        defer { submitting = false }
        let payload = answers.map { KaiXJLPTPlacementAnswer(questionId: $0.key, selectedIndex: $0.value) }
        do {
            result = try await KaiXAPIClient.shared.jlptPlacementSubmit(answers: payload)
        } catch {
            // Keep the quiz (and the user's answers) visible; surface a retryable
            // inline error instead of masking everything with the full-screen
            // load-failed state, which would discard the completed quiz.
            submitFailed = true
        }
    }
}
