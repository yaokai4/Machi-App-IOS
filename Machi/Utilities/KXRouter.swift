import Combine
import SwiftData
import SwiftUI

enum KXRoute: Hashable {
    case postDetail(postId: String)
    case postDetailComment(postId: String, commentId: String?)
    case profile(userId: String)
    case topic(tag: String)
    case city(regionCode: String)
    case cityChannel(regionCode: String, channel: CityChannel)
    case cityListings(regionCode: String, type: String)
    case userListings(userId: String, type: String, title: String)
    case cityListingDetail(listingId: String)
    case createCityListing(type: String, citySlug: String?)
    case editCityListing(listingId: String)
    case myInquiries
    case businessDirectory(citySlug: String)
    case businessProfile(businessId: String)
    case guideCategory(categoryKey: String)
    case guideJourney(key: String)
    case guidePlan
    case guideCalendar
    case guideProfile
    case guideLifePlanner
    case guideApplications
    case guideServices
    case guideMemberResources
    case guideArticle(slug: String)
    case guideProduct(slug: String)
    case guideSchools
    case guideSchool(id: String)
    case guideCompanies
    case guideCompany(id: String)
    case guideCompanyReviews(id: String)
    case guideInterviewReviews
    case conversation(conversationId: String)
    case search(initialQuery: String?)
}

@MainActor
final class AppRouter: ObservableObject {
    @Published private var homePath: [KXRoute] = []
    @Published private var searchPath: [KXRoute] = []
    @Published private var guidePath: [KXRoute] = []
    @Published private var messagesPath: [KXRoute] = []
    @Published private var profilePath: [KXRoute] = []
    @Published var routeErrorMessage: String?
    @Published private(set) var activeTab: AppTab = .home
    @Published private(set) var routeRevision = 0

    func open(_ route: KXRoute) {
        open(route, in: activeTab)
    }

    func open(_ route: KXRoute, in tab: AppTab) {
        guard let normalizedRoute = route.normalized else {
            let language = AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? AppLanguage.system.rawValue)
            routeErrorMessage = L("routeUnavailable", language)
            return
        }
        append(normalizedRoute, to: tab)
    }

    func setActiveTab(_ tab: AppTab) {
        activeTab = tab
    }

    func binding(for tab: AppTab) -> Binding<[KXRoute]> {
        Binding {
            self.path(for: tab)
        } set: { path in
            self.setPath(path, for: tab)
        }
    }

    func popToRoot(_ tab: AppTab) {
        setPath([], for: tab)
    }

    @discardableResult
    func replaceTop(with route: KXRoute, in tab: AppTab? = nil) -> Bool {
        guard let normalizedRoute = route.normalized else {
            let language = AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? AppLanguage.system.rawValue)
            routeErrorMessage = L("routeUnavailable", language)
            return false
        }
        let targetTab = tab ?? activeTab
        var nextPath = path(for: targetTab)
        guard !nextPath.isEmpty else { return false }
        nextPath[nextPath.count - 1] = normalizedRoute
        setPath(nextPath, for: targetTab)
        return true
    }

    func resetAll() {
        homePath = []
        searchPath = []
        guidePath = []
        messagesPath = []
        profilePath = []
        activeTab = .home
        routeErrorMessage = nil
        routeRevision += 1
    }

    func pathCount(for tab: AppTab) -> Int {
        path(for: tab).count
    }

    func requiresHiddenChrome(for tab: AppTab? = nil) -> Bool {
        path(for: tab ?? activeTab).contains { $0.requiresHiddenTabBar }
    }

    func routes(for tab: AppTab) -> [KXRoute] {
        path(for: tab)
    }

    private func path(for tab: AppTab) -> [KXRoute] {
        switch tab {
        case .home:
            homePath
        case .search:
            searchPath
        case .guide:
            guidePath
        case .messages:
            messagesPath
        case .profile:
            profilePath
        }
    }

    private func setPath(_ path: [KXRoute], for tab: AppTab) {
        let normalizedPath = path.compactMap(\.normalized)
        switch tab {
        case .home:
            homePath = normalizedPath
        case .search:
            searchPath = normalizedPath
        case .guide:
            guidePath = normalizedPath
        case .messages:
            messagesPath = normalizedPath
        case .profile:
            profilePath = normalizedPath
        }
        routeRevision += 1
    }

    private func append(_ route: KXRoute, to tab: AppTab) {
        var nextPath = path(for: tab)
        // Idempotent navigation: if the destination is already somewhere in
        // this tab's stack, pop back to it instead of pushing a duplicate.
        // Without this, bouncing between two users' profiles (A→B→A→B…) — or
        // any A→…→A loop — grew the stack without bound, so the user had to
        // tap Back a dozen times to escape. Pop-to-existing keeps the back
        // chain shallow and matches what people expect ("I'm already here").
        if let existingIndex = nextPath.lastIndex(of: route) {
            if existingIndex < nextPath.count - 1 {
                nextPath.removeSubrange((existingIndex + 1)...)
                setPath(nextPath, for: tab)
            }
            return
        }
        nextPath.append(route)
        setPath(nextPath, for: tab)
    }
}

