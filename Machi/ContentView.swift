import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("currentUserID") private var currentUserID = ""
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// Raw `arrival_stage` value picked on the onboarding persona step ("" =
    /// skipped). Written by OnboardingView; drives the first-entry journey
    /// routing here and is synced to the Guide profile on login.
    @AppStorage("onboardingPersona") private var onboardingPersona = ""
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
    /// Which tab the logged-out entry AuthView opens on. Onboarding's explicit
    /// "登录 / 注册" tap sets `.register`; the default cold entry stays `.login`.
    @State private var entryAuthMode: AuthViewModel.Mode = .login
    @State private var isSyncingSystemNotifications = false
    /// A system-notification tap that arrived while `currentUser` was still nil
    /// (cold start from a killed app: the tap lands before bootstrap finishes).
    /// Stashed here and replayed once the session loads, so the deep link is
    /// never silently swallowed.
    @State private var pendingNotificationPayload: [AnyHashable: Any]?

    private var language: AppLanguage {
        AppLanguage.resolved(from: appLanguageCode)
    }

    /// Emit the `home.firstRender` launch signpost exactly once. `onAppear` can
    /// fire again on later account switches; only the cold-launch marker is
    /// interesting for hitch profiling, so guard it behind a one-shot flag.
    private static var didEmitFirstHomeRender = false
    private static func markFirstHomeRender() {
        guard !didEmitFirstHomeRender else { return }
        didEmitFirstHomeRender = true
        KXPerf.event("home.firstRender")
    }

    /// Count this cold launch exactly once per process so the review prompt can
    /// fire on the third genuine launch (not on every scene reactivation).
    private static var didCountColdLaunch = false
    private static func markColdLaunchForReview() {
        guard !didCountColdLaunch else { return }
        didCountColdLaunch = true
        ReviewPromptService.shared.noteColdLaunch()
    }

    /// A coarse, Equatable launch phase so the splash → main / auth swap can
    /// cross-fade-and-settle instead of hard-cutting. Changes only on bootstrap
    /// completion, login, and logout — exactly the moments we want animated.
    private var launchPhase: Int {
        switch appState.state {
        case .loading, .idle: return 0
        case .error: return 1
        case .empty: return 2
        case .loaded: return appState.currentUser != nil ? 3 : 2
        }
    }

    var body: some View {
        Group {
            switch appState.state {
            case .loading, .idle:
                KXSplashView()
                    .transition(.opacity)
            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await appState.bootstrap(context: modelContext, currentUserId: currentUserID) }
                }
            case .empty:
                entryView
                    .transition(.opacity)
            case .loaded:
                if let currentUser = appState.currentUser {
                    MainTabView(currentUser: currentUser, onLogout: logout, onSwitchAccount: switchAccount)
                        .id(currentUser.id)
                        // The app "arrives": content fades up from a hair under
                        // 1.0 as the splash fades out — a calm, premium settle.
                        .transition(.opacity.combined(with: .scale(scale: 1.015)))
                        // Launch-profiling marker: the home/main UI is now on
                        // screen. Pairs with `app.launch` / `database.ready` /
                        // `app.bootstrap` to bracket cold launch in Instruments.
                        .onAppear {
                            Self.markFirstHomeRender()
                            Self.markColdLaunchForReview()
                        }
                } else {
                    entryView
                        .transition(.opacity)
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: launchPhase)
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
        // Honour Dynamic Type up to a generous accessibility size — body text,
        // post content and titles now scale (see kxScaledFont / KXTypography) —
        // while capping the two most extreme categories that would shatter the
        // dense feed/tab-bar layouts. A pragmatic balance for a content app.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .kxPageBackground()
        // DEBUG-only frame/hitch monitor (no-op in release) — the runtime half
        // of the 120 Hz regression guardrail.
        .kxFrameRateMonitored()
        .toastHost(toastManager)
        // Surfaces the App Store rating sheet when a ReviewPromptService trigger
        // fires (3rd cold launch / first post engagement / consultation reply).
        .kxReviewPrompts()
        // Login prompt for guests: any gated action calls
        // GuestGate.shared.requireLogin(); we present the auth flow here and
        // upgrade the guest to the real account on success.
        .sheet(isPresented: $guestGate.isPromptingLogin) {
            AuthView(onAuthenticated: { user in
                guestGate.dismiss()
                completeLogin(user)
            }, onBrowseAsGuest: {
                // Clear "稍后再说" escape so a gated guest is never trapped behind
                // the login sheet with no obvious way out (the prompt is shown for
                // optional actions — saving a Todo, a reminder — not a hard wall).
                guestGate.dismiss()
            }, contextReason: guestGate.reason)
            .environment(\.appLanguage, language)
            .presentationDragIndicator(.visible)
        }
        .task(id: currentUserID) {
            await KXPerf.measure("app.bootstrap") {
                await appState.bootstrap(context: modelContext, currentUserId: currentUserID)
            }
            #if DEBUG
            if appState.currentUser == nil,
               ProcessInfo.processInfo.arguments.contains("-KXAutoGuest") {
                enterAsGuest()
            }
            #endif
            if let user = appState.currentUser {
                // Signed-in accounts always sync their declared home region.
                // Guests must NOT: applyUserRegion would overwrite the city the
                // guest picked by hand (persisted in UserDefaults, restored into
                // RegionStore.current on launch) with the guest's default Tokyo.
                // Only seed a region for a guest that genuinely has none yet.
                if !user.isGuest {
                    RegionStore.shared.applyUserRegion(user)
                } else if RegionStore.shared.current == nil {
                    RegionStore.shared.applyUserRegion(user)
                }
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
        .onReceive(notificationStore.$notificationsById) { _ in
            // socialUnreadCount is derived from the notification set, which can
            // shift without the raw unreadCount total changing (e.g. one social
            // read + one DM arriving in the same sync) — re-sync the badge on
            // set changes too, not just count changes.
            syncAppBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXSystemNotificationTapped)) { note in
            handleSystemNotificationTap(note)
        }
        .onChange(of: appState.currentUser?.id) { _, userId in
            // Session just became available: replay a notification tap that
            // arrived before bootstrap finished (cold-start deep link).
            guard userId != nil, let payload = pendingNotificationPayload else { return }
            pendingNotificationPayload = nil
            routeNotificationPayload(payload)
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
            handleSessionExpired()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            handleUniversalLink(url)
        }
    }

    /// Route an inbound Universal Link (`https://machicity.com/...`,
    /// `https://www.machicity.com/...`) tapped in Safari / Mail / another app.
    /// Rather than duplicate the routing switch, this maps the web path onto the
    /// equivalent `machi://` deep link and hands it to `handleDeepLink`, so the
    /// two entry points can never drift apart. Web-only paths (marketing pages,
    /// unknown routes) fall through and open nothing.
    private func handleUniversalLink(_ url: URL) {
        guard let host = url.host?.lowercased(),
              host == "machicity.com" || host == "www.machicity.com" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let first = parts.first else { return }

        func route(_ machiURL: String) {
            guard let mapped = URL(string: machiURL) else { return }
            handleDeepLink(mapped)
        }

        // Percent-encode path segments so slugs with CJK / spaces survive the
        // round-trip through a fresh URL string.
        func enc(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
        }

        switch first {
        case "i":
            // /i/<code> → 邀请裂变 invite link. There is no in-app destination:
            // stash the code so the register flow can prefill + submit it, then
            // either prompt an anonymous user to sign up, or late-bind it for a
            // user who tapped the link while already signed in.
            guard parts.count >= 2 else { return }
            handleInviteCode(parts[1])
        case "p":
            // /p/<id> → post
            guard parts.count >= 2 else { return }
            route("machi://post/\(enc(parts[1]))")
        case "listings":
            // /listings/<id> → listing
            guard parts.count >= 2 else { return }
            route("machi://listing/\(enc(parts[1]))")
        case "c":
            // /c/<code> → city
            guard parts.count >= 2 else { return }
            route("machi://city/\(enc(parts[1]))")
        case "guide":
            // /guide/articles/<slug> → article
            if parts.count >= 3, parts[1] == "articles" {
                route("machi://article/\(enc(parts[2]))")
            } else if parts.count >= 3, parts[1] == "journey" {
                route("machi://guide/journey/\(enc(parts[2]))")
            }
        case "u", "users":
            // /u/<id> or /users/<id> → profile
            guard parts.count >= 2 else { return }
            route("machi://profile/\(enc(parts[1]))")
        default:
            break
        }
    }

    /// 邀请裂变: a tapped `https://machicity.com/i/<code>` invite link.
    ///
    /// - Always remembers the code (so the register form can prefill + submit
    ///   it as `referral_code`).
    /// - If the user is already signed in (not a guest), late-binds it right
    ///   away — idempotent server-side, never pays out, a no-op if they were
    ///   ever bound — then clears the pending code.
    /// - Otherwise nudges them toward sign-up via the shared guest gate; the
    ///   code rides along into `register`.
    private func handleInviteCode(_ rawCode: String) {
        let code = rawCode.removingPercentEncoding ?? rawCode
        ReferralInvite.remember(code)
        let isSignedIn = KaiXBackend.token != nil && appState.currentUser?.isGuest != true
        if isSignedIn {
            Task {
                _ = try? await KaiXAPIClient.shared.referralBind(code: code)
                ReferralInvite.clear()
            }
        } else {
            GuestGate.shared.requireLogin(
                KXListingCopy.pickText(
                    language,
                    "注册即可领取好友邀请奖励。",
                    "登録すると友達招待の特典を受け取れます。",
                    "Sign up to claim your friend's invite reward."
                )
            )
        }
    }

    /// Route an inbound `machi://` deep link (the scheme the "copy link" actions
    /// produce). Mirrors the system-notification tap routing. The Google OAuth
    /// callback (`machi://auth/...`) never reaches here — it is intercepted by
    /// the in-flight `ASWebAuthenticationSession` — but we ignore it defensively.
    private func handleDeepLink(_ url: URL) {
        // Public destinations open for everyone — login is enforced at the
        // ACTION, not at navigation (guest-first). Only the private conversation
        // target keeps a signed-in guard. (N10 / modify#5)
        guard url.scheme == "machi" else { return }
        let identifier = url.pathComponents.first(where: { $0 != "/" }) ?? ""
        switch url.host {
        case "post":
            guard !identifier.isEmpty else { return }
            appChrome.select(.home)
            appRouter.setActiveTab(.home)
            appRouter.open(.postDetail(postId: identifier), in: .home)
        case "user", "profile":
            guard !identifier.isEmpty else { return }
            appChrome.select(.home)
            appRouter.setActiveTab(.home)
            appRouter.open(.profile(userId: identifier), in: .home)
        case "topic":
            guard !identifier.isEmpty else { return }
            appChrome.select(.home)
            appRouter.setActiveTab(.home)
            appRouter.open(.topic(tag: identifier), in: .home)
        case "listing", "cityListing":
            guard !identifier.isEmpty else { return }
            appChrome.select(.search)
            appRouter.setActiveTab(.search)
            appRouter.open(.cityListingDetail(listingId: identifier), in: .search)
        case "article", "guideArticle":
            guard !identifier.isEmpty else { return }
            appChrome.select(.guide)
            appRouter.setActiveTab(.guide)
            appRouter.open(.guideArticle(slug: identifier), in: .guide)
        case "product", "guideProduct":
            guard !identifier.isEmpty else { return }
            appChrome.select(.guide)
            appRouter.setActiveTab(.guide)
            appRouter.open(.guideProduct(slug: identifier), in: .guide)
        case "city":
            guard !identifier.isEmpty else { return }
            appChrome.select(.search)
            appRouter.setActiveTab(.search)
            appRouter.open(.city(regionCode: identifier.lowercased()), in: .search)
        case "guide":
            // machi://guide/journey/<key> — Guide journey deep link.
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 2, parts[0] == "journey", !parts[1].isEmpty else { return }
            appChrome.select(.guide)
            appRouter.setActiveTab(.guide)
            appRouter.open(.guideJourney(key: parts[1]), in: .guide)
        case "conversation", "dm":
            // Private: opening a thread needs a signed-in user.
            guard !identifier.isEmpty else { return }
            guard appState.currentUser != nil else {
                // Cold start from a killed app: the deep link can arrive before
                // bootstrap resolves the session. Stash it (reusing the
                // notification replay mechanism) and route once currentUser
                // becomes non-nil, instead of silently dropping it.
                pendingNotificationPayload = ["conversationId": identifier]
                return
            }
            appChrome.select(.messages)
            appRouter.setActiveTab(.messages)
            appRouter.open(.conversation(conversationId: identifier), in: .messages)
        default:
            break
        }
    }

    /// Route a tapped system banner. DM / inquiry banners land in the chat
    /// itself; everything else routes to the post (or just the home feed).
    private func handleSystemNotificationTap(_ note: Notification) {
        guard appState.currentUser != nil else {
            // Cold start from a killed app: the tap fires before bootstrap
            // resolves the session. Keep the payload and replay it from the
            // `currentUser` onChange below instead of dropping the deep link.
            pendingNotificationPayload = note.userInfo ?? [:]
            return
        }
        routeNotificationPayload(note.userInfo)
    }

    private func routeNotificationPayload(_ userInfo: [AnyHashable: Any]?) {
        let type = (userInfo?["type"] as? String).flatMap(NotificationType.init(rawValue:))
        let actorId = userInfo?["actorId"] as? String
        let conversationId = userInfo?["conversationId"] as? String
        let postId = userInfo?["postId"] as? String
        let listingId = userInfo?["listingId"] as? String
        if let conversationId, !conversationId.isEmpty {
            appChrome.select(.messages)
            appRouter.setActiveTab(.messages)
            appRouter.open(.conversation(conversationId: conversationId), in: .messages)
            return
        }
        // Saved-search / favorite (price drop, closed) banners land on the
        // listing itself (same destination as the machi://listing deep link).
        if let listingId, !listingId.isEmpty {
            appChrome.select(.search)
            appRouter.setActiveTab(.search)
            appRouter.open(.cityListingDetail(listingId: listingId), in: .search)
            return
        }
        // Follow / follow-digest banners open the actor's profile, matching the
        // in-app NotificationsView.route(for:) behavior.
        if (type == .follow || type == .followDigest), let actorId, !actorId.isEmpty {
            appChrome.select(.home)
            appRouter.setActiveTab(.home)
            appRouter.open(.profile(userId: actorId), in: .home)
            return
        }
        // City digest with no specific post routes to the discover/home tab.
        if type == .cityDigest, postId == nil {
            appChrome.select(.home)
            appRouter.setActiveTab(.home)
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
        guard !isSyncingSystemNotifications else { return }
        isSyncingSystemNotifications = true
        defer { isSyncingSystemNotifications = false }
        do {
            if let conversations = try? await MessageRepository(context: modelContext).fetchThreads(currentUserId: user.id) {
                let previousLastMessageDates = messageStore.conversationsById.mapValues(\.lastMessageAt)
                messageStore.setConversations(conversations)
                if shouldWarmChangedMessageThreads {
                    await warmChangedMessageThreads(
                        conversations,
                        previousLastMessageDates: previousLastMessageDates
                    )
                }
                syncAppBadge()
            }
            let response = try await KaiXAPIClient.shared.notifications(kind: "all")
            let all = response.items.map(notificationEntity(from:))
            notificationStore.setNotifications(all)
            notificationStore.setUnreadCount(response.unread_count)
            syncAppBadge()
            // Rating-prompt delight moments (each internally gated to at most one
            // prompt per app version, so firing here is safe every sync):
            //   • an unread like / comment / reply on the user's own content
            //     → "people like my thing" (first-engagement, once per install)
            //   • an unread reply inside a consultation the user started
            //     → "the app worked for me"
            for note in all where !note.isRead {
                switch note.type {
                case .like, .comment, .reply:
                    ReviewPromptService.shared.noteFirstPostEngagement()
                case .message where ReviewPromptService.shared.isInquiryConversation(note.targetConversationId):
                    ReviewPromptService.shared.noteConsultationReply()
                default:
                    break
                }
            }
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
    private var shouldWarmChangedMessageThreads: Bool {
        appChrome.selectedTab == .messages || appChrome.hiddenReasons.contains(.conversation)
    }

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
            .prefix(4)
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
        // Social unread + per-conversation DM unread. NotificationStore's raw
        // unreadCount also counts `.message`/`.listingInquiry` rows, which
        // mirror the very conversations MessageStore already counts — summing
        // that would badge every unread DM twice.
        let totalUnread = notificationStore.socialUnreadCount + messageStore.totalUnreadCount
        SystemNotificationService.shared.syncBadge(unreadCount: totalUnread)
    }

    private func notificationEntity(from dto: KaiXNotificationDTO) -> NotificationEntity {
        NotificationEntity(
            id: dto.id,
            type: NotificationType(rawValue: dto.type) ?? .system,
            actorId: dto.actor?.id ?? dto.actor_id,
            targetPostId: dto.target_post_id,
            targetCommentId: dto.target_comment_id,
            targetListingId: dto.target_listing_id,
            targetConversationId: dto.target_conversation_id,
            content: dto.content ?? "",
            isRead: dto.is_read,
            createdAt: parseServerDate(dto.created_at) ?? .now,
            remoteId: dto.id,
            syncStatus: .synced
        )
    }

    // Delegate to the cached KXDateParsing formatters (see ServerEntityFactory)
    // instead of allocating fresh ISO8601DateFormatters — this runs for every
    // notification row on every 12s poll tick.
    private func parseServerDate(_ raw: String?) -> Date? { KXDateParsing.parse(raw) }

    /// First-run shows the onboarding value cards (guest-first); after that, or
    /// once dismissed, the auth screen. Deferring registration friction behind a
    /// "Browse first" CTA is the cold-start funnel fix.
    @ViewBuilder
    private var entryView: some View {
        if hasSeenOnboarding {
            AuthView(onAuthenticated: completeLogin, onBrowseAsGuest: enterAsGuest, initialMode: entryAuthMode)
        } else {
            OnboardingView(
                onBrowseAsGuest: {
                    hasSeenOnboarding = true
                    enterAsGuest()
                    routeOnboardingPersonaJourney()
                },
                onContinueToAuth: {
                    // Someone tapping "登录 / 注册" from onboarding is here to make an
                    // account — open the AuthView on the register tab.
                    entryAuthMode = .register
                    hasSeenOnboarding = true
                }
            )
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
        syncOnboardingPersonaToGuideProfile()
        bindPendingReferralIfNeeded()
    }

    /// 邀请裂变: consume a pending `/i/<code>` invite once a real session exists.
    /// Registration already binds it inline (via `referral_code`), but a user
    /// who tapped the link and then *logged in* to an existing account needs the
    /// late-bind here. Idempotent server-side (UNIQUE invitee, no payout), so a
    /// double-bind after register is a harmless no-op. Best-effort — a failure
    /// leaves the code pending for a later attempt but never blocks sign-in.
    private func bindPendingReferralIfNeeded() {
        guard let code = ReferralInvite.pendingCode, KaiXBackend.token != nil else { return }
        Task {
            _ = try? await KaiXAPIClient.shared.referralBind(code: code)
            ReferralInvite.clear()
        }
    }

    /// First guest entry from onboarding: a pre-arrival / just-arrived persona
    /// lands directly on its matching Guide journey (mirrors the
    /// machi://guide/journey deep-link routing) so the first screen is the one
    /// that actually helps. first_year / long_term / skipped keep the default
    /// home feed.
    private func routeOnboardingPersonaJourney() {
        guard let key = guideJourneyKey(forArrivalStage: onboardingPersona) else { return }
        appChrome.select(.guide)
        appRouter.setActiveTab(.guide)
        appRouter.open(.guideJourney(key: key), in: .guide)
    }

    /// Push the onboarding persona into the server-side Guide profile
    /// (`arrival_stage`) once a real session exists. The PATCH endpoint is a
    /// full-replace upsert, so read-merge the current profile first and skip
    /// entirely when the server already has a stage (never clobber a value the
    /// user set later in the Guide identity form). Best-effort: any failure is
    /// silent — the persona stays local and personalization keeps working.
    private func syncOnboardingPersonaToGuideProfile() {
        let persona = onboardingPersona
        guard !persona.isEmpty, KaiXBackend.token != nil else { return }
        Task {
            guard let current = try? await KaiXAPIClient.shared.guideProfile() else { return }
            let profile = current.profile
            if let stage = profile?.arrivalStage, !stage.isEmpty { return }
            var payload = KaiXGuideProfileUpdatePayload(
                identityType: profile?.identityType,
                city: profile?.city,
                isInJapan: profile?.isInJapan,
                visaStatus: profile?.visaStatus,
                visaExpiresAt: profile?.visaExpiresAt,
                japaneseLevel: profile?.japaneseLevel,
                targetJapaneseLevel: profile?.targetJapaneseLevel,
                graduationDate: profile?.graduationDate,
                targetEntryTerm: profile?.targetEntryTerm,
                targetIndustry: profile?.targetIndustry,
                targetSchoolType: profile?.targetSchoolType,
                weeklyAvailableMinutes: profile?.weeklyAvailableMinutes,
                needsMaterials: profile?.needsMaterials,
                needsServices: profile?.needsServices
            )
            payload.arrivalStage = persona
            _ = try? await KaiXAPIClient.shared.updateGuideProfile(payload)
        }
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

    /// Runtime session expiry / revocation (a 401 on a real, token-backed
    /// session). Rather than yanking the user to a full login wall — which is
    /// jarring and drops their context — fall back to guest browsing and show a
    /// gentle toast. They can re-login from the profile tab or any gated action.
    /// Matches the documented "session 失效退游客" behavior and the
    /// "登录失效时温和提示，不要突然跳走" requirement.
    private func handleSessionExpired() {
        guard let user = appState.currentUser, !user.isGuest else { return }
        logout()
        enterAsGuest()
        toastManager.show(.custom(
            title: L("sessionExpiredTitle", language),
            message: L("sessionExpiredMessage", language),
            systemImage: "person.crop.circle.badge.clock",
            tint: KXColor.accent,
            technicalDetails: nil
        ), duration: 4)
    }

    private func logout() {
        AuthService.shared.logout()
        // Post-logout the auth screen defaults to login (register is only the
        // default when arriving via onboarding's explicit "登录 / 注册").
        entryAuthMode = .login
        currentUserID = ""
        appState.currentUser = nil
        appRouter.resetAll()
        appChrome.reset()
        sessionStore.invalidate()
        userStore.setCurrentUser(nil)
        resetPerAccountState()
        appState.state = .empty
    }

    private func switchAccount(_ user: UserEntity) {
        AuthService.shared.switchAccount(to: user)
        currentUserID = user.id
        appState.currentUser = user
        appRouter.resetAll()
        appChrome.reset()
        // Wipe the outgoing account's cached content before the incoming account
        // loads — otherwise account B briefly renders A's feed / DMs / badge.
        resetPerAccountState()
        sessionStore.setCurrentUser(user.id)
        userStore.setCurrentUser(user)
        appState.state = .loaded
    }

    /// Tear down every per-account in-memory + on-disk cache so a logout or
    /// account switch never leaks one account's feed, messages, notifications,
    /// comments, search results or unread badge into the next.
    private func resetPerAccountState() {
        messageStore.reset()
        notificationStore.reset()
        postStore.reset()
        commentStore.reset()
        searchStore.reset()
        composeStore.clear()
        MessageRepository.clearCaches()
        KaiXFeedCache.clearAll()
        // Zero the app-icon badge immediately; the next account's sync repopulates
        // it. Leaving the previous count up until the first poll looks like a bug.
        SystemNotificationService.shared.syncBadge(unreadCount: 0)
    }
}
