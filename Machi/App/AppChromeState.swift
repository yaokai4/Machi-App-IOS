import Combine
import SwiftUI

enum AppChromeHiddenReason: Hashable {
    case route
    case compose
    case input
    case conversation
    case mediaPreview
    case postDetail
    case custom(String)
}

@MainActor
final class AppChromeState: ObservableObject {
    private static let persistedTabKey = "kx.selectedTab"

    @Published var selectedTab: AppTab = AppChromeState.restoredTab() {
        didSet { UserDefaults.standard.set(selectedTab.rawValue, forKey: Self.persistedTabKey) }
    }
    @Published private(set) var navigationDepthByTab: [AppTab: Int] = [:]
    @Published private(set) var hiddenReasons = Set<AppChromeHiddenReason>()

    /// Restore the last-selected tab across cold launches. Region and language
    /// were already persisted, but the tab wasn't — so a user who lived in
    /// 我的 / 消息 was always dropped back onto 首页 on relaunch. MainTabView reads
    /// `selectedTab` at startup to seed loadedTabs + the router, so restoring it
    /// here is enough. Falls back to .home for a fresh install / bad value.
    private static func restoredTab() -> AppTab {
        guard let raw = UserDefaults.standard.string(forKey: persistedTabKey),
              let tab = AppTab(rawValue: raw) else { return .home }
        return tab
    }

    var isTabBarHidden: Bool {
        !hiddenReasons.isEmpty
    }

    var bottomContentPadding: CGFloat {
        isTabBarHidden ? KXSpacing.lg : KaiXTheme.bottomContentPadding
    }

    func select(_ tab: AppTab) {
        // Signpost the switch so a janky tab transition is visible on the
        // Instruments Points-of-Interest track (120 Hz regression guardrail).
        KXPerf.event("tab.switch")
        selectedTab = tab
        restoreTopLevelChrome()
    }

    func setRouteHidden(_ hidden: Bool) {
        setHidden(hidden, reason: .route)
    }

    func setNavigationDepth(_ depth: Int, for tab: AppTab) {
        navigationDepthByTab[tab] = max(0, depth)
    }

    func setHidden(_ hidden: Bool, reason: AppChromeHiddenReason) {
        if hidden {
            hiddenReasons.insert(reason)
        } else {
            hiddenReasons.remove(reason)
        }
    }

    func clearTransientReasons() {
        hiddenReasons.remove(.input)
        hiddenReasons.remove(.compose)
        hiddenReasons.remove(.conversation)
        hiddenReasons.remove(.mediaPreview)
        hiddenReasons.remove(.postDetail)
    }

    func reset() {
        hiddenReasons.removeAll()
        navigationDepthByTab.removeAll()
        selectedTab = .home
    }

    func restoreTopLevelChrome() {
        hiddenReasons.remove(.compose)
        hiddenReasons.remove(.input)
        hiddenReasons.remove(.conversation)
        hiddenReasons.remove(.mediaPreview)
        hiddenReasons.remove(.postDetail)
    }
}

private struct KXHiddenTabBarModifier: ViewModifier {
    @EnvironmentObject private var chrome: AppChromeState
    let reason: AppChromeHiddenReason

    func body(content: Content) -> some View {
        content
            .onAppear {
                chrome.setHidden(true, reason: reason)
            }
            .onDisappear {
                chrome.setHidden(false, reason: reason)
            }
    }
}

extension View {
    func kxHidesTabBar(reason: AppChromeHiddenReason) -> some View {
        modifier(KXHiddenTabBarModifier(reason: reason))
    }

    /// Reserves scroll-past space under the floating glass tab bar.
    /// Apply to the *content* of any scrollable page that can show the
    /// tab bar, instead of a hard-coded `.padding(.bottom, N)` — the
    /// value collapses automatically when the bar is hidden.
    func kxTabBarSafeBottomPadding(extra: CGFloat = 0) -> some View {
        modifier(KXTabBarSafeBottomPaddingModifier(extra: extra))
    }
}

private struct KXTabBarSafeBottomPaddingModifier: ViewModifier {
    @EnvironmentObject private var chrome: AppChromeState
    var extra: CGFloat = 0

    func body(content: Content) -> some View {
        content.padding(.bottom, chrome.bottomContentPadding + extra)
    }
}
