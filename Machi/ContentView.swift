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
            #if DEBUG
            if appState.currentUser == nil,
               ProcessInfo.processInfo.arguments.contains("-KXAutoGuest") {
                enterAsGuest()
            }
            #endif
            if let user = appState.currentUser {
                RegionStore.shared.applyUserRegion(user)
            }
            // First-run auto-locate: when no browsing region is set yet, fill it
            // from the device's current city so the user never has to pick one by
            // hand. Skips silently if location was denied; a manual picker (with a
            // "使用当前位置" button) remains available either way.
            //
            // Gated on an actual user (logged in or guest) so the OS location
            // prompt is never thrown up over the logged-out auth screen — guests
            // already default to Tokyo and signed-in accounts carry a region, so
            // this only fires in-context for an account that still lacks one.
            if appState.currentUser != nil,
               RegionStore.shared.current == nil,
               !LocationService.shared.isDenied {
                if let region = await LocationService.shared.detectRegion() {
                    RegionStore.shared.setCurrent(region)
                }
            }
            sessionStore.setCurrentUser(appState.currentUser?.id)
            userStore.setCurrentUser(appState.currentUser)
            // Foreground notification loop: poll the server's notification
            // list and surface anything new as a REAL system banner +
            // app-icon badge. Cancelled automatically when the session
            // changes (task id) or the root view goes away.
            guard KaiXBackend.token != nil, appState.currentUser?.isGuest != true else { return }
            await SystemNotificationService.shared.requestAuthorizationIfNeeded()
            while !Task.isCancelled {
                await syncSystemNotifications()
                try? await Task.sleep(nanoseconds: 12_000_000_000)
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
            syncAppBadge()
            if count == 0 {
                SystemNotificationService.shared.clearDelivered()
            }
        }
        .onReceive(messageStore.$unreadCounts) { _ in
            syncAppBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXSystemNotificationTapped)) { note in
            handleSystemNotificationTap(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXConversationShouldRefresh)) { _ in
            guard KaiXBackend.token != nil else { return }
            Task { await syncSystemNotifications() }
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

    /// One notification tick: read the server list directly, refresh the
    /// in-app store/badge, and banner anything new.
    private func syncSystemNotifications() async {
        guard KaiXBackend.token != nil, let user = appState.currentUser, !user.isGuest else { return }
        do {
            if let conversations = try? await MessageRepository(context: modelContext).fetchThreads(currentUserId: user.id) {
                let previousLastMessageDates = messageStore.conversationsById.mapValues(\.lastMessageAt)
                messageStore.setConversations(conversations)
                await warmChangedMessageThreads(
                    conversations,
                    previousLastMessageDates: previousLastMessageDates
                )
                syncAppBadge()
            }
            let response = try await KaiXAPIClient.shared.notifications(kind: "all")
            let all = response.items.map(notificationEntity(from:))
            notificationStore.setNotifications(all)
            notificationStore.setUnreadCount(response.unread_count)
            syncAppBadge()
            let wanted = all.filter {
                !$0.isRead && NotificationPreferenceService.isEnabled($0.type, recipientUserId: user.id)
            }
            guard !wanted.isEmpty else { return }
            var actors: [String: UserEntity] = [:]
            for dto in response.items.compactMap(\.actor) {
                actors[dto.id] = UserRepository.entity(from: dto)
            }
            let missingActorIds = Set(wanted.map(\.actorId)).subtracting(actors.keys)
            if !missingActorIds.isEmpty {
                let fetched = try await UserRepository(context: modelContext).fetchUsers(ids: missingActorIds)
                for actor in fetched {
                    actors[actor.id] = actor
                }
            }
            await SystemNotificationService.shared.deliver(
                wanted,
                actors: actors,
                language: language
            )
        } catch {
            // Background polling should never interrupt foreground use.
        }
    }

    /// Keep foreground push banners and the actual chat timeline in sync.
    /// The notification poll is lightweight, but when it observes a new/unread
    /// conversation we also prefetch that conversation's messages so opening the
    /// chat never shows stale content behind a fresh banner.
    private func warmChangedMessageThreads(
        _ conversations: [MessageThreadEntity],
        previousLastMessageDates: [String: Date]
    ) async {
        guard KaiXBackend.token != nil else { return }
        let changed = conversations
            .filter { conversation in
                if conversation.unreadCount > 0 { return true }
                guard let previous = previousLastMessageDates[conversation.id] else { return true }
                return conversation.lastMessageAt > previous.addingTimeInterval(0.25)
            }
            .prefix(8)
        guard !changed.isEmpty else { return }
        let repository = MessageRepository(context: modelContext)
        for conversation in changed {
            do {
                let messages = try await repository.fetchMessages(threadId: conversation.id)
                _ = try await repository.fetchMedia(threadId: conversation.id, messageIds: Set(messages.map(\.id)))
                messageStore.setMessages(messages, conversationId: conversation.id)
                messageStore.upsertConversation(conversation)
            } catch {
                // Foreground warming must never interrupt the active screen.
            }
        }
    }

    private func syncAppBadge() {
        let totalUnread = notificationStore.unreadCount + messageStore.totalUnreadCount
        SystemNotificationService.shared.syncBadge(unreadCount: totalUnread)
    }

    private func notificationEntity(from dto: KaiXNotificationDTO) -> NotificationEntity {
        NotificationEntity(
            id: dto.id,
            type: NotificationType(rawValue: dto.type) ?? .system,
            actorId: dto.actor?.id ?? dto.actor_id,
            targetPostId: dto.target_post_id,
            targetCommentId: dto.target_comment_id,
            targetConversationId: dto.target_conversation_id,
            content: dto.content ?? "",
            isRead: dto.is_read,
            createdAt: parseServerDate(dto.created_at) ?? .now,
            remoteId: dto.id,
            syncStatus: .synced
        )
    }

    private func parseServerDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
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
        // 立即套用游客的默认/上次浏览城市，首页 feed 不留空白等待。
        RegionStore.shared.applyUserRegion(guest)
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
