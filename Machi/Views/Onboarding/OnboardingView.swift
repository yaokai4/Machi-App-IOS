import SwiftUI

/// First-run value proposition: 3 paged cards then a guest-first CTA, so a new
/// user understands what Machi IS (and can start browsing) BEFORE hitting any
/// login / captcha / email-code friction. Shown once (hasSeenOnboarding in
/// ContentView). "Browse first" is the primary CTA — registration is deferred to
/// the point of an action that genuinely needs an account.
struct OnboardingView: View {
    @Environment(\.appLanguage) private var language
    /// Raw `arrival_stage` contract value picked on the persona step
    /// (pre_arrival / just_arrived / first_year / long_term, "" = skipped).
    /// Read by ContentView (guest journey routing + profile sync on login)
    /// and HomeJourneyNextStepCard.
    @AppStorage("onboardingPersona") private var onboardingPersona = ""
    var onBrowseAsGuest: () -> Void
    var onContinueToAuth: () -> Void

    @State private var page = 0
    @State private var showPersonaStep = false

    private struct Card: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
    }

    private struct PersonaOption: Identifiable {
        let id: String // raw arrival_stage value
        let icon: String
        let title: String
        let subtitle: String
    }

    private var personaOptions: [PersonaOption] {
        [
            .init(id: "pre_arrival", icon: "airplane.departure",
                  title: pick("还没来日本", "これから日本へ", "Not in Japan yet"),
                  subtitle: pick("正在准备出发", "渡日を準備中", "Getting ready to come")),
            .init(id: "just_arrived", icon: "figure.wave",
                  title: pick("刚到日本", "来日したばかり", "Just arrived"),
                  subtitle: pick("3 个月内", "3ヶ月以内", "Within 3 months")),
            .init(id: "first_year", icon: "leaf.fill",
                  title: pick("来日 1 年内", "来日1年未満", "First year in Japan"),
                  subtitle: pick("正在安顿下来", "生活を整えている段階", "Settling in")),
            .init(id: "long_term", icon: "house.fill",
                  title: pick("来日 1 年以上", "来日1年以上", "Over a year in Japan"),
                  subtitle: pick("已经比较熟悉这里", "日本の生活にはもう慣れた", "Already know my way around")),
        ]
    }

    private var cards: [Card] {
        [
            .init(icon: "bubble.left.and.bubble.right.fill", tint: KXColor.accent,
                  title: pick("社区 · 本地生活", "コミュニティ・暮らし", "Community & local life"),
                  subtitle: pick("和在日的华人、留学生、外国人聊聊，看你所在城市正在发生什么。",
                                 "在日の仲間とつながり、街の「今」をチェック。",
                                 "Connect with people in Japan and see what's happening in your city.")),
            .init(icon: "book.pages.fill", tint: .blue,
                  title: pick("学校 · 公司 · 签证指南", "学校・企業・ビザガイド", "School, work & visa guide"),
                  subtitle: pick("升学、就职、签证、日语、在日生活——一步步带你查清楚、办明白。",
                                 "進学・就職・ビザ・日本語・生活を、順番に分かりやすく。",
                                 "Study, jobs, visa, Japanese, daily life — figured out step by step.")),
            .init(icon: "bag.fill", tint: .teal,
                  title: pick("二手 · 租房 · 工作", "中古・賃貸・求人", "Secondhand, housing & jobs"),
                  subtitle: pick("买卖二手、找房合租、找兼职工作，本地的事在这里办。",
                                 "売買・部屋探し・アルバイト探しもここで。",
                                 "Buy/sell, find a room, find work — local life, sorted.")),
        ]
    }

    var body: some View {
        Group {
            if showPersonaStep {
                personaStep
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                cardsStep
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .kxPageBackground()
    }

    private var cardsStep: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                    cardView(card).tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 7) {
                ForEach(0..<cards.count, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? KXColor.accent : Color.secondary.opacity(0.25))
                        .frame(width: i == page ? 22 : 7, height: 7)
                        .animation(.snappy(duration: 0.25), value: page)
                }
            }
            .padding(.bottom, 22)

            VStack(spacing: KXSpacing.md) {
                Button(action: {
                    // UI-test launches drive the app through the auth wall /
                    // -KXAutoGuest, never this step — but if a script ever taps
                    // "先逛逛", skip the persona question so scripted flows
                    // land straight in the app.
                    if KXRuntime.isUITesting {
                        onBrowseAsGuest()
                    } else {
                        withAnimation(.snappy(duration: 0.3)) { showPersonaStep = true }
                    }
                }) {
                    Text(pick("先逛逛", "まず見てみる", "Browse first"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(KXColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(KXColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.browseGuest")

                Button(action: onContinueToAuth) {
                    Text(pick("登录 / 注册", "ログイン / 登録", "Log in / Register"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KXColor.accent)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.toAuth")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    /// One optional question between "先逛逛" and the feed: which arrival stage
    /// the user is at. Picking an option personalizes the first screen (guests
    /// land on the matching Guide journey); "跳过" is always one tap away and
    /// enters the app exactly as before.
    private var personaStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: KXSpacing.md) {
                Text(pick("你现在处于哪个阶段？", "いまはどの段階ですか？", "Where are you right now?"))
                    .kxScaledFont(26, relativeTo: .title2, weight: .bold, design: .rounded)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(pick("选一个，首页和指南会先展示对你最有用的内容。",
                          "選ぶと、ホームとガイドがあなたに合う内容から表示されます。",
                          "Pick one and Home & Guide lead with what helps you most."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 36)

            VStack(spacing: KXSpacing.md) {
                ForEach(personaOptions) { option in
                    personaRow(option)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            Spacer()

            Button(action: onBrowseAsGuest) {
                Text(pick("跳过", "スキップ", "Skip"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(KXColor.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(KXColor.accentSoft, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.persona.skip")
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private func personaRow(_ option: PersonaOption) -> some View {
        Button {
            onboardingPersona = option.id
            onBrowseAsGuest()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.icon)
                    .kxScaledFont(18, weight: .bold)
                    .foregroundStyle(KXColor.accent)
                    .frame(width: 44, height: 44)
                    .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(option.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .kxGlassSurface(radius: KXRadius.lg)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.persona.\(option.id)")
    }

    private func cardView(_ card: Card) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: card.icon)
                .kxScaledFont(60, weight: .bold)
                .foregroundStyle(.white)
                .frame(width: 124, height: 124)
                .background(
                    LinearGradient(colors: [card.tint, card.tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                )
                .shadow(color: card.tint.opacity(0.3), radius: 18, y: 10)
            VStack(spacing: KXSpacing.md) {
                Text(card.title)
                    .kxScaledFont(26, relativeTo: .title2, weight: .bold, design: .rounded)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(card.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 36)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pick(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }
}
