import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DiscoverView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var searchStore: SearchStore
    @EnvironmentObject private var router: AppRouter

    @StateObject private var viewModel = SearchViewModel()
    @ObservedObject private var regionStore = RegionStore.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    // Persisted across tab switches / relaunches so the user's chosen view
    // (推荐 / 热榜 / 正在发生 and city-vs-country) is remembered instead of
    // snapping back to 推荐 every time they leave and return.
    @SceneStorage("discover.segment") private var selectedSegment: DiscoverSegment = .recommend
    @SceneStorage("discover.hotScope") private var selectedHotScope: DiscoverHotScope = .city
    @State private var isShowingRegionSelector = false
    @State private var isShowingMoreChannels = false
    @State private var isShowingNotifications = false

    let currentUser: UserEntity
    /// Opens the global composer. Supplied by the host (MainTabView); when nil
    /// (previews) the floating compose button is simply not shown.
    var onCompose: (() -> Void)? = nil

    private var currentRegion: KaiXRegionDirectory.Region? {
        regionStore.current
    }

    private var sortedPosts: [PostEntity] {
        let source = viewModel.happeningPosts.isEmpty ? viewModel.hotPosts : viewModel.happeningPosts
        let regionPosts = source.filter { $0.matches(region: currentRegion) }
        let base = regionPosts.isEmpty ? source : regionPosts
        return base.sorted { lhs, rhs in
            if lhs.discoverBoostScore == rhs.discoverBoostScore {
                return lhs.heatScore > rhs.heatScore
            }
            return lhs.discoverBoostScore > rhs.discoverBoostScore
        }
    }

    private var cityHotPosts: [PostEntity] {
        Array(sortedPosts.sorted { $0.heatScore > $1.heatScore }.prefix(10))
    }

    private var countryHotPosts: [PostEntity] {
        guard let currentRegion else {
            return Array(viewModel.hotPosts.sorted { $0.heatScore > $1.heatScore }.prefix(10))
        }
        let countryPosts = viewModel.hotPosts
            .filter { $0.country == currentRegion.countryCode }
            .sorted { $0.heatScore > $1.heatScore }
        return Array((countryPosts.isEmpty ? viewModel.hotPosts.sorted { $0.heatScore > $1.heatScore } : countryPosts).prefix(10))
    }

    private var scopedHotPosts: [PostEntity] {
        switch selectedHotScope {
        case .city:
            return cityHotPosts
        case .country:
            return countryHotPosts
        }
    }

    private var scopedHotTitle: String {
        switch selectedHotScope {
        case .city:
            return currentRegion.map { "\((KaiXRegionDirectory.localizedMetroName(for: $0, language: language) ?? KaiXRegionDirectory.localizedShortLabel($0, language: language)))\(L("hot", language))" } ?? "\(L("currentRegion", language))\(L("hot", language))"
        case .country:
            return currentRegion.map {
                let country = KaiXRegionDirectory.localizedCountryName(
                    .init(code: $0.countryCode, name: $0.countryName, emoji: $0.countryEmoji, tier: 1, hasProvinces: !$0.provinceCode.isEmpty),
                    language: language
                )
                return "\(country)\(L("hot", language))"
            } ?? "\(L("hotScopeCountry", language))\(L("hot", language))"
        }
    }

    private var recommendedPosts: [PostEntity] {
        Array(sortedPosts.prefix(12))
    }

    /// Pure-recency feed for the 正在发生 radar: the newest server happening
    /// posts in the current region, freshest first. Deliberately NOT heat-ranked
    /// — this answers "what's happening right now", which is a different product
    /// from the 热榜 trend board (heat-ranked, server-owned).
    private var happeningRadarPosts: [PostEntity] {
        let source = viewModel.happeningPosts.isEmpty ? viewModel.hotPosts : viewModel.happeningPosts
        let regional = source.filter { $0.matches(region: currentRegion) }
        let base = regional.isEmpty ? source : regional
        return Array(base.sorted { $0.createdAt > $1.createdAt }.prefix(20))
    }

    private var recommendedUsers: [UserEntity] {
        var uniqueUsers: [String: UserEntity] = [:]
        for user in viewModel.suggestedUsers + Array(viewModel.authors.values) where user.id != currentUser.id {
            uniqueUsers[user.id] = user
        }
        return uniqueUsers.values.sorted { $0.followerCount > $1.followerCount }
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading, .idle:
                // Card-shaped skeletons keep Discover's layout rhythm
                // during the initial load instead of a centered spinner.
                ScrollView {
                    KXFeedSkeleton()
                        .padding(.horizontal, KaiXTheme.horizontalPadding)
                        .padding(.vertical, 7)
                }
                .scrollDisabled(true)
            case .empty:
                discoverContent
            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await load() }
                }
            case .loaded:
                discoverContent
            }
        }
        .kxPageBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discover.root")
        // Layered OUTSIDE the `discover.root` accessibility container (like the
        // FAB below) so the dismiss button stays hittable. Local, dismissible
        // follow-failure notice — replaces the old behaviour where one failed
        // follow flipped the whole page into a full-screen error state
        // (viewModel no longer touches `state` on follow errors).
        .overlay(alignment: .top) {
            if let message = viewModel.followErrorMessage {
                KXInlineNotice(message: message) {
                    viewModel.followErrorMessage = nil
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // FAB is layered OUTSIDE the `discover.root` accessibility container (a
        // sibling on top, mirroring Home) so it stays hit-testable — nesting it
        // inside `.accessibilityElement(children: .contain)` makes it
        // present-but-not-hittable for XCUITest/VoiceOver.
        .overlay(alignment: .bottomTrailing) {
            if let onCompose {
                // Same floating compose button as Home, kept clear of the tab bar
                // via the dynamic bottom-content padding. Tapping opens the
                // composer (guests are intercepted with the login gate upstream),
                // never a post — directly addressing the audit's "FAB landed on
                // a deleted post detail" confusion on this surface.
                KXFloatingComposeButton {
                    onCompose()
                }
                .accessibilityLabel(L("compose", language))
                .padding(.trailing, KXSpacing.lg)
                .padding(.bottom, chrome.bottomContentPadding + KXSpacing.sm)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await load()
        }
        .onChange(of: languageManager.preferred) { _, _ in
            Task { await load() }
        }
        .onChange(of: regionStore.current?.regionCode) { _, _ in
            Task { await load() }
        }
        .sheet(isPresented: $isShowingRegionSelector) {
            RegionSelectorView(
                initialCountry: currentUser.country.isEmpty ? (currentRegion?.countryCode ?? "jp") : currentUser.country,
                allowsAnyCountry: false
            ) { region in
                regionStore.setCurrent(region)
                persistBrowsingRegion(region)
            }
        }
        .sheet(isPresented: $isShowingMoreChannels) {
            MoreChannelSheet(categories: allCategories) { category in
                isShowingMoreChannels = false
                openCategory(category)
            }
        }
        .sheet(isPresented: $isShowingNotifications) {
            NavigationStack {
                NotificationsView(currentUser: currentUser)
                    .kxRouteDestinations(currentUser: currentUser)
            }
            .presentationDragIndicator(.visible)
        }
    }

    private func persistBrowsingRegion(_ region: KaiXRegionDirectory.Region) {
        currentUser.country = region.countryCode
        currentUser.province = region.provinceCode
        currentUser.city = region.cityCode
        currentUser.currentRegionCode = region.regionCode
        currentUser.recentRegionCodes = regionStore.recent.map(\.regionCode)
        try? modelContext.save()
        guard KaiXBackend.token != nil else { return }
        Task {
            _ = try? await KaiXAPIClient.shared.updateRegionLanguage([
                "country": region.countryCode,
                "province": region.provinceCode,
                "city": region.cityCode,
                "current_region_code": region.regionCode
            ])
        }
    }

    private var discoverContent: some View {
        VStack(spacing: 0) {
            discoverHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    categorySection
                    DiscoverSegmentedTabs(selection: $selectedSegment)
                    switch selectedSegment {
                    case .recommend:
                        HappeningSection(
                            region: currentRegion,
                            posts: happeningRadarPosts,
                            authors: viewModel.authors,
                            language: language,
                            onOpenPost: openPost,
                            onRefresh: { Task { await load() } },
                            isActive: chrome.selectedTab == .search
                        )
                    case .ranking:
                        // Server owns the ranking, the explainable reason, and the
                        // scope/window switching — iOS never hand-rolls a board.
                        HotBoardSection(
                            region: currentRegion,
                            language: language,
                            onOpenTopic: { router.open(.topic(tag: $0)) }
                        )
                    case .topics, .users:
                        contentListSection
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, chrome.bottomContentPadding + 28)
                .kxReadableWidth()
            }
            .refreshable {
                await load()
            }
        }
    }

    private var regionSection: some View {
        CurrentRegionCard(region: currentRegion) {
            isShowingRegionSelector = true
        }
    }

    private var categorySection: some View {
        DiscoverCategoryGrid(
            primaryCategories: primaryCategories,
            secondaryCategories: secondaryCategories,
            onOpen: openCategory,
            onMore: { isShowingMoreChannels = true }
        )
    }

    private var rankingSection: some View {
        CityHotRankingView(
            region: currentRegion,
            posts: cityHotPosts,
            authors: viewModel.authors,
            language: language,
            onSeeAll: openCityHotList,
            onOpen: openPost
        )
    }

    /// Official 编辑部精选 / 城市助手 content for the current city. These are
    /// City Seed Bot posts (`isSeedContent`) authored by official accounts —
    /// surfaced here in place of the old 热门话题/热门城市 chips, which were
    /// redundant with the segmented "话题" tab and the city card above.
    private var editorialPosts: [PostEntity] {
        Array(sortedPosts.filter { $0.isSeedContent }.prefix(6))
    }

    private var editorialSection: some View {
        DiscoverEditorialView(
            region: currentRegion,
            posts: editorialPosts,
            authors: viewModel.authors,
            language: language,
            onOpen: openPost
        )
    }

    private var contentListSection: some View {
        DiscoverContentList(
            segment: selectedSegment,
            region: currentRegion,
            posts: recommendedPosts,
            rankingTitle: scopedHotTitle,
            scopedRankingPosts: scopedHotPosts,
            topics: viewModel.topics,
            users: recommendedUsers,
            authors: viewModel.authors,
            mediaByPostId: viewModel.mediaByPostId,
            followingIds: viewModel.followingIds,
            currentUser: currentUser,
            language: language,
            onOpenPost: openPost,
            onOpenTopic: { router.open(.topic(tag: $0)) },
            onOpenUser: { router.open(.profile(userId: $0.id)) },
            onFollow: follow,
            onLike: { post in
                Task {
                    postStore.register(post)
                    try? await postStore.toggleLike(context: modelContext, postId: post.id, currentUser: currentUser)
                }
            },
            onBookmark: { post in
                Task {
                    postStore.register(post)
                    try? await postStore.toggleBookmark(context: modelContext, postId: post.id, currentUser: currentUser)
                }
            },
            onRepost: { post in
                Task {
                    postStore.register(post)
                    _ = try? await postStore.toggleRepost(context: modelContext, postId: post.id, currentUser: currentUser)
                }
            },
            onQuoteRepost: { post, content in
                Task {
                    postStore.register(post)
                    _ = try? await postStore.quoteRepost(context: modelContext, postId: post.id, currentUser: currentUser, content: content)
                }
            }
        )
    }

    private var discoverHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: KXSpacing.md) {
                Button {
                    router.open(.profile(userId: currentUser.id))
                } label: {
                    AvatarView(user: currentUser, size: 40)
                        .overlay(Circle().stroke(KXColor.cardBackground, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("profile", language))

                Text(L("discover", language))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer(minLength: KXSpacing.sm)

                // 与首页完全同款的城市按钮(同组件、同尺寸、同样式)。
                RegionPickerButton(region: currentRegion) {
                    isShowingRegionSelector = true
                }

                Button {
                    isShowingNotifications = true
                } label: {
                    Image(systemName: "bell")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .kxGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("notifications", language))
            }

            // Tap opens the dedicated search screen (live, debounced results) —
            // one consistent search experience. The old inline field looked like
            // it would search-as-you-type but only acted on Enter and then jumped
            // away anyway, which read as "typed but nothing happened".
            Button {
                router.open(.search(initialQuery: ""))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(KXColor.accent)
                    Text(L("searchPlaceholderShort", language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, KXSpacing.lg)
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .kxGlassCapsule()
                .overlay {
                    Capsule()
                        .stroke(KXColor.glassStroke.opacity(0.88), lineWidth: 0.8)
                }
            }
            .buttonStyle(KXPressableStyle())
            .accessibilityLabel(L("searchPlaceholder", language))
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.18)
        }
    }

    /// First-row shortcuts shown above the fold on the Discover page.
    /// The first four are high-intent structured listing channels; the
    /// remaining five are community/content channels.
    private var primaryCategories: [DiscoverCategory] {
        DiscoverView.primarySpecs.map { spec in resolveCategory(spec) }
    }

    /// Secondary channels (活动/优惠/指南/快讯/问答) shown as a compact chip row
    /// under the 4 primary cards — one tap away instead of buried in 更多频道.
    private var secondaryCategories: [DiscoverCategory] {
        let primaryIDs = Set(DiscoverView.primarySpecs.map(\.id))
        return allCategories.filter { !primaryIDs.contains($0.id) }
    }

    /// Channels shown in the MoreChannelSheet: the 4 primary entrances + the
    /// genuinely-distinct community channels (matches the web's 9-channel set).
    /// The rest of `extendedSpecs` (找工作/招聘/内推 ⊂ 工作; 商家/景点/认证商家/民宿
    /// ⊂ 商家与服务; 语言交换/Food/本地小组 ⊂ 活动小组; plus publish-only types
    /// 投票/长文/匿名) stay defined as the underlying catalog for content-type
    /// mapping / compose / deep-links, but are hidden so the sheet isn't a
    /// redundant wall.
    private static let moreSheetExtendedIDs: Set<String> = ["guide", "news", "coupon", "groups", "question"]
    private var allCategories: [DiscoverCategory] {
        let extended = DiscoverView.extendedSpecs.filter { DiscoverView.moreSheetExtendedIDs.contains($0.id) }
        return (DiscoverView.primarySpecs + extended).map { resolveCategory($0) }
    }

    private func resolveCategory(_ spec: DiscoverCategorySpec) -> DiscoverCategory {
        let count = viewModel.hotPosts.filter { post in
            post.matches(region: currentRegion) && spec.types.contains(post.contentType)
        }.count
        return DiscoverCategory(spec: spec, count: count)
    }

    // Tints collapsed to the 5-colour semantic palette (KXColor.category*):
    // brand = core Machi surfaces, heat = marketplace/deals, alert = jobs &
    // warnings (money/time-sensitive), info = reference/directory, neutral =
    // utilities. Colour now encodes *kind of action*, not just tile identity.
    private static let primarySpecs: [DiscoverCategorySpec] = [
        .init(id: "secondhand", title: "二手市场", subtitle: "闲置交易、求购和搬家出清", icon: "bag", types: [.secondhand], channel: .secondhand, tint: KXColor.categoryHeat),
        .init(id: "housing", title: "租房 · 住宿", subtitle: "长租房源、看房预约与民宿", icon: "house", types: [.housing, .roommate], channel: .housing, tint: KXColor.categoryBrand),
        .init(id: "work", title: "工作", subtitle: "职位、招聘、内推和申请进度", icon: "briefcase", types: [.job_seek, .job_post, .referral], channel: .jobPost, tint: KXColor.categoryAlert),
        .init(id: "service", title: "商家与服务", subtitle: "餐厅、订座点评、景点玩乐", icon: "storefront", types: [.service, .merchant], channel: .service, tint: KXColor.categoryInfo),
    ]

    private static let extendedSpecs: [DiscoverCategorySpec] = [
        .init(id: "guide", title: "城市指南", subtitle: "攻略、经验、避坑", icon: "book.closed", types: [.guide, .long_post, .warning], channel: .guide, tint: KXColor.categoryBrand),
        .init(id: "news", title: "本地快讯", subtitle: "新闻、交通、生活提醒", icon: "newspaper", types: [.news, .local_info], channel: .news, tint: KXColor.categoryInfo),
        .init(id: "coupon", title: "商家优惠", subtitle: "折扣福利、本地商家活动", icon: "tag", types: [.coupon], channel: .coupon, tint: KXColor.categoryHeat),
        .init(id: "groups", title: "约局 / 活动", subtitle: "约饭、语言交换、桌游", icon: "person.2", types: [.meetup, .dining, .event], channel: .meetup, tint: KXColor.categoryBrand),
        .init(id: "question", title: "问答互助", subtitle: "问答、匿名提问、生活求助", icon: "questionmark.circle", types: [.question, .anonymous], channel: .question, tint: KXColor.categoryInfo),
        .init(id: "warning", title: "避坑经验", subtitle: "风险提醒和踩雷复盘", icon: "exclamationmark.shield", types: [.warning], channel: .guide, tint: KXColor.categoryAlert),
        .init(id: "jobseek", title: "找工作", subtitle: "求职线索、兼职、全职", icon: "briefcase", types: [.job_seek], channel: .jobSeek, tint: KXColor.categoryAlert),
        .init(id: "jobpost", title: "招聘", subtitle: "职位发布和招聘方认证", icon: "person.badge.plus", types: [.job_post], channel: .jobPost, tint: KXColor.categoryAlert),
        .init(id: "referral", title: "内推", subtitle: "公司内推", icon: "person.crop.circle.badge.checkmark", types: [.referral], channel: .jobPost, tint: KXColor.categoryAlert),
        .init(id: "language", title: "语言交换", subtitle: "公开语言学习活动", icon: "bubble.left.and.bubble.right", types: [.meetup], channel: .meetup, tint: KXColor.categoryBrand),
        .init(id: "food", title: "Food meetup", subtitle: "餐厅、咖啡和小型饭局", icon: "fork.knife", types: [.dining], channel: .dining, tint: KXColor.categoryHeat),
        .init(id: "localgroup", title: "本地约局", subtitle: "运动、周末活动、城市散步", icon: "calendar", types: [.event, .meetup], channel: .event, tint: KXColor.categoryBrand),
        .init(id: "merchant", title: "商家", subtitle: "本地店铺和服务商资料", icon: "storefront", types: [.merchant], channel: .service, tint: KXColor.categoryInfo),
        .init(id: "travel_stays", title: "民宿", subtitle: "租房 · 住宿内", icon: "bed.double", types: [.service, .merchant], channel: .housing, tint: KXColor.categoryBrand),
        .init(id: "attractions", title: "景点票务", subtitle: "门票、一日游和本地向导", icon: "ticket", types: [.service, .merchant], channel: .service, tint: KXColor.categoryInfo),
        .init(id: "verified_merchant", title: "认证商家", subtitle: "已提交认证资料的商家", icon: "checkmark.seal", types: [.merchant], channel: .service, tint: KXColor.categoryInfo),
        .init(id: "poll", title: "投票", subtitle: "选项投票", icon: "chart.bar", types: [.poll], channel: .dynamic, tint: KXColor.categoryInfo),
        .init(id: "longpost", title: "长文", subtitle: "作为内容形式使用", icon: "doc.text", types: [.long_post], channel: .guide, tint: KXColor.categoryNeutral),
        .init(id: "anonymous", title: "匿名提问", subtitle: "匿名问答/生活吐槽", icon: "eye.slash", types: [.anonymous], channel: .question, tint: KXColor.categoryNeutral),
        .init(id: "localinfo", title: "本地资讯", subtitle: "社区告示", icon: "megaphone", types: [.local_info], channel: .news, tint: KXColor.categoryInfo),
        .init(id: "roommate", title: "找室友", subtitle: "合租找人", icon: "person.2.fill", types: [.roommate], channel: .housing, tint: KXColor.categoryBrand),
    ]

    private func openCategory(_ category: DiscoverCategory) {
        guard let region = currentRegion else {
            isShowingRegionSelector = true
            return
        }
        if let listingType = category.listingType {
            router.open(.cityListings(regionCode: region.regionCode, type: listingType))
            return
        }
        router.open(.cityChannel(regionCode: region.regionCode, channel: category.channel))
    }

    private func openCityHotList() {
        guard let region = currentRegion else {
            isShowingRegionSelector = true
            return
        }
        router.open(.cityChannel(regionCode: region.regionCode, channel: .hot))
    }

    private func openPost(_ post: PostEntity) {
        router.open(.postDetail(postId: post.repostOfPostId ?? post.id))
    }

    private func follow(_ user: UserEntity) {
        guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以关注感兴趣的人。", "ログインするとフォローできます。", "Sign in to follow people.")) else { return }
        Task {
            await viewModel.toggleFollow(
                context: modelContext,
                currentUser: currentUser,
                target: user,
                userStore: userStore
            )
        }
    }

    private func load() async {
        await viewModel.load(context: modelContext, currentUser: currentUser, postStore: postStore, searchStore: searchStore)
    }

}

