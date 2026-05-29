import SwiftUI

struct MainTabView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var composeStore: ComposeStore
    let currentUser: UserEntity
    let onLogout: () -> Void
    let onSwitchAccount: (UserEntity) -> Void

    @State private var isShowingComposer = false
    @State private var presetComposeType: ContentType?
    @State private var feedRefreshToken = UUID()
    @State private var profileRefreshToken = UUID()
    @State private var loadedTabs: Set<AppTab> = [.home]

    private var selectedTab: Binding<AppTab> {
        Binding {
            chrome.selectedTab
        } set: { tab in
            withAnimation(.snappy(duration: 0.2)) {
                loadedTabs.insert(tab)
                chrome.select(tab)
                router.setActiveTab(tab)
                syncChromeForActiveRoute()
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(AppTab.allCases) { tab in
                if loadedTabs.contains(tab) {
                    tabContent(tab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .opacity(chrome.selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(chrome.selectedTab == tab)
                        .accessibilityHidden(chrome.selectedTab != tab)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if !chrome.isTabBarHidden {
                BottomTabBarView(selection: selectedTab, currentUser: currentUser)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: chrome.isTabBarHidden)
        .onAppear {
            loadedTabs.insert(chrome.selectedTab)
            router.setActiveTab(chrome.selectedTab)
            syncChromeForActiveRoute()
        }
        .onChange(of: chrome.selectedTab) { _, tab in
            loadedTabs.insert(tab)
            router.setActiveTab(tab)
            chrome.setNavigationDepth(router.pathCount(for: tab), for: tab)
            syncChromeForActiveRoute()
        }
        .onChange(of: router.routeRevision) { _, _ in
            chrome.setNavigationDepth(router.pathCount(for: chrome.selectedTab), for: chrome.selectedTab)
            syncChromeForActiveRoute()
        }
        .onChange(of: isShowingComposer) { _, isPresented in
            chrome.setHidden(isPresented, reason: .compose)
            if !isPresented { presetComposeType = nil }
        }
        .onChange(of: composeStore.pendingComposeContentType) { _, newType in
            // Channel empty-states / discover shortcuts use this
            // channel to ask the host to open the composer with a
            // specific ContentType pre-selected. We consume the
            // request immediately by clearing the store and flipping
            // the cover binding.
            if let newType {
                presetComposeType = newType
                composeStore.pendingComposeContentType = nil
                isShowingComposer = true
            }
        }
        .fullScreenCover(isPresented: $isShowingComposer, onDismiss: {
            chrome.setHidden(false, reason: .compose)
            presetComposeType = nil
        }) {
            ComposePostView(currentUser: currentUser, initialContentType: presetComposeType) {
                feedRefreshToken = UUID()
                profileRefreshToken = UUID()
                chrome.select(.home)
            }
        }
    }

    private func syncChromeForActiveRoute() {
        chrome.setRouteHidden(router.requiresHiddenChrome(for: chrome.selectedTab))
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .home:
            NavigationStack(path: router.binding(for: .home)) {
                HomeTimelineView(
                    currentUser: currentUser,
                    selectedTab: selectedTab,
                    isShowingComposer: $isShowingComposer,
                    refreshToken: feedRefreshToken,
                    onLogout: onLogout,
                    onSwitchAccount: onSwitchAccount
                )
                .kxRouteDestinations(currentUser: currentUser)
            }
        case .search:
            NavigationStack(path: router.binding(for: .search)) {
                DiscoverView(currentUser: currentUser)
                    .kxRouteDestinations(currentUser: currentUser)
            }
        case .notifications:
            NavigationStack(path: router.binding(for: .notifications)) {
                NotificationsView(currentUser: currentUser)
                    .kxRouteDestinations(currentUser: currentUser)
            }
        case .messages:
            NavigationStack(path: router.binding(for: .messages)) {
                MessagesView(currentUser: currentUser)
                    .kxRouteDestinations(currentUser: currentUser)
            }
        case .profile:
            NavigationStack(path: router.binding(for: .profile)) {
                ProfileView(
                    currentUser: currentUser,
                    refreshToken: profileRefreshToken,
                    onLogout: onLogout,
                    onSwitchAccount: onSwitchAccount
                )
                    .kxRouteDestinations(currentUser: currentUser)
            }
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case search
    case notifications
    case messages
    case profile

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .home: L("home", language)
        case .search: L("discover", language)
        case .notifications: L("notifications", language)
        case .messages: L("messages", language)
        case .profile: L("me", language)
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .search: "safari.fill"
        case .notifications: "bell.fill"
        case .messages: "envelope"
        case .profile: "person.crop.circle.fill"
        }
    }
}
