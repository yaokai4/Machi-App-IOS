import SwiftData
import SwiftUI
import UserNotifications

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
    // P-4 游客召回钩子:游客会话计数 + 「问过一次就永不再问」标记(拒绝、
    // 滑掉、或系统权限已 denied 都算问过)。计数只在 maybePromptGuestRecall
    // 里、每个进程一次地自增。
    @AppStorage("guestRecallSessionCount") private var guestRecallSessionCount = 0
    @AppStorage("guestRecallPromptDone") private var guestRecallPromptDone = false
    @State private var isShowingGuestRecallPrompt = false
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

    /// P-4: count a guest browsing session exactly once per process — the
    /// bootstrap task re-runs on every login/logout (task id = currentUserID),
    /// and re-counting those transitions would fake "multiple sessions" inside
    /// one launch.
    private static var didCountGuestSession = false

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
        // P-4 游客召回:第 2 次游客会话后的一次性通知软引导(阈值与「只问
        // 一次」规则见 maybePromptGuestRecall)。
        .sheet(isPresented: $isShowingGuestRecallPrompt) {
            GuestRecallPromptSheet {
                Task { await SystemNotificationService.shared.requestGuestAuthorization() }
            }
            .environment(\.appLanguage, language)
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
            // P-4 游客召回钩子。放在下面的通知轮询 guard 之前 —— 游客没有
            // token,那个 guard 对游客直接 return,永远走不到这里之后。
            if appState.currentUser?.isGuest == true {
                await maybePromptGuestRecall()
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .kaixIAPVerificationPending)) { _ in
            // A background IAP verification failed — the charge is safe (StoreKit
            // re-delivers it) but tell the user it's confirming rather than
            // leaving it silently pending.
            toastManager.show(
                .custom(
                    title: L("iapVerifyPending", language),
                    message: L("iapVerifyPendingHelp", language),
                    systemImage: "hourglass",
                    tint: .orange,
                    technicalDetails: nil
                ),
                duration: 6
            )
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
        // A follow-digest's payload actorId is unreliable — the recipient's own
        // id when delivered locally, "" over APNs — so route it to the current
        // user's own profile (where the follower list lives), regardless of the
        // payload, so local / APNs / in-app all agree (matches route(for:)).
        if type == .followDigest {
            appChrome.select(.home)
            appRouter.setActiveTab(.home)
            if let uid = appState.currentUser?.id, !uid.isEmpty {
                appRouter.open(.profile(userId: uid), in: .home)
            }
            return
        }
        // A single follow banner opens the follower's profile.
        if type == .follow, let actorId, !actorId.isEmpty {
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
            // Comment / reply banners focus the specific comment, matching the
            // in-app route(for:) behavior; everything else opens the post top.
            if type == .comment || type == .reply {
                appRouter.open(.postDetailComment(postId: postId, commentId: userInfo?["commentId"] as? String), in: .home)
            } else {
                appRouter.open(.postDetail(postId: postId), in: .home)
            }
        }
    }

    /// 会话复核:每个 await 之后 token 可能已被 401/登出清空,或已切到另一账号
    /// (scenePhase / kaiXConversationShouldRefresh 触发的同步 Task 不随会话取消)。
    /// 任何写 store / 角标的动作前都必须复核,否则在途响应会把上个账号的通知、
    /// 未读数回填进 resetPerAccountState() 刚清空的 store——跨账号泄漏。
    private func isSessionStillCurrent(_ user: UserEntity) -> Bool {
        !Task.isCancelled && KaiXBackend.token != nil && appState.currentUser?.id == user.id
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
                guard isSessionStillCurrent(user) else { return }
                let previousLastMessageDates = messageStore.conversationsById.mapValues(\.lastMessageAt)
                // 合并进 store 里既有的线程实例,而不是整批换新实例:收件箱 List
                // (MessagesViewModel.threads)与 ChatView 持有的是旧实例引用,换新
                // 实例后 ChatView 标记已读只写得到新实例,行内未读徽章要滞留到下
                // 一次收件箱轮询(~8s)才与 Tab 角标一致。实例身份稳定后未读数
                // 只有一份事实,标记已读立即反映到所有屏幕。
                let merged = conversations.map { fetched -> MessageThreadEntity in
                    guard let existing = messageStore.conversationsById[fetched.id],
                          existing !== fetched else { return fetched }
                    existing.participantIdsRaw = fetched.participantIdsRaw
                    existing.lastMessage = fetched.lastMessage
                    existing.lastMessageAt = fetched.lastMessageAt
                    existing.unreadCount = fetched.unreadCount
                    existing.updatedAt = fetched.updatedAt
                    existing.remoteId = fetched.remoteId
                    existing.syncStatusRaw = fetched.syncStatusRaw
                    existing.deletedAt = fetched.deletedAt
                    existing.cursor = fetched.cursor
                    return existing
                }
                messageStore.setConversations(merged)
                if shouldWarmChangedMessageThreads {
                    await warmChangedMessageThreads(
                        merged,
                        previousLastMessageDates: previousLastMessageDates,
                        for: user
                    )
                }
                guard isSessionStillCurrent(user) else { return }
                syncAppBadge()
            }
            let response = try await KaiXAPIClient.shared.notifications(kind: "all")
            guard isSessionStillCurrent(user) else { return }
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
            // 会话在 actor 拉取期间失效/切号:别再替上个账号弹系统横幅。
            guard isSessionStillCurrent(user) else { return }
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
        previousLastMessageDates: [String: Date],
        for user: UserEntity
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
                // 拉消息期间可能已登出/切号:store 刚被清空,别把上个账号的
                // 聊天内容回填进去。
                guard isSessionStillCurrent(user) else { return }
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
            customTitle: dto.title ?? "",
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
                    // P-3: pre_arrival / just_arrived 人设曾在这里直接跳进
                    // Guide journey——第一屏变成一张待办清单,看不到社区本体。
                    // 现在所有人设一律落社区首页 feed:HomeTimelineView 顶部的
                    // HomeJourneyNextStepCard 读同一个 onboardingPersona(经
                    // guideJourneyKey(forArrivalStage:) 映射)把该人设的旅程作为
                    // 一键钩子常驻呈现,指引仍一眼可达,但先看到的是内容。
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

    /// P-4 游客召回钩子:游客的第 2 次会话(冷启动)后,用一张三语软引导
    /// sheet 轻声问一次要不要「开启新内容提醒」。规则:
    ///   • 会话每个进程只计一次(见 didCountGuestSession),阈值 ≥2 —— 不在
    ///     第一次打开时打扰,回头客才值得问。
    ///   • 每位游客一生最多询问一次:sheet 出现即记「问过」,拒绝 / 滑掉都
    ///     不再弹(guestRecallPromptDone)。
    ///   • 系统权限已是 authorized(例如曾登录时授权过)就不弹卡片,直接
    ///     静默注册 APNs 把 token 缓存好;已 denied 则问了也没用,记跳过。
    ///   • 与 guestGate 登录 sheet 撞车时让路且不记「问过」,下次会话再试。
    /// 服务端 push-token 端点要求登录态(web/server.py api_register_push_token
    /// → require_user),游客 token 只缓存在本地,登录后由既有的
    /// refreshRegistration() 自动补上传 —— 详见 PushTokenService.registerForGuest。
    private func maybePromptGuestRecall() async {
        if !Self.didCountGuestSession {
            Self.didCountGuestSession = true
            guestRecallSessionCount += 1
        }
        guard !guestRecallPromptDone, guestRecallSessionCount >= 2 else { return }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            // 已有权限,无需再问 —— 只补一次 APNs 注册,把 token 缓存到位。
            guestRecallPromptDone = true
            await PushTokenService.registerForGuest()
            return
        case .denied:
            guestRecallPromptDone = true
            return
        default:
            break
        }
        // 让 feed 先站稳:这张卡应该像温和的建议,而不是启动插屏。
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        guard !Task.isCancelled,
              appState.currentUser?.isGuest == true,
              !guestGate.isPromptingLogin else { return }
        guestRecallPromptDone = true
        isShowingGuestRecallPrompt = true
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
        // 磁盘 Store 兜底:生产不写业务数据进 SwiftData(服务器唯一真相),但
        // 老版本升级上来的设备可能残留旧库内容。登出/切号时安排下次启动清空
        // (不能删活着的 SQLite 文件),保证磁盘上不留任何前账号痕迹。
        KaiXDatabaseContainer.requestLocalDataWipe()
        // Zero the app-icon badge immediately; the next account's sync repopulates
        // it. Leaving the previous count up until the first poll looks like a bug.
        SystemNotificationService.shared.syncBadge(unreadCount: 0)
    }
}

