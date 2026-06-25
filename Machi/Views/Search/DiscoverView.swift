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
    @State private var selectedSegment: DiscoverSegment = .recommend
    @State private var selectedHotScope: DiscoverHotScope = .city
    @State private var searchDraft = ""
    @State private var isShowingRegionSelector = false
    @State private var isShowingMoreChannels = false
    @State private var isShowingNotifications = false

    let currentUser: UserEntity

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
        .background(KXColor.livingBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discover.root")
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
                            onRefresh: { Task { await load() } }
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

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(KXColor.accent)
                TextField(L("searchPlaceholderShort", language), text: $searchDraft)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .font(.subheadline.weight(.semibold))
                    .onSubmit { submitDiscoverSearch() }
                if !searchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        submitDiscoverSearch()
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("search", language))
                }
            }
            .padding(.horizontal, KXSpacing.lg)
            .frame(height: 50)
            .kxGlassCapsule()
            .overlay {
                Capsule()
                    .stroke(KXColor.glassStroke.opacity(0.88), lineWidth: 0.8)
            }
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

    private static let primarySpecs: [DiscoverCategorySpec] = [
        .init(id: "secondhand", title: "二手市场", subtitle: "闲置交易、求购和搬家出清", icon: "bag", types: [.secondhand], channel: .secondhand, tint: Color.green),
        .init(id: "housing", title: "租房 · 住宿", subtitle: "长租房源、看房预约与民宿", icon: "house", types: [.housing, .roommate], channel: .housing, tint: Color.blue),
        .init(id: "work", title: "工作", subtitle: "职位、招聘、内推和申请进度", icon: "briefcase", types: [.job_seek, .job_post, .referral], channel: .jobPost, tint: KXColor.rankViolet),
        .init(id: "service", title: "商家与服务", subtitle: "餐厅、订座点评、景点玩乐", icon: "storefront", types: [.service, .merchant], channel: .service, tint: Color.brown),
    ]

    private static let extendedSpecs: [DiscoverCategorySpec] = [
        .init(id: "guide", title: "城市指南", subtitle: "攻略、经验、避坑", icon: "book.closed", types: [.guide, .long_post, .warning], channel: .guide, tint: KXColor.rankTeal),
        .init(id: "news", title: "本地快讯", subtitle: "新闻、交通、生活提醒", icon: "newspaper", types: [.news, .local_info], channel: .news, tint: KXColor.rankSky),
        .init(id: "coupon", title: "商家优惠", subtitle: "折扣福利、本地商家活动", icon: "tag", types: [.coupon], channel: .coupon, tint: KXColor.heat),
        .init(id: "groups", title: "约局 / 活动", subtitle: "约饭、语言交换、桌游", icon: "person.2", types: [.meetup, .dining, .event], channel: .meetup, tint: Color.orange),
        .init(id: "question", title: "问答互助", subtitle: "问答、匿名提问、生活求助", icon: "questionmark.circle", types: [.question, .anonymous], channel: .question, tint: Color.indigo),
        .init(id: "warning", title: "避坑经验", subtitle: "风险提醒和踩雷复盘", icon: "exclamationmark.shield", types: [.warning], channel: .guide, tint: Color.red),
        .init(id: "jobseek", title: "找工作", subtitle: "求职线索、兼职、全职", icon: "briefcase", types: [.job_seek], channel: .jobSeek, tint: Color.mint),
        .init(id: "jobpost", title: "招聘", subtitle: "职位发布和招聘方认证", icon: "person.badge.plus", types: [.job_post], channel: .jobPost, tint: KXColor.rankViolet),
        .init(id: "referral", title: "内推", subtitle: "公司内推", icon: "person.crop.circle.badge.checkmark", types: [.referral], channel: .jobPost, tint: Color.indigo),
        .init(id: "language", title: "语言交换", subtitle: "公开语言学习活动", icon: "bubble.left.and.bubble.right", types: [.meetup], channel: .meetup, tint: Color.orange),
        .init(id: "food", title: "Food meetup", subtitle: "餐厅、咖啡和小型饭局", icon: "fork.knife", types: [.dining], channel: .dining, tint: KXColor.rankCoral),
        .init(id: "localgroup", title: "本地约局", subtitle: "运动、周末活动、城市散步", icon: "calendar", types: [.event, .meetup], channel: .event, tint: Color.purple),
        .init(id: "merchant", title: "商家", subtitle: "本地店铺和服务商资料", icon: "storefront", types: [.merchant], channel: .service, tint: Color.teal),
        .init(id: "travel_stays", title: "民宿", subtitle: "租房 · 住宿内", icon: "bed.double", types: [.service, .merchant], channel: .housing, tint: Color.cyan),
        .init(id: "attractions", title: "景点票务", subtitle: "门票、一日游和本地向导", icon: "ticket", types: [.service, .merchant], channel: .service, tint: Color.mint),
        .init(id: "verified_merchant", title: "认证商家", subtitle: "已提交认证资料的商家", icon: "checkmark.seal", types: [.merchant], channel: .service, tint: Color.teal),
        .init(id: "poll", title: "投票", subtitle: "选项投票", icon: "chart.bar", types: [.poll], channel: .dynamic, tint: Color.blue),
        .init(id: "longpost", title: "长文", subtitle: "作为内容形式使用", icon: "doc.text", types: [.long_post], channel: .guide, tint: Color.gray),
        .init(id: "anonymous", title: "匿名提问", subtitle: "匿名问答/生活吐槽", icon: "eye.slash", types: [.anonymous], channel: .question, tint: Color.gray),
        .init(id: "localinfo", title: "本地资讯", subtitle: "社区告示", icon: "megaphone", types: [.local_info], channel: .news, tint: Color.orange),
        .init(id: "roommate", title: "找室友", subtitle: "合租找人", icon: "person.2.fill", types: [.roommate], channel: .housing, tint: Color.cyan),
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

    private func submitDiscoverSearch() {
        let query = searchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        router.open(.search(initialQuery: query))
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

    @State private var liveNewCount = 0

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
            content
        }
        .task(id: pollKey) { await pollLoop() }
        .onChange(of: posts.map(\.id)) { _, _ in
            // New data flowed in from the parent (refresh / region change) —
            // the user is now looking at the latest, so clear the nudge.
            liveNewCount = 0
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HappeningLiveDot()
            Text(regionTitle)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
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
            liveNewCount = 0
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
            VStack(spacing: 0) {
                ForEach(Array(posts.enumerated()), id: \.element.id) { idx, post in
                    Button { onOpenPost(post) } label: {
                        HappeningRadarRow(rank: idx + 1, post: post, author: authors[post.authorId], language: language)
                    }
                    .buttonStyle(KXPressableStyle(scale: 0.985, dim: 0.92))
                    if idx != posts.count - 1 {
                        Divider().opacity(0.12).padding(.leading, 62)
                    }
                }
            }
            .kxGlassSurface(radius: KXRadius.lg, elevated: true)
        }
    }

    private func pollLoop() async {
        guard KaiXBackend.token != nil else { return }
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

/// One city event on the radar: type icon · what happened · who/where · how
/// fresh. Reads at a glance, distinct from the numbered heat board.
private struct HappeningRadarRow: View {
    let rank: Int
    let post: PostEntity
    let author: UserEntity?
    let language: AppLanguage

    var body: some View {
        let spec = post.contentType.spec
        HStack(alignment: .top, spacing: 12) {
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
                    Text("·").foregroundStyle(.secondary)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption2)
            }

            Spacer(minLength: 6)

            Text(DateFormatterUtils.relativeText(from: post.createdAt, language: language))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
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
        .onAppear {
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
        .kxGlassSurface(radius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .gesture(TapGesture().onEnded { onOpen() }, including: .gesture)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: KXSpacing.sm) {
            Button(action: onOpenAuthor) {
                AvatarView(user: author, size: 36)
            }
            .buttonStyle(.plain)

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

private enum ListingSortMode: String, CaseIterable, Identifiable {
    case newest
    case priceLow
    case priceHigh
    case rating

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .newest: KXListingCopy.pickText(language, "最新", "新着順", "Newest")
        case .priceLow: KXListingCopy.pickText(language, "价格低", "安い順", "Price low")
        case .priceHigh: KXListingCopy.pickText(language, "价格高", "高い順", "Price high")
        case .rating: KXListingCopy.pickText(language, "评分高", "評価順", "Top rated")
        }
    }

    func sortsBefore(_ lhs: KaiXCityListingDTO, _ rhs: KaiXCityListingDTO) -> Bool {
        switch self {
        case .newest:
            return KXListingCopy.sortForDisplay(lhs, rhs)
        case .priceLow:
            return (lhs.price ?? Double.greatestFiniteMagnitude) < (rhs.price ?? Double.greatestFiniteMagnitude)
        case .priceHigh:
            return (lhs.price ?? -Double.greatestFiniteMagnitude) > (rhs.price ?? -Double.greatestFiniteMagnitude)
        case .rating:
            let lhsCount = lhs.rating_count ?? lhs.ratingCount ?? 0
            let rhsCount = rhs.rating_count ?? rhs.ratingCount ?? 0
            // 无评分的沉底；有评分的按分数、再按评价数。
            if (lhsCount > 0) != (rhsCount > 0) { return lhsCount > 0 }
            let lhsAvg = lhs.rating_avg ?? lhs.ratingAvg ?? 0
            let rhsAvg = rhs.rating_avg ?? rhs.ratingAvg ?? 0
            if lhsAvg != rhsAvg { return lhsAvg > rhsAvg }
            return lhsCount > rhsCount
        }
    }
}

private enum ListingScopeMode: String, Identifiable {
    case city
    case country
    case area
    case selectedCity

    var id: String { rawValue }
}

private struct ListingScopeArea: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let regionCodes: [String]

    func localizedTitle(_ language: AppLanguage) -> String {
        switch id {
        case "kanto": KXListingCopy.pickText(language, "关东圈", "関東圏", "Greater Kanto")
        case "kansai": KXListingCopy.pickText(language, "关西圈", "関西圏", "Greater Kansai")
        case "popular": KXListingCopy.pickText(language, "其他热门", "その他の人気都市", "Other popular")
        default: title
        }
    }

    func localizedSubtitle(_ language: AppLanguage) -> String {
        switch id {
        case "kanto": KXListingCopy.pickText(language, "东京、横滨、川崎、埼玉、千叶", "東京・横浜・川崎・埼玉・千葉", "Tokyo, Yokohama, Kawasaki, Saitama, Chiba")
        case "kansai": KXListingCopy.pickText(language, "大阪、京都、神户、奈良、大津", "大阪・京都・神戸・奈良・大津", "Osaka, Kyoto, Kobe, Nara, Otsu")
        case "popular": KXListingCopy.pickText(language, "名古屋、福冈、仙台", "名古屋・福岡・仙台", "Nagoya, Fukuoka, Sendai")
        default: subtitle
        }
    }
}

private let listingScopeAreas: [ListingScopeArea] = [
    .init(
        id: "kanto",
        title: "关东圈",
        subtitle: "东京、横滨、川崎、埼玉、千叶",
        regionCodes: ["jp.tokyo.tokyo", "jp.kanagawa.yokohama", "jp.kanagawa.kawasaki", "jp.saitama.saitama", "jp.chiba.chiba"]
    ),
    .init(
        id: "kansai",
        title: "关西圈",
        subtitle: "大阪、京都、神户、奈良、大津",
        regionCodes: ["jp.osaka.osaka", "jp.kyoto.kyoto", "jp.hyogo.kobe", "jp.nara.nara", "jp.shiga.otsu"]
    ),
    .init(
        id: "popular",
        title: "其他热门",
        subtitle: "名古屋、福冈、仙台",
        regionCodes: ["jp.aichi.nagoya", "jp.fukuoka.fukuoka", "jp.miyagi.sendai"]
    ),
]

private let listingScopeHotCityCodes = [
    "jp.tokyo.tokyo", "jp.kanagawa.yokohama", "jp.kanagawa.kawasaki", "jp.saitama.saitama", "jp.chiba.chiba",
    "jp.osaka.osaka", "jp.kyoto.kyoto", "jp.hyogo.kobe", "jp.nara.nara", "jp.shiga.otsu",
    "jp.aichi.nagoya", "jp.fukuoka.fukuoka", "jp.miyagi.sendai",
]

struct CityListingChannelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState

    let regionCode: String
    let listingType: String
    let currentUser: UserEntity
    /// Shared with CityListingDetailView (via the router) for the card→detail
    /// zoom transition. nil outside the router path → plain push.
    var zoomNamespace: Namespace.ID? = nil

    @State private var items: [KaiXCityListingDTO] = []
    @State private var query = ""
    @State private var selectedCategory = "全部"
    @State private var serviceSection = "all"
    @State private var sortMode: ListingSortMode = .newest
    @State private var filtersOpen = false
    @State private var scopeMode: ListingScopeMode = .city
    @State private var selectedScopeArea = ""
    @State private var selectedScopeRegionCode = ""
    /// Default to the metro circle (关东圈/关西圈…) on first open: a single city
    /// usually has too few listings, so the都市圈 view is the useful default.
    /// Users can still switch to their exact city from the scope menu.
    @State private var didApplyDefaultScope = false
    @State private var minimumPrice = ""
    @State private var maximumPrice = ""
    /// 属性级筛选（key → 值，布尔用 "true"，人数下限用 gte_ 前缀），
    /// 与 Web 同一套 attr_<key> 协议，全部交给服务端过滤。
    @State private var attrFilters: [String: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// True once the listings scroll past the top — condenses the pinned
    /// header (drops the rental tabs + result summary, keeps search + rail).
    @State private var headerCollapsed = false
    /// Local 收藏 sheet.
    @State private var wishlistOpen = false
    /// Map vs list presentation of the current results.
    @State private var mapMode = false
    // Server-side keyset pagination ("work" merges two listing types, so it
    // carries one cursor per stream). nil = that stream is exhausted.
    @State private var nextCursor: String?
    @State private var nextHiringCursor: String?
    @State private var isLoadingMore = false

    private var hasMoreListings: Bool {
        nextCursor != nil || nextHiringCursor != nil
    }

    private var marketplaceGridSpacing: CGFloat { 12 }

    private var marketplaceCardWidth: CGFloat {
        let contentWidth = activeScreenWidth - (KaiXTheme.horizontalPadding * 2)
        return max(142, floor((contentWidth - marketplaceGridSpacing) / 2))
    }

    private var activeScreenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState != .unattached }?
            .screen.bounds.width ?? 393
    }

    private var secondhandRows: [[KaiXCityListingDTO]] {
        stride(from: 0, to: visibleItems.count, by: 2).map { start in
            Array(visibleItems[start..<min(start + 2, visibleItems.count)])
        }
    }

    private var region: KaiXRegionDirectory.Region? {
        KaiXRegionDirectory.resolve(regionCode: regionCode)
    }

    /// 服务频道分区与发布页第一阶段正式类目保持一致。
    /// 住宿类目已整体搬去租房页「民宿」，这里不再展示。
    static let serviceSections: [(key: String, title: String, categories: [String])] = [
        ("all", "全部", []),
        ("food", "餐厅", KXListingCopy.foodSectionCategories),
        ("travel", "旅行票务", KXListingCopy.travelSectionCategories),
        ("transfer", "接送交通", KXListingCopy.transferSectionCategories),
        ("paperwork", "翻译手续", KXListingCopy.paperworkSectionCategories),
        ("moving", "搬家清洁", KXListingCopy.movingSectionCategories),
        ("life", "生活开通", KXListingCopy.lifeSetupSectionCategories),
        ("beauty", "美容健康", KXListingCopy.beautyHealthSectionCategories),
    ]

    /// 「stays / hotels」是住房频道伪类型；旧 hotels 深链统一归并到民宿。
    /// 工作频道兼容 work/job/hiring 三种入口，避免外部深链只展示半条招聘流。
    private var baseType: String {
        let raw = listingType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "stays", "hotels":
            return "rental"
        case "work", "job", "jobs", "hiring":
            return "work"
        case "service", "services", "local_services":
            return "local_service"
        default:
            return raw
        }
    }
    private var isWorkChannel: Bool { baseType == "work" }

    private var staysActive: Bool { baseType == "rental" && activeRentalTab == .stays }
    private var lodgingActive: Bool { staysActive }

    /// 真正发给 API 的 listing type。
    private var queryType: String { lodgingActive ? "local_service" : baseType }

    enum RentalTab: String { case homes, stays }
    @State private var rentalTab: RentalTab?

    private var activeRentalTab: RentalTab {
        rentalTab ?? (listingType == "hotels" || listingType == "stays" ? .stays : .homes)
    }

    private var visibleItems: [KaiXCityListingDTO] {
        let sectionCategories = Self.serviceSections.first { $0.key == serviceSection }?.categories ?? []
        let filtered = items.filter { item in
            // 住宿新入口只展示民宿；服务频道隐藏全部住宿历史类目。
            if staysActive {
                guard KXListingCopy.isHomestayCategory(item.category) else { return false }
            } else if baseType == "local_service", KXListingCopy.isStayCategory(item.category) {
                return false
            }
            let categoryOK = selectedCategory == "全部" || (item.category ?? "").localizedCaseInsensitiveContains(selectedCategory)
            // 分区只在「全部」类目下生效，选中具体类目时以类目为准
            let sectionOK = baseType != "local_service"
                || selectedCategory != "全部"
                || sectionCategories.isEmpty
                || sectionCategories.contains(item.category ?? "")
            let queryOK = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || item.title.localizedCaseInsensitiveContains(query)
                || (item.description ?? "").localizedCaseInsensitiveContains(query)
                || (item.location_text ?? "").localizedCaseInsensitiveContains(query)
            let priceOK = (Double(minimumPrice).map { (item.price ?? 0) >= $0 } ?? true)
                && (Double(maximumPrice).map { (item.price ?? .greatestFiniteMagnitude) <= $0 } ?? true)
            // 属性筛选由服务端完成（attrFilters → attr_<key>），客户端不再
            // 重复判断——gte 这类语义客户端复刻不了，重复判断只会误隐藏。
            return categoryOK && sectionOK && queryOK && priceOK
        }
        return filtered.sorted(by: sortMode.sortsBefore)
    }

    private var selectedArea: ListingScopeArea? {
        listingScopeAreas.first { $0.id == selectedScopeArea }
    }

    private var selectedScopeRegion: KaiXRegionDirectory.Region? {
        KaiXRegionDirectory.resolve(regionCode: selectedScopeRegionCode)
    }

    private var activeScopeLabel: String {
        switch scopeMode {
        case .city:
            return region.map { KaiXRegionDirectory.localizedShortLabel($0, language: language) } ?? L("currentRegion", language)
        case .country:
            return region.map {
                KaiXRegionDirectory.localizedCountryName(
                    .init(code: $0.countryCode, name: $0.countryName, emoji: $0.countryEmoji, tier: 1, hasProvinces: !$0.provinceCode.isEmpty),
                    language: language
                )
            } ?? KXListingCopy.pickText(language, "当前国家", "現在の国", "Current country")
        case .area:
            return selectedArea?.localizedTitle(language) ?? KXListingCopy.pickText(language, "城市圈", "都市圏", "Metro area")
        case .selectedCity:
            return selectedScopeRegion.map { KaiXRegionDirectory.localizedShortLabel($0, language: language) } ?? ListingFilterLocalizer.text("热门城市", language)
        }
    }

    private var activeFilterCount: Int {
        var count = 0
        if selectedCategory != "全部" { count += 1 }
        if scopeMode != .city { count += 1 }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !minimumPrice.isEmpty { count += 1 }
        if !maximumPrice.isEmpty { count += 1 }
        count += attrFilters.values.filter { !$0.isEmpty }.count
        return count
    }

    private var serverSort: String {
        switch sortMode {
        case .newest: "latest"
        case .priceLow: "price_asc"
        case .priceHigh: "price_desc"
        case .rating: "rating"
        }
    }

    /// 评分排序只对有点评体系的内容开放（服务频道与住宿分区）。
    private var availableSortModes: [ListingSortMode] {
        baseType == "local_service" || lodgingActive
            ? ListingSortMode.allCases
            : ListingSortMode.allCases.filter { $0 != .rating }
    }

    /// 选择/开关筛选即静默重载——保留旧列表避免闪白，结果回来再替换。
    private func attrChoiceBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { attrFilters[key] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    attrFilters.removeValue(forKey: key)
                } else {
                    attrFilters[key] = newValue
                }
                Task { await load(quiet: true) }
            }
        )
    }

    private func attrToggleBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { attrFilters[key] == "true" },
            set: { isOn in
                if isOn {
                    attrFilters[key] = "true"
                } else {
                    attrFilters.removeValue(forKey: key)
                }
                Task { await load(quiet: true) }
            }
        )
    }

    private var lodgingCategories: [String] {
        if staysActive { return KXListingCopy.homestayCategories }
        return []
    }

    private var serverLodgingCategory: String? {
        lodgingActive && selectedCategory != "全部" ? selectedCategory : nil
    }

    private var serverCategory: String? {
        if lodgingActive { return serverLodgingCategory }
        if baseType == "local_service", selectedCategory != "全部" { return selectedCategory }
        return nil
    }

    private var serverCategories: [String] {
        if lodgingActive {
            return serverLodgingCategory == nil ? lodgingCategories : []
        }
        if baseType == "local_service", selectedCategory == "全部" {
            return Self.serviceSections.first { $0.key == serviceSection }?.categories ?? []
        }
        return []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // Pinned search-first chrome: search pill + icon rail stay reachable
            // while listings scroll under; secondary rows condense on scroll.
            listingControls
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 10)
            if mapMode {
                ListingMapView(listings: visibleItems) { id in
                    router.open(.cityListingDetail(listingId: id))
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if baseType == "local_service" {
                            MerchantDirectoryStripView(citySlug: regionCode)
                        }
                        stateContent
                        if !isLoading, errorMessage == nil, hasMoreListings {
                            // Sentinel row: scrolling it into view pulls the next
                            // server page. Re-armed by id whenever items grow.
                            KXInlineLoader()
                                .task(id: items.count) { await loadMore() }
                        }
                    }
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
                    .padding(.top, 6)
                    .padding(.bottom, chrome.bottomContentPadding + 28)
                    .kxReadableWidth(820)
                }
                .refreshable { await load() }
                .kxScrollCollapse($headerCollapsed)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLoading, errorMessage == nil, !visibleItems.isEmpty {
                mapToggle
                    .padding(.bottom, 24)
            }
        }
        .kxPageBackground()
        .sheet(isPresented: $filtersOpen) { filterSheet }
        .sheet(isPresented: $wishlistOpen) {
            WishlistView { id in openFromWishlist(id) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(regionCode)-\(listingType)-\(activeRentalTab.rawValue)") {
            applyDefaultScopeIfNeeded()
            await load()
        }
        .onChange(of: minimumPrice) { _, _ in Task { await load(quiet: true) } }
        .onChange(of: maximumPrice) { _, _ in Task { await load(quiet: true) } }
    }

    private var header: some View {
        HStack(spacing: KXSpacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(region.map { KaiXRegionDirectory.localizedShortLabel($0, language: language) } ?? L("currentRegion", language)) · \(KXListingCopy.title(for: baseType, language))")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(KXListingCopy.subtitle(for: baseType, language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { wishlistOpen = true } label: {
                Image(systemName: "heart")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KXListingCopy.pickText(language, "我的收藏", "お気に入り", "Saved"))
            Button {
                router.open(.createCityListing(type: KXListingCopy.createType(for: lodgingActive ? "local_service" : baseType), citySlug: regionCode))
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(KXColor.livingAccent, in: Circle())
                    .shadow(color: KXColor.livingAccent.opacity(0.18), radius: 9, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    /// Dismiss the wishlist sheet, then push the chosen listing's detail on the
    /// host stack (same deferred pattern as the inquiry receipt sheet).
    private func openFromWishlist(_ id: String) {
        wishlistOpen = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            router.open(.cityListingDetail(listingId: id))
        }
    }

    /// Floating list ⇄ map switch (Airbnb-style), centred above the safe area.
    private var mapToggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { mapMode.toggle() }
        } label: {
            Label(
                mapMode ? KXListingCopy.pickText(language, "列表", "リスト", "List") : KXListingCopy.pickText(language, "地图", "地図", "Map"),
                systemImage: mapMode ? "list.bullet" : "map.fill"
            )
            .font(.subheadline.weight(.black))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 46)
            .background(KXColor.livingInk, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(KXPressableStyle(scale: 0.95))
    }

    /// 住房频道双标签：长租 / 民宿。
    private var rentalTabSwitcher: some View {
        HStack(spacing: 4) {
            rentalTabButton(.homes, title: KXListingCopy.pickText(language, "长租", "長期賃貸", "Rentals"), icon: "house")
            rentalTabButton(.stays, title: KXListingCopy.pickText(language, "民宿", "民泊", "Homestays"), icon: "bed.double")
        }
        .padding(4)
        .background(KXColor.softBackground.opacity(0.82), in: Capsule())
        .overlay(Capsule().stroke(KXColor.separator.opacity(0.6), lineWidth: 0.7))
        .frame(maxWidth: .infinity)
    }

    private func rentalTabButton(_ tab: RentalTab, title: String, icon: String) -> some View {
        Button {
            guard activeRentalTab != tab else { return }
            rentalTab = tab
            selectedCategory = "全部"
            // 三个分区的筛选维度不同（长租=户型/家具，住宿=人数/早餐），
            // 残留上一分区的条件会变成隐形过滤；评分排序仅住宿分区可用。
            attrFilters = [:]
            if sortMode == .rating, tab == .homes { sortMode = .newest }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.black))
                .foregroundStyle(activeRentalTab == tab ? Color.white : KXColor.livingInk)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .frame(maxWidth: .infinity)
                .background(activeRentalTab == tab ? KXColor.livingAccent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var listingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if baseType == "rental", !headerCollapsed {
                rentalTabSwitcher
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            heroSearchBar
            categoryIconRail
            serviceSubCategoryRail
            if !headerCollapsed {
                resultSummaryRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Web-parity second-level menu for 商家与服务: once a primary section
    /// (餐厅 / 旅行票务 …) is chosen, its sub-categories appear as a chip row so
    /// users can drill in (e.g. 餐厅 → 中餐 / 日料 / 火锅). Driven by the existing
    /// serviceSections taxonomy + selectedCategory state.
    @ViewBuilder private var serviceSubCategoryRail: some View {
        if baseType == "local_service", serviceSection != "all" {
            let subs = Self.serviceSections.first { $0.key == serviceSection }?.categories ?? []
            if !subs.isEmpty {
                KXFadingHScroll {
                    HStack(spacing: 8) {
                        serviceSubChip(ListingFilterLocalizer.text("全部", language), value: "全部")
                        ForEach(subs, id: \.self) { cat in
                            serviceSubChip(ListingFilterLocalizer.text(cat, language), value: cat)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func serviceSubChip(_ title: String, value: String) -> some View {
        let selected = selectedCategory == value
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                selectedCategory = value
                Task { await load(quiet: true) }
            }
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? Color.white : KXColor.livingInk)
                .padding(.horizontal, 13)
                .frame(height: 32)
                .background(selected ? KXColor.livingAccent : KXColor.softBackground.opacity(0.88), in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : KXColor.separator.opacity(0.6), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    /// 爱彼迎式搜索条：左端城市/范围菜单 + 内联搜索框，合成一颗悬浮胶囊。
    private var heroSearchBar: some View {
        HStack(spacing: 0) {
            scopeMenu
            Rectangle()
                .fill(KXColor.livingInk.opacity(0.10))
                .frame(width: 1, height: 26)
                .padding(.horizontal, 10)
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(KXColor.livingAccent)
            TextField(KXListingCopy.searchPlaceholder(for: staysActive ? "stays" : baseType, language), text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 8)
                .onSubmit { Task { await load(quiet: true) } }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    query = ""
                    Task { await load(quiet: true) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(height: 56)
        .background(KXColor.livingSurface, in: Capsule())
        .overlay(Capsule().stroke(KXColor.livingInk.opacity(0.09), lineWidth: 0.8))
        .shadow(color: KXColor.glassShadow.opacity(0.6), radius: 12, y: 5)
    }

    /// 范围菜单：城市 / 全国 / 都市圈，收进搜索胶囊左端（热门城市仍在筛选面板）。
    private var scopeMenu: some View {
        Menu {
            Button {
                selectScope(.city)
            } label: {
                Label(region.map { KaiXRegionDirectory.localizedShortLabel($0, language: language) } ?? KXListingCopy.pickText(language, "本市", "現在の都市", "This city"), systemImage: scopeMode == .city ? "checkmark" : "building.2")
            }
            Button {
                selectScope(.country)
            } label: {
                Label(region.map {
                    KaiXRegionDirectory.localizedCountryName(
                        .init(code: $0.countryCode, name: $0.countryName, emoji: $0.countryEmoji, tier: 1, hasProvinces: !$0.provinceCode.isEmpty),
                        language: language
                    )
                } ?? KXListingCopy.pickText(language, "全国", "全国", "Whole country"), systemImage: scopeMode == .country ? "checkmark" : "globe.asia.australia")
            }
            Section(KXListingCopy.pickText(language, "都市圈", "都市圏", "Metro areas")) {
                ForEach(listingScopeAreas) { area in
                    Button {
                        selectScope(.area, area: area.id)
                    } label: {
                        Label(area.localizedTitle(language), systemImage: scopeMode == .area && selectedScopeArea == area.id ? "checkmark" : "map")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.livingAccent)
                Text(activeScopeLabel)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(KXColor.livingInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: 150)
            .frame(height: 40)
            .background(KXColor.livingSoft.opacity(0.9), in: Capsule())
        }
    }

    private func selectScope(_ mode: ListingScopeMode, area: String = "", cityCode: String = "") {
        scopeMode = mode
        selectedScopeArea = area
        selectedScopeRegionCode = cityCode
        Task { await load() }
    }

    /// 爱彼迎标志性的图标类目滑栏 + 末端固定的排序 / 筛选按钮。
    private var categoryIconRail: some View {
        HStack(spacing: 8) {
            KXFadingHScroll {
                HStack(spacing: 2) {
                    if baseType == "local_service" {
                        ForEach(Self.serviceSections, id: \.key) { section in
                            categoryIconItem(
                                title: ListingFilterLocalizer.text(section.title, language),
                                icon: KXListingCopy.serviceSectionIcon(section.key),
                                selected: serviceSection == section.key && selectedCategory == "全部"
                            ) {
                                serviceSection = section.key
                                selectedCategory = "全部"
                                Task { await load(quiet: true) }
                            }
                        }
                    } else {
                        ForEach(visibleCategoryChips, id: \.self) { category in
                            categoryIconItem(
                                title: KXListingCopy.categoryLabel(category, language),
                                icon: KXListingCopy.categoryIcon(category),
                                selected: selectedCategory == category
                            ) {
                                selectedCategory = category
                                Task { await load(quiet: true) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            sortButton
            filtersButton
        }
    }

    private func categoryIconItem(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 22)
                Text(title)
                    .font(.caption2.weight(selected ? .heavy : .semibold))
                    .lineLimit(1)
                    .fixedSize()
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(selected ? KXColor.livingInk : Color.clear)
                    .frame(width: 18, height: 2.5)
            }
            .foregroundStyle(selected ? KXColor.livingInk : KXColor.livingMuted)
            .padding(.horizontal, 9)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sortButton: some View {
        Menu {
            ForEach(availableSortModes) { mode in
                Button {
                    sortMode = mode
                    Task { await load(quiet: true) }
                } label: {
                    if sortMode == mode {
                        Label(mode.title(language), systemImage: "checkmark")
                    } else {
                        Text(mode.title(language))
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(KXColor.livingInk)
                .frame(width: 44, height: 44)
                .background(KXColor.livingSoft.opacity(0.9), in: Circle())
                .overlay(Circle().stroke(KXColor.livingInk.opacity(0.08), lineWidth: 0.8))
        }
        .accessibilityLabel(KXListingCopy.pickText(language, "排序", "並び替え", "Sort"))
    }

    private var filtersButton: some View {
        Button {
            filtersOpen = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(sheetFilterCount > 0 ? Color.white : KXColor.livingInk)
                    .frame(width: 44, height: 44)
                    .background(sheetFilterCount > 0 ? KXColor.livingAccent : KXColor.livingSoft.opacity(0.9), in: Circle())
                    .overlay(Circle().stroke(sheetFilterCount > 0 ? Color.clear : KXColor.livingInk.opacity(0.08), lineWidth: 0.8))
                if sheetFilterCount > 0 {
                    Text("\(sheetFilterCount)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(KXColor.livingAccent)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().stroke(KXColor.livingAccent, lineWidth: 1.2))
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KXListingCopy.pickText(language, "筛选", "絞り込み", "Filters"))
    }

    /// 轻量结果摘要行：结果数 + 当前范围/类目 + 清空。
    private var resultSummaryRow: some View {
        HStack(spacing: 6) {
            Text(resultCountText(visibleItems.count))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            Text("\(activeScopeLabel) · \(ListingFilterLocalizer.text(selectedCategory, language))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            if activeFilterCount > 0 {
                Button {
                    clearAllFilters()
                } label: {
                    Label(KXListingCopy.pickText(language, "清空筛选", "絞り込みをクリア", "Clear filters"), systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private func clearAllFilters() {
        query = ""
        selectedCategory = "全部"
        scopeMode = .city
        selectedScopeArea = ""
        selectedScopeRegionCode = ""
        minimumPrice = ""
        maximumPrice = ""
        attrFilters = [:]
        Task { await load() }
    }

    /// 筛选面板内的条件计数（类目在滑栏、城市/全国在菜单，不计入角标）。
    private var sheetFilterCount: Int {
        var count = 0
        if !minimumPrice.isEmpty { count += 1 }
        if !maximumPrice.isEmpty { count += 1 }
        if scopeMode == .area || scopeMode == .selectedCity { count += 1 }
        if baseType == "local_service", selectedCategory != "全部" { count += 1 }
        count += attrFilters.values.filter { !$0.isEmpty }.count
        return count
    }

    private var visibleCategoryChips: [String] {
        if baseType == "local_service" {
            let quick: [String]
            switch serviceSection {
            case "food":
                quick = ["全部", "中华料理", "日本料理", "居酒屋", "烧肉火锅", "咖啡甜品"]
            case "travel":
                quick = ["全部", "景点门票", "一日游", "本地向导", "体验活动", "包车行程"]
            case "transfer":
                quick = ["全部", "机场接送", "车站接送", "包车", "行李协助"]
            case "paperwork":
                quick = ["全部", "材料翻译", "市役所陪同", "银行卡协助", "手机卡协助", "租房申请协助"]
            case "moving":
                quick = ["全部", "搬家", "退房清洁", "粗大垃圾协助", "行李搬运", "家具家电配送协助"]
            case "life":
                quick = ["全部", "手机卡开通", "网络开通", "水电煤协助", "地址登记协助", "粗大垃圾预约"]
            case "beauty":
                quick = ["全部", "美容美发", "美甲", "按摩", "皮肤管理", "体检/牙科预约协助"]
            default:
                quick = ["全部", "中华料理", "日本料理", "景点门票", "机场接送", "材料翻译", "搬家", "美容美发"]
            }
            return selectedCategory == "全部" || quick.contains(selectedCategory) ? quick : quick + [selectedCategory]
        }
        return KXListingCopy.categories(for: staysActive ? "stays" : baseType)
    }

    /// 全部细筛收进底部弹出面板，带「查看 N 个结果」固定底栏（爱彼迎式）。
    private var filterSheet: some View {
        NavigationStack {
            ScrollView {
                scopeFilterPanel
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
            }
            .background(KXColor.pageBackground.ignoresSafeArea())
            .navigationTitle(KXListingCopy.pickText(language, "筛选", "絞り込み", "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if activeFilterCount > 0 {
                        Button(KXListingCopy.pickText(language, "清空", "クリア", "Clear")) {
                            clearAllFilters()
                        }
                        .foregroundStyle(KXColor.livingAccent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        filtersOpen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                filterSheetBottomBar
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var filterSheetBottomBar: some View {
        Button {
            filtersOpen = false
        } label: {
            Text(KXListingCopy.pickText(language, "查看 \(visibleItems.count) 个结果", "\(visibleItems.count) 件を見る", "Show \(visibleItems.count) results"))
                .kxGlassButton(prominent: true)
        }
        .buttonStyle(KXPressableStyle(scale: 0.97))
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.4) }
    }

    private var scopeFilterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ListingFilterLocalizer.text(baseType == "rental" ? (lodgingActive ? "每晚价格" : "月租范围") : isWorkChannel ? "薪资范围" : "价格范围", language))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    filterPriceField(title: ListingFilterLocalizer.text("最低", language), text: $minimumPrice)
                    Text("—")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    filterPriceField(title: ListingFilterLocalizer.text("最高", language), text: $maximumPrice)
                }
            }

            if baseType == "secondhand" {
                filterChoiceSection(
                    title: "发布类型",
                    options: [("", "全部"), ("sale", "出售"), ("free", "免费送"), ("wanted", "求购")],
                    selection: attrChoiceBinding("listing_mode")
                )
                filterChoiceSection(
                    title: "新旧程度",
                    options: [("", "不限"), ("brand_new", "全新"), ("like_new", "几乎全新"), ("good", "良好"), ("used", "有使用痕迹"), ("fair", "可用")],
                    selection: attrChoiceBinding("condition")
                )
                filterChoiceSection(
                    title: "交易方式",
                    options: [("", "不限"), ("meetup", "面交"), ("pickup", "自取"), ("shipping", "邮寄"), ("negotiable", "可商量")],
                    selection: attrChoiceBinding("delivery_method")
                )
                filterToggleSection(title: "交易偏好", toggles: [
                    ("price_negotiable", "价格可议"),
                    ("pickup_available", "可自取"),
                    ("shipping_available", "可邮寄"),
                ])
            } else if lodgingActive {
                filterChoiceSection(
                    title: "可住人数",
                    options: [("", "不限"), ("2", "2 人及以上"), ("3", "3 人及以上"), ("4", "4 人及以上"), ("6", "6 人及以上")],
                    selection: attrChoiceBinding("gte_max_guests")
                )
                filterToggleSection(title: "住宿条件", toggles: [
                    ("breakfast_included", "含早餐"),
                    ("instant_confirmation", "即时确认"),
                    ("certified_provider", "认证商家"),
                ])
            } else if baseType == "rental" {
                filterChoiceSection(
                    title: "户型",
                    options: [("", "不限"), ("1R", "1R"), ("1K", "1K"), ("1DK", "1DK"), ("1LDK", "1LDK"), ("2K", "2K"), ("2LDK", "2LDK"), ("合租", "合租")],
                    selection: attrChoiceBinding("layout")
                )
                filterToggleSection(title: "条件", toggles: [
                    ("furnished", "家具家电"),
                    ("pet_allowed", "可宠物"),
                    ("share_allowed", "可合租"),
                ])
            } else if isWorkChannel {
                filterChoiceSection(
                    title: "雇佣形式",
                    options: [("", "不限"), ("part_time", "兼职"), ("full_time", "全职"), ("dispatch", "派遣"), ("internship", "实习")],
                    selection: attrChoiceBinding("employment_type")
                )
                filterChoiceSection(
                    title: "日语要求",
                    options: [("", "不限"), ("not_required", "日语不限"), ("N5", "N5"), ("N4", "N4"), ("N3", "N3"), ("N2", "N2"), ("N1", "N1")],
                    selection: attrChoiceBinding("japanese_level")
                )
                filterChoiceSection(
                    title: "签证支持",
                    // "available,true" 兼容老数据：早期版本把 visa_support 存成了布尔。
                    options: [("", "不限"), ("available,true", "有"), ("consult", "可咨询")],
                    selection: attrChoiceBinding("visa_support")
                )
                filterToggleSection(title: "条件", toggles: [
                    ("no_experience_ok", "无经验可"),
                    ("student_ok", "留学生可"),
                    ("remote_ok", "可远程"),
                ])
            } else if baseType == "local_service" {
                filterChoiceSection(
                    title: "服务细分类",
                    options: serviceCategoryFilterOptions,
                    selection: Binding(
                        get: { selectedCategory },
                        set: { newValue in
                            selectedCategory = newValue
                            Task { await load(quiet: true) }
                        }
                    )
                )
                filterToggleSection(title: "商家条件", toggles: [
                    ("booking_required", "需要预约"),
                    ("certified_provider", "认证商家"),
                ])
            }

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 7) {
                Text(ListingFilterLocalizer.text("城市范围", language))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                ForEach(listingScopeAreas) { area in
                    Button {
                        scopeMode = .area
                        selectedScopeArea = area.id
                        selectedScopeRegionCode = ""
                        Task { await load() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedScopeArea == area.id && scopeMode == .area ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(selectedScopeArea == area.id && scopeMode == .area ? KXColor.accent : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(area.localizedTitle(language))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text(area.localizedSubtitle(language))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 54)
                        .background(KXColor.softBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(ListingFilterLocalizer.text("热门城市", language))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(listingScopeHotCityCodes, id: \.self) { code in
                        if let city = KaiXRegionDirectory.resolve(regionCode: code) {
                            Button {
                                scopeMode = .selectedCity
                                selectedScopeRegionCode = city.regionCode
                                selectedScopeArea = ""
                                Task { await load() }
                            } label: {
                                Text(KaiXRegionDirectory.localizedShortLabel(city, language: language))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(scopeMode == .selectedCity && selectedScopeRegionCode == city.regionCode ? Color.white : .primary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(scopeMode == .selectedCity && selectedScopeRegionCode == city.regionCode ? KXColor.accent : KXColor.softBackground.opacity(0.88), in: Capsule())
                                    .overlay(Capsule().stroke(KXColor.separator.opacity(0.55), lineWidth: 0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

        }
        .padding(12)
        .background(KXColor.softBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var serviceCategoryFilterOptions: [(value: String, label: String)] {
        let categories: [String]
        switch serviceSection {
        case "food":
            categories = KXListingCopy.foodSectionCategories
        case "travel":
            categories = KXListingCopy.travelSectionCategories
        case "transfer":
            categories = KXListingCopy.transferSectionCategories
        case "paperwork":
            categories = KXListingCopy.paperworkSectionCategories
        case "moving":
            categories = KXListingCopy.movingSectionCategories
        case "life":
            categories = KXListingCopy.lifeSetupSectionCategories
        case "beauty":
            categories = KXListingCopy.beautyHealthSectionCategories
        default:
            categories = KXListingCopy.foodSectionCategories + KXListingCopy.travelSectionCategories + KXListingCopy.transferSectionCategories + KXListingCopy.lifeSectionCategories
        }
        let unique = categories.reduce(into: [String]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }
        return [("全部", "全部")] + unique.map { ($0, KXListingCopy.categoryLabel($0, language)) }
    }

    private func filterPriceField(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text("¥")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .keyboardType(.numberPad)
                .font(.subheadline.weight(.bold))
                .onSubmit { Task { await load(quiet: true) } }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(KXColor.separator.opacity(0.7), lineWidth: 0.7))
    }

    private func filterChoiceSection(
        title: String,
        options: [(value: String, label: String)],
        selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ListingFilterLocalizer.text(title, language))
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    Button {
                        selection.wrappedValue = option.value
                    } label: {
                        Text(ListingFilterLocalizer.text(option.label, language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selection.wrappedValue == option.value ? Color.white : .primary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(selection.wrappedValue == option.value ? KXColor.accent : Color(.systemBackground), in: Capsule())
                            .overlay(Capsule().stroke(selection.wrappedValue == option.value ? Color.clear : KXColor.separator.opacity(0.65), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func filterToggleSection(title: String, toggles: [(key: String, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ListingFilterLocalizer.text(title, language))
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(toggles, id: \.key) { item in
                    filterToggle(title: ListingFilterLocalizer.text(item.label, language), isOn: attrToggleBinding(item.key))
                }
            }
        }
    }

    private func filterToggle(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.bold))
                .foregroundStyle(isOn.wrappedValue ? KXColor.accent : .primary)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(Color(.systemBackground), in: Capsule())
                .overlay(Capsule().stroke(isOn.wrappedValue ? KXColor.accent.opacity(0.45) : KXColor.separator.opacity(0.65), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var stateContent: some View {
        if isLoading {
            loadingSkeleton
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) { Task { await load() } }
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if visibleItems.isEmpty {
            VStack(spacing: 18) {
                EmptyStateView(
                    title: KXListingCopy.emptyTitle(for: staysActive ? "stays" : baseType, language),
                    subtitle: KXListingCopy.emptySubtitle(for: staysActive ? "stays" : baseType, language),
                    systemImage: KXListingCopy.icon(for: baseType)
                )
                Button {
                    router.open(.createCityListing(type: KXListingCopy.createType(for: lodgingActive ? "local_service" : baseType), citySlug: regionCode))
                } label: {
                    Label(KXListingCopy.createTitle(for: lodgingActive ? "local_service" : baseType, language), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(height: 48)
                        .background(KXColor.livingAccent, in: Capsule())
                        .shadow(color: KXColor.livingAccent.opacity(0.25), radius: 12, y: 5)
                }
                .buttonStyle(KXPressableStyle())
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if isWorkChannel {
            // Indeed-style job cards, Airbnb layout: each role is its own
            // elevated card with breathing room — no outer surface (which
            // would nest card-in-card with KXJobListingRow's own surface).
            LazyVStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    KXJobListingRow(listing: item) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                    .kxListingZoomSource("listing-\(item.id)", zoomNamespace)
                }
            }
        } else if baseType == "secondhand" {
            // Two-column photo grid: square covers, price first, quick scan.
            LazyVStack(spacing: 14) {
                ForEach(secondhandRows.indices, id: \.self) { rowIndex in
                    HStack(alignment: .top, spacing: marketplaceGridSpacing) {
                        ForEach(secondhandRows[rowIndex]) { item in
                            KXSecondhandListingCard(listing: item, width: marketplaceCardWidth) {
                                router.open(.cityListingDetail(listingId: item.id))
                            }
                            .kxListingZoomSource("listing-\(item.id)", zoomNamespace)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if secondhandRows[rowIndex].count == 1 {
                            Spacer(minLength: 0)
                                .frame(width: marketplaceCardWidth)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
        } else if baseType == "rental" {
            // 照片主导卡：长租与民宿共用同一套视觉语言。
            LazyVStack(spacing: 18) {
                ForEach(visibleItems) { item in
                    KXStayListingCard(listing: item, variant: staysActive ? .stay : .home) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                    .kxListingZoomSource("listing-\(item.id)", zoomNamespace)
                }
            }
        } else if baseType == "local_service" {
            // 服务卡片：评分、类目、价位、预约 CTA。
            LazyVStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    KXServiceListingCard(listing: item) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                    .kxListingZoomSource("listing-\(item.id)", zoomNamespace)
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    KXStructuredListingRow(listing: item) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                    .kxListingZoomSource("listing-\(item.id)", zoomNamespace)
                }
            }
        }
    }

    /// 按频道形态给出对应骨架占位，替代单调的居中转圈，初次加载也保留版式。
    @ViewBuilder
    private var loadingSkeleton: some View {
        if isWorkChannel {
            LazyVStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in KXJobSkeletonRow() }
            }
        } else if baseType == "secondhand" {
            LazyVStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(alignment: .top, spacing: marketplaceGridSpacing) {
                        KXSecondhandSkeletonCard(width: marketplaceCardWidth)
                        KXSecondhandSkeletonCard(width: marketplaceCardWidth)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if baseType == "rental" {
            LazyVStack(spacing: 18) {
                ForEach(0..<3, id: \.self) { _ in KXBigPhotoSkeletonCard() }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in KXBigPhotoSkeletonCard() }
            }
        }
    }

    /// quiet = 筛选/排序微调时静默重载：保留旧列表直到新结果回来，避免闪白。
    private func load(quiet: Bool = false) async {
        guard let region else {
            errorMessage = "城市无法识别，请重新选择城市。"
            isLoading = false
            return
        }
        if !quiet { isLoading = true }
        errorMessage = nil
        do {
            let scope = listingScopeQuery(for: region)
            if isWorkChannel {
                async let jobs = KaiXAPIClient.shared.listingsPage(type: "job", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, countryCode: scope.countryCode, query: query, minPrice: Double(minimumPrice), maxPrice: Double(maximumPrice), sort: serverSort, attributes: attrFilters)
                async let hiring = KaiXAPIClient.shared.listingsPage(type: "hiring", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, countryCode: scope.countryCode, query: query, minPrice: Double(minimumPrice), maxPrice: Double(maximumPrice), sort: serverSort, attributes: attrFilters)
                let jobPage = try await jobs
                let hiringPage = try await hiring
                items = (jobPage.items + hiringPage.items).sorted(by: KXListingCopy.sortForDisplay)
                nextCursor = jobPage.nextCursor
                nextHiringCursor = hiringPage.nextCursor
            } else {
                let page = try await KaiXAPIClient.shared.listingsPage(
                    type: queryType,
                    citySlug: scope.citySlug,
                    regionCode: scope.regionCode,
                    regionCodes: scope.regionCodes,
                    countryCode: scope.countryCode,
                    query: query,
                    category: serverCategory,
                    categories: serverCategories,
                    minPrice: Double(minimumPrice),
                    maxPrice: Double(maximumPrice),
                    sort: serverSort,
                    attributes: attrFilters
                )
                items = page.items
                nextCursor = page.nextCursor
                nextHiringCursor = nil
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// Pull the next server page(s) and append, deduplicating by id so a
    /// row that moved between keyset windows can never show twice.
    private func loadMore() async {
        guard !isLoadingMore, !isLoading, hasMoreListings, let region else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let scope = listingScopeQuery(for: region)
        do {
            var fetched: [KaiXCityListingDTO] = []
            if isWorkChannel {
                if let cursor = nextCursor {
                    let page = try await KaiXAPIClient.shared.listingsPage(type: "job", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, countryCode: scope.countryCode, query: query, minPrice: Double(minimumPrice), maxPrice: Double(maximumPrice), sort: serverSort, attributes: attrFilters, cursor: cursor)
                    fetched += page.items
                    nextCursor = page.nextCursor
                }
                if let cursor = nextHiringCursor {
                    let page = try await KaiXAPIClient.shared.listingsPage(type: "hiring", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, countryCode: scope.countryCode, query: query, minPrice: Double(minimumPrice), maxPrice: Double(maximumPrice), sort: serverSort, attributes: attrFilters, cursor: cursor)
                    fetched += page.items
                    nextHiringCursor = page.nextCursor
                }
            } else if let cursor = nextCursor {
                let page = try await KaiXAPIClient.shared.listingsPage(
                    type: queryType,
                    citySlug: scope.citySlug,
                    regionCode: scope.regionCode,
                    regionCodes: scope.regionCodes,
                    countryCode: scope.countryCode,
                    query: query,
                    category: serverCategory,
                    categories: serverCategories,
                    minPrice: Double(minimumPrice),
                    maxPrice: Double(maximumPrice),
                    sort: serverSort,
                    attributes: attrFilters,
                    cursor: cursor
                )
                fetched = page.items
                nextCursor = page.nextCursor
            }
            let existing = Set(items.map(\.id))
            items += fetched.filter { !existing.contains($0.id) }
        } catch {
            // Quietly stop paging on error; pull-to-refresh recovers.
            nextCursor = nil
            nextHiringCursor = nil
        }
    }

    /// The metro area whose member cities share the current region's province
    /// (关东圈 contains jp.chiba.*, so 千叶/柏 → kanto). nil when the current
    /// region isn't part of a known metro circle.
    private func defaultMetroAreaId(for region: KaiXRegionDirectory.Region) -> String? {
        let provincePrefix = "\(region.countryCode).\(region.provinceCode)."
        return listingScopeAreas.first { area in
            area.regionCodes.contains { $0.hasPrefix(provincePrefix) }
        }?.id
    }

    private func applyDefaultScopeIfNeeded() {
        guard !didApplyDefaultScope else { return }
        didApplyDefaultScope = true
        guard scopeMode == .city, let region, let areaId = defaultMetroAreaId(for: region) else { return }
        scopeMode = .area
        selectedScopeArea = areaId
        selectedScopeRegionCode = ""
    }

    private func listingScopeQuery(for region: KaiXRegionDirectory.Region) -> (citySlug: String?, regionCode: String?, regionCodes: [String], countryCode: String?) {
        switch scopeMode {
        case .city:
            return (region.cityCode, region.regionCode, [], nil)
        case .country:
            return (nil, nil, [], region.countryCode)
        case .area:
            return (nil, nil, selectedArea?.regionCodes ?? [], nil)
        case .selectedCity:
            let selected = selectedScopeRegion ?? region
            return (selected.cityCode, selected.regionCode, [], nil)
        }
    }

    private func resultCountText(_ count: Int) -> String {
        KXListingCopy.pickText(language, "\(count) 条结果", "\(count)件の結果", "\(count) results")
    }
}

/// One user's published listings of a single type — opened from a tappable
/// count tag on their profile ("出售二手 5" → their secondhand items). Reuses
/// the channel cards but is seller-scoped across all cities (no region filter).
struct UserListingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState
    let userId: String
    let listingType: String
    let title: String
    let currentUser: UserEntity

    @State private var items: [KaiXCityListingDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var baseType: String {
        listingType == "hiring" ? "job" : listingType
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if isLoading {
                    LoadingView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load() } }
                } else if items.isEmpty {
                    KXEmptyState(
                        title: KXListingCopy.pickText(language, "暂无发布", "まだ投稿がありません", "No listings yet"),
                        subtitle: KXListingCopy.pickText(language, "TA 还没有发布该类型的内容。", "この種類の投稿はまだありません。", "This person has not published this type of listing yet."),
                        systemImage: "tray"
                    )
                } else {
                    resultsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .kxPageBackground()
        .background(KXColor.livingBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(userId)-\(listingType)") { await load() }
    }

    private var header: some View {
        HStack(spacing: KXSpacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(KXColor.livingInk)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(KXColor.livingInk)
                Text(KXListingCopy.pickText(language, "\(items.count) 条发布", "\(items.count)件の投稿", "\(items.count) listings"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KXColor.livingMuted)
            }
            Spacer()
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(KXColor.livingBackground.opacity(0.94))
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    @ViewBuilder
    private var resultsList: some View {
        ScrollView {
            Group {
                if baseType == "secondhand" {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                        ForEach(items) { item in
                            KXSecondhandListingCard(listing: item) { router.open(.cityListingDetail(listingId: item.id)) }
                        }
                    }
                } else if baseType == "rental" {
                    LazyVStack(spacing: 18) {
                        ForEach(items) { item in
                            KXStayListingCard(listing: item, variant: KXListingCopy.isStayCategory(item.category) ? .stay : .home) {
                                router.open(.cityListingDetail(listingId: item.id))
                            }
                        }
                    }
                } else if baseType == "job" {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            KXJobListingRow(listing: item) { router.open(.cityListingDetail(listingId: item.id)) }
                        }
                    }
                } else if baseType == "local_service" {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            KXServiceListingCard(listing: item) { router.open(.cityListingDetail(listingId: item.id)) }
                        }
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            KXStructuredListingRow(listing: item) { router.open(.cityListingDetail(listingId: item.id)) }
                        }
                    }
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, chrome.bottomContentPadding + 24)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            // job tag covers both job + hiring; fetch both and merge.
            if listingType == "job" {
                async let jobs = KaiXAPIClient.shared.sellerListings(type: "job", sellerId: userId)
                async let hiring = KaiXAPIClient.shared.sellerListings(type: "hiring", sellerId: userId)
                items = sortListings((try await jobs) + (try await hiring))
            } else {
                items = sortListings(try await KaiXAPIClient.shared.sellerListings(type: listingType, sellerId: userId))
            }
            isLoading = false
        } catch {
            errorMessage = error.kaixUserMessage
            isLoading = false
        }
    }

    private func sortListings(_ listings: [KaiXCityListingDTO]) -> [KaiXCityListingDTO] {
        var seen = Set<String>()
        return listings
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.updated_at ?? $0.updatedAt ?? "") > ($1.updated_at ?? $1.updatedAt ?? "") }
    }
}

/// Reservation calendar on a listing detail (no money): a horizontal day strip
/// plus time-slot chips the merchant/landlord published. Renders nothing until
/// slots load and stays hidden when none exist, so it only appears where the
/// owner actually opened bookings (看房 / 餐厅订座 / 服务预约).
struct ListingBookingSection: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let listingId: String
    let listingType: String?

    @State private var slots: [KaiXBookingSlotDTO] = []
    @State private var loaded = false
    @State private var isOwner = false
    @State private var selectedDayKey: String?
    @State private var inFlightSlotId: String?
    @State private var bookedTick = 0
    @State private var toast: String?
    @State private var showAddSheet = false
    @State private var pendingDeleteSlot: KaiXBookingSlotDTO?
    @State private var pendingCancelSlot: KaiXBookingSlotDTO?

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        Group {
            if loaded && (!slots.isEmpty || isOwner) {
                KXListingSection(title: titleText, icon: "calendar.badge.clock") {
                    VStack(alignment: .leading, spacing: 14) {
                        if slots.isEmpty {
                            Text(KXListingCopy.pickText(language,
                                                        "还没有可预约的时段，添加后买家/租客就能直接在线预约。",
                                                        "予約枠がまだありません。追加すると相手が直接予約できます。",
                                                        "No slots yet — add some so people can reserve online."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            dayStrip
                            slotGrid
                        }
                        if isOwner {
                            Button {
                                showAddSheet = true
                            } label: {
                                Label(KXListingCopy.pickText(language, "添加预约时段", "予約枠を追加", "Add a slot"),
                                      systemImage: "plus.circle.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(KXColor.livingAccent)
                            }
                            .buttonStyle(KXPressableStyle())
                            if !slots.isEmpty {
                                Text(KXListingCopy.pickText(language, "长按时段可删除", "長押しで削除できます", "Long-press a slot to remove it"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if let toast {
                            Label(toast, systemImage: toast.contains("成功") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(toast.contains("成功") ? KXColor.livingAccent : KXColor.livingWarm)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        // After a successful booking, give the user a stable way to
                        // reach "我的预约" (the toast alone left them with no next step).
                        // Pushes onto the current stack via the shared route — no tab
                        // switch, no sheet-dismiss timing hazards.
                        if bookedTick > 0 {
                            Button {
                                router.open(.myReservations)
                            } label: {
                                Label(KXListingCopy.pickText(language, "查看我的预约", "予約を見る", "View my reservations"),
                                      systemImage: "calendar.badge.checkmark")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(KXColor.livingAccent)
                            }
                            .buttonStyle(KXPressableStyle())
                        }
                        Label(KXListingCopy.pickText(language,
                                                     "预约不收取任何费用，具体时间请到店/看房时与对方确认。",
                                                     "予約は無料です。詳細は現地で相手にご確認ください。",
                                                     "Booking is free — confirm the exact time with the host on arrival."),
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: listingId) { await reload() }
        .sensoryFeedback(.success, trigger: bookedTick)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedDayKey)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: bookedTick)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: slots.count)
        .sheet(isPresented: $showAddSheet) {
            AddBookingSlotSheet { startAt, capacity, note in
                Task { await addSlots([KaiXAPIClient.SlotInput(startAt: startAt, capacity: capacity, note: note)]) }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            KXListingCopy.pickText(language, "删除这个预约时段？", "この予約枠を削除しますか？", "Remove this slot?"),
            isPresented: Binding(get: { pendingDeleteSlot != nil }, set: { if !$0 { pendingDeleteSlot = nil } }),
            titleVisibility: .visible
        ) {
            Button(KXListingCopy.pickText(language, "删除", "削除", "Remove"), role: .destructive) {
                if let s = pendingDeleteSlot { Task { await deleteSlot(s) } }
                pendingDeleteSlot = nil
            }
            Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel"), role: .cancel) { pendingDeleteSlot = nil }
        } message: {
            Text(KXListingCopy.pickText(language, "已预约的用户会收到取消通知。", "予約済みのユーザーに取消通知が届きます。", "Anyone booked will be notified of the cancellation."))
        }
        .confirmationDialog(
            KXListingCopy.pickText(language, "取消你的预约？", "予約をキャンセルしますか？", "Cancel your reservation?"),
            isPresented: Binding(get: { pendingCancelSlot != nil }, set: { if !$0 { pendingCancelSlot = nil } }),
            titleVisibility: .visible
        ) {
            Button(KXListingCopy.pickText(language, "取消预约", "予約をキャンセル", "Cancel reservation"), role: .destructive) {
                if let s = pendingCancelSlot { Task { await cancelMyBooking(s) } }
                pendingCancelSlot = nil
            }
            Button(KXListingCopy.pickText(language, "返回", "戻る", "Keep"), role: .cancel) { pendingCancelSlot = nil }
        }
    }

    // Day pills (distinct days that have slots).
    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(dayKeys, id: \.self) { key in
                    let date = firstDate(forDay: key)
                    Button {
                        selectedDayKey = key
                    } label: {
                        VStack(spacing: 3) {
                            Text(weekdayText(date))
                                .font(.caption2.weight(.semibold))
                            Text(dayNumberText(date))
                                .font(.headline.weight(.bold))
                        }
                        .frame(width: 52, height: 60)
                        .foregroundStyle(key == selectedDayKey ? .white : KXColor.livingInk)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(key == selectedDayKey ? AnyShapeStyle(KXColor.livingAccent) : AnyShapeStyle(KXColor.livingAccentSoft.opacity(0.5)))
                        )
                    }
                    .buttonStyle(KXPressableStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }

    // Time-slot chips for the selected day.
    private var slotGrid: some View {
        FlowLayout(spacing: 10) {
            ForEach(slotsForSelectedDay) { slot in
                slotChip(slot)
            }
        }
    }

    @ViewBuilder
    private func slotChip(_ slot: KaiXBookingSlotDTO) -> some View {
        let booked = slot.resolvedBookedByMe
        let full = slot.resolvedIsFull && !booked
        let busy = inFlightSlotId == slot.id
        Button {
            if isOwner { return }
            if booked { pendingCancelSlot = slot } else { Task { await book(slot) } }
        } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.mini).tint(KXColor.livingAccent)
                } else if booked {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(timeText(slot.startDate))
                    .font(.subheadline.weight(.bold))
                if booked {
                    Text(KXListingCopy.pickText(language, "已预约", "予約済み", "Booked")).font(.caption2.weight(.semibold))
                } else if full {
                    Text(KXListingCopy.pickText(language, "已约满", "満席", "Full")).font(.caption2.weight(.semibold))
                } else {
                    Text(KXListingCopy.pickText(language, "剩\(slot.resolvedAvailable)", "残\(slot.resolvedAvailable)", "\(slot.resolvedAvailable) left"))
                        .font(.caption2.weight(.semibold)).opacity(0.85)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(chipForeground(booked: booked, full: full))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(booked ? AnyShapeStyle(KXColor.livingAccent.opacity(0.14)) : AnyShapeStyle(KXColor.livingSurface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(booked ? KXColor.livingAccent : (full ? Color.secondary.opacity(0.25) : KXColor.livingAccent.opacity(0.45)),
                            lineWidth: 1.2)
            )
        }
        .buttonStyle(KXPressableStyle())
        .disabled(busy || (!isOwner && full && !booked))
        .onLongPressGesture(minimumDuration: 0.4) {
            if isOwner { pendingDeleteSlot = slot }
        }
    }

    private func chipForeground(booked: Bool, full: Bool) -> Color {
        if booked { return KXColor.livingAccent }
        if full { return .secondary }
        return KXColor.livingInk
    }

    // MARK: - Data

    private var dayKeys: [String] {
        var seen = Set<String>(); var ordered: [String] = []
        for s in slots {
            guard let d = s.startDate else { continue }
            let k = Self.dayKeyFormatter.string(from: d)
            if !seen.contains(k) { seen.insert(k); ordered.append(k) }
        }
        return ordered
    }

    private var slotsForSelectedDay: [KaiXBookingSlotDTO] {
        guard let key = selectedDayKey ?? dayKeys.first else { return [] }
        return slots.filter { s in
            guard let d = s.startDate else { return false }
            return Self.dayKeyFormatter.string(from: d) == key
        }
    }

    private func firstDate(forDay key: String) -> Date? {
        slots.first { s in
            guard let d = s.startDate else { return false }
            return Self.dayKeyFormatter.string(from: d) == key
        }?.startDate
    }

    private func reload() async {
        do {
            let resp = try await KaiXAPIClient.shared.listingSlots(listingId)
            await MainActor.run {
                slots = resp.items.sorted { ($0.startAt ?? "") < ($1.startAt ?? "") }
                isOwner = resp.isOwner ?? false
                if selectedDayKey == nil { selectedDayKey = dayKeys.first }
                loaded = true
            }
        } catch {
            await MainActor.run { loaded = true }   // hide section silently on failure
        }
    }

    private func addSlots(_ inputs: [KaiXAPIClient.SlotInput]) async {
        do {
            _ = try await KaiXAPIClient.shared.createListingSlots(listingId, slots: inputs)
            await reload()
            await MainActor.run {
                if selectedDayKey == nil { selectedDayKey = dayKeys.first }
                toast = KXListingCopy.pickText(language, "时段已添加", "枠を追加しました", "Slot added")
            }
        } catch {
            await MainActor.run { toast = KXListingCopy.pickText(language, "添加失败，请重试", "追加に失敗しました", "Failed to add") }
        }
    }

    private func deleteSlot(_ slot: KaiXBookingSlotDTO) async {
        do {
            try await KaiXAPIClient.shared.deleteListingSlot(listingId: listingId, slotId: slot.id)
            await reload()
            await MainActor.run {
                if let key = selectedDayKey, !dayKeys.contains(key) { selectedDayKey = dayKeys.first }
                toast = KXListingCopy.pickText(language, "时段已删除", "枠を削除しました", "Slot removed")
            }
        } catch {
            await MainActor.run { toast = KXListingCopy.pickText(language, "删除失败，请重试", "削除に失敗しました", "Failed to remove") }
        }
    }

    private func cancelMyBooking(_ slot: KaiXBookingSlotDTO) async {
        do {
            let mine = try await KaiXAPIClient.shared.myReservations()
            guard let booking = mine.first(where: { $0.slotId == slot.id && ($0.status ?? "confirmed") == "confirmed" }) else {
                await MainActor.run { toast = KXListingCopy.pickText(language, "未找到该预约", "予約が見つかりません", "Reservation not found") }
                return
            }
            try await KaiXAPIClient.shared.cancelReservation(booking.id)
            await reload()
            await MainActor.run { toast = KXListingCopy.pickText(language, "已取消预约", "予約をキャンセルしました", "Reservation cancelled") }
        } catch {
            await MainActor.run { toast = KXListingCopy.pickText(language, "取消失败，请重试", "キャンセルに失敗しました", "Failed to cancel") }
        }
    }

    private func book(_ slot: KaiXBookingSlotDTO) async {
        guard inFlightSlotId == nil else { return }
        await MainActor.run { inFlightSlotId = slot.id; toast = nil }
        do {
            try await KaiXAPIClient.shared.bookSlot(listingId: listingId, slotId: slot.id)
            let resp = try? await KaiXAPIClient.shared.listingSlots(listingId)
            await MainActor.run {
                if let resp { slots = resp.items.sorted { ($0.startAt ?? "") < ($1.startAt ?? "") } }
                inFlightSlotId = nil
                bookedTick += 1
                toast = KXListingCopy.pickText(language, "预约成功，已加入「我的预约」", "予約が完了しました", "Reserved — see My reservations")
            }
        } catch {
            await MainActor.run {
                inFlightSlotId = nil
                toast = bookingErrorText(error)
            }
        }
    }

    private func bookingErrorText(_ error: Error) -> String {
        let msg = (error as NSError).localizedDescription
        if msg.contains("登录") || msg.contains("401") || msg.lowercased().contains("unauthor") {
            return KXListingCopy.pickText(language, "请先登录后再预约", "ログインしてください", "Please sign in to book")
        }
        if msg.contains("约满") { return KXListingCopy.pickText(language, "该时段已约满", "満席です", "This slot is full") }
        if msg.contains("已预约") { return KXListingCopy.pickText(language, "你已预约该时段", "予約済みです", "Already booked") }
        return KXListingCopy.pickText(language, "预约失败，请稍后再试", "予約に失敗しました", "Booking failed, try again")
    }

    // MARK: - Formatting

    private var titleText: String {
        switch listingType {
        case "housing", "rental", "roommate":
            return KXListingCopy.pickText(language, "看房预约", "内見予約", "Book a viewing")
        case "local_service", "service", "discount", "event":
            return KXListingCopy.pickText(language, "预约到店", "来店予約", "Reserve a visit")
        default:
            return KXListingCopy.pickText(language, "预约时段", "予約枠", "Reservation")
        }
    }

    private func localizedFormatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        switch language {
        case .ja: f.locale = Locale(identifier: "ja_JP")
        case .en: f.locale = Locale(identifier: "en_US")
        default: f.locale = Locale(identifier: "zh_CN")
        }
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private func weekdayText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return localizedFormatter("EEE").string(from: date)
    }

    private func dayNumberText(_ date: Date?) -> String {
        guard let date else { return "" }
        return localizedFormatter("Md").string(from: date)
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "" }
        return localizedFormatter("Hm").string(from: date)
    }
}

/// Owner-side sheet to publish one bookable slot (date + time + capacity). No money.
struct AddBookingSlotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    /// (ISO8601 start, capacity, note)
    let onSave: (String, Int, String) -> Void

    @State private var date = Calendar.current.date(byAdding: .hour, value: 24, to: Date()) ?? Date()
    @State private var capacity = 1
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(KXListingCopy.pickText(language, "时间", "日時", "Time"),
                               selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Stepper(value: $capacity, in: 1...20) {
                        Text(KXListingCopy.pickText(language, "可约人数：\(capacity)", "受付人数：\(capacity)", "Capacity: \(capacity)"))
                    }
                    TextField(KXListingCopy.pickText(language, "备注（可选，如「每场30分钟」）", "メモ（任意）", "Note (optional)"),
                              text: $note)
                } footer: {
                    Text(KXListingCopy.pickText(language,
                                               "对方可在线预约该时段，不涉及任何费用。",
                                               "相手はこの枠をオンラインで予約できます（無料）。",
                                               "People can reserve this slot online — no payment involved."))
                }
            }
            .navigationTitle(KXListingCopy.pickText(language, "添加预约时段", "予約枠を追加", "Add a slot"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(KXListingCopy.pickText(language, "添加", "追加", "Add")) {
                        let f = ISO8601DateFormatter()
                        f.formatOptions = [.withInternetDateTime]
                        onSave(f.string(from: date), capacity, note.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CityListingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState
    let listingId: String
    let currentUser: UserEntity
    /// Matches the source card's namespace for the zoom-in transition (router
    /// path only; nil → default push).
    var zoomNamespace: Namespace.ID? = nil

    @State private var listing: KaiXCityListingDTO?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var isBusy = false
    @State private var intakeOpen = false
    @State private var inquiryReceipt: ListingInquiryReceipt?
    @State private var similarItems: [KaiXCityListingDTO] = []
    @State private var sellerOtherItems: [KaiXCityListingDTO] = []

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Group {
                if isLoading {
                    LoadingView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load() } }
                } else if let listing {
                    detailContent(listing)
                } else {
                    EmptyStateView(title: "信息不存在", subtitle: "它可能已下架或正在审核。", systemImage: "tray")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let listing, !isLoading, errorMessage == nil {
                detailStickyBar(listing)
            }
        }
        .kxPageBackground()
        .background(KXColor.livingBackground)
        .kxListingZoomDestination("listing-\(listingId)", zoomNamespace)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: listingId) { await load() }
        .sheet(isPresented: $intakeOpen) {
            Group {
                if let listing {
                    ListingIntakeSheet(listingTitle: KXListingCopy.displayTitle(listing), listingType: listing.type, listingCategory: listing.category, submitting: isBusy) { message, details in
                        Task { await submitInquiry(message: message, details: details) }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $inquiryReceipt) { receipt in
            ListingInquirySuccessSheet(
                receipt: receipt,
                onOpenRecords: {
                    inquiryReceipt = nil
                    // Two things were broken here:
                    // 1. Switch the *visible* tab via chrome.select (which keeps
                    //    router.activeTab in sync). router.setActiveTab alone left the
                    //    visible tab on Search while activeTab moved to Profile, so the
                    //    button looked dead AND later router.open calls went to the
                    //    hidden Profile stack (Discover entries stopped responding).
                    // 2. Defer the tab switch + push until AFTER the sheet finishes
                    //    dismissing. Doing it in the same runloop tick as the dismiss
                    //    makes SwiftUI drop the navigation — the actual reason the
                    //    buttons did nothing.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        chrome.select(.profile)
                        router.popToRoot(.profile)
                        router.open(.myInquiries, in: .profile)
                    }
                },
                onOpenConversation: {
                    guard !receipt.conversationId.isEmpty else { return }
                    inquiryReceipt = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        chrome.select(.messages)
                        router.open(.conversation(conversationId: receipt.conversationId), in: .messages)
                    }
                },
                onClose: {
                    inquiryReceipt = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Airbnb-style sticky bottom bar: price on the left, primary CTA on the
    /// right, always reachable. Translucent glass so content scrolls under it.
    private func detailStickyBar(_ listing: KaiXCityListingDTO) -> some View {
        let ownListing = isOwnListing(listing)
        let spec = ListingIntakeSpec.forType(listing.type, category: listing.category)
        let isWork = listing.type == "job" || listing.type == "hiring"
        let ratingCount = listing.rating_count ?? listing.ratingCount ?? 0
        let ratingAvg = listing.rating_avg ?? listing.ratingAvg ?? 0
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(KXListingCopy.priceLabel(listing, language))
                    .font(.title3.weight(.black))
                    .foregroundStyle(isWork ? KXColor.livingAccent : KXColor.livingWarm)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if ratingCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 10, weight: .black)).foregroundStyle(.orange)
                        Text(String(format: "%.1f", ratingAvg)).font(.caption2.weight(.black)).foregroundStyle(KXColor.livingInk)
                        Text("(\(ratingCount))").font(.caption2.weight(.semibold)).foregroundStyle(KXColor.livingMuted)
                    }
                } else {
                    Text(KXListingCopy.title(for: listing.type, language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KXColor.livingMuted)
                }
            }
            Spacer(minLength: 8)
            Button {
                if ownListing { router.open(.editCityListing(listingId: listing.id)) }
                else { intakeOpen = true }
            } label: {
                Text(ownListing ? KXListingCopy.pickText(language, "编辑发布", "投稿を編集", "Edit listing") : ListingIntakeLocalizer.text(spec.title, language))
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 50)
                    .background(KXColor.livingAccent, in: Capsule())
                    .shadow(color: KXColor.livingAccent.opacity(0.32), radius: 10, y: 4)
            }
            .buttonStyle(KXPressableStyle(scale: 0.96))
            .disabled(isBusy)
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(KXColor.livingSurface.opacity(0.5)))
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(KXColor.livingInk.opacity(0.08)).frame(height: 0.5)
        }
    }

    private var detailHeader: some View {
        HStack(spacing: KXSpacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(KXListingCopy.title(for: listing?.type ?? "secondhand", language))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(KXColor.livingInk)
                Text(KXListingCopy.pickText(language, "详情与联系", "詳細・連絡", "Details & contact"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KXColor.livingMuted)
            }
            Spacer()
            Button { Task { await favorite() } } label: {
                Image(systemName: listing?.favorited == true ? "heart.fill" : "heart")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(listing?.favorited == true ? KXColor.heat : .primary)
                    .symbolEffect(.bounce, value: listing?.favorited)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(KXColor.livingBackground.opacity(0.94))
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    /// 商家与服务详情：团购套餐(展示「暂不支持线上购买」) + 菜单 + 预约·到店。
    @ViewBuilder
    private func merchantDetailSections(_ listing: KaiXCityListingDTO) -> some View {
        if listing.type == "local_service", KXListingCopy.serviceVertical(for: listing) == .foodRestaurant {
            let packages = listing.groupPackages
            let dishes = listing.menuDishes
            let openHours = KXListingCopy.attr(listing, "open_hours") ?? ""
            let reservationNote = KXListingCopy.attr(listing, "reservation_note") ?? ""
            let storePhone = KXListingCopy.attr(listing, "store_phone") ?? ""
            let reservationRequired = listing.attributes?["reservation_required"]?.boolValue ?? false
            let hasReservation = reservationRequired || !openHours.isEmpty || !reservationNote.isEmpty || !storePhone.isEmpty

            if !packages.isEmpty {
                KXListingSection(title: KXListingCopy.pickText(language, "团购套餐", "セット・クーポン", "Packages"), icon: "ticket") {
                    VStack(spacing: 10) {
                        HStack {
                            Spacer()
                            Text(KXListingCopy.pickText(language, "暂不支持线上购买", "オンライン購入は未対応", "Online purchase unavailable"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(KXColor.livingSoft, in: Capsule())
                        }
                        ForEach(packages) { pkg in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(pkg.title ?? "").font(.subheadline.weight(.black)).foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    if let price = pkg.price, !price.isEmpty {
                                        Text(price).font(.subheadline.weight(.black)).foregroundStyle(KXColor.livingWarm)
                                    }
                                    if let orig = pkg.original_price, !orig.isEmpty {
                                        Text(orig).font(.caption.weight(.semibold)).foregroundStyle(.secondary).strikethrough()
                                    }
                                }
                                if let inc = pkg.includes, !inc.isEmpty {
                                    Text(inc).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                if let note = pkg.note, !note.isEmpty {
                                    Text(note).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(KXColor.livingSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }

            if !dishes.isEmpty {
                KXListingSection(title: KXListingCopy.pickText(language, "菜单", "メニュー", "Menu"), icon: "fork.knife") {
                    VStack(spacing: 0) {
                        ForEach(Array(dishes.enumerated()), id: \.offset) { idx, dish in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dish.name ?? "").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                                    if let d = dish.desc, !d.isEmpty {
                                        Text(d).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                if let price = dish.price, !price.isEmpty {
                                    Text(price).font(.subheadline.weight(.black)).foregroundStyle(KXColor.livingWarm)
                                }
                            }
                            .padding(.vertical, 9)
                            if idx < dishes.count - 1 { Divider().opacity(0.5) }
                        }
                    }
                }
            }

            if hasReservation {
                KXListingSection(title: KXListingCopy.pickText(language, "预约 · 到店", "予約・来店", "Booking & visit"), icon: "calendar.badge.clock") {
                    VStack(alignment: .leading, spacing: 6) {
                        if !openHours.isEmpty {
                            Label("\(KXListingCopy.pickText(language, "营业时间", "営業時間", "Hours")) · \(openHours)", systemImage: "clock")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if reservationRequired {
                            Label(KXListingCopy.pickText(language, "本店采用预约制，建议先预约再到店。", "予約制です。来店前の予約をおすすめします。", "Reservation is recommended before visiting."), systemImage: "checkmark.seal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if !reservationNote.isEmpty { Text(reservationNote).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        if !storePhone.isEmpty {
                            Label("\(KXListingCopy.pickText(language, "到店电话", "店舗電話", "Phone")) · \(storePhone)", systemImage: "phone")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func detailContent(_ listing: KaiXCityListingDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageStrip(listing)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(KXListingCopy.priceLabel(listing, language))
                                .font(.title2.weight(.black))
                                .foregroundStyle(listing.type == "job" || listing.type == "hiring" ? KXColor.livingAccent : KXColor.livingWarm)
                            Text(KXListingCopy.displayTitle(listing))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(KXColor.livingInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        KXListingBadge(title: KXListingCopy.statusLabel(listing.status, type: listing.type, language), tint: KXListingCopy.statusColor(listing.status))
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(KXListingCopy.badges(for: listing, language), id: \.self) { badge in
                            KXListingBadge(title: badge, tint: KXColor.livingAccent)
                        }
                    }
                }
                .padding(KXSpacing.lg)
                .kxLivingSurface(radius: 24, elevated: true)

                KXListingAttributeSection(listing: listing)

                if let description = listing.description, !description.isEmpty {
                    KXListingSection(title: KXListingCopy.pickText(language, "描述", "説明", "Description"), icon: "text.alignleft") {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                merchantDetailSections(listing)

                ListingBookingSection(listingId: listing.id, listingType: listing.type)

                KXListingSection(title: KXListingCopy.pickText(language, "发布者", "投稿者", "Poster"), icon: "person.crop.circle") {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(KXColor.livingAccentSoft)
                            .frame(width: 44, height: 44)
                            .overlay(Text((listing.seller?.display_name ?? "M").prefix(1)).font(.headline.weight(.bold)).foregroundStyle(KXColor.livingAccent))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(listing.seller?.display_name ?? KXListingCopy.pickText(language, "Machi 用户", "Machi ユーザー", "Machi user"))
                                .font(.subheadline.weight(.bold))
                            Text(KXListingCopy.verificationLabel(listing.verification_status, language))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                ListingReviewsSectionView(listing: listing, currentUser: currentUser)

                if !sellerOtherItems.isEmpty {
                    listingRail(title: KXListingCopy.pickText(language, "TA 的其他发布", "このユーザーの他の投稿", "More from this poster"), icon: "person.crop.rectangle.stack", items: sellerOtherItems)
                }
                if !similarItems.isEmpty {
                    listingRail(title: KXListingCopy.pickText(language, "相似推荐", "関連おすすめ", "Similar listings"), icon: "sparkles.rectangle.stack", items: similarItems)
                }

                KXListingSection(title: KXListingCopy.pickText(language, "安全提醒", "安全の注意", "Safety tips"), icon: "shield.checkered") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(KXListingCopy.safetyTips(for: listing.type, language), id: \.self) { tip in
                            Label(tip, systemImage: "checkmark.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let actionMessage {
                    Text(actionMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KXColor.livingAccent)
                        .padding(.horizontal, 2)
                }

                contactPanel(listing)
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private func imageStrip(_ listing: KaiXCityListingDTO) -> some View {
        // Drop server-generated placeholder media so the gallery shows a clean
        // native placeholder instead of the "Generated default cover" card.
        let realMedia = (listing.media ?? []).filter { !KaiXCityListingDTO.isGeneratedCover($0.url) }
        let mediaItems: [KaiXListingMediaDTO]
        if !realMedia.isEmpty {
            mediaItems = realMedia
        } else if let cover = listing.primaryCoverMedia, !KaiXCityListingDTO.isGeneratedCover(cover.url) {
            mediaItems = [cover]
        } else {
            mediaItems = []
        }
        return Group {
            if mediaItems.isEmpty {
                ListingMediaPlaceholder(type: listing.type)
            } else {
                TabView {
                    ForEach(Array(mediaItems.enumerated()), id: \.offset) { index, media in
                        ListingMediaPage(media: media, index: index, total: mediaItems.count)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: mediaItems.count > 1 ? .automatic : .never))
            }
        }
        .aspectRatio(16.0 / 10.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.07), radius: 16, y: 7)
    }

    private func contactPanel(_ listing: KaiXCityListingDTO) -> some View {
        let spec = ListingIntakeSpec.forType(listing.type, category: listing.category)
        let ownListing = isOwnListing(listing)
        return KXListingSection(title: KXListingCopy.pickText(language, "申请/预约/咨询", "応募・予約・問い合わせ", "Apply, book or inquire"), icon: "tray.full") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: ownListing ? "person.crop.circle.badge.checkmark" : "doc.badge.clock")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ownListing ? .secondary : KXColor.livingAccent)
                        .frame(width: 38, height: 38)
                        .background(ownListing ? Color.secondary.opacity(0.12) : KXColor.livingAccentSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ownListing
                             ? KXListingCopy.pickText(language, "这是你的发布", "これはあなたの投稿です", "This is your listing")
                             : KXListingCopy.pickText(language, "提交申请、预约或咨询", "応募・予約・問い合わせを送信", "Submit an application, booking or inquiry"))
                            .font(.subheadline.weight(.bold))
                        Text(ownListing
                             ? KXListingCopy.pickText(language, "自己的发布不能发起咨询，可以在我的发布中管理状态。", "自分の投稿には問い合わせできません。投稿管理から状態を変更できます。", "You cannot inquire about your own listing. Manage it from My listings.")
                             : KXListingCopy.pickText(language, "提交后会生成正式记录，私信只用于后续补充沟通。", "送信後は正式な記録が作成され、メッセージは補足連絡用です。", "Submitting creates an official record; messages are only for follow-up."))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if ownListing {
                    // 自己的发布：联系按钮换成直达编辑，管理动作不再是死路。
                    Button {
                        router.open(.editCityListing(listingId: listing.id))
                    } label: {
                        Label(KXListingCopy.pickText(language, "编辑这条发布", "この投稿を編集", "Edit this listing"), systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(KXColor.livingAccent, in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                } else {
                    Button { intakeOpen = true } label: {
                        Label(isBusy ? KXListingCopy.pickText(language, "处理中", "処理中", "Processing") : ListingIntakeLocalizer.text(spec.title, language), systemImage: "doc.badge.plus")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(KXColor.livingAccent, in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }

                if listing.type == "secondhand", !ownListing {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(quickInquiries(for: listing)) { item in
                            Button {
                                Task { await submitInquiry(message: item.message, details: item.details) }
                            } label: {
                                Text(item.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(KXColor.livingAccent)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(KXColor.livingAccentSoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button { Task { await report() } } label: {
                        Label(KXListingCopy.pickText(language, "举报异常", "問題を報告", "Report issue"), systemImage: "flag")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    Text(KXListingCopy.pickText(language, "不要提前转账，建议公共场所交易。", "前払いは避け、公共の場所での取引をおすすめします。", "Avoid paying in advance; meet in public when trading."))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func isOwnListing(_ listing: KaiXCityListingDTO) -> Bool {
        let sellerId = listing.seller_user_id ?? listing.sellerUserId ?? ""
        return listing.can_manage == true || listing.canManage == true || sellerId == currentUser.id
    }

    private func quickInquiries(for listing: KaiXCityListingDTO) -> [ListingQuickInquiry] {
        let title = KXListingCopy.displayTitle(listing)
        let location = listing.location_text ?? listing.locationText ?? ""
        return [
            ListingQuickInquiry(
                id: "available",
                title: KXListingCopy.pickText(language, "还在吗？", "まだありますか？", "Still available?"),
                message: KXListingCopy.pickText(
                    language,
                    "你好，我想确认「\(title)」还可以交易吗？",
                    "こんにちは。「\(title)」はまだ取引できますか？",
                    "Hi, is \"\(title)\" still available?"
                ),
                details: [["label": KXListingCopy.pickText(language, "咨询内容", "内容", "Question"), "value": KXListingCopy.pickText(language, "确认是否仍可交易", "まだ取引可能か確認", "Check availability")]]
            ),
            ListingQuickInquiry(
                id: "meetup",
                title: KXListingCopy.pickText(language, "约自取", "受け取り相談", "Meet up"),
                message: KXListingCopy.pickText(
                    language,
                    "你好，我想预约自取「\(title)」，方便的话请告诉我可交易时间。",
                    "こんにちは。「\(title)」の受け取りを相談したいです。可能な日時を教えてください。",
                    "Hi, I would like to arrange pickup for \"\(title)\". Please let me know a good time."
                ),
                details: [
                    ["label": KXListingCopy.pickText(language, "希望交易方式", "希望取引方法", "Preferred handoff"), "value": KXListingCopy.pickText(language, "自取 / 面交", "受け取り / 対面", "Pickup / meet up")],
                    ["label": KXListingCopy.pickText(language, "希望地点", "希望場所", "Preferred location"), "value": location]
                ]
            ),
            ListingQuickInquiry(
                id: "condition",
                title: KXListingCopy.pickText(language, "问瑕疵", "状態確認", "Condition"),
                message: KXListingCopy.pickText(
                    language,
                    "你好，我想了解「\(title)」的使用痕迹、配件和是否有瑕疵。",
                    "こんにちは。「\(title)」の使用感、付属品、傷などを確認したいです。",
                    "Hi, I would like to know the condition, accessories, and any defects for \"\(title)\"."
                ),
                details: [["label": KXListingCopy.pickText(language, "咨询内容", "内容", "Question"), "value": KXListingCopy.pickText(language, "确认状态、配件和瑕疵", "状態・付属品・傷の確認", "Condition, accessories, and defects")]]
            ),
            ListingQuickInquiry(
                id: "price",
                title: KXListingCopy.pickText(language, "可议价吗？", "価格相談", "Negotiate"),
                message: KXListingCopy.pickText(
                    language,
                    "你好，我对「\(title)」感兴趣，想问一下价格是否可以商量。",
                    "こんにちは。「\(title)」に興味があります。価格相談は可能ですか？",
                    "Hi, I am interested in \"\(title)\". Is the price negotiable?"
                ),
                details: [["label": KXListingCopy.pickText(language, "咨询内容", "内容", "Question"), "value": KXListingCopy.pickText(language, "价格是否可商量", "価格相談の可否", "Whether the price is negotiable")]]
            ),
        ]
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await KaiXAPIClient.shared.cityListing(listingId)
            listing = loaded
            isLoading = false
            await loadRecommendations(for: loaded)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// 相似推荐 + TA 的其他发布。推荐栏失败不影响详情主体。
    private func loadRecommendations(for loaded: KaiXCityListingDTO) async {
        let sellerId = loaded.seller_user_id ?? loaded.sellerUserId ?? ""
        let viewerId = currentUser.id
        async let similarTask = try? KaiXAPIClient.shared.similarListings(loaded.id)
        async let sellerTask: [KaiXCityListingDTO]? = sellerId.isEmpty || sellerId == viewerId
            ? nil
            : try? KaiXAPIClient.shared.listingsPage(
                type: loaded.type,
                sellerId: sellerId,
                excludeListingId: loaded.id,
                limit: 8
            ).items
        similarItems = (await similarTask) ?? []
        sellerOtherItems = (await sellerTask) ?? []
    }

    private func listingRail(title: String, icon: String, items: [KaiXCityListingDTO]) -> some View {
        KXListingSection(title: title, icon: icon) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        KXSecondhandListingCard(listing: item, width: 150) {
                            router.open(.cityListingDetail(listingId: item.id))
                        }
                    }
                }
            }
        }
    }

    private func favorite() async {
        guard let listing else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await KaiXAPIClient.shared.favoriteListing(listing.id, on: !(listing.favorited ?? false))
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func submitInquiry(message: String, details: [[String: String]]) async {
        guard let listing else { return }
        guard !isOwnListing(listing) else {
            actionMessage = KXListingCopy.pickText(language, "不能咨询自己发布的信息。", "自分の投稿には問い合わせできません。", "You cannot inquire about your own listing.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let spec = ListingIntakeSpec.forType(listing.type, category: listing.category)
            let actionWord = ListingIntakeLocalizer.text(spec.actionWord, language)
            let fallback = KXListingCopy.pickText(
                language,
                "我想\(actionWord)：\(KXListingCopy.displayTitle(listing))",
                "\(actionWord)：\(KXListingCopy.displayTitle(listing))",
                "\(actionWord): \(KXListingCopy.displayTitle(listing))"
            )
            let locale = language == .zh ? "zh-Hans" : language.rawValue
            let receiptDTO = try await KaiXAPIClient.shared.contactListing(
                listing.id,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : message,
                details: details,
                locale: locale
            )
            intakeOpen = false
            actionMessage = receiptDTO.resolvedSuccessTitle
            try? await Task.sleep(for: .milliseconds(220))
            inquiryReceipt = ListingInquiryReceipt(
                listingTitle: KXListingCopy.displayTitle(listing),
                listingType: listing.type,
                receipt: receiptDTO
            )
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func report() async {
        guard let listing else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await KaiXAPIClient.shared.reportListing(listing.id, reason: "suspicious", note: "App 用户举报")
            actionMessage = KXListingCopy.pickText(language, "举报已提交，Machi 会进行审核。", "通報を送信しました。Machi が確認します。", "Report submitted. Machi will review it.")
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

private struct ListingQuickInquiry: Identifiable {
    let id: String
    let title: String
    let message: String
    let details: [[String: String]]
}

private struct ListingInquiryReceipt: Identifiable {
    let id: String
    let listingTitle: String
    let listingType: String
    let inquiryType: String
    let status: String
    let successTitle: String
    let conversationId: String
    let details: [[String: String]]
    let submittedAt: Date

    init(listingTitle: String, listingType: String, receipt: KaiXListingInquiryReceiptDTO) {
        self.id = receipt.resolvedInquiryId.isEmpty ? UUID().uuidString : receipt.resolvedInquiryId
        self.listingTitle = listingTitle
        self.listingType = listingType
        self.inquiryType = receipt.type ?? "general_consult"
        self.status = receipt.status ?? "submitted"
        self.successTitle = receipt.resolvedSuccessTitle
        self.conversationId = receipt.resolvedConversationId
        self.details = receipt.details ?? []
        self.submittedAt = Date()
    }

    func recordLabel(_ language: AppLanguage) -> String {
        if inquiryType == "job_apply" || inquiryType == "rental_application" {
            return KXListingCopy.pickText(language, "查看我的申请", "自分の応募を見る", "View my applications")
        }
        if inquiryType.hasSuffix("_booking") || inquiryType == "rental_viewing" {
            return KXListingCopy.pickText(language, "查看我的预约", "自分の予約を見る", "View my bookings")
        }
        return KXListingCopy.pickText(language, "查看我的咨询", "自分の問い合わせを見る", "View my inquiries")
    }
}

private struct ListingInquirySuccessSheet: View {
    @Environment(\.appLanguage) private var language
    let receipt: ListingInquiryReceipt
    let onOpenRecords: () -> Void
    let onOpenConversation: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title.weight(.black))
                        .foregroundStyle(KXColor.accent)
                        .frame(width: 52, height: 52)
                        .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.successTitle)
                            .font(.title3.weight(.black))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(KXListingCopy.pickText(
                            language,
                            "记录已进入工作台，私信只作为后续沟通补充。",
                            "記録はワークベンチに保存されました。メッセージは補足連絡用です。",
                            "The record is saved to your workbench; messages are only for follow-up."
                        ))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

            VStack(alignment: .leading, spacing: 10) {
                receiptLine(KXListingCopy.pickText(language, "信息", "投稿", "Listing"), receipt.listingTitle)
                receiptLine(KXListingCopy.pickText(language, "类型", "種類", "Type"), Self.typeLabel(receipt.inquiryType, language))
                receiptLine(KXListingCopy.pickText(language, "状态", "ステータス", "Status"), Self.statusLabel(receipt.status, language))
                receiptLine(KXListingCopy.pickText(language, "时间", "日時", "Time"), Self.timeLabel(receipt.submittedAt, language))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.softBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !receipt.details.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(KXListingCopy.pickText(language, "提交摘要", "送信内容", "Submission summary"))
                        .font(.subheadline.weight(.black))
                    ForEach(Array(receipt.details.prefix(8).enumerated()), id: \.offset) { _, item in
                        let label = ListingIntakeLocalizer.text(item["label"] ?? "", language)
                        let value = item["value"] ?? ""
                        if !label.isEmpty || !value.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(label)
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 86, alignment: .leading)
                                Text(value)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(KXColor.separator.opacity(0.5), lineWidth: 0.7)
                }
            }

                VStack(spacing: 10) {
                    Button(action: onOpenRecords) {
                        Label(receipt.recordLabel(language), systemImage: "tray.full")
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(KXColor.accent, in: Capsule())
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)

                    Button(action: onOpenConversation) {
                        Label(
                            KXListingCopy.pickText(language, "继续私信补充", "補足メッセージを送る", "Continue follow-up message"),
                            systemImage: "bubble.left.and.bubble.right"
                        )
                            .font(.subheadline.weight(.black))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(KXColor.softBackground, in: Capsule())
                            .foregroundStyle(receipt.conversationId.isEmpty ? .secondary : KXColor.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(receipt.conversationId.isEmpty)

                    Button(action: onClose) {
                        Text(KXListingCopy.pickText(language, "返回详情", "詳細へ戻る", "Back to detail"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(KaiXTheme.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kxPageBackground()
    }

    private func receiptLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func typeLabel(_ type: String, _ language: AppLanguage) -> String {
        switch type {
        case "secondhand_trade_request", "secondhand_consult": KXListingCopy.pickText(language, "二手交易咨询", "フリマ取引相談", "Marketplace inquiry")
        case "rental_viewing": KXListingCopy.pickText(language, "看房预约", "内見予約", "Viewing request")
        case "rental_application": KXListingCopy.pickText(language, "租房申请", "賃貸申込", "Rental application")
        case "job_apply": KXListingCopy.pickText(language, "职位申请", "求人応募", "Job application")
        case "restaurant_booking": KXListingCopy.pickText(language, "餐饮订座", "飲食予約", "Restaurant booking")
        case "stay_booking": KXListingCopy.pickText(language, "住宿预订", "宿泊予約", "Stay booking")
        case "travel_ticket_booking": KXListingCopy.pickText(language, "旅行票务", "旅行・チケット予約", "Travel/ticket booking")
        case "transfer_booking": KXListingCopy.pickText(language, "接送预约", "送迎予約", "Transfer booking")
        case "paperwork_booking": KXListingCopy.pickText(language, "手续协助", "手続きサポート", "Paperwork help")
        case "moving_cleaning_booking": KXListingCopy.pickText(language, "搬家清洁", "引越し・清掃", "Moving/cleaning")
        case "life_setup_booking": KXListingCopy.pickText(language, "生活开通", "生活セットアップ", "Life setup")
        case "beauty_health_booking": KXListingCopy.pickText(language, "美容健康", "美容・健康", "Beauty/health")
        case "pet_family_booking": KXListingCopy.pickText(language, "宠物家庭", "ペット・家庭", "Pet/family")
        case "discount_claim": KXListingCopy.pickText(language, "优惠咨询", "特典問い合わせ", "Deal inquiry")
        default: KXListingCopy.pickText(language, "城市咨询", "街の問い合わせ", "City inquiry")
        }
    }

    private static func statusLabel(_ status: String, _ language: AppLanguage) -> String {
        switch status {
        case "submitted": KXListingCopy.pickText(language, "已提交", "送信済み", "Submitted")
        case "reviewing": KXListingCopy.pickText(language, "处理中", "対応中", "Reviewing")
        case "contacted": KXListingCopy.pickText(language, "已联系", "連絡済み", "Contacted")
        case "confirmed": KXListingCopy.pickText(language, "已确认", "確定済み", "Confirmed")
        case "rescheduled": KXListingCopy.pickText(language, "待改期", "日程調整中", "Rescheduling")
        case "rejected": KXListingCopy.pickText(language, "已拒绝", "却下", "Rejected")
        case "withdrawn": KXListingCopy.pickText(language, "已撤回", "取り下げ", "Withdrawn")
        case "completed": KXListingCopy.pickText(language, "已完成", "完了", "Completed")
        case "closed": KXListingCopy.pickText(language, "已关闭", "終了", "Closed")
        default: KXListingCopy.pickText(language, "新提交", "新規送信", "New")
        }
    }

    private static func timeLabel(_ date: Date, _ language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .ja ? "ja_JP" : language == .en ? "en_US" : "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

enum ListingIntakeLocalizer {
    static func text(_ value: String, _ language: AppLanguage) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return value }
        if let entry = table[normalized] {
            return KXListingCopy.pickText(language, normalized, entry.ja, entry.en)
        }
        return KXListingCopy.attributeLabel(normalized, language)
    }

    static func requiredMessage(_ fieldLabel: String, _ language: AppLanguage) -> String {
        let label = text(fieldLabel, language)
        return KXListingCopy.pickText(language, "请填写「\(label)」", "「\(label)」を入力してください", "Please fill in \"\(label)\"")
    }

    private static let table: [String: (ja: String, en: String)] = [
        "预订住宿": ("宿泊を予約", "Book stay"),
        "在线订座": ("席を予約", "Reserve table"),
        "订座": ("席を予約", "reserve a table"),
        "预订门票": ("チケットを予約", "Book tickets"),
        "预订行程": ("ツアーを予約", "Book tour"),
        "预订": ("予約", "Book"),
        "预约接送": ("送迎を予約", "Book transfer"),
        "预约手续协助": ("手続きサポートを予約", "Book paperwork help"),
        "预约搬家清洁": ("引越し・清掃を予約", "Book moving/cleaning"),
        "预约生活开通": ("生活セットアップを予約", "Book life setup"),
        "预约服务": ("サービスを予約", "Book service"),
        "预约美容健康": ("美容・健康を予約", "book beauty/health"),
        "预约看房": ("内見を予約", "Request viewing"),
        "申请职位": ("求人に応募", "Apply for job"),
        "申请": ("応募", "Apply"),
        "联系商家": ("店舗に問い合わせ", "Contact merchant"),
        "报名 / 咨询": ("申込 / 問い合わせ", "Join / inquire"),
        "联系卖家": ("出品者に問い合わせ", "Contact seller"),
        "咨询": ("問い合わせ", "inquire"),
        "补充说明（选填）": ("補足（任意）", "Additional details (optional)"),
        "提交后会生成正式记录，私信只用于后续补充沟通。Machi 不代收交易款、押金、保证金或第三方服务款，请勿提前转账。": ("送信後は正式な記録が作成され、メッセージは補足連絡用です。Machi は代金・保証金・第三者サービス費を預かりません。前払いは避けてください。", "Submitting creates an official record; messages are only for follow-up. Machi does not hold trade payments, deposits, guarantees, or third-party service fees. Avoid paying in advance."),
        "提交中": ("送信中", "Submitting"),
        "关闭": ("閉じる", "Close"),
        "请选择": ("選択してください", "Select"),
        "希望看房日期": ("希望内見日", "Preferred viewing date"),
        "希望时段": ("希望時間帯", "Preferred time"),
        "当前情况": ("現在の状況", "Current situation"),
        "入住人数": ("宿泊・入居人数", "People"),
        "预算": ("予算", "Budget"),
        "联系方式": ("連絡先", "Contact"),
        "姓名": ("氏名", "Name"),
        "签证状态": ("在留資格", "Visa status"),
        "日语水平": ("日本語レベル", "Japanese level"),
        "可工作时间": ("勤務可能時間", "Availability"),
        "最快入职时间": ("最短開始日", "Earliest start"),
        "自我介绍": ("自己紹介", "Self introduction"),
        "咨询意向": ("相談内容", "Intent"),
        "希望交易地点": ("希望受け渡し場所", "Preferred meetup"),
        "可交易时间": ("取引可能時間", "Available time"),
        "交易方式": ("取引方法", "Trade method"),
        "补充留言": ("追加メッセージ", "Additional message"),
        "用餐日期": ("来店日", "Dining date"),
        "到店时间": ("来店時間", "Arrival time"),
        "用餐人数": ("人数", "Party size"),
        "预订姓名": ("予約名", "Booking name"),
        "特殊需求": ("特別リクエスト", "Special requests"),
        "入住日期": ("チェックイン", "Check-in"),
        "退房日期": ("チェックアウト", "Check-out"),
        "房间数": ("部屋数", "Rooms"),
        "补充说明": ("補足", "Notes"),
        "出行日期": ("利用日", "Travel date"),
        "人数 / 票数": ("人数 / 枚数", "People / tickets"),
        "希望语言": ("希望言語", "Preferred language"),
        "用车日期": ("利用日", "Ride date"),
        "路线": ("ルート", "Route"),
        "航班/车次": ("便名 / 到着時間", "Flight / train"),
        "行李数": ("荷物数", "Luggage"),
        "具体需求": ("具体的な依頼内容", "Request details"),
        "事项类型": ("手続き種別", "Procedure type"),
        "希望完成时间": ("希望納期", "Preferred deadline"),
        "物品/房间说明": ("荷物・部屋について", "Items / room notes"),
        "希望日期": ("希望日", "Preferred date"),
        "服务区域": ("対応エリア", "Service area"),
        "物品量/房型": ("荷物量・間取り", "Item volume / room type"),
        "服务事项": ("サービス内容", "Service item"),
        "注意事项": ("注意事項", "Notes"),
        "预约日期": ("予約日", "Appointment date"),
        "预约时段": ("予約時間帯", "Appointment time"),
        "服务项目": ("サービス項目", "Service item")
    ]
}

private enum ListingFilterLocalizer {
    static func text(_ value: String, _ language: AppLanguage) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return value }
        if let entry = table[normalized] {
            return KXListingCopy.pickText(language, normalized, entry.ja, entry.en)
        }
        let category = KXListingCopy.categoryLabel(normalized, language)
        if category != normalized { return category }
        return ListingIntakeLocalizer.text(normalized, language)
    }

    private static let table: [String: (ja: String, en: String)] = [
        "每晚价格": ("1泊料金", "Nightly price"),
        "月租范围": ("月額家賃", "Monthly rent"),
        "薪资范围": ("給与範囲", "Pay range"),
        "价格范围": ("価格範囲", "Price range"),
        "最低": ("下限", "Min"),
        "最高": ("上限", "Max"),
        "不限": ("指定なし", "Any"),
        "出售": ("売ります", "For sale"),
        "全新": ("新品", "Brand new"),
        "几乎全新": ("ほぼ新品", "Like new"),
        "良好": ("良好", "Good"),
        "有使用痕迹": ("使用感あり", "Used"),
        "可用": ("使用可", "Fair"),
        "面交": ("手渡し", "Meetup"),
        "自取": ("引き取り", "Pickup"),
        "邮寄": ("配送", "Shipping"),
        "可商量": ("相談可", "Negotiable"),
        "交易偏好": ("取引条件", "Deal preferences"),
        "可自取": ("引き取り可", "Pickup available"),
        "可邮寄": ("配送可", "Shipping available"),
        "2 人及以上": ("2名以上", "2+ guests"),
        "3 人及以上": ("3名以上", "3+ guests"),
        "4 人及以上": ("4名以上", "4+ guests"),
        "6 人及以上": ("6名以上", "6+ guests"),
        "住宿条件": ("宿泊条件", "Stay options"),
        "条件": ("条件", "Options"),
        "可宠物": ("ペット可", "Pet friendly"),
        "可短租": ("短期可", "Short-term OK"),
        "可合租": ("ルームシェア可", "Share OK"),
        "雇佣形式": ("雇用形態", "Employment type"),
        "日语要求": ("日本語条件", "Japanese requirement"),
        "日语不限": ("日本語不問", "No Japanese required"),
        "签证支持": ("ビザサポート", "Visa support"),
        "有": ("あり", "Available"),
        "可咨询": ("相談可", "Ask"),
        "可远程": ("リモート可", "Remote OK"),
        "服务细分类": ("サービス細分類", "Service subcategory"),
        "餐饮预约": ("飲食店", "Restaurants"),
        "餐厅美食": ("飲食店", "Restaurants"),
        "餐厅": ("飲食店", "Restaurants"),
        "旅行票务": ("旅行・チケット", "Travel"),
        "接送交通": ("送迎・交通", "Transfers"),
        "美容健康": ("美容・健康", "Beauty & health"),
        "商家条件": ("店舗条件", "Merchant options"),
        "需要预约": ("予約必須", "Booking required"),
        "城市范围": ("都市圏", "Metro area"),
        "热门城市": ("人気都市", "Popular cities")
    ]
}

private struct ListingIntakeField: Identifiable, Equatable {
    let id: String
    let label: String
    let placeholder: String
    let options: [String]
    let required: Bool

    init(_ id: String, label: String, placeholder: String = "", options: [String] = [], required: Bool = false) {
        self.id = id
        self.label = label
        self.placeholder = placeholder
        self.options = options
        self.required = required
    }
}

private struct ListingIntakeSpec {
    let title: String
    let actionWord: String
    let noteLabel: String
    let fields: [ListingIntakeField]

    static func forType(_ type: String, category: String? = nil) -> ListingIntakeSpec {
        // 结构化预订：服务类目给出真正可用的字段。
        if type == "local_service" {
            if KXListingCopy.isStayCategory(category) {
                return ListingIntakeSpec(
                    title: "预订住宿",
                    actionWord: "预订住宿",
                    noteLabel: "特殊需求",
                    fields: [
                        ListingIntakeField("check_in", label: "入住日期", placeholder: "例如 7 月 1 日", required: true),
                        ListingIntakeField("check_out", label: "退房日期", placeholder: "例如 7 月 3 日", required: true),
                        ListingIntakeField("guests", label: "入住人数", options: ["1 人", "2 人", "3 人", "4 人", "5 人及以上"], required: true),
                        ListingIntakeField("rooms", label: "房间数", options: ["1 间", "2 间", "3 间及以上"]),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            }
            if KXListingCopy.isFoodCategory(category) {
                // 餐饮在线订座
                return ListingIntakeSpec(
                    title: "在线订座",
                    actionWord: "订座",
                    noteLabel: "备注（忌口 / 包间 / 儿童座椅等）",
                    fields: [
                        ListingIntakeField("date", label: "用餐日期", placeholder: "例如 6 月 15 日", required: true),
                        ListingIntakeField("time", label: "到店时间", options: ["午市 11:00-14:00", "下午 14:00-17:00", "晚市 17:00-20:00", "晚市 20:00 之后"], required: true),
                        ListingIntakeField("party", label: "用餐人数", options: ["1-2 人", "3-4 人", "5-8 人", "8 人以上"], required: true),
                        ListingIntakeField("name", label: "预订姓名", placeholder: "到店报姓名即可", required: true),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            }
            switch category ?? "" {
            case "景点门票", "一日游", "本地向导", "体验活动", "包车行程":
                return ListingIntakeSpec(
                    title: category == "景点门票" ? "预订门票" : "预订行程",
                    actionWord: "预订",
                    noteLabel: "补充说明",
                    fields: [
                        ListingIntakeField("date", label: "出行日期", placeholder: "例如 7 月 1 日", required: true),
                        ListingIntakeField("tickets", label: "人数 / 票数", options: ["1", "2", "3", "4", "5 及以上"], required: true),
                        ListingIntakeField("language", label: "希望语言", options: ["中文", "日本語", "English", "无要求"]),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "接送机", "机场接送", "车站接送", "包车", "行李协助":
                return ListingIntakeSpec(
                    title: "预约接送",
                    actionWord: "预约接送",
                    noteLabel: "补充说明",
                    fields: [
                        ListingIntakeField("date", label: "用车日期", placeholder: "例如 7 月 1 日", required: true),
                        ListingIntakeField("route", label: "路线", placeholder: "成田机场 -> 新宿 / 东京站 -> 住处", required: true),
                        ListingIntakeField("flight", label: "航班/车次", placeholder: "例如 NH878 / 新干线到达时间"),
                        ListingIntakeField("passengers", label: "人数", options: ["1", "2", "3", "4", "5 及以上"], required: true),
                        ListingIntakeField("luggage", label: "行李数", options: ["1-2 件", "3-4 件", "5 件及以上"]),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "材料翻译", "市役所陪同", "银行卡协助", "手机卡协助", "租房申请协助", "签证材料整理", "翻译手续", "签证/手续协助", "翻译":
                return ListingIntakeSpec(
                    title: "预约手续协助",
                    actionWord: "预约手续协助",
                    noteLabel: "具体需求",
                    fields: [
                        ListingIntakeField("service", label: "事项类型", placeholder: "住民票 / 银行卡 / 手机卡 / 材料翻译", required: true),
                        ListingIntakeField("deadline", label: "希望完成时间", placeholder: "例如 本周内 / 3 个工作日"),
                        ListingIntakeField("language", label: "希望语言", options: ["中文", "日本語", "English", "无要求"]),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "搬家", "退房清洁", "粗大垃圾协助", "行李搬运", "家具家电配送协助", "搬家清洁", "清洁":
                return ListingIntakeSpec(
                    title: "预约搬家清洁",
                    actionWord: "预约搬家清洁",
                    noteLabel: "物品/房间说明",
                    fields: [
                        ListingIntakeField("date", label: "希望日期", placeholder: "例如 7 月 1 日", required: true),
                        ListingIntakeField("address_area", label: "服务区域", placeholder: "新宿区 / 丰岛区", required: true),
                        ListingIntakeField("volume", label: "物品量/房型", placeholder: "1K / 纸箱 20 个 / 大件 3 件"),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "手机卡开通", "网络开通", "水电煤协助", "地址登记协助", "粗大垃圾预约", "生活跑腿":
                return ListingIntakeSpec(
                    title: "预约生活开通",
                    actionWord: "预约生活开通",
                    noteLabel: "具体需求",
                    fields: [
                        ListingIntakeField("service", label: "服务事项", placeholder: "手机卡 / 网络 / 水电煤 / 地址登记", required: true),
                        ListingIntakeField("preferred_date", label: "希望日期", placeholder: "例如 到日当天 / 本周末"),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "美容美发", "美甲", "按摩", "皮肤管理", "体检/牙科预约协助":
                return ListingIntakeSpec(
                    title: "预约服务",
                    actionWord: "预约美容健康",
                    noteLabel: "注意事项",
                    fields: [
                        ListingIntakeField("date", label: "预约日期", placeholder: "例如 6 月 20 日", required: true),
                        ListingIntakeField("time", label: "预约时段", options: ["上午", "下午", "晚上", "周末"], required: true),
                        ListingIntakeField("service", label: "服务项目", placeholder: "剪发 / 美甲 / 按摩 / 体检预约", required: true),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            default:
                break
            }
        }
        switch type {
        case "rental":
            return ListingIntakeSpec(
                title: "预约看房",
                actionWord: "预约看房",
                noteLabel: "备注",
                fields: [
                    ListingIntakeField("date", label: "希望看房日期", placeholder: "例如 6 月 12 日", required: true),
                    ListingIntakeField("time", label: "希望时段", options: ["上午", "下午", "晚上", "周末"], required: true),
                    ListingIntakeField("situation", label: "当前情况", options: ["在日本", "海外", "学生", "在职"]),
                    ListingIntakeField("move_in", label: "入住时间", placeholder: "例如 7 月上旬 / 即可入住"),
                    ListingIntakeField("people", label: "入住人数", options: ["1 人", "2 人", "3 人", "4 人及以上"]),
                    ListingIntakeField("budget", label: "预算", placeholder: "例如 月租 8 万以内"),
                    ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                ]
            )
        case "job", "hiring", "work":
            return ListingIntakeSpec(
                title: "申请职位",
                actionWord: "申请",
                noteLabel: "自我介绍",
                fields: [
                    ListingIntakeField("name", label: "姓名", required: true),
                    ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ListingIntakeField("visa", label: "签证状态", options: ["留学", "工作签证", "永住", "家族滞在", "其他"]),
                    ListingIntakeField("japanese", label: "日语水平", options: ["N1", "N2", "N3", "日常会话", "暂不会"]),
                    ListingIntakeField("availability", label: "可工作时间", placeholder: "平日晚上 / 周末"),
                    ListingIntakeField("start_date", label: "最快入职时间", placeholder: "例如 立即 / 7 月起"),
                ]
            )
        case "local_service":
            return ListingIntakeSpec(
                title: "预约服务",
                actionWord: "预约服务",
                noteLabel: "具体需求",
                fields: [
                    ListingIntakeField("city", label: "服务城市", required: true),
                    ListingIntakeField("service_scene", label: "服务场景", options: ["到店预约", "景点门票", "一日游", "机场接送", "翻译手续", "搬家清洁", "生活开通", "美容健康"]),
                    ListingIntakeField("date", label: "希望日期", placeholder: "例如 6 月 12 日"),
                    ListingIntakeField("time", label: "希望时段", options: ["上午", "下午", "晚上", "周末"]),
                    ListingIntakeField("people", label: "人数/件数", placeholder: "例如 2 人 / 3 件行李 / 1 套资料"),
                    ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                ]
            )
        case "discount":
            return ListingIntakeSpec(title: "联系商家", actionWord: "咨询", noteLabel: "留言", fields: [
                ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
            ])
        case "event":
            return ListingIntakeSpec(title: "报名 / 咨询", actionWord: "报名 / 咨询", noteLabel: "留言", fields: [
                ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
            ])
        default:
            return ListingIntakeSpec(
                title: "联系卖家",
                actionWord: "咨询",
                noteLabel: "补充留言",
                fields: [
                    ListingIntakeField("intent", label: "咨询意向", options: ["想购买", "想议价", "想看实物", "想预约自取", "询问是否还在"], required: true),
                    ListingIntakeField("meetup", label: "希望交易地点", placeholder: "例如 新宿站 / 池袋 / 可线上确认"),
                    ListingIntakeField("available_time", label: "可交易时间", placeholder: "例如 今天晚上 / 周末下午 / 平日 19:00 后", required: true),
                    ListingIntakeField("delivery", label: "交易方式", options: ["自取 / 面交", "希望邮寄", "都可以"]),
                    ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                ]
            )
        }
    }
}

private struct ListingIntakeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    let listingTitle: String
    let listingType: String
    var listingCategory: String? = nil
    let submitting: Bool
    let onSubmit: (_ message: String, _ details: [[String: String]]) -> Void

    @State private var values: [String: String] = [:]
    @State private var note = ""
    @State private var errorMessage: String?

    private var spec: ListingIntakeSpec {
        ListingIntakeSpec.forType(listingType, category: listingCategory)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ListingIntakeLocalizer.text(spec.title, language))
                            .font(.title3.weight(.black))
                        Text(listingTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .kxGlassSurface(radius: 20)

                    ForEach(spec.fields) { field in
                        intakeField(field)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(ListingIntakeLocalizer.text(spec.noteLabel, language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField(ListingIntakeLocalizer.text("补充说明（选填）", language), text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.subheadline.weight(.semibold))
                            .padding(12)
                            .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(12)
                    .background(KXColor.softBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.heat)
                    }

                    Text(ListingIntakeLocalizer.text("提交后会生成正式记录，私信只用于后续补充沟通。Machi 不代收交易款、押金、保证金或第三方服务款，请勿提前转账。", language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KXColor.heat)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(KXColor.heat.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button(action: submit) {
                        HStack {
                            if submitting { KXSpinner(size: 18, lineWidth: 2.2, tint: .white) }
                            Text(submitting ? ListingIntakeLocalizer.text("提交中", language) : ListingIntakeLocalizer.text(spec.title, language))
                                .font(.headline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(KXColor.accent, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(submitting)
                }
                .padding(KaiXTheme.horizontalPadding)
            }
            .kxPageBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ListingIntakeLocalizer.text("关闭", language)) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func intakeField(_ field: ListingIntakeField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.required ? "\(ListingIntakeLocalizer.text(field.label, language)) *" : ListingIntakeLocalizer.text(field.label, language))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if field.options.isEmpty {
                TextField(ListingIntakeLocalizer.text(field.placeholder.isEmpty ? field.label : field.placeholder, language), text: binding(for: field))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Picker(ListingIntakeLocalizer.text(field.label, language), selection: binding(for: field)) {
                    Text(ListingIntakeLocalizer.text("请选择", language)).tag("")
                    ForEach(field.options, id: \.self) { option in
                        Text(ListingIntakeLocalizer.text(option, language)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(12)
        .background(KXColor.softBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func binding(for field: ListingIntakeField) -> Binding<String> {
        Binding(
            get: { values[field.id, default: ""] },
            set: { values[field.id] = $0 }
        )
    }

    private func submit() {
        for field in spec.fields where field.required {
            if values[field.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = ListingIntakeLocalizer.requiredMessage(field.label, language)
                return
            }
        }
        errorMessage = nil
        let details = spec.fields.compactMap { field -> [String: String]? in
            let value = values[field.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return ["label": ListingIntakeLocalizer.text(field.label, language), "value": ListingIntakeLocalizer.text(value, language)]
        }
        onSubmit(note, details)
    }
}

enum ListingMediaUploadPhase: Equatable {
    case idle
    case preparing
    case uploading(Double)
    case completing
    case ready
    case failed(String)

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .idle: return KXListingCopy.pickText(language, "待上传", "アップロード待ち", "Waiting")
        case .preparing: return KXListingCopy.pickText(language, "准备中", "準備中", "Preparing")
        case .uploading(let progress):
            return "\(KXListingCopy.pickText(language, "上传中", "アップロード中", "Uploading")) \(Int(progress * 100))%"
        case .completing: return KXListingCopy.pickText(language, "确认中", "確認中", "Finalizing")
        case .ready: return KXListingCopy.pickText(language, "已上传", "アップロード済み", "Uploaded")
        case .failed(let message): return message
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

// MARK: - 频道加载骨架（与各卡片版式同构，breathe 动效复用 kxShimmer）

private struct KXSkeletonBone: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = 5
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(KXColor.softBackground)
            .frame(width: width, height: height)
    }
}

private struct KXSecondhandSkeletonCard: View {
    let width: CGFloat
    private var inner: CGFloat { max(0, width - 14) }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KXColor.softBackground)
                .frame(width: inner, height: inner)
            KXSkeletonBone(width: 72, height: 15)
            KXSkeletonBone(width: inner - 24, height: 11)
            KXSkeletonBone(width: 96, height: 9)
        }
        .padding(7)
        .padding(.bottom, 2)
        .frame(width: width, alignment: .leading)
        .kxLivingSurface(radius: 18)
        .kxShimmer()
    }
}

private struct KXJobSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(KXColor.softBackground)
                    .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 7) {
                    KXSkeletonBone(width: 190, height: 13)
                    KXSkeletonBone(width: 120, height: 10)
                }
                Spacer(minLength: 0)
            }
            KXSkeletonBone(width: 140, height: 13)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    KXSkeletonBone(width: 56, height: 22, radius: 11)
                }
            }
        }
        .padding(14)
        .kxLivingSurface(radius: 20, elevated: true)
        .kxShimmer()
    }
}

private struct KXBigPhotoSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(KXColor.softBackground) }
            VStack(alignment: .leading, spacing: 7) {
                KXSkeletonBone(width: 200, height: 13)
                KXSkeletonBone(width: 150, height: 10)
                KXSkeletonBone(width: 110, height: 13)
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .kxLivingSurface(radius: 24, elevated: true)
        .kxShimmer()
    }
}

/// Square cover sizing for listing cards. With a fixed `side` it's an exact
/// square; with `nil` (card filling a flexible grid cell) it fills the cell
/// width and stays 1:1 — fixes the ragged/overlapping grid when no width is
/// passed (e.g. profile → 我的二手).
private struct KXSquareCover: ViewModifier {
    let side: CGFloat?
    func body(content: Content) -> some View {
        if let side {
            content.frame(width: side, height: side)
        } else {
            content.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
        }
    }
}

private struct KXSecondhandListingCard: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    var width: CGFloat? = nil
    let onOpen: () -> Void

    private var innerWidth: CGFloat? {
        width.map { max(0, $0 - 14) }
    }

    private var statusBadgeMaxWidth: CGFloat? {
        innerWidth.map { max(70, $0 - 48) }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                cover
                    .frame(width: innerWidth)
                Text(KXListingCopy.priceLabel(listing, language))
                    .font(.headline.weight(.black))
                    .foregroundStyle(KXColor.heat)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(width: innerWidth, alignment: .leading)
                Text(KXListingCopy.displayTitle(listing))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(width: innerWidth, alignment: .leading)
                let badges = KXListingCopy.secondhandCardBadges(for: listing, language)
                if !badges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(badges.prefix(2), id: \.self) { badge in
                            Text(badge)
                                .font(.caption2.weight(.black))
                                .foregroundStyle(KXColor.rankTeal)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .padding(.horizontal, 6)
                                .frame(height: 20)
                                .background(KXColor.rankTeal.opacity(0.09), in: Capsule())
                        }
                    }
                    .frame(width: innerWidth, alignment: .leading)
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2.weight(.bold))
                    Text(KXListingCopy.compactMeta(listing, language))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: innerWidth, alignment: .leading)
            }
            .padding(7)
            .padding(.bottom, 2)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
            .kxLivingSurface(radius: 18)
        }
        .frame(maxWidth: width ?? .infinity, alignment: .leading)
        .buttonStyle(.plain)
    }

    private var cover: some View {
        ZStack {
            if let url = listing.coverURL {
                MediaImageView(url: url, targetPixelSize: 720)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                ListingMediaPlaceholder(type: listing.type)
            }
            if listing.coverIsVideo {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.55), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .modifier(KXSquareCover(side: innerWidth))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                Circle()
                    .fill(KXListingCopy.statusColor(listing.status))
                    .frame(width: 6, height: 6)
                Text(KXListingCopy.formatListingStatus(listing.status, type: listing.type, language))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            .frame(maxWidth: statusBadgeMaxWidth, alignment: .leading)
            .padding(7)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: listing.favorited == true ? "heart.fill" : "heart")
                .font(.caption2.weight(.bold))
                .foregroundStyle(listing.favorited == true ? KXColor.heat : .primary)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                .padding(7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
        }
    }
}

private struct ListingMediaPage: View {
    let media: KaiXListingMediaDTO
    let index: Int
    let total: Int

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if media.normalizedType == "video" {
                MediaVideoView(sourceURL: media.sourceURL, posterURL: media.previewURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url = media.previewURL {
                MediaImageView(url: url, targetPixelSize: 1400)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                ListingMediaPlaceholder(type: media.normalizedType)
            }
            if total > 1 {
                Text("\(index + 1)/\(total)")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(10)
            }
        }
    }
}

private struct ListingMediaPlaceholder: View {
    @Environment(\.appLanguage) private var language

    let type: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    KXColor.livingSoft,
                    KXColor.livingAccentSoft.opacity(0.7),
                    Color(.systemBackground).opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(KXColor.livingWarm.opacity(0.10))
                .frame(width: 200, height: 200)
                .offset(x: -120, y: -70)
            Circle()
                .fill(KXColor.livingAccent.opacity(0.10))
                .frame(width: 240, height: 240)
                .offset(x: 150, y: 90)
            VStack(spacing: 11) {
                Image(systemName: type == "video" ? "play.rectangle.fill" : KXListingCopy.icon(for: type))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(KXColor.livingAccent.opacity(0.8))
                Text(type == "video"
                     ? KXListingCopy.pickText(language, "视频封面生成中", "動画カバーを生成中", "Generating video cover")
                     : KXListingCopy.pickText(language, "暂无图片", "画像はまだありません", "No photos yet"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.livingMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct KXJobListingRow: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    let onOpen: () -> Void

    private var companyName: String {
        (KXListingCopy.attr(listing, "company_name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var workLocation: String {
        (KXListingCopy.attr(listing, "work_location") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var salaryText: String {
        let s = (KXListingCopy.attr(listing, "salary") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? KXListingCopy.priceLabel(listing, language) : s
    }
    private var companyVerified: Bool {
        KXListingCopy.boolAttr(listing, "company_verified") || listing.verification_status == "verified"
    }
    // Employment type is stored as a ready-to-show label ("全职"/"兼职"…), not a
    // key — read it directly. Falls back to the job_type enum for older rows.
    private var employmentLabel: String? {
        let e = (KXListingCopy.attr(listing, "employment_type") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.isEmpty { return e }
        switch KXListingCopy.attr(listing, "job_type") {
        case "full_time": return L("jt_full_time", language)
        case "part_time": return L("jt_part_time", language)
        case "internship": return L("jt_internship", language)
        case "remote": return L("jt_remote", language)
        default: return nil
        }
    }
    private var japaneseLabel: String? {
        let j = (KXListingCopy.attr(listing, "japanese_level") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLanguagePrefix = j.contains("日语") || j.contains("日本語") || j.localizedCaseInsensitiveContains("Japanese")
        return j.isEmpty ? nil : (hasLanguagePrefix ? j : "\(KXListingCopy.pickText(language, "日语", "日本語", "Japanese")) \(j)")
    }
    private var visaSupport: Bool { KXListingCopy.boolAttr(listing, "visa_support") }
    private var companyInitial: String {
        let source = companyName.isEmpty ? KXListingCopy.displayTitle(listing) : companyName
        return String(source.prefix(1)).uppercased()
    }

    /// Indeed-style fact chips beyond employment + japanese: visa, no-experience,
    /// remote, students, commute, weekly holidays, benefits. Capped so the row
    /// stays tidy.
    private var jobFactChips: [String] {
        var chips: [String] = []
        let visa = (KXListingCopy.attr(listing, "visa_support") ?? "").lowercased()
        if visa == "available" || visa == "support" || visa == "true" {
            chips.append(KXListingCopy.pickText(language, "签证支持", "ビザサポート", "Visa support"))
        } else if visa == "consult" {
            chips.append(KXListingCopy.pickText(language, "签证可咨询", "ビザ相談可", "Visa negotiable"))
        }
        if KXListingCopy.boolAttr(listing, "no_experience_ok") { chips.append(KXListingCopy.pickText(language, "无经验可", "未経験可", "No experience OK")) }
        if KXListingCopy.boolAttr(listing, "remote_ok") { chips.append(KXListingCopy.pickText(language, "可远程", "リモート可", "Remote OK")) }
        if KXListingCopy.boolAttr(listing, "student_ok") { chips.append(KXListingCopy.pickText(language, "留学生可", "留学生可", "Students OK")) }
        if KXListingCopy.boolAttr(listing, "transportation_fee") { chips.append(KXListingCopy.pickText(language, "交通费支给", "交通費支給", "Transport paid")) }
        let holidays = KXListingCopy.attr(listing, "holidays") ?? ""
        if !holidays.isEmpty { chips.append(holidays.count > 6 ? String(holidays.prefix(6)) : holidays) }
        if KXListingCopy.boolAttr(listing, "foreigner_friendly"), chips.count < 5 {
            chips.append(KXListingCopy.pickText(language, "外国人友好", "外国人歓迎", "Foreigner-friendly"))
        }
        return Array(chips.prefix(5))
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 12) {
                    Text(companyInitial.isEmpty ? "M" : companyInitial)
                        .font(.title3.weight(.black))
                        .foregroundStyle(KXColor.livingAccent)
                        .frame(width: 50, height: 50)
                        .background(
                            LinearGradient(
                                colors: [KXColor.livingAccentSoft, KXColor.livingWarm.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(KXColor.livingInk.opacity(0.06), lineWidth: 0.8)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(KXListingCopy.displayTitle(listing))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(KXColor.livingInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !companyName.isEmpty {
                            HStack(spacing: 5) {
                                Text(companyName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(KXColor.livingMuted)
                                    .lineLimit(1)
                                if companyVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(KXColor.accent)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                // Indeed-style key facts: salary + location with leading glyphs.
                HStack(spacing: 14) {
                    if !salaryText.isEmpty {
                        Label(salaryText, systemImage: "yensign.circle.fill")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(KXColor.livingAccent)
                            .lineLimit(1)
                    }
                    if !workLocation.isEmpty {
                        Label(workLocation, systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KXColor.livingMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                FlowLayout(spacing: 6) {
                    if let employment = employmentLabel {
                        jobChip(employment, filled: true)
                    }
                    if let japanese = japaneseLabel {
                        jobChip(japanese, filled: false)
                    }
                    ForEach(jobFactChips, id: \.self) { chip in
                        jobChip(chip, filled: false)
                    }
                }

                Divider().overlay(KXColor.livingInk.opacity(0.06))

                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    Text(KXListingCopy.pickText(language, "查看详情 · 投递", "詳細を見る・応募", "View details · Apply"))
                        .font(.caption.weight(.black))
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.black))
                }
                .foregroundStyle(KXColor.livingAccent)
            }
            .padding(14)
            .kxLivingSurface(radius: 20, elevated: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(KXPressableStyle(scale: 0.985, dim: 0.9))
    }

    @ViewBuilder
    private func jobChip(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(filled ? KXColor.livingAccent : KXColor.livingMuted)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(filled ? KXColor.livingAccentSoft : KXColor.livingSoft, in: Capsule())
            .overlay(filled ? Capsule().strokeBorder(KXColor.livingAccent.opacity(0.25), lineWidth: 0.8) : nil)
    }
}

private struct KXStructuredListingRow: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    if let url = listing.coverURL {
                        MediaImageView(url: url)
                            .frame(width: 112, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(KXColor.softBackground)
                            .frame(width: 112, height: 104)
                            .overlay {
                                Image(systemName: KXListingCopy.icon(for: listing.type))
                                    .foregroundStyle(.secondary.opacity(0.56))
                            }
                    }
                    if listing.coverIsVideo {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.55), in: Circle())
                            .frame(width: 112, height: 104)
                    }
                    KXListingBadge(title: KXListingCopy.formatListingType(listing.type), tint: KXColor.accent)
                        .padding(7)
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        Text(KXListingCopy.priceLabel(listing, language))
                            .font(.headline.weight(.black))
                            .foregroundStyle(KXColor.heat)
                            .lineLimit(2)
                        Spacer()
                        KXListingBadge(title: KXListingCopy.statusLabel(listing.status, type: listing.type, language), tint: KXListingCopy.statusColor(listing.status))
                    }
                    Text(KXListingCopy.displayTitle(listing))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(KXListingCopy.structuredMeta(listing, language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    FlowLayout(spacing: 6) {
                        ForEach(KXListingCopy.badges(for: listing, language).prefix(3), id: \.self) { badge in
                            KXListingBadge(title: badge, tint: KXColor.rankTeal)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11)
            .kxGlassSurface(radius: 20, elevated: true)
        }
        .buttonStyle(.plain)
    }
}

private struct KXListingAttributeSection: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO

    var body: some View {
        KXListingSection(title: KXListingCopy.pickText(language, "核心字段", "基本情報", "Key details"), icon: KXListingCopy.icon(for: listing.type)) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(KXListingCopy.attributes(for: listing, language), id: \.0) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(KXListingCopy.attributeLabel(item.0, language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(item.1)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KXColor.livingSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
        }
    }
}

struct KXListingSection<Content: View>: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(KXListingCopy.formText(title, language), systemImage: icon)
                .font(.headline.weight(.bold))
            content
        }
        .padding(KXSpacing.lg)
        .kxLivingSurface(radius: 22)
    }
}

private struct KXListingBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(tint.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.18), lineWidth: 0.7)
            }
    }
}

private extension KaiXCityListingDTO {
    var primaryCoverMedia: KaiXListingMediaDTO? {
        coverMedia
            ?? cover_media
            ?? card?.coverMedia
            ?? listingCard?.coverMedia
            ?? media?.first(where: { $0.is_cover == true || $0.isCover == true })
            ?? media?.first
    }

    var coverURL: URL? {
        // Skip server-generated placeholder covers — the native placeholder
        // looks far better than the "Generated default cover" card.
        if let cover = primaryCoverMedia,
           !KaiXCityListingDTO.isGeneratedCover(cover.url),
           let url = cover.previewURL {
            return url
        }
        return realCoverURL
    }

    var coverIsVideo: Bool {
        primaryCoverMedia?.normalizedType == "video"
    }
}

extension KaiXAttributeValue {
    var listingDisplayValue: String {
        switch kind {
        case .string(let value):
            return value
        case .double(let value):
            return value.rounded() == value ? "\(Int(value))" : String(format: "%.2f", value)
        case .bool(let value):
            return value ? "是" : "否"
        case .json:
            return ""   // 结构化属性(菜单/团购)由专门的视图渲染,不在通用属性行展示
        case .null:
            return ""
        }
    }
}

/// Identifiable receipt for the post-publish success sheet.
struct ListingPublishReceipt: Identifiable {
    let id = UUID()
    let listingId: String
    let isEditing: Bool
    let published: Bool
    let typeLabel: String
    let title: String
    let regionLabel: String
    let locationText: String
}

/// Post-publish success sheet — clear confirmation with the key facts and the
/// three next actions (查看发布 / 继续发布 / 去工作台). Replaces the old 0.42s flash.
struct ListingPublishSuccessSheet: View {
    let receipt: ListingPublishReceipt
    let language: AppLanguage
    let onViewListing: () -> Void
    let onContinuePublishing: () -> Void
    let onClose: () -> Void

    private func pick(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(KXColor.softBackground, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, KXSpacing.lg)
            .padding(.top, KXSpacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    VStack(spacing: 10) {
                        Image(systemName: receipt.published ? "checkmark.seal.fill" : "clock.badge.checkmark.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(receipt.published ? KXColor.accent : .orange)
                        Text(receipt.published
                             ? pick("发布成功", "公開しました", "Published")
                             : pick("已提交审核", "審査に提出しました", "Submitted for review"))
                            .font(.title3.weight(.bold))
                        Text(receipt.published
                             ? pick("已同步到 Web 与 iOS，并进入对应城市频道。", "Web と iOS に同期し、都市チャンネルに表示されます。", "Synced to web & iOS and added to the city channel.")
                             : pick("审核通过后会自动展示，可在详情页查看状态。", "承認後に自動表示されます。詳細で状態を確認できます。", "It will appear once approved; track status on the detail page."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, KXSpacing.sm)

                    VStack(spacing: 0) {
                        row(pick("类型", "種類", "Type"), receipt.typeLabel)
                        Divider()
                        row(pick("标题", "タイトル", "Title"), receipt.title)
                        if !receipt.regionLabel.isEmpty {
                            Divider(); row(pick("发布地区", "公開エリア", "Publish area"), receipt.regionLabel)
                        }
                        if !receipt.locationText.isEmpty {
                            Divider(); row(pick("展示位置", "表示する場所", "Location"), receipt.locationText)
                        }
                        Divider()
                        row(pick("状态", "状態", "Status"), receipt.published ? pick("已发布", "公開中", "Live") : pick("审核中", "審査中", "In review"))
                    }
                    .padding(KXSpacing.md)
                    .background(KXColor.softBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, KXSpacing.lg)
                .padding(.bottom, KXSpacing.md)
            }

            VStack(spacing: 10) {
                Button(action: onViewListing) {
                    Text(pick("查看发布", "投稿を見る", "View listing"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(KXColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                HStack(spacing: 10) {
                    Button(action: onContinuePublishing) {
                        Text(pick("继续发布", "続けて投稿", "Publish another"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(KXColor.accent.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button(action: onClose) {
                        Text(pick("完成", "完了", "Done"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(KXColor.softBackground.opacity(0.9), in: Capsule())
                            .overlay(Capsule().stroke(KXColor.separator.opacity(0.6), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KXSpacing.lg)
            .padding(.bottom, KXSpacing.lg)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
    }
}
