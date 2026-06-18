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
                        contentListSection
                    case .ranking:
                        DiscoverHotScopePicker(selection: $selectedHotScope, region: currentRegion)
                        contentListSection
                    case .topics, .users:
                        contentListSection
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, chrome.bottomContentPadding + 28)
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
                    .accessibilityLabel("搜索")
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
        .init(id: "housing", title: "租房 · 住宿", subtitle: "长租房源、看房预约与民宿短住", icon: "house", types: [.housing, .roommate], channel: .housing, tint: Color.blue),
        .init(id: "work", title: "工作", subtitle: "职位、招聘、内推和申请进度", icon: "briefcase", types: [.job_seek, .job_post, .referral], channel: .jobPost, tint: KXColor.rankViolet),
        .init(id: "service", title: "商家与服务", subtitle: "餐厅美食、订座点评、景点玩乐", icon: "storefront", types: [.service, .merchant], channel: .service, tint: Color.brown),
    ]

    private static let extendedSpecs: [DiscoverCategorySpec] = [
        .init(id: "guide", title: "城市指南", subtitle: "攻略、经验、避坑", icon: "book.closed", types: [.guide, .long_post, .warning], channel: .guide, tint: KXColor.rankTeal),
        .init(id: "news", title: "本地快讯", subtitle: "新闻、交通、生活提醒", icon: "newspaper", types: [.news, .local_info], channel: .news, tint: KXColor.rankSky),
        .init(id: "coupon", title: "商家优惠", subtitle: "折扣福利、本地商家活动", icon: "tag", types: [.coupon], channel: .coupon, tint: KXColor.heat),
        .init(id: "groups", title: "活动小组", subtitle: "Food meetup、语言交换", icon: "person.2", types: [.meetup, .dining, .event], channel: .meetup, tint: Color.orange),
        .init(id: "question", title: "问答互助", subtitle: "问答、匿名提问、生活求助", icon: "questionmark.circle", types: [.question, .anonymous], channel: .question, tint: Color.indigo),
        .init(id: "warning", title: "避坑经验", subtitle: "风险提醒和踩雷复盘", icon: "exclamationmark.shield", types: [.warning], channel: .guide, tint: Color.red),
        .init(id: "jobseek", title: "找工作", subtitle: "求职线索、兼职、全职", icon: "briefcase", types: [.job_seek], channel: .jobSeek, tint: Color.mint),
        .init(id: "jobpost", title: "招聘", subtitle: "职位发布和招聘方认证", icon: "person.badge.plus", types: [.job_post], channel: .jobPost, tint: KXColor.rankViolet),
        .init(id: "referral", title: "内推", subtitle: "公司内推", icon: "person.crop.circle.badge.checkmark", types: [.referral], channel: .jobPost, tint: Color.indigo),
        .init(id: "language", title: "语言交换", subtitle: "公开语言学习活动", icon: "bubble.left.and.bubble.right", types: [.meetup], channel: .meetup, tint: Color.orange),
        .init(id: "food", title: "Food meetup", subtitle: "餐厅、咖啡和小型饭局", icon: "fork.knife", types: [.dining], channel: .dining, tint: KXColor.rankCoral),
        .init(id: "localgroup", title: "本地小组", subtitle: "运动、周末活动、城市散步", icon: "calendar", types: [.event, .meetup], channel: .event, tint: Color.purple),
        .init(id: "merchant", title: "商家", subtitle: "本地店铺和服务商资料", icon: "storefront", types: [.merchant], channel: .service, tint: Color.teal),
        .init(id: "travel_stays", title: "民宿 · 短住", subtitle: "民宿、酒店、温泉旅馆（租房 · 住宿内）", icon: "bed.double", types: [.service, .merchant], channel: .housing, tint: Color.cyan),
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

    var title: String {
        switch self {
        case .recommend: "正在发生"
        case .ranking: "热榜"
        case .topics: "话题"
        case .users: "用户推荐"
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
    var title: String { spec.title }
    var subtitle: String { spec.subtitle }
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
        // 「民宿·短住」伪类型：租房频道直接落在 stays 标签。
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

    var heroTags: [String] {
        switch id {
        case "secondhand": return ["估价", "求购", "面交安全"]
        case "housing": return ["长租", "民宿短住", "看房预约"]
        case "work": return ["薪资", "签证", "雇主认证"]
        case "service": return ["餐厅美食", "订座", "景点玩乐"]
        case "travel_stays": return ["民宿", "酒店", "温泉旅馆"]
        case "attractions": return ["门票", "一日游", "向导"]
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
        return KaiXRegionDirectory.localizedDisplayName(region, language: language)
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
                    Text(region.map { "正在浏览\(KaiXRegionDirectory.localizedMetroName(for: $0, language: language) ?? $0.cityName)的本地动态和生活信息" } ?? "选择城市后，首页、发现和热榜会围绕本地内容展开")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Text("切换城市")
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
    let primaryCategories: [DiscoverCategory]
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
                DiscoverSectionTitle(title: "城市功能入口", trailing: nil)
                Spacer(minLength: 10)
                Button(action: onMore) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                        Text("更多频道")
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
        }
    }
}

/// The shared row used in both the 8-cell grid and the More sheet.
private struct DiscoverCategoryCell: View {
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
        category.heroTags.prefix(3).joined(separator: " · ")
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
                Text(category.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(category.subtitle)
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
                Text(category.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(category.subtitle)
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
    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(KXColor.accent)
                .frame(width: 36, height: 36)
                .background(KXColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("更多")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("分组查看细分功能")
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
            ("服务商家", ["service", "merchant", "travel_stays", "attractions", "verified_merchant"]),
            ("内容工具", ["poll", "longpost", "anonymous"]),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups, id: \.0) { group in
                        let items = group.1.compactMap { categoryMap[$0] }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.0)
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
            .navigationTitle("全部频道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
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
                title: region.map { "\(KaiXRegionDirectory.localizedMetroName(for: $0, language: language) ?? $0.cityName)热榜" } ?? "当前城市热榜",
                trailing: "查看全部",
                trailingAction: onSeeAll
            )

            if posts.isEmpty {
                HStack(spacing: KXSpacing.md) {
                    Image(systemName: "flame")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(KXColor.heat)
                    Text("正在积累本地热度")
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
                    title: region.map { "\($0.cityName)编辑部精选" } ?? "编辑部精选",
                    trailing: nil
                )
                VStack(spacing: 0) {
                    ForEach(Array(posts.prefix(5).enumerated()), id: \.element.id) { index, post in
                        Button {
                            onOpen(post)
                        } label: {
                            DiscoverEditorialRow(post: post, author: authors[post.authorId])
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

    /// Light, honest label. We never present seed content as a real person —
    /// the badge + the official account name make the source explicit.
    private var badge: String {
        post.seedAuthorType == "editorial" ? "编辑部整理" : "城市助手"
    }

    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            AvatarView(user: author, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(author?.displayName ?? "Machi 城市助手")
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
    @Binding var selection: DiscoverSegment

    var body: some View {
        KXSegmentedControl(DiscoverSegment.allCases, selection: $selection, itemMinWidth: 76, itemHeight: 42) { segment in
            Text(segment.title)
        }
    }
}

private struct DiscoverHotScopePicker: View {
    @Environment(\.appLanguage) private var language
    @Binding var selection: DiscoverHotScope
    let region: KaiXRegionDirectory.Region?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(KXColor.heat)
                Text(L("hot", language))
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(language == .ja ? "直近7日" : language == .en ? "Last 7 days" : "最近 7 天")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(KXColor.softBackground, in: Capsule())
            }
            HStack(spacing: 8) {
                ForEach(DiscoverHotScope.allCases) { scope in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            selection = scope
                        }
                    } label: {
                        Text(scope.title(region: region, language: language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selection == scope ? Color.white : .primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(selection == scope ? KXColor.accent : KXColor.softBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg, elevated: true)
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
                    .buttonStyle(.plain)
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
                Text(item?.title.isEmpty == false ? item?.title ?? "" : (isLocal ? "本地内容" : "入口说明"))
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

    var title: String {
        switch self {
        case .newest: "最新"
        case .priceLow: "价格低"
        case .priceHigh: "价格高"
        case .rating: "评分高"
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

    @State private var items: [KaiXCityListingDTO] = []
    @State private var query = ""
    @State private var selectedCategory = "全部"
    @State private var serviceSection = "all"
    @State private var sortMode: ListingSortMode = .newest
    @State private var filtersOpen = false
    @State private var scopeMode: ListingScopeMode = .city
    @State private var selectedScopeArea = ""
    @State private var selectedScopeRegionCode = ""
    @State private var minimumPrice = ""
    @State private var maximumPrice = ""
    /// 属性级筛选（key → 值，布尔用 "true"，人数下限用 gte_ 前缀），
    /// 与 Web 同一套 attr_<key> 协议，全部交给服务端过滤。
    @State private var attrFilters: [String: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
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
    /// 住宿类目已整体搬去租房页「民宿·短住」，这里不再展示。
    static let serviceSections: [(key: String, title: String, categories: [String])] = [
        ("all", "全部", []),
        ("food", "餐饮预约", KXListingCopy.foodSectionCategories),
        ("travel", "旅行票务", KXListingCopy.travelSectionCategories),
        ("transfer", "接送交通", KXListingCopy.transferSectionCategories),
        ("paperwork", "翻译手续", KXListingCopy.paperworkSectionCategories),
        ("moving", "搬家清洁", KXListingCopy.movingSectionCategories),
        ("life", "生活开通", KXListingCopy.lifeSetupSectionCategories),
        ("beauty", "美容健康", KXListingCopy.beautyHealthSectionCategories),
    ]

    /// 「stays / hotels」是住房频道伪类型，数据实际来自住宿类 local_service。
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
    private var hotelsActive: Bool { baseType == "rental" && activeRentalTab == .hotels }
    private var lodgingActive: Bool { staysActive || hotelsActive }

    /// 真正发给 API 的 listing type。
    private var queryType: String { lodgingActive ? "local_service" : baseType }

    enum RentalTab: String { case homes, stays, hotels }
    @State private var rentalTab: RentalTab?

    private var activeRentalTab: RentalTab {
        rentalTab ?? (listingType == "hotels" ? .hotels : listingType == "stays" ? .stays : .homes)
    }

    private var visibleItems: [KaiXCityListingDTO] {
        let sectionCategories = Self.serviceSections.first { $0.key == serviceSection }?.categories ?? []
        let filtered = items.filter { item in
            // 民宿与酒店独立筛选；服务频道不再重复展示住宿类目。
            if staysActive {
                guard KXListingCopy.isHomestayCategory(item.category) else { return false }
            } else if hotelsActive {
                guard KXListingCopy.isHotelCategory(item.category) else { return false }
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
            return region?.cityName ?? "当前城市"
        case .country:
            return region?.countryName ?? "当前国家"
        case .area:
            return selectedArea?.title ?? "城市圈"
        case .selectedCity:
            return selectedScopeRegion?.cityName ?? "热门城市"
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
        if hotelsActive { return KXListingCopy.hotelCategories }
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    listingControls
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
                .padding(.top, 14)
                .padding(.bottom, chrome.bottomContentPadding + 28)
            }
            .refreshable { await load() }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(regionCode)-\(listingType)-\(activeRentalTab.rawValue)") { await load() }
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
                Text("\(region?.cityName ?? "当前城市") · \(KXListingCopy.title(for: baseType, language))")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(KXListingCopy.subtitle(for: baseType, language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
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

    /// 住房频道三标签：长租房源 / 民宿短住 / 酒店住宿。
    private var rentalTabSwitcher: some View {
        HStack(spacing: 4) {
            rentalTabButton(.homes, title: "长租房源", icon: "house")
            rentalTabButton(.stays, title: "民宿短住", icon: "bed.double")
            rentalTabButton(.hotels, title: "酒店", icon: "building.2")
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
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 10) {
                if baseType == "rental" {
                    rentalTabSwitcher
                }
                // 单行控制条：范围(城市/国家) ····· 筛选 / 排序。
                HStack(spacing: 6) {
                    scopeButton(title: region?.cityName ?? "城市", mode: .city)
                    scopeButton(title: region?.countryName ?? "国家", mode: .country)
                    Spacer(minLength: 6)
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            filtersOpen.toggle()
                        }
                    } label: {
                        Label(activeFilterCount > 0 ? "筛选 \(activeFilterCount)" : "筛选", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(filtersOpen || activeFilterCount > 0 ? KXColor.accent : .primary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(filtersOpen || activeFilterCount > 0 ? KXColor.accent.opacity(0.10) : KXColor.softBackground.opacity(0.88), in: Capsule())
                            .overlay(Capsule().stroke(filtersOpen || activeFilterCount > 0 ? KXColor.accent.opacity(0.35) : KXColor.separator.opacity(0.65), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    Menu {
                        ForEach(availableSortModes) { mode in
                            Button {
                                sortMode = mode
                                Task { await load(quiet: true) }
                            } label: {
                                if sortMode == mode {
                                    Label(mode.title, systemImage: "checkmark")
                                } else {
                                    Text(mode.title)
                                }
                            }
                        }
                    } label: {
                        Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(KXColor.softBackground.opacity(0.88), in: Capsule())
                            .overlay(Capsule().stroke(KXColor.separator.opacity(0.65), lineWidth: 0.7))
                    }
                }
                searchBar
                // 服务分区只展示一级入口，细分类收进下方横滑与「筛选」面板。
                if baseType == "local_service" {
                    serviceSectionChips
                }
                // Persistent category rail: one tap from anywhere, never buried
                // in a collapsed filter panel.
                categoryChips
                if filtersOpen {
                    scopeFilterPanel
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(KXSpacing.md)
            .kxLivingSurface(radius: KXRadius.lg, elevated: true)

            // 轻量结果摘要行：替代原来卡片里占两行的标题块。
            HStack(spacing: 6) {
                Text("\(visibleItems.count) 条结果")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                Text("\(activeScopeLabel) · \(selectedCategory)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 6)
                if activeFilterCount > 0 {
                    Button {
                        query = ""
                        selectedCategory = "全部"
                        scopeMode = .city
                        selectedScopeArea = ""
                        selectedScopeRegionCode = ""
                        minimumPrice = ""
                        maximumPrice = ""
                        attrFilters = [:]
                        Task { await load() }
                    } label: {
                        Label("清空筛选", systemImage: "xmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.livingAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var serviceSectionChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(Self.serviceSections, id: \.key) { section in
                Button {
                    serviceSection = section.key
                    selectedCategory = "全部"
                    Task { await load(quiet: true) }
                } label: {
                    Text(section.title)
                        .font(.caption.weight(.black))
                        .foregroundStyle(serviceSection == section.key && selectedCategory == "全部" ? Color.white : .primary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(
                            serviceSection == section.key && selectedCategory == "全部" ? KXColor.livingWarm : KXColor.livingSoft.opacity(0.88),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(serviceSection == section.key && selectedCategory == "全部" ? Color.clear : KXColor.separator.opacity(0.7), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func scopeButton(title: String, mode: ListingScopeMode) -> some View {
        Button {
            scopeMode = mode
            if mode != .area { selectedScopeArea = "" }
            if mode != .selectedCity { selectedScopeRegionCode = "" }
            Task { await load() }
        } label: {
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(scopeMode == mode ? Color.white : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(scopeMode == mode ? KXColor.livingAccent : KXColor.livingSoft.opacity(0.88), in: Capsule())
                .overlay(Capsule().stroke(scopeMode == mode ? Color.clear : KXColor.separator.opacity(0.65), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.headline.weight(.semibold))
                .foregroundStyle(KXColor.livingAccent)
            TextField(KXListingCopy.searchPlaceholder(for: hotelsActive ? "hotels" : staysActive ? "stays" : baseType, language), text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .font(.subheadline.weight(.semibold))
                // 输入即时过滤已加载页（visibleItems），提交后走服务端全量搜索。
                .onSubmit { Task { await load(quiet: true) } }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    query = ""
                    Task { await load(quiet: true) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, KXSpacing.lg)
        .frame(height: isWorkChannel ? 52 : 48)
        .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isWorkChannel ? KXColor.livingAccent.opacity(0.28) : KXColor.livingInk.opacity(0.09), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var categoryChips: some View {
        let categories = visibleCategoryChips
        // One consistent horizontal chip rail across every channel. The work
        // channel used to wrap this in a nested card, which boxed the chips in
        // awkwardly inside the already-carded control bar.
        KXFadingHScroll {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    categoryChip(category)
                }
            }
        }
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
        return KXListingCopy.categories(for: hotelsActive ? "hotels" : staysActive ? "stays" : baseType)
    }

    private func categoryChip(_ category: String) -> some View {
        Button {
            selectedCategory = category
            Task { await load(quiet: true) }
        } label: {
            Text(KXListingCopy.categoryLabel(category, language))
                .font(.caption.weight(.bold))
                .foregroundStyle(selectedCategory == category ? Color.white : KXColor.livingInk)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(selectedCategory == category ? KXColor.livingAccent : KXColor.livingSoft.opacity(0.9), in: Capsule())
                .overlay(Capsule().stroke(selectedCategory == category ? Color.clear : KXColor.livingInk.opacity(0.08), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private var scopeFilterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(baseType == "rental" ? (lodgingActive ? "每晚价格" : "月租范围") : isWorkChannel ? "薪资范围" : "价格范围")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    filterPriceField(title: "最低", text: $minimumPrice)
                    Text("—")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    filterPriceField(title: "最高", text: $maximumPrice)
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
                    ("short_term_allowed", "可短租"),
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
                Text("城市范围")
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
                                Text(area.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text(area.subtitle)
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
                Text("热门城市")
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
                                Text(city.cityName)
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
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    Button {
                        selection.wrappedValue = option.value
                    } label: {
                        Text(option.label)
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
            Text(title)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(toggles, id: \.key) { item in
                    filterToggle(title: item.label, isOn: attrToggleBinding(item.key))
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
            LoadingView()
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) { Task { await load() } }
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if visibleItems.isEmpty {
            EmptyStateView(
                title: KXListingCopy.emptyTitle(for: hotelsActive ? "hotels" : staysActive ? "stays" : baseType, language),
                subtitle: KXListingCopy.emptySubtitle(for: hotelsActive ? "hotels" : staysActive ? "stays" : baseType, language),
                systemImage: KXListingCopy.icon(for: baseType)
            )
            .frame(maxWidth: .infinity, minHeight: 260)
        } else if isWorkChannel {
            // Indeed-style job cards, Airbnb layout: each role is its own
            // elevated card with breathing room — no outer surface (which
            // would nest card-in-card with KXJobListingRow's own surface).
            LazyVStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    KXJobListingRow(listing: item) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
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
            // 照片主导卡：长租与民宿短住共用同一套视觉语言。
            LazyVStack(spacing: 18) {
                ForEach(visibleItems) { item in
                    KXStayListingCard(listing: item, variant: staysActive ? .stay : .home) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                }
            }
        } else if baseType == "local_service" {
            // 服务卡片：评分、类目、价位、预约 CTA。
            LazyVStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    KXServiceListingCard(listing: item) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    KXStructuredListingRow(listing: item) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                }
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
}

/// One user's published listings of a single type — opened from a tappable
/// count tag on their profile ("出售二手 5" → their secondhand items). Reuses
/// the channel cards but is seller-scoped across all cities (no region filter).
struct UserListingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
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
                    KXEmptyState(title: "暂无发布", subtitle: "TA 还没有发布该类型的内容。", systemImage: "tray")
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
                Text("\(items.count) 条发布")
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
            .padding(.bottom, 28)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            // job tag covers both job + hiring; fetch both and merge.
            if listingType == "job" {
                async let jobs = KaiXAPIClient.shared.listingsPage(type: "job", sellerId: userId, limit: 50)
                async let hiring = KaiXAPIClient.shared.listingsPage(type: "hiring", sellerId: userId, limit: 50)
                items = (try await jobs).items + (try await hiring).items
            } else {
                items = try await KaiXAPIClient.shared.listingsPage(type: listingType, sellerId: userId, limit: 50).items
            }
            isLoading = false
        } catch {
            errorMessage = error.kaixUserMessage
            isLoading = false
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
                    router.setActiveTab(.profile)
                    router.popToRoot(.profile)
                    router.open(.myInquiries, in: .profile)
                },
                onOpenConversation: {
                    guard !receipt.conversationId.isEmpty else { return }
                    inquiryReceipt = nil
                    router.setActiveTab(.messages)
                    router.open(.conversation(conversationId: receipt.conversationId), in: .messages)
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

private enum ListingIntakeLocalizer {
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

private enum ListingMediaUploadPhase: Equatable {
    case idle
    case preparing
    case uploading(Double)
    case completing
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "待上传"
        case .preparing: return "准备中"
        case .uploading(let progress): return "上传中 \(Int(progress * 100))%"
        case .completing: return "确认中"
        case .ready: return "已上传"
        case .failed(let message): return message
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct EditCityListingRouteView: View {
    let listingId: String
    let currentUser: UserEntity

    @State private var listing: KaiXCityListingDTO?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let listing {
                CreateCityListingView(
                    listingType: listing.type,
                    citySlug: listing.region_code ?? listing.regionCode ?? listing.city_slug ?? listing.citySlug,
                    currentUser: currentUser,
                    existingListing: listing
                )
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) {
                    Task { await load() }
                }
            } else {
                KXInlineLoader()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .kxPageBackground()
            }
        }
        .task(id: listingId) { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            listing = try await KaiXAPIClient.shared.cityListing(listingId)
        } catch {
            errorMessage = error.kaixUserMessage
        }
    }
}

/// 菜单 / 团购套餐:发布页里「一行一项、| 分隔」<-> 结构化 JSON 字符串。
/// 发布时编码成 JSON(后端 normalize_listing_attributes 解析回数组),
/// 编辑时把已存数组还原成多行文本。
enum KXMerchantInput {
    static func encodeMenu(_ text: String) -> String {
        let dishes: [[String: String]] = text.components(separatedBy: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let p = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = p.first, !name.isEmpty else { return nil }
            var d = ["name": name]
            if p.count > 1, !p[1].isEmpty { d["price"] = p[1] }
            if p.count > 2, !p[2].isEmpty { d["desc"] = p[2] }
            return d
        }
        guard !dishes.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: dishes),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    static func encodePackages(_ text: String) -> String {
        let pkgs: [[String: String]] = text.components(separatedBy: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let p = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let title = p.first, !title.isEmpty else { return nil }
            var d = ["title": title]
            if p.count > 1, !p[1].isEmpty { d["price"] = p[1] }
            if p.count > 2, !p[2].isEmpty { d["original_price"] = p[2] }
            if p.count > 3, !p[3].isEmpty { d["includes"] = p[3] }
            return d
        }
        guard !pkgs.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: pkgs),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    static func menuLines(_ listing: KaiXCityListingDTO) -> String {
        listing.menuDishes.map { [$0.name, $0.price, $0.desc].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " | ") }.joined(separator: "\n")
    }

    static func packageLines(_ listing: KaiXCityListingDTO) -> String {
        listing.groupPackages.map { [$0.title, $0.price, $0.original_price, $0.includes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " | ") }.joined(separator: "\n")
    }
}

struct CreateCityListingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState
    let listingType: String
    let citySlug: String?
    let currentUser: UserEntity
    let existingListing: KaiXCityListingDTO?

    init(
        listingType: String,
        citySlug: String?,
        currentUser: UserEntity,
        existingListing: KaiXCityListingDTO? = nil
    ) {
        self.listingType = listingType
        self.citySlug = citySlug
        self.currentUser = currentUser
        self.existingListing = existingListing
    }

    @State private var title = ""
    @State private var category = ""
    @State private var price = ""
    @State private var location = ""
    @State private var description = ""
    @State private var listingMode = "出售"
    @State private var condition = "良好"
    @State private var brandModel = ""
    @State private var originalPrice = ""
    @State private var purchaseTime = ""
    @State private var accessories = ""
    @State private var defectNote = ""
    @State private var secondhandAvailableTime = ""
    @State private var secondhandPickupNotes = ""
    @State private var pickupAvailable = true
    @State private var secondhandShippingAvailable = false
    @State private var priceNegotiable = false
    @State private var layout = "1K"
    @State private var area = ""
    @State private var station = ""
    @State private var moveIn = ""
    @State private var employmentType = "兼职"
    @State private var japaneseLevel = "N3"
    @State private var workingHours = ""
    @State private var companyName = ""
    @State private var shareAllowed = false
    @State private var shortTermAllowed = false
    @State private var furnished = false
    @State private var visaSupport = false
    @State private var noExperienceOK = false
    @State private var studentOK = false
    @State private var remoteOK = false
    @State private var jobHolidays = ""
    @State private var jobBenefits = ""
    @State private var serviceBusinessName = ""
    @State private var serviceType = ""
    @State private var serviceCategorySection = KXListingCopy.serviceCreateSections.first?.id ?? "food"
    @State private var serviceArea = ""
    @State private var priceUnit = "预约咨询"
    @State private var availability = ""
    @State private var certifiedProvider = false
    @State private var serviceProcess = ""
    @State private var cancellationRule = ""
    @State private var openHours = ""
    @State private var priceRange = ""
    @State private var nearStation = ""
    @State private var storePhone = ""
    @State private var reservationRequired = false
    @State private var reservationNote = ""
    @State private var menuText = ""
    @State private var packagesText = ""
    @State private var languages = ""
    @State private var roomType = ""
    @State private var maxGuests = ""
    @State private var checkInTime = "15:00"
    @State private var checkOutTime = "10:00"
    @State private var minimumStay = "1 晚"
    @State private var amenities = ""
    @State private var inventoryNote = ""
    @State private var breakfastIncluded = false
    @State private var instantConfirmation = false
    @State private var ticketType = ""
    @State private var duration = ""
    @State private var meetingPoint = ""
    @State private var pickupService = false
    @State private var includedItems = ""
    @State private var notIncluded = ""
    @State private var userPrepare = ""
    @State private var licenseNote = ""
    @State private var airportRoute = ""
    @State private var vehicleType = ""
    @State private var passengerCount = ""
    @State private var luggageCount = ""
    @State private var flightInfoNote = ""
    @State private var waitingRule = ""
    @State private var surchargeNote = ""
    @State private var documentType = ""
    @State private var requiredMaterials = ""
    @State private var deliveryTime = ""
    @State private var noResultGuarantee = false
    @State private var propertySize = ""
    @State private var itemVolume = ""
    @State private var vehicleStaff = ""
    @State private var setupType = ""
    @State private var cannotGuarantee = ""
    @State private var beautyService = ""
    @State private var medicalDisclaimer = ""
    @State private var serviceTarget = ""
    @State private var merchantName = ""
    @State private var discountInfo = ""
    @State private var validUntil = ""
    @State private var usageRules = ""
    @State private var merchantVerified = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var mediaDrafts: [MediaDraft] = []
    @State private var mediaUploadPhases: [String: ListingMediaUploadPhase] = [:]
    @State private var uploadedMedia: [String: KaiXMediaDTO] = [:]
    @State private var existingMedia: [KaiXListingMediaDTO] = []
    @State private var didHydrateExisting = false
    @State private var isSubmitting = false
    @State private var message: String?

    private var region: KaiXRegionDirectory.Region? {
        if let citySlug,
           let region = KaiXRegionDirectory.resolve(regionCode: citySlug) {
            return region
        }
        return RegionStore.shared.current ?? KaiXRegionDirectory.resolve(regionCode: "jp.tokyo.tokyo")
    }

    private var isEditing: Bool { existingListing != nil }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && region != nil
            && typeRequiredFieldsReady
            && !hasBlockingMediaUpload
            && !isSubmitting
    }

    private var hasBlockingMediaUpload: Bool {
        mediaUploadPhases.values.contains { phase in
            if case .failed = phase { return true }
            return false
        }
    }

    private var imageLimit: Int {
        if listingType == "rental" { return 20 }
        if listingType == "work" || listingType == "job" || listingType == "hiring" || listingType == "discount" { return 5 }
        return 10
    }

    private var typeRequiredFieldsReady: Bool {
        let filled: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if listingType == "rental" {
            return filled(layout) && filled(area) && filled(station) && filled(moveIn)
        }
        if listingType == "work" || listingType == "job" || listingType == "hiring" {
            return filled(companyName) && filled(workingHours)
        }
        if listingType == "local_service" {
            guard let vertical = serviceVertical, filled(category) else { return false }
            switch vertical {
            case .foodRestaurant, .diningBooking:
                return filled(serviceBusinessName) && filled(serviceArea)
            case .lodging:
                return filled(serviceBusinessName) && filled(roomType) && filled(maxGuests)
            case .attractionTicket, .dayTour:
                return filled(serviceBusinessName) && filled(ticketType) && filled(availability)
            case .airportTransfer:
                return filled(serviceBusinessName) && filled(airportRoute) && filled(serviceArea)
            case .paperworkTranslation:
                return filled(serviceBusinessName) && filled(languages) && filled(documentType)
            case .movingCleaning:
                return filled(serviceBusinessName) && filled(serviceArea)
            case .lifeSetup:
                return filled(serviceBusinessName) && filled(serviceArea) && filled(setupType)
            case .beautyHealth:
                return filled(serviceBusinessName) && filled(serviceArea) && filled(beautyService)
            case .petFamily:
                return filled(serviceBusinessName) && filled(serviceArea)
            }
        }
        if listingType == "discount" {
            return filled(merchantName) && filled(discountInfo) && filled(validUntil)
        }
        if listingType == "secondhand" {
            return filled(category) && filled(price) && filled(condition)
        }
        return true
    }

    private var isStayService: Bool {
        serviceVertical == .lodging
    }

    private var serviceVertical: KXListingCopy.ServiceVertical? {
        guard listingType == "local_service" else { return nil }
        return KXListingCopy.serviceVertical(category: category, serviceType: serviceType)
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { category },
            set: { nextValue in
                if listingType == "local_service" {
                    applyServiceCategory(nextValue)
                } else {
                    category = nextValue
                }
            }
        )
    }

    private func applyServiceCategory(_ nextCategory: String) {
        let previousVertical = serviceVertical
        let cleanCategory = nextCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanCategory.isEmpty {
            category = ""
            serviceType = ""
            return
        }
        let nextVertical = KXListingCopy.serviceVertical(category: cleanCategory, serviceType: cleanCategory)
        serviceCategorySection = KXListingCopy.serviceCreateSectionKey(for: cleanCategory) ?? serviceCategorySection
        category = cleanCategory
        serviceType = cleanCategory
        if previousVertical != nextVertical {
            clearServiceSpecificFields()
        }
    }

    private func applyServiceType(_ nextType: String) {
        let previousVertical = serviceVertical
        let nextVertical = KXListingCopy.serviceVertical(category: nextType, serviceType: nextType)
        serviceCategorySection = KXListingCopy.serviceCreateSectionKey(for: nextType) ?? serviceCategorySection
        serviceType = nextType
        category = nextType
        if previousVertical != nextVertical {
            clearServiceSpecificFields()
        }
    }

    private var activeServiceCreateSection: KXListingCopy.ServiceCreateSection {
        if let fromCategory = KXListingCopy.serviceCreateSection(for: category) {
            return fromCategory
        }
        if let fromState = KXListingCopy.serviceCreateSections.first(where: { $0.id == serviceCategorySection }) {
            return fromState
        }
        return KXListingCopy.serviceCreateSections[0]
    }

    private func selectServiceCreateSection(_ section: KXListingCopy.ServiceCreateSection) {
        serviceCategorySection = section.id
        guard !section.categories.contains(category), let first = section.categories.first else { return }
        applyServiceCategory(first)
    }

    private func clearServiceSpecificFields() {
        serviceArea = ""
        priceUnit = "预约咨询"
        availability = ""
        serviceProcess = ""
        cancellationRule = ""
        openHours = ""
        priceRange = ""
        nearStation = ""
        storePhone = ""
        reservationRequired = false
        reservationNote = ""
        menuText = ""
        packagesText = ""
        languages = ""
        roomType = ""
        maxGuests = ""
        checkInTime = "15:00"
        checkOutTime = "10:00"
        minimumStay = "1 晚"
        amenities = ""
        inventoryNote = ""
        breakfastIncluded = false
        instantConfirmation = false
        ticketType = ""
        duration = ""
        meetingPoint = ""
        pickupService = false
        includedItems = ""
        notIncluded = ""
        userPrepare = ""
        licenseNote = ""
        airportRoute = ""
        vehicleType = ""
        passengerCount = ""
        luggageCount = ""
        flightInfoNote = ""
        waitingRule = ""
        surchargeNote = ""
        documentType = ""
        requiredMaterials = ""
        deliveryTime = ""
        noResultGuarantee = false
        propertySize = ""
        itemVolume = ""
        vehicleStaff = ""
        setupType = ""
        cannotGuarantee = ""
        beautyService = ""
        medicalDisclaimer = ""
        serviceTarget = ""
    }

    private var typeAccent: Color {
        switch listingType {
        case "rental":
            return KXColor.accent
        case "work", "job", "hiring":
            return KXColor.rankViolet
        case "local_service":
            return KXColor.heat
        case "discount":
            return KXColor.rankCoral
        default:
            return KXColor.rankTeal
        }
    }

    private func messageIsPositive(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return text.contains("成功")
            || text.contains("提交")
            || text.contains("保存")
            || text.contains("送信")
            || text.contains("保存")
            || lowercased.contains("success")
            || lowercased.contains("submitted")
            || lowercased.contains("saved")
    }

    private var requiredProgress: (done: Int, total: Int) {
        let filled: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var values = [filled(title), filled(location)]
        if listingType == "rental" {
            values += [filled(layout), filled(area), filled(station), filled(moveIn)]
        } else if listingType == "work" || listingType == "job" || listingType == "hiring" {
            values += [filled(companyName), filled(workingHours)]
        } else if listingType == "local_service" {
            values += [filled(category)]
            if let vertical = serviceVertical {
                switch vertical {
                case .foodRestaurant, .diningBooking:
                    values += [filled(serviceBusinessName), filled(serviceArea)]
                case .lodging:
                    values += [filled(serviceBusinessName), filled(roomType), filled(maxGuests)]
                case .attractionTicket, .dayTour:
                    values += [filled(serviceBusinessName), filled(ticketType), filled(availability)]
                case .airportTransfer:
                    values += [filled(serviceBusinessName), filled(airportRoute), filled(serviceArea)]
                case .paperworkTranslation:
                    values += [filled(serviceBusinessName), filled(languages), filled(documentType)]
                case .movingCleaning, .petFamily:
                    values += [filled(serviceBusinessName), filled(serviceArea)]
                case .lifeSetup:
                    values += [filled(serviceBusinessName), filled(serviceArea), filled(setupType)]
                case .beautyHealth:
                    values += [filled(serviceBusinessName), filled(serviceArea), filled(beautyService)]
                }
            } else {
                values += [false]
            }
        } else if listingType == "discount" {
            values += [filled(merchantName), filled(discountInfo), filled(validUntil)]
        } else if listingType == "secondhand" {
            values += [filled(category), filled(price), filled(condition)]
        }
        return (values.filter { $0 }.count, values.count)
    }

    private var missingRequiredCopy: String {
        let filled: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !filled(title) { return KXListingCopy.pickText(language, "请先补充标题", "タイトルを入力してください", "Add a title first") }
        if !filled(location) { return KXListingCopy.pickText(language, "请补充地区、车站或交易地点", "エリア、駅、または受け渡し場所を入力してください", "Add an area, station, or meetup location") }
        if region == nil { return KXListingCopy.pickText(language, "请先选择可发布的城市", "投稿先の都市を選んでください", "Choose a city before posting") }
        if listingType == "rental" && !typeRequiredFieldsReady { return KXListingCopy.pickText(language, "请补充户型、面积、最近车站和入住时间", "間取り、面積、最寄り駅、入居時期を入力してください", "Add layout, size, nearest station, and move-in date") }
        if (listingType == "work" || listingType == "job" || listingType == "hiring") && !typeRequiredFieldsReady { return KXListingCopy.pickText(language, "请补充公司/店铺名和工作时间", "会社・店舗名と勤務時間を入力してください", "Add company/store name and working hours") }
        if listingType == "local_service" && serviceVertical == nil { return KXListingCopy.pickText(language, "请先选择商家与服务细分类", "店舗・サービスの細分類を選んでください", "Choose a business/service subcategory") }
        if listingType == "local_service" && !typeRequiredFieldsReady { return KXListingCopy.pickText(language, "请补齐当前服务分类的必填字段", "現在のサービス分類の必須項目を入力してください", "Complete the required fields for this service type") }
        if listingType == "discount" && !typeRequiredFieldsReady { return KXListingCopy.pickText(language, "请补充商家、优惠内容和有效期", "店舗、特典内容、有効期限を入力してください", "Add merchant, deal details, and validity") }
        if listingType == "secondhand" && !typeRequiredFieldsReady { return KXListingCopy.pickText(language, "请补充分类、价格和新旧程度，免费送可填 0", "カテゴリ、価格、状態を入力してください。無料譲渡は 0 で登録できます", "Add category, price, and condition. Use 0 for free items") }
        return KXListingCopy.pickText(language, "信息完整后即可提交", "情報がそろうと送信できます", "You can submit once the details are complete")
    }

    var body: some View {
        VStack(spacing: 0) {
            createHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    createHero
                    photoSection
                    basicInfoSection
                    typeFields
                    validationInlineHint
                    safetySection
                    if let message {
                        Text(message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(messageIsPositive(message) ? KXColor.accent : KXColor.heat)
                            .padding(KXSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background((messageIsPositive(message) ? KXColor.accent : KXColor.heat).opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, canSubmit || isSubmitting ? 22 : chrome.bottomContentPadding + 22)
            }
            if canSubmit || isSubmitting {
                submitBar
            }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        // 工作台等入口用 NavigationLink 直推本页(不走 router 的
        // requiresHiddenTabBar),不收起悬浮 TabBar 会压住底部提交栏。
        .kxHidesTabBar(reason: .custom("focus-form"))
        .onChange(of: pickerItems) { _, newItems in
            Task { await loadImages(newItems) }
        }
        .task(id: existingListing?.id) {
            hydrateExistingListingIfNeeded()
        }
    }

    private var createHeader: some View {
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
                Text(isEditing ? KXListingCopy.pickText(language, "编辑发布", "投稿を編集", "Edit listing") : KXListingCopy.createTitle(for: listingType, language))
                    .font(.headline.weight(.semibold))
                Text(region.map { KaiXRegionDirectory.localizedHeaderLabel($0, language: language) } ?? KXListingCopy.pickText(language, "选择城市后发布", "都市を選んで投稿", "Choose a city to post"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    private var createHero: some View {
        let progress = requiredProgress
        return HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: KXListingCopy.icon(for: listingType))
                .font(.title3.weight(.bold))
                .foregroundStyle(typeAccent)
                .frame(width: 52, height: 52)
                .background(typeAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(isEditing ? KXListingCopy.pickText(language, "完善并保存修改", "内容を整えて保存", "Review and save changes") : KXListingCopy.createTitle(for: listingType, language))
                        .font(.title3.weight(.black))
                    Spacer()
                    Text("\(progress.done)/\(progress.total)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(typeAccent)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(typeAccent.opacity(0.10), in: Capsule())
                }
                Text(KXListingCopy.createGuidance(for: listingType, language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .tint(typeAccent)
            }
        }
        .padding(KXSpacing.lg)
        .kxGlassSurface(radius: 24, elevated: true)
    }

    private var photoSection: some View {
        KXListingSection(title: KXListingCopy.pickText(language, "图片与视频", "写真・動画", "Photos & video"), icon: "photo.on.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: imageLimit, matching: .any(of: [.images, .videos])) {
                    HStack(spacing: KXSpacing.md) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(typeAccent)
                            .frame(width: 42, height: 42)
                            .background(typeAccent.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mediaDrafts.isEmpty ? KXListingCopy.pickText(language, "添加图片或视频", "写真または動画を追加", "Add photos or video") : KXListingCopy.pickText(language, "继续添加媒体", "メディアを追加", "Add more media"))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(KXListingCopy.pickText(language, "最多 \(imageLimit) 个媒体，其中最多 1 个视频，第一项作为封面。避免包含身份证、护照等敏感信息。", "最大 \(imageLimit) 件まで、動画は 1 件まで。最初のメディアがカバーになります。身分証やパスポートなどの個人情報は入れないでください。", "Up to \(imageLimit) media files, including at most 1 video. The first item becomes the cover. Avoid IDs, passports, or sensitive information."))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(KXSpacing.md)
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                    .background(KXColor.softBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(typeAccent.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    }
                }
                .buttonStyle(.plain)

                if !existingMedia.isEmpty || !mediaDrafts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(existingMedia.enumerated()), id: \.element.id) { index, item in
                                ZStack {
                                    MediaImageView(url: URL(string: item.thumbnail_url ?? item.thumbnailUrl ?? item.url))
                                    if (item.media_type ?? item.mediaType ?? item.type) == "video" {
                                        Image(systemName: "play.fill")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 38, height: 38)
                                            .background(.black.opacity(0.58), in: Circle())
                                    }
                                }
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .overlay(alignment: .topLeading) {
                                    Text(index == 0 ? KXListingCopy.pickText(language, "封面", "カバー", "Cover") : "\(index + 1)")
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .frame(height: 20)
                                        .background(.black.opacity(0.52), in: Capsule())
                                        .padding(7)
                                }
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            existingMedia.removeAll { $0.id == item.id }
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(.primary)
                                            .frame(width: 28, height: 28)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                }
                            }
                            ForEach(Array(mediaDrafts.enumerated()), id: \.element.id) { index, draft in
                                ZStack {
                                    if let image = UIImage(contentsOfFile: draft.thumbnailURL.path) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Color.secondary.opacity(0.12)
                                    }
                                    if draft.type == .video {
                                        Image(systemName: "play.fill")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 38, height: 38)
                                            .background(.black.opacity(0.58), in: Circle())
                                    }
                                }
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .overlay(alignment: .topLeading) {
                                    Text(existingMedia.isEmpty && index == 0 ? KXListingCopy.pickText(language, "封面", "カバー", "Cover") : "\(existingMedia.count + index + 1)")
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .frame(height: 20)
                                        .background(.black.opacity(0.52), in: Capsule())
                                        .padding(7)
                                }
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            mediaDrafts.removeAll { $0.id == draft.id }
                                            mediaUploadPhases.removeValue(forKey: draft.id)
                                            uploadedMedia.removeValue(forKey: draft.id)
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(.primary)
                                            .frame(width: 28, height: 28)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                }
                                .overlay(alignment: .bottom) {
                                    if let phase = mediaUploadPhases[draft.id], phase != .idle {
                                        Text(phase.label)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(phase.isFailure ? KXColor.heat : .white)
                                            .lineLimit(1)
                                            .padding(.horizontal, 7)
                                            .frame(height: 22)
                                            .frame(maxWidth: .infinity)
                                            .background(.black.opacity(0.58))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var basicInfoSection: some View {
        KXListingSection(title: KXListingCopy.pickText(language, "基本信息", "基本情報", "Basic info"), icon: "square.and.pencil") {
            VStack(spacing: 12) {
                KXListingFormField(title: KXListingCopy.pickText(language, "标题", "タイトル", "Title"), placeholder: KXListingCopy.titlePlaceholder(for: listingType, language), icon: "text.cursor", text: $title)
                KXListingFormField(title: KXListingCopy.pickText(language, "分类", "カテゴリ", "Category"), placeholder: KXListingCopy.categoryPlaceholder(for: listingType, language), icon: "square.grid.2x2", text: categoryBinding)
                listingCategorySelector
                KXListingFormField(title: listingType == "rental" ? KXListingCopy.pickText(language, "租金", "家賃", "Rent") : KXListingCopy.pickText(language, "价格", "価格", "Price"), placeholder: KXListingCopy.pricePlaceholder(for: listingType, language), icon: "yensign.circle", text: $price, keyboard: .decimalPad)
                KXListingFormField(title: KXListingCopy.pickText(language, "地区 / 车站 / 交易地点", "エリア / 駅 / 受け渡し場所", "Area / station / meetup"), placeholder: KXListingCopy.pickText(language, "例如 新宿站附近、池袋、线上咨询", "例：新宿駅近く、池袋、オンライン相談", "e.g. near Shinjuku Station, Ikebukuro, online"), icon: "location", text: $location)
                KXListingFormField(title: KXListingCopy.pickText(language, "描述", "説明", "Description"), placeholder: KXListingCopy.descriptionPlaceholder(for: listingType, language), icon: "text.alignleft", text: $description, lineLimit: 4...8)
            }
        }
    }

    @ViewBuilder
    private var listingCategorySelector: some View {
        if listingType == "local_service" {
            serviceCreateCategorySelector
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(KXListingCopy.categories(for: listingType).filter { $0 != "全部" }, id: \.self) { chip in
                        Button {
                            category = chip
                        } label: {
                            Text(KXListingCopy.categoryLabel(chip, language))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(category == chip ? Color.white : .primary)
                                .padding(.horizontal, 11)
                                .frame(height: 28)
                                .background(category == chip ? KXColor.accent : KXColor.softBackground.opacity(0.88), in: Capsule())
                                .overlay(Capsule().stroke(category == chip ? Color.clear : KXColor.separator.opacity(0.6), lineWidth: 0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var serviceCreateCategorySelector: some View {
        let activeSection = activeServiceCreateSection
        return VStack(alignment: .leading, spacing: 10) {
            Label(KXListingCopy.pickText(language, "一级分类", "大カテゴリ", "Primary category"), systemImage: "square.grid.3x3")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(KXListingCopy.serviceCreateSections) { section in
                        let isSelected = activeSection.id == section.id
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                selectServiceCreateSection(section)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: section.icon)
                                    .font(.caption.weight(.black))
                                Text(section.label(language))
                                    .font(.caption.weight(.black))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSelected ? Color.white : KXColor.livingInk)
                            .padding(.horizontal, 13)
                            .frame(height: 38)
                            .background(isSelected ? KXColor.livingInk : KXColor.softBackground.opacity(0.88), in: Capsule())
                            .overlay(Capsule().stroke(isSelected ? Color.clear : KXColor.separator.opacity(0.65), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(typeAccent)
                    .frame(width: 18, height: 18)
                Text(activeSection.subtitle(language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(typeAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Label(KXListingCopy.pickText(language, "二级分类", "サブカテゴリ", "Subcategory"), systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(activeSection.categories, id: \.self) { chip in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            applyServiceCategory(chip)
                        }
                    } label: {
                        Text(KXListingCopy.categoryLabel(chip, language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(category == chip ? Color.white : .primary)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(category == chip ? typeAccent : KXColor.softBackground.opacity(0.82), in: Capsule())
                            .overlay(Capsule().stroke(category == chip ? Color.clear : KXColor.separator.opacity(0.58), lineWidth: 0.65))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var safetySection: some View {
        KXListingSection(title: KXListingCopy.pickText(language, "安全确认", "安全確認", "Safety check"), icon: "shield.checkered") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(KXListingCopy.safetyTips(for: listingType, language), id: \.self) { tip in
                    KXListingHintRow(text: tip, icon: "checkmark.circle.fill", tint: KXColor.accent)
                }
                KXListingHintRow(
                    text: KXListingCopy.pickText(language, "Machi 只做信息发布、联系、收藏、举报和审核，不代收交易款、押金或保证金。", "Machi は情報掲載、連絡、保存、通報、審査のみを行い、取引代金・敷金・保証金は預かりません。", "Machi only supports listing, contact, saving, reporting, and review. It does not hold payments, deposits, or guarantees."),
                    icon: "exclamationmark.triangle.fill",
                    tint: KXColor.heat
                )
            }
        }
    }

    @ViewBuilder
    private var validationInlineHint: some View {
        if !canSubmit {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: hasBlockingMediaUpload ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(hasBlockingMediaUpload ? KXColor.heat : typeAccent)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(KXListingCopy.pickText(language, "还差一步", "あと一歩", "One more step"))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.primary)
                    Text(hasBlockingMediaUpload ? KXListingCopy.pickText(language, "有媒体上传失败，请删除后重新选择。", "アップロードに失敗したメディアがあります。削除して選び直してください。", "Some media failed to upload. Remove it and choose again.") : missingRequiredCopy)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(KXSpacing.md)
            .background(typeAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(typeAccent.opacity(0.16), lineWidth: 0.8)
            }
        }
    }

    private var submitBar: some View {
        VStack(spacing: 8) {
            if !canSubmit {
                Text(hasBlockingMediaUpload ? KXListingCopy.pickText(language, "有媒体上传失败，请删除后重新选择。", "アップロードに失敗したメディアがあります。削除して選び直してください。", "Some media failed to upload. Remove it and choose again.") : missingRequiredCopy)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { Task { await submit() } } label: {
                HStack(spacing: 8) {
                    if isSubmitting { KXSpinner(size: 18, lineWidth: 2.2, tint: .white) }
                    Text(isSubmitting ? KXListingCopy.pickText(language, "提交中", "送信中", "Submitting") : isEditing ? KXListingCopy.pickText(language, "保存修改", "変更を保存", "Save changes") : KXListingCopy.submitLabel(for: listingType, language))
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSubmit ? typeAccent : Color.secondary.opacity(0.18), in: Capsule())
                .foregroundStyle(canSubmit ? Color.white : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(KXColor.pageBackground.opacity(0.98))
        .overlay(alignment: .top) { Divider().opacity(0.16) }
    }

    @ViewBuilder
    private var typeFields: some View {
        if listingType == "rental" {
            KXListingSection(title: "房源信息", icon: "house") {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        KXListingFormField(title: "户型", placeholder: "1K / 2LDK", icon: "square.split.2x2", text: $layout)
                        KXListingFormField(title: "面积", placeholder: "24", icon: "ruler", text: $area, keyboard: .decimalPad)
                    }
                    KXListingFormField(title: "最近车站", placeholder: "例如 池袋站 步行 8 分钟", icon: "tram", text: $station)
                    KXListingFormField(title: "入住时间", placeholder: "例如 7 月上旬 / 即可入住", icon: "calendar", text: $moveIn)
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "可合租", icon: "person.2", isOn: $shareAllowed, tint: typeAccent)
                        KXListingToggleChip(title: "可短租", icon: "calendar.badge.clock", isOn: $shortTermAllowed, tint: typeAccent)
                    }
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "家具家电", icon: "bed.double", isOn: $furnished, tint: typeAccent)
                    }
                    KXListingHintRow(text: "完整填写车站、面积和入住时间，能明显减少重复私信询问。", icon: "sparkles", tint: typeAccent)
                }
            }
        } else if listingType == "work" || listingType == "job" || listingType == "hiring" {
            KXListingSection(title: "职位信息", icon: "briefcase") {
                VStack(spacing: 12) {
                    KXListingFormField(title: "公司 / 店铺名", placeholder: "例如 新宿咖啡店 / 株式会社...", icon: "building.2", text: $companyName)
                    KXListingFormField(title: "工作时间", placeholder: "例如 周末 10:00-18:00", icon: "clock", text: $workingHours)
                    KXListingFormField(title: "休日休假", placeholder: "完全周休二日 / 轮班制", icon: "calendar", text: $jobHolidays)
                    KXListingFormField(title: "福利待遇", placeholder: "社保完备、员工餐、交通费支给", icon: "gift", text: $jobBenefits)
                    KXListingChoiceRow(title: "雇佣形式", icon: "person.text.rectangle", options: ["兼职", "全职", "派遣", "实习"], selection: $employmentType, tint: typeAccent)
                    KXListingChoiceRow(title: "日语要求", icon: "character.bubble", options: ["不限", "N5", "N4", "N3", "N2", "N1"], selection: $japaneseLevel, tint: typeAccent)
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "签证支持", icon: "checkmark.shield", isOn: $visaSupport, tint: typeAccent)
                        KXListingToggleChip(title: "无经验可", icon: "figure.wave", isOn: $noExperienceOK, tint: typeAccent)
                    }
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "留学生可", icon: "graduationcap", isOn: $studentOK, tint: typeAccent)
                        KXListingToggleChip(title: "可远程", icon: "laptopcomputer.and.iphone", isOn: $remoteOK, tint: typeAccent)
                    }
                }
            }
        } else if listingType == "local_service" {
            if let vertical = serviceVertical {
                KXListingSection(title: KXListingCopy.serviceVerticalLabel(vertical, language), icon: "calendar.badge.clock") {
                    VStack(spacing: 12) {
                        KXListingFormField(title: "服务方名称", placeholder: "个人 / 店铺 / 公司名称", icon: "person.crop.square", text: $serviceBusinessName)
                        KXListingChoiceRow(
                            title: "细分类 / 服务类型",
                            icon: "line.3.horizontal.decrease.circle",
                            options: KXListingCopy.serviceTypeOptions(for: vertical),
                            selection: Binding(get: { serviceType }, set: { applyServiceType($0) }),
                            tint: typeAccent
                        )

                        switch vertical {
                        case .foodRestaurant:
                            KXListingFormField(title: "服务范围", placeholder: "东京 23 区 / 店内用餐 / 外带自取", icon: "map", text: $serviceArea)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "营业时间", placeholder: "11:00-22:00 / 周一休", icon: "clock", text: $openHours)
                                KXListingFormField(title: "人均 / 价位", placeholder: "人均 ¥2,500-3,500", icon: "yensign.circle", text: $priceRange)
                            }
                            KXListingFormField(title: "最近车站", placeholder: "新宿站东口步行 5 分钟", icon: "tram", text: $nearStation)
                            KXListingFormField(title: "到店电话", placeholder: "03-1234-5678", icon: "phone", text: $storePhone)
                            KXListingToggleChip(title: "仅限预约制", icon: "calendar.badge.clock", isOn: $reservationRequired, tint: typeAccent)
                            KXListingFormField(title: "预约说明", placeholder: "如何预约、可预约时段、几人起订、是否需要定金", icon: "text.bubble", text: $reservationNote, lineLimit: 2...4)
                            KXListingFormField(title: "菜单（每行：菜名 | 价格 | 备注）", placeholder: "麻婆豆腐 | ¥980\n口水鸡 | ¥1,080 | 微辣", icon: "fork.knife", text: $menuText, lineLimit: 3...10)
                            KXListingFormField(title: "团购套餐（每行：套餐名 | 现价 | 原价 | 包含）", placeholder: "双人套餐 | ¥3,980 | ¥5,200 | 4菜1汤+2饮料", icon: "ticket", text: $packagesText, lineLimit: 3...8)
                            KXListingFormField(title: "服务语言", placeholder: "中文 / 日文 / 英文", icon: "character.bubble", text: $languages)
                            KXListingToggleChip(title: "认证商家", icon: "checkmark.seal", isOn: $certifiedProvider, tint: typeAccent)

                        case .diningBooking:
                            KXListingFormField(title: "服务范围", placeholder: "东京 23 区 / 线上预约 / 到店点评", icon: "map", text: $serviceArea)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "营业时间", placeholder: "11:00-22:00 / 周一休", icon: "clock", text: $openHours)
                                KXListingFormField(title: "价格区间", placeholder: "人均 ¥2,500-3,500", icon: "yensign.circle", text: $priceRange)
                            }
                            KXListingFormField(title: "最近车站", placeholder: "新宿站东口步行 5 分钟", icon: "tram", text: $nearStation)
                            KXListingFormField(title: "到店电话", placeholder: "03-1234-5678", icon: "phone", text: $storePhone)
                            KXListingFormField(title: "可预约时间", placeholder: "平日晚上 / 周末 / 需提前 2 天", icon: "calendar.badge.clock", text: $availability)
                            KXListingToggleChip(title: "仅限预约制", icon: "calendar.badge.clock", isOn: $reservationRequired, tint: typeAccent)
                            KXListingFormField(title: "预约说明", placeholder: "如何预约、可预约时段、几人起订、是否需要定金", icon: "text.bubble", text: $reservationNote, lineLimit: 2...4)
                            KXListingFormField(title: "服务流程", placeholder: "预约确认、到店、点评或优惠使用流程", icon: "list.bullet.clipboard", text: $serviceProcess, lineLimit: 3...6)
                            KXListingFormField(title: "取消/退款规则", placeholder: "例如 前一天可取消，定金不可退请写清", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)
                            KXListingFormField(title: "服务语言", placeholder: "中文 / 日文 / 英文", icon: "character.bubble", text: $languages)
                            KXListingToggleChip(title: "认证服务方", icon: "checkmark.seal", isOn: $certifiedProvider, tint: typeAccent)

                        case .lodging:
                            HStack(spacing: 10) {
                                KXListingFormField(title: "房型", placeholder: "大床房 / 双床房 / 整套民宿", icon: "bed.double", text: $roomType)
                                KXListingFormField(title: "可住人数", placeholder: "2", icon: "person.2", text: $maxGuests, keyboard: .numberPad)
                            }
                            KXListingFormField(title: "每晚/起步价格", placeholder: "每晚 / 每人 / 预约咨询", icon: "yensign.circle", text: $priceUnit)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "入住时间", placeholder: "15:00", icon: "arrow.right.to.line", text: $checkInTime)
                                KXListingFormField(title: "退房时间", placeholder: "10:00", icon: "arrow.left.to.line", text: $checkOutTime)
                            }
                            KXListingFormField(title: "最少入住晚数", placeholder: "1 晚 / 2 晚起", icon: "moon.stars", text: $minimumStay)
                            KXListingFormField(title: "设施服务", placeholder: "Wi-Fi、厨房、洗衣机、停车场、温泉、行李寄存", icon: "sparkles", text: $amenities, lineLimit: 2...4)
                            KXListingFormField(title: "房量与日期说明", placeholder: "可订日期、剩余房量、旺季限制、儿童入住规则", icon: "calendar", text: $inventoryNote, lineLimit: 2...5)
                            HStack(spacing: 10) {
                                KXListingToggleChip(title: "含早餐", icon: "cup.and.saucer", isOn: $breakfastIncluded, tint: typeAccent)
                                KXListingToggleChip(title: "即时确认", icon: "bolt", isOn: $instantConfirmation, tint: typeAccent)
                            }
                            KXListingFormField(title: "取消规则", placeholder: "入住前几天可取消、旺季不可退等", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)
                            KXListingFormField(title: "资质/许可说明", placeholder: "旅馆业许可 / 民泊备案 / 可接待范围", icon: "checkmark.shield", text: $licenseNote, lineLimit: 2...4)

                        case .attractionTicket, .dayTour:
                            KXListingFormField(title: "票种", placeholder: vertical == .dayTour ? "成人 / 儿童 / 私人团 / 拼团" : "成人票 / 儿童票 / 套票 / 电子票", icon: "ticket", text: $ticketType)
                            KXListingFormField(title: "日期 / 有效期", placeholder: "指定日期 / 购买后 30 天有效 / 每周六出发", icon: "calendar.badge.clock", text: $availability)
                            KXListingFormField(title: "时长", placeholder: vertical == .dayTour ? "约 8 小时" : "约 2 小时 / 当日有效", icon: "clock", text: $duration)
                            KXListingFormField(title: "集合地点", placeholder: "新宿站西口 / 景区入口 / 酒店接送范围", icon: "mappin.and.ellipse", text: $meetingPoint)
                            KXListingFormField(title: "包含内容", placeholder: "门票、导览、交通、餐食等", icon: "checklist", text: $includedItems, lineLimit: 2...5)
                            KXListingFormField(title: "不包含内容", placeholder: "个人消费、餐饮、保险等", icon: "minus.circle", text: $notIncluded, lineLimit: 2...5)
                            KXListingFormField(title: "用户需准备", placeholder: "护照、证件、舒适鞋、雨具等", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            if vertical == .dayTour {
                                KXListingToggleChip(title: "含酒店接送", icon: "bus", isOn: $pickupService, tint: typeAccent)
                            }
                            KXListingFormField(title: "取消规则", placeholder: "票务不可退 / 出发前 3 天可取消", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)
                            KXListingFormField(title: "资质/许可说明", placeholder: "票务来源、旅行资质、保险或导游说明", icon: "checkmark.shield", text: $licenseNote, lineLimit: 2...4)

                        case .airportTransfer:
                            KXListingFormField(title: "机场/路线", placeholder: "成田机场 - 东京 23 区 / 羽田 - 横滨", icon: "airplane", text: $airportRoute)
                            KXListingFormField(title: "服务范围", placeholder: "可接送区域、是否支持跨县、夜间范围", icon: "map", text: $serviceArea)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "车型", placeholder: "轿车 / Alphard / Hiace", icon: "car", text: $vehicleType)
                                KXListingFormField(title: "人数", placeholder: "4", icon: "person.2", text: $passengerCount, keyboard: .numberPad)
                            }
                            KXListingFormField(title: "行李数", placeholder: "2 个 28 寸 + 2 个随身", icon: "suitcase", text: $luggageCount)
                            KXListingFormField(title: "航班号说明", placeholder: "是否需要航班号、延误如何处理", icon: "airplane.arrival", text: $flightInfoNote, lineLimit: 2...4)
                            KXListingFormField(title: "等待规则", placeholder: "免费等待 60 分钟，超时每 30 分钟加收", icon: "timer", text: $waitingRule, lineLimit: 2...4)
                            KXListingFormField(title: "夜间/追加费用", placeholder: "夜间、儿童座椅、大件行李、高速费说明", icon: "moon.stars", text: $surchargeNote, lineLimit: 2...4)
                            KXListingFormField(title: "取消规则", placeholder: "出发前多久可取消，临时取消费用", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)

                        case .paperworkTranslation:
                            KXListingFormField(title: "服务语言", placeholder: "中日 / 中英 / 日英 / 多语言", icon: "character.bubble", text: $languages)
                            KXListingFormField(title: "文件/手续类型", placeholder: "住民票翻译 / 签证材料 / 租房申请 / 电话代沟通", icon: "doc.text", text: $documentType)
                            KXListingFormField(title: "所需材料", placeholder: "护照、在留卡、原文件、申请表等", icon: "folder.badge.plus", text: $requiredMaterials, lineLimit: 2...5)
                            KXListingFormField(title: "交付时间", placeholder: "最快当天 / 2-3 个工作日 / 加急另议", icon: "clock.badge.checkmark", text: $deliveryTime)
                            KXListingFormField(title: "服务流程", placeholder: "资料确认、报价、翻译/代办、交付方式", icon: "list.bullet.clipboard", text: $serviceProcess, lineLimit: 3...6)
                            KXListingFormField(title: "用户需准备", placeholder: "需本人确认、签字、原件邮寄或线上提交的信息", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            KXListingToggleChip(title: "不保证结果", icon: "exclamationmark.shield", isOn: $noResultGuarantee, tint: typeAccent)
                            KXListingFormField(title: "资质/许可说明", placeholder: "行政书士、翻译资质、合作机构或免责声明", icon: "checkmark.shield", text: $licenseNote, lineLimit: 2...4)
                            KXListingFormField(title: "取消规则", placeholder: "开始处理后是否可退、材料错误如何处理", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)

                        case .movingCleaning:
                            KXListingFormField(title: "服务范围", placeholder: "东京 23 区 / 横滨 / 清洁可线上估价", icon: "map", text: $serviceArea)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "房型/面积", placeholder: "1K / 45 平 / 店铺 20 平", icon: "square.split.2x2", text: $propertySize)
                                KXListingFormField(title: "物品量", placeholder: "纸箱 20 个 / 大件 3 件", icon: "shippingbox", text: $itemVolume)
                            }
                            KXListingFormField(title: "车辆/人员", placeholder: "2 吨车 + 2 人 / 1 人上门", icon: "truck.box", text: $vehicleStaff)
                            KXListingFormField(title: "包含内容", placeholder: "搬运、拆装、基础清洁、垃圾袋等", icon: "checklist", text: $includedItems, lineLimit: 2...5)
                            KXListingFormField(title: "不包含内容", placeholder: "空调拆装、粗大垃圾处理、停车费等", icon: "minus.circle", text: $notIncluded, lineLimit: 2...5)
                            KXListingFormField(title: "用户需准备", placeholder: "提前打包、预约电梯、停车位、垃圾券等", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            KXListingFormField(title: "追加费用", placeholder: "楼梯、大件、远距离、夜间、停车费说明", icon: "plus.circle", text: $surchargeNote, lineLimit: 2...4)
                            KXListingFormField(title: "取消规则", placeholder: "预约前一天取消费、雨天改期等", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)

                        case .lifeSetup:
                            KXListingFormField(title: "服务区域", placeholder: "东京 23 区 / 横滨 / 线上协助", icon: "map", text: $serviceArea)
                            KXListingFormField(title: "服务类型", placeholder: "手机卡 / 网络 / 水电煤 / 地址登记", icon: "slider.horizontal.3", text: $setupType)
                            KXListingFormField(title: "所需材料", placeholder: "在留卡、护照、地址、银行卡、本人到场要求", icon: "folder.badge.plus", text: $requiredMaterials, lineLimit: 2...5)
                            KXListingFormField(title: "预计耗时", placeholder: "当天 / 1-3 个工作日 / 需预约窗口", icon: "clock.badge.checkmark", text: $deliveryTime)
                            KXListingFormField(title: "服务方式", placeholder: "线上确认材料、预约窗口、陪同办理或远程协助", icon: "list.bullet.clipboard", text: $serviceProcess, lineLimit: 3...6)
                            KXListingFormField(title: "用户需准备", placeholder: "证件原件、印章、现金、可接电话时间等", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            KXListingFormField(title: "不可承诺事项", placeholder: "不能保证运营商审核、开户结果、政府窗口受理或第三方时效", icon: "exclamationmark.shield", text: $cannotGuarantee, lineLimit: 2...5)
                            KXListingFormField(title: "价格说明", placeholder: "预约咨询 / ¥3,000 起 / 按事项报价", icon: "yensign.circle", text: $priceRange)
                            KXListingFormField(title: "取消规则", placeholder: "材料确认后、预约日前后取消与改期规则", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)

                        case .beautyHealth:
                            KXListingFormField(title: "服务区域 / 店铺位置", placeholder: "新宿 / 原宿 / 线上预约协助", icon: "map", text: $serviceArea)
                            KXListingFormField(title: "服务项目", placeholder: "剪发 / 美甲 / 按摩 / 体检预约协助", icon: "sparkles", text: $beautyService)
                            KXListingFormField(title: "可预约时间", placeholder: "平日晚间 / 周末 / 需提前 2 天", icon: "calendar.badge.clock", text: $availability)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "价格区间", placeholder: "¥4,000 起 / 按项目报价", icon: "yensign.circle", text: $priceRange)
                                KXListingFormField(title: "服务时长", placeholder: "45 分钟 / 90 分钟", icon: "clock", text: $duration)
                            }
                            KXListingFormField(title: "注意事项", placeholder: "迟到规则、过敏史、禁忌提醒、预约前准备", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            KXListingFormField(title: "医疗免责声明", placeholder: "医疗相关仅做预约协助，不提供诊断、治疗承诺或医疗建议", icon: "cross.case", text: $medicalDisclaimer, lineLimit: 2...5)
                            KXListingFormField(title: "取消规则", placeholder: "24 小时内取消、迟到、改期等规则", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)

                        case .petFamily:
                            KXListingFormField(title: "服务区域", placeholder: "东京 23 区 / 到店 / 上门", icon: "map", text: $serviceArea)
                            KXListingFormField(title: "服务对象", placeholder: "小型犬 / 猫 / 儿童用品 / 家庭协助", icon: "person.2", text: $serviceTarget)
                            KXListingFormField(title: "可预约时间", placeholder: "平日晚上 / 周末 / 假期", icon: "calendar.badge.clock", text: $availability)
                            KXListingFormField(title: "价格说明", placeholder: "按小时 / 按天 / 预约咨询", icon: "yensign.circle", text: $priceRange)
                            KXListingFormField(title: "注意事项", placeholder: "宠物性格、疫苗、用品、紧急联系人、家庭规则", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            KXListingFormField(title: "安全/资质说明", placeholder: "经验、保险、照看范围、不可服务边界", icon: "checkmark.shield", text: $licenseNote, lineLimit: 2...4)
                            KXListingFormField(title: "取消规则", placeholder: "预约前取消、临时变更、超时费用等", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)
                        }
                    }
                }
            } else {
                KXListingSection(title: "选择服务细分类", icon: "square.grid.2x2") {
                    KXListingHintRow(
                        text: "请先在基本信息里选择一个标准服务分类，例如 餐厅美食、民宿、景点门票、一日游、机场接送、翻译手续、搬家清洁、生活开通或美容健康。",
                        icon: "hand.tap",
                        tint: typeAccent
                    )
                }
            }
        } else if listingType == "discount" {
            KXListingSection(title: "商家优惠字段", icon: "tag") {
                VStack(spacing: 12) {
                    KXListingFormField(title: "商家名称", placeholder: "店铺 / 品牌 / 公司名称", icon: "storefront", text: $merchantName)
                    KXListingFormField(title: "优惠内容", placeholder: "例如 学生出示证件 9 折，套餐减 500 日元", icon: "tag", text: $discountInfo, lineLimit: 3...6)
                    KXListingFormField(title: "有效期", placeholder: "例如 2026-08-31", icon: "calendar", text: $validUntil)
                    KXListingFormField(title: "使用规则", placeholder: "适用门店、不可叠加、预约说明等", icon: "doc.text", text: $usageRules, lineLimit: 2...5)
                    KXListingToggleChip(title: "商家已认证", icon: "checkmark.seal", isOn: $merchantVerified, tint: typeAccent)
                }
            }
        } else {
            KXListingSection(title: "交易字段", icon: "shippingbox") {
                VStack(spacing: 12) {
                    KXListingChoiceRow(title: "发布类型", icon: "arrow.left.arrow.right.circle", options: ["出售", "免费送", "求购"], selection: $listingMode, tint: typeAccent)
                    KXListingFormField(title: "品牌 / 型号", placeholder: "可选，例如 日文配列键盘 / 白色书桌 / 13 寸笔记本", icon: "tag", text: $brandModel)
                    KXListingChoiceRow(title: "新旧程度", icon: "sparkles", options: ["全新", "几乎全新", "良好", "有使用痕迹", "可用"], selection: $condition, tint: typeAccent)
                    HStack(spacing: 10) {
                        KXListingFormField(title: "原价 / 参考价", placeholder: "可选，例如 28000", icon: "chart.line.uptrend.xyaxis", text: $originalPrice, keyboard: .decimalPad)
                        KXListingFormField(title: "购买时间", placeholder: "可选，例如 2025 年春", icon: "calendar", text: $purchaseTime)
                    }
                    KXListingFormField(title: "配件 / 包装", placeholder: "例如 原盒、充电器、说明书、保修卡", icon: "shippingbox.and.arrow.backward", text: $accessories)
                    KXListingFormField(title: "瑕疵 / 使用痕迹", placeholder: "如有划痕、缺件、维修史请提前说明；没有可写“无明显瑕疵”", icon: "exclamationmark.circle", text: $defectNote, lineLimit: 2...4)
                    KXListingFormField(title: "可交易时间", placeholder: "例如 平日 19:00 后 / 周末下午", icon: "calendar.badge.clock", text: $secondhandAvailableTime)
                    KXListingFormField(title: "取货 / 邮寄说明", placeholder: "例如 新宿站面交，邮寄需买家承担运费", icon: "shippingbox", text: $secondhandPickupNotes, lineLimit: 2...4)
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "自取 / 面交", icon: "person.2", isOn: $pickupAvailable, tint: typeAccent)
                        KXListingToggleChip(title: "可邮寄", icon: "shippingbox", isOn: $secondhandShippingAvailable, tint: typeAccent)
                    }
                    KXListingToggleChip(title: "价格可商量", icon: "arrow.left.arrow.right", isOn: $priceNegotiable, tint: typeAccent)
                    KXListingHintRow(text: "建议写清购买时间、瑕疵、配件、是否含包装和交易地点，减少来回确认。", icon: "lightbulb", tint: typeAccent)
                }
            }
        }
    }

    private func hydrateExistingListingIfNeeded() {
        guard !didHydrateExisting, let listing = existingListing else { return }
        didHydrateExisting = true
        title = listing.title
        category = listing.category ?? ""
        price = listing.price.map { String(format: $0.rounded() == $0 ? "%.0f" : "%.2f", $0) } ?? ""
        location = listing.location_text ?? listing.locationText ?? ""
        description = listing.description ?? ""
        existingMedia = listing.media ?? []

        let raw: (String) -> String = { key in
            listing.attributes?[key]?.listingDisplayValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let bool: (String) -> Bool = { key in
            if let value = listing.attributes?[key]?.boolValue { return value }
            return ["true", "1", "yes", "是", "可", "有", "available"].contains(raw(key).lowercased())
        }

        switch listing.type {
        case "rental":
            layout = raw("layout").isEmpty ? layout : raw("layout")
            area = raw("area_sqm")
            station = raw("nearest_station")
            moveIn = raw("move_in_date")
            shareAllowed = bool("share_allowed")
            shortTermAllowed = bool("short_term_allowed")
            furnished = bool("furnished")
        case "job", "hiring":
            companyName = raw("company_name")
            workingHours = raw("working_hours")
            employmentType = KXListingCopy.employmentTypeLabel(raw("employment_type"))
            japaneseLevel = raw("japanese_level").isEmpty ? japaneseLevel : raw("japanese_level")
            visaSupport = bool("visa_support")
            noExperienceOK = bool("no_experience_ok")
            studentOK = bool("student_ok")
            remoteOK = bool("remote_ok")
            jobHolidays = raw("holidays")
            jobBenefits = raw("benefits")
        case "local_service":
            serviceBusinessName = raw("business_name")
            serviceType = raw("service_type").isEmpty ? (listing.category ?? "") : raw("service_type")
            if category.isEmpty { category = serviceType }
            serviceArea = raw("service_area")
            priceUnit = raw("price_unit").isEmpty ? priceUnit : raw("price_unit")
            availability = raw("availability")
            certifiedProvider = bool("certified_provider")
            serviceProcess = raw("service_process")
            cancellationRule = raw("cancellation_rule")
            openHours = raw("open_hours")
            priceRange = raw("price_range")
            nearStation = raw("near_station")
            storePhone = raw("store_phone")
            reservationRequired = bool("reservation_required")
            reservationNote = raw("reservation_note")
            menuText = KXMerchantInput.menuLines(listing)
            packagesText = KXMerchantInput.packageLines(listing)
            languages = raw("languages")
            roomType = raw("room_type")
            maxGuests = raw("max_guests")
            checkInTime = raw("check_in_time").isEmpty ? checkInTime : raw("check_in_time")
            checkOutTime = raw("check_out_time").isEmpty ? checkOutTime : raw("check_out_time")
            minimumStay = raw("minimum_stay").isEmpty ? minimumStay : raw("minimum_stay")
            amenities = raw("amenities")
            inventoryNote = raw("inventory_note")
            breakfastIncluded = bool("breakfast_included")
            instantConfirmation = bool("instant_confirmation")
            ticketType = raw("ticket_type")
            duration = raw("duration")
            meetingPoint = raw("meeting_point")
            pickupService = bool("pickup_service")
            includedItems = raw("included_items")
            notIncluded = raw("not_included")
            userPrepare = raw("user_prepare")
            licenseNote = raw("license_note")
            airportRoute = raw("airport_route")
            vehicleType = raw("vehicle_type")
            passengerCount = raw("passenger_count")
            luggageCount = raw("luggage_count")
            flightInfoNote = raw("flight_info_note")
            waitingRule = raw("waiting_rule")
            surchargeNote = raw("surcharge_note")
            documentType = raw("document_type")
            requiredMaterials = raw("required_materials")
            deliveryTime = raw("delivery_time")
            noResultGuarantee = bool("no_result_guarantee")
            propertySize = raw("property_size")
            itemVolume = raw("item_volume")
            vehicleStaff = raw("vehicle_staff")
            setupType = raw("setup_type")
            cannotGuarantee = raw("cannot_guarantee")
            beautyService = raw("beauty_service")
            medicalDisclaimer = raw("medical_disclaimer")
            serviceTarget = raw("service_target")
        case "discount":
            merchantName = raw("merchant_name")
            discountInfo = raw("discount_info")
            validUntil = raw("valid_until")
            usageRules = raw("usage_rules")
            merchantVerified = bool("merchant_verified")
        default:
            listingMode = KXListingCopy.listingModeLabel(raw("listing_mode"))
            condition = KXListingCopy.conditionLabel(raw("condition"))
            brandModel = [raw("brand"), raw("model")].filter { !$0.isEmpty }.joined(separator: " / ")
            originalPrice = raw("original_price")
            priceNegotiable = bool("price_negotiable")
            purchaseTime = raw("purchase_time")
            accessories = raw("accessories")
            defectNote = raw("defect_note")
            secondhandAvailableTime = raw("available_time")
            secondhandPickupNotes = raw("pickup_note")
            pickupAvailable = bool("pickup_available")
            secondhandShippingAvailable = bool("shipping_available")
        }
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var next = mediaDrafts
        var videoCount = mediaDrafts.filter { $0.type == .video }.count
        var imageCount = mediaDrafts.filter { $0.type == .image }.count
        var mediaCount = mediaDrafts.count
        var warning: String?
        for item in items.prefix(imageLimit) {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                warning = "无法读取所选媒体，请重新选择。"
                continue
            }
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            do {
                guard mediaCount < imageLimit else {
                    warning = "媒体最多上传 \(imageLimit) 个，其中最多 1 个视频。"
                    continue
                }
                if isVideo {
                    guard videoCount < 1 else {
                        warning = "每条信息最多上传 1 个视频。"
                        continue
                    }
                    guard data.count <= (listingType == "rental" ? 300 * 1024 * 1024 : KaiXConfig.maxPostVideoBytes) else {
                        warning = "视频文件过大，请压缩后重试。"
                        continue
                    }
                    let draft = try await UploadService.shared.prepareVideo(data: data, contentType: item.supportedContentTypes.first { $0.conforms(to: .movie) })
                    guard draft.duration <= (listingType == "rental" ? 600 : 300) else {
                        warning = listingType == "rental" ? "房源视频最长 10 分钟。" : "视频最长 5 分钟。"
                        continue
                    }
                    next.append(draft)
                    videoCount += 1
                    mediaCount += 1
                } else {
                    guard imageCount < imageLimit else {
                        warning = "图片最多上传 \(imageLimit) 张。"
                        continue
                    }
                    let draft = try await UploadService.shared.prepareImage(data: data)
                    next.append(draft)
                    imageCount += 1
                    mediaCount += 1
                }
            } catch {
                warning = "媒体处理失败，请重新选择。"
            }
        }
        mediaDrafts = next
        mediaUploadPhases = Dictionary(uniqueKeysWithValues: next.map { ($0.id, uploadedMedia[$0.id] == nil ? .idle : .ready) })
        pickerItems = []
        if let warning { message = warning }
    }

    private func submit() async {
        guard let region else { return }
        isSubmitting = true
        message = nil
        do {
            var mediaIds = existingMedia.compactMap { $0.uploaded_file_id ?? $0.uploadedFileId }
            for draft in mediaDrafts {
                if let cached = uploadedMedia[draft.id] {
                    mediaIds.append(cached.id)
                    continue
                }
                mediaUploadPhases[draft.id] = .preparing
                let isVideo = draft.type == .video
                withAnimation(.easeInOut(duration: 0.2)) {
                    mediaUploadPhases[draft.id] = .uploading(0.45)
                }
                let media = try await UploadManager.shared.upload(
                    draft: draft,
                    purpose: listingUploadPurpose(isVideo: isVideo),
                    entityType: "listing"
                )
                mediaUploadPhases[draft.id] = .completing
                uploadedMedia[draft.id] = media
                withAnimation(.easeOut(duration: 0.2)) {
                    mediaUploadPhases[draft.id] = .ready
                }
                mediaIds.append(media.id)
            }
            let result: KaiXCityListingDTO
            if let existingListing {
                result = try await KaiXAPIClient.shared.updateListing(
                    existingListing.id,
                    title: title,
                    description: description,
                    category: category.isEmpty ? KXListingCopy.defaultCategory(for: listingType) : category,
                    price: Double(price),
                    locationText: location,
                    mediaIds: mediaIds,
                    attributes: attributes
                )
            } else {
                result = try await KaiXAPIClient.shared.createListing(
                    type: KXListingCopy.createType(for: listingType),
                    countryCode: region.countryCode,
                    citySlug: region.cityCode,
                    regionCode: region.regionCode,
                    language: language == .zh ? "zh-CN" : language.rawValue,
                    title: title,
                    description: description,
                    category: category.isEmpty ? KXListingCopy.defaultCategory(for: listingType) : category,
                    price: Double(price),
                    locationText: location,
                    mediaIds: mediaIds,
                    attributes: attributes
                )
            }
            let published = result.status == "published" || result.status == "active"
            message = isEditing
                ? (published ? "修改已保存，Web 与 iOS 已同步。" : "修改已保存并提交复审。")
                : (published ? "发布成功，已同步到三端。" : "已提交审核，可在详情页查看审核状态。")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSubmitting = false
            try? await Task.sleep(for: .milliseconds(550))
            router.open(.cityListingDetail(listingId: result.id))
        } catch {
            if let failed = mediaDrafts.first(where: {
                if case .uploading = mediaUploadPhases[$0.id] { return true }
                if case .completing = mediaUploadPhases[$0.id] { return true }
                if case .preparing = mediaUploadPhases[$0.id] { return true }
                return false
            }) {
                mediaUploadPhases[failed.id] = .failed(error.kaixUserMessage)
            }
            message = error.kaixUserMessage
            isSubmitting = false
        }
    }

    private func listingUploadPurpose(isVideo: Bool) -> String {
        switch KXListingCopy.createType(for: listingType) {
        case "rental": return isVideo ? "rental_video" : "rental_image"
        case "job", "hiring": return isVideo ? "job_video" : "job_image"
        case "local_service": return isVideo ? "service_video" : "service_image"
        case "discount", "event": return isVideo ? "discount_video" : "discount_image"
        default: return isVideo ? "secondhand_video" : "secondhand_image"
        }
    }

    private var attributes: [String: KaiXAttributeValue] {
        if listingType == "rental" {
            return [
                "rent": .init(double: Double(price) ?? 0),
                "layout": .init(string: layout),
                "area_sqm": .init(double: Double(area) ?? 0),
                "nearest_station": .init(string: station),
                "move_in_date": .init(string: moveIn),
                "share_allowed": .init(bool: shareAllowed),
                "short_term_allowed": .init(bool: shortTermAllowed),
                "furnished": .init(bool: furnished),
            ]
        }
        if listingType == "work" || listingType == "job" || listingType == "hiring" {
            return [
                "salary_min": .init(double: Double(price) ?? 0),
                "salary_type": .init(string: "hourly"),
                "employment_type": .init(string: KXListingCopy.employmentTypeKey(employmentType)),
                "japanese_level": .init(string: japaneseLevel),
                // visa_support 是三态枚举（none/consult/available），与 Web 同一
                // 套 wire 值——存布尔会让 Web 端「签证支持」筛选永远匹配不到。
                "visa_support": .init(string: visaSupport ? "available" : "none"),
                "working_hours": .init(string: workingHours),
                "company_name": .init(string: companyName),
                "holidays": .init(string: jobHolidays),
                "benefits": .init(string: jobBenefits),
                "no_experience_ok": .init(bool: noExperienceOK),
                "student_ok": .init(bool: studentOK),
                "remote_ok": .init(bool: remoteOK),
            ]
        }
        if listingType == "local_service" {
            var result: [String: KaiXAttributeValue] = [
                "business_name": .init(string: serviceBusinessName),
                "service_type": .init(string: serviceType.isEmpty ? category : serviceType),
                "certified_provider": .init(bool: certifiedProvider),
            ]
            guard let vertical = serviceVertical else { return result }
            result["service_vertical"] = .init(string: vertical.rawValue)

            switch vertical {
            case .foodRestaurant:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["open_hours"] = .init(string: openHours)
                result["price_range"] = .init(string: priceRange)
                result["near_station"] = .init(string: nearStation)
                result["store_phone"] = .init(string: storePhone)
                result["reservation_required"] = .init(bool: reservationRequired)
                result["reservation_note"] = .init(string: reservationNote)
                result["languages"] = .init(string: languages)
                result["menu"] = .init(string: KXMerchantInput.encodeMenu(menuText))
                result["packages"] = .init(string: KXMerchantInput.encodePackages(packagesText))
            case .diningBooking:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["open_hours"] = .init(string: openHours)
                result["price_range"] = .init(string: priceRange)
                result["near_station"] = .init(string: nearStation)
                result["store_phone"] = .init(string: storePhone)
                result["availability"] = .init(string: availability)
                result["booking_required"] = .init(bool: reservationRequired)
                result["reservation_required"] = .init(bool: reservationRequired)
                result["reservation_note"] = .init(string: reservationNote)
                result["service_process"] = .init(string: serviceProcess)
                result["cancellation_rule"] = .init(string: cancellationRule)
                result["languages"] = .init(string: languages)
            case .lodging:
                result["room_type"] = .init(string: roomType)
                result["max_guests"] = .init(string: maxGuests)
                result["price_unit"] = .init(string: priceUnit)
                result["check_in_time"] = .init(string: checkInTime)
                result["check_out_time"] = .init(string: checkOutTime)
                result["minimum_stay"] = .init(string: minimumStay)
                result["amenities"] = .init(string: amenities)
                result["inventory_note"] = .init(string: inventoryNote)
                result["breakfast_included"] = .init(bool: breakfastIncluded)
                result["instant_confirmation"] = .init(bool: instantConfirmation)
                result["cancellation_rule"] = .init(string: cancellationRule)
                result["license_note"] = .init(string: licenseNote)
            case .attractionTicket:
                result["ticket_type"] = .init(string: ticketType)
                result["availability"] = .init(string: availability)
                result["duration"] = .init(string: duration)
                result["meeting_point"] = .init(string: meetingPoint)
                result["included_items"] = .init(string: includedItems)
                result["not_included"] = .init(string: notIncluded)
                result["user_prepare"] = .init(string: userPrepare)
                result["cancellation_rule"] = .init(string: cancellationRule)
                result["license_note"] = .init(string: licenseNote)
            case .dayTour:
                result["ticket_type"] = .init(string: ticketType)
                result["availability"] = .init(string: availability)
                result["duration"] = .init(string: duration)
                result["meeting_point"] = .init(string: meetingPoint)
                result["included_items"] = .init(string: includedItems)
                result["not_included"] = .init(string: notIncluded)
                result["user_prepare"] = .init(string: userPrepare)
                result["pickup_service"] = .init(bool: pickupService)
                result["cancellation_rule"] = .init(string: cancellationRule)
                result["license_note"] = .init(string: licenseNote)
            case .airportTransfer:
                result["airport_route"] = .init(string: airportRoute)
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["vehicle_type"] = .init(string: vehicleType)
                result["passenger_count"] = .init(string: passengerCount)
                result["luggage_count"] = .init(string: luggageCount)
                result["flight_info_note"] = .init(string: flightInfoNote)
                result["waiting_rule"] = .init(string: waitingRule)
                result["surcharge_note"] = .init(string: surchargeNote)
                result["cancellation_rule"] = .init(string: cancellationRule)
            case .paperworkTranslation:
                result["languages"] = .init(string: languages)
                result["document_type"] = .init(string: documentType)
                result["required_materials"] = .init(string: requiredMaterials)
                result["delivery_time"] = .init(string: deliveryTime)
                result["service_process"] = .init(string: serviceProcess)
                result["user_prepare"] = .init(string: userPrepare)
                result["no_result_guarantee"] = .init(bool: noResultGuarantee)
                result["license_note"] = .init(string: licenseNote)
                result["cancellation_rule"] = .init(string: cancellationRule)
            case .movingCleaning:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["property_size"] = .init(string: propertySize)
                result["item_volume"] = .init(string: itemVolume)
                result["vehicle_staff"] = .init(string: vehicleStaff)
                result["included_items"] = .init(string: includedItems)
                result["not_included"] = .init(string: notIncluded)
                result["user_prepare"] = .init(string: userPrepare)
                result["surcharge_note"] = .init(string: surchargeNote)
                result["cancellation_rule"] = .init(string: cancellationRule)
            case .lifeSetup:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["setup_type"] = .init(string: setupType)
                result["required_materials"] = .init(string: requiredMaterials)
                result["delivery_time"] = .init(string: deliveryTime)
                result["service_process"] = .init(string: serviceProcess)
                result["user_prepare"] = .init(string: userPrepare)
                result["cannot_guarantee"] = .init(string: cannotGuarantee)
                result["price_range"] = .init(string: priceRange)
                result["cancellation_rule"] = .init(string: cancellationRule)
            case .beautyHealth:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["beauty_service"] = .init(string: beautyService)
                result["price_range"] = .init(string: priceRange)
                result["availability"] = .init(string: availability)
                result["duration"] = .init(string: duration)
                result["user_prepare"] = .init(string: userPrepare)
                result["medical_disclaimer"] = .init(string: medicalDisclaimer)
                result["cancellation_rule"] = .init(string: cancellationRule)
            case .petFamily:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["service_target"] = .init(string: serviceTarget)
                result["availability"] = .init(string: availability)
                result["price_range"] = .init(string: priceRange)
                result["user_prepare"] = .init(string: userPrepare)
                result["cancellation_rule"] = .init(string: cancellationRule)
                result["license_note"] = .init(string: licenseNote)
            }
            return result
        }
        if listingType == "discount" {
            return [
                "merchant_name": .init(string: merchantName),
                "discount_info": .init(string: discountInfo),
                "valid_until": .init(string: validUntil),
                "usage_rules": .init(string: usageRules),
                "merchant_verified": .init(bool: merchantVerified),
            ]
        }
        return [
            "listing_mode": .init(string: KXListingCopy.listingModeKey(listingMode)),
            "brand": .init(string: brandModel),
            "condition": .init(string: KXListingCopy.conditionKey(condition)),
            "original_price": .init(string: originalPrice),
            "price_negotiable": .init(bool: priceNegotiable),
            "purchase_time": .init(string: purchaseTime),
            "accessories": .init(string: accessories),
            "defect_note": .init(string: defectNote),
            "available_time": .init(string: secondhandAvailableTime),
            "pickup_note": .init(string: secondhandPickupNotes),
            "delivery_method": .init(string: pickupAvailable ? (secondhandShippingAvailable ? "pickup_or_shipping" : "pickup") : (secondhandShippingAvailable ? "shipping" : "negotiable")),
            "pickup_available": .init(bool: pickupAvailable),
            "shipping_available": .init(bool: secondhandShippingAvailable),
        ]
    }
}

private struct KXListingFormField: View {
    let title: String
    let placeholder: String
    let icon: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var lineLimit: ClosedRange<Int>?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            Group {
                if let lineLimit {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(lineLimit)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                }
            }
            .font(.subheadline.weight(.semibold))
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.softBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(KXColor.separator.opacity(0.58), lineWidth: 0.65)
            }
        }
    }
}

private struct KXListingChoiceRow: View {
    let title: String
    let icon: String
    let options: [String]
    @Binding var selection: String
    var tint: Color = KXColor.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(option)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selection == option ? Color.white : .primary)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(selection == option ? tint : KXColor.softBackground.opacity(0.82), in: Capsule())
                            .overlay(Capsule().stroke(selection == option ? Color.clear : KXColor.separator.opacity(0.58), lineWidth: 0.65))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KXListingToggleChip: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    var tint: Color = KXColor.accent

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : icon)
                    .font(.subheadline.weight(.bold))
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isOn ? tint : .secondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isOn ? tint.opacity(0.11) : KXColor.softBackground.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isOn ? tint.opacity(0.32) : KXColor.separator.opacity(0.58), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct KXListingHintRow: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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
            .frame(width: width, alignment: .leading)
            .kxLivingSurface(radius: 18)
        }
        .frame(width: width, alignment: .leading)
        .buttonStyle(.plain)
    }

    private var cover: some View {
        ZStack {
            if let url = listing.coverURL {
                MediaImageView(url: url, targetPixelSize: 720)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                KXColor.livingSoft
                Image(systemName: KXListingCopy.icon(for: listing.type))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary.opacity(0.56))
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
        .frame(width: innerWidth, height: innerWidth)
        .overlay(alignment: .topLeading) {
            KXListingBadge(
                title: KXListingCopy.formatListingStatus(listing.status, type: listing.type, language),
                tint: KXListingCopy.statusColor(listing.status)
            )
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
                        .frame(width: 48, height: 48)
                        .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
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

enum KXListingCopy {
    enum ServiceVertical: String, CaseIterable {
        case foodRestaurant = "food_restaurant"
        case diningBooking = "dining_booking"
        case lodging = "lodging"
        case attractionTicket = "attraction_ticket"
        case dayTour = "day_tour"
        case airportTransfer = "airport_transfer"
        case paperworkTranslation = "paperwork_translation"
        case movingCleaning = "moving_cleaning"
        case lifeSetup = "life_setup"
        case beautyHealth = "beauty_health"
        case petFamily = "pet_family"
    }

    struct ServiceCreateSection: Identifiable {
        let id: String
        let icon: String
        let zh: String
        let ja: String
        let en: String
        let subtitleZh: String
        let subtitleJa: String
        let subtitleEn: String
        let categories: [String]

        func label(_ language: AppLanguage) -> String {
            KXListingCopy.pickText(language, zh, ja, en)
        }

        func subtitle(_ language: AppLanguage) -> String {
            KXListingCopy.pickText(language, subtitleZh, subtitleJa, subtitleEn)
        }
    }

    /// 餐厅美食：菜系类目（与 web ListingKit FOOD_CATEGORIES 同步）。
    static let foodCategories = ["中华料理", "日本料理", "居酒屋", "烧肉火锅", "拉面", "寿司海鲜", "咖啡甜品", "西餐", "韩国料理"]
    static let foodSectionCategories = ["餐厅美食"] + foodCategories + ["优惠预约"]
    static let lodgingSectionCategories = ["民宿", "酒店", "温泉旅馆", "公寓式酒店", "短住公寓"]
    static let travelSectionCategories = ["景点门票", "一日游", "本地向导", "体验活动", "包车行程"]
    static let transferSectionCategories = ["机场接送", "车站接送", "包车", "行李协助"]
    static let paperworkSectionCategories = ["材料翻译", "市役所陪同", "银行卡协助", "手机卡协助", "租房申请协助", "签证材料整理"]
    static let movingSectionCategories = ["搬家", "退房清洁", "粗大垃圾协助", "行李搬运", "家具家电配送协助"]
    static let lifeSetupSectionCategories = ["手机卡开通", "网络开通", "水电煤协助", "地址登记协助", "粗大垃圾预约", "生活跑腿", "生活支持"]
    static let beautyHealthSectionCategories = ["美容美发", "美甲", "按摩", "皮肤管理", "体检/牙科预约协助"]
    static let petFamilySectionCategories = ["宠物寄养", "遛狗", "临时照看", "儿童用品租赁", "家庭协助", "宠物服务"]
    static let serviceCreateSections: [ServiceCreateSection] = [
        .init(
            id: "food",
            icon: "fork.knife",
            zh: "餐饮预约",
            ja: "飲食予約",
            en: "Dining",
            subtitleZh: "餐厅、居酒屋、咖啡甜品和优惠预约只填写到店、菜单、套餐和取消规则。",
            subtitleJa: "飲食店、居酒屋、カフェ、予約特典は来店予約・メニュー・セット・取消規定を入力します。",
            subtitleEn: "Restaurants, cafes and booking deals use dining, menu, set and cancellation fields.",
            categories: foodSectionCategories
        ),
        .init(
            id: "lodging",
            icon: "bed.double",
            zh: "住宿短住",
            ja: "宿泊・短期滞在",
            en: "Stays",
            subtitleZh: "民宿、酒店和短住公寓只填写房型、人数、入住退房、设施、房量与许可说明。",
            subtitleJa: "民泊、ホテル、短期アパートは部屋タイプ、人数、チェックイン、設備、在庫、許可情報を入力します。",
            subtitleEn: "Stays use room, guest, check-in, amenity, availability and permit fields.",
            categories: lodgingSectionCategories
        ),
        .init(
            id: "travel",
            icon: "map",
            zh: "旅行票务",
            ja: "旅行・チケット",
            en: "Travel",
            subtitleZh: "景点门票、一日游、向导和体验活动填写日期、人数、时长、集合地点和包含内容。",
            subtitleJa: "チケット、日帰り、ガイド、体験は日付、人数、所要時間、集合場所、含まれる内容を入力します。",
            subtitleEn: "Tickets, tours and experiences use date, guests, duration, meeting point and inclusion fields.",
            categories: travelSectionCategories
        ),
        .init(
            id: "transfer",
            icon: "car",
            zh: "接送交通",
            ja: "送迎・交通",
            en: "Transfers",
            subtitleZh: "机场、车站、包车和行李协助填写路线、车型、人数、行李、等待与追加费用规则。",
            subtitleJa: "空港・駅送迎、貸切、荷物サポートはルート、車種、人数、荷物、待機・追加料金を入力します。",
            subtitleEn: "Transfers use route, vehicle, passenger, luggage, waiting and surcharge fields.",
            categories: transferSectionCategories
        ),
        .init(
            id: "paperwork",
            icon: "doc.text",
            zh: "翻译手续",
            ja: "翻訳・手続き",
            en: "Paperwork",
            subtitleZh: "材料翻译、市役所、银行卡、手机卡和租房/签证材料整理必须写清材料、流程与不可承诺事项。",
            subtitleJa: "翻訳、役所、銀行、SIM、賃貸・ビザ書類は必要書類、流れ、保証できない事項を明記します。",
            subtitleEn: "Paperwork help must state required materials, workflow and no-result-guarantee boundaries.",
            categories: paperworkSectionCategories
        ),
        .init(
            id: "moving",
            icon: "shippingbox",
            zh: "搬家清洁",
            ja: "引越し・清掃",
            en: "Moving",
            subtitleZh: "搬家、退房清洁、粗大垃圾和配送协助填写面积、物品量、车辆人员、包含内容和追加费用。",
            subtitleJa: "引越し、退去清掃、粗大ごみ、配送補助は広さ、物量、車両人員、含まれる内容、追加料金を入力します。",
            subtitleEn: "Moving and cleaning use size, volume, vehicle/staff, inclusions and surcharge fields.",
            categories: movingSectionCategories
        ),
        .init(
            id: "life",
            icon: "house",
            zh: "生活开通",
            ja: "生活手続き",
            en: "Life setup",
            subtitleZh: "手机卡、网络、水电煤、地址登记、粗大垃圾预约和生活跑腿填写材料、耗时、方式与不可承诺事项。",
            subtitleJa: "SIM、ネット、ライフライン、住所登録、粗大ごみ予約、生活代行は書類、所要時間、方法、保証できない事項を入力します。",
            subtitleEn: "Life setup uses required materials, timeline, method and no-guarantee fields.",
            categories: lifeSetupSectionCategories
        ),
        .init(
            id: "beauty",
            icon: "sparkles",
            zh: "美容健康",
            ja: "美容・健康予約",
            en: "Beauty",
            subtitleZh: "美容美发、美甲、按摩、皮肤管理和体检/牙科预约协助填写项目、时间、价格、注意事项和医疗边界。",
            subtitleJa: "美容、ネイル、マッサージ、肌ケア、健診・歯科予約は項目、時間、料金、注意事項、医療境界を入力します。",
            subtitleEn: "Beauty and health booking uses service, time, price, notes and medical-boundary fields.",
            categories: beautyHealthSectionCategories
        ),
    ]
    static let serviceCreateCategories = uniqueCategories(serviceCreateSections.flatMap(\.categories))
    /// 生活服务只展示第一阶段正式入口；旧伞类目仍在映射中兼容已有数据。
    static let lifeSectionCategories = paperworkSectionCategories + movingSectionCategories + lifeSetupSectionCategories + beautyHealthSectionCategories
    static let homestayCategories = ["民宿"]
    static let hotelCategories = ["酒店", "温泉旅馆", "公寓式酒店", "短住公寓", "酒店民宿"]
    static let stayCategories = homestayCategories + hotelCategories
    static let stayChips = ["全部", "民宿"]
    static let hotelChips = ["全部", "酒店", "温泉旅馆", "公寓式酒店", "短住公寓"]

    private static func uniqueCategories(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }
    }

    static func isStayCategory(_ category: String?) -> Bool {
        stayCategories.contains(category ?? "")
    }

    static func isHomestayCategory(_ category: String?) -> Bool {
        homestayCategories.contains(category ?? "")
    }

    static func isHotelCategory(_ category: String?) -> Bool {
        hotelCategories.contains(category ?? "")
    }

    static func isFoodCategory(_ category: String?) -> Bool {
        foodSectionCategories.contains(category ?? "")
    }

    private static let serviceVerticalByCategory: [String: ServiceVertical] = [
        "餐厅美食": .foodRestaurant,
        "中华料理": .foodRestaurant,
        "日本料理": .foodRestaurant,
        "居酒屋": .foodRestaurant,
        "烧肉火锅": .foodRestaurant,
        "拉面": .foodRestaurant,
        "寿司海鲜": .foodRestaurant,
        "咖啡甜品": .foodRestaurant,
        "西餐": .foodRestaurant,
        "韩国料理": .foodRestaurant,
        "餐饮点评": .diningBooking,
        "优惠预约": .diningBooking,
        "民宿": .lodging,
        "酒店": .lodging,
        "温泉旅馆": .lodging,
        "公寓式酒店": .lodging,
        "短住公寓": .lodging,
        "酒店民宿": .lodging,
        "景点门票": .attractionTicket,
        "一日游": .dayTour,
        "本地向导": .dayTour,
        "体验活动": .dayTour,
        "包车行程": .dayTour,
        "接送机": .airportTransfer,
        "机场接送": .airportTransfer,
        "车站接送": .airportTransfer,
        "包车": .airportTransfer,
        "行李协助": .airportTransfer,
        "材料翻译": .paperworkTranslation,
        "市役所陪同": .paperworkTranslation,
        "银行卡协助": .paperworkTranslation,
        "手机卡协助": .paperworkTranslation,
        "签证材料整理": .paperworkTranslation,
        "翻译手续": .paperworkTranslation,
        "签证/手续协助": .paperworkTranslation,
        "翻译": .paperworkTranslation,
        "租房申请协助": .paperworkTranslation,
        "认证服务": .paperworkTranslation,
        "退房清洁": .movingCleaning,
        "粗大垃圾协助": .movingCleaning,
        "行李搬运": .movingCleaning,
        "家具家电配送协助": .movingCleaning,
        "搬家清洁": .movingCleaning,
        "搬家": .movingCleaning,
        "清洁": .movingCleaning,
        "手机卡开通": .lifeSetup,
        "网络开通": .lifeSetup,
        "水电煤协助": .lifeSetup,
        "地址登记协助": .lifeSetup,
        "粗大垃圾预约": .lifeSetup,
        "生活跑腿": .lifeSetup,
        "生活支持": .lifeSetup,
        "美容美发": .beautyHealth,
        "美甲": .beautyHealth,
        "按摩": .beautyHealth,
        "皮肤管理": .beautyHealth,
        "体检/牙科预约协助": .beautyHealth,
        "宠物寄养": .petFamily,
        "遛狗": .petFamily,
        "临时照看": .petFamily,
        "儿童用品租赁": .petFamily,
        "家庭协助": .petFamily,
        "宠物服务": .petFamily,
    ]

    static func serviceVertical(category: String?, serviceType: String?) -> ServiceVertical? {
        let categoryKey = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let serviceKey = serviceType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let vertical = serviceVerticalByCategory[categoryKey] { return vertical }
        if let vertical = serviceVerticalByCategory[serviceKey] { return vertical }
        if let vertical = ServiceVertical(rawValue: serviceKey) { return vertical }
        return nil
    }

    static func serviceCreateSection(for category: String?) -> ServiceCreateSection? {
        guard let key = serviceCreateSectionKey(for: category) else { return nil }
        return serviceCreateSections.first { $0.id == key }
    }

    static func serviceCreateSectionKey(for category: String?) -> String? {
        let value = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty { return nil }
        if let section = serviceCreateSections.first(where: { $0.categories.contains(value) }) {
            return section.id
        }
        switch serviceVertical(category: value, serviceType: value) {
        case .foodRestaurant, .diningBooking:
            return "food"
        case .lodging:
            return "lodging"
        case .attractionTicket, .dayTour:
            return "travel"
        case .airportTransfer:
            return "transfer"
        case .paperworkTranslation:
            return "paperwork"
        case .movingCleaning:
            return "moving"
        case .lifeSetup:
            return "life"
        case .beautyHealth:
            return "beauty"
        case .petFamily:
            return nil
        case .none:
            return nil
        }
    }

    static func serviceVertical(for listing: KaiXCityListingDTO) -> ServiceVertical? {
        let serviceType = listing.attributes?["service_type"]?.listingDisplayValue
        if let vertical = serviceVertical(category: listing.category, serviceType: serviceType) { return vertical }
        let explicit = listing.attributes?["service_vertical"]?.listingDisplayValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let vertical = ServiceVertical(rawValue: explicit) { return vertical }
        let attrs = listing.attributes ?? [:]
        if attrs["menu"] != nil || attrs["packages"] != nil { return .foodRestaurant }
        if attrs["room_type"] != nil || attrs["max_guests"] != nil { return .lodging }
        if attrs["airport_route"] != nil || attrs["flight_info_note"] != nil { return .airportTransfer }
        if attrs["document_type"] != nil || attrs["required_materials"] != nil { return .paperworkTranslation }
        if attrs["property_size"] != nil || attrs["vehicle_staff"] != nil { return .movingCleaning }
        if attrs["setup_type"] != nil || attrs["cannot_guarantee"] != nil { return .lifeSetup }
        if attrs["beauty_service"] != nil || attrs["medical_disclaimer"] != nil { return .beautyHealth }
        if attrs["service_target"] != nil { return .petFamily }
        if attrs["ticket_type"] != nil {
            if attrs["pickup_service"] != nil { return .dayTour }
            return .attractionTicket
        }
        return nil
    }

    static func serviceVerticalLabel(_ vertical: ServiceVertical, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch vertical {
        case .foodRestaurant: (zh, ja, en) = ("餐厅美食字段", "飲食店フィールド", "Dining fields")
        case .diningBooking: (zh, ja, en) = ("餐饮预约优惠字段", "飲食予約特典フィールド", "Dining booking fields")
        case .lodging: (zh, ja, en) = ("住宿字段", "宿泊フィールド", "Stay fields")
        case .attractionTicket: (zh, ja, en) = ("景点门票字段", "観光チケットフィールド", "Attraction ticket fields")
        case .dayTour: (zh, ja, en) = ("一日游字段", "日帰りツアーフィールド", "Day tour fields")
        case .airportTransfer: (zh, ja, en) = ("接送与交通字段", "送迎・交通フィールド", "Transfer fields")
        case .paperworkTranslation: (zh, ja, en) = ("翻译 / 手续字段", "翻訳・手続きフィールド", "Paperwork fields")
        case .movingCleaning: (zh, ja, en) = ("搬家 / 清洁字段", "引越し・清掃フィールド", "Moving & cleaning fields")
        case .lifeSetup: (zh, ja, en) = ("生活开通 / 住后支持字段", "生活手続きフィールド", "Life setup fields")
        case .beautyHealth: (zh, ja, en) = ("美容健康预约字段", "美容・健康予約フィールド", "Beauty & health fields")
        case .petFamily: (zh, ja, en) = ("宠物与家庭支持字段", "ペット・家庭サポートフィールド", "Pet & family fields")
        }
        return pickText(language, zh, ja, en)
    }

    static func serviceTypeOptions(for vertical: ServiceVertical) -> [String] {
        switch vertical {
        case .foodRestaurant:
            return ["餐厅美食"] + foodCategories
        case .diningBooking:
            return ["优惠预约"]
        case .lodging:
            return lodgingSectionCategories
        case .attractionTicket:
            return ["景点门票"]
        case .dayTour:
            return ["一日游", "本地向导", "体验活动", "包车行程"]
        case .airportTransfer:
            return transferSectionCategories
        case .paperworkTranslation:
            return paperworkSectionCategories
        case .movingCleaning:
            return movingSectionCategories
        case .lifeSetup:
            return lifeSetupSectionCategories
        case .beautyHealth:
            return beautyHealthSectionCategories
        case .petFamily:
            return petFamilySectionCategories
        }
    }

    /// Header copy in the viewer's app language. zh remains the source of
    /// truth; ja/en mirror web ListingKit's CHANNEL_TEXT so both clients
    /// read the same.
    static func title(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental", "stays", "hotels": (zh, ja, en) = ("租房 · 住宿", "賃貸・宿泊", "Homes & Stays")
        case "work":          (zh, ja, en) = ("工作", "求人", "Jobs")
        case "job":           (zh, ja, en) = ("找工作", "仕事を探す", "Find work")
        case "hiring":        (zh, ja, en) = ("招聘", "採用", "Hiring")
        case "local_service": (zh, ja, en) = ("商家与服务", "店舗・地域サービス", "Businesses & local services")
        case "discount":      (zh, ja, en) = ("优惠", "クーポン", "Deals")
        case "event":         (zh, ja, en) = ("活动", "イベント", "Events")
        default:              (zh, ja, en) = ("二手市场", "フリマ", "Marketplace")
        }
        return pickText(language, zh, ja, en)
    }

    static func subtitle(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental", "stays", "hotels":
            (zh, ja, en) = ("长租房源、民宿短住与酒店住宿", "賃貸・民泊・ホテルをまとめて探せる", "Long-term rentals, homestays and hotels")
        case "work", "job", "hiring":
            (zh, ja, en) = ("职位库、薪资、日语要求和签证支持", "求人・給与・日本語レベル・ビザサポート", "Jobs, salary, Japanese level, visa support")
        case "local_service":
            (zh, ja, en) = ("餐厅美食、点评订座、景点玩乐和生活支持", "グルメ・口コミ予約・観光体験・生活サポート", "Food & dining, reviews & booking, attractions and local support")
        case "discount":
            (zh, ja, en) = ("本地商家优惠与精选活动", "地元店舗の特典と注目イベント", "Local merchant deals and featured events")
        default:
            (zh, ja, en) = ("图片、价格、地点和交易状态", "写真・価格・場所・取引状況", "Photos, price, location and deal status")
        }
        return pickText(language, zh, ja, en)
    }

    /// Inline trilingual pick — file-wide helper for one-off UI strings.
    static func pickText(_ language: AppLanguage, _ zh: String, _ ja: String, _ en: String) -> String {
        switch language {
        case .ja: ja
        case .en: en
        default:  zh
        }
    }

    /// Detail-row titles, keyed by the canonical zh label used when the
    /// rows are built. Mirrors DETAIL_FIELD_LABELS in web listingFormat.ts
    /// so both clients read identically. Unknown labels pass through.
    private static let attributeLabels: [String: (ja: String, en: String)] = [
        "地区": ("エリア", "Area"),
        "最近车站": ("最寄り駅", "Nearest station"),
        "车站距离": ("駅からの距離", "To station"),
        "户型": ("間取り", "Layout"),
        "面积": ("面積", "Size"),
        "押金": ("敷金", "Deposit"),
        "礼金": ("礼金", "Key money"),
        "管理费": ("管理費", "Management fee"),
        "初期费用说明": ("初期費用について", "Initial costs"),
        "入住时间": ("入居可能日", "Move-in date"),
        "租期": ("契約期間", "Lease term"),
        "短租": ("短期", "Short-term"),
        "合租": ("ルームシェア", "Roomshare"),
        "家具家电": ("家具家電", "Furnished"),
        "宠物": ("ペット", "Pets"),
        "公司/店铺": ("会社・店舗", "Company"),
        "地点": ("場所", "Location"),
        "雇佣形式": ("雇用形態", "Employment type"),
        "薪资": ("給与", "Salary"),
        "薪资类型": ("給与形態", "Salary type"),
        "日语要求": ("日本語レベル", "Japanese level"),
        "签证支持": ("ビザサポート", "Visa support"),
        "签证支持说明": ("ビザサポート", "Visa support"),
        "工作时间": ("勤務時間", "Working hours"),
        "交通费": ("交通費", "Transport fee"),
        "外国人友好": ("外国人歓迎", "Foreigner friendly"),
        "无经验可": ("未経験OK", "No experience OK"),
        "留学生可": ("留学生OK", "Students OK"),
        "服务类型": ("サービス種別", "Service type"),
        "服务方": ("提供者", "Provider"),
        "服务范围": ("対応範囲", "Service scope"),
        "可服务城市": ("対応エリア", "Service area"),
        "价格": ("価格", "Price"),
        "起步价格": ("開始価格", "Starting price"),
        "价格单位": ("料金単位", "Price unit"),
        "可预约时间": ("予約可能時間", "Availability"),
        "营业时间": ("営業時間", "Business hours"),
        "价格区间": ("価格帯", "Price range"),
        "到店电话": ("店舗電話", "Store phone"),
        "预约制": ("予約制", "Reservation required"),
        "预约说明": ("予約について", "Reservation notes"),
        "服务语言": ("対応言語", "Service languages"),
        "认证服务方": ("認証済み提供者", "Verified provider"),
        "房型": ("客室タイプ", "Room type"),
        "可住人数": ("定員", "Guests"),
        "入住办理": ("チェックイン", "Check-in"),
        "退房时间": ("チェックアウト", "Check-out"),
        "最少入住": ("最低宿泊数", "Minimum stay"),
        "设施服务": ("設備・サービス", "Amenities"),
        "房量与日期": ("空室・日程", "Availability notes"),
        "含早餐": ("朝食付き", "Breakfast included"),
        "即时确认": ("即時確定", "Instant confirmation"),
        "资质/许可说明": ("資格・許認可", "License notes"),
        "票种": ("チケット種別", "Ticket type"),
        "日期/有效期": ("日付・有効期限", "Date / validity"),
        "时长": ("所要時間", "Duration"),
        "集合地点": ("集合場所", "Meeting point"),
        "包含内容": ("含まれるもの", "Included"),
        "不包含内容": ("含まれないもの", "Not included"),
        "含酒店接送": ("ホテル送迎付き", "Hotel pickup"),
        "机场/路线": ("空港・ルート", "Airport / route"),
        "车型": ("車種", "Vehicle type"),
        "人数": ("人数", "Passengers"),
        "行李数": ("荷物数", "Luggage"),
        "航班号说明": ("便名について", "Flight info"),
        "等待规则": ("待機ルール", "Waiting rule"),
        "夜间/追加费用": ("深夜・追加料金", "Surcharges"),
        "文件/手续类型": ("書類・手続き種別", "Document / procedure type"),
        "所需材料": ("必要書類", "Required materials"),
        "交付时间": ("納期", "Delivery time"),
        "结果说明": ("結果について", "Result note"),
        "房型/面积": ("間取り・面積", "Room / size"),
        "物品量": ("荷物量", "Item volume"),
        "车辆/人员": ("車両・スタッフ", "Vehicle / staff"),
        "追加费用": ("追加料金", "Extra fees"),
        "设备/项目类型": ("設備・作業種別", "Device / project"),
        "品牌/型号": ("ブランド・型番", "Brand / model"),
        "上门区域": ("出張エリア", "On-site area"),
        "上门费": ("出張費", "On-site fee"),
        "配件费": ("部品代", "Parts fee"),
        "保修说明": ("保証について", "Warranty"),
        "不可服务范围": ("対応不可範囲", "Unavailable scope"),
        "服务流程": ("サービスの流れ", "Process"),
        "用户需准备": ("ご準備いただくもの", "You prepare"),
        "取消规则": ("キャンセル規定", "Cancellation"),
        "审核状态": ("審査状況", "Review status"),
        "商家": ("店舗", "Merchant"),
        "优惠": ("特典", "Deal"),
        "优惠内容": ("特典内容", "Deal details"),
        "有效期": ("有効期限", "Valid until"),
        "使用规则": ("利用条件", "Usage rules"),
        "商家认证": ("店舗認証", "Merchant verification"),
        "状态": ("ステータス", "Status"),
        "发布类型": ("出品タイプ", "Listing type"),
        "分类": ("カテゴリ", "Category"),
        "新旧程度": ("状態", "Condition"),
        "原价/参考价": ("元値・参考価格", "Original/reference price"),
        "价格可议": ("価格相談", "Negotiable"),
        "购买时间": ("購入時期", "Purchase time"),
        "配件/包装": ("付属品・箱", "Accessories/box"),
        "瑕疵说明": ("傷・不具合", "Defects note"),
        "交易地点": ("受け渡し場所", "Meetup location"),
        "交易方式": ("受け渡し方法", "Delivery method"),
        "品牌": ("ブランド", "Brand"),
        "可交易时间": ("受け渡し可能時間", "Available time"),
        "取货说明": ("受け渡しメモ", "Pickup note"),
    ]

    static func attributeLabel(_ zhLabel: String, _ language: AppLanguage) -> String {
        guard let entry = attributeLabels[zhLabel.trimmingCharacters(in: .whitespaces)] else { return zhLabel }
        switch language {
        case .ja: return entry.ja
        case .en: return entry.en
        default:  return zhLabel
        }
    }

    static func icon(for type: String) -> String {
        switch type {
        case "rental": "house"
        case "work", "job", "hiring": "briefcase"
        case "local_service": "storefront"
        case "discount": "tag"
        case "event": "calendar"
        default: "bag"
        }
    }

    static func searchPlaceholder(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental":
            (zh, ja, en) = ("搜索地区、车站、学校、房源关键词", "エリア・駅・学校・物件キーワードを検索", "Search area, station, school, keywords")
        case "stays":
            (zh, ja, en) = ("搜索民宿、整套短住、地区关键词", "民泊・一棟貸し・エリアを検索", "Search homestays and short stays")
        case "hotels":
            (zh, ja, en) = ("搜索酒店、温泉旅馆、公寓式酒店", "ホテル・温泉旅館・アパートホテルを検索", "Search hotels, ryokan and aparthotels")
        case "work", "job", "hiring":
            (zh, ja, en) = ("搜索职位、公司、地点、日语要求", "職種・会社・場所・日本語レベルを検索", "Search roles, companies, locations")
        case "local_service":
            (zh, ja, en) = ("搜索餐饮预约、旅行票务、机场接送、翻译手续、生活服务", "飲食予約、旅行チケット、空港送迎、翻訳・手続き、生活サポートを検索", "Search dining, travel tickets, transfers, paperwork and local support")
        case "discount":
            (zh, ja, en) = ("搜索优惠、商家、地区", "特典・店舗・エリアを検索", "Search deals, merchants, areas")
        default:
            (zh, ja, en) = ("搜索家具、家电、教材、搬家出清", "家具・家電・教材・引越し処分を検索", "Search furniture, appliances, textbooks")
        }
        return pickText(language, zh, ja, en)
    }

    static func categories(for type: String) -> [String] {
        switch type {
        case "rental": ["全部", "单人", "合租", "短租", "整租", "家具家电", "近车站"]
        case "stays": stayChips
        case "hotels": hotelChips
        case "work", "job", "hiring": ["全部", "兼职", "全职", "时给", "月给", "N3 可", "签证支持", "无经验可"]
        case "local_service": ["全部"] + serviceCreateCategories
        case "discount": ["全部", "餐饮", "学校", "服务", "购物", "限时"]
        default: ["全部", "家具", "家电", "手机数码", "电脑办公", "电子产品", "教材", "书籍教材", "衣物", "生活用品", "母婴儿童", "运动户外", "票券卡券", "搬家出清", "免费送", "求购"]
        }
    }

    /// Display-only ja/en labels for category values. The zh string is the
    /// CANONICAL wire/storage format (listings store and filter by it —
    /// mirrors `CATEGORY_LABELS` in web ListingKit.tsx), so only the label
    /// localizes; the value sent to the API never changes. Unknown
    /// (user-typed) categories fall back to the raw value.
    private static let categoryLabels: [String: (ja: String, en: String)] = [
        "全部": ("すべて", "All"),
        "家具": ("家具", "Furniture"),
        "家电": ("家電", "Appliances"),
        "手机数码": ("スマホ・デジタル", "Phones & gadgets"),
        "电脑办公": ("PC・オフィス", "Computers & office"),
        "电子产品": ("電子機器", "Electronics"),
        "教材": ("教材", "Textbooks"),
        "书籍教材": ("本・教材", "Books & textbooks"),
        "衣物": ("衣類", "Clothing"),
        "生活用品": ("生活用品", "Daily goods"),
        "母婴儿童": ("ベビー・キッズ", "Baby & kids"),
        "运动户外": ("スポーツ・アウトドア", "Sports & outdoors"),
        "票券卡券": ("チケット・ギフト券", "Tickets & gift cards"),
        "搬家出清": ("引越し処分", "Moving sale"),
        "免费送": ("無料譲渡", "Free giveaway"),
        "求购": ("買います", "Wanted"),
        "单人": ("一人暮らし", "Single"),
        "合租": ("ルームシェア", "Roomshare"),
        "短租": ("短期", "Short-term"),
        "整租": ("まるごと賃貸", "Entire place"),
        "家具家电": ("家具家電付き", "Furnished"),
        "近车站": ("駅近", "Near station"),
        "兼职": ("アルバイト", "Part-time"),
        "全职": ("正社員", "Full-time"),
        "派遣": ("派遣", "Temp agency"),
        "实习": ("インターン", "Internship"),
        "时给": ("時給", "Hourly pay"),
        "月给": ("月給", "Monthly pay"),
        "N3 可": ("N3可", "N3 OK"),
        "无经验可": ("未経験OK", "No experience"),
        "留学生可": ("留学生OK", "Students OK"),
        "签证支持": ("ビザサポート", "Visa support"),
        "周末": ("週末", "Weekend"),
        "搬家": ("引越し", "Moving"),
        "签证": ("ビザ", "Visa"),
        "维修": ("修理", "Repair"),
        "翻译": ("翻訳", "Translation"),
        "接送": ("送迎", "Pickup"),
        "清洁": ("清掃", "Cleaning"),
        "美容美发": ("美容・ヘア", "Beauty & hair"),
        "宠物服务": ("ペットサービス", "Pet care"),
        "生活支持": ("生活サポート", "Life support"),
        "签证/手续协助": ("ビザ・手続きサポート", "Visa & paperwork"),
        "租房申请协助": ("賃貸申込サポート", "Rental application help"),
        "餐饮点评": ("飲食口コミ", "Dining reviews"),
        "优惠预约": ("予約特典", "Deals & booking"),
        "中华料理": ("中華料理", "Chinese"),
        "日本料理": ("日本料理", "Japanese"),
        "居酒屋": ("居酒屋", "Izakaya"),
        "烧肉火锅": ("焼肉・鍋", "BBQ & hot pot"),
        "拉面": ("ラーメン", "Ramen"),
        "寿司海鲜": ("寿司・海鮮", "Sushi & seafood"),
        "咖啡甜品": ("カフェ・スイーツ", "Café & desserts"),
        "西餐": ("洋食", "Western"),
        "韩国料理": ("韓国料理", "Korean"),
        "酒店民宿": ("ホテル・民泊", "Hotels & stays"),
        "民宿": ("民泊", "Guesthouse"),
        "酒店": ("ホテル", "Hotel"),
        "温泉旅馆": ("温泉旅館", "Onsen ryokan"),
        "公寓式酒店": ("アパートホテル", "Aparthotel"),
        "短住公寓": ("短期アパート", "Short-stay apartment"),
        "景点门票": ("観光チケット", "Attraction tickets"),
        "一日游": ("日帰りツアー", "Day trips"),
        "本地向导": ("ローカルガイド", "Local guide"),
        "体验活动": ("体験アクティビティ", "Experiences"),
        "包车行程": ("貸切ツアー", "Chartered tour"),
        "接送机": ("空港送迎", "Airport transfer"),
        "机场接送": ("空港送迎", "Airport transfer"),
        "车站接送": ("駅送迎", "Station transfer"),
        "包车": ("貸切車", "Private car"),
        "行李协助": ("荷物サポート", "Luggage help"),
        "翻译手续": ("翻訳・手続き", "Translation & paperwork"),
        "材料翻译": ("書類翻訳", "Document translation"),
        "市役所陪同": ("役所同行", "City-office accompaniment"),
        "银行卡协助": ("銀行口座サポート", "Bank account help"),
        "手机卡协助": ("SIMサポート", "SIM card help"),
        "签证材料整理": ("ビザ書類整理", "Visa document prep"),
        "搬家清洁": ("引越し・清掃", "Moving & cleaning"),
        "退房清洁": ("退去清掃", "Move-out cleaning"),
        "粗大垃圾协助": ("粗大ごみサポート", "Oversized trash help"),
        "行李搬运": ("荷物運搬", "Luggage moving"),
        "家具家电配送协助": ("家具家電配送サポート", "Furniture delivery help"),
        "手机卡开通": ("SIM開通", "SIM setup"),
        "网络开通": ("ネット開通", "Internet setup"),
        "水电煤协助": ("ライフライン手続き", "Utilities setup"),
        "地址登记协助": ("住所登録サポート", "Address registration help"),
        "粗大垃圾预约": ("粗大ごみ予約", "Oversized trash booking"),
        "生活跑腿": ("生活代行", "Local errands"),
        "美甲": ("ネイル", "Nails"),
        "按摩": ("マッサージ", "Massage"),
        "皮肤管理": ("肌ケア", "Skin care"),
        "体检/牙科预约协助": ("健診・歯科予約サポート", "Checkup/dental booking help"),
        "宠物寄养": ("ペット預かり", "Pet boarding"),
        "遛狗": ("犬の散歩", "Dog walking"),
        "临时照看": ("一時見守り", "Temporary care"),
        "儿童用品租赁": ("子ども用品レンタル", "Kids item rental"),
        "家庭协助": ("家庭サポート", "Family support"),
        "认证服务": ("認定サービス", "Verified services"),
        "餐饮": ("飲食", "Dining"),
        "学校": ("学校", "Schools"),
        "服务": ("サービス", "Services"),
        "购物": ("ショッピング", "Shopping"),
        "限时": ("期間限定", "Limited-time"),
        "生活": ("生活", "Living"),
        "学习": ("学習", "Study"),
        "今天": ("今日", "Today"),
        "本周": ("今週", "This week"),
        "免费": ("無料", "Free"),
    ]

    static func categoryLabel(_ value: String, _ language: AppLanguage) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entry = categoryLabels[trimmed] else { return value }
        switch language {
        case .ja: return entry.ja
        case .en: return entry.en
        default:  return value
        }
    }

    static func emptyTitle(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental":               (zh, ja, en) = ("这里还没有房源", "まだ物件がありません", "No rentals yet")
        case "stays":                (zh, ja, en) = ("这里还没有民宿和酒店", "まだ宿泊施設がありません", "No stays yet")
        case "hotels":               (zh, ja, en) = ("这里还没有酒店住宿", "まだホテルがありません", "No hotels yet")
        case "work", "job", "hiring": (zh, ja, en) = ("这里还没有工作信息", "まだ求人がありません", "No jobs yet")
        case "local_service":        (zh, ja, en) = ("这里还没有商家与服务", "まだ店舗・地域サービスがありません", "No business or local services yet")
        case "discount":             (zh, ja, en) = ("这里还没有优惠", "まだ特典がありません", "No deals yet")
        default:                     (zh, ja, en) = ("这里还没有二手商品", "まだ出品がありません", "No items yet")
        }
        return pickText(language, zh, ja, en)
    }

    static func emptySubtitle(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental":
            (zh, ja, en) = ("发布房源或稍后查看新的租房信息。", "物件を掲載するか、また後で見に来てください。", "Post a rental or check back soon.")
        case "stays":
            (zh, ja, en) = ("认证服务方可以发布民宿和短住，审核通过后展示给同城旅客。", "認証ホストの民泊・短期滞在が審査後に表示されます。", "Verified homestays appear here after review.")
        case "hotels":
            (zh, ja, en) = ("认证商家可以发布酒店、温泉旅馆和公寓式酒店，审核通过后展示。", "認証施設のホテル・旅館・アパートホテルが審査後に表示されます。", "Verified hotels and ryokan appear here after review.")
        case "work", "job", "hiring":
            (zh, ja, en) = ("稍后查看新的同城工作机会。", "新しい求人をまた後でチェックしてください。", "Check back soon for new local jobs.")
        case "local_service":
            (zh, ja, en) = ("认证商家的餐饮预约、旅行票务、接送交通、翻译手续、搬家清洁和生活服务审核后会展示在这里。", "認証店舗の飲食予約、旅行チケット、送迎、翻訳・手続き、引越し清掃、生活サポートが審査後に表示されます。", "Verified dining, travel, transfers, paperwork, moving and local support appear here after review.")
        case "discount":
            (zh, ja, en) = ("商家优惠审核后会展示在这里。", "店舗特典が審査後にここに表示されます。", "Merchant deals appear here after review.")
        default:
            (zh, ja, en) = ("发布第一个闲置，让同城的人看到它。", "最初の出品をして、近くの人に届けよう。", "List the first item for your city to see.")
        }
        return pickText(language, zh, ja, en)
    }

    static func createTitle(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental": (zh, ja, en) = ("发布房源", "物件を投稿", "Post rental")
        case "job": (zh, ja, en) = ("发布求职信息", "求職情報を投稿", "Post job-seeking profile")
        case "work", "hiring": (zh, ja, en) = ("发布招聘", "求人を投稿", "Post job")
        case "local_service": (zh, ja, en) = ("发布商家与服务", "店舗・サービスを投稿", "Post business/service")
        case "discount": (zh, ja, en) = ("发布优惠", "特典を投稿", "Post deal")
        default: (zh, ja, en) = ("发布二手", "出品する", "List item")
        }
        return pickText(language, zh, ja, en)
    }

    static func createGuidance(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental":
            (zh, ja, en) = ("把租金、车站、户型、面积和入住时间写清楚，房源会更容易被认真咨询。", "家賃、駅、間取り、面積、入居時期を明確にすると、質の高い問い合わせが増えます。", "Clear rent, station, layout, size, and move-in timing bring better inquiries.")
        case "work", "job", "hiring":
            (zh, ja, en) = ("岗位、工作时间、日语要求和签证说明越清楚，越能减少无效沟通。", "職種、勤務時間、日本語レベル、ビザ条件を明確にすると無駄なやり取りを減らせます。", "Clear role, hours, Japanese level, and visa notes reduce unqualified messages.")
        case "local_service":
            (zh, ja, en) = ("先选择一级服务，再选细分类。系统只展示该服务真正需要的字段，资质、价格、服务边界和取消规则会直接影响审核与用户信任。", "大カテゴリから細分類を選ぶと、そのサービスに必要な項目だけ表示されます。資格、料金、範囲、取消規定は審査と信頼に直結します。", "Choose a primary service, then a subcategory. Only relevant fields appear; credentials, pricing, boundaries, and cancellation rules affect review and trust.")
        case "discount":
            (zh, ja, en) = ("优惠内容、有效期和使用规则需要明确，避免用户到店后产生误解。", "特典内容、有効期限、利用条件を明確にして、来店時の誤解を防ぎましょう。", "Make deal details, validity, and usage rules clear to avoid confusion in-store.")
        default:
            (zh, ja, en) = ("清楚的照片、价格、地点和新旧程度，会让同城交易更快也更安全。", "写真、価格、場所、状態が明確だと、地域取引はより速く安全になります。", "Clear photos, price, location, and condition make local trades faster and safer.")
        }
        return pickText(language, zh, ja, en)
    }

    static func createType(for type: String) -> String {
        type == "work" ? "hiring" : type
    }

    static func submitLabel(for type: String, _ language: AppLanguage = .zh) -> String {
        type == "secondhand"
            ? pickText(language, "发布", "投稿", "Post")
            : pickText(language, "提交审核", "審査に送信", "Submit for review")
    }

    static func categoryPlaceholder(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental": (zh, ja, en) = ("类型，例如 单人 / 合租 / 短租", "種類：一人暮らし / ルームシェア / 短期", "Type, e.g. single / share / short-term")
        case "work", "job", "hiring": (zh, ja, en) = ("行业或岗位分类", "業種または職種カテゴリ", "Industry or role category")
        case "local_service": (zh, ja, en) = ("服务分类，例如 日本料理 / 民宿 / 景点门票 / 机场接送", "サービス分類：日本料理 / 民泊 / 観光チケット / 空港送迎", "Service category, e.g. Japanese dining / stay / tickets / airport transfer")
        case "discount": (zh, ja, en) = ("优惠分类", "特典カテゴリ", "Deal category")
        default: (zh, ja, en) = ("分类，例如 家具 / 家电 / 教材", "カテゴリ：家具 / 家電 / 教材", "Category, e.g. furniture / appliances / textbooks")
        }
        return pickText(language, zh, ja, en)
    }

    static func titlePlaceholder(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental": (zh, ja, en) = ("例如 池袋 1K 公寓，可预约看房", "例：池袋 1K、内見予約可", "e.g. Ikebukuro 1K, viewing available")
        case "work", "job", "hiring": (zh, ja, en) = ("例如 新宿咖啡店周末兼职", "例：新宿カフェの週末アルバイト", "e.g. Weekend cafe shift in Shinjuku")
        case "local_service": (zh, ja, en) = ("例如 东京周末一日游 / 机场接送 / 材料翻译协助", "例：東京週末ツアー / 空港送迎 / 書類翻訳サポート", "e.g. Tokyo day tour / airport transfer / document translation")
        case "discount": (zh, ja, en) = ("例如 留学生套餐 9 折", "例：留学生セット 10% オフ", "e.g. 10% off student set")
        default: (zh, ja, en) = ("例如 日文配列键盘 / 搬家出清书桌", "例：日本語配列キーボード / 引越し処分デスク", "e.g. Japanese keyboard / moving-sale desk")
        }
        return pickText(language, zh, ja, en)
    }

    static func pricePlaceholder(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental": (zh, ja, en) = ("月租，例如 58000", "月額家賃：例 58000", "Monthly rent, e.g. 58000")
        case "work", "job", "hiring": (zh, ja, en) = ("薪资，例如 1200", "給与：例 1200", "Pay, e.g. 1200")
        default: (zh, ja, en) = ("价格，例如 8000", "価格：例 8000", "Price, e.g. 8000")
        }
        return pickText(language, zh, ja, en)
    }

    static func descriptionPlaceholder(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental":
            (zh, ja, en) = ("写清房间状态、费用包含项、初期费用、可入住时间、看房方式。", "部屋の状態、費用に含まれるもの、初期費用、入居可能時期、内見方法を書いてください。", "Describe room condition, included costs, initial fees, move-in timing, and viewing method.")
        case "work", "job", "hiring":
            (zh, ja, en) = ("写清工作内容、薪资、排班、试用期、交通费和需要准备的材料。", "仕事内容、給与、シフト、試用期間、交通費、必要書類を書いてください。", "Describe duties, pay, schedule, probation, transport fee, and required materials.")
        case "local_service":
            (zh, ja, en) = ("写清适合谁、服务包含/不包含什么、预约规则、旅行/景点说明、取消退款规则，以及预约前需要准备的信息。", "対象者、含まれる内容・含まれない内容、予約規則、旅行/観光説明、取消・返金規定、事前準備を書いてください。", "Explain who it suits, what is included/excluded, booking rules, travel or attraction notes, cancellation/refund rules, and what users should prepare.")
        case "discount":
            (zh, ja, en) = ("写清适用门店、适用人群、不可叠加条件和使用方式。", "対象店舗、対象者、併用不可条件、利用方法を書いてください。", "Describe eligible stores, audience, non-stackable conditions, and how to use it.")
        default:
            (zh, ja, en) = ("写清购买时间、使用情况、瑕疵、配件、交易地点和是否可议价。", "購入時期、使用状況、傷、付属品、受け渡し場所、価格相談可否を書いてください。", "Describe purchase time, usage, defects, accessories, meetup location, and negotiability.")
        }
        return pickText(language, zh, ja, en)
    }

    static func defaultCategory(for type: String) -> String {
        switch type {
        case "rental": "房源"
        case "work", "job", "hiring": "职位"
        case "local_service": "商家与服务"
        case "discount": "优惠"
        default: "二手"
        }
    }

    static func formatListingType(_ type: String) -> String {
        title(for: type)
    }

    static func formatListingStatus(_ status: String, type: String? = nil, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch normalized(status) {
        case "draft": (zh, ja, en) = ("草稿", "下書き", "Draft")
        case "pending_review": (zh, ja, en) = ("审核中", "審査中", "In review")
        case "reserved": (zh, ja, en) = ("已预约", "予約済み", "Reserved")
        case "sold": (zh, ja, en) = ("已售出", "売約済み", "Sold")
        case "rented": (zh, ja, en) = ("已租出", "成約済み", "Rented")
        case "closed": (zh, ja, en) = ("已关闭", "終了", "Closed")
        case "expired": (zh, ja, en) = ("已过期", "期限切れ", "Expired")
        case "rejected": (zh, ja, en) = ("已拒绝", "却下", "Rejected")
        case "hidden": (zh, ja, en) = ("已下架", "非公開", "Hidden")
        case "published":
            switch type {
            case "rental": (zh, ja, en) = ("可咨询", "問い合わせ可", "Open")
            case "job", "hiring": (zh, ja, en) = ("招聘中", "募集中", "Hiring")
            case "local_service": (zh, ja, en) = ("可预约", "予約可", "Bookable")
            case "discount": (zh, ja, en) = ("有效中", "有効", "Active")
            case "event": (zh, ja, en) = ("开放报名", "受付中", "Open")
            default: (zh, ja, en) = ("出售中", "販売中", "Available")
            }
        default: (zh, ja, en) = ("待补充", "未設定", "Pending")
        }
        return pickText(language, zh, ja, en)
    }

    static func formatVerificationStatus(_ status: String, _ language: AppLanguage = .zh) -> String {
        switch normalized(status) {
        case "verified": pickText(language, "认证", "認証済み", "Verified")
        case "pending": pickText(language, "待核验", "確認待ち", "Pending verification")
        case "needs_review": pickText(language, "需复核", "再確認が必要", "Needs review")
        case "rejected": pickText(language, "认证拒绝", "認証却下", "Verification rejected")
        case "unverified": pickText(language, "未认证", "未認証", "Unverified")
        default: pickText(language, "未认证", "未認証", "Unverified")
        }
    }

    static func formatEmploymentType(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        return switch normalized(value) {
        case "full_time", "full-time": "全职"
        case "part_time", "part-time": "兼职"
        case "dispatch": "派遣"
        case "contract": "契约"
        case "internship": "实习"
        case "freelance": "自由职业"
        case "temporary": "短期"
        default: value
        }
    }

    static func employmentTypeKey(_ value: String) -> String {
        switch normalized(value) {
        case "全职", "full_time", "full-time": "full_time"
        case "派遣", "dispatch": "dispatch"
        case "契约", "contract": "contract"
        case "实习", "internship": "internship"
        case "自由职业", "freelance": "freelance"
        case "短期", "temporary": "temporary"
        default: "part_time"
        }
    }

    static func employmentTypeLabel(_ value: String) -> String {
        let label = formatEmploymentType(value)
        return label.isEmpty ? "兼职" : label
    }

    static func conditionKey(_ value: String) -> String {
        switch normalized(value) {
        case "全新", "brand_new", "new": "brand_new"
        case "几乎全新", "like_new": "like_new"
        case "有使用痕迹", "used": "used"
        case "可用", "fair": "fair"
        default: "good"
        }
    }

    static func conditionLabel(_ value: String) -> String {
        switch normalized(value) {
        case "brand_new", "new", "全新": "全新"
        case "like_new", "几乎全新": "几乎全新"
        case "used", "有使用痕迹": "有使用痕迹"
        case "fair", "可用": "可用"
        default: "良好"
        }
    }

    static func listingModeKey(_ value: String) -> String {
        switch normalized(value) {
        case "免费送", "free", "giveaway": "free"
        case "求购", "wanted", "buy": "wanted"
        default: "sale"
        }
    }

    static func listingModeLabel(_ value: String) -> String {
        switch normalized(value) {
        case "free", "giveaway", "免费送": "免费送"
        case "wanted", "buy", "求购": "求购"
        default: "出售"
        }
    }

    static func formatSalaryType(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        return switch normalized(value) {
        case "hourly", "hour": "时给"
        case "daily": "日给"
        case "weekly": "周给"
        case "monthly", "month": "月给"
        case "annual", "yearly": "年薪"
        case "fixed": "固定价"
        case "negotiable": "可商量"
        default: value
        }
    }

    static func formatCurrency(_ currency: String?) -> String {
        switch normalized(currency ?? "JPY").uppercased() {
        case "JPY": "日元"
        case "CNY": "人民币"
        case "USD": "美元"
        case "EUR": "欧元"
        case "KRW": "韩元"
        default: cleanText(currency) ?? "日元"
        }
    }

    static func formatPrice(_ listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> String {
        let type = listing.type
        let priceType = normalized(listing.price_type ?? "")
        if priceType == "free" { return pickText(language, "免费", "無料", "Free") }
        if ["appointment_only", "quote_required", "consultation", "negotiable"].contains(priceType) {
            return fallbackPriceLabel(for: type, language)
        }
        guard let price = listing.price, price.isFinite, price > 0 else {
            return fallbackPriceLabel(for: type, language)
        }
        let amount = price.rounded() == price
            ? NumberFormatter.localizedString(from: NSNumber(value: Int(price)), number: .decimal)
            : String(format: "%.2f", price)
        let code = (listing.currency ?? "JPY").uppercased()
        let prefix: String = {
            switch code {
            case "JPY", "CNY": return "¥"
            case "USD": return "$"
            case "EUR": return "€"
            case "KRW": return "₩"
            default: return "\(code) "
            }
        }()
        let rendered = "\(prefix)\(amount)"
        switch priceType {
        case "monthly", "month": return "\(rendered)\(pickText(language, "/月", "/月", "/mo"))"
        case "hourly", "hour": return "\(rendered)\(pickText(language, "/小时", "/時", "/hr"))"
        case "per_night", "nightly": return "\(rendered)\(pickText(language, "/晚", "/泊", "/night"))"
        case "daily": return "\(rendered)\(pickText(language, "/日", "/日", "/day"))"
        case "weekly": return "\(rendered)\(pickText(language, "/周", "/週", "/wk"))"
        case "yearly", "annual": return "\(rendered)\(pickText(language, "/年", "/年", "/yr"))"
        case "starting_from": return "\(rendered) \(pickText(language, "起", "から", "and up"))"
        default:
            if type == "rental" { return "\(rendered)\(pickText(language, "/月", "/月", "/mo"))" }
            if type == "job" || type == "hiring" { return "\(rendered)\(pickText(language, "/小时", "/時", "/hr"))" }
            return rendered
        }
    }

    static func formatArea(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        if let number = Double(value), number.isFinite, number > 0 {
            let text = number.rounded() == number ? "\(Int(number))" : String(format: "%.1f", number)
            return "\(text) m²"
        }
        return value
    }

    static func formatStationDistance(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        if let number = Double(value), number.isFinite, number > 0 {
            return "步行 \(Int(number.rounded())) 分钟"
        }
        return value
    }

    static func formatDate(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return value
    }

    static func formatJapaneseLevel(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        switch normalized(value) {
        case "not_required", "none", "no_requirement":
            return "不限"
        case "native":
            return "母语级"
        case "business":
            return "商务日语"
        case "daily":
            return "日常会话"
        default:
            let upper = value.uppercased()
            return ["N1", "N2", "N3", "N4", "N5"].contains(upper) ? upper : value
        }
    }

    static func priceLabel(_ listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> String {
        formatPrice(listing, language)
    }

    static func displayTitle(_ listing: KaiXCityListingDTO) -> String {
        guard listing.type == "rental" else { return listing.title }
        return listing.title
            .replacingOccurrences(of: "，外国人可咨询", with: "，可预约看房")
            .replacingOccurrences(of: "外国人可咨询", with: "可预约看房")
            .replacingOccurrences(of: "，外国人可", with: "")
            .replacingOccurrences(of: "外国人可", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compactMeta(_ listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> String {
        [cleanText(listing.location_text), attr(listing, "condition"), attr(listing, "available_time"), statusLabel(listing.status, type: listing.type, language)]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    static func structuredMeta(_ listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> String {
        switch listing.type {
        case "rental":
            return [cleanText(listing.location_text), attr(listing, "nearest_station"), attr(listing, "layout"), attr(listing, "area_sqm")]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        case "job", "hiring":
            let level = attr(listing, "japanese_level") ?? pickText(language, "未注明", "未記入", "Not specified")
            return [attr(listing, "company_name"), cleanText(listing.location_text), attr(listing, "employment_type"), "\(pickText(language, "日语", "日本語", "Japanese")) \(level)"]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        case "local_service":
            return [attr(listing, "service_type"), attr(listing, "service_area"), attr(listing, "price_unit"), attr(listing, "availability")]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        case "discount":
            return [attr(listing, "merchant_name"), cleanText(listing.location_text), attr(listing, "valid_until").map { "\(pickText(language, "有效至", "有効期限", "Valid until")) \($0)" }]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        default:
            return compactMeta(listing, language)
        }
    }

    static func badges(for listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> [String] {
        var result: [String] = []
        if listing.verification_status == "pending" { result.append(formatVerificationStatus(listing.verification_status, language)) }
        if listing.verification_status == "verified" { result.append(formatVerificationStatus(listing.verification_status, language)) }
        switch listing.type {
        case "rental":
            if boolAttr(listing, "short_term_allowed") { result.append(pickText(language, "短租", "短期可", "Short-term")) }
            if boolAttr(listing, "share_allowed") { result.append(pickText(language, "合租", "シェア可", "Shared OK")) }
            if boolAttr(listing, "furnished") { result.append(pickText(language, "家具家电", "家具家電付き", "Furnished")) }
        case "job", "hiring":
            if boolAttr(listing, "visa_support") { result.append(pickText(language, "签证支持", "ビザサポート", "Visa support")) }
            if let level = attr(listing, "japanese_level") { result.append("\(pickText(language, "日语", "日本語", "Japanese")) \(level)") }
            if let employment = attr(listing, "employment_type") { result.append(employment) }
        case "local_service":
            if let service = attr(listing, "service_type") { result.append(service) }
            if boolAttr(listing, "certified_provider") || listing.verification_status == "verified" { result.append(pickText(language, "认证服务方", "認証済みサービス", "Verified provider")) }
            if let area = attr(listing, "service_area") { result.append(area) }
        case "discount":
            if let merchant = attr(listing, "merchant_name") { result.append(merchant) }
            if let validUntil = attr(listing, "valid_until") { result.append("\(pickText(language, "有效至", "有効期限", "Valid until")) \(validUntil)") }
            if boolAttr(listing, "merchant_verified") || listing.verification_status == "verified" { result.append(pickText(language, "认证商家", "認証済み店舗", "Verified merchant")) }
        default:
            if let condition = attr(listing, "condition") { result.append(condition) }
            if boolAttr(listing, "pickup_available") { result.append(pickText(language, "可自取", "手渡し可", "Pickup OK")) }
            if boolAttr(listing, "shipping_available") { result.append(pickText(language, "可邮寄", "配送可", "Shipping OK")) }
            if let time = attr(listing, "available_time") { result.append(time) }
        }
        return result
    }

    static func secondhandCardBadges(for listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> [String] {
        guard listing.type == "secondhand" else { return [] }
        var result: [String] = []
        if let mode = attr(listing, "listing_mode") { result.append(mode) }
        if boolAttr(listing, "price_negotiable") { result.append(pickText(language, "可议价", "価格相談可", "Negotiable")) }
        if boolAttr(listing, "pickup_available") { result.append(pickText(language, "可自取", "手渡し可", "Pickup OK")) }
        if boolAttr(listing, "shipping_available") { result.append(pickText(language, "可邮寄", "配送可", "Shipping OK")) }
        if let condition = attr(listing, "condition") { result.append(condition) }
        return result
    }

    static func attributes(for listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> [(String, String)] {
        let base: [(String, String?)]
        switch listing.type {
        case "rental":
            base = [
                ("月租", priceLabel(listing, language)),
                ("地区", cleanText(listing.location_text)),
                ("最近车站", attr(listing, "nearest_station")),
                ("户型", attr(listing, "layout")),
                ("面积", attr(listing, "area_sqm")),
                ("入住时间", attr(listing, "move_in_date")),
                ("合租", boolAttr(listing, "share_allowed") ? "可" : "未注明"),
                ("短租", boolAttr(listing, "short_term_allowed") ? "可" : "未注明"),
                ("家具家电", boolAttr(listing, "furnished") ? "有" : "未注明"),
            ]
        case "job", "hiring":
            // visa_support 历史上存过布尔（true/false），现统一为枚举
            // none/consult/available——两种 wire 值都要能读。
            let visaRaw = rawAttribute(listing, "visa_support")
            let visaLabel: String? = switch visaRaw {
            case "available", "true", "1", "yes": "支持"
            case "consult": "可咨询"
            case "none", "false": "无"
            default: nil
            }
            base = [
                ("薪资", priceLabel(listing, language)),
                ("公司/店铺", attr(listing, "company_name")),
                ("地点", cleanText(listing.location_text)),
                ("雇佣形式", attr(listing, "employment_type")),
                ("日语要求", attr(listing, "japanese_level")),
                ("签证支持", visaLabel ?? "未注明"),
                ("工作时间", attr(listing, "working_hours")),
                ("休日休假", attr(listing, "holidays")),
                ("试用期", attr(listing, "trial_period")),
                ("福利待遇", attr(listing, "benefits")),
                ("无经验可", boolAttr(listing, "no_experience_ok") ? "可" : nil),
                ("留学生可", boolAttr(listing, "student_ok") ? "可" : nil),
                ("可远程", boolAttr(listing, "remote_ok") ? "可" : nil),
                ("审核状态", verificationLabel(listing.verification_status, language)),
            ]
        case "local_service":
            switch serviceVertical(for: listing) {
            case .foodRestaurant?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("营业时间", attr(listing, "open_hours")),
                    ("价格区间", attr(listing, "price_range")),
                    ("最近车站", attr(listing, "near_station")),
                    ("到店电话", attr(listing, "store_phone")),
                    ("预约制", boolAttr(listing, "reservation_required") ? "需要预约" : nil),
                    ("预约说明", attr(listing, "reservation_note")),
                    ("服务语言", attr(listing, "languages")),
                    ("认证服务方", boolAttr(listing, "certified_provider") || listing.verification_status == "verified" ? "已认证" : nil),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .diningBooking?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("营业时间", attr(listing, "open_hours")),
                    ("价格区间", attr(listing, "price_range")),
                    ("最近车站", attr(listing, "near_station")),
                    ("到店电话", attr(listing, "store_phone")),
                    ("可预约时间", attr(listing, "availability")),
                    ("预约制", boolAttr(listing, "booking_required") || boolAttr(listing, "reservation_required") ? "需要预约" : nil),
                    ("预约说明", attr(listing, "reservation_note")),
                    ("服务流程", attr(listing, "service_process")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("服务语言", attr(listing, "languages")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .lodging?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("房型", attr(listing, "room_type")),
                    ("可住人数", attr(listing, "max_guests")),
                    ("价格单位", attr(listing, "price_unit")),
                    ("入住办理", attr(listing, "check_in_time")),
                    ("退房时间", attr(listing, "check_out_time")),
                    ("最少入住", attr(listing, "minimum_stay")),
                    ("设施服务", attr(listing, "amenities")),
                    ("房量与日期", attr(listing, "inventory_note")),
                    ("含早餐", boolAttr(listing, "breakfast_included") ? "包含" : nil),
                    ("即时确认", boolAttr(listing, "instant_confirmation") ? "支持" : nil),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("资质/许可说明", attr(listing, "license_note")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .attractionTicket?, .dayTour?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("票种", attr(listing, "ticket_type")),
                    ("日期/有效期", attr(listing, "availability")),
                    ("时长", attr(listing, "duration")),
                    ("集合地点", attr(listing, "meeting_point")),
                    ("包含内容", attr(listing, "included_items")),
                    ("不包含内容", attr(listing, "not_included")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("含酒店接送", boolAttr(listing, "pickup_service") ? "包含" : nil),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("资质/许可说明", attr(listing, "license_note")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .airportTransfer?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("机场/路线", attr(listing, "airport_route")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("车型", attr(listing, "vehicle_type")),
                    ("人数", attr(listing, "passenger_count")),
                    ("行李数", attr(listing, "luggage_count")),
                    ("航班号说明", attr(listing, "flight_info_note")),
                    ("等待规则", attr(listing, "waiting_rule")),
                    ("夜间/追加费用", attr(listing, "surcharge_note")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .paperworkTranslation?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务语言", attr(listing, "languages")),
                    ("文件/手续类型", attr(listing, "document_type")),
                    ("所需材料", attr(listing, "required_materials")),
                    ("交付时间", attr(listing, "delivery_time")),
                    ("服务流程", attr(listing, "service_process")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("结果说明", boolAttr(listing, "no_result_guarantee") ? "不保证结果" : nil),
                    ("资质/许可说明", attr(listing, "license_note")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .movingCleaning?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("房型/面积", attr(listing, "property_size")),
                    ("物品量", attr(listing, "item_volume")),
                    ("车辆/人员", attr(listing, "vehicle_staff")),
                    ("包含内容", attr(listing, "included_items")),
                    ("不包含内容", attr(listing, "not_included")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("追加费用", attr(listing, "surcharge_note")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .lifeSetup?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("办理类型", attr(listing, "setup_type")),
                    ("所需材料", attr(listing, "required_materials")),
                    ("交付时间", attr(listing, "delivery_time")),
                    ("服务流程", attr(listing, "service_process")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("结果说明", attr(listing, "cannot_guarantee")),
                    ("价格区间", attr(listing, "price_range")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .beautyHealth?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("服务项目", attr(listing, "beauty_service")),
                    ("可预约时间", attr(listing, "availability")),
                    ("价格区间", attr(listing, "price_range")),
                    ("服务时长", attr(listing, "duration")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("安全说明", attr(listing, "medical_disclaimer")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .petFamily?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("服务对象", attr(listing, "service_target")),
                    ("可预约时间", attr(listing, "availability")),
                    ("价格区间", attr(listing, "price_range")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("资质/许可说明", attr(listing, "license_note")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .none:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("价格单位", attr(listing, "price_unit")),
                    ("可预约时间", attr(listing, "availability")),
                    ("服务流程", attr(listing, "service_process")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            }
        case "discount":
            base = [
                ("优惠", priceLabel(listing, language)),
                ("商家", attr(listing, "merchant_name")),
                ("地点", cleanText(listing.location_text)),
                ("优惠内容", attr(listing, "discount_info")),
                ("有效期", attr(listing, "valid_until")),
                ("使用规则", attr(listing, "usage_rules")),
                ("商家认证", boolAttr(listing, "merchant_verified") || listing.verification_status == "verified" ? "已认证" : "待核验"),
            ]
        default:
            base = [
                ("价格", priceLabel(listing, language)),
                ("地点", cleanText(listing.location_text)),
                ("分类", cleanText(listing.category)),
                ("发布类型", attr(listing, "listing_mode")),
                ("品牌", attr(listing, "brand")),
                ("新旧程度", attr(listing, "condition")),
                ("原价/参考价", attr(listing, "original_price")),
                ("价格可议", boolAttr(listing, "price_negotiable") ? "可商量" : nil),
                ("购买时间", attr(listing, "purchase_time")),
                ("配件/包装", attr(listing, "accessories")),
                ("瑕疵说明", attr(listing, "defect_note")),
                ("可交易时间", attr(listing, "available_time")),
                ("交易方式", attr(listing, "delivery_method")),
                ("取货说明", attr(listing, "pickup_note")),
                ("状态", statusLabel(listing.status, type: listing.type, language)),
            ]
        }
        return base.compactMap { key, value in
            guard let value, !value.isEmpty else { return nil }
            return (localizedAttributeLabel(key, language), localizedAttributeValue(value, language))
        }
    }

    private static func localizedAttributeLabel(_ key: String, _ language: AppLanguage) -> String {
        switch key {
        case "月租": pickText(language, "月租", "月額家賃", "Monthly rent")
        case "地区": pickText(language, "地区", "エリア", "Area")
        case "最近车站": pickText(language, "最近车站", "最寄り駅", "Nearest station")
        case "户型": pickText(language, "户型", "間取り", "Layout")
        case "面积": pickText(language, "面积", "面積", "Area size")
        case "入住时间": pickText(language, "入住时间", "入居時期", "Move-in")
        case "合租": pickText(language, "合租", "シェア", "Shared")
        case "短租": pickText(language, "短租", "短期", "Short-term")
        case "家具家电": pickText(language, "家具家电", "家具家電", "Furnished")
        case "薪资": pickText(language, "薪资", "給与", "Pay")
        case "公司/店铺": pickText(language, "公司/店铺", "会社・店舗", "Company/store")
        case "地点": pickText(language, "地点", "場所", "Location")
        case "雇佣形式": pickText(language, "雇佣形式", "雇用形態", "Employment type")
        case "日语要求": pickText(language, "日语要求", "日本語要件", "Japanese level")
        case "签证支持": pickText(language, "签证支持", "ビザサポート", "Visa support")
        case "工作时间": pickText(language, "工作时间", "勤務時間", "Working hours")
        case "休日休假": pickText(language, "休日休假", "休日・休暇", "Holidays")
        case "试用期": pickText(language, "试用期", "試用期間", "Trial period")
        case "福利待遇": pickText(language, "福利待遇", "福利厚生", "Benefits")
        case "无经验可": pickText(language, "无经验可", "未経験可", "No experience OK")
        case "留学生可": pickText(language, "留学生可", "留学生可", "Students OK")
        case "可远程": pickText(language, "可远程", "リモート可", "Remote OK")
        case "审核状态": pickText(language, "审核状态", "審査状態", "Review status")
        case "起步价格": pickText(language, "起步价格", "開始価格", "Starting price")
        case "服务方": pickText(language, "服务方", "提供者", "Provider")
        case "服务类型": pickText(language, "服务类型", "サービス種別", "Service type")
        case "服务范围": pickText(language, "服务范围", "対応範囲", "Service area")
        case "营业时间": pickText(language, "营业时间", "営業時間", "Hours")
        case "价格区间": pickText(language, "价格区间", "価格帯", "Price range")
        case "到店电话": pickText(language, "到店电话", "店舗電話", "Phone")
        case "预约制": pickText(language, "预约制", "予約制", "Reservation")
        case "预约说明": pickText(language, "预约说明", "予約説明", "Booking notes")
        case "服务语言": pickText(language, "服务语言", "対応言語", "Languages")
        case "认证服务方": pickText(language, "认证服务方", "認証済み提供者", "Verified provider")
        case "可预约时间": pickText(language, "可预约时间", "予約可能時間", "Available times")
        case "服务流程": pickText(language, "服务流程", "サービス手順", "Service flow")
        case "取消规则": pickText(language, "取消规则", "キャンセル規定", "Cancellation")
        case "房型": pickText(language, "房型", "部屋タイプ", "Room type")
        case "可住人数": pickText(language, "可住人数", "定員", "Guests")
        case "价格单位": pickText(language, "价格单位", "価格単位", "Price unit")
        case "入住办理": pickText(language, "入住办理", "チェックイン", "Check-in")
        case "退房时间": pickText(language, "退房时间", "チェックアウト", "Check-out")
        case "最少入住": pickText(language, "最少入住", "最低宿泊", "Minimum stay")
        case "设施服务": pickText(language, "设施服务", "設備", "Amenities")
        case "房量与日期": pickText(language, "房量与日期", "空室・日程", "Availability")
        case "含早餐": pickText(language, "含早餐", "朝食付き", "Breakfast")
        case "即时确认": pickText(language, "即时确认", "即時確認", "Instant confirmation")
        case "资质/许可说明": pickText(language, "资质/许可说明", "資格・許可", "License notes")
        case "票种": pickText(language, "票种", "チケット種別", "Ticket type")
        case "日期/有效期": pickText(language, "日期/有效期", "日付・有効期限", "Date/validity")
        case "时长": pickText(language, "时长", "所要時間", "Duration")
        case "集合地点": pickText(language, "集合地点", "集合場所", "Meeting point")
        case "包含内容": pickText(language, "包含内容", "含まれるもの", "Included")
        case "不包含内容": pickText(language, "不包含内容", "含まれないもの", "Not included")
        case "用户需准备": pickText(language, "用户需准备", "利用者の準備", "User preparation")
        case "含酒店接送": pickText(language, "含酒店接送", "ホテル送迎", "Hotel pickup")
        case "机场/路线": pickText(language, "机场/路线", "空港・ルート", "Airport/route")
        case "车型": pickText(language, "车型", "車種", "Vehicle")
        case "人数": pickText(language, "人数", "人数", "Passengers")
        case "行李数": pickText(language, "行李数", "荷物数", "Luggage")
        case "航班号说明": pickText(language, "航班号说明", "便名メモ", "Flight notes")
        case "等待规则": pickText(language, "等待规则", "待機ルール", "Waiting rules")
        case "夜间/追加费用": pickText(language, "夜间/追加费用", "夜間・追加料金", "Surcharges")
        case "文件/手续类型": pickText(language, "文件/手续类型", "書類・手続き種別", "Document type")
        case "所需材料": pickText(language, "所需材料", "必要書類", "Required materials")
        case "交付时间": pickText(language, "交付时间", "納期", "Delivery time")
        case "结果说明": pickText(language, "结果说明", "結果の説明", "Result notes")
        case "房型/面积": pickText(language, "房型/面积", "部屋・面積", "Property size")
        case "物品量": pickText(language, "物品量", "荷物量", "Item volume")
        case "车辆/人员": pickText(language, "车辆/人员", "車両・人員", "Vehicle/staff")
        case "办理类型": pickText(language, "办理类型", "手続き種別", "Setup type")
        case "服务项目": pickText(language, "服务项目", "サービス項目", "Service items")
        case "服务时长": pickText(language, "服务时长", "施術時間", "Service duration")
        case "安全说明": pickText(language, "安全说明", "安全説明", "Safety notes")
        case "服务对象": pickText(language, "服务对象", "対象", "Service target")
        case "优惠": pickText(language, "优惠", "特典", "Deal")
        case "商家": pickText(language, "商家", "店舗", "Merchant")
        case "优惠内容": pickText(language, "优惠内容", "特典内容", "Deal details")
        case "有效期": pickText(language, "有效期", "有効期限", "Valid until")
        case "使用规则": pickText(language, "使用规则", "利用条件", "Usage rules")
        case "商家认证": pickText(language, "商家认证", "店舗認証", "Merchant verification")
        case "价格": pickText(language, "价格", "価格", "Price")
        case "分类": pickText(language, "分类", "カテゴリ", "Category")
        case "发布类型": pickText(language, "发布类型", "投稿種別", "Listing mode")
        case "品牌": pickText(language, "品牌", "ブランド", "Brand")
        case "新旧程度": pickText(language, "新旧程度", "状態", "Condition")
        case "原价/参考价": pickText(language, "原价/参考价", "元値・参考価格", "Original/reference")
        case "价格可议": pickText(language, "价格可议", "価格相談", "Negotiable")
        case "购买时间": pickText(language, "购买时间", "購入時期", "Purchase time")
        case "配件/包装": pickText(language, "配件/包装", "付属品・箱", "Accessories/box")
        case "瑕疵说明": pickText(language, "瑕疵说明", "傷・不具合", "Defects")
        case "可交易时间": pickText(language, "可交易时间", "取引可能時間", "Available time")
        case "交易方式": pickText(language, "交易方式", "取引方法", "Handoff")
        case "取货说明": pickText(language, "取货说明", "受け渡しメモ", "Pickup notes")
        case "状态": pickText(language, "状态", "状態", "Status")
        default: key
        }
    }

    private static func localizedAttributeValue(_ value: String, _ language: AppLanguage) -> String {
        switch value {
        case "可": pickText(language, "可", "可", "Yes")
        case "有": pickText(language, "有", "あり", "Yes")
        case "无": pickText(language, "无", "なし", "No")
        case "未注明": pickText(language, "未注明", "未記入", "Not specified")
        case "支持": pickText(language, "支持", "対応", "Supported")
        case "可咨询": pickText(language, "可咨询", "相談可", "Consultable")
        case "需要预约": pickText(language, "需要预约", "予約が必要", "Reservation required")
        case "已认证": pickText(language, "已认证", "認証済み", "Verified")
        case "待核验": pickText(language, "待核验", "確認待ち", "Pending verification")
        case "包含": pickText(language, "包含", "含む", "Included")
        case "不保证结果": pickText(language, "不保证结果", "結果保証なし", "No result guarantee")
        case "可商量": pickText(language, "可商量", "相談可", "Negotiable")
        default: value
        }
    }

    static func safetyTips(for type: String, _ language: AppLanguage = .zh) -> [String] {
        if type == "rental" {
            return [
                pickText(language, "Machi 不代收押金、订金或房租", "Machi は敷金・申込金・家賃を預かりません", "Machi does not hold deposits, reservation fees, or rent"),
                pickText(language, "不要提前转账，先核实房源和发布者身份", "事前送金は避け、物件と投稿者の本人確認をしてください", "Do not transfer money upfront; verify the listing and poster first"),
                pickText(language, "避免暴露完整住址，线下看房注意安全", "詳細住所の公開は避け、内見時は安全に注意してください", "Avoid exposing the full address and stay safe during viewings"),
                pickText(language, "遇到虚假地址、假照片或可疑收费立即举报", "偽住所、偽写真、不審な請求はすぐ通報してください", "Report fake addresses, fake photos, or suspicious fees immediately")
            ]
        }
        if type == "work" || type == "job" || type == "hiring" {
            return [
                pickText(language, "招聘不允许押金、保证金或培训费骗局", "求人で敷金・保証金・研修費を請求する詐欺は禁止です", "Jobs must not require deposits, guarantees, or training-fee scams"),
                pickText(language, "核实招聘方身份、工作地点和签证支持说明", "採用側の身元、勤務地、ビザサポート条件を確認してください", "Verify the employer, work location, and visa-support details"),
                pickText(language, "警惕虚假高薪、违法兼职和灰产招聘", "不自然な高収入、違法バイト、グレーな求人に注意してください", "Watch for fake high pay, illegal gigs, or gray-market jobs"),
                pickText(language, "遇到可疑内容立即举报", "不審な内容はすぐ通報してください", "Report suspicious content immediately")
            ]
        }
        if type == "local_service" {
            return [
                pickText(language, "商家与服务默认进入审核，服务方认证状态会展示", "店舗・サービスは原則審査され、提供者の認証状態が表示されます", "Business and service posts are reviewed, and provider verification is shown"),
                pickText(language, "餐饮、住宿、票务、旅行、接送交通和手续协助需写清资质、包含/不包含内容和取消规则", "飲食、宿泊、チケット、旅行、送迎、手続き支援は資格、含まれる/含まれない内容、取消規定を明記してください", "Dining, stays, tickets, travel, transfers, and paperwork help must state credentials, inclusions/exclusions, and cancellation rules"),
                pickText(language, "暂不开放外卖配送、维修安装、学习咨询；禁止成人服务、高风险线下服务和违法服务", "デリバリー、修理設置、学習相談は現在対象外です。成人向け、高リスク対面、違法サービスは禁止です", "Delivery, repair/installation, and study consulting are not supported yet. Adult, high-risk offline, and illegal services are prohibited"),
                pickText(language, "不要提前转账给未核验服务方，预约前确认服务范围、取消规则和所需材料", "未確認の提供者へ事前送金せず、予約前に範囲、取消規定、必要書類を確認してください", "Do not prepay unverified providers; confirm scope, cancellation rules, and required materials before booking")
            ]
        }
        if type == "discount" {
            return [
                pickText(language, "确认优惠有效期、适用门店和使用规则", "特典の有効期限、対象店舗、利用条件を確認してください", "Confirm the deal validity, eligible stores, and usage rules"),
                pickText(language, "不要把个人敏感信息发给未核验商家", "未確認の店舗へ個人情報を送らないでください", "Do not send sensitive personal information to unverified merchants"),
                pickText(language, "遇到虚假折扣、诱导转账或强制消费立即举报", "虚偽割引、送金誘導、強制消費はすぐ通報してください", "Report fake discounts, payment pressure, or forced purchases immediately")
            ]
        }
        return [
            pickText(language, "Machi 不代收二手交易款", "Machi はフリマ代金を預かりません", "Machi does not hold marketplace payments"),
            pickText(language, "不要提前转账，交易建议选择公共场所", "事前送金は避け、受け渡しは公共の場所がおすすめです", "Avoid paying upfront; meet in a public place"),
            pickText(language, "核实对方身份，谨慎提供个人信息", "相手を確認し、個人情報の共有は慎重にしてください", "Verify the other person and be careful with personal information"),
            pickText(language, "遇到可疑内容立即举报", "不審な内容はすぐ通報してください", "Report suspicious content immediately")
        ]
    }

    static func sortForDisplay(_ lhs: KaiXCityListingDTO, _ rhs: KaiXCityListingDTO) -> Bool {
        let left = lhs.published_at ?? lhs.updated_at ?? lhs.created_at ?? ""
        let right = rhs.published_at ?? rhs.updated_at ?? rhs.created_at ?? ""
        return left > right
    }

    static func statusLabel(_ status: String, type: String? = nil, _ language: AppLanguage = .zh) -> String {
        formatListingStatus(status, type: type, language)
    }

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "published": KXColor.accent
        case "pending_review": KXColor.heat
        default: .secondary
        }
    }

    static func verificationLabel(_ status: String, _ language: AppLanguage = .zh) -> String {
        formatVerificationStatus(status, language)
    }

    static func attr(_ listing: KaiXCityListingDTO, _ key: String) -> String? {
        guard let raw = listing.attributes?[key]?.listingDisplayValue else { return nil }
        return formatAttribute(key: key, value: raw)
    }

    static func boolAttr(_ listing: KaiXCityListingDTO, _ key: String) -> Bool {
        listing.attributes?[key]?.boolValue ?? false
    }

    static func rawAttribute(_ listing: KaiXCityListingDTO, _ key: String) -> String {
        listing.attributes?[key]?.listingDisplayValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func fallbackPriceLabel(for type: String, _ language: AppLanguage = .zh) -> String {
        switch type {
        case "rental": pickText(language, "租金咨询", "家賃相談", "Rent on request")
        case "job", "hiring": pickText(language, "薪资面议", "給与応相談", "Pay negotiable")
        case "local_service": pickText(language, "预约咨询", "予約相談", "Booking inquiry")
        case "discount": pickText(language, "查看优惠", "特典を見る", "View deal")
        default: pickText(language, "价格咨询", "価格相談", "Price on request")
        }
    }

    private static func formatAttribute(key: String, value: String) -> String? {
        guard let value = cleanText(value) else { return nil }
        switch normalized(key) {
        case "employment_type", "job_type":
            return cleanText(formatEmploymentType(value))
        case "salary_type", "price_unit":
            return cleanText(formatSalaryType(value))
        case "japanese_level", "required_japanese_level":
            return cleanText(formatJapaneseLevel(value))
        case "area_sqm", "area", "size_sqm":
            return cleanText(formatArea(value))
        case "station_distance", "station_distance_minutes":
            return cleanText(formatStationDistance(value))
        case "move_in_date", "valid_until", "expires_at":
            return cleanText(formatDate(value))
        case "condition":
            switch normalized(value) {
            case "brand_new", "new": return "全新"
            case "like_new": return "几乎全新"
            case "good": return "良好"
            case "used": return "有使用痕迹"
            case "fair": return "可用"
            default: return value
            }
        case "listing_mode":
            switch normalized(value) {
            case "sale", "sell": return "出售"
            case "free", "giveaway": return "免费送"
            case "wanted", "buy": return "求购"
            default: return value
            }
        case "delivery_method":
            switch normalized(value) {
            case "pickup": return "自取"
            case "meetup": return "面交"
            case "shipping": return "邮寄"
            case "pickup_or_shipping": return "自取或邮寄"
            case "negotiable": return "可商量"
            default: return value
            }
        case "visa_support":
            if isPositive(value) { return "支持" }
            if isNegative(value) { return "不支持" }
            return value
        default:
            return value
        }
    }

    private static func cleanText(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let bad = ["unknown", "undefined", "null", "nan", "n/a", "na", "none", "tbd", "未知", "不明"]
        return bad.contains(text.lowercased()) ? nil : text
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_")
    }

    private static func isPositive(_ value: String) -> Bool {
        ["true", "1", "yes", "是", "可", "有", "支持", "available", "allowed"].contains(normalized(value))
    }

    private static func isNegative(_ value: String) -> Bool {
        ["false", "0", "no", "否", "不可", "无", "不支持", "none", "unavailable"].contains(normalized(value))
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

private extension KaiXAttributeValue {
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
