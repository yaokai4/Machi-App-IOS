import SwiftUI

struct MainTabView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var composeStore: ComposeStore
    @ObservedObject private var regionStore = RegionStore.shared
    let currentUser: UserEntity
    let onLogout: () -> Void
    let onSwitchAccount: (UserEntity) -> Void

    @State private var isShowingComposer = false
    @State private var presetComposeType: ContentType?
    @State private var feedRefreshToken = UUID()
    @State private var profileRefreshToken = UUID()
    @State private var loadedTabs: Set<AppTab> = [.home]
    #if DEBUG
    @State private var debugPushScreen: KXDebugScreen?
    #endif

    private var selectedTab: Binding<AppTab> {
        Binding {
            chrome.selectedTab
        } set: { tab in
            withAnimation(.snappy(duration: 0.2)) {
                if chrome.selectedTab == tab {
                    // Re-tapping the tab you are already on pops that tab's
                    // navigation stack back to its root — standard iOS behavior.
                    // Without this, after pushing e.g. a user's profile from the
                    // Discover tab, tapping Discover again kept showing the pushed
                    // profile, stranding the user (they had to repeatedly hit Back).
                    if router.pathCount(for: tab) > 0 {
                        router.popToRoot(tab)
                    }
                } else {
                    loadedTabs.insert(tab)
                    chrome.select(tab)
                    router.setActiveTab(tab)
                }
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
                        // Subtle settle: the incoming tab scales 0.988 → 1 with
                        // the existing snappy fade, so switching reads as a
                        // gentle pop instead of a hard cross-dissolve.
                        .scaleEffect(chrome.selectedTab == tab ? 1 : 0.988)
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
            #if DEBUG
            // UI 验证/截图脚本用:`simctl launch <udid> <bundle> -KXOpenTab discover`
            if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-KXOpenTab"),
               idx + 1 < ProcessInfo.processInfo.arguments.count,
               let tab = AppTab(rawValue: ProcessInfo.processInfo.arguments[idx + 1]) {
                loadedTabs.insert(tab)
                chrome.select(tab)
            }
            // 直达某个市场频道:`-KXOpenListingChannel secondhand|rental|work|service|discount`
            if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-KXOpenListingChannel"),
               idx + 1 < ProcessInfo.processInfo.arguments.count {
                let type = ProcessInfo.processInfo.arguments[idx + 1]
                let regionCode = RegionStore.shared.current?.regionCode ?? "jp.tokyo.tokyo"
                loadedTabs.insert(.search)
                chrome.select(.search)
                router.setActiveTab(.search)
                router.open(.cityListings(regionCode: regionCode, type: type), in: .search)
            }
            // 直达某条信息详情:`-KXOpenListingDetail <listingId>`
            if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-KXOpenListingDetail"),
               idx + 1 < ProcessInfo.processInfo.arguments.count {
                let listingId = ProcessInfo.processInfo.arguments[idx + 1]
                loadedTabs.insert(.search)
                chrome.select(.search)
                router.setActiveTab(.search)
                router.open(.cityListingDetail(listingId: listingId), in: .search)
            }
            // 直达某用户主页:`-KXOpenProfile <userId>`（截图走查标签/计数）。
            if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-KXOpenProfile"),
               idx + 1 < ProcessInfo.processInfo.arguments.count {
                let uid = ProcessInfo.processInfo.arguments[idx + 1]
                loadedTabs.insert(.search)
                chrome.select(.search)
                router.setActiveTab(.search)
                router.open(.profile(userId: uid), in: .search)
            }
            // 截图走查用:`-KXDebugPush workbench|merchant` 直接展示登录后
            // 才能进的页面(工作台/商家认证表单),不用真实登录。
            if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-KXDebugPush"),
               idx + 1 < ProcessInfo.processInfo.arguments.count {
                debugPushScreen = KXDebugScreen(name: ProcessInfo.processInfo.arguments[idx + 1])
            }
            #endif
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
            // Guests can browse but not publish — intercept every compose
            // trigger (FAB / Guide / channel shortcuts) and prompt login.
            if isPresented && currentUser.isGuest {
                isShowingComposer = false
                GuestGate.shared.requireLogin()
                return
            }
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
        #if DEBUG
        .fullScreenCover(item: $debugPushScreen) { screen in
            NavigationStack {
                Group {
                    if let type = screen.payload(after: "compose:").flatMap(ContentType.init(rawValue:)) {
                        ComposePostView(currentUser: currentUser, initialContentType: type)
                    } else if let type = screen.payload(after: "create:") {
                        CreateCityListingView(listingType: type, citySlug: debugRegionCode, currentUser: currentUser)
                    } else if let type = screen.payload(after: "listing:") {
                        CityListingChannelView(regionCode: debugRegionCode, listingType: type, currentUser: currentUser)
                    } else if let listingId = screen.payload(after: "listing-detail:") {
                        CityListingDetailView(listingId: listingId, currentUser: currentUser)
                    } else if let postId = screen.payload(after: "post-detail:") {
                        PostDetailView(postId: postId, currentUser: currentUser)
                    } else if let tag = screen.payload(after: "topic:") {
                        TopicDetailView(tag: tag, currentUser: currentUser)
                    } else if let category = screen.payload(after: "guide-category:") {
                        GuideCategoryView(categoryKey: category)
                    } else if let slug = screen.payload(after: "guide-article:") {
                        GuideArticleDetailView(slug: slug)
                    } else if let slug = screen.payload(after: "guide-product:") {
                        GuideProductDetailView(slug: slug)
                    } else if let id = screen.payload(after: "guide-school:") {
                        GuideSchoolDetailView(schoolId: id)
                    } else if let id = screen.payload(after: "guide-company-reviews:") {
                        GuideCompanyReviewsView(companyId: id)
                    } else if let id = screen.payload(after: "guide-company:") {
                        GuideCompanyDetailView(companyId: id)
                    } else {
                        switch screen.name {
                    case "workbench":
                        MyWorkbenchView(currentUser: currentUser)
                    case "merchant":
                        MerchantSettingsView(currentUser: currentUser)
                    case "settings":
                        SettingsView(currentUser: currentUser, onLogout: onLogout, onSwitchAccount: onSwitchAccount)
                    case "security":
                        AccountSecuritySettingsView(currentUser: currentUser) { onLogout() }
                    case "region-language":
                        RegionLanguageSettingsView(currentUser: currentUser)
                    case "notification-preferences":
                        NotificationPreferencesView(currentUser: currentUser)
                    case "notifications":
                        NotificationsView(currentUser: currentUser)
                    case "privacy":
                        PrivacySettingsView()
                    case "membership":
                        MembershipView(currentUser: currentUser)
                    case "bookmarks":
                        BookmarkView(currentUser: currentUser)
                    case "drafts":
                        DraftsSettingsView(currentUser: currentUser)
                    case "media-library":
                        MediaLibraryView(currentUser: currentUser)
                    case "help":
                        HelpCenterView()
                    case "feedback":
                        FeedbackView()
                    case "about":
                        AboutKaiXView()
                    case "orders":
                        MyOrdersView()
                    case "inquiries":
                        MyInquiriesView(currentUser: currentUser)
                    case "my-listings":
                        MyCityListingsView(currentUser: currentUser)
                    case "merchant-reviews":
                        MerchantReviewsManageView(currentUser: currentUser)
                    case "business-directory":
                        MerchantDirectoryView(citySlug: debugRegionCode, currentUser: currentUser)
                    case "guide-services":
                        GuideServicesView()
                    case "guide-member":
                        GuideMemberResourcesView()
                    case "guide-schools":
                        GuideSchoolListView()
                    case "guide-companies":
                        GuideCompanyListView()
                    case "guide-interviews":
                        GuideInterviewReviewListView()
                    case "search-screen":
                        SearchScreen(currentUser: currentUser, initialQuery: "tokyo")
                    case "profile-self":
                        ProfileView(currentUser: currentUser, tracksChrome: false, showsBackButton: false)
                    case "city":
                        CityChannelView(regionCode: debugRegionCode, currentUser: currentUser)
                    default:
                        EmptyView()
                        }
                    }
                }
                .kxRouteDestinations(currentUser: currentUser)
            }
        }
        #endif
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
        case .guide:
            NavigationStack(path: router.binding(for: .guide)) {
                GuideHomeView(currentUser: currentUser)
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

#if DEBUG
/// Identifiable wrapper for the `-KXDebugPush` screenshot hook.
struct KXDebugScreen: Identifiable {
    let name: String
    var id: String { name }

    func payload(after prefix: String) -> String? {
        guard name.hasPrefix(prefix) else { return nil }
        return String(name.dropFirst(prefix.count))
    }
}

private let debugRegionCode = "jp.tokyo.tokyo"
#endif

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case search
    case guide
    case messages
    case profile

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .home: L("home", language)
        case .search: L("discover", language)
        case .guide: L("guide", language)
        case .messages: L("messages", language)
        case .profile: L("me", language)
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .search: "safari.fill"
        case .guide: "text.book.closed.fill"
        case .messages: "envelope"
        case .profile: "person.crop.circle.fill"
        }
    }
}
