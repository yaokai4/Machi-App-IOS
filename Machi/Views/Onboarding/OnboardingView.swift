import SwiftUI

/// First-run value proposition: 3 paged cards then a guest-first CTA, so a new
/// user understands what Machi IS (and can start browsing) BEFORE hitting any
/// login / captcha / email-code friction. Shown once (hasSeenOnboarding in
/// ContentView). "Browse first" is the primary CTA — registration is deferred to
/// the point of an action that genuinely needs an account.
struct OnboardingView: View {
    @Environment(\.appLanguage) private var language
    var onBrowseAsGuest: () -> Void
    var onContinueToAuth: () -> Void

    @State private var page = 0

    private struct Card: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
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

            VStack(spacing: 12) {
                Button(action: onBrowseAsGuest) {
                    Text(pick("先逛逛", "まず見てみる", "Browse first"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .kxPageBackground()
    }

    private func cardView(_ card: Card) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: card.icon)
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 124, height: 124)
                .background(
                    LinearGradient(colors: [card.tint, card.tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                )
                .shadow(color: card.tint.opacity(0.3), radius: 18, y: 10)
            VStack(spacing: 12) {
                Text(card.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
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
