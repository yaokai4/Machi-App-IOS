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
    @Published var selectedTab: AppTab = .home
    @Published private(set) var navigationDepthByTab: [AppTab: Int] = [:]
    @Published private(set) var hiddenReasons = Set<AppChromeHiddenReason>()

    var isTabBarHidden: Bool {
        !hiddenReasons.isEmpty
    }

    var bottomContentPadding: CGFloat {
        isTabBarHidden ? KXSpacing.lg : KaiXTheme.bottomContentPadding
    }

    func select(_ tab: AppTab) {
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
}