private enum DiscoverSegment: String, CaseIterable, Identifiable, Hashable {
    case recommend
    case ranking
    case topics
    case users

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .recommend: KXListingCopy.pickText(language, "正在发生", "いま起きていること", "Happening")
        case .ranking: KXListingCopy.pickText(language, "热榜", "急上昇", "Hot")
        case .topics: KXListingCopy.pickText(language, "话题", "話題", "Topics")
        case .users: KXListingCopy.pickText(language, "用户推荐", "おすすめユーザー", "People")
        }
    }
}

private enum DiscoverHotScope: String, CaseIterable, Identifiable, Hashable {
    case city
    case country

    var id: String { rawValue }

    func title(region: KaiXRegionDirectory.Region?, language: AppLanguage) -> String {
        switch self {
        case .city:
            return region.map { KaiXRegionDirectory.localizedMetroName(for: $0, language: language) ?? KaiXRegionDirectory.localizedShortLabel($0, language: language) } ?? L("hotScopeCity", language)
        case .country:
            guard let region else { return L("hotScopeCountry", language) }
            return KaiXRegionDirectory.localizedCountryName(
                .init(code: region.countryCode, name: region.countryName, emoji: region.countryEmoji, tier: 1, hasProvinces: !region.provinceCode.isEmpty),
                language: language
            )
        }
    }
}

