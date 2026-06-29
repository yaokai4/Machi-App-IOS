import SwiftData
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var router: AppRouter
    @AppStorage("blockedUserIds") private var blockedUserIdsRaw = ""
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

    /// Shown on the "我的" tab when browsing as a guest: a clear login /
    /// register call-to-action instead of an empty placeholder profile.
    private var guestProfilePrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(KXColor.accent)
            Text(L("guestProfileTitle", language))
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(L("guestProfileSubtitle", language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Label {
                Text(KXListingCopy.pickText(
                    language,
                    "登录后即可使用「我的工作台」管理 Todo、日历、申请、账单和证件期限。",
                    "ログインすると「マイワークベンチ」でTodo・カレンダー・申請・支払い・証明書を管理できます。",
                    "Log in to use My Workbench: tasks, calendar, applications, bills, and document expiries."
                ))
            } icon: {
                Image(systemName: "square.grid.2x2.fill").foregroundStyle(KXColor.accent)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 32)
            Button {
                GuestGate.shared.requireLogin()
            } label: {
                Text(L("loginOrRegister", language))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(KXColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 36)
            .padding(.top, 4)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, chrome.bottomContentPadding)
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
            currentUser: currentUser,
            profileUser: profileUser,
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
            return AnyView(LoadingView())
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
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, KXSpacing.sm)
                .padding(.bottom, KXSpacing.md)
                .kxGlassBar(ignoresTopSafeArea: true)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.35)
                }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: KXSpacing.md) {
                    profileHeader
                    if isCurrentUser {
                        personalWorkbenchEntry
                        reputationCard
                    }
                    PersonalProfileTabPicker(tabs: availableTabs, selection: $profileTab)
                        .padding(.horizontal, 2)
                    stateContent
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
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
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(colors: [KXColor.accent, KXColor.accent.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
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
            .padding(16)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator.opacity(0.6), lineWidth: 0.8))
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
        .accessibilityIdentifier("profile.personalWorkbench")
    }

    /// N8: lightweight reputation surface — the user's own level + trust label,
    /// directly under the workbench entry. Hidden until loaded (and for guests).
    @ViewBuilder
    private var reputationCard: some View {
        if let rep = reputation, let level = rep.level {
            let levelName = KXListingCopy.pickText(
                language, rep.levelName ?? "", rep.levelNameJa ?? "", rep.levelNameEn ?? ""
            )
            let trust = rep.publicTrustLabel ?? rep.reputationLabel ?? ""
            let detail = levelName.isEmpty ? trust : (trust.isEmpty ? levelName : "\(levelName) · \(trust)")
            HStack(spacing: 14) {
                Image(systemName: "rosette")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(colors: [KXColor.accent, KXColor.accent.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(KXListingCopy.pickText(language, "我的信誉", "信頼レベル", "My reputation"))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Lv.\(level)")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(KXColor.accent)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator.opacity(0.6), lineWidth: 0.8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(KXListingCopy.pickText(language, "我的信誉 等级\(level) \(trust)", "信頼レベル \(level) \(trust)", "My reputation level \(level) \(trust)"))
        }
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
                .accessibilityLabel("返回")
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
                    Button(L("shareProfile", language)) {
                        UIPasteboard.general.string = "@\(profileUser.username)"
                        menuMessage = L("profileCopied", language)
                    }
                    Button(L("reportUser", language), role: .destructive) {
                        // C3: file a real report instead of only toasting.
                        if currentUser.isGuest { GuestGate.shared.requireLogin() }
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
            LoadingView()
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

                AvatarView(user: profileUser, size: KXAvatarSize.profile)
                    .overlay(Circle().stroke(KXColor.cardBackground, lineWidth: 4))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .offset(x: 14, y: 44)
            }
            .padding(.bottom, 48)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(profileUser.displayName)
                            .font(.title3.weight(.semibold))
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

            HStack(spacing: KXSpacing.md) {
                if let regionLabel = profileRegionLabel {
                    Label(regionLabel, systemImage: "mappin.and.ellipse")
                } else if !profileUser.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(profileUser.location, systemImage: "mappin.and.ellipse")
                }
                Label("\(profileUser.joinDate.formatted(date: .numeric, time: .omitted)) \(L("joined", language))", systemImage: "calendar")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            profileStatsStrip
            listingCountTags
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
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

    private var profileStatsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tight, X-style metric strip — only the four numbers the
            // user actually checks on themselves and others. "总热度",
            // "被收藏", "活跃城市" earlier filled the card with
            // numbers nobody actively reads.
            FlowLayout(spacing: 14) {
                followMetricButton(kind: .following)
                followMetricButton(kind: .followers)
                if isCurrentUser {
                    followMetricButton(kind: .mutual)
                }
                ProfileMetricInline(value: NumberFormatterUtils.compact(viewModel.postCount), title: L("posts", language))
                ProfileMetricInline(value: NumberFormatterUtils.compact(viewModel.likeCount), title: L("likes", language))
            }
            // Identity + merchant + creator badges below the stats
            // strip — these are categorical not numeric, so they
            // belong on their own line.
            FlowLayout(spacing: 6) {
                ProfileRoleBadge(title: roleTitle, isOfficial: profileUser.isMachiOfficialAccount)
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
        .padding(.top, 2)
    }

    /// Tappable per-type listing counts — open this user's published items of a
    /// type (出售二手 5 → their secondhand listings). Accurate listing counts
    /// from the profile-detail payload, not post counts.
    @ViewBuilder
    private var listingCountTags: some View {
        let tags = profileListingCountTags
        if !tags.isEmpty {
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
                        .frame(height: 30)
                        .background(KXColor.livingSurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(KXColor.livingInk.opacity(0.12), lineWidth: 0.8))
                    }
                    .buttonStyle(KXPressableStyle(scale: 0.96))
                }
            }
            .padding(.top, 4)
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

    @ViewBuilder
    private var contentSummaryStrip: some View {
        let visible = profileContentSummaryItems
        if !visible.isEmpty {
            FlowLayout(spacing: 7) {
                ForEach(visible, id: \.0) { item in
                    let spec = item.0.spec
                    Label("\(L(spec.titleKey, language)) \(item.1)", systemImage: spec.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(spec.tint)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .kxGlassCapsule()
                }
            }
            .padding(.top, 4)
        }
    }

    /// "成就" — small badge strip computed from existing
    /// counters. Pure local derivation, no extra fetch.
    @ViewBuilder
    private var achievementsRow: some View {
        let badges = computedAchievements
        if !badges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(KXColor.heat)
                        .font(.subheadline.weight(.bold))
                    Text(L("profileAchievements", language))
                        .font(.subheadline.weight(.bold))
                    Spacer()
                }
                FlowLayout(spacing: 8) {
                    ForEach(badges, id: \.self) { badge in
                        HStack(spacing: 5) {
                            Image(systemName: badge.icon)
                                .font(.caption.weight(.bold))
                            Text(badge.title)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(badge.color.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(14)
            .kxGlassSurface(radius: KXRadius.lg)
        }
    }

    /// "活跃城市" — derive from `profileUser.recentRegionCodes`. Tap
    /// any chip to set that region as the global browsing region.
    @ViewBuilder
    private var activeRegionsRow: some View {
        let regions = profileUser.recentRegionCodes.prefix(6).compactMap { KaiXRegionDirectory.resolve(regionCode: $0) }
        if !regions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "map")
                        .foregroundStyle(KXColor.accent)
                        .font(.subheadline.weight(.bold))
                    Text(L("profileActiveCities", language))
                        .font(.subheadline.weight(.bold))
                    Spacer()
                }
                FlowLayout(spacing: 8) {
                    ForEach(regions, id: \.regionCode) { region in
                        Button {
                            RegionStore.shared.setCurrent(region)
                        } label: {
                            HStack(spacing: 5) {
                                Text(region.countryEmoji)
                                Text(region.cityName)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .kxGlassCapsule()
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .kxGlassSurface(radius: KXRadius.lg)
        }
    }

    /// Top hashtags this user posted in. Tap → topic list.
    @ViewBuilder
    private var topTopicsRow: some View {
        let topTopics = computedTopTopics
        if !topTopics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "number")
                        .foregroundStyle(KXColor.accent)
                        .font(.subheadline.weight(.bold))
                    Text(L("profileFrequentTopics", language))
                        .font(.subheadline.weight(.bold))
                    Spacer()
                }
                FlowLayout(spacing: 8) {
                    ForEach(topTopics, id: \.self) { topic in
                        Button {
                            router.open(.topic(tag: topic))
                        } label: {
                            Text("#\(topic)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(KXColor.accent)
                                .padding(.horizontal, 11)
                                .frame(height: 30)
                                .background(KXColor.accent.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .kxGlassSurface(radius: KXRadius.lg)
        }
    }

    private struct AchievementBadge: Hashable {
        let icon: String
        let title: String
        let color: Color
    }

    private var computedAchievements: [AchievementBadge] {
        var badges: [AchievementBadge] = []
        if viewModel.totalHeat >= 10_000 {
            badges.append(.init(icon: "flame.fill", title: achievementTitle("万热达人", "1万ヒート達成", "10K heat"), color: KXColor.heat))
        }
        if viewModel.postCount >= 50 {
            badges.append(.init(icon: "pencil.tip", title: achievementTitle("高产作者", "投稿上級者", "Power creator"), color: .indigo))
        } else if viewModel.postCount >= 10 {
            badges.append(.init(icon: "pencil", title: achievementTitle("活跃作者", "アクティブ投稿者", "Active creator"), color: .indigo))
        }
        if displayedFollowerCount >= 100 {
            badges.append(.init(icon: "person.3.fill", title: achievementTitle("百人关注", "100人フォロワー", "100 followers"), color: .blue))
        }
        if viewModel.bookmarkCount >= 20 {
            badges.append(.init(icon: "bookmark.fill", title: achievementTitle("收藏达人", "保存上手", "Saved often"), color: .teal))
        }
        if profileUser.merchantVerified {
            badges.append(.init(icon: "checkmark.seal.fill", title: achievementTitle("认证商家", "認証済み店舗", "Verified merchant"), color: .green))
        }
        if profileUser.role == .creator {
            badges.append(.init(icon: "sparkles", title: achievementTitle("本地创作者", "ローカルクリエイター", "Local creator"), color: KXColor.accent))
        }
        return badges
    }

    private func achievementTitle(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    private var computedTopTopics: [String] {
        var counts: [String: Int] = [:]
        for post in viewModel.authoredPosts {
            for tag in post.hashtags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }
            .prefix(8)
            .map { $0.key }
    }

    private var profileContentSummaryItems: [(ContentType, Int)] {
        let preferred: [ContentType] = [
            .guide, .secondhand, .housing, .roommate, .job_seek, .job_post,
            .meetup, .dining, .event, .service, .merchant, .coupon
        ]
        return preferred.compactMap { type in
            guard let count = viewModel.contentTypeCounts[type], count > 0 else { return nil }
            return (type, count)
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
            HStack(spacing: 8) {
                Button {
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
                    if currentUser.isGuest { GuestGate.shared.requireLogin(); return }
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
        blockedUserIdsRaw = ids.removingDuplicates().joined(separator: "|")
        // Sync the block to the unified backend so it persists across devices
        // and the web client, and is enforced server-side — not just hidden
        // locally. Optimistic: the local list above already updated the UI;
        // the network call is fire-and-forget and a no-op when unauthenticated.
        let targetId = profileUserId
        Task { try? await KaiXAPIClient.shared.setBlock(targetId, isNowBlocking) }
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

    let currentUser: UserEntity
    let profileUser: UserEntity
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
    }
}

private struct WorkbenchFullScreenView: View {
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
                        .accessibilityLabel("关闭")
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

private struct ProfileMetricInline: View {
    let value: String
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.callout.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ProfileRoleBadge: View {
    let title: String
    var isOfficial = false

    private var tint: Color { isOfficial ? Color(red: 0.05, green: 0.48, blue: 0.45) : KXColor.accent }

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

/// Admin-assigned custom tag — a soft bordered chip (no seal icon) in the
/// brand-warm tone so it reads distinctly from the verification badges.
private struct ProfileCustomTagChip: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(KXColor.livingWarm)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(KXColor.livingWarm.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(KXColor.livingWarm.opacity(0.32), lineWidth: 0.8))
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
                    .padding(KaiXTheme.horizontalPadding)
            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await load() }
                }
                .padding(KaiXTheme.horizontalPadding)
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
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
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
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 8)
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
                VStack(alignment: .leading, spacing: 4) {
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
                HStack(spacing: 8) {
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
                            .padding(.horizontal, 12)
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
        .padding(12)
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

    var body: some View {
        ZStack {
            if let url = user.coverURL.kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: 1200)
            } else {
                LinearGradient(
                    colors: [
                        Color.pink.opacity(0.90),
                        KXColor.accent.opacity(0.34),
                        Color.cyan.opacity(0.24),
                        Color(.systemGray4).opacity(0.42)
                    ],
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
            }
        }
        .frame(height: 146)
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