typealias KXRouter = AppRouter

extension KXRoute {
    var initialFocus: PostDetailInitialFocus {
        switch self {
        case .postDetail:
            return .none
        case .postDetailComment(_, let commentId):
            return commentId.map { .comment($0) } ?? .comments
        case .profile, .topic, .city, .cityChannel, .cityListings, .userListings, .cityListingDetail, .createCityListing, .editCityListing, .myInquiries, .businessDirectory, .businessProfile, .guideCategory, .guideJourney, .guidePlan, .guideCalendar, .guideProfile, .guideLifePlanner, .guideApplications, .guideServices, .guideMemberResources, .guideArticle, .guideProduct, .guideSchools, .guideSchool, .guideCompanies, .guideCompany, .guideCompanyReviews, .guideInterviewReviews, .conversation, .search:
            return .none
        }
    }

    var requiresHiddenTabBar: Bool {
        switch self {
        case .postDetail, .postDetailComment, .cityListings, .userListings, .cityListingDetail, .createCityListing, .editCityListing, .businessProfile, .guideArticle, .guideProduct, .guideJourney, .guideSchool, .guideCompany, .guideCompanyReviews, .conversation:
            true
        case .profile, .topic, .city, .cityChannel, .myInquiries, .businessDirectory, .guideCategory, .guidePlan, .guideCalendar, .guideProfile, .guideLifePlanner, .guideApplications, .guideServices, .guideMemberResources, .guideSchools, .guideCompanies, .guideInterviewReviews, .search:
            false
        }
    }

    func friendlyFailureMessage(_ language: AppLanguage) -> String {
        switch self {
        case .postDetail, .postDetailComment:
            L("postDeletedHelp", language)
        case .profile:
            L("unknownUser", language)
        case .topic:
            L("noTopicPosts", language)
        case .city, .cityChannel, .cityListings, .userListings, .cityListingDetail, .createCityListing, .editCityListing, .myInquiries, .businessDirectory, .businessProfile:
            L("emptyFeed", language)
        case .guideCategory, .guideJourney, .guidePlan, .guideCalendar, .guideProfile, .guideLifePlanner, .guideApplications, .guideServices, .guideMemberResources, .guideArticle, .guideProduct, .guideSchools, .guideSchool, .guideCompanies, .guideCompany, .guideCompanyReviews, .guideInterviewReviews:
            L("guideOpenFailed", language)
        case .conversation:
            L("emptyMessages", language)
        case .search:
            L("emptySearch", language)
        }
    }
}

private struct KXRouteDestinations: ViewModifier {
    @EnvironmentObject private var router: KXRouter
    @Environment(\.appLanguage) private var language
    /// One namespace shared by every listing screen pushed onto this stack, so
    /// a channel card can zoom into its detail (iOS 18+; no-op on 17).
    @Namespace private var listingZoom

