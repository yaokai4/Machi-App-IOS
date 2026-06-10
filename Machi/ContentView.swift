import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("currentUserID") private var currentUserID = ""
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.light.rawValue
    @StateObject private var appState = AppState()
    @StateObject private var appRouter = AppRouter()
    @StateObject private var appChrome = AppChromeState()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var userStore = UserStore()
    @StateObject private var postStore = PostStore()
    @StateObject private var commentStore = CommentStore()
    @StateObject private var notificationStore = NotificationStore()
    @StateObject private var messageStore = MessageStore()
    @StateObject private var searchStore = SearchStore()
    @StateObject private var composeStore = ComposeStore()
    @StateObject private var toastManager = ToastManager()
    @StateObject private var connectivityMonitor = ConnectivityMonitor()
    @ObservedObject private var guestGate = GuestGate.shared
    @State private var displayedDatabaseNoticeKey: String?

    private var language: AppLanguage {
        AppLanguage.resolved(from: appLanguageCode)
    }

    var body: some View {
        Group {
            switch appState.state {
            case .loading, .idle:
                KXSplashView()
            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await appState.bootstrap(context: modelContext, currentUserId: currentUserID) }
                }
            case .empty:
                AuthView(onAuthenticated: completeLogin, onBrowseAsGuest: enterAsGuest)
            case .loaded:
                if let currentUser = appState.currentUser {
                    MainTabView(currentUser: currentUser, onLogout: logout, onSwitchAccount: switchAccount)
                        .id(currentUser.id)
                } else {
                    AuthView(onAuthenticated: completeLogin, onBrowseAsGuest: enterAsGuest)
                }
            }
        }
        .environment(\.appLanguage, language)
        .environmentObject(appRouter)
        .environmentObject(appChrome)
        .environmentObject(sessionStore)
        .environmentObject(userStore)
        .environmentObject(postStore)
        .environmentObject(commentStore)
        .environmentObject(notificationStore)
        .environmentObject(messageStore)
        .environmentObject(searchStore)
        .environmentObject(composeStore)
        .environmentObject(toastManager)
        .preferredColorScheme(AppAppearance.from(appAppearance).colorScheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .kxPageBackground()
        .toastHost(toastManager)
        // Login prompt for guests: any gated action calls
        // GuestGate.shared.requireLogin(); we present the auth flow here and
        // upgrade the guest to the real account on success.
        .sheet(isPresented: $guestGate.isPromptingLogin) {
            AuthView { user in
                guestGate.dismiss()
                completeLogin(user)
            }
            .environment(\.appLanguage, language)
        }
        .task(id: currentUserID) {
            await appState.bootstrap(context: modelContext, currentUserId: currentUserID)
            if let user = appState.currentUser {
                RegionStore.shared.applyUserRegion(user)
            }
            sessionStore.setCurrentUser(appState.currentUser?.id)
            userStore.setCurrentUser(appState.currentUser)
            // After local SwiftData is in shape, pull the latest state
            // from the unified backend so iOS and Web actually share the
            // same data. This is a no-op when offline / unauthenticated.
            if KaiXBackend.token != nil {
                await RemoteSyncService.shared.bootstrap(context: modelContext)
            }
            // Foreground notification loop: poll the server's notification
            // list and surface anything new as a REAL system banner +
            // app-icon badge. Cancelled automatically when the session
            // changes (task id) or the root view goes away.
            guard KaiXBackend.token != nil, appState.currentUser?.isGuest != true else { return }
            await SystemNotificationService.shared.requestAuthorizationIfNeeded()
            while !Task.isCancelled {
                await syncSystemNotifications()
                try? await Task.sleep(nanoseconds: 45_000_000_000)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Snappy re-sync on returning to the foreground (the sleeping
            // poll loop also resumes, this just skips the residual wait).
            if phase == .active, KaiXBackend.token != nil {
                Task { await syncSystemNotifications() }
            }
        }
        .onChange(of: notificationStore.unreadCount) { _, count in
            SystemNotificationService.shared.syncBadge(unreadCount: count)
            if count == 0 {
                SystemNotificationService.shared.clearDelivered()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXSystemNotificationTapped)) { note in
            handleSystemNotificationTap(note)
        }
        .onChange(of: appState.databaseRecoveryNotice) { _, notice in
            #if DEBUG
            guard let notice else { return }
            guard displayedDatabaseNoticeKey != notice.presentationKey else { return }
            displayedDatabaseNoticeKey = notice.presentationKey
            toastManager.show(ErrorState.database(notice), duration: notice.mode.isPersistentRecovery ? nil : 5) {
                Task { await appState.bootstrap(context: modelContext, currentUserId: currentUserID) }
            }
            #else
            _ = notice
            #endif
        }
        .onChange(of: connectivityMonitor.isOffline) { _, isOffline in
            if isOffline {
                toastManager.show(.offline, duration: nil)
            } else if toastManager.current?.state.title == ErrorState.offline.title {
                toastManager.dismiss()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXSessionInvalidated)) { _ in
            logout()
        }
    }

    /// Route a tapped system banner. DM / inquiry banners land in the chat
    /// itself; everything else routes to the post (or just the home feed).
    private func handleSystemNotificationTap(_ note: Notification) {
        guard appState.currentUser != nil else { return }
        let conversationId = note.userInfo?["conversationId"] as? String
        let postId = note.userInfo?["postId"] as? String
        if let conversationId, !conversationId.isEmpty {
            appChrome.select(.messages)
            appRouter.setActiveTab(.messages)
            appRouter.open(.conversation(conversationId: conversationId), in: .messages)
            return
        }
        appChrome.select(.home)
        appRouter.setActiveTab(.home)
        if let postId, !postId.isEmpty {
            appRouter.open(.postDetail(postId: postId), in: .home)
        }
    }

    /// One notification tick: mirror the server list into SwiftData,
    /// refresh the in-app store/badge, and banner anything new.
    private func syncSystemNotifications() async {
        guard KaiXBackend.token != nil, let user = appState.currentUser, !user.isGuest else { return }
        let fresh = await RemoteSyncService.shared.syncNotifications(context: modelContext)
        if let all = try? await NotificationRepository(context: modelContext).fetchNotifications() {
            notificationStore.setNotifications(all)
        }
        // Honor the user's per-type switches from 设置 → 通知设置.
        let wanted = fresh.filter { NotificationPreferenceService.isEnabled($0.type, recipientUserId: user.id) }
        guard !wanted.isEmpty else { return }
        let actorIds = Set(wanted.map(\.actorId))
        let actorList = (try? await UserRepository(context: modelContext).fetchUsers(ids: actorIds)) ?? []
        await SystemNotificationService.shared.deliver(
            wanted,
            actors: Dictionary(uniqueKeysWithValues: actorList.map { ($0.id, $0) }),
            language: language
        )
    }

    /// Shared success path for a real (non-guest) login or registration.
    private func completeLogin(_ user: UserEntity) {
        AuthService.shared.persistSession(user: user)
        currentUserID = user.id
        appState.currentUser = user
        sessionStore.setCurrentUser(user.id)
        userStore.setCurrentUser(user)
        appState.state = .loaded
    }

    /// Enter the app as a guest (logged-out browsing). The guest is a local
    /// UserEntity with no backend token, so authenticated sync stays a no-op.
    /// We persist `currentUserID = guestID` so the choice survives relaunch
    /// and the user isn't nagged to log in every cold start.
    private func enterAsGuest() {
        let guest = GuestSession.ensureGuestUser(context: modelContext)
        currentUserID = GuestSession.guestID
        appState.currentUser = guest
        sessionStore.setCurrentUser(guest.id)
        userStore.setCurrentUser(guest)
        appState.state = .loaded
    }

    private func logout() {
        AuthService.shared.logout()
        currentUserID = ""
        appState.currentUser = nil
        appRouter.resetAll()
        appChrome.reset()
        sessionStore.invalidate()
        userStore.setCurrentUser(nil)
        appState.state = .empty
    }

    private func switchAccount(_ user: UserEntity) {
        AuthService.shared.switchAccount(to: user)
        currentUserID = user.id
        appState.currentUser = user
        appRouter.resetAll()
        appChrome.reset()
        sessionStore.setCurrentUser(user.id)
        userStore.setCurrentUser(user)
        appState.state = .loaded
    }
}
