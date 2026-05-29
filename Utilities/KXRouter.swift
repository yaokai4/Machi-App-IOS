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
    case conversation(conversationId: String)
    case search(initialQuery: String?)
}

@MainActor
final class AppRouter: ObservableObject {
    @Published private var homePath: [KXRoute] = []
    @Published private var searchPath: [KXRoute] = []
    @Published private var notificationsPath: [KXRoute] = []
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
            routeErrorMessage = "内容暂时无法打开，请稍后重试。"
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

    func resetAll() {
        homePath = []
        searchPath = []
        notificationsPath = []
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
        case .notifications:
            notificationsPath
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
        case .notifications:
            notificationsPath = normalizedPath
        case .messages:
            messagesPath = normalizedPath
        case .profile:
            profilePath = normalizedPath
        }
        routeRevision += 1
    }

    private func append(_ route: KXRoute, to tab: AppTab) {
        var nextPath = path(for: tab)
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
        case .profile, .topic, .city, .cityChannel, .conversation, .search:
            return .none
        }
    }

    var requiresHiddenTabBar: Bool {
        switch self {
        case .postDetail, .postDetailComment, .conversation:
            true
        case .profile, .topic, .city, .cityChannel, .search:
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
        case .city, .cityChannel:
            L("emptyFeed", language)
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
        case .conversation(let conversationId):
            let id = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : .conversation(conversationId: id)
        case .search(let initialQuery):
            let query = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .search(initialQuery: query?.isEmpty == true ? nil : query)
        }
    }
}
