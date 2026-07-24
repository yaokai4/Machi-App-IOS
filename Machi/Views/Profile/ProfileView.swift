import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var router: AppRouter
    // 逐账号拉黑键(KXBlocklist),与 ChatView / 设置▸黑名单共用同一事实源。
    // 旧的设备全局 "blockedUserIds" 会把账号 A 的拉黑漏到同机账号 B 的个人页,
    // 且与其余屏幕的逐账号键分裂——init 里迁移一次后统一走逐账号键。
    @AppStorage private var blockedUserIdsRaw: String
    @StateObject private var viewModel = ProfileViewModel()
    @State private var loadedProfileUser: UserEntity?
    @State private var profileLoadState: ScreenState = .idle
    @State private var profileTab = PersonalProfileTab.posts
    @State private var isFollowing = false
    @State private var isFollowWorking = false
    @State private var menuMessage: String?
    @State private var isShowingSettings = false
    @State private var isShowingWorkbench = false
    @State private var followListKind: FollowListKind?
    @State private var mutualCount: Int?
    @State private var reputation: KaiXReputationProfileDTO?
    @State private var showReputationSheet = false
    @State private var isRefreshingProfile = false
    @State private var scheduledProfileRefreshTask: Task<Void, Never>?

    let currentUser: UserEntity
    let profileUserId: String
    private let initialProfileUser: UserEntity?
    private let refreshToken: UUID?
    let sourceTab: AppTab
    let tracksChrome: Bool
    var showsBackButton = false
    var onLogout: (() -> Void)?
    var onSwitchAccount: ((UserEntity) -> Void)?

    init(
        currentUser: UserEntity,
        profileUserId: String? = nil,
        profileUser: UserEntity? = nil,
        refreshToken: UUID? = nil,
        sourceTab: AppTab = .profile,
        tracksChrome: Bool = true,
        showsBackButton: Bool = false,
        onLogout: (() -> Void)? = nil,
        onSwitchAccount: ((UserEntity) -> Void)? = nil
    ) {
        self.currentUser = currentUser
        self.profileUserId = profileUserId ?? profileUser?.id ?? currentUser.id
        self.initialProfileUser = profileUser
        self.refreshToken = refreshToken
        self.sourceTab = sourceTab
        self.tracksChrome = tracksChrome
        self.showsBackButton = showsBackButton
        self.onLogout = onLogout
        self.onSwitchAccount = onSwitchAccount
        KXBlocklist.migrateLegacyIfNeeded(to: currentUser.id)
        _blockedUserIdsRaw = AppStorage(wrappedValue: "", KXBlocklist.storageKey(for: currentUser.id))
        _loadedProfileUser = State(initialValue: profileUser ?? ((profileUserId == nil || profileUserId == currentUser.id) ? currentUser : nil))
    }

    private var profileUser: UserEntity {
        loadedProfileUser ?? initialProfileUser ?? currentUser
    }

    private var isCurrentUser: Bool {
        currentUser.id == profileUserId
    }

    private var blockedUserIds: [String] {
        blockedUserIdsRaw
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var isBlocked: Bool {
        blockedUserIds.contains(profileUserId)
    }

    private var visiblePosts: [PostEntity] {
        switch profileTab {
        case .posts: viewModel.authoredPosts
        case .replies: viewModel.repliedPosts
        case .media: viewModel.mediaPosts
        case .likes: viewModel.likedPosts
        }
    }

    private var availableTabs: [PersonalProfileTab] {
        PersonalProfileTab.allCases
    }

    private var isProfileVisibleForRefresh: Bool {
        !tracksChrome || chrome.selectedTab == sourceTab
    }

    /// I2-6 游客「我的」预览墙:不再是一堵纯登录硬墙,而是灰态的主页结构预览
    /// —— 工作台可以直接进(PersonalWorkbenchView 对游客本就可浏览,动作时才
    /// 弹登录),收藏 / 声望点击时才弹 GuestGate,把转化点从「进门」后移到
    /// 「动手」。会员 / 钱包入口保留(App Review 承诺:付费面对游客始终可寻,
    /// 不可删)。
    private var guestProfilePrompt: some View {
        ScrollView {
            VStack(spacing: KXSpacing.lg) {
                VStack(spacing: KXSpacing.md) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .kxScaledFont(58, weight: .semibold)
                        .foregroundStyle(KXColor.accent)
                    Text(L("guestProfileTitle", language))
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(L("guestProfileSubtitle", language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Button {
                        GuestGate.shared.requireLogin(L("guestLoginRequired", language))
                    } label: {
                        Text(L("loginOrRegister", language))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(KXColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(KXColor.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 36)
                    .padding(.top, KXSpacing.xs)
                }
                .padding(.top, KXSpacing.xl)

                // 灰态结构预览:登录后主页有什么,先让人看见。
                VStack(spacing: KXSpacing.sm) {
                    guestPreviewRow(
                        icon: "square.grid.2x2.fill",
                        title: KXListingCopy.pickText(language, "我的工作台", "マイワークベンチ", "My Workbench"),
                        subtitle: KXListingCopy.pickText(
                            language,
                            "Todo、日历、申请、账单和证件期限，可先随意看看",
                            "Todo・カレンダー・申請・支払い・証明書の期限。まず見てみよう",
                            "Tasks, calendar, applications, bills & expiries — browse freely"
                        ),
                        locked: false
                    ) {
                        router.open(.personalWorkbench)
                    }
                    guestPreviewRow(
                        icon: "bookmark.fill",
                        title: KXListingCopy.pickText(language, "我的收藏", "ブックマーク", "Bookmarks"),
                        subtitle: KXListingCopy.pickText(
                            language,
                            "登录后同步收藏的帖子和房源",
                            "ログインすると保存した投稿・物件を同期",
                            "Log in to sync saved posts and listings"
                        ),
                        locked: true
                    ) {
                        GuestGate.shared.requireLogin(KXListingCopy.pickText(
                            language,
                            "登录后可以收藏帖子和房源，随时回看。",
                            "ログインすると投稿や物件を保存して、いつでも見返せます。",
                            "Log in to bookmark posts and listings and come back anytime."
                        ))
                    }
                    guestPreviewRow(
                        icon: "rosette",
                        title: KXListingCopy.pickText(language, "我的声望", "マイ評価", "My reputation"),
                        subtitle: KXListingCopy.pickText(
                            language,
                            "发帖和互助会累计声望等级",
                            "投稿や助け合いで評価レベルが上がります",
                            "Posting and helping others builds your reputation"
                        ),
                        locked: true
                    ) {
                        GuestGate.shared.requireLogin(KXListingCopy.pickText(
                            language,
                            "登录后开始积累你的声望等级。",
                            "ログインして評価レベルを積み上げましょう。",
                            "Log in to start building your reputation."
                        ))
                    }
                }
                .padding(.horizontal, 36)

                // Browse the paid tiers without an account — the subscriptions and
                // coin packs are visible here so they're always locatable (including
                // for App Review, which browses as a guest); the Buy action prompts
                // for sign-in. Do NOT gate these behind the Settings gear, which a
                // guest can never reach.
                VStack(spacing: KXSpacing.sm) {
                    NavigationLink {
                        MembershipView(currentUser: currentUser)
                    } label: {
                        guestPaidEntryLabel(icon: "checkmark.seal.fill", title: L("membershipTitle", language))
                    }
                    NavigationLink {
                        WalletView(currentUser: currentUser)
                    } label: {
                        guestPaidEntryLabel(icon: "circle.hexagongrid.fill",
                                            title: KXListingCopy.pickText(language, "Machi 币钱包", "Machi コインウォレット", "Machi Coins Wallet"))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 36)
            }
            .padding(.bottom, chrome.bottomContentPadding + KXSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 灰态预览行:结构可见但视觉降一档(次级图标 + 降透明标题)。locked 的行
    /// 尾部是锁,点击弹 GuestGate;可浏览的行(工作台)尾部是箭头,直接进。
    private func guestPreviewRow(icon: String, title: String, subtitle: String, locked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.72))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: KXSpacing.sm)
                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, KXSpacing.sm + 2)
            .padding(.horizontal, KXSpacing.md)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func guestPaidEntryLabel(icon: String, title: String) -> some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(KXColor.accent)
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: KXSpacing.sm)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, KXSpacing.sm + 2)
        .padding(.horizontal, KXSpacing.md)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.separator, lineWidth: 0.8))
    }

    private var displayedFollowerCount: Int {
        userStore.followerCounts[profileUser.id] ?? profileUser.followerCount
    }

    private var displayedFollowingCount: Int {
        userStore.followingCounts[profileUser.id] ?? profileUser.followingCount
    }

    var body: some View {
        profileBodyContent
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: profileUserId) {
            await loadProfileAndContent()
            if isCurrentUser, !currentUser.isGuest {
                reputation = try? await KaiXAPIClient.shared.reputationMe()
            } else if !isCurrentUser {
                // Surface the viewed user's public trust level (badge on others'
                // profiles), mirroring Web/admin which already show reputation.
                reputation = try? await KaiXAPIClient.shared.reputationUser(profileUserId)
            }
        }
        .onChange(of: chrome.selectedTab) { _, tab in
            guard tracksChrome, tab == sourceTab else { return }
            scheduleProfileRefresh()
        }
        .onChange(of: refreshToken) { _, _ in
            scheduleProfileRefresh(currentUserOnly: true)
        }
        .onChange(of: postStore.profilePostIds[profileUserId] ?? []) { _, _ in
            scheduleProfileRefresh()
        }
        .onChange(of: postStore.likedPostIds) { _, _ in
            scheduleProfileRefresh(currentUserOnly: true)
        }
        .onChange(of: postStore.bookmarkedPostIds) { _, _ in
            scheduleProfileRefresh(currentUserOnly: true)
        }
        .onChange(of: postStore.repostedPostIds) { _, _ in
            scheduleProfileRefresh(currentUserOnly: true)
        }
        .onDisappear {
            scheduledProfileRefreshTask?.cancel()
            scheduledProfileRefreshTask = nil
        }
        .modifier(ProfileAlertsModifier(menuMessage: $menuMessage, transientError: $viewModel.transientError, language: language))
        .modifier(ProfilePresentationModifier(
            isShowingSettings: $isShowingSettings,
            isShowingWorkbench: $isShowingWorkbench,
            followListKind: $followListKind,
            showReputationSheet: $showReputationSheet,
            currentUser: currentUser,
            profileUser: profileUser,
            isCurrentUser: isCurrentUser,
            reputation: reputation,
            language: language,
            onLogout: onLogout,
            onSwitchAccount: onSwitchAccount
        ))
    }

    private var profileBodyContent: AnyView {
        if isCurrentUser && currentUser.isGuest {
            return AnyView(guestProfilePrompt)
        }

        switch profileLoadState {
        case .idle, .loading:
            return AnyView(
                KXFeedSkeleton()
                    .padding(.horizontal, KXSpacing.screen)
                    .padding(.top, KXSpacing.md)
            )
        case .error(let message):
            return AnyView(ErrorStateView(message: message) {
                Task { await loadProfileAndContent() }
            })
        case .empty:
            return AnyView(EmptyStateView(title: L("unknownUser", language), subtitle: L("noContent", language), systemImage: "person.crop.circle"))
        case .loaded:
            return AnyView(loadedProfileContent)
        }
    }

    private var loadedProfileContent: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, KXSpacing.sm)
                .padding(.bottom, KXSpacing.md)
                .kxGlassBar(ignoresTopSafeArea: true)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.35)
                }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: KXSpacing.md, pinnedViews: [.sectionHeaders]) {
                    profileHeader
                    if isCurrentUser {
                        personalWorkbenchEntry
                    }
                    // tab 栏做吸顶 Section header:长列表里回切 tab 不必再滚回顶部。
                    // 玻璃底只在吸顶时有感知,防止下方卡片从 picker 后面透出。
                    Section {
                        stateContent
                    } header: {
                        PersonalProfileTabPicker(tabs: availableTabs, selection: $profileTab)
                            .padding(.horizontal, KXSpacing.xxs)
                            .padding(.vertical, KXSpacing.xs)
                            .background {
                                // 与页面同色 + 左右负边距出血到屏幕边:不吸顶时与
                                // 背景融为一体,吸顶时照样挡住下方滚动内容。此前用
                                // kxGlassBar 的毛玻璃矩形两侧内缩,边缘发虚像一层
                                // 「隔膜」——pageBackground 正是页面渐变的中点色,
                                // 铺满后看不出任何矩形边界。
                                KXColor.pageBackground
                                    .padding(.horizontal, -KXSpacing.screen)
                            }
                    }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, KXSpacing.sm)
                .padding(.bottom, (showsBackButton ? KXSpacing.xl : chrome.bottomContentPadding) + 24)
                .kxReadableWidth()
            }
            .refreshable {
                await loadProfileAndContent(showLoading: false)
            }
        }
    }

    /// Strong entry into the personal 我的工作台 (Todo / 日历 / 申请 / 账单 / 合同 /
    /// 证件). Shown only on the current user's own profile, directly under the
    /// header. Distinct from the publish/商家 "经营工作台" reached via the top-bar
    /// grid icon.
    private var personalWorkbenchEntry: some View {
        Button {
            router.open(.personalWorkbench)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(KXColor.onAccent)
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(colors: [KXColor.accent, KXColor.accent.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(KXListingCopy.pickText(language, "我的工作台", "マイワークベンチ", "My Workbench"))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(KXListingCopy.pickText(
                        language,
                        "Todo、日历、申请、账单、合同和证件期限",
                        "Todo・カレンダー・申請・支払い・契約・証明書の期限",
                        "Tasks, calendar, applications, bills, contracts & document expiries"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(KXSpacing.lg)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous).stroke(KXColor.separator.opacity(0.6), lineWidth: 0.8))
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
        .accessibilityIdentifier("profile.personalWorkbench")
    }


    /// Localized current-level name (zh/ja/en) for the compact reputation chip.
    private var reputationLevelName: String {
        guard let rep = reputation else { return "" }
        return KXListingCopy.pickText(
            language, rep.levelName ?? "", rep.levelNameJa ?? "", rep.levelNameEn ?? ""
        )
    }

    private func loadProfileAndContent(showLoading: Bool = true) async {
        // A guest viewing their OWN profile only sees the login CTA, so the
        // authed fetch here is pointless (it would 401). Skip it — viewing
        // *other* users' public profiles as a guest still loads normally.
        if isCurrentUser && currentUser.isGuest { return }
        if isRefreshingProfile, !showLoading { return }
        isRefreshingProfile = true
        defer { isRefreshingProfile = false }

        let hadLoadedProfile = profileLoadState == .loaded && loadedProfileUser != nil
        if showLoading || !hadLoadedProfile {
            profileLoadState = .loading
        }
        do {
            // Pull the authoritative profile from the server first so identity
            // tags, custom tags and per-type listing counts are always fresh
            // (these only ride the user-detail endpoint, not feed payloads).
            if profileUserId != currentUser.id {
                if let dto = try? await KaiXAPIClient.shared.userDetail(profileUserId) {
                    loadedProfileUser = UserRepository.entity(from: dto)
                }
            }
            let resolvedUser: UserEntity?
            if profileUserId == currentUser.id {
                resolvedUser = currentUser
            } else if let fetched = try await UserRepository(context: modelContext).fetchUser(id: profileUserId) {
                resolvedUser = fetched
            } else {
                resolvedUser = initialProfileUser?.id == profileUserId ? initialProfileUser : nil
            }

            guard let resolvedUser else {
                loadedProfileUser = nil
                profileLoadState = .empty
                return
            }

            loadedProfileUser = resolvedUser
            userStore.register(resolvedUser)
            if isCurrentUser {
                userStore.register(currentUser)
            }
            profileLoadState = .loaded
            await viewModel.load(context: modelContext, user: resolvedUser, postStore: postStore)
            await refreshFollowState()
            await refreshMutualCountIfNeeded()
        } catch {
            if hadLoadedProfile {
                profileLoadState = .loaded
                viewModel.transientError = error.kaixUserMessage
            } else {
                loadedProfileUser = nil
                profileLoadState = .error(error.kaixUserMessage)
            }
        }
    }

    private func scheduleProfileRefresh(currentUserOnly: Bool = false) {
        guard !currentUserOnly || isCurrentUser else { return }
        guard isProfileVisibleForRefresh else { return }
        guard profileLoadState == .loaded || profileLoadState == .empty else { return }
        guard !isRefreshingProfile else { return }

        scheduledProfileRefreshTask?.cancel()
        scheduledProfileRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await loadProfileAndContent(showLoading: false)
        }
    }

    /// Public web URL for the system share sheet — resolves back into the app
    /// via Universal Links (`/u/<id>` → profile).
    private var profileShareURL: URL {
        URL(string: "https://machicity.com/u/\(profileUserId)") ?? URL(string: "https://machicity.com")!
    }

    /// Share-sheet title: the person's display name (or @handle fallback).
    private var profileShareTitle: String {
        let name = profileUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "@\(profileUser.username)" : name
    }

    private var topBar: some View {
        HStack {
            if showsBackButton {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .kxGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KXListingCopy.pickText(language, "返回", "戻る", "Back"))
            } else if isCurrentUser {
                Button {
                    isShowingWorkbench = true
                } label: {
                    Image(systemName: "rectangle.grid.2x2.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .kxGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.workbench")
                .accessibilityLabel(L("workbenchTitle", language))
            } else {
                Color.clear
                    .frame(width: 42, height: 42)
            }

            Spacer()

            Text(isCurrentUser ? L("profile", language) : profileUser.displayName)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            Spacer()

            if isCurrentUser {
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .kxGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("settings", language))
            } else {
                Menu {
                    ShareLink(
                        item: profileShareURL,
                        subject: Text(profileShareTitle),
                        preview: SharePreview(profileShareTitle)
                    ) {
                        Label(L("shareProfile", language), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = "@\(profileUser.username)"
                        menuMessage = L("profileCopied", language)
                    } label: {
                        Label(L("copyLink", language), systemImage: "at")
                    }
                    Button(L("reportUser", language), role: .destructive) {
                        // C3: file a real report instead of only toasting.
                        if currentUser.isGuest { GuestGate.shared.requireLogin(L("guestReasonReport", language)) }
                        else {
                            let targetId = profileUserId
                            Task {
                                do {
                                    try await KaiXAPIClient.shared.reportUser(targetId, reason: "other")
                                    menuMessage = L("reportRecorded", language)
                                } catch {
                                    menuMessage = error.kaixUserMessage
                                }
                            }
                        }
                    }
                    if isBlocked {
                        Button(L("unblockUser", language)) {
                            toggleBlockUser()
                        }
                    } else {
                        Button(L("blockUser", language), role: .destructive) {
                            toggleBlockUser()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .kxGlassCircle()
                }
                .accessibilityLabel(L("more", language))
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .loading, .idle:
            KXFeedSkeleton()
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, KXSpacing.md)
                .frame(maxWidth: .infinity)
        case .error(let message):
            ErrorStateView(message: message) {
                Task { await loadProfileAndContent() }
            }
        case .empty, .loaded:
            if visiblePosts.isEmpty {
                EmptyStateView(title: profileTab.emptyTitle(language), subtitle: L("noContent", language), systemImage: profileTab.emptyIcon)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
            } else {
                ForEach(visiblePosts) { post in
                    let displayedPost = postStore.post(id: post.id) ?? post
                    let originalPost = displayedPost.repostOfPostId.flatMap { postStore.post(id: $0) }
                    let isQuoteRepost = originalPost != nil && !displayedPost.previewText.isEmpty
                    let targetPost = isQuoteRepost ? displayedPost : (originalPost ?? displayedPost)
                    PostCardView(
                        post: displayedPost,
                        author: viewModel.authors[displayedPost.authorId] ?? profileUser,
                        mediaItems: viewModel.mediaByPostId[displayedPost.id] ?? [],
                        currentUser: currentUser,
                        originalPost: originalPost,
                        originalAuthor: originalPost.flatMap { viewModel.authors[$0.authorId] },
                        originalMediaItems: originalPost == nil ? [] : (viewModel.mediaByPostId[originalPost?.id ?? ""] ?? []),
                        onOpen: { router.open(.postDetail(postId: targetPost.id)) },
                        onOpenOriginal: { if let originalPost { router.open(.postDetail(postId: originalPost.id)) } },
                        onAuthor: { router.open(.profile(userId: targetPost.authorId)) },
                        onTag: { router.open(.topic(tag: $0)) },
                        onComment: { router.open(.postDetailComment(postId: targetPost.id, commentId: nil)) },
                        onLike: { Task { await viewModel.toggleLike(context: modelContext, post: targetPost, currentUser: currentUser, profileUser: profileUser, postStore: postStore) } },
                        onBookmark: { Task { await viewModel.toggleBookmark(context: modelContext, post: targetPost, currentUser: currentUser, profileUser: profileUser, postStore: postStore) } },
                        onRepost: { Task { await viewModel.repost(context: modelContext, post: targetPost, currentUser: currentUser, profileUser: profileUser, postStore: postStore) } },
                        onQuoteRepost: { content in
                            Task { await viewModel.quoteRepost(context: modelContext, post: targetPost, currentUser: currentUser, profileUser: profileUser, content: content, postStore: postStore) }
                        }
                    )
                    .equatable()
                }
            }
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            ZStack(alignment: .bottomLeading) {
                CoverGradientView(user: profileUser)

                // Seat the avatar exactly half-into the cover: bottom-anchored,
                // then pushed down by half its diameter (82 / 2 = 41) so its
                // center lands on the cover's bottom edge — the X-style straddle.
                AvatarView(user: profileUser, size: KXAvatarSize.profile)
                    .overlay(Circle().stroke(KXColor.cardBackground, lineWidth: 4))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .offset(x: 14, y: 41)
            }
            .padding(.bottom, 46)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(profileUser.displayName)
                            .font(KXTypography.title2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        KXUserBadge(user: profileUser)
                            .font(.title3)
                    }
                    Text("@\(profileUser.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer()

                profileActionButton
            }

            Text(profileUser.bio.isEmpty ? L("defaultBio", language) : profileUser.bio)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            profileMetaRow

            // 身份区与数据区之间只靠留白分层——hairline 在这种密度下是多余
            // 的线条噪音,留白足以立住层级,也更干净。
            profileStatsStrip
                .padding(.top, KXSpacing.xs)

            profileBadgeRow
                .padding(.top, KXSpacing.xs)

            listingCountTags
        }
        .padding(KXSpacing.lg)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    /// 地区 + 加入时间的低噪 metadata 行:小图标 tertiary、间隔点连接,与
    /// 帖子卡 meta 行同一视觉语言。日期只到年月——精确到日只剩数字噪音。
    private var profileMetaRow: some View {
        HStack(spacing: KXSpacing.sm) {
            if let locationText = profileLocationText {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(locationText)
                }
                Text("·")
                    .foregroundStyle(.quaternary)
            }
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(joinDateText)
            }
        }
        .font(KXTypography.metaEmphasis)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var profileLocationText: String? {
        if let regionLabel = profileRegionLabel { return regionLabel }
        let location = profileUser.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return location.isEmpty ? nil : location
    }

    /// 「2026年5月加入」/「2026年5月に参加」/「Joined May 2026」——语序按语言
    /// 组装(en 习惯动词前置),年月格式用对应 locale 保证「年/月」字与月名正确。
    private var joinDateText: String {
        let joined = profileUser.joinDate
        switch language {
        case .ja:
            return "\(joined.formatted(.dateTime.year().month().locale(Locale(identifier: "ja_JP"))))に参加"
        case .en:
            return "Joined \(joined.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "en_US"))))"
        default:
            return "\(joined.formatted(.dateTime.year().month().locale(Locale(identifier: "zh_CN"))))加入"
        }
    }

    private var profileRegionLabel: String? {
        if !profileUser.country.isEmpty, !profileUser.city.isEmpty,
           let region = KaiXRegionDirectory.make(
            country: profileUser.country,
            province: profileUser.province.isEmpty ? nil : profileUser.province,
            city: profileUser.city
           ) {
            return KaiXRegionDirectory.localizedShortLabel(region, language: language)
        }
        return nil
    }

    /// Tight, X-style metric strip — only the four/five numbers the user
    /// actually checks. 等宽分列 + 细分隔线让它读成数据块而非一句话;
    /// 超大动态字号下等宽列必然截断,退回 FlowLayout 自动换行。
    @ViewBuilder
    private var profileStatsStrip: some View {
        if dynamicTypeSize.isAccessibilitySize {
            FlowLayout(spacing: 14) {
                profileStatCells
            }
        } else {
            // 列间不再放竖线:等宽留白本身就分得清列,少一层线条更精致。
            HStack(spacing: 0) {
                followMetricButton(kind: .following)
                followMetricButton(kind: .followers)
                if isCurrentUser {
                    followMetricButton(kind: .mutual)
                }
                ProfileMetricInline(value: NumberFormatterUtils.compact(viewModel.postCount), title: L("posts", language))
                ProfileMetricInline(value: NumberFormatterUtils.compact(viewModel.likeCount), title: L("likes", language))
            }
        }
    }

    /// FlowLayout 降级分支复用同一组 cell,保持列版与流版数据一致。
    @ViewBuilder
    private var profileStatCells: some View {
        followMetricButton(kind: .following)
        followMetricButton(kind: .followers)
        if isCurrentUser {
            followMetricButton(kind: .mutual)
        }
        ProfileMetricInline(value: NumberFormatterUtils.compact(viewModel.postCount), title: L("posts", language))
        ProfileMetricInline(value: NumberFormatterUtils.compact(viewModel.likeCount), title: L("likes", language))
    }

    /// Identity + merchant + creator badges — categorical not numeric,
    /// so they sit on their own line below the stats block.
    private var profileBadgeRow: some View {
        FlowLayout(spacing: 6) {
            ProfileRoleBadge(title: roleTitle, isOfficial: profileUser.isMachiOfficialAccount)
            // Compact reputation chip sits right beside the role badge —
            // tap to open the full level pathway + how-to-level-up sheet.
            if let rep = reputation, let level = rep.level {
                ProfileReputationChip(level: level, name: reputationLevelName) {
                    showReputationSheet = true
                }
            }
            if !profileUser.creatorBadge.isEmpty {
                ProfileRoleBadge(title: profileUser.creatorBadge)
            }
            if profileUser.merchantVerified {
                ProfileRoleBadge(title: L("merchantVerified", language))
            }
            if profileUser.isMerchant && !profileUser.merchantVerified {
                ProfileRoleBadge(title: L("merchantPending", language))
            }
            if !profileUser.contentLanguagePreference.isEmpty {
                ProfileRoleBadge(title: ContentLanguage(rawValue: profileUser.contentLanguagePreference)?.title(language) ?? profileUser.contentLanguagePreference)
            }
            // Admin-assigned custom tags (优质房东 / 资深卖家…).
            ForEach(profileUser.customTags, id: \.self) { tag in
                ProfileCustomTagChip(title: tag)
            }
        }
    }

    /// Tappable per-type listing counts — open this user's published items of a
    /// type (出售二手 5 → their secondhand listings). Accurate listing counts
    /// from the profile-detail payload, not post counts.
    @ViewBuilder
    private var listingCountTags: some View {
        let tags = profileListingCountTags
        if !tags.isEmpty {
            // 与徽章行之间加 hairline、胶囊统一 26 高度——商业计数与身份徽章
            // 同节奏排布,避免三种胶囊高度在卡内打架。
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                Divider()
                    .overlay(KXColor.separator)
                FlowLayout(spacing: 7) {
                    ForEach(tags, id: \.type) { tag in
                        Button {
                            router.open(.userListings(userId: profileUser.id, type: tag.type, title: "\(profileUser.displayName) · \(tag.label)"))
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tag.icon).font(.caption2.weight(.bold))
                                Text(tag.label).font(.caption.weight(.bold))
                                Text("\(tag.count)")
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(KXColor.accent)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 18, minHeight: 16)
                                    .background(KXColor.accentSoft, in: Capsule())
                            }
                            .foregroundStyle(KXColor.livingInk)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(KXColor.livingSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(KXColor.livingInk.opacity(0.12), lineWidth: 0.8))
                        }
                        .buttonStyle(KXPressableStyle(scale: 0.96))
                    }
                }
            }
            .padding(.top, KXSpacing.xs)
        }
    }

    /// Listing types worth surfacing as tappable tags, merged (job+hiring → 招聘).
    private var profileListingCountTags: [(type: String, label: String, icon: String, count: Int)] {
        let counts = profileUser.listingCounts
        let order: [(type: String, label: String, icon: String, keys: [String])] = [
            ("secondhand", "二手", "bag.fill", ["secondhand"]),
            ("rental", "租房", "house.fill", ["rental"]),
            ("job", "招聘", "briefcase.fill", ["job", "hiring"]),
            ("local_service", "本地服务", "storefront.fill", ["local_service"]),
            ("discount", "优惠", "tag.fill", ["discount"]),
        ]
        return order.compactMap { entry in
            let total = entry.keys.reduce(0) { $0 + (counts[$1] ?? 0) }
            guard total > 0 else { return nil }
            return (entry.type, entry.label, entry.icon, total)
        }
    }

    private func followMetricButton(kind: FollowListKind) -> some View {
        let value: Int
        switch kind {
        case .following:
            value = displayedFollowingCount
        case .followers:
            value = displayedFollowerCount
        case .mutual:
            value = mutualCount ?? 0
        }
        let title = kind.metricTitle(language)

        return Button {
            followListKind = kind
        } label: {
            ProfileMetricInline(value: NumberFormatterUtils.compact(value), title: title)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(value)")
    }

    @ViewBuilder
    private var profileActionButton: some View {
        if isCurrentUser {
            NavigationLink {
                EditProfileView(user: currentUser)
            } label: {
                Label(L("editProfile", language), systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, KXSpacing.md)
                    .frame(height: 34)
                    .kxGlassCapsule()
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: KXSpacing.sm) {
                Button {
                    guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以发私信。", "ログインするとメッセージを送れます。", "Sign in to send messages.")) else { return }
                    guard !isBlocked else {
                        menuMessage = L("userBlocked", language)
                        return
                    }
                    Task {
                        do {
                            let thread = try await MessageRepository(context: modelContext).getOrCreateThread(currentUserId: currentUser.id, peerUserId: profileUser.id)
                            router.open(.conversation(conversationId: thread.id))
                        } catch {
                            menuMessage = error.kaixUserMessage
                        }
                    }
                } label: {
                    Image(systemName: "envelope")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .kxGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("messages", language))

                Button {
                    if currentUser.isGuest { GuestGate.shared.requireLogin(L("guestReasonFollow", language)); return }
                    Task { await toggleFollow() }
                } label: {
                    Text(isFollowing ? L("followed", language) : L("follow", language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isFollowing ? Color.primary : KXColor.accent)
                        .padding(.horizontal, KXSpacing.md)
                        .frame(height: 36)
                        .kxGlassCapsule(isSelected: !isFollowing)
                }
                .disabled(isFollowWorking)
                .buttonStyle(.plain)
            }
        }
    }

    private func refreshFollowState() async {
        guard !isCurrentUser else { return }
        isFollowing = (try? await UserRepository(context: modelContext).isFollowing(
            followerId: currentUser.id,
            followingId: profileUser.id
        )) ?? false
        userStore.setFollowing(isFollowing, userId: profileUser.id)
        userStore.updateCounts(userId: currentUser.id, followers: currentUser.followerCount, following: currentUser.followingCount)
        userStore.updateCounts(userId: profileUser.id, followers: profileUser.followerCount, following: profileUser.followingCount)
    }

    private func refreshMutualCountIfNeeded() async {
        guard isCurrentUser else {
            mutualCount = nil
            return
        }
        do {
            let users = try await KaiXAPIClient.shared.mutualMessageFriends(limit: 100)
            mutualCount = UserRepository.uniqueUsers(users.map(UserRepository.entity(from:))).count
        } catch {
            mutualCount = mutualCount ?? 0
        }
    }

    private func toggleFollow() async {
        guard !isCurrentUser, !isFollowWorking else { return }
        isFollowWorking = true
        defer { isFollowWorking = false }
        do {
            isFollowing = try await UserRepository(context: modelContext).toggleFollow(
                currentUser: currentUser,
                targetUser: profileUser
            )
            userStore.register([currentUser, profileUser])
            userStore.setFollowing(isFollowing, userId: profileUser.id)
            userStore.updateCounts(userId: currentUser.id, followers: currentUser.followerCount, following: currentUser.followingCount)
            userStore.updateCounts(userId: profileUser.id, followers: profileUser.followerCount, following: profileUser.followingCount)
        } catch {
            await refreshFollowState()
        }
    }

    private func toggleBlockUser() {
        guard !isCurrentUser else { return }
        var ids = blockedUserIds
        let isNowBlocking: Bool
        if ids.contains(profileUserId) {
            ids.removeAll { $0 == profileUserId }
            menuMessage = L("userUnblocked", language)
            isNowBlocking = false
        } else {
            ids.append(profileUserId)
            menuMessage = L("userBlocked", language)
            isNowBlocking = true
        }
        // Optimistic UI update.
        let snapshot = blockedUserIdsRaw
        blockedUserIdsRaw = ids.removingDuplicates().joined(separator: "|")
        // For a signed-in account the server blocklist is the source of truth,
        // and Settings ▸ Blocklist REPLACES this local mirror on its next load.
        // A silently-swallowed write failure here would leave the block only
        // local, then get erased on the next reload — a silent un-block of a
        // harassment/safety control. So the server write must stick: snapshot +
        // roll back on failure, matching BlocklistSettingsView.unblock.
        // A guest has no server session (setBlock would 401) and its local
        // mirror is never clobbered by loadBlockedUsers, so its block stays
        // purely local — don't attempt the sync or the rollback.
        guard !currentUser.isGuest else { return }
        let targetId = profileUserId
        Task {
            do {
                try await KaiXAPIClient.shared.setBlock(targetId, isNowBlocking)
            } catch {
                blockedUserIdsRaw = snapshot
                menuMessage = error.kaixUserMessage
            }
        }
    }

    private var roleTitle: String {
        if profileUser.isMachiOfficialAccount {
            return L("machiOfficial", language)
        }
        if profileUser.isVerifiedMember {
            return L("machiVerifiedMember", language)
        }
        switch profileUser.role {
        case .admin, .creator: return L("creator", language)
        case .member: return L("regularUser", language)
        }
    }
}

private struct ProfileAlertsModifier: ViewModifier {
    @Binding var menuMessage: String?
    @Binding var transientError: String?
    let language: AppLanguage

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = transientError ?? menuMessage {
                    KXInlineNotice(message: message) {
                        transientError = nil
                        menuMessage = nil
                    }
                    .padding(.top, 76)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
    }
}

private struct ProfilePresentationModifier: ViewModifier {
    @Binding var isShowingSettings: Bool
    @Binding var isShowingWorkbench: Bool
    @Binding var followListKind: FollowListKind?
    @Binding var showReputationSheet: Bool

    let currentUser: UserEntity
    let profileUser: UserEntity
    let isCurrentUser: Bool
    let reputation: KaiXReputationProfileDTO?
    let language: AppLanguage
    let onLogout: (() -> Void)?
    let onSwitchAccount: ((UserEntity) -> Void)?

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(currentUser: currentUser, onLogout: onLogout, onSwitchAccount: onSwitchAccount)
            }
            .fullScreenCover(isPresented: $isShowingWorkbench) {
                WorkbenchFullScreenView(isPresented: $isShowingWorkbench, currentUser: currentUser)
            }
            .sheet(item: $followListKind) { kind in
                NavigationStack {
                    FollowListView(profileUser: profileUser, currentUser: currentUser, kind: kind)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showReputationSheet) {
                if let rep = reputation {
                    ReputationDetailSheet(reputation: rep, isSelf: isCurrentUser, language: language)
                        .presentationDragIndicator(.visible)
                }
            }
    }
}

