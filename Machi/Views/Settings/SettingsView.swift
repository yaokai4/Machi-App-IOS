import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.light.rawValue
    @StateObject private var viewModel = ProfileViewModel()
    // I1-6 币余额前置:钱包行 subtitle 直接显示余额。复用 WalletStore
    // (refreshWallet 只打 walletMe,不碰 StoreKit);游客/加载失败静默回退原文案。
    @StateObject private var walletStore = WalletStore()
    @State private var showLogoutConfirm = false
    @State private var isShowingFavorites = false
    @State private var didEnter = false
    // 通知行显示真实系统授权态(denied → 已关闭),不再恒显「已开启」。
    @State private var notificationStatus: UNAuthorizationStatus?
    // 隐私行显示服务端真实可见性(privacy_protect),不再恒显「公开」。
    @State private var privacyProtected: Bool?

    let currentUser: UserEntity
    var onLogout: (() -> Void)?
    var onSwitchAccount: ((UserEntity) -> Void)?

    var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    topBar
                        .kxSettingsEntrance(didEnter, index: 0)

                    if currentUser.isGuest {
                        // 游客设置页:登录 CTA 取代账号功能区,隐藏账号与安全 / 会员 /
                        // 钱包 / 邀请 / 订单 / 内容仪表盘(未登录点进全是 401),保留地区
                        // 与语言 / 帮助 / 关于 —— 游客真正可用的部分。不显示「退出登录」。
                        guestLoginCard
                            .kxSettingsEntrance(didEnter, index: 1)
                        guestPreferencesSection
                            .kxSettingsEntrance(didEnter, index: 2)
                        serviceSection
                            .kxSettingsEntrance(didEnter, index: 3)
                    } else {
                        SettingsAccountCard(user: currentUser)
                            .kxSettingsEntrance(didEnter, index: 1)

                        // My content dashboard — the tappable home for posts /
                        // favorites (listings + posts) / drafts / media. Replaces the
                        // dead header numbers AND the old "内容管理" list section.
                        contentDashboard
                            .kxSettingsEntrance(didEnter, index: 2)

                        accountSection
                            .kxSettingsEntrance(didEnter, index: 3)
                        serviceSection
                            .kxSettingsEntrance(didEnter, index: 4)

                        if currentUser.role == .admin {
                            adminSection
                                .kxSettingsEntrance(didEnter, index: 5)
                        }

                        Button {
                            showLogoutConfirm = true
                        } label: {
                            Label(L("logout", language), systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .kxGlassSurface(radius: KXRadius.lg)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, KXSpacing.xs)
                        .kxSettingsEntrance(didEnter, index: 5)
                    }

                    Text("Machi \(KaiXBackend.appVersion)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .kxSettingsEntrance(didEnter, index: 6)
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, KXSpacing.md)
                .padding(.bottom, 96)
                .kxReadableWidth()
            }
            .kxPageBackground()
            .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingFavorites) {
            FavoritesHubView(currentUser: currentUser) { listingId in
                isShowingFavorites = false
                dismiss()   // pop settings so the profile tab isn't left stale
                router.open(.cityListingDetail(listingId: listingId), in: .search)
                chrome.select(.search)
                router.setActiveTab(.search)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .environmentObject(postStore)
        }
        .task {
            await viewModel.load(context: modelContext, user: currentUser, postStore: postStore)
        }
        .task {
            guard !currentUser.isGuest, KaiXBackend.token?.isEmpty == false else { return }
            await walletStore.refreshWallet()
        }
        .task {
            // 系统通知授权态是本地读取(无网络);游客也读,通知行对游客不显示但无害。
            notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
        .task {
            // 隐私可见性以服务端为准(privacy_protect)。游客 / 未登录不拉。
            guard !currentUser.isGuest, KaiXBackend.token?.isEmpty == false else { return }
            if let remote = try? await KaiXAPIClient.shared.settings() {
                privacyProtected = remote.privacy_protect
            }
        }
        .onAppear {
            withAnimation(.snappy(duration: 0.38)) {
                didEnter = true
            }
        }
        .confirmationDialog(L("logoutConfirm", language), isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button(L("logout", language), role: .destructive) {
                onLogout?()
                dismiss()
            }
            Button(L("cancel", language), role: .cancel) {}
        } message: {
            Text(L("logoutConfirmMessage", language))
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Text(L("account", language))
                    .kxScaledFont(32, relativeTo: .largeTitle, weight: .bold)
                    .tracking(0)
                Text(L("accountSettingsSubtitle", language))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("close", language))
        }
        .padding(.top, KXSpacing.xs)
    }

    private var accountSection: some View {
        SettingsSectionCard(title: L("accountGroup", language)) {
            // 编辑资料入口:此前只能从个人主页进,在设置里找头像 / 昵称修改的用户
            // 会失败。EditProfileView 自带玻璃头(含返回),故不再叠系统导航栏。
            SettingsRowLink(
                icon: "person.text.rectangle",
                tint: KXColor.accent,
                title: t("编辑资料", "プロフィール編集", "Edit profile"),
                subtitle: t("头像、昵称、简介与所在地", "アイコン・名前・自己紹介・地域", "Avatar, name, bio & location"),
                revealsNavBar: false
            ) {
                EditProfileView(user: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "rectangle.grid.2x2.fill", tint: KXColor.accent, title: L("workbenchTitle", language), subtitle: L("workbenchSettingsSubtitle", language)) {
                MyWorkbenchView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "lock.shield", tint: .purple, title: L("accountSecurity", language), value: securityEmailValue, subtitle: L("accountSecuritySubtitle", language)) {
                AccountSecuritySettingsView(currentUser: currentUser) {
                    onLogout?()
                    dismiss()
                }
            }
            SettingsDivider()
            SettingsRowLink(
                icon: "checkmark.seal.fill",
                tint: .blue,
                title: L("membershipSettingsTitle", language),
                value: currentUser.isVerifiedMember ? L("membershipStatusActive", language) : nil,
                subtitle: L("membershipSettingsSubtitle", language)
            ) {
                MembershipView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(
                icon: "circle.hexagongrid.fill",
                tint: .orange,
                title: walletRowTitle,
                subtitle: walletRowSubtitle
            ) {
                WalletView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(
                icon: "gift.fill",
                tint: .pink,
                title: inviteRowTitle,
                subtitle: inviteRowSubtitle
            ) {
                MyInvitesView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "doc.plaintext.fill", tint: .green, title: L("ordersTitle", language), subtitle: L("ordersSubtitle", language)) {
                MyOrdersView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "globe.asia.australia", tint: .teal, title: L("regionAndLanguage", language), value: regionDisplayLabel, subtitle: L("regionAndLanguageSubtitle", language)) {
                RegionLanguageSettingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "bell.badge", tint: .orange, title: L("notificationSettings", language), value: notificationRowValue, subtitle: L("notificationsHere", language)) {
                NotificationPreferencesView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "bell.and.waves.left.and.right", tint: .mint, title: L("savedSearchesTitle", language), subtitle: L("savedSearchesSubtitle", language)) {
                SavedSearchesView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "hand.raised.fill", tint: .indigo, title: L("privacySettings", language), value: privacyRowValue, subtitle: L("privacySettingsSubtitle", language)) {
                PrivacySettingsView(currentUser: currentUser)
            }
        }
    }

    private var walletRowTitle: String {
        switch language {
        case .en: return "Points Wallet"
        case .ja: return "ポイント"
        default: return "Machi 币钱包"
        }
    }

    private var walletRowSubtitle: String {
        // 余额到手就亮出来;拿不到(游客/网络失败)静默回退原文案。
        if let balance = walletStore.wallet?.balancePoints {
            switch language {
            case .en: return "Balance \(balance) coins · top-up and history"
            case .ja: return "残高 \(balance) コイン・チャージ・履歴"
            default: return "余额 \(balance) 币 · 充值与记录"
            }
        }
        switch language {
        case .en: return "Machi Coins balance, top-up and history"
        case .ja: return "Machi ポイントの残高・チャージ・履歴"
        default: return "Machi 币余额、充值与记录"
        }
    }

    private var inviteRowTitle: String {
        KXListingCopy.pickText(language, "我的邀请", "招待", "Invite friends")
    }

    private var inviteRowSubtitle: String {
        KXListingCopy.pickText(language,
            "邀请好友注册，双方都得 Machi 币",
            "友達を招待して二人ともコイン獲得",
            "Invite friends — you both earn Machi Coins")
    }

    /// Four tappable tiles: my posts / favorites (listings + posts) / drafts /
    /// media library. Favorites opens the two-tab hub as a sheet (its listing
    /// taps route into the Search tab); the rest push in the settings stack.
    private var contentDashboard: some View {
        HStack(spacing: KXSpacing.sm) {
            NavigationLink {
                MyPostsView(currentUser: currentUser)
            } label: {
                dashboardTile(icon: "doc.text.fill", tint: KXColor.accent, count: viewModel.postCount, label: L("posts", language))
            }
            .buttonStyle(.plain)

            Button {
                isShowingFavorites = true
            } label: {
                dashboardTile(icon: "heart.fill", tint: .pink, count: viewModel.bookmarkCount, label: L("bookmarks", language))
            }
            .buttonStyle(.plain)

            NavigationLink {
                DraftsSettingsView(currentUser: currentUser)
            } label: {
                dashboardTile(icon: "tray.full.fill", tint: .purple, count: viewModel.draftCount, label: L("drafts", language))
            }
            .buttonStyle(.plain)

            NavigationLink {
                MediaLibraryView(currentUser: currentUser)
            } label: {
                dashboardTile(icon: "photo.on.rectangle.fill", tint: .cyan, count: viewModel.mediaCount, label: L("mediaLibrary", language))
            }
            .buttonStyle(.plain)
        }
    }

    private func dashboardTile(icon: String, tint: Color, count: Int, label: String) -> some View {
        VStack(spacing: KXSpacing.xs) {
            Image(systemName: icon)
                .kxScaledFont(15, weight: .semibold)
                .foregroundStyle(tint)
                .frame(height: 20)
            Text(NumberFormatterUtils.compact(count))
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KXSpacing.md)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .kxGlassSurface(radius: KXRadius.md)
    }

    private var regionDisplayLabel: String {
        if let region = RegionStore.shared.current {
            return "\(region.countryEmoji) \(region.cityName)"
        }
        return L("pickRegion", language)
    }

    private var contentLanguageLabel: String {
        LanguageManager.shared.preferred.title(language)
    }

    private var serviceSection: some View {
        // 帮助与反馈 only — merchant verification is a business function and lives
        // in the workbench (经营后台), not in settings (职责清晰).
        SettingsSectionCard(title: L("helpGroup", language)) {
            SettingsRowLink(icon: "questionmark.circle", tint: .blue, title: L("helpCenter", language), subtitle: t("常见问题与使用指南", "よくある質問と使い方", "FAQ & how-to guides")) {
                HelpCenterView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "bubble.left.and.text.bubble.right", tint: .orange, title: L("feedback", language), subtitle: t("告诉我们哪里可以做得更好", "改善点を教えてください", "Tell us what we can do better")) {
                FeedbackView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "info.circle", tint: .gray, title: L("aboutKaiX", language), value: KaiXBackend.appVersion, subtitle: "\(L("version", language)) \(KaiXBackend.appVersion)") {
                AboutKaiXView()
            }
            SettingsDivider()
            SettingsRowLink(
                icon: "externaldrive",
                tint: .indigo,
                title: KXListingCopy.pickText(language, "数据管理", "データ管理", "Data & storage"),
                subtitle: KXListingCopy.pickText(language, "缓存与存储清理", "キャッシュと保存容量", "Cache & storage")
            ) {
                DataManagementView()
            }
        }
    }

    // Admin-only tools. Shown solely for role == .admin; every endpoint behind
    // it is independently gated by require_admin server-side.
    private var adminSection: some View {
        SettingsSectionCard(title: L("adminGroup", language)) {
            SettingsRowLink(
                icon: "megaphone.fill",
                tint: .red,
                title: L("adminPushTitle", language),
                subtitle: L("adminPushSubtitle", language)
            ) {
                AdminPushComposeView(currentUser: currentUser)
            }
        }
    }

    private var blockedUserCount: Int {
        KXBlocklist.migrateLegacyIfNeeded(to: currentUser.id)
        let raw = UserDefaults.standard.string(forKey: KXBlocklist.storageKey(for: currentUser.id)) ?? ""
        return raw.split(separator: "|").filter { !$0.isEmpty }.count
    }

    private var blocklistSubtitle: String {
        blockedUserCount == 0 ? L("noBlockedUsers", language) : "\(blockedUserCount) \(L("blockedUsers", language))"
    }

    private var securityEmailValue: String? {
        // 只信 currentUser.email(服务端真相)。旧的设备全局 "accountEmail" 回退
        // 会把上一账号的邮箱显示在未绑邮箱的账号 B 上,且明文 PII 落 UserDefaults
        // ——该键已废弃并在 ContactSettingsView 里清除。
        currentUser.email.isEmpty ? nil : currentUser.email
    }

    private func t(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    /// 通知行真值:未拉到(nil)不显示 value;denied → 已关闭;notDetermined →
    /// 未开启;授权 / 临时 / 短时 → 已开启。
    private var notificationRowValue: String? {
        guard let status = notificationStatus else { return nil }
        switch status {
        case .authorized, .provisional, .ephemeral:
            return L("enabled", language)
        case .denied:
            return t("已关闭", "オフ", "Off")
        case .notDetermined:
            return t("未开启", "未設定", "Not set")
        @unknown default:
            return nil
        }
    }

    /// 隐私行真值:未拉到(nil)不显示 value;privacy_protect 打开 → 保护中,
    /// 否则 → 公开。
    private var privacyRowValue: String? {
        guard let protected = privacyProtected else { return nil }
        return protected ? t("保护中", "保護中", "Protected") : L("public", language)
    }

    /// 游客版账号卡:登录 / 注册 CTA(复用 guestProfile 文案体系)。点击走
    /// GuestGate 弹登录 sheet。既是转化位,也让「未登录被要求退出登录」的荒诞消失。
    private var guestLoginCard: some View {
        VStack(spacing: KXSpacing.md) {
            Image(systemName: "person.crop.circle.badge.plus")
                .kxScaledFont(46, weight: .semibold)
                .foregroundStyle(KXColor.accent)
            Text(L("guestProfileTitle", language))
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(L("guestProfileSubtitle", language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                GuestSession.requireSignedIn(currentUser, reason: L("guestLoginRequired", language))
            } label: {
                Text(L("loginOrRegister", language))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(KXColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(KXColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.guestLogin")
        }
        .padding(KXSpacing.lg)
        .frame(maxWidth: .infinity)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    /// 游客可用的偏好:地区与语言(本地设置,不需登录)。
    private var guestPreferencesSection: some View {
        SettingsSectionCard(title: t("偏好", "設定", "Preferences")) {
            SettingsRowLink(icon: "globe.asia.australia", tint: .teal, title: L("regionAndLanguage", language), value: regionDisplayLabel, subtitle: L("regionAndLanguageSubtitle", language)) {
                RegionLanguageSettingsView(currentUser: currentUser)
            }
        }
    }
}

private extension View {
    func kxSettingsEntrance(_ active: Bool, index: Int) -> some View {
        self
            .opacity(active ? 1 : 0)
            .offset(y: active ? 0 : 12)
            .animation(.snappy(duration: 0.38).delay(Double(index) * 0.035), value: active)
    }
}

private struct SettingsAccountCard: View {
    @Environment(\.appLanguage) private var language
    let user: UserEntity

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(alignment: .top, spacing: KXSpacing.md) {
                AvatarView(user: user, size: 58)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                    .shadow(color: .black.opacity(0.055), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(user.displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        KXUserBadge(user: user)
                    }
                    Text("@\(user.username)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    SettingsRolePill(user: user)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)
            }

            Text(user.bio.isEmpty ? L("defaultBio", language) : user.bio)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}

private struct SettingsRolePill: View {
    @Environment(\.appLanguage) private var language
    let user: UserEntity

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(tint)
        .padding(.horizontal, KXSpacing.sm)
        .frame(height: 24)
        .background(tint.opacity(0.10), in: Capsule())
    }

    private var title: String {
        if user.isMachiOfficialAccount { return L("machiOfficial", language) }
        if user.isVerifiedMember { return L("machiVerifiedMember", language) }
        if user.role == .member { return L("regularUser", language) }
        return user.creatorBadge.isEmpty ? L("creator", language) : user.creatorBadge
    }

    private var icon: String {
        if user.isMachiOfficialAccount { return "checkmark.shield.fill" }
        if user.isVerifiedMember { return "checkmark.seal.fill" }
        return user.role == .member ? "person.fill" : "sparkles"
    }

    private var tint: Color {
        if user.isMachiOfficialAccount { return KXColor.official }
        if user.isVerifiedMember { return .blue }
        return user.role == .member ? .secondary : KXColor.accent
    }
}

struct ProfileCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @StateObject private var actionModel = ProfileViewModel()
    @State private var selectedDestination: ProfileCollectionDestination?
    let title: String
    let posts: [PostEntity]
    let mediaByPostId: [String: [MediaEntity]]
    let currentUser: UserEntity

    var body: some View {
        ScrollView {
            LazyVStack(spacing: KXSpacing.md) {
                if posts.isEmpty {
                    EmptyStateView(title: title, subtitle: L("noContent", language), systemImage: "tray")
                        .padding(.top, 32)
                } else {
                    ForEach(posts) { post in
                        let displayedPost = postStore.post(id: post.id) ?? post
                        PostCardView(
                            post: displayedPost,
                            author: currentUser,
                            mediaItems: mediaByPostId[displayedPost.id] ?? [],
                            currentUser: currentUser,
                            onOpen: { selectedDestination = .post(postId: displayedPost.id, focusComments: false) },
                            onAuthor: { selectedDestination = .profile(userId: displayedPost.authorId) },
                            onTag: { selectedDestination = .topic(tag: $0) },
                            onComment: { selectedDestination = .post(postId: displayedPost.id, focusComments: true) },
                            onLike: { Task { await actionModel.toggleLike(context: modelContext, post: displayedPost, currentUser: currentUser, profileUser: currentUser, postStore: postStore) } },
                            onBookmark: { Task { await actionModel.toggleBookmark(context: modelContext, post: displayedPost, currentUser: currentUser, profileUser: currentUser, postStore: postStore) } },
                            onRepost: { Task { await actionModel.repost(context: modelContext, post: displayedPost, currentUser: currentUser, profileUser: currentUser, postStore: postStore) } },
                            onQuoteRepost: { content in
                                Task { await actionModel.quoteRepost(context: modelContext, post: displayedPost, currentUser: currentUser, profileUser: currentUser, content: content, postStore: postStore) }
                            }
                        )
                        .equatable()
                    }
                }
            }
            .padding(KXSpacing.screen)
        }
        .kxPageBackground()
        .navigationTitle(title)
        .navigationDestination(item: $selectedDestination) { destination in
            switch destination {
            case .post(let postId, let focusComments):
                KXRoutedPostDetailView(
                    postId: postId,
                    currentUser: currentUser,
                    initialFocus: focusComments ? .comments : .none
                )
            case .profile(let userId):
                ProfileView(currentUser: currentUser, profileUserId: userId, tracksChrome: false, showsBackButton: true)
            case .topic(let tag):
                TopicDetailView(tag: tag, currentUser: currentUser)
            }
        }
    }
}

private enum ProfileCollectionDestination: Identifiable, Hashable {
    case post(postId: String, focusComments: Bool)
    case profile(userId: String)
    case topic(tag: String)

    var id: String {
        switch self {
        case .post(let postId, let focusComments):
            "post:\(postId):\(focusComments)"
        case .profile(let userId):
            "profile:\(userId)"
        case .topic(let tag):
            "topic:\(tag.normalizedTopicName)"
        }
    }
}

struct LanguageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue
    @State private var message: String?

    let currentUser: UserEntity

    var body: some View {
        SettingsFormPage(title: L("language", language)) {
            Text(L("currentLanguage", language))
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: KXSpacing.xxs) {
                ForEach(AppLanguage.allCases) { option in
                    KXSelectRow(
                        leadingSymbol: option == .system ? "gearshape.fill" : "character.bubble.fill",
                        title: option == .system ? L("systemAppearance", language) : option.title,
                        isSelected: appLanguageCode == option.rawValue,
                        action: { persistAppLanguage(option) }
                    )
                }
            }

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func persistAppLanguage(_ option: AppLanguage) {
        appLanguageCode = option.rawValue
        let serverValue = serverLanguageCode(for: option)
        currentUser.appLanguage = serverValue
        try? modelContext.save()
        guard KaiXBackend.token != nil else { return }

        Task {
            do {
                let dto = try await KaiXAPIClient.shared.updateRegionLanguage(["app_language": serverValue])
                await MainActor.run {
                    UserRepository.apply(dto, to: currentUser)
                    try? modelContext.save()
                    message = nil
                }
            } catch {
                await MainActor.run {
                    message = error.kaixUserMessage
                }
            }
        }
    }

    private func serverLanguageCode(for option: AppLanguage) -> String {
        let resolved = option == .system
            ? AppLanguage.resolved(from: AppLanguage.system.rawValue)
            : option
        switch resolved {
        case .zh, .system: return "zh-Hans"
        case .ja: return "ja"
        case .en: return "en"
        }
    }
}
