import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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