private struct WorkbenchFullScreenView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState

    @Binding var isPresented: Bool
    let currentUser: UserEntity

    var body: some View {
        NavigationStack {
            MyWorkbenchView(currentUser: currentUser) { listingId in
                openPublishedListingFromWorkbench(listingId)
            }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .kxGlassCircle()
                        }
                        .buttonStyle(KXPressableStyle(scale: 0.94, dim: 0.88))
                        .accessibilityIdentifier("workbench.close")
                        .accessibilityLabel(KXListingCopy.pickText(language, "关闭", "閉じる", "Close"))
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
        .kxPageBackground()
        .onChange(of: router.routeRevision) { _, _ in
            // Workbench sub-views (e.g. 咨询管理 / 我的咨询) navigate with
            // router.open(...), which targets a TAB navigation stack that lives
            // *behind* this fullScreenCover — so "查看详情" / "补充沟通" pushed a
            // destination the user could never see and the buttons looked dead.
            // Dismiss the cover whenever a route is pushed so the destination
            // becomes visible on its tab. Internal workbench navigation uses
            // NavigationLink (the cover's own stack) and does NOT bump
            // routeRevision, so this only fires for genuine external routes.
            if isPresented { isPresented = false }
        }
    }

    private func openPublishedListingFromWorkbench(_ listingId: String) {
        isPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            chrome.select(.profile)
            router.setActiveTab(.profile)
            router.open(.cityListingDetail(listingId: listingId), in: .profile)
        }
    }
}