private struct DiscoverCategorySpec: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let types: [ContentType]
    let channel: CityChannel
    let tint: Color
}

private struct DiscoverCategory: Identifiable, Hashable {
    let spec: DiscoverCategorySpec
    let count: Int

    var id: String { spec.id }
    func title(_ language: AppLanguage) -> String {
        switch id {
        case "secondhand": KXListingCopy.pickText(language, "二手市场", "フリマ", "Marketplace")
        case "housing": KXListingCopy.pickText(language, "租房 · 住宿", "賃貸・宿泊", "Homes & Stays")
        case "work": KXListingCopy.pickText(language, "工作", "仕事", "Work")
        case "service": KXListingCopy.pickText(language, "商家与服务", "店舗・サービス", "Businesses & services")
        case "guide": KXListingCopy.pickText(language, "城市指南", "都市ガイド", "City guide")
        case "news": KXListingCopy.pickText(language, "本地快讯", "地域ニュース", "Local updates")
        case "coupon": KXListingCopy.pickText(language, "商家优惠", "店舗特典", "Deals")
        case "groups": KXListingCopy.pickText(language, "活动小组", "イベント・グループ", "Groups & events")
        case "question": KXListingCopy.pickText(language, "问答互助", "質問・助け合い", "Q&A")
        case "warning": KXListingCopy.pickText(language, "避坑经验", "注意・体験談", "Warnings")
        case "jobseek": KXListingCopy.pickText(language, "找工作", "仕事を探す", "Find work")
        case "jobpost": KXListingCopy.pickText(language, "招聘", "求人", "Hiring")
        case "referral": KXListingCopy.pickText(language, "内推", "紹介", "Referrals")
        case "language": KXListingCopy.pickText(language, "语言交换", "言語交換", "Language exchange")
        case "food": KXListingCopy.pickText(language, "Food meetup", "グルメ会", "Food meetup")
        case "localgroup": KXListingCopy.pickText(language, "本地小组", "地域グループ", "Local groups")
        case "merchant": KXListingCopy.pickText(language, "商家", "店舗", "Merchants")
        case "travel_stays": KXListingCopy.pickText(language, "民宿", "民泊", "Homestays")
        case "attractions": KXListingCopy.pickText(language, "景点票务", "観光チケット", "Attractions")
        case "verified_merchant": KXListingCopy.pickText(language, "认证商家", "認証済み店舗", "Verified merchants")
        case "poll": KXListingCopy.pickText(language, "投票", "投票", "Polls")
        case "longpost": KXListingCopy.pickText(language, "长文", "長文", "Long posts")
        case "anonymous": KXListingCopy.pickText(language, "匿名提问", "匿名質問", "Anonymous questions")
        case "localinfo": KXListingCopy.pickText(language, "本地资讯", "地域情報", "Local info")
        case "roommate": KXListingCopy.pickText(language, "找室友", "ルームメイト募集", "Roommates")
        default: spec.title
        }
    }

    func subtitle(_ language: AppLanguage) -> String {
        switch id {
        case "secondhand": KXListingCopy.pickText(language, "闲置交易、求购和搬家出清", "中古取引・買います・引越し処分", "Local resale, wanted posts, moving sales")
        case "housing": KXListingCopy.pickText(language, "长租房源、看房预约与民宿", "賃貸・内見予約・民泊", "Rentals, viewings, homestays")
        case "work": KXListingCopy.pickText(language, "职位、招聘、内推和申请进度", "求人・採用・紹介・応募状況", "Jobs, hiring, referrals, applications")
        case "service": KXListingCopy.pickText(language, "餐厅、订座点评、景点玩乐", "飲食店・予約・観光体験", "Restaurants, bookings, local experiences")
        case "guide": KXListingCopy.pickText(language, "攻略、经验、避坑", "手順・体験談・注意点", "Guides, tips, warnings")
        case "news": KXListingCopy.pickText(language, "新闻、交通、生活提醒", "ニュース・交通・生活のお知らせ", "News, transit, life alerts")
        case "coupon": KXListingCopy.pickText(language, "折扣福利、本地商家活动", "割引・特典・地域イベント", "Discounts and merchant offers")
        case "groups": KXListingCopy.pickText(language, "聚会、运动、语言交换", "集まり・運動・言語交換", "Meetups, sports, exchange")
        case "question": KXListingCopy.pickText(language, "问答、匿名提问、生活求助", "質問・匿名相談・生活ヘルプ", "Questions and local help")
        case "warning": KXListingCopy.pickText(language, "风险提醒和踩雷复盘", "リスク共有と体験談", "Risk alerts and lessons")
        case "jobseek": KXListingCopy.pickText(language, "求职线索、兼职、全职", "求職・バイト・正社員", "Leads, part-time, full-time")
        case "jobpost": KXListingCopy.pickText(language, "职位发布和招聘方认证", "求人掲載と採用側認証", "Roles and employer verification")
        case "referral": KXListingCopy.pickText(language, "公司内推", "社内紹介", "Company referrals")
        case "language": KXListingCopy.pickText(language, "公开语言学习活动", "公開の言語学習イベント", "Language-learning meetups")
        case "food": KXListingCopy.pickText(language, "餐厅、咖啡和小型饭局", "飲食店・カフェ・食事会", "Restaurants, cafes, meals")
        case "localgroup": KXListingCopy.pickText(language, "运动、周末活动、城市散步", "運動・週末活動・街歩き", "Sports, weekends, walks")
        case "merchant": KXListingCopy.pickText(language, "本地店铺和服务商资料", "地域店舗とサービス提供者", "Local merchant profiles")
        case "travel_stays": KXListingCopy.pickText(language, "民宿", "民泊", "Homestays")
        case "attractions": KXListingCopy.pickText(language, "门票、一日游和本地向导", "チケット・日帰り・ガイド", "Tickets, day trips, guides")
        case "verified_merchant": KXListingCopy.pickText(language, "已提交认证资料的商家", "認証済みの店舗", "Approved merchant profiles")
        case "poll": KXListingCopy.pickText(language, "选项投票", "選択式の投票", "Option polls")
        case "longpost": KXListingCopy.pickText(language, "作为内容形式使用", "読み物形式の投稿", "Long-form posts")
        case "anonymous": KXListingCopy.pickText(language, "匿名问答/生活吐槽", "匿名Q&A・相談", "Anonymous Q&A")
        case "localinfo": KXListingCopy.pickText(language, "社区告示", "地域のお知らせ", "Community notices")
        case "roommate": KXListingCopy.pickText(language, "合租找人", "ルームシェア募集", "Roomshare leads")
        default: spec.subtitle
        }
    }
    var icon: String { spec.icon }
    var types: [ContentType] { spec.types }
    var channel: CityChannel { spec.channel }
    var tint: Color { spec.tint }