    let currentUser: UserEntity

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: KXRoute.self) { route in
                switch route {
                case .postDetail(let postId):
                    PostDetailView(postId: postId, currentUser: currentUser)
                case .postDetailComment(let postId, _):
                    PostDetailView(
                        postId: postId,
                        currentUser: currentUser,
                        initialFocus: route.initialFocus
                    )
                case .profile(let userId):
                    ProfileRouteView(userId: userId, currentUser: currentUser)
                case .topic(let tag):
                    TopicDetailView(tag: tag, currentUser: currentUser)
                case .city(let regionCode):
                    CityChannelView(regionCode: regionCode, currentUser: currentUser)
                case .cityChannel(let regionCode, let channel):
                    CityChannelView(regionCode: regionCode, currentUser: currentUser, initialChannel: channel)
                case .cityListings(let regionCode, let type):
                    CityListingChannelView(regionCode: regionCode, listingType: type, currentUser: currentUser, zoomNamespace: listingZoom)
                case .userListings(let userId, let type, let title):
                    UserListingsView(userId: userId, listingType: type, title: title, currentUser: currentUser)
                case .cityListingDetail(let listingId):
                    CityListingDetailView(listingId: listingId, currentUser: currentUser, zoomNamespace: listingZoom)
                case .createCityListing(let type, let citySlug):
                    CreateCityListingView(listingType: type, citySlug: citySlug, currentUser: currentUser)
                case .editCityListing(let listingId):
                    EditCityListingRouteView(listingId: listingId, currentUser: currentUser)
                case .myInquiries:
                    MyInquiriesView(currentUser: currentUser)
                case .businessDirectory(let citySlug):
                    MerchantDirectoryView(citySlug: citySlug, currentUser: currentUser)
                case .businessProfile(let businessId):
                    BusinessPublicProfileView(businessId: businessId, currentUser: currentUser)
                case .guideCategory(let categoryKey):
                    GuideCategoryView(categoryKey: categoryKey)
                case .guideJourney(let key):
                    GuideJourneyDetailView(journeyKey: key)
                case .guidePlan:
                    GuidePlanView()
                case .guideCalendar:
                    GuideCalendarView()
                case .guideProfile:
                    GuideProfileSetupView()
                case .guideLifePlanner:
                    GuideLifePlannerView()
                case .guideApplications:
                    GuideApplicationPlannerView()
                case .guideServices:
                    GuideServicesView()
                case .guideMemberResources:
                    GuideMemberResourcesView()
                case .guideArticle(let slug):
                    GuideArticleDetailView(slug: slug)
                case .guideProduct(let slug):
                    GuideProductDetailView(slug: slug)
                case .guideSchools:
                    GuideSchoolListView()
                case .guideSchool(let id):
                    GuideSchoolDetailView(schoolId: id)
                case .guideCompanies:
                    GuideCompanyListView()
                case .guideCompany(let id):
                    GuideCompanyDetailView(companyId: id)
                case .guideCompanyReviews(let id):
                    GuideCompanyReviewsView(companyId: id)
                case .guideInterviewReviews:
                    GuideInterviewReviewListView()
                case .conversation(let conversationId):
                    ConversationView(conversationId: conversationId, currentUser: currentUser)
                case .search(let initialQuery):
                    SearchScreen(currentUser: currentUser, initialQuery: initialQuery ?? "")
                }
            }
            .alert(L("error", language), isPresented: Binding(
                get: { router.routeErrorMessage != nil },
                set: { if !$0 { router.routeErrorMessage = nil } }
            )) {
                Button(L("ok", language), role: .cancel) {}
            } message: {
                Text(router.routeErrorMessage ?? "")
            }
    }
}

extension View {
    func kxRouteDestinations(currentUser: UserEntity) -> some View {
        modifier(KXRouteDestinations(currentUser: currentUser))
    }
}

struct KXRoutedPostDetailView: View {
    @EnvironmentObject private var router: AppRouter

    let postId: String
    let currentUser: UserEntity
    var initialFocus: PostDetailInitialFocus = .none

    var body: some View {
        PostDetailView(postId: postId, currentUser: currentUser, initialFocus: initialFocus)
            .kxRouteDestinations(currentUser: currentUser)
    }
}

private struct ProfileRouteView: View {
    let userId: String
    let currentUser: UserEntity

    var body: some View {
        ProfileView(currentUser: currentUser, profileUserId: userId, tracksChrome: false, showsBackButton: true)
    }
}