private enum FollowListKind: String, Identifiable {
    case followers
    case following
    case mutual

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .followers: L("followersList", language)
        case .following: L("followingList", language)
        case .mutual: KXListingCopy.pickText(language, "互关好友", "相互フォロー", "Mutual friends")
        }
    }

    func metricTitle(_ language: AppLanguage) -> String {
        switch self {
        case .followers: L("followers", language)
        case .following: L("followingCount", language)
        case .mutual: KXListingCopy.pickText(language, "互关", "相互", "Mutual")
        }
    }

    func emptyTitle(_ language: AppLanguage) -> String {
        switch self {
        case .followers: L("emptyFollowers", language)
        case .following: L("emptyFollowing", language)
        case .mutual: KXListingCopy.pickText(language, "还没有互关好友", "相互フォローはまだありません", "No mutual friends yet")
        }
    }

    var emptyIcon: String {
        switch self {
        case .followers: "person.2"
        case .following: "person.crop.circle.badge.checkmark"
        case .mutual: "person.2.wave.2"
        }
    }
}

/// 纵向 metric cell:数字大字在上、标签小字在下——靠字号层级而非字重区分,
/// 读起来是数据块而不是一句话。monospacedDigit 稳住数字宽度,numericText
/// 让刷新时逐位滚动;ScaledMetric 保证 20pt 跟随动态字体放大。
private struct ProfileMetricInline: View {
    let value: String
    let title: String
    // 对齐 KXTypography.title2 的 19-20pt 尺度。
    @ScaledMetric(relativeTo: .title3) private var valueSize: CGFloat = 19