    var listingType: String? {
        switch id {
        case "secondhand":
            "secondhand"
        case "housing", "roommate":
            "rental"
        // 「民宿」伪类型：租房频道直接落在 stays 标签。
        case "travel_stays":
            "stays"
        case "work", "jobseek", "jobpost", "referral":
            "work"
        case "service", "merchant", "attractions", "verified_merchant":
            "local_service"
        case "coupon":
            "discount"
        default:
            nil
        }
    }

    func heroTags(_ language: AppLanguage) -> [String] {
        switch id {
        case "secondhand": return [
            KXListingCopy.pickText(language, "估价", "相場", "Pricing"),
            KXListingCopy.pickText(language, "求购", "買います", "Wanted"),
            KXListingCopy.pickText(language, "面交安全", "安全な受け渡し", "Safe meetup")
        ]
        case "housing": return [
            KXListingCopy.pickText(language, "长租", "長期賃貸", "Rentals"),
            KXListingCopy.pickText(language, "民宿", "民泊", "Homestays"),
            KXListingCopy.pickText(language, "看房预约", "内見予約", "Viewing")
        ]
        case "work": return [
            KXListingCopy.pickText(language, "薪资", "給与", "Pay"),
            KXListingCopy.pickText(language, "签证", "ビザ", "Visa"),
            KXListingCopy.pickText(language, "雇主认证", "雇用主認証", "Employer verified")
        ]
        case "service": return [
            KXListingCopy.pickText(language, "餐厅", "飲食店", "Restaurants"),
            KXListingCopy.pickText(language, "订座", "予約", "Booking"),
            KXListingCopy.pickText(language, "景点玩乐", "観光体験", "Things to do")
        ]
        case "travel_stays": return [
            KXListingCopy.categoryLabel("民宿", language),
            KXListingCopy.pickText(language, "民宿", "民泊", "Homestays")
        ]
        case "attractions": return [
            KXListingCopy.pickText(language, "门票", "チケット", "Tickets"),
            KXListingCopy.categoryLabel("一日游", language),
            KXListingCopy.pickText(language, "向导", "ガイド", "Guides")
        ]
        default: return []
        }
    }
}

private struct CurrentRegionCard: View {
    @Environment(\.appLanguage) private var language
    let region: KaiXRegionDirectory.Region?
    let onChange: () -> Void

    private var title: String {
        guard let region else { return L("selectCity", language) }
        return KaiXRegionDirectory.localizedShortLabel(region, language: language)
    }