private extension KXRoute {
    var normalized: KXRoute? {
        switch self {
        case .postDetail(let postId):
            let id = postId.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .postDetail(postId: id)
        case .postDetailComment(let postId, let commentId):
            let id = postId.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedCommentId = commentId?.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .postDetailComment(
                postId: id,
                commentId: normalizedCommentId?.isEmpty == true ? nil : normalizedCommentId
            )
        case .profile(let userId):
            let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .profile(userId: id)
        case .topic(let tag):
            let normalizedTag = tag.normalizedTopicName
            return normalizedTag.isEmpty ? nil : .topic(tag: normalizedTag)
        case .city(let regionCode):
            let code = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return KaiXRegionDirectory.resolve(regionCode: code) == nil ? nil : .city(regionCode: code)
        case .cityChannel(let regionCode, let channel):
            let code = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return KaiXRegionDirectory.resolve(regionCode: code) == nil ? nil : .cityChannel(regionCode: code, channel: channel)
        case .cityListings(let regionCode, let type):
            let code = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return KaiXRegionDirectory.resolve(regionCode: code) == nil || normalizedType.isEmpty
                ? nil
                : .cityListings(regionCode: code, type: normalizedType)
        case .userListings(let userId, let type, let title):
            let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty || normalizedType.isEmpty
                ? nil
                : .userListings(userId: id, type: normalizedType, title: normalizedTitle.isEmpty ? normalizedType : normalizedTitle)
        case .cityListingDetail(let listingId):
            let id = listingId.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .cityListingDetail(listingId: id)
        case .createCityListing(let type, let citySlug):
            let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedCity = citySlug?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalizedType.isEmpty
                ? nil
                : .createCityListing(type: normalizedType, citySlug: normalizedCity?.isEmpty == true ? nil : normalizedCity)
        case .editCityListing(let listingId):
            let id = listingId.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .editCityListing(listingId: id)
        case .myInquiries:
            return .myInquiries
        case .guideCategory(let categoryKey):
            let key = categoryKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : .guideCategory(categoryKey: key)
        case .guideJourney(let key):
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedKey.isEmpty ? nil : .guideJourney(key: normalizedKey)
        case .guidePlan:
            return .guidePlan
        case .guideCalendar:
            return .guideCalendar
        case .guideProfile:
            return .guideProfile
        case .guideLifePlanner:
            return .guideLifePlanner
        case .guideApplications:
            return .guideApplications
        case .guideServices:
            return .guideServices
        case .guideMemberResources:
            return .guideMemberResources
        case .guideArticle(let slug):
            let id = slug.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .guideArticle(slug: id)
        case .guideProduct(let slug):
            let id = slug.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .guideProduct(slug: id)
        case .guideSchools:
            return .guideSchools
        case .guideSchool(let id):
            let normalizedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedId.isEmpty ? nil : .guideSchool(id: normalizedId)
        case .guideCompanies:
            return .guideCompanies
        case .guideCompany(let id):
            let normalizedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedId.isEmpty ? nil : .guideCompany(id: normalizedId)
        case .guideCompanyReviews(let id):
            let normalizedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedId.isEmpty ? nil : .guideCompanyReviews(id: normalizedId)
        case .guideInterviewReviews:
            return .guideInterviewReviews
        case .businessDirectory(let citySlug):
            let slug = citySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return .businessDirectory(citySlug: slug)
        case .businessProfile(let businessId):
            let id = businessId.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .businessProfile(businessId: id)
        case .conversation(let conversationId):
            let id = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .conversation(conversationId: id)
        case .search(let initialQuery):
            let query = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .search(initialQuery: query?.isEmpty == true ? nil : query)
        }
    }
}

import UIKit

/// Re-enables the system edge-swipe-back gesture on pages that hide the
/// navigation bar (`.toolbar(.hidden, for: .navigationBar)`). By default UIKit
/// disables `interactivePopGestureRecognizer` while the bar is hidden, which is
/// why Machi's custom-header pages (chat, listing detail, etc.) couldn't be
/// swiped back. We re-point the gesture's delegate so the swipe is allowed
/// whenever the navigation stack has something to pop. The recognizer is a
/// left-screen-edge pan, so it never steals mid-screen horizontal scrolling.
private struct KXSwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> KXSwipeBackProbe { KXSwipeBackProbe() }
    func updateUIViewController(_ uiViewController: KXSwipeBackProbe, context: Context) {}
}

final class KXSwipeBackProbe: UIViewController, UIGestureRecognizerDelegate {
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        attach()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attach()
    }
    private func attach() {
        DispatchQueue.main.async { [weak self] in
            guard let nav = self?.navigationController,
                  let gesture = nav.interactivePopGestureRecognizer else { return }
            gesture.delegate = self
            gesture.isEnabled = true
        }
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}

extension View {
    /// Enable edge-swipe-back even when the nav bar is hidden. Apply once on a
    /// NavigationStack's root content.
    func kxEnableSwipeBack() -> some View {
        background(KXSwipeBackEnabler().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