    var body: some View {
        // 数字与标签贴得更紧(2pt)读成一个整体;标签加一点字距,小字才有
        // 精致感——这两处是「数据块」与「一排文字」的分界。
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: valueSize, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
            Text(title)
                .font(KXTypography.meta)
                .tracking(0.25)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, KXSpacing.xs)
        // 等宽列版里撑满本列;FlowLayout 降级版按内容自然宽度换行。
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct ProfileRoleBadge: View {
    let title: String
    var isOfficial = false

    private var tint: Color { isOfficial ? KXColor.official : KXColor.accent }

    var body: some View {
        Label(title, systemImage: isOfficial ? "checkmark.shield.fill" : "checkmark.seal.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .frame(height: 26)
            // Faint tinted rim so identity tags read as distinct chips, not loose
            // floating text (the user asked badges to have a light border).
            .background(tint.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.8))
    }
}

/// Admin-assigned custom tag — a soft bordered chip (no seal icon) in a
/// neutral tone. 曾用 livingWarm 橙红,但那属于商业 listing 语境(见
/// DesignSystem surface ownership 注释);中性灰让徽章行只剩 accent 一个色系。
private struct ProfileCustomTagChip: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.primary.opacity(0.7))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(KXColor.softBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
    }
}

/// Compact reputation pill (Lv.N · 等级名) that sits beside the role badge.
/// Tapping opens the full reputation/level sheet.
private struct ProfileReputationChip: View {
    let level: Int
    let name: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "rosette")
                    .font(.caption2.weight(.bold))
                Text("Lv.\(level)")
                    .font(.caption.weight(.heavy))
                if !name.isEmpty {
                    Text(name)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .opacity(0.55)
            }
            .foregroundStyle(KXColor.accent)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(KXColor.accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(KXColor.accent.opacity(0.26), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lv.\(level) \(name)")
    }
}