/// P-4 游客召回钩子:一次性的三语通知软引导。系统权限弹窗一生只有一次
/// 机会,先用这张卡讲清价值(同城新帖 / 活动第一时间知道)再触发系统
/// 弹窗;点「暂不需要」或滑掉都视为问过,不再打扰(由呈现方记账)。
private struct GuestRecallPromptSheet: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    /// Invoked on opt-in — the caller owns the actual system permission
    /// request + APNs registration (SystemNotificationService.requestGuestAuthorization).
    let onEnable: () -> Void

    var body: some View {
        VStack(spacing: KXSpacing.xl) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(KXColor.accent)
                .frame(width: 76, height: 76)
                .background(KXColor.accentSoft, in: Circle())
                .padding(.top, KXSpacing.xl)

            VStack(spacing: KXSpacing.sm) {
                Text(KXListingCopy.pickText(
                    language,
                    "开启新内容提醒",
                    "新着コンテンツの通知をオン",
                    "Turn on new-content alerts"
                ))
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

                Text(KXListingCopy.pickText(
                    language,
                    "同城的新帖子、活动和干货,第一时间告诉你。以后随时可以在系统设置里关闭。",
                    "同じ街の新しい投稿・イベント・お役立ち情報をいち早くお届けします。設定からいつでもオフにできます。",
                    "Be the first to know about new posts, events and tips in your city. You can turn alerts off anytime in Settings."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, KXSpacing.xl)

            VStack(spacing: KXSpacing.sm) {
                Button {
                    onEnable()
                    dismiss()
                } label: {
                    Text(KXListingCopy.pickText(language, "开启提醒", "通知をオンにする", "Turn on alerts"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(KXColor.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(KXColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guestRecall.enable")

                Button {
                    dismiss()
                } label: {
                    Text(KXListingCopy.pickText(language, "暂不需要", "今はしない", "Not now"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guestRecall.dismiss")
            }
            .padding(.horizontal, KXSpacing.xl)

            Spacer(minLength: 0)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
