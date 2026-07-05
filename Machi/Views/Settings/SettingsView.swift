import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.light.rawValue
    @AppStorage("accountEmail") private var accountEmail = ""
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showLogoutConfirm = false
    @State private var isShowingFavorites = false
    @State private var didEnter = false

    let currentUser: UserEntity
    var onLogout: (() -> Void)?
    var onSwitchAccount: ((UserEntity) -> Void)?

    var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    topBar
                        .kxSettingsEntrance(didEnter, index: 0)
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

                    Text("Machi \(KaiXBackend.appVersion)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .kxSettingsEntrance(didEnter, index: 6)
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
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
            SettingsRowLink(icon: "bell.badge", tint: .orange, title: L("notificationSettings", language), value: L("enabled", language), subtitle: L("notificationsHere", language)) {
                NotificationPreferencesView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "bell.and.waves.left.and.right", tint: .mint, title: L("savedSearchesTitle", language), subtitle: L("savedSearchesSubtitle", language)) {
                SavedSearchesView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "hand.raised.fill", tint: .indigo, title: L("privacySettings", language), value: L("public", language), subtitle: L("privacySettingsSubtitle", language)) {
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
            SettingsRowLink(icon: "questionmark.circle", tint: .blue, title: L("helpCenter", language), subtitle: L("navigationReady", language)) {
                HelpCenterView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "bubble.left.and.text.bubble.right", tint: .orange, title: L("feedback", language), subtitle: L("navigationReady", language)) {
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

    private var blockedUserCount: Int {
        KXBlocklist.migrateLegacyIfNeeded(to: currentUser.id)
        let raw = UserDefaults.standard.string(forKey: KXBlocklist.storageKey(for: currentUser.id)) ?? ""
        return raw.split(separator: "|").filter { !$0.isEmpty }.count
    }

    private var blocklistSubtitle: String {
        blockedUserCount == 0 ? L("noBlockedUsers", language) : "\(blockedUserCount) \(L("blockedUsers", language))"
    }

    private var securityEmailValue: String? {
        let email = currentUser.email.isEmpty ? accountEmail : currentUser.email
        return email.isEmpty ? nil : email
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
            .padding(KaiXTheme.horizontalPadding)
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