/// The full reputation system, surfaced from the compact chip: current standing
/// + XP progress, the perks unlocked at the current level, the complete 10-tier
/// pathway, and concrete ways to level up. Makes the level system transparent
/// instead of a one-line label.
private struct ReputationDetailSheet: View {
    let reputation: KaiXReputationProfileDTO
    let isSelf: Bool
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var levels: [KaiXReputationLevelDTO] = []
    @State private var loaded = false

    private func pick(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    private var currentLevel: Int { reputation.level ?? 1 }
    private var currentName: String {
        KXListingCopy.pickText(language, reputation.levelName ?? "", reputation.levelNameJa ?? "", reputation.levelNameEn ?? "")
    }
    private var trust: String { reputation.publicTrustLabel ?? reputation.reputationLabel ?? "" }
    private var currentLevelStartXp: Int { levels.first(where: { $0.level == currentLevel })?.xpRequired ?? 0 }
    private var currentPrivileges: [String] { levels.first(where: { $0.level == currentLevel })?.privileges ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    if !currentPrivileges.isEmpty {
                        section(pick("当前等级权益", "現在のレベル特典", "Current perks")) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(currentPrivileges, id: \.self) { perk in
                                    HStack(alignment: .top, spacing: 9) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(KXColor.accent)
                                        Text(perk)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                    if !levels.isEmpty {
                        section(pick("等级路线", "レベルの道のり", "Level pathway")) {
                            VStack(spacing: 0) {
                                ForEach(levels) { lv in
                                    levelRow(lv)
                                    if lv.level != levels.last?.level {
                                        Divider().opacity(0.12)
                                    }
                                }
                            }
                        }
                    }
                    section(pick("如何提升信誉", "信頼の上げ方", "How to level up")) {
                        VStack(alignment: .leading, spacing: KXSpacing.md) {
                            ForEach(levelUpTips, id: \.text) { tip in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: tip.icon)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(KXColor.accent)
                                        .frame(width: 22)
                                    Text(tip.text)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    Text(pick("信誉用于建立社区信任，等级越高可解锁更多发布与参与权益；违规会降低信誉。",
                              "信頼はコミュニティの安心のためのもので、レベルが上がるほど投稿・参加の特典が増えます。違反すると下がります。",
                              "Reputation builds community trust — higher levels unlock more posting and participation perks; violations lower it."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, KXSpacing.xs)
                }
                .padding(KXSpacing.lg)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(isSelf ? pick("我的信誉", "信頼レベル", "My reputation") : pick("信誉等级", "信頼レベル", "Reputation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(pick("完成", "完了", "Done")) { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .task {
                guard !loaded else { return }
                levels = (try? await KaiXAPIClient.shared.reputationLevels()) ?? []
                loaded = true
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                        .fill(LinearGradient(colors: [KXColor.accent, KXColor.accent.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                    Image(systemName: "rosette")
                        .font(.title.weight(.bold))
                        .foregroundStyle(KXColor.onAccent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(currentName.isEmpty ? "Lv.\(currentLevel)" : "Lv.\(currentLevel) · \(currentName)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    if !trust.isEmpty {
                        Text(trust)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if isSelf { progressView }
        }
        .padding(KXSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
    }

    @ViewBuilder private var progressView: some View {
        if let xp = reputation.xp, let nextXp = reputation.nextLevelXp, nextXp > currentLevelStartXp {
            let denom = max(1, nextXp - currentLevelStartXp)
            let frac = min(1.0, max(0.0, Double(xp - currentLevelStartXp) / Double(denom)))
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(KXColor.accent.opacity(0.14))
                        Capsule().fill(KXColor.accent).frame(width: max(6, geo.size.width * frac))
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("\(xp) XP")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                    Spacer()
                    if let toNext = reputation.xpToNext, toNext > 0 {
                        Text(pick("还需 \(toNext) XP 升到 Lv.\(currentLevel + 1)", "あと \(toNext) XP で Lv.\(currentLevel + 1)", "\(toNext) XP to Lv.\(currentLevel + 1)"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if reputation.nextLevelXp == nil, reputation.xp != nil {
            Text(pick("已达到最高等级", "最高レベルに到達", "Top level reached"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func levelRow(_ lv: KaiXReputationLevelDTO) -> some View {
        let name = KXListingCopy.pickText(language, lv.nameZh ?? "", lv.nameJa ?? "", lv.nameEn ?? "")
        let isCurrent = lv.level == currentLevel
        let reached = lv.level <= currentLevel
        return HStack(spacing: KXSpacing.md) {
            ZStack {
                Circle()
                    .fill(reached ? KXColor.accent : KXColor.separator.opacity(0.28))
                    .frame(width: 30, height: 30)
                Text("\(lv.level)")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(reached ? .white : .secondary)
            }
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(name)
                    .font(.subheadline.weight(isCurrent ? .bold : .semibold))
                    .foregroundStyle(.primary)
                Text(pick("满 \(lv.xpRequired) XP", "\(lv.xpRequired) XP", "\(lv.xpRequired) XP"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Text(pick("当前", "現在", "Now"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .padding(.horizontal, KXSpacing.sm)
                    .frame(height: 22)
                    .background(KXColor.accent.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 9)
        .opacity(reached ? 1 : 0.7)
    }

    private var levelUpTips: [(icon: String, text: String)] {
        [
            ("square.and.pencil", pick("发布真实、有用的城市生活内容", "リアルで役立つ街の投稿をする", "Post genuine, useful local content")),
            ("hand.thumbsup", pick("内容获得点赞、评论与收藏", "いいね・コメント・保存を集める", "Earn likes, comments and saves")),
            ("checkmark.seal", pick("完善个人资料并绑定邮箱", "プロフィール完成とメール認証", "Complete your profile & verify email")),
            ("shield.lefthalf.filled", pick("长期保持无违规记录", "違反のない状態を保つ", "Keep a clean, violation-free record")),
        ]
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, KXSpacing.xs)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
        }
    }
}

private struct FollowListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var userStore: UserStore
    @State private var users: [UserEntity] = []
    @State private var state: ScreenState = .idle
    @State private var workingUserIds: Set<String> = []
    @State private var transientMessage: String?

    let profileUser: UserEntity
    let currentUser: UserEntity
    let kind: FollowListKind

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                LoadingView()
            case .empty:
                EmptyStateView(title: kind.emptyTitle(language), subtitle: "@\(profileUser.username)", systemImage: kind.emptyIcon)
                    .padding(KXSpacing.screen)
            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await load() }
                }
                .padding(KXSpacing.screen)
            case .loaded:
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(users) { user in
                            FollowUserCard(
                                user: user,
                                isCurrentUser: user.id == currentUser.id,
                                isFollowing: userStore.followStateByUserId[user.id] ?? false,
                                isWorking: workingUserIds.contains(user.id),
                                language: language
                            ) {
                                dismiss()
                                router.open(.profile(userId: user.id))
                            } onMessage: {
                                Task { await openMessage(with: user) }
                            } onToggleFollow: {
                                Task { await toggleFollow(user) }
                            }
                        }
                    }
                    .padding(.horizontal, KXSpacing.screen)
                    .padding(.top, KXSpacing.md)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await load()
                }
            }
        }
        .kxPageBackground()
        .navigationTitle(kind.title(language))
        .overlay(alignment: .top) {
            if let transientMessage {
                KXInlineNotice(message: transientMessage) {
                    self.transientMessage = nil
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, KXSpacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("ok", language)) {
                    dismiss()
                }
            }
        }
        .task(id: "\(profileUser.id)-\(kind.id)") {
            await load()
        }
    }

    private func load() async {
        state = .loading
        do {
            let repository = UserRepository(context: modelContext)
            switch kind {
            case .followers:
                users = try await repository.fetchFollowers(userId: profileUser.id)
            case .following:
                users = try await repository.fetchFollowing(userId: profileUser.id)
            case .mutual:
                users = try await fetchMutualUsers(repository: repository)
            }
            users = UserRepository.uniqueUsers(users).filter { $0.deletedAt == nil }
            userStore.register(users)
            await refreshFollowStates()
            state = users.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    private func fetchMutualUsers(repository: UserRepository) async throws -> [UserEntity] {
        if profileUser.id == currentUser.id {
            let remoteUsers = try await KaiXAPIClient.shared.mutualMessageFriends(limit: 100)
            return remoteUsers.map(UserRepository.entity(from:))
        }
        let profileId = profileUser.id
        let followerUsers = try await repository.fetchFollowers(userId: profileId)
        let followingUsers = try await repository.fetchFollowing(userId: profileId)
        let followingIds = Set(followingUsers.map(\.id))
        return followerUsers.filter { followingIds.contains($0.id) }
    }

    private func refreshFollowStates() async {
        let repository = UserRepository(context: modelContext)
        for user in users where user.id != currentUser.id {
            if let isFollowing = try? await repository.isFollowing(followerId: currentUser.id, followingId: user.id) {
                userStore.setFollowing(isFollowing, userId: user.id)
            }
        }
    }

    private func openMessage(with user: UserEntity) async {
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以发私信。", "ログインするとメッセージを送れます。", "Sign in to send messages.")) else { return }
        guard user.id != currentUser.id else { return }
        do {
            let thread = try await MessageRepository(context: modelContext)
                .getOrCreateThread(currentUserId: currentUser.id, peerUserId: user.id)
            dismiss()
            chrome.select(.messages)
            router.setActiveTab(.messages)
            router.open(.conversation(conversationId: thread.id), in: .messages)
        } catch {
            transientMessage = error.kaixUserMessage
        }
    }

    private func toggleFollow(_ user: UserEntity) async {
        guard user.id != currentUser.id, !workingUserIds.contains(user.id) else { return }
        workingUserIds.insert(user.id)
        defer { workingUserIds.remove(user.id) }
        do {
            let isFollowing = try await UserRepository(context: modelContext)
                .toggleFollow(currentUser: currentUser, targetUser: user)
            userStore.register([currentUser, user])
            userStore.setFollowing(isFollowing, userId: user.id)
            userStore.updateCounts(userId: currentUser.id, followers: currentUser.followerCount, following: currentUser.followingCount)
            userStore.updateCounts(userId: user.id, followers: user.followerCount, following: user.followingCount)
            if kind == .mutual && !isFollowing {
                withAnimation(.snappy(duration: 0.2)) {
                    users.removeAll { $0.id == user.id }
                }
                if users.isEmpty {
                    state = .empty
                }
            }
        } catch {
            transientMessage = error.kaixUserMessage
        }
    }
}

private struct FollowUserCard: View {
    let user: UserEntity
    let isCurrentUser: Bool
    let isFollowing: Bool
    let isWorking: Bool
    let language: AppLanguage
    let onOpenProfile: () -> Void
    let onMessage: () -> Void
    let onToggleFollow: () -> Void

    var body: some View {
        HStack(spacing: KXSpacing.md) {
            Button(action: onOpenProfile) {
                AvatarView(user: user, size: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(user.displayName)

            Button(action: onOpenProfile) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        KXUserBadge(user: user)
                    }
                    Text("@\(user.username)")
                        .font(KXTypography.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(NumberFormatterUtils.compact(user.followerCount)) \(L("followers", language))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if !isCurrentUser {
                HStack(spacing: KXSpacing.sm) {
                    Button(action: onMessage) {
                        Image(systemName: "envelope")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                            .frame(width: 34, height: 34)
                            .background(KXColor.accent.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(KXPressableStyle(scale: 0.94))
                    .accessibilityLabel(L("messages", language))

                    Button(action: onToggleFollow) {
                        Text(isFollowing ? L("followed", language) : L("follow", language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isFollowing ? Color.primary : .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .padding(.horizontal, KXSpacing.md)
                            .frame(height: 34)
                            .background(isFollowing ? Color(.secondarySystemBackground) : KXColor.accent, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(isFollowing ? 0.08 : 0), lineWidth: 1))
                    }
                    .disabled(isWorking)
                    .opacity(isWorking ? 0.55 : 1)
                    .buttonStyle(KXPressableStyle(scale: 0.96))
                }
            }
        }
        .padding(KXSpacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
    }
}

private struct CoverGradientView: View {
    let user: UserEntity

    /// 无封面时按 user.id 在品牌墨绿-暖纸系里确定性取一组渐变——千人千面但
    /// 不偏出品牌。String.hashValue 每次启动换随机种子,同一用户会换色,
    /// 故用 UTF-8 累乘做跨启动稳定的哈希。
    private var fallbackGradientColors: [Color] {
        let palettes: [[Color]] = [
            [KXColor.livingAccent.opacity(0.85), KXColor.accent.opacity(0.45), KXColor.livingBackground],
            [KXColor.official.opacity(0.68), KXColor.livingAccent.opacity(0.34), KXColor.livingSoft],
            [KXColor.accent.opacity(0.58), KXColor.livingSoft, KXColor.livingBackground],
        ]
        let hash = user.id.utf8.reduce(UInt64(5381)) { ($0 &* 131) &+ UInt64($1) }
        return palettes[Int(hash % UInt64(palettes.count))]
    }

    var body: some View {
        ZStack {
            if let url = user.coverURL.kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: 1200)
            } else {
                LinearGradient(
                    colors: fallbackGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            Color.clear,
                            Color.black.opacity(0.035)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                // 底部 10pt 渐隐到卡面,头像骑跨 cover 下缘处的过渡更柔。
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color.clear, KXColor.cardBackground.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 10)
                }
            }
        }
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
    }
}

private enum PersonalProfileTab: String, CaseIterable, Identifiable {
    case posts
    case replies
    case media
    case likes

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .posts: L("posts", language)
        case .replies: L("reply", language)
        case .media: L("media", language)
        case .likes: L("likes", language)
        }
    }

    func emptyTitle(_ language: AppLanguage) -> String {
        switch self {
        case .posts: L("emptyPosts", language)
        case .replies: L("emptyReplies", language)
        case .media: L("emptyMedia", language)
        case .likes: L("emptyLikes", language)
        }
    }

    var emptyIcon: String {
        switch self {
        case .posts: "doc.text"
        case .replies: "bubble.left"
        case .media: "photo.on.rectangle"
        case .likes: "heart"
        }
    }
}

private struct PersonalProfileTabPicker: View {
    @Environment(\.appLanguage) private var language
    let tabs: [PersonalProfileTab]
    @Binding var selection: PersonalProfileTab

    var body: some View {
        KXSegmentedControl(tabs, selection: $selection) { tab in
            Text(tab.title(language))
        }
    }
}

/// Two-tab aggregate for "我的收藏": saved listings (WishlistView) + bookmarked
/// posts (BookmarkView). Presented as a sheet from the profile. A single
/// segmented header switches the panel; each child view keeps its own loading
/// and empty states.
struct FavoritesHubView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    let currentUser: UserEntity
    /// Opens a saved listing (routes into the Search tab and dismisses the sheet).
    let onOpenListing: (String) -> Void

    private enum Segment: Hashable { case listings, posts }
    @State private var segment: Segment = .listings

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KXSpacing.md) {
                KXSegmentedControl(
                    [Segment.listings, .posts],
                    selection: $segment
                ) { seg in
                    Text(seg == .listings ? L("favoritesListingsTab", language) : L("favoritesPostsTab", language))
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(L("close", language))
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.top, 14)
            .padding(.bottom, KXSpacing.sm)

            Divider().opacity(0.4)

            Group {
                switch segment {
                case .listings:
                    // Embedded: WishlistView renders only its list (the hub owns
                    // the segmented header + the single close button above).
                    WishlistView(embedded: true) { id in onOpenListing(id) }
                case .posts:
                    NavigationStack {
                        BookmarkView(currentUser: currentUser)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(KXColor.pageBackground.ignoresSafeArea())
        .accessibilityIdentifier("favorites.hub")
    }
}
