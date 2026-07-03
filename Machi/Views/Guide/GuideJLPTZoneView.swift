import SwiftUI

/// JLPT 备考专区 (#4) — a curated prep hub (hero, N5–N1 levels, member-priced
/// resources / mock tests, roadmap articles, FAQ, and a study-plan CTA) backed
/// by `/api/guide/jlpt`. Replaces the generic category view for the `jlpt`
/// channel so JLPT reads as a real destination and a concrete membership payoff.
struct GuideJLPTZoneView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    @State private var zone: KaiXGuideJLPTZoneResponse?
    @State private var isLoading = true
    @State private var loadFailed = false

    private var serverLanguage: String {
        switch language {
        case .ja: return "ja"
        case .en: return "en"
        default: return "zh-CN"
        }
    }

    var body: some View {
        ScrollView {
            if isLoading && zone == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if let z = zone, z.status != "coming_soon" {
                content(z)
            } else {
                Text(loadFailed
                     ? guideText(language, "内容暂时无法加载，请稍后再试。", "コンテンツを読み込めません。後でもう一度お試しください。", "Content is temporarily unavailable. Please try again later.")
                     : guideText(language, "JLPT 专区即将开放。", "JLPT センターは近日公開。", "The JLPT center is coming soon."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            }
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle("JLPT")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ z: KaiXGuideJLPTZoneResponse) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Machi Guide · JLPT")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(KXColor.livingAccent)
                if let title = z.hero?.title {
                    Text(title).font(.title2.weight(.bold)).foregroundStyle(.primary)
                }
                if let subtitle = z.hero?.subtitle {
                    Text(subtitle).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
            }

            // 倒计时条 (hero) — 距下一场 JLPT 考试还有几天.
            if let countdown = z.jlptCore?.examCountdown {
                JLPTCountdownBar(countdown: countdown)
            }

            // 打卡 streak badge (signed-in only; server omits when signed out).
            if let streak = z.jlptCore?.streak, (streak.totalDays ?? 0) > 0 || (streak.currentStreak ?? 0) > 0 {
                JLPTStreakBadge(streak: streak)
            }

            // BE6 核心入口:定级 / 自测 / 我的单词 / 模拟考试.
            coreEntries(z.jlptCore)

            if let plan = z.studyPlan, let title = plan.title {
                Button {
                    router.open(.guidePlan)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(KXColor.livingAccent)
                            if let s = plan.subtitle {
                                Text(s).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.livingAccent)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let levels = z.levels, !levels.isEmpty {
                sectionHeader(guideText(language, "N5 – N1 等级", "N5〜N1 レベル", "N5 – N1 levels"))
                VStack(spacing: 8) {
                    ForEach(levels) { lv in
                        HStack(alignment: .top, spacing: 12) {
                            Text(lv.label)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(KXColor.livingAccent)
                                .frame(width: 42, height: 42)
                                .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(lv.summary)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .kxLivingSurface(radius: KXRadius.md)
                    }
                }
            }

            if let resources = z.resources, !resources.isEmpty {
                sectionHeader(guideText(language, "资料与模拟题", "資料・模擬問題", "Resources & mock tests"))
                VStack(spacing: 10) {
                    ForEach(resources) { GuideProductCard(product: $0) }
                }
            }

            if let articles = z.articles, !articles.isEmpty {
                sectionHeader(guideText(language, "备考路线与方法", "学習ロードマップ", "Roadmaps & methods"))
                VStack(spacing: 10) {
                    ForEach(articles) { GuideArticleCard(article: $0) }
                }
            }

            if let faq = z.faq, !faq.isEmpty {
                sectionHeader(guideText(language, "常见问题", "よくある質問", "FAQ"))
                VStack(spacing: 8) {
                    ForEach(faq) { item in
                        DisclosureGroup {
                            Text(item.answer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        } label: {
                            Text(item.question)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        .tint(KXColor.livingAccent)
                        .padding(12)
                        .kxLivingSurface(radius: KXRadius.md)
                    }
                }
            }

            if let disclaimer = z.disclaimer {
                Text(disclaimer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.headline.weight(.bold)).foregroundStyle(.primary)
    }

    /// BE6 核心练习入口. Cards route into the placement / practice / vocab / exam
    /// surfaces; disabled (dimmed) when the bank isn't seeded for that surface.
    @ViewBuilder
    private func coreEntries(_ core: KaiXJLPTZoneCore?) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                NavigationLink { GuideJLPTPlacementView() } label: {
                    coreCard(icon: "gauge.with.dots.needle.50percent",
                             title: guideText(language, "30 秒测水平", "30秒でレベル判定", "30-sec placement"),
                             subtitle: guideText(language, "定级 + 学习计划", "レベル判定＋計画", "Level + plan"),
                             enabled: core?.hasPlacement ?? true)
                }
                .buttonStyle(.plain)
                .disabled(!(core?.hasPlacement ?? true))

                NavigationLink { GuideJLPTPracticeView() } label: {
                    coreCard(icon: "square.and.pencil",
                             title: guideText(language, "开始自测", "問題演習", "Practice"),
                             subtitle: guideText(language, "分级分科题库", "レベル・科目別", "By level & section"),
                             enabled: core?.hasPractice ?? true)
                }
                .buttonStyle(.plain)
                .disabled(!(core?.hasPractice ?? true))
            }
            HStack(spacing: 10) {
                NavigationLink { GuideJLPTVocabView() } label: {
                    coreCard(icon: "character.book.closed.fill",
                             title: guideText(language, "我的单词", "単語", "Vocabulary"),
                             subtitle: guideText(language, "词表 + 考单词", "単語帳＋テスト", "Decks + quiz"),
                             enabled: core?.hasVocab ?? true)
                }
                .buttonStyle(.plain)
                .disabled(!(core?.hasVocab ?? true))

                NavigationLink { GuideJLPTExamView() } label: {
                    coreCard(icon: "checklist",
                             title: guideText(language, "模拟考试", "模擬試験", "Mock exams"),
                             subtitle: guideText(language, "限时组卷 + 成绩", "時間制限＋成績", "Timed + scored"),
                             enabled: core?.hasExams ?? true)
                }
                .buttonStyle(.plain)
                .disabled(!(core?.hasExams ?? true))
            }
            HStack(spacing: 10) {
                NavigationLink { GuideJLPTReviewView() } label: {
                    coreCard(icon: "arrow.uturn.backward.circle.fill",
                             title: guideText(language, "错题本", "間違いノート", "Review book"),
                             subtitle: guideText(language, "重练答错的题", "間違いを再演習", "Re-do wrong ones"),
                             enabled: core?.hasPractice ?? true)
                }
                .buttonStyle(.plain)
                .disabled(!(core?.hasPractice ?? true))

                // Balance the row when only one card remains.
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
            }
        }
    }

    private func coreCard(icon: String, title: String, subtitle: String, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(enabled ? KXColor.livingAccent : KXColor.livingMuted)
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? KXColor.livingInk : KXColor.livingMuted)
            Text(enabled ? subtitle : guideText(language, "即将开放", "近日公開", "Coming soon"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(KXColor.livingAccentSoft, lineWidth: 1))
        .opacity(enabled ? 1 : 0.6)
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            zone = try await KaiXAPIClient.shared.guideJLPTZone(country: "jp", language: serverLanguage)
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}
