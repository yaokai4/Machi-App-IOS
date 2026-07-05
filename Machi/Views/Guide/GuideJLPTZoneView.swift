import SwiftUI

/// JLPT 备考专区 (#4) — a curated prep hub (hero, N5–N1 levels, member-priced
/// resources / mock tests, roadmap articles, FAQ, and a study-plan CTA) backed
/// by `/api/guide/jlpt`. Replaces the generic category view for the `jlpt`
/// channel so JLPT reads as a real destination and a concrete membership payoff.
///
/// 视觉方向「考场里的静气」: hero 带极淡「日本語」kana 水印,暖火 streak 胶囊,
/// 近7天周条;入口 2 列网格(定级=主行动);N5–N1 等级阶梯带难度计。
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
                JLPTStateView(title: guideText(language, "正在加载 JLPT 专区…", "JLPT センターを読み込み中…", "Loading JLPT center…"),
                              isLoading: true)
                    .frame(minHeight: 420)
            } else if let z = zone, z.status != "coming_soon" {
                content(z)
            } else {
                JLPTStateView(
                    systemImage: loadFailed ? "wifi.slash" : "graduationcap",
                    title: loadFailed
                        ? guideText(language, "内容暂时无法加载", "コンテンツを読み込めません", "Content unavailable right now")
                        : guideText(language, "JLPT 专区即将开放", "JLPT センターは近日公開", "The JLPT center is coming soon"),
                    message: loadFailed
                        ? guideText(language, "请检查网络后重试。", "通信を確認して再試行してください。", "Check your connection and try again.")
                        : nil,
                    actionTitle: loadFailed ? guideText(language, "重试", "再試行", "Retry") : nil,
                    action: loadFailed ? { Task { await load() } } : nil)
                    .frame(minHeight: 420)
            }
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle("JLPT")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ z: KaiXGuideJLPTZoneResponse) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            heroCard(z)

            // 倒计时条 — 距下一场 JLPT 考试还有几天.
            if let countdown = z.jlptCore?.examCountdown {
                JLPTCountdownBar(countdown: countdown)
            }

            // 打卡 streak card (signed-in only; server omits when signed out).
            if let streak = z.jlptCore?.streak, (streak.totalDays ?? 0) > 0 || (streak.currentStreak ?? 0) > 0 {
                JLPTStreakBadge(streak: streak)
            }

            // BE6 核心入口:定级 / 自测 / 我的单词 / 模拟考试 + 错题本 / 考试日历.
            practiceSection(z.jlptCore)

            if let plan = z.studyPlan, let title = plan.title {
                studyPlanCTA(title: title, subtitle: plan.subtitle)
            }

            if let levels = z.levels, !levels.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    JLPTSectionHeader(title: guideText(language, "N5 – N1 等级阶梯", "N5〜N1 レベル", "N5 – N1 levels"))
                    VStack(spacing: KXSpacing.sm) {
                        ForEach(levels) { lv in levelRow(lv) }
                    }
                }
            }

            if let resources = z.resources, !resources.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    JLPTSectionHeader(title: guideText(language, "资料与模拟题", "資料・模擬問題", "Resources & mock tests"))
                    VStack(spacing: 10) {
                        ForEach(resources) { GuideProductCard(product: $0) }
                    }
                }
            }

            if let articles = z.articles, !articles.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    JLPTSectionHeader(title: guideText(language, "备考路线与方法", "学習ロードマップ", "Roadmaps & methods"))
                    VStack(spacing: 10) {
                        ForEach(articles) { GuideArticleCard(article: $0) }
                    }
                }
            }

            if let faq = z.faq, !faq.isEmpty {
                VStack(alignment: .leading, spacing: KXSpacing.md) {
                    JLPTSectionHeader(title: guideText(language, "常见问题", "よくある質問", "FAQ"))
                    VStack(spacing: KXSpacing.sm) {
                        ForEach(faq) { item in faqRow(item) }
                    }
                }
            }

            if let disclaimer = z.disclaimer {
                JLPTComplianceNote(text: disclaimer)
            }
        }
        .padding(KXSpacing.lg)
    }

    // MARK: Hero

    @ViewBuilder
    private func heroCard(_ z: KaiXGuideJLPTZoneResponse) -> some View {
        ZStack(alignment: .topLeading) {
            // 极淡「日本語」kana 水印 — sits bottom-trailing, barely there.
            Text("日本語")
                .kxScaledFont(96, weight: .black)
                .foregroundStyle(KXColor.livingAccent.opacity(0.05))
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .offset(x: 18, y: 14)
                .clipped()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    JLPTEyebrow(text: "Machi Guide · JLPT")
                    Spacer(minLength: 0)
                    if let streak = z.jlptCore?.streak,
                       (streak.currentStreak ?? 0) > 0 {
                        JLPTStreakBadge(streak: streak, compact: true)
                    }
                }
                if let title = z.hero?.title {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(KXColor.livingInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(guideText(language, "JLPT 备考专区", "JLPT 対策センター", "JLPT prep center"))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(KXColor.livingInk)
                }
                if let subtitle = z.hero?.subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(KXColor.livingMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(KXSpacing.xl)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KXRadius.sheet, style: .continuous).stroke(JLPTStyle.hairline, lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 6)
    }

    // MARK: 练起来 — 2-col entry grid + ghost chips

    @ViewBuilder
    private func practiceSection(_ core: KaiXJLPTZoneCore?) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            JLPTSectionHeader(title: guideText(language, "练起来", "さっそく練習", "Start practicing"))

            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                NavigationLink { GuideJLPTPlacementView() } label: {
                    entryCard(icon: "gauge.with.dots.needle.50percent",
                              title: guideText(language, "30 秒测水平", "30秒でレベル判定", "30-sec placement"),
                              subtitle: guideText(language, "定级 + 学习计划", "レベル判定＋計画", "Level + plan"),
                              primary: true,
                              enabled: core?.hasPlacement ?? true)
                }
                .buttonStyle(KXPressableStyle(scale: 0.97))
                .disabled(!(core?.hasPlacement ?? true))

                NavigationLink { GuideJLPTPracticeView() } label: {
                    entryCard(icon: "square.and.pencil",
                              title: guideText(language, "开始自测", "問題演習", "Practice"),
                              subtitle: guideText(language, "分级分科题库", "レベル・科目別", "By level & section"),
                              primary: false,
                              enabled: core?.hasPractice ?? true)
                }
                .buttonStyle(KXPressableStyle(scale: 0.97))
                .disabled(!(core?.hasPractice ?? true))

                NavigationLink { GuideJLPTVocabView() } label: {
                    entryCard(icon: "character.book.closed.fill",
                              title: guideText(language, "我的单词", "単語", "Vocabulary"),
                              subtitle: guideText(language, "词表 + 考单词", "単語帳＋テスト", "Decks + quiz"),
                              primary: false,
                              enabled: core?.hasVocab ?? true)
                }
                .buttonStyle(KXPressableStyle(scale: 0.97))
                .disabled(!(core?.hasVocab ?? true))

                NavigationLink { GuideJLPTExamView() } label: {
                    entryCard(icon: "checklist",
                              title: guideText(language, "模拟考试", "模擬試験", "Mock exams"),
                              subtitle: guideText(language, "限时组卷 + 成绩", "時間制限＋成績", "Timed + scored"),
                              primary: false,
                              enabled: core?.hasExams ?? true)
                }
                .buttonStyle(KXPressableStyle(scale: 0.97))
                .disabled(!(core?.hasExams ?? true))
            }

            HStack(spacing: KXSpacing.sm) {
                NavigationLink { GuideJLPTReviewView() } label: {
                    ghostChip(icon: "arrow.uturn.backward", title: guideText(language, "错题本", "間違いノート", "Review book"))
                }
                .buttonStyle(KXPressableStyle(scale: 0.96))

                Button {
                    router.open(.guideCalendar, in: .guide)
                } label: {
                    ghostChip(icon: "calendar", title: guideText(language, "考试日历", "試験カレンダー", "Exam calendar"))
                }
                .buttonStyle(KXPressableStyle(scale: 0.96))
            }
        }
    }

    private func entryCard(icon: String, title: String, subtitle: String, primary: Bool, enabled: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                // 定级 = 主行动: 填充青图标 tile(白图标). 其余: accent-soft tile + 青图标.
                Image(systemName: icon)
                    .kxScaledFont(18, weight: .semibold)
                    .foregroundStyle(enabled ? (primary ? KXColor.onAccent : KXColor.livingAccent) : KXColor.livingMuted)
                    .frame(width: 40, height: 40)
                    .background(
                        (enabled && primary ? KXColor.livingAccent : KXColor.livingAccentSoft),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                Spacer(minLength: 4)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(enabled ? KXColor.livingInk : KXColor.livingMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(enabled ? subtitle : guideText(language, "即将开放", "近日公開", "Coming soon"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(KXColor.livingMuted)
                .frame(width: 22, height: 22)
                .background(KXColor.livingSoft, in: Circle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(
            (primary && enabled ? KXColor.livingAccentSoft : KXColor.livingSurface),
            in: RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous)
                .stroke(primary && enabled ? JLPTStyle.accentRim : JLPTStyle.hairline, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 6, y: 2)
        .opacity(enabled ? 1 : 0.62)
    }

    private func ghostChip(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption.weight(.bold))
            Text(title).font(.caption.weight(.bold))
        }
        .foregroundStyle(KXColor.livingAccent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(KXColor.livingSurface, in: Capsule())
        .overlay(Capsule().stroke(JLPTStyle.accentRim, lineWidth: 0.9))
    }

    // MARK: 学习计划 CTA — 青渐变横幅

    private func studyPlanCTA(title: String, subtitle: String?) -> some View {
        Button {
            router.open(.guidePlan)
        } label: {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: "map.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(KXColor.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.onAccent)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(KXColor.onAccent.opacity(0.82))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.onAccent)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [KXColor.livingAccent, KXColor.livingAccent.opacity(0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous)
            )
            .shadow(color: KXColor.livingAccent.opacity(0.28), radius: 12, y: 5)
        }
        .buttonStyle(KXPressableStyle(scale: 0.98))
    }

    // MARK: N5–N1 等级阶梯

    private func levelRow(_ lv: KaiXGuideJLPTLevelDTO) -> some View {
        let level = JLPTLevel.from(lv.key)
        return HStack(alignment: .center, spacing: KXSpacing.md) {
            // 徽章 — 底色按难度逐级加深一点点.
            Text(lv.label)
                .kxScaledFont(17, weight: .black, design: .rounded)
                .foregroundStyle(KXColor.livingAccent)
                .frame(width: 46, height: 46)
                .background(level.badgeTint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(JLPTStyle.accentRim, lineWidth: 0.8))

            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                HStack(spacing: KXSpacing.sm) {
                    Text(level.tierName(language))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.livingInk)
                    difficultyMeter(tier: level.tier)
                }
                Text(lv.summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .jlptSurface(radius: KXRadius.hero)
    }

    private func difficultyMeter(tier: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle()
                    .fill(i <= tier ? KXColor.livingAccent : KXColor.livingSoft)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel(guideText(language, "难度 \(tier) / 5", "難易度 \(tier) / 5", "Difficulty \(tier) of 5"))
    }

    // MARK: FAQ

    private func faqRow(_ item: KaiXGuideFaqDTO) -> some View {
        DisclosureGroup {
            Text(item.answer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, KXSpacing.sm)
        } label: {
            Text(item.question)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(KXColor.livingInk)
        }
        .tint(KXColor.livingAccent)
        .padding(14)
        .jlptSurface(radius: KXRadius.hero)
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