    var body: some View {
        Button(action: onChange) {
            HStack(spacing: KXSpacing.md) {
                Text(region?.flagEmoji ?? "⌖")
                    .font(.system(size: 28))
                    .frame(width: 46, height: 46)
                    .background(KXColor.softBackground, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(region.map {
                        let city = KaiXRegionDirectory.localizedMetroName(for: $0, language: language) ?? KaiXRegionDirectory.localizedShortLabel($0, language: language)
                        return KXListingCopy.pickText(
                            language,
                            "正在浏览\(city)的本地动态和生活信息",
                            "\(city)の地域投稿と生活情報を表示しています",
                            "Browsing local posts and life updates for \(city)"
                        )
                    } ?? KXListingCopy.pickText(
                        language,
                        "选择城市后，首页、发现和热榜会围绕本地内容展开",
                        "都市を選ぶと、ホーム・発見・急上昇が地域中心に切り替わります",
                        "Choose a city to tune Home, Discover, and Hot to local content"
                    ))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Text(KXListingCopy.pickText(language, "切换城市", "都市を変更", "Change city"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, KXSpacing.lg)
            .padding(.vertical, KXSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(KXColor.cardBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(KXColor.glassStroke.opacity(0.72), lineWidth: 0.8)
            }
            .shadow(color: KXColor.glassShadow.opacity(0.48), radius: 7, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct DiscoverCategoryGrid: View {
    @Environment(\.appLanguage) private var language
    let primaryCategories: [DiscoverCategory]
    var secondaryCategories: [DiscoverCategory] = []
    let onOpen: (DiscoverCategory) -> Void
    let onMore: () -> Void

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 12),
        GridItem(.flexible(minimum: 0), spacing: 12),
    ]

    var body: some View {
        let core = Array(primaryCategories.prefix(4))
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(alignment: .center) {
                DiscoverSectionTitle(title: KXListingCopy.pickText(language, "生活功能入口", "生活機能", "Life features"), trailing: nil)
                Spacer(minLength: 10)
                Button(action: onMore) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                        Text(KXListingCopy.pickText(language, "更多功能", "もっと", "More"))
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .kxGlassCapsule(isSelected: false)
                }
                .buttonStyle(KXPressableStyle())
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(core) { category in
                    Button {
                        onOpen(category)
                    } label: {
                        DiscoverCategoryCell(category: category, prominence: .high)
                    }
                    .buttonStyle(KXPressableStyle(scale: 0.97))
                }
            }
            if !secondaryCategories.isEmpty {
                KXFadingHScroll {
                    HStack(spacing: 8) {
                        ForEach(secondaryCategories) { category in
                            Button { onOpen(category) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: category.icon)
                                        .font(.caption.weight(.bold))
                                    Text(category.title(language))
                                        .font(.caption.weight(.bold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(category.tint)
                                .padding(.horizontal, 13)
                                .frame(height: 36)
                                .background(category.tint.opacity(0.10), in: Capsule())
                                .overlay(Capsule().stroke(category.tint.opacity(0.18), lineWidth: 0.7))
                            }
                            .buttonStyle(KXPressableStyle(scale: 0.95))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.top, 2)
            }
        }
    }
}

/// The shared row used in both the 8-cell grid and the More sheet.
private struct DiscoverCategoryCell: View {
    @Environment(\.appLanguage) private var language
    enum Prominence {
        case normal
        case high
    }

    let category: DiscoverCategory
    var prominence: Prominence = .normal

    var body: some View {
        if prominence == .high {
            // NOTE: no zoom source here on purpose. The channel screen used to
            // be a zoom destination of this tile AND host the per-card zoom
            // sources into the listing detail — a nested matchedTransitionSource
            // setup that iOS 18/26 renders blank (whole list invisible) with
            // high probability after popping back from the detail. The tile now
            // plain-pushes; the card→detail zoom (the valuable one) stays.
            highCard
        } else {
            normalCard
        }
    }

    private var heroLine: String {
        category.heroTags(language).prefix(3).joined(separator: " · ")
    }

    /// Premium tile: gradient icon squircle + one-line title + one-line
    /// keyword caption. Fixed two-line composition keeps the four tiles
    /// perfectly even — the old version mixed 2-line wrapping text with
    /// a tag pill and produced the "ragged grid" the user flagged.
    private var highCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: category.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [category.tint.opacity(0.92), category.tint.opacity(0.62)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(color: category.tint.opacity(0.32), radius: 6, y: 3)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(category.tint)
                    .frame(width: 26, height: 26)
                    .background(category.tint.opacity(0.10), in: Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title(language))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(category.subtitle(language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    // Always reserve two lines so a 1-line subtitle tile is the
                    // exact same height as a 2-line one — kills the ragged grid.
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [category.tint.opacity(0.10), Color(.systemBackground).opacity(0.96)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .kxGlassSurface(radius: KXRadius.lg, elevated: true)
    }

    private var normalCard: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: category.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(category.tint.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(category.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title(language))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(category.subtitle(language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, KXSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg, elevated: false)
    }
}

/// The 9th cell — opens MoreChannelSheet.
private struct DiscoverMoreCell: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(KXColor.accent)
                .frame(width: 36, height: 36)
                .background(KXColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(KXListingCopy.pickText(language, "更多", "もっと見る", "More"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(KXListingCopy.pickText(language, "分组查看细分功能", "カテゴリ別に探す", "Browse by use case"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, KXSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous)
                .fill(KXColor.accent.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous)
                .stroke(KXColor.accent.opacity(0.16), lineWidth: 0.8)
        )
    }
}

/// Bottom sheet listing every local-life channel by use case. Publishing
/// tools remain tools, not main channels.
private struct MoreChannelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    let categories: [DiscoverCategory]
    let onSelect: (DiscoverCategory) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var categoryMap: [String: DiscoverCategory] {
        Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }

    private var groups: [(String, [String])] {
        [
            ("城市信息", ["news", "guide", "question", "warning"]),
            ("交易生活", ["secondhand", "housing", "coupon"]),
            ("机会工作", ["jobseek", "jobpost", "referral"]),
            ("本地连接", ["groups", "language", "food", "localgroup"]),
            ("服务商家", ["service", "merchant", "attractions", "verified_merchant"]),
            ("内容工具", ["poll", "longpost", "anonymous"]),
        ]
    }

    private func groupTitle(_ title: String) -> String {
        switch title {
        case "城市信息": return KXListingCopy.pickText(language, "城市信息", "街の情報", "City info")
        case "交易生活": return KXListingCopy.pickText(language, "交易生活", "暮らしの取引", "Life & trade")
        case "机会工作": return KXListingCopy.pickText(language, "机会工作", "仕事と機会", "Work opportunities")
        case "本地连接": return KXListingCopy.pickText(language, "本地连接", "地域のつながり", "Local connections")
        case "服务商家": return KXListingCopy.pickText(language, "服务商家", "店舗・サービス", "Services & merchants")
        case "内容工具": return KXListingCopy.pickText(language, "内容工具", "投稿ツール", "Content tools")
        default: return title
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.0) { group in
                        let items = group.1.compactMap { categoryMap[$0] }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(groupTitle(group.0))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 2)
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(items) { category in
                                        Button {
                                            onSelect(category)
                                        } label: {
                                            DiscoverCategoryCell(category: category)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.vertical, KXSpacing.md)
            }
            .kxPageBackground()
            .navigationTitle(KXListingCopy.pickText(language, "全部频道", "すべてのチャンネル", "All channels"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KXListingCopy.pickText(language, "关闭", "閉じる", "Close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct CityHotRankingView: View {
    let region: KaiXRegionDirectory.Region?
    let posts: [PostEntity]
    let authors: [String: UserEntity]
    let language: AppLanguage
    let onSeeAll: () -> Void
    let onOpen: (PostEntity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            DiscoverSectionTitle(
                title: region.map {
                    let city = KaiXRegionDirectory.localizedMetroName(for: $0, language: language) ?? KaiXRegionDirectory.localizedShortLabel($0, language: language)
                    return "\(city)\(L("hot", language))"
                } ?? "\(L("currentRegion", language))\(L("hot", language))",
                trailing: KXListingCopy.pickText(language, "查看全部", "すべて見る", "See all"),
                trailingAction: onSeeAll
            )

            if posts.isEmpty {
                HStack(spacing: KXSpacing.md) {
                    Image(systemName: "flame")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(KXColor.heat)
                    Text(KXListingCopy.pickText(language, "正在积累本地热度", "地域の反応を集計中", "Building local momentum"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(KXSpacing.md)
                .frame(maxWidth: .infinity, minHeight: 68)
                .kxGlassSurface(radius: KXRadius.lg, elevated: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(posts.prefix(5).enumerated()), id: \.element.id) { index, post in
                        Button {
                            onOpen(post)
                        } label: {
                            CityHotRankingRow(
                                rank: index + 1,
                                post: post,
                                author: authors[post.authorId],
                                language: language
                            )
                        }
                        .buttonStyle(.plain)

                        if index < min(posts.count, 5) - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .kxGlassSurface(radius: KXRadius.lg, elevated: true)
            }
        }
    }
}

private struct CityHotRankingRow: View {
    let rank: Int
    let post: PostEntity
    let author: UserEntity?
    let language: AppLanguage

    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            DiscoverRankBadge(rank: rank)

            VStack(alignment: .leading, spacing: 5) {
                Text(post.discoverTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(L(post.contentType.spec.titleKey, language))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(post.contentType.spec.tint)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(post.contentType.spec.tint.opacity(0.11), in: Capsule())
                    Text(author?.displayName ?? "@\(post.authorId.prefix(8))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HeatPill(score: post.heatScore, rank: rank)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
    }
}

/// Unified ranking-board row for 正在发生 (recent, time chip) and 热榜 (heat pill).
/// Rank badge + title + content-type chip + author, compact so the board scans
/// like a leaderboard rather than a feed of full cards.
private struct DiscoverRankingRow: View {
    let rank: Int
    let post: PostEntity
    let author: UserEntity?
    let language: AppLanguage
    var showHeat: Bool = false

    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            DiscoverRankBadge(rank: rank)
            VStack(alignment: .leading, spacing: 4) {
                Text(post.discoverTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(L(post.contentType.spec.titleKey, language))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(post.contentType.spec.tint)
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(post.contentType.spec.tint.opacity(0.11), in: Capsule())
                    Text(author?.displayName ?? "@\(post.authorId.prefix(8))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showHeat {
                HeatPill(score: post.heatScore, rank: rank)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// 编辑部精选 / 城市助手 — the official City Seed Bot row that replaced the
/// old 热门话题 + 热门城市 chips. Renders official cold-start content with a
/// clear official identity (account name + light "编辑部整理/城市助手" badge +
/// the account's official avatar), never as a real user. Hidden entirely when
/// the current city has no seed content yet, so the page stays clean.
private struct DiscoverEditorialView: View {
    let region: KaiXRegionDirectory.Region?
    let posts: [PostEntity]
    let authors: [String: UserEntity]
    let language: AppLanguage
    let onOpen: (PostEntity) -> Void

    var body: some View {
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                DiscoverSectionTitle(
                    title: region.map {
                        let city = KaiXRegionDirectory.localizedMetroName(for: $0, language: language) ?? KaiXRegionDirectory.localizedShortLabel($0, language: language)
                        return KXListingCopy.pickText(language, "\(city)编辑部精选", "\(city)編集部ピックアップ", "\(city) editor picks")
                    } ?? KXListingCopy.pickText(language, "编辑部精选", "編集部ピックアップ", "Editor picks"),
                    trailing: nil
                )
                VStack(spacing: 0) {
                    ForEach(Array(posts.prefix(5).enumerated()), id: \.element.id) { index, post in
                        Button {
                            onOpen(post)
                        } label: {
                            DiscoverEditorialRow(post: post, author: authors[post.authorId], language: language)
                        }
                        .buttonStyle(.plain)

                        if index < min(posts.count, 5) - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .kxGlassSurface(radius: KXRadius.lg, elevated: true)
            }
        }
    }
}

private struct DiscoverEditorialRow: View {
    let post: PostEntity
    let author: UserEntity?
    let language: AppLanguage

    /// Light, honest label. We never present seed content as a real person —
    /// the badge + the official account name make the source explicit.
    private var badge: String {
        post.seedAuthorType == "editorial"
            ? KXListingCopy.pickText(language, "编辑部整理", "編集部整理", "Editorial")
            : KXListingCopy.pickText(language, "城市助手", "街のアシスタント", "City helper")
    }

    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            AvatarView(user: author, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(author?.displayName ?? KXListingCopy.pickText(language, "Machi 城市助手", "Machi 街のアシスタント", "Machi City Helper"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(KXColor.accent.opacity(0.12), in: Capsule())
                }
                Text(post.discoverTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
}

private struct DiscoverSegmentedTabs: View {
    @Environment(\.appLanguage) private var language
    @Binding var selection: DiscoverSegment

    var body: some View {
        KXSegmentedControl(DiscoverSegment.allCases, selection: $selection, itemMinWidth: 76, itemHeight: 42) { segment in
            Text(segment.title(language))
        }
    }
}

// MARK: - 热榜 trend board (server-ranked topics)

private enum HotBoardScope: String, CaseIterable, Identifiable {
    case prefecture, national
    var id: String { rawValue }
    /// Region-aware labels: 都道府県 shows the current prefecture (千叶县/东京都…),
    /// 全国 shows the current country name (日本…). Falls back to generic copy
    /// when the region is unknown.
    func label(_ region: KaiXRegionDirectory.Region?, _ language: AppLanguage) -> String {
        switch self {
        case .prefecture:
            if let region, !region.provinceName.isEmpty {
                return region.provinceName
            }
            return language == .ja ? "都道府県" : language == .en ? "Prefecture" : "都道府县"
        case .national:
            if let region {
                return KaiXRegionDirectory.localizedCountryName(
                    .init(code: region.countryCode, name: region.countryName, emoji: region.countryEmoji,
                          tier: 1, hasProvinces: !region.provinceCode.isEmpty),
                    language: language)
            }
            return language == .ja ? "全国" : language == .en ? "National" : "全国"
        }
    }
}

/// Local trend board. Topics + ranking + the "why it's hot" reason all come
/// from `GET /api/discover/hot` — iOS never hand-rolls a ranking. Scope
/// (本市/都市圈/全国) and time window (2h/24h/7d) re-query the server.
private struct HotBoardSection: View {
    let region: KaiXRegionDirectory.Region?
    let language: AppLanguage
    let onOpenTopic: (String) -> Void

    // Default to the prefecture (都道府県) board: ranks within the user's
    // prefecture (e.g. 千叶县), with a 日本 (national) toggle. Time window is
    // fixed at 7 days (the 2h/24h/3d toggles added noise without value).
    @State private var scope: HotBoardScope = .prefecture
    private let window = "7d"
    @State private var items: [KaiXDiscoverHotItemDTO] = []
    @State private var isLoading = false
    @State private var didFail = false

    private var reloadKey: String { "\(scope.rawValue)|\(window)|\(region?.regionCode ?? "")" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switchers
            content
        }
        .task(id: reloadKey) { await reload() }
        .sensoryFeedback(.selection, trigger: scope)
    }

    private var switchers: some View {
        HotPillRow(ids: HotBoardScope.allCases.map(\.id),
                   labels: HotBoardScope.allCases.map { $0.label(region, language) },
                   selected: scope.id) { id in
            if let next = HotBoardScope(rawValue: id) { withAnimation(.snappy(duration: 0.16)) { scope = next } }
        }
    }

    @ViewBuilder private var content: some View {
        if isLoading && items.isEmpty {
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in HotBoardSkeletonRow() }
            }
            .kxGlassSurface(radius: KXRadius.lg, elevated: true)
        } else if items.isEmpty {
            DiscoverSoftEmptyRow(text: didFail
                ? (language == .ja ? "読み込みに失敗しました。引っ張って再試行" : language == .en ? "Couldn't load. Pull to retry." : "热榜加载失败，下拉重试")
                : (language == .ja ? "この範囲はまだ話題がありません" : language == .en ? "No trends in this range yet" : "当前范围暂无热榜内容"))
                .kxGlassSurface(radius: KXRadius.lg, elevated: true)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        let tag = item.routeID.isEmpty
                            ? item.title.replacingOccurrences(of: "#", with: "")
                            : item.routeID
                        onOpenTopic(tag)
                    } label: {
                        HotBoardRow(item: item, language: language)
                    }
                    .buttonStyle(KXPressableStyle(scale: 0.985, dim: 0.92))
                    if idx != items.count - 1 {
                        Divider().opacity(0.14).padding(.leading, 62)
                    }
                }
            }
            .kxGlassSurface(radius: KXRadius.lg, elevated: true)
        }
    }

    @MainActor private func reload() async {
        isLoading = true
        didFail = false
        do {
            let resp = try await KaiXAPIClient.shared.discoverHot(
                scope: scope.rawValue, window: window, regionCode: region?.regionCode ?? "")
            items = resp.items
        } catch {
            didFail = true
            items = []
        }
        isLoading = false
    }
}

private struct HotPillRow: View {
    let ids: [String]
    let labels: [String]
    let selected: String
    var compact: Bool = false
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(zip(ids, labels)), id: \.0) { id, label in
                let isOn = id == selected
                Button { onSelect(id) } label: {
                    Text(label)
                        .font((compact ? Font.caption2 : Font.caption).weight(.bold))
                        .foregroundStyle(isOn ? Color.white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: compact ? 30 : 36)
                        .background(isOn ? KXColor.accent : KXColor.softBackground, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HotBoardRow: View {
    let item: KaiXDiscoverHotItemDTO
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 12) {
            DiscoverRankBadge(rank: item.rank)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !item.reason.isEmpty {
                        Text(item.reason)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(KXColor.heat)
                            .lineLimit(1)
                    }
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Label("\(item.heatScore)", systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.heat)
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
                trendBadge
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var trendBadge: some View {
        switch item.trend {
        case "up":
            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.green)
        case "down":
            Image(systemName: "arrow.down.right")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

private struct HotBoardSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(KXColor.softBackground).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(KXColor.softBackground).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(KXColor.softBackground).frame(width: 90, height: 9)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .redacted(reason: .placeholder)
    }
}

// MARK: - 正在发生 city event radar (real-time, recency-first)

/// The 正在发生 feed is a *city event radar*, not a ranking board: it answers
/// "what's happening in my city right now" with the freshest server posts —
/// new listings / questions / jobs / services — each shown as an event with a
/// type icon, who/where, and a freshness chip. A live poll surfaces a
/// "有 N 条新动态" banner when newer server items appear. This is intentionally
/// a different product from the heat-ranked 热榜 (`HotBoardSection`).
private struct HappeningSection: View {
    let region: KaiXRegionDirectory.Region?
    let posts: [PostEntity]
    let authors: [String: UserEntity]
    let language: AppLanguage
    let onOpenPost: (PostEntity) -> Void
    let onRefresh: () -> Void
    /// Only poll while Discover is the visible tab. Tabs are kept alive (opacity
    /// 0) when you switch away, so without this the 45s loop kept firing network
    /// + main-thread state updates on every other screen — a periodic hitch and
    /// wasted battery/data the whole time you're elsewhere in the app.
    var isActive: Bool = true

    @State private var liveNewCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pollKey: String { region?.regionCode ?? "all" }

    private var regionTitle: String {
        // The tab is already labelled 正在发生, so don't repeat it here (and don't
        // use the 关东圈 metro name): show the prefecture with a neutral "最新".
        guard let region else {
            return language == .ja ? "いま起きていること" : language == .en ? "Happening now" : "正在发生"
        }
        let base = region.provinceName.isEmpty ? region.cityName : region.provinceName
        let suffix = language == .ja ? "の最新" : language == .en ? " · Live" : " · 最新"
        return base + suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if liveNewCount > 0 {
                newContentBanner
            }
            // New radar items animate in/out (stable post.id) instead of the
            // list hard-swapping when the user taps "refresh" or fresh data lands.
            content
                .animation(reduceMotion ? nil : KXMotion.reveal, value: posts.map(\.id))
        }
        .task(id: "\(pollKey)|\(isActive)") { await pollLoop() }
        .onChange(of: posts.map(\.id)) { _, _ in
            // New data flowed in from the parent (refresh / region change) —
            // the user is now looking at the latest, so clear the nudge.
            liveNewCount = 0
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            HappeningLiveDot()
            VStack(alignment: .leading, spacing: 2) {
                Text(regionTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(language == .ja ? "リアルタイムの話題と街の動き"
                     : language == .en ? "Live topics and city activity"
                     : "实时话题与城市动态")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !posts.isEmpty {
                Text(language == .ja ? "\(posts.count) 件" : language == .en ? "\(posts.count)" : "\(posts.count) 条")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 2)
    }

    private var newContentBanner: some View {
        Button {
            withAnimation(reduceMotion ? nil : KXMotion.reveal) { liveNewCount = 0 }
            onRefresh()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                Text(language == .ja ? "新着 \(liveNewCount) 件 · タップで更新"
                     : language == .en ? "\(liveNewCount) new · tap to refresh"
                     : "有 \(liveNewCount) 条新动态，点击刷新")
                    .lineLimit(1)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(KXColor.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder private var content: some View {
        if posts.isEmpty {
            DiscoverSoftEmptyRow(text: language == .ja ? "この都市圏ではまだ新しい動きがありません"
                                 : language == .en ? "No fresh activity in this area yet"
                                 : "当前都市圈暂无新动态")
                .kxGlassSurface(radius: KXRadius.lg, elevated: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // 焦点 — the hottest item leads as a prominent card, mirroring the
                // search "正在发生" board so both surfaces feel like one product.
                if let lead = posts.first {
                    Button { onOpenPost(lead) } label: {
                        HappeningFocusCard(post: lead, author: authors[lead.authorId], language: language)
                    }
                    .buttonStyle(KXPressableStyle(scale: 0.99, dim: 0.95))
                }
                // Ranked rows 2…N with colored rank badges + heat pills.
                let rest = Array(posts.dropFirst())
                if !rest.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(rest.enumerated()), id: \.element.id) { idx, post in
                            Button { onOpenPost(post) } label: {
                                HappeningRankRow(rank: idx + 2, post: post, author: authors[post.authorId], language: language)
                            }
                            .buttonStyle(KXPressableStyle(scale: 0.985, dim: 0.92))
                            if idx != rest.count - 1 {
                                Divider().opacity(0.12).padding(.leading, 58)
                            }
                        }
                    }
                    .kxGlassSurface(radius: KXRadius.lg, elevated: true)
                }
            }
        }
    }

    private func pollLoop() async {
        guard isActive, KaiXBackend.token != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { break }
            guard let resp = try? await KaiXAPIClient.shared.exploreHappening(region: region, limit: 30) else { continue }
            let current = Set(posts.map(\.id))
            let newOnes = resp.orderedPosts.map(\.id).filter { !current.contains($0) }
            await MainActor.run {
                withAnimation(.snappy(duration: 0.2)) { liveNewCount = newOnes.count }
            }
        }
    }
}

/// 焦点 — the lead "正在发生" item rendered as a prominent gradient card with a
/// heat pill, matching the search board's HappeningLeadCard so both surfaces
/// read as one cohesive ranking system.
private struct HappeningFocusCard: View {
    let post: PostEntity
    let author: UserEntity?
    let language: AppLanguage

    var body: some View {
        let spec = post.contentType.spec
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(language == .ja ? "注目" : language == .en ? "Top" : "焦点")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.heat)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(KXColor.heat.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(KXColor.heat.opacity(0.22), lineWidth: 0.7))
                Spacer(minLength: 6)
                HeatPill(score: post.heatScore, rank: 1, compact: true)
            }

            Text(post.discoverTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Text(L(spec.titleKey, language))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(spec.tint)
                if !subtitle.isEmpty {
                    Text("·").font(.caption).foregroundStyle(.secondary)
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [KXColor.rankGold.opacity(0.18), Color.orange.opacity(0.08), KXColor.cardBackground.opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .stroke(KXColor.rankGold.opacity(0.30), lineWidth: 0.9)
        }
    }

    private var subtitle: String {
        let who = author?.displayName ?? ""
        let location = post.discoverLocationLabel
        return [who, location].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A ranked "正在发生" row: colored rank badge · title · type/where · heat pill.
/// Heat (engagement) replaces the bare timestamp so the board reads as "what's
/// hot right now", consistent with the search ranking.
private struct HappeningRankRow: View {
    let rank: Int
    let post: PostEntity
    let author: UserEntity?
    let language: AppLanguage

    var body: some View {
        let spec = post.contentType.spec
        HStack(alignment: .center, spacing: 12) {
            DiscoverRankBadge(rank: rank)

            VStack(alignment: .leading, spacing: 3) {
                Text(post.discoverTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Text(L(spec.titleKey, language))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(spec.tint)
                    if !subtitle.isEmpty {
                        Text("·").foregroundStyle(.secondary)
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HeatPill(score: post.heatScore, rank: rank, compact: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let who = author?.displayName ?? ""
        let location = post.discoverLocationLabel
        return [who, location].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Small breathing dot that signals the radar is live (real-time).
private struct HappeningLiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.28))
                .frame(width: 16, height: 16)
                .scaleEffect(animate ? 1.0 : 0.5)
                .opacity(animate ? 0 : 0.9)
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
        }
        // Perpetual pulse guarded by Reduce Motion + UITest idle, matching the
        // rest of this file (a repeatForever animation blocks XCUITest's idle
        // snapshot and ignores the accessibility switch). Static dot otherwise.
        .onAppear {
            guard !reduceMotion, !KXRuntime.isUITesting else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

private struct DiscoverContentList: View {
    @EnvironmentObject private var postStore: PostStore
    let segment: DiscoverSegment
    let region: KaiXRegionDirectory.Region?
    let posts: [PostEntity]
    let rankingTitle: String
    let scopedRankingPosts: [PostEntity]
    let topics: [TopicEntity]
    let users: [UserEntity]
    let authors: [String: UserEntity]
    let mediaByPostId: [String: [MediaEntity]]
    let followingIds: Set<String>
    let currentUser: UserEntity
    let language: AppLanguage
    let onOpenPost: (PostEntity) -> Void
    let onOpenTopic: (String) -> Void
    let onOpenUser: (UserEntity) -> Void
    let onFollow: (UserEntity) -> Void
    var onLike: (PostEntity) -> Void = { _ in }
    var onBookmark: (PostEntity) -> Void = { _ in }
    var onRepost: (PostEntity) -> Void = { _ in }
    var onQuoteRepost: (PostEntity, String) -> Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            DiscoverSectionTitle(title: sectionTitle, trailing: nil)

            switch segment {
            case .recommend:
                postList(posts)
            case .ranking:
                postList(scopedRankingPosts.isEmpty ? posts : scopedRankingPosts)
            case .topics:
                topicList
            case .users:
                userList
            }
        }
    }

    private var sectionTitle: String {
        switch segment {
        case .recommend:
            return region.map { "\((KaiXRegionDirectory.localizedMetroName(for: $0, language: language) ?? $0.cityName))正在发生" } ?? "正在发生"
        case .ranking:
            return rankingTitle
        case .topics:
            return "热门话题"
        case .users:
            return "推荐用户"
        }
    }

    private func postList(_ items: [PostEntity]) -> some View {
        // 正在发生 / 热榜 = 排行榜（名次 + 标题 + 类型 + 热度/时间），只看标题就能扫，
        // 不再把首页整张卡片塞进来。正在发生取近 2 天、热榜取近 7 天（后端窗口）。
        let visible = Array(items.prefix(12))
        return VStack(spacing: 0) {
            if visible.isEmpty {
                DiscoverSoftEmptyRow(text: segment == .recommend ? "当前都市圈暂无新动态" : "当前都市圈暂无热榜内容")
            } else {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, post in
                    let displayed = postStore.post(id: post.id) ?? post
                    Button { onOpenPost(displayed) } label: {
                        DiscoverRankingRow(
                            rank: index + 1,
                            post: displayed,
                            author: authors[displayed.authorId],
                            language: language,
                            showHeat: segment == .ranking
                        )
                    }
                    .buttonStyle(KXPressableStyle(scale: 0.985, dim: 0.92))
                    if displayed.id != visible.last?.id {
                        Divider().opacity(0.16).padding(.leading, 52)
                    }
                }
            }
        }
        .kxGlassSurface(radius: KXRadius.lg, elevated: true)
    }

    private var topicList: some View {
        FlowLayout(spacing: 8) {
            ForEach(topics.prefix(18)) { topic in
                Button {
                    onOpenTopic(topic.name)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("#\(topic.name)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(topic.postCount) \(L("posts", language))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 56)
                    .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(KXColor.separator, lineWidth: 0.6)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var userList: some View {
        VStack(spacing: 10) {
            if users.isEmpty {
                DiscoverSoftEmptyRow(text: "还没有可推荐的本地用户")
            } else {
                ForEach(users.prefix(8)) { user in
                    DiscoverUserRow(
                        user: user,
                        isFollowing: followingIds.contains(user.id),
                        onOpen: { onOpenUser(user) },
                        onFollow: { onFollow(user) }
                    )
                }
            }
        }
    }
}

private struct DiscoverContentCard: View {
    let post: PostEntity
    let author: UserEntity?
    let mediaItems: [MediaEntity]
    let language: AppLanguage
    let onOpen: () -> Void
    let onOpenTopic: (String) -> Void
    let onOpenAuthor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            header
            bodyText
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
            if !mediaItems.isEmpty {
                MediaGridView(mediaItems: mediaItems)
            }
            highlightChips
            topicChips
            footer
        }
        .padding(KXSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.card)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .gesture(TapGesture().onEnded { onOpen() }, including: .gesture)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: KXSpacing.sm) {
            Button(action: onOpenAuthor) {
                AvatarView(user: author, size: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(author?.displayName ?? L("profile", language))

            VStack(alignment: .leading, spacing: 2) {
                Text(author?.displayName ?? "@\(post.authorId.prefix(8))")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(post.discoverLocationLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: KXSpacing.sm)

            Label(L(post.contentType.spec.titleKey, language), systemImage: post.contentType.spec.icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(post.contentType.spec.tint)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(post.contentType.spec.tint.opacity(0.12), in: Capsule())
        }
    }

    private var bodyText: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(post.discoverTitle)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !post.discoverSummary.isEmpty {
                Text(post.discoverSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    @ViewBuilder
    private var highlightChips: some View {
        let highlights = post.discoverHighlights(language: language)
        if !highlights.isEmpty {
            FlowLayout(spacing: 7) {
                ForEach(highlights) { item in
                    DiscoverHighlightChip(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private var topicChips: some View {
        if !post.hashtags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(post.hashtags.prefix(4), id: \.self) { topic in
                    Button {
                        onOpenTopic(topic)
                    } label: {
                        Text("#\(topic)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KXColor.accent)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(KXColor.accent.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HeatPill(score: post.heatScore, rank: 1, compact: true)
            Spacer(minLength: 0)
            DiscoverStat(icon: "heart", value: post.likeCount)
            DiscoverStat(icon: "bubble.right", value: post.commentCount)
            DiscoverStat(icon: "bookmark", value: post.bookmarkCount)
            DiscoverStat(icon: "arrow.2.squarepath", value: post.repostCount)
        }
    }
}

private struct DiscoverHighlightChip: View {
    let item: DiscoverHighlight

    var body: some View {
        HStack(spacing: 4) {
            Text(item.label)
                .foregroundStyle(.secondary)
            Text(item.value)
                .foregroundStyle(.primary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(KXColor.softBackground, in: Capsule())
    }
}

private struct DiscoverUserRow: View {
    let user: UserEntity
    let isFollowing: Bool
    let onOpen: () -> Void
    let onFollow: () -> Void

    var body: some View {
        HStack(spacing: KXSpacing.md) {
            Button(action: onOpen) {
                HStack(spacing: KXSpacing.md) {
                    AvatarView(user: user, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("@\(user.username)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onFollow) {
                Text(isFollowing ? "已关注" : "关注")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFollowing ? .secondary : KXColor.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .kxGlassCapsule(isSelected: !isFollowing)
            }
            .buttonStyle(.plain)
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}

private struct DiscoverSectionTitle: View {
    let title: String
    var trailing: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
            if let trailing {
                Button(action: { trailingAction?() }) {
                    Text(trailing)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct DiscoverRankBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(rank <= 3 ? .white : rankColor)
            .frame(width: 36, height: 36)
            .background {
                if rank <= 3 {
                    Circle()
                        .fill(LinearGradient(colors: rankGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Circle()
                        .fill(rankColor.opacity(0.15))
                }
            }
            .overlay(Circle().stroke(rankColor.opacity(0.28), lineWidth: 1))
    }

    private var rankColor: Color {
        switch rank {
        case 1: KXColor.rankGold
        case 2: KXColor.rankCoral
        case 3: KXColor.rankViolet
        default: KXColor.rankSky
        }
    }

    private var rankGradient: [Color] {
        switch rank {
        case 1: [KXColor.rankGold, Color.orange]
        case 2: [KXColor.rankCoral, Color.red.opacity(0.78)]
        case 3: [KXColor.rankViolet, KXColor.rankSky]
        default: [KXColor.rankSky.opacity(0.2), KXColor.softBackground]
        }
    }
}

private struct HeatPill: View {
    let score: Double
    let rank: Int
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: compact ? 10 : 11, weight: .black))
            Text(NumberFormatterUtils.compact(Int(score.rounded())))
                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 7 : 8)
        .frame(minHeight: compact ? 22 : 24)
        .background(color.opacity(0.13), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.8))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var color: Color {
        switch rank {
        case 1: KXColor.heat
        case 2: KXColor.rankCoral
        case 3: KXColor.rankViolet
        default: KXColor.rankSky
        }
    }
}

private struct DiscoverStat: View {
    let icon: String
    let value: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(NumberFormatterUtils.compact(value))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct DiscoverSoftEmptyRow: View {
    let text: String

    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(KXColor.accent)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}

private struct DiscoverHighlight: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

private extension PostEntity {
    var discoverBoostScore: Double {
        guard isBoosted else { return heatScore }
        if let boostedUntil, boostedUntil < .now { return heatScore }
        return heatScore + max(0, boostWeight) * 1_000
    }

    var discoverTitle: String {
        let title = attr(PostAttributeKeys.title)
        if !title.isEmpty { return title }
        let cleaned = previewText
            .replacingOccurrences(of: #"#[\p{L}\p{N}_-]+"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !cleaned.isEmpty else { return "一条新动态" }
        return cleaned.count > 42 ? "\(cleaned.prefix(42))..." : cleaned
    }

    var discoverSummary: String {
        for key in [PostAttributeKeys.summary, PostAttributeKeys.description, PostAttributeKeys.content] {
            let value = attr(key)
            if !value.isEmpty { return value }
        }
        return previewText == discoverTitle ? "" : previewText
    }

    var discoverLocationLabel: String {
        if let region = discoverRegion {
            return region.displayName
        }
        let parts = [country, province, city].filter { !$0.isEmpty }
        return parts.isEmpty ? "本地" : parts.joined(separator: " · ")
    }

    var discoverRegion: KaiXRegionDirectory.Region? {
        if !regionCode.isEmpty {
            return KaiXRegionDirectory.resolve(regionCode: regionCode)
        }
        guard !country.isEmpty, !city.isEmpty else { return nil }
        return KaiXRegionDirectory.make(country: country, province: province.isEmpty ? nil : province, city: city)
    }

    func matches(region: KaiXRegionDirectory.Region?) -> Bool {
        guard let region else { return true }
        let regionCodes = KaiXRegionDirectory.regionCodesForMetro(region: region)
        let cityCodes = KaiXRegionDirectory.cityCodesForMetro(region: region)
        return regionCodes.contains(regionCode)
            || (country == region.countryCode && cityCodes.contains(city))
            || (regionCode.isEmpty && country.isEmpty && city.isEmpty)
    }

    func discoverHighlights(language: AppLanguage) -> [DiscoverHighlight] {
        let regionValue = attr(PostAttributeKeys.area, fallback: discoverRegion?.cityName ?? city)
        switch contentType {
        case .secondhand:
            return highlights([
                ("价格", priceText),
                ("成色", attr(PostAttributeKeys.condition)),
                ("地区", regionValue),
            ])
        case .housing, .roommate:
            return highlights([
                ("租金", attr(PostAttributeKeys.rent, fallback: attr(PostAttributeKeys.rentRange))),
                ("区域", regionValue),
                ("最近车站", attr(PostAttributeKeys.nearestStation)),
                ("入住", attr(PostAttributeKeys.moveInDate)),
            ])
        case .job_seek:
            return highlights([
                ("方向", attr(PostAttributeKeys.desiredJob)),
                ("技能", attr(PostAttributeKeys.skills)),
                ("语言", attr(PostAttributeKeys.languages)),
                ("签证", attr(PostAttributeKeys.visaStatus)),
            ])
        case .job_post, .referral:
            return highlights([
                ("岗位", attr(PostAttributeKeys.jobTitle)),
                ("薪资", attr(PostAttributeKeys.salary)),
                ("公司", attr(PostAttributeKeys.companyName)),
                ("地点", attr(PostAttributeKeys.workLocation, fallback: regionValue)),
            ])
        case .meetup:
            return highlights([
                ("类型", attr(PostAttributeKeys.meetupType)),
                ("时间", attr(PostAttributeKeys.meetupTime)),
                ("地点", attr(PostAttributeKeys.location, fallback: regionValue)),
                ("人数", attr(PostAttributeKeys.peopleLimit)),
            ])
        case .dining:
            return highlights([
                ("时间", attr(PostAttributeKeys.meetupTime)),
                ("地点", attr(PostAttributeKeys.restaurantOrArea, fallback: attr(PostAttributeKeys.location, fallback: regionValue))),
                ("预算", attr(PostAttributeKeys.budget)),
                ("人数", attr(PostAttributeKeys.peopleLimit)),
            ])
        case .event:
            return highlights([
                ("时间", attr(PostAttributeKeys.eventTime)),
                ("地点", attr(PostAttributeKeys.location, fallback: regionValue)),
                ("费用", attr(PostAttributeKeys.fee)),
                ("报名", attr(PostAttributeKeys.registrationMethod)),
            ])
        case .guide:
            return highlights([
                ("摘要", attr(PostAttributeKeys.summary)),
                ("收藏", "\(bookmarkCount)"),
            ])
        case .news, .local_info:
            return highlights([
                ("来源", attr(PostAttributeKeys.source, fallback: "Machi News")),
                ("时间", createdAt.formatted(date: .abbreviated, time: .omitted)),
            ])
        case .merchant:
            return highlights([
                ("评分", attr(PostAttributeKeys.rating)),
                ("地址", attr(PostAttributeKeys.address, fallback: regionValue)),
                ("优惠", attr(PostAttributeKeys.discountInfo)),
            ])
        case .service:
            return highlights([
                ("服务", attr(PostAttributeKeys.serviceType)),
                ("价格", attr(PostAttributeKeys.priceRange, fallback: priceText)),
                ("地区", regionValue),
            ])
        case .coupon:
            return highlights([
                ("优惠", attr(PostAttributeKeys.discountInfo)),
                ("商家", attr(PostAttributeKeys.merchantName)),
                ("有效期", attr(PostAttributeKeys.validUntil)),
            ])
        default:
            return []
        }
    }

    private var priceText: String {
        let price = attr(PostAttributeKeys.price)
        guard !price.isEmpty else { return "" }
        let currency = attr(PostAttributeKeys.currency)
        return currency.isEmpty ? price : "\(currency) \(price)"
    }

    private func attr(_ key: String, fallback: String = "") -> String {
        if let value = stringAttribute(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        if let int = intAttribute(key) {
            return "\(int)"
        }
        if let double = doubleAttribute(key) {
            return double == double.rounded() ? "\(Int(double))" : String(format: "%.1f", double)
        }
        return fallback
    }

    private func highlights(_ items: [(String, String)]) -> [DiscoverHighlight] {
        items.compactMap { label, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : DiscoverHighlight(label: label, value: trimmed)
        }
        .prefix(4)
        .map { $0 }
    }
}

// Legacy support for the previous SearchView implementation. The active
// tab now uses DiscoverView, but keeping these small cards avoids removing
// the older screen while this page evolves.
struct DiscoverPulseCard: View {
    let region: KaiXRegionDirectory.Region?
    let items: [TrendingItem]
    let topics: [TopicEntity]
    let language: AppLanguage
    let onOpenItem: (TrendingItem) -> Void
    let onOpenTopic: (TopicEntity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            Text(region.map { "\(KaiXRegionDirectory.localizedMetroName(for: $0, language: language) ?? $0.cityName)正在发生" } ?? L("happeningNow", language))
                .font(.headline.weight(.bold))
            ForEach(items.prefix(3)) { item in
                Button { onOpenItem(item) } label: {
                    HStack {
                        Text(item.title.isEmpty ? L("untitledPost", language) : item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Spacer()
                        HeatPill(score: item.heatScore, rank: 1, compact: true)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}

struct DiscoverOverviewCard: View {
    let title: String
    let icon: String
    let tint: Color
    let item: TrendingItem?
    let language: AppLanguage
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(item?.title.isEmpty == false ? item?.title ?? "" : L("untitledPost", language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(KXSpacing.md)
            .frame(width: 156, alignment: .leading)
            .frame(minHeight: 108, alignment: .leading)
            .kxGlassSurface(radius: KXRadius.lg)
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
    }
}

struct DiscoverTypeCard: View {
    let title: String
    let icon: String
    let tint: Color
    let item: TrendingItem?
    let isLocal: Bool
    let language: AppLanguage

    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(item?.title.isEmpty == false ? item?.title ?? "" : (isLocal ? KXListingCopy.pickText(language, "本地内容", "地域コンテンツ", "Local content") : KXListingCopy.pickText(language, "入口说明", "入口の説明", "Entry guide")))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(KXSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}
