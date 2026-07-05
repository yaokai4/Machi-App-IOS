import Combine
import SwiftUI

/// 首页「下一步该办什么」— a single compact hook above the feed that leads
/// into the Guide journey system. Logged-in users see their first unfinished
/// journey with real progress (/api/guide/progress); guests see the journey
/// suggested by their onboarding persona (`onboardingPersona` ->
/// `guideJourneyKey(forArrivalStage:)`). No data -> renders nothing.
/// Self-contained loader (GuideDigestCardView pattern) so it can never slow
/// down or entangle the feed — every fetch failure is silent.
@MainActor
final class HomeJourneyNextStepViewModel: ObservableObject {
    struct Hint: Equatable {
        let journeyKey: String
        let title: String
        let icon: String
        /// Progress counts (logged-in only); nil for the guest persona entry.
        let done: Int?
        let total: Int?
    }

    @Published private(set) var hint: Hint?

    func load(isGuest: Bool, persona: String) async {
        let loggedIn = !isGuest && KaiXBackend.token != nil
        // Guests without a persona journey can never show a hint — skip the
        // network entirely instead of fetching a list we'd throw away.
        if !loggedIn, guideJourneyKey(forArrivalStage: persona) == nil {
            hint = nil
            return
        }
        // Titles come from the localized journey list (public endpoint) so the
        // card matches the app language instead of a hardcoded key->title map.
        let language = guideLanguage()
        guard let journeys = try? await KaiXAPIClient.shared.guideJourneys(country: "jp", language: language).journeys,
              !journeys.isEmpty else { return }
        if loggedIn {
            guard let progress = try? await KaiXAPIClient.shared.guideProgress() else { return }
            guard let next = progress.summary.first(where: { $0.percent < 100 && $0.total > 0 }),
                  let journey = journeys.first(where: { $0.key == next.journeyKey }) else {
                hint = nil
                return
            }
            hint = Hint(journeyKey: journey.key, title: journey.title, icon: journey.icon, done: next.done, total: next.total)
        } else {
            guard let key = guideJourneyKey(forArrivalStage: persona),
                  let journey = journeys.first(where: { $0.key == key }) else {
                hint = nil
                return
            }
            hint = Hint(journeyKey: journey.key, title: journey.title, icon: journey.icon, done: nil, total: nil)
        }
    }

    /// Same resolution as GuideViewModel.currentGuideLanguage (private there).
    private func guideLanguage() -> String {
        switch AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? "") {
        case .ja: return "ja"
        case .en: return "en"
        case .zh, .system: return "zh-CN"
        }
    }
}

struct HomeJourneyNextStepCard: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = HomeJourneyNextStepViewModel()
    @AppStorage("onboardingPersona") private var onboardingPersona = ""

    let currentUser: UserEntity

    var body: some View {
        Group {
            if let hint = vm.hint {
                Button {
                    router.open(.guideJourney(key: hint.journeyKey), in: .home)
                } label: {
                    HStack(spacing: KXSpacing.md) {
                        Image(systemName: guideJourneySymbol(hint.icon))
                            .kxScaledFont(15, weight: .bold)
                            .foregroundStyle(KXColor.accent)
                            .frame(width: 36, height: 36)
                            .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                            Text(KXListingCopy.pickText(language, "下一步该办什么", "次にやること", "Next step"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(hint.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if let done = hint.done, let total = hint.total, total > 0 {
                            Text("\(done)/\(total)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(KXColor.accent)
                                .padding(.horizontal, KXSpacing.sm)
                                .frame(height: 22)
                                .background(KXColor.accentSoft, in: Capsule())
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(KXSpacing.md)
                    .contentShape(Rectangle())
                    .kxGlassSurface(radius: KXRadius.lg)
                }
                .buttonStyle(.fullArea)
            }
        }
        .task(id: currentUser.id) {
            await vm.load(isGuest: currentUser.isGuest, persona: onboardingPersona)
        }
    }
}
