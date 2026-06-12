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
            return currentRegion.map { "\(KaiXRegionDirectory.localizedShortLabel($0, language: language))\(L("hot", language))" } ?? "\(L("currentRegion", language))\(L("hot", language))"
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

    /// Full catalog (primary + extended). Surfaces inside the grouped
    /// MoreChannelSheet so publishing tools do not become main channels.
    private var allCategories: [DiscoverCategory] {
        (DiscoverView.primarySpecs + DiscoverView.extendedSpecs).map { resolveCategory($0) }
    }

    private func resolveCategory(_ spec: DiscoverCategorySpec) -> DiscoverCategory {
        let count = viewModel.hotPosts.filter { post in
            post.matches(region: currentRegion) && spec.types.contains(post.contentType)
        }.count
        return DiscoverCategory(spec: spec, count: count)
    }

    private static let primarySpecs: [DiscoverCategorySpec] = [
        .init(id: "secondhand", title: "二手市场", subtitle: "闲鱼 / Mercari 式闲置交易", icon: "bag", types: [.secondhand], channel: .secondhand, tint: Color.green),
        .init(id: "housing", title: "租房 · 住宿", subtitle: "爱彼迎式长租与民宿短住", icon: "house", types: [.housing, .roommate], channel: .housing, tint: Color.blue),
        .init(id: "work", title: "工作", subtitle: "BOSS / Indeed 式机会", icon: "briefcase", types: [.job_seek, .job_post, .referral], channel: .jobPost, tint: KXColor.rankViolet),
        .init(id: "service", title: "商家与本地服务", subtitle: "餐厅美食、订座点评、景点玩乐", icon: "storefront", types: [.service, .merchant], channel: .service, tint: Color.brown),
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
            return region.map { KaiXRegionDirectory.localizedShortLabel($0, language: language) } ?? L("hotScopeCity", language)
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
                    Text(region.map { "正在浏览\($0.cityName)的本地动态和生活信息" } ?? "选择城市后，首页、发现和热榜会围绕本地内容展开")
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
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        let core = Array(primaryCategories.prefix(4))
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        DiscoverSectionTitle(title: "城市功能入口", trailing: nil)
                        Text("二手、租房、工作、商家与本地服务各自独立：交易、看房、求职、预约点评都按真实场景展开。")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                    }
                    Spacer(minLength: 10)
                    Button(action: onMore) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("更多频道")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .kxGlassCapsule(isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(core) { category in
                        Button {
                            onOpen(category)
                        } label: {
                            DiscoverCategoryCell(category: category, prominence: .high)
                        }
                        .buttonStyle(.plain)
                    }
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
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: category.icon)
                .font(.system(size: prominence == .high ? 20 : 18, weight: .bold))
                .foregroundStyle(category.tint.opacity(0.9))
                .frame(width: prominence == .high ? 42 : 36, height: prominence == .high ? 42 : 36)
                .background(category.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: prominence == .high ? 14 : 11, style: .continuous))

            VStack(alignment: .leading, spacing: prominence == .high ? 7 : 3) {
                Text(category.title)
                    .font((prominence == .high ? Font.headline : Font.subheadline).weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(category.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if prominence == .high, !category.heroTags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(category.heroTags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.black))
                                .foregroundStyle(category.tint)
                                .padding(.horizontal, 6)
                                .frame(height: 20)
                                .background(category.tint.opacity(0.10), in: Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if prominence == .high {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, KXSpacing.md)
        .frame(maxWidth: .infinity, minHeight: prominence == .high ? 122 : 78, alignment: .leading)
        .background {
            if prominence == .high {
                RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [category.tint.opacity(0.12), Color(.systemBackground).opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .kxGlassSurface(radius: KXRadius.lg, elevated: prominence == .high)
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
                title: region.map { "\($0.cityName)热榜" } ?? "当前城市热榜",
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
            return region.map { "\($0.cityName)正在发生" } ?? "正在发生"
        case .ranking:
            return rankingTitle
        case .topics:
            return "热门话题"
        case .users:
            return "推荐用户"
        }
    }

    private func postList(_ items: [PostEntity]) -> some View {
        // Same PostCardView as the home feed — Discover must not grow its own
        // card spec (media rules, action bar, fonts all stay identical).
        VStack(spacing: 10) {
            if items.isEmpty {
                DiscoverSoftEmptyRow(text: "这里还在等待新的本地内容")
            } else {
                ForEach(items.prefix(12)) { post in
                    let displayedPost = postStore.post(id: post.id) ?? post
                    let originalPost = displayedPost.repostOfPostId.flatMap { postStore.post(id: $0) }
                    let isQuoteRepost = originalPost != nil && !displayedPost.previewText.isEmpty
                    let targetPost = isQuoteRepost ? displayedPost : (originalPost ?? displayedPost)
                    PostCardView(
                        post: displayedPost,
                        author: authors[displayedPost.authorId],
                        mediaItems: mediaByPostId[displayedPost.id] ?? [],
                        currentUser: currentUser,
                        originalPost: originalPost,
                        originalAuthor: originalPost.flatMap { authors[$0.authorId] },
                        originalMediaItems: originalPost == nil ? [] : (mediaByPostId[originalPost?.id ?? ""] ?? []),
                        onOpen: { onOpenPost(targetPost) },
                        onOpenOriginal: { if let originalPost { onOpenPost(originalPost) } },
                        onAuthor: {
                            if let author = authors[targetPost.authorId] {
                                onOpenUser(author)
                            }
                        },
                        onTag: onOpenTopic,
                        onComment: { onOpenPost(targetPost) },
                        onLike: { onLike(targetPost) },
                        onBookmark: { onBookmark(targetPost) },
                        onRepost: { onRepost(targetPost) },
                        onQuoteRepost: { onQuoteRepost(targetPost, $0) }
                    )
                    .equatable()
                }
            }
        }
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
        return regionCode == region.regionCode || (country == region.countryCode && city == region.cityCode)
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
            Text(region.map { "\($0.cityName)正在发生" } ?? L("happeningNow", language))
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "最新"
        case .priceLow: "价格低"
        case .priceHigh: "价格高"
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

    private var region: KaiXRegionDirectory.Region? {
        KaiXRegionDirectory.resolve(regionCode: regionCode)
    }

    /// 服务频道分区（大众点评/美团式信息架构）：餐厅美食 / 景点玩乐 / 生活服务。
    /// 住宿类目已整体搬去租房页「民宿·短住」，这里不再展示。
    static let serviceSections: [(key: String, title: String, categories: [String])] = [
        ("all", "全部", []),
        ("food", "餐厅美食", KXListingCopy.foodSectionCategories),
        ("fun", "景点玩乐", ["景点门票", "一日游", "接送机"]),
        ("life", "生活服务", ["翻译手续", "搬家清洁", "维修安装", "认证服务"]),
    ]

    /// 「stays」是租房频道里的民宿短住伪类型：列表数据其实是住宿类 local_service。
    private var baseType: String { listingType == "stays" ? "rental" : listingType }

    private var staysActive: Bool { baseType == "rental" && activeRentalTab == .stays }

    /// 真正发给 API 的 listing type。
    private var queryType: String { staysActive ? "local_service" : baseType }

    enum RentalTab: String { case homes, stays }
    @State private var rentalTab: RentalTab?

    private var activeRentalTab: RentalTab {
        rentalTab ?? (listingType == "stays" ? .stays : .homes)
    }

    private var visibleItems: [KaiXCityListingDTO] {
        let sectionCategories = Self.serviceSections.first { $0.key == serviceSection }?.categories ?? []
        let filtered = items.filter { item in
            // 民宿短住：只看住宿类目；服务频道：住宿类目已搬走，不再展示。
            if staysActive {
                guard KXListingCopy.isStayCategory(item.category) else { return false }
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
            return categoryOK && sectionOK && queryOK
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
        return count
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
                router.open(.createCityListing(type: KXListingCopy.createType(for: staysActive ? "local_service" : baseType), citySlug: regionCode))
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(KXColor.accent, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    /// 爱彼迎式双标签：长租房源 / 民宿·短住。
    private var rentalTabSwitcher: some View {
        HStack(spacing: 4) {
            rentalTabButton(.homes, title: "长租房源", icon: "house")
            rentalTabButton(.stays, title: "民宿·短住", icon: "bed.double")
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
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.black))
                .foregroundStyle(activeRentalTab == tab ? Color.white : .primary)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .frame(maxWidth: .infinity)
                .background(activeRentalTab == tab ? KXColor.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var listingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if baseType == "rental" {
                rentalTabSwitcher
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(activeScopeLabel)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    Text("\(visibleItems.count) 条结果 · \(selectedCategory)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if activeFilterCount > 0 {
                    Button("清空") {
                        query = ""
                        selectedCategory = "全部"
                        scopeMode = .city
                        selectedScopeArea = ""
                        selectedScopeRegionCode = ""
                        Task { await load() }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    scopeButton(title: region?.cityName ?? "城市", mode: .city)
                    scopeButton(title: region?.countryName ?? "国家", mode: .country)
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            filtersOpen.toggle()
                        }
                    } label: {
                        Label(activeFilterCount > 0 ? "筛选 \(activeFilterCount)" : "筛选", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(filtersOpen ? KXColor.accent : .primary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(filtersOpen ? KXColor.accent.opacity(0.10) : KXColor.softBackground.opacity(0.88), in: Capsule())
                            .overlay(Capsule().stroke(filtersOpen ? KXColor.accent.opacity(0.35) : KXColor.separator.opacity(0.65), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                    Menu {
                        ForEach(ListingSortMode.allCases) { mode in
                            Button {
                                sortMode = mode
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
            }
            searchBar
            // 大众点评/美团式分区：餐厅美食 / 景点玩乐 / 生活服务。
            if baseType == "local_service" {
                serviceSectionChips
            }
            // Persistent category rail — marketplace muscle memory
            // (Mercari/闲鱼): one tap from anywhere, never buried in a
            // collapsed filter panel.
            categoryChips
            if filtersOpen {
                scopeFilterPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg, elevated: true)
    }

    private var serviceSectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.serviceSections, id: \.key) { section in
                    Button {
                        serviceSection = section.key
                        selectedCategory = "全部"
                    } label: {
                        Text(section.title)
                            .font(.caption.weight(.black))
                            .foregroundStyle(serviceSection == section.key && selectedCategory == "全部" ? Color.white : .primary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                serviceSection == section.key && selectedCategory == "全部" ? Color.orange : KXColor.softBackground.opacity(0.88),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(serviceSection == section.key && selectedCategory == "全部" ? Color.clear : KXColor.separator.opacity(0.7), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
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
                .background(scopeMode == mode ? KXColor.accent : KXColor.softBackground.opacity(0.88), in: Capsule())
                .overlay(Capsule().stroke(scopeMode == mode ? Color.clear : KXColor.separator.opacity(0.65), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.headline.weight(.semibold))
                .foregroundStyle(KXColor.accent)
            TextField(KXListingCopy.searchPlaceholder(for: staysActive ? "stays" : baseType, language), text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .font(.subheadline.weight(.semibold))
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, KXSpacing.lg)
        .frame(height: 46)
        .background(KXColor.softBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KXColor.glassStroke.opacity(0.7), lineWidth: 0.8)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(KXListingCopy.categories(for: staysActive ? "stays" : baseType), id: \.self) { category in
                    Button { selectedCategory = category } label: {
                        Text(KXListingCopy.categoryLabel(category, language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selectedCategory == category ? Color.white : .primary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(selectedCategory == category ? KXColor.accent : KXColor.softBackground.opacity(0.88), in: Capsule())
                            .overlay(Capsule().stroke(selectedCategory == category ? Color.clear : KXColor.separator.opacity(0.7), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scopeFilterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                title: KXListingCopy.emptyTitle(for: staysActive ? "stays" : baseType, language),
                subtitle: KXListingCopy.emptySubtitle(for: staysActive ? "stays" : baseType, language),
                systemImage: KXListingCopy.icon(for: baseType)
            )
            .frame(maxWidth: .infinity, minHeight: 260)
        } else if baseType == "secondhand" {
            // Two-column photo grid — the marketplace layout people already
            // know from Mercari/闲鱼. Square covers, price first.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(visibleItems) { item in
                    KXSecondhandListingCard(listing: item) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        } else if baseType == "rental" {
            // 爱彼迎式照片主导卡：长租与民宿短住共用同一套视觉语言。
            LazyVStack(spacing: 18) {
                ForEach(visibleItems) { item in
                    KXAirbnbListingCard(listing: item, variant: staysActive ? .stay : .home) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                }
            }
        } else if baseType == "local_service" {
            // 大众点评/美团式卡片：评分、类目、价位、预约 CTA。
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

    private func load() async {
        guard let region else {
            errorMessage = "城市无法识别，请重新选择城市。"
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let scope = listingScopeQuery(for: region)
            if baseType == "work" {
                async let jobs = KaiXAPIClient.shared.listingsPage(type: "job", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, countryCode: scope.countryCode, query: query)
                async let hiring = KaiXAPIClient.shared.listingsPage(type: "hiring", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, countryCode: scope.countryCode, query: query)
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
                    query: query
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
            if baseType == "work" {
                if let cursor = nextCursor {
                    let page = try await KaiXAPIClient.shared.listingsPage(type: "job", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, countryCode: scope.countryCode, query: query, cursor: cursor)
                    fetched += page.items
                    nextCursor = page.nextCursor
                }
                if let cursor = nextHiringCursor {
                    let page = try await KaiXAPIClient.shared.listingsPage(type: "hiring", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, countryCode: scope.countryCode, query: query, cursor: cursor)
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
        .kxPageBackground()
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
                Text(KXListingCopy.pickText(language, "详情与联系", "詳細・連絡", "Details & contact"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    private func detailContent(_ listing: KaiXCityListingDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageStrip(listing)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(KXListingCopy.priceLabel(listing))
                                .font(.title2.weight(.black))
                                .foregroundStyle(KXColor.heat)
                            Text(KXListingCopy.displayTitle(listing))
                                .font(.title3.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        KXListingBadge(title: KXListingCopy.statusLabel(listing.status, type: listing.type), tint: KXListingCopy.statusColor(listing.status))
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(KXListingCopy.badges(for: listing), id: \.self) { badge in
                            KXListingBadge(title: badge, tint: KXColor.accent)
                        }
                    }
                }
                .padding(KXSpacing.lg)
                .kxGlassSurface(radius: KXRadius.lg)

                KXListingAttributeSection(listing: listing)

                if let description = listing.description, !description.isEmpty {
                    KXListingSection(title: "描述", icon: "text.alignleft") {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                KXListingSection(title: "发布者", icon: "person.crop.circle") {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(KXColor.accent.opacity(0.14))
                            .frame(width: 44, height: 44)
                            .overlay(Text((listing.seller?.display_name ?? "M").prefix(1)).font(.headline.weight(.bold)).foregroundStyle(KXColor.accent))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(listing.seller?.display_name ?? "Machi 用户")
                                .font(.subheadline.weight(.bold))
                            Text(KXListingCopy.verificationLabel(listing.verification_status))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                ListingReviewsSectionView(listing: listing, currentUser: currentUser)

                KXListingSection(title: "安全提醒", icon: "shield.checkered") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(KXListingCopy.safetyTips(for: listing.type), id: \.self) { tip in
                            Label(tip, systemImage: "checkmark.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let actionMessage {
                    Text(actionMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KXColor.accent)
                        .padding(.horizontal, 2)
                }

                contactPanel(listing)
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, chrome.bottomContentPadding + 28)
        }
    }

    private func imageStrip(_ listing: KaiXCityListingDTO) -> some View {
        let mediaItems: [KaiXListingMediaDTO]
        if let media = listing.media, !media.isEmpty {
            mediaItems = media
        } else if let cover = listing.primaryCoverMedia {
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
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func contactPanel(_ listing: KaiXCityListingDTO) -> some View {
        let spec = ListingIntakeSpec.forType(listing.type, category: listing.category)
        let ownListing = isOwnListing(listing)
        return KXListingSection(title: "联系与交易", icon: "message.badge") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: ownListing ? "person.crop.circle.badge.checkmark" : "bubble.left.and.bubble.right.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ownListing ? .secondary : KXColor.accent)
                        .frame(width: 38, height: 38)
                        .background((ownListing ? Color.secondary : KXColor.accent).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ownListing ? "这是你的发布" : "通过 Machi 私信联系发布者")
                            .font(.subheadline.weight(.bold))
                        Text(ownListing ? "自己的发布不能发起咨询，可以在我的发布中管理状态。" : "提交后会开启真实对话，发布者会收到商品和表单信息。")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Button { intakeOpen = true } label: {
                    Label(isBusy ? "处理中" : spec.title, systemImage: "message.fill")
                        .font(.subheadline.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(ownListing ? Color.secondary.opacity(0.16) : KXColor.accent, in: Capsule())
                        .foregroundStyle(ownListing ? Color.secondary : Color.white)
                }
                .buttonStyle(.plain)
                .disabled(isBusy || ownListing)

                if listing.type == "secondhand", !ownListing {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(quickInquiries(for: listing)) { item in
                            Button {
                                Task { await submitInquiry(message: item.message, details: item.details) }
                            } label: {
                                Text(item.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(KXColor.accent)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(KXColor.accent.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button { Task { await report() } } label: {
                        Label("举报异常", systemImage: "flag")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                    Text("不要提前转账，建议公共场所交易。")
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
                title: "还在吗？",
                message: "你好，我想确认「\(title)」还可以交易吗？",
                details: [["label": "咨询内容", "value": "确认是否仍可交易"]]
            ),
            ListingQuickInquiry(
                id: "meetup",
                title: "约自取",
                message: "你好，我想预约自取「\(title)」，方便的话请告诉我可交易时间。",
                details: [["label": "希望交易方式", "value": "自取 / 面交"], ["label": "希望地点", "value": location]]
            ),
            ListingQuickInquiry(
                id: "condition",
                title: "问瑕疵",
                message: "你好，我想了解「\(title)」的使用痕迹、配件和是否有瑕疵。",
                details: [["label": "咨询内容", "value": "确认状态、配件和瑕疵"]]
            ),
            ListingQuickInquiry(
                id: "price",
                title: "可议价吗？",
                message: "你好，我对「\(title)」感兴趣，想问一下价格是否可以商量。",
                details: [["label": "咨询内容", "value": "价格是否可商量"]]
            ),
        ]
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            listing = try await KaiXAPIClient.shared.cityListing(listingId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
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
            actionMessage = "不能咨询自己发布的信息。"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let fallback = "我想\(ListingIntakeSpec.forType(listing.type, category: listing.category).actionWord)：\(KXListingCopy.displayTitle(listing))"
            let conversationId = try await KaiXAPIClient.shared.contactListing(
                listing.id,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : message,
                details: details
            )
            intakeOpen = false
            if conversationId.isEmpty {
                actionMessage = "已发送联系请求。请继续在私信或平台通知中沟通，避免提前转账。"
            } else {
                actionMessage = "已为你和发布者开启对话。"
                router.open(.conversation(conversationId: conversationId))
            }
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
            actionMessage = "举报已提交，Machi 会进行审核。"
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
        // 携程 / 美团式结构化预订：服务类目给出真正可用的字段。
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
                // 大众点评式在线订座
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
            case "景点门票", "一日游":
                return ListingIntakeSpec(
                    title: category == "一日游" ? "预订行程" : "预订门票",
                    actionWord: "预订",
                    noteLabel: "补充说明",
                    fields: [
                        ListingIntakeField("date", label: "出行日期", placeholder: "例如 7 月 1 日", required: true),
                        ListingIntakeField("tickets", label: "人数 / 票数", options: ["1", "2", "3", "4", "5 及以上"], required: true),
                        ListingIntakeField("language", label: "希望语言", options: ["中文", "日本語", "English", "无要求"]),
                        ListingIntakeField("contact", label: "联系方式", placeholder: "微信 / LINE / 电话", required: true),
                    ]
                )
            case "接送机":
                return ListingIntakeSpec(
                    title: "预约接送机",
                    actionWord: "预约接送机",
                    noteLabel: "补充说明",
                    fields: [
                        ListingIntakeField("date", label: "用车日期", placeholder: "例如 7 月 1 日", required: true),
                        ListingIntakeField("flight", label: "航班号", placeholder: "例如 NH878 / CA181"),
                        ListingIntakeField("passengers", label: "人数", options: ["1", "2", "3", "4", "5 及以上"], required: true),
                        ListingIntakeField("luggage", label: "行李数", options: ["1-2 件", "3-4 件", "5 件及以上"]),
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
                ]
            )
        case "local_service":
            return ListingIntakeSpec(
                title: "预约服务",
                actionWord: "预约服务",
                noteLabel: "具体需求",
                fields: [
                    ListingIntakeField("city", label: "服务城市", required: true),
                    ListingIntakeField("service_scene", label: "服务场景", options: ["到店预约", "景点门票", "一日游", "接送机", "翻译手续", "维修安装"]),
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
                        Text(spec.title)
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
                        Text(spec.noteLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField("补充说明（选填）", text: $note, axis: .vertical)
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

                    Text("提交后会与发布者开启对话。Machi 不代收交易款、押金、保证金或第三方服务款，请勿提前转账。")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KXColor.heat)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(KXColor.heat.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button(action: submit) {
                        HStack {
                            if submitting { ProgressView().tint(.white) }
                            Text(submitting ? "提交中" : spec.title)
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
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func intakeField(_ field: ListingIntakeField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.required ? "\(field.label) *" : field.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if field.options.isEmpty {
                TextField(field.placeholder.isEmpty ? field.label : field.placeholder, text: binding(for: field))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Picker(field.label, selection: binding(for: field)) {
                    Text("请选择").tag("")
                    ForEach(field.options, id: \.self) { option in
                        Text(option).tag(option)
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
                errorMessage = "请填写「\(field.label)」"
                return
            }
        }
        errorMessage = nil
        let details = spec.fields.compactMap { field -> [String: String]? in
            let value = values[field.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return ["label": field.label, "value": value]
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

struct CreateCityListingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState
    let listingType: String
    let citySlug: String?
    let currentUser: UserEntity

    @State private var title = ""
    @State private var category = ""
    @State private var price = ""
    @State private var location = ""
    @State private var description = ""
    @State private var condition = "良好"
    @State private var brandModel = ""
    @State private var secondhandAvailableTime = ""
    @State private var secondhandPickupNotes = ""
    @State private var pickupAvailable = true
    @State private var secondhandShippingAvailable = false
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
    @State private var serviceBusinessName = ""
    @State private var serviceType = "翻译手续"
    @State private var serviceArea = ""
    @State private var priceUnit = "预约咨询"
    @State private var availability = ""
    @State private var certifiedProvider = false
    @State private var serviceProcess = ""
    @State private var cancellationRule = ""
    @State private var merchantName = ""
    @State private var discountInfo = ""
    @State private var validUntil = ""
    @State private var usageRules = ""
    @State private var merchantVerified = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var mediaDrafts: [MediaDraft] = []
    @State private var mediaUploadPhases: [String: ListingMediaUploadPhase] = [:]
    @State private var uploadedMedia: [String: KaiXMediaDTO] = [:]
    @State private var isSubmitting = false
    @State private var message: String?

    private var region: KaiXRegionDirectory.Region? {
        if let citySlug,
           let region = KaiXRegionDirectory.resolve(regionCode: citySlug) {
            return region
        }
        return RegionStore.shared.current ?? KaiXRegionDirectory.resolve(regionCode: "jp.tokyo.tokyo")
    }

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
            return filled(serviceBusinessName) && filled(serviceArea) && filled(availability)
        }
        if listingType == "discount" {
            return filled(merchantName) && filled(discountInfo) && filled(validUntil)
        }
        return true
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

    private var requiredProgress: (done: Int, total: Int) {
        let filled: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var values = [filled(title), filled(location)]
        if listingType == "rental" {
            values += [filled(layout), filled(area), filled(station), filled(moveIn)]
        } else if listingType == "work" || listingType == "job" || listingType == "hiring" {
            values += [filled(companyName), filled(workingHours)]
        } else if listingType == "local_service" {
            values += [filled(serviceBusinessName), filled(serviceArea), filled(availability)]
        } else if listingType == "discount" {
            values += [filled(merchantName), filled(discountInfo), filled(validUntil)]
        }
        return (values.filter { $0 }.count, values.count)
    }

    private var missingRequiredCopy: String {
        let filled: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !filled(title) { return "请先补充标题" }
        if !filled(location) { return "请补充地区、车站或交易地点" }
        if region == nil { return "请先选择可发布的城市" }
        if listingType == "rental" && !typeRequiredFieldsReady { return "请补充户型、面积、最近车站和入住时间" }
        if (listingType == "work" || listingType == "job" || listingType == "hiring") && !typeRequiredFieldsReady { return "请补充公司/店铺名和工作时间" }
        if listingType == "local_service" && !typeRequiredFieldsReady { return "请补充服务方、服务范围和可预约时间" }
        if listingType == "discount" && !typeRequiredFieldsReady { return "请补充商家、优惠内容和有效期" }
        return "信息完整后即可提交"
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
                    safetySection
                    if let message {
                        Text(message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(message.contains("成功") || message.contains("提交") ? KXColor.accent : KXColor.heat)
                            .padding(KXSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background((message.contains("成功") || message.contains("提交") ? KXColor.accent : KXColor.heat).opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, chrome.bottomContentPadding + 128)
            }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            submitBar
        }
        .onChange(of: pickerItems) { _, newItems in
            Task { await loadImages(newItems) }
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
                Text(KXListingCopy.createTitle(for: listingType))
                    .font(.headline.weight(.semibold))
                Text(region.map { "\($0.countryEmoji) \($0.cityName)" } ?? "选择城市后发布")
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
                    Text(KXListingCopy.createTitle(for: listingType))
                        .font(.title3.weight(.black))
                    Spacer()
                    Text("\(progress.done)/\(progress.total)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(typeAccent)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(typeAccent.opacity(0.10), in: Capsule())
                }
                Text(KXListingCopy.createGuidance(for: listingType))
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
        KXListingSection(title: "图片与视频", icon: "photo.on.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: imageLimit, matching: .any(of: [.images, .videos])) {
                    HStack(spacing: KXSpacing.md) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(typeAccent)
                            .frame(width: 42, height: 42)
                            .background(typeAccent.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mediaDrafts.isEmpty ? "添加图片或视频" : "继续添加媒体")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("最多 \(imageLimit) 个媒体，其中最多 1 个视频，第一项作为封面。避免包含身份证、护照等敏感信息。")
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

                if !mediaDrafts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
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
                                    Text(index == 0 ? "封面" : "\(index + 1)")
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
        KXListingSection(title: "基本信息", icon: "square.and.pencil") {
            VStack(spacing: 12) {
                KXListingFormField(title: "标题", placeholder: KXListingCopy.titlePlaceholder(for: listingType), icon: "text.cursor", text: $title)
                KXListingFormField(title: "分类", placeholder: KXListingCopy.categoryPlaceholder(for: listingType), icon: "square.grid.2x2", text: $category)
                // 规范类目快捷选择 —— 分区/筛选按精确类目匹配，鼓励选标准值
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(KXListingCopy.categories(for: listingType).filter { $0 != "全部" }, id: \.self) { chip in
                            Button {
                                category = chip
                            } label: {
                                Text(chip)
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
                KXListingFormField(title: listingType == "rental" ? "租金" : "价格", placeholder: KXListingCopy.pricePlaceholder(for: listingType), icon: "yensign.circle", text: $price, keyboard: .decimalPad)
                KXListingFormField(title: "地区 / 车站 / 交易地点", placeholder: "例如 新宿站附近、池袋、线上咨询", icon: "location", text: $location)
                KXListingFormField(title: "描述", placeholder: KXListingCopy.descriptionPlaceholder(for: listingType), icon: "text.alignleft", text: $description, lineLimit: 4...8)
            }
        }
    }

    private var safetySection: some View {
        KXListingSection(title: "安全确认", icon: "shield.checkered") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(KXListingCopy.safetyTips(for: listingType), id: \.self) { tip in
                    KXListingHintRow(text: tip, icon: "checkmark.circle.fill", tint: KXColor.accent)
                }
                KXListingHintRow(
                    text: "Machi 只做信息发布、联系、收藏、举报和审核，不代收交易款、押金或保证金。",
                    icon: "exclamationmark.triangle.fill",
                    tint: KXColor.heat
                )
            }
        }
    }

    private var submitBar: some View {
        VStack(spacing: 8) {
            if !canSubmit {
                Text(hasBlockingMediaUpload ? "有媒体上传失败，请删除后重新选择。" : missingRequiredCopy)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { Task { await submit() } } label: {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().tint(.white) }
                    Text(isSubmitting ? "提交中" : KXListingCopy.submitLabel(for: listingType))
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
        .background(.ultraThinMaterial)
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
                    KXListingChoiceRow(title: "雇佣形式", icon: "person.text.rectangle", options: ["兼职", "全职", "派遣", "实习"], selection: $employmentType, tint: typeAccent)
                    KXListingChoiceRow(title: "日语要求", icon: "character.bubble", options: ["不限", "N5", "N4", "N3", "N2", "N1"], selection: $japaneseLevel, tint: typeAccent)
                    KXListingToggleChip(title: "签证支持", icon: "checkmark.shield", isOn: $visaSupport, tint: typeAccent)
                }
            }
        } else if listingType == "local_service" {
            KXListingSection(title: "服务预约字段", icon: "calendar.badge.clock") {
                VStack(spacing: 12) {
                    KXListingFormField(title: "服务方名称", placeholder: "个人 / 店铺 / 公司名称", icon: "person.crop.square", text: $serviceBusinessName)
                    KXListingChoiceRow(title: "服务类型", icon: "wrench.and.screwdriver", options: ["餐厅美食", "餐饮点评", "优惠预约", "民宿", "酒店", "温泉旅馆", "公寓式酒店", "景点门票", "一日游", "接送机", "翻译手续", "搬家清洁", "维修安装", "租房申请协助", "本地向导"], selection: $serviceType, tint: typeAccent)
                    KXListingFormField(title: "服务范围", placeholder: "东京 23 区 / 成田机场 / 富士山一日游 / 线上", icon: "map", text: $serviceArea)
                    KXListingFormField(title: "价格单位", placeholder: "每小时 / 每次 / 预约咨询", icon: "yensign.circle", text: $priceUnit)
                    KXListingFormField(title: "可预约时间", placeholder: "平日晚上 / 周末 / 需提前 2 天", icon: "calendar.badge.clock", text: $availability)
                    KXListingToggleChip(title: "认证服务方", icon: "checkmark.seal", isOn: $certifiedProvider, tint: typeAccent)
                    KXListingFormField(title: "服务流程", placeholder: "写清预约、准备材料、到场、旅行/景点集合或线上服务步骤", icon: "list.bullet.clipboard", text: $serviceProcess, lineLimit: 3...6)
                    KXListingFormField(title: "取消/退款规则", placeholder: "例如 前一天可取消，票务/酒店/一日游请写清不可退规则", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)
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
                    KXListingFormField(title: "品牌 / 型号", placeholder: "例如 Apple Magic Keyboard / IKEA 桌子", icon: "tag", text: $brandModel)
                    KXListingChoiceRow(title: "新旧程度", icon: "sparkles", options: ["全新", "几乎全新", "良好", "有使用痕迹"], selection: $condition, tint: typeAccent)
                    KXListingFormField(title: "可交易时间", placeholder: "例如 平日 19:00 后 / 周末下午", icon: "calendar.badge.clock", text: $secondhandAvailableTime)
                    KXListingFormField(title: "取货 / 邮寄说明", placeholder: "例如 新宿站面交，邮寄需买家承担运费", icon: "shippingbox", text: $secondhandPickupNotes, lineLimit: 2...4)
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "自取 / 面交", icon: "person.2", isOn: $pickupAvailable, tint: typeAccent)
                        KXListingToggleChip(title: "可邮寄", icon: "shippingbox", isOn: $secondhandShippingAvailable, tint: typeAccent)
                    }
                    KXListingHintRow(text: "建议写清购买时间、瑕疵、是否含包装和交易地点，减少来回确认。", icon: "lightbulb", tint: typeAccent)
                }
            }
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
            var mediaIds: [String] = []
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
            let created = try await KaiXAPIClient.shared.createListing(
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
            let published = created.status == "published" || created.status == "active"
            message = published ? "发布成功，已同步到三端。" : "已提交审核，可在详情页查看审核状态。"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSubmitting = false
            try? await Task.sleep(for: .milliseconds(550))
            router.open(.cityListingDetail(listingId: created.id))
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
                "visa_support": .init(bool: visaSupport),
                "working_hours": .init(string: workingHours),
                "company_name": .init(string: companyName),
            ]
        }
        if listingType == "local_service" {
            return [
                "business_name": .init(string: serviceBusinessName),
                "service_type": .init(string: serviceType),
                "service_area": .init(string: serviceArea.isEmpty ? location : serviceArea),
                "price_unit": .init(string: priceUnit),
                "availability": .init(string: availability),
                "certified_provider": .init(bool: certifiedProvider),
                "service_process": .init(string: serviceProcess),
                "cancellation_rule": .init(string: cancellationRule),
            ]
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
            "brand": .init(string: brandModel),
            "condition": .init(string: KXListingCopy.conditionKey(condition)),
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
    let listing: KaiXCityListingDTO
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack(alignment: .topTrailing) {
                    if let url = listing.coverURL {
                        MediaImageView(url: url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(KXColor.softBackground)
                            .overlay {
                                Image(systemName: KXListingCopy.icon(for: listing.type))
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.secondary.opacity(0.56))
                            }
                    }
                    if listing.coverIsVideo {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.55), in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    VStack {
                        HStack {
                            KXListingBadge(title: KXListingCopy.formatListingStatus(listing.status, type: listing.type), tint: KXListingCopy.statusColor(listing.status))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                    Image(systemName: listing.favorited == true ? "heart.fill" : "heart")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(listing.favorited == true ? KXColor.heat : .primary)
                        .frame(width: 26, height: 26)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
                .frame(maxWidth: .infinity)
                // Square cover — the half-width marketplace grid standard.
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(KXListingCopy.priceLabel(listing))
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(KXColor.heat)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(KXListingCopy.displayTitle(listing))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2.weight(.bold))
                    Text(KXListingCopy.compactMeta(listing))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxGlassSurface(radius: 18)
        }
        .buttonStyle(.plain)
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
    let type: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    KXColor.accent.opacity(0.13),
                    KXColor.softBackground,
                    KXColor.rankTeal.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Image(systemName: type == "video" ? "play.rectangle.fill" : KXListingCopy.icon(for: type))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(KXColor.accent.opacity(0.72))
                Text(type == "video" ? "视频封面生成中" : "暂无图片")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct KXStructuredListingRow: View {
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
                        Text(KXListingCopy.priceLabel(listing))
                            .font(.headline.weight(.black))
                            .foregroundStyle(KXColor.heat)
                            .lineLimit(2)
                        Spacer()
                        KXListingBadge(title: KXListingCopy.statusLabel(listing.status, type: listing.type), tint: KXListingCopy.statusColor(listing.status))
                    }
                    Text(KXListingCopy.displayTitle(listing))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(KXListingCopy.structuredMeta(listing))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    FlowLayout(spacing: 6) {
                        ForEach(KXListingCopy.badges(for: listing).prefix(3), id: \.self) { badge in
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
                ForEach(KXListingCopy.attributes(for: listing), id: \.0) { item in
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
                    .background(KXColor.softBackground.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .kxGlassSurface(radius: KXRadius.lg)
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
    /// 餐厅美食：大众点评式菜系类目（与 web ListingKit FOOD_CATEGORIES 同步）。
    static let foodCategories = ["中华料理", "日本料理", "居酒屋", "烧肉火锅", "拉面", "寿司海鲜", "咖啡甜品", "西餐", "韩国料理"]
    /// 餐厅美食分区还包含两个老类目（已有数据继续生效）。
    static let foodSectionCategories = foodCategories + ["餐饮点评", "优惠预约"]
    /// 住宿（爱彼迎式）：归属租房页「民宿·短住」标签；"酒店民宿" 为老类目伞值。
    static let stayCategories = ["民宿", "酒店", "温泉旅馆", "公寓式酒店", "酒店民宿"]
    /// 租房页「民宿·短住」标签下的筛选 chips。
    static let stayChips = ["全部", "民宿", "酒店", "温泉旅馆", "公寓式酒店"]

    static func isStayCategory(_ category: String?) -> Bool {
        stayCategories.contains(category ?? "")
    }

    static func isFoodCategory(_ category: String?) -> Bool {
        foodSectionCategories.contains(category ?? "")
    }

    /// Header copy in the viewer's app language. zh remains the source of
    /// truth; ja/en mirror web ListingKit's CHANNEL_TEXT so both clients
    /// read the same.
    static func title(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental", "stays": (zh, ja, en) = ("租房 · 住宿", "賃貸・宿泊", "Homes & Stays")
        case "work":          (zh, ja, en) = ("工作", "求人", "Jobs")
        case "job":           (zh, ja, en) = ("找工作", "仕事を探す", "Find work")
        case "hiring":        (zh, ja, en) = ("招聘", "採用", "Hiring")
        case "local_service": (zh, ja, en) = ("商家与本地服务", "店舗・地域サービス", "Businesses & local services")
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
        case "rental", "stays":
            (zh, ja, en) = ("长租房源与民宿短住，像爱彼迎一样找住处", "賃貸も民泊・短期滞在もまとめて探せる", "Long-term rentals and short stays in one place")
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
        "不包含内容": ("含まれないもの", "Not included"),
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
        case "local_service": "wrench.and.screwdriver"
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
            (zh, ja, en) = ("搜索民宿、酒店、温泉旅馆、地区关键词", "民泊・ホテル・旅館・エリアを検索", "Search guesthouses, hotels, ryokan, areas")
        case "work", "job", "hiring":
            (zh, ja, en) = ("搜索职位、公司、地点、日语要求", "職種・会社・場所・日本語レベルを検索", "Search roles, companies, locations")
        case "local_service":
            (zh, ja, en) = ("搜索餐厅美食、景点门票、一日游、接送机、翻译手续", "グルメ、観光チケット、ツアー、送迎、翻訳・手続きを検索", "Search restaurants, attraction tickets, tours, transfers, paperwork")
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
        case "work", "job", "hiring": ["全部", "兼职", "全职", "时给", "月给", "N3 可", "签证支持", "无经验可"]
        case "local_service": ["全部"] + foodCategories + ["餐饮点评", "优惠预约", "民宿", "酒店", "温泉旅馆", "公寓式酒店", "酒店民宿", "景点门票", "一日游", "接送机", "翻译手续", "搬家清洁", "维修安装", "认证服务"]
        case "discount": ["全部", "餐饮", "学校", "服务", "购物", "限时"]
        default: ["全部", "家具", "家电", "电子产品", "教材", "生活用品", "搬家出清", "免费送", "求购"]
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
        "电子产品": ("電子機器", "Electronics"),
        "教材": ("教材", "Textbooks"),
        "衣物": ("衣類", "Clothing"),
        "生活用品": ("生活用品", "Daily goods"),
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
        "景点门票": ("観光チケット", "Attraction tickets"),
        "一日游": ("日帰りツアー", "Day trips"),
        "接送机": ("空港送迎", "Airport transfer"),
        "翻译手续": ("翻訳・手続き", "Translation & paperwork"),
        "搬家清洁": ("引越し・清掃", "Moving & cleaning"),
        "维修安装": ("修理・設置", "Repair & installation"),
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
        case "work", "job", "hiring": (zh, ja, en) = ("这里还没有工作信息", "まだ求人がありません", "No jobs yet")
        case "local_service":        (zh, ja, en) = ("这里还没有商家与本地服务", "まだ店舗・地域サービスがありません", "No business or local services yet")
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
            (zh, ja, en) = ("认证商家可以发布民宿、酒店、温泉旅馆，像爱彼迎一样展示给同城旅客。", "認証店舗が民泊・ホテル・旅館を掲載すると、ここに表示されます。", "Verified hosts can list guesthouses, hotels and ryokan here.")
        case "work", "job", "hiring":
            (zh, ja, en) = ("稍后查看新的同城工作机会。", "新しい求人をまた後でチェックしてください。", "Check back soon for new local jobs.")
        case "local_service":
            (zh, ja, en) = ("认证商家的餐厅美食、景点票务、一日游、接送机和生活服务审核后会展示在这里。", "認証店舗のグルメ、観光チケット、日帰りツアー、送迎、生活サポートが審査後に表示されます。", "Verified restaurants, tickets, day trips, transfers and local support appear here after review.")
        case "discount":
            (zh, ja, en) = ("商家优惠审核后会展示在这里。", "店舗特典が審査後にここに表示されます。", "Merchant deals appear here after review.")
        default:
            (zh, ja, en) = ("发布第一个闲置，让同城的人看到它。", "最初の出品をして、近くの人に届けよう。", "List the first item for your city to see.")
        }
        return pickText(language, zh, ja, en)
    }

    static func createTitle(for type: String) -> String {
        switch type {
        case "rental": "发布房源"
        case "job": "发布求职信息"
        case "work", "hiring": "发布招聘"
        case "local_service": "发布商家与本地服务"
        case "discount": "发布优惠"
        default: "发布二手"
        }
    }

    static func createGuidance(for type: String) -> String {
        switch type {
        case "rental":
            return "把租金、车站、户型、面积和入住时间写清楚，房源会更容易被认真咨询。"
        case "work", "job", "hiring":
            return "岗位、工作时间、日语要求和签证说明越清楚，越能减少无效沟通。"
        case "local_service":
            return "服务范围、预约时间、价格单位、资质许可和取消规则会影响审核与用户信任。酒店、票务、旅行与景点服务请写清包含/不包含内容。"
        case "discount":
            return "优惠内容、有效期和使用规则需要明确，避免用户到店后产生误解。"
        default:
            return "清楚的照片、价格、地点和新旧程度，会让同城交易更快也更安全。"
        }
    }

    static func createType(for type: String) -> String {
        type == "work" ? "hiring" : type
    }

    static func submitLabel(for type: String) -> String {
        type == "secondhand" ? "发布" : "提交审核"
    }

    static func categoryPlaceholder(for type: String) -> String {
        switch type {
        case "rental": "类型，例如 单人 / 合租 / 短租"
        case "work", "job", "hiring": "行业或岗位分类"
        case "local_service": "服务分类，例如 日本料理 / 民宿 / 景点门票 / 接送机"
        case "discount": "优惠分类"
        default: "分类，例如 家具 / 家电 / 教材"
        }
    }

    static func titlePlaceholder(for type: String) -> String {
        switch type {
        case "rental": "例如 池袋 1K 公寓，可预约看房"
        case "work", "job", "hiring": "例如 新宿咖啡店周末兼职"
        case "local_service": "例如 东京周末一日游 / 机场接送 / 认证翻译服务"
        case "discount": "例如 留学生套餐 9 折"
        default: "例如 Apple Magic Keyboard 日文配列"
        }
    }

    static func pricePlaceholder(for type: String) -> String {
        switch type {
        case "rental": "月租，例如 58000"
        case "work", "job", "hiring": "薪资，例如 1200"
        default: "价格，例如 8000"
        }
    }

    static func descriptionPlaceholder(for type: String) -> String {
        switch type {
        case "rental":
            return "写清房间状态、费用包含项、初期费用、可入住时间、看房方式。"
        case "work", "job", "hiring":
            return "写清工作内容、薪资、排班、试用期、交通费和需要准备的材料。"
        case "local_service":
            return "写清适合谁、服务包含/不包含什么、预约规则、旅行/景点说明、取消退款规则，以及预约前需要准备的信息。"
        case "discount":
            return "写清适用门店、适用人群、不可叠加条件和使用方式。"
        default:
            return "写清购买时间、使用情况、瑕疵、配件、交易地点和是否可议价。"
        }
    }

    static func defaultCategory(for type: String) -> String {
        switch type {
        case "rental": "房源"
        case "work", "job", "hiring": "职位"
        case "local_service": "商家与本地服务"
        case "discount": "优惠"
        default: "二手"
        }
    }

    static func formatListingType(_ type: String) -> String {
        title(for: type)
    }

    static func formatListingStatus(_ status: String, type: String? = nil) -> String {
        switch normalized(status) {
        case "draft": "草稿"
        case "pending_review": "审核中"
        case "reserved": "已预约"
        case "sold": "已售出"
        case "rented": "已租出"
        case "closed": "已关闭"
        case "expired": "已过期"
        case "rejected": "已拒绝"
        case "hidden": "已下架"
        case "published":
            switch type {
            case "rental": "可咨询"
            case "job", "hiring": "招聘中"
            case "local_service": "可预约"
            case "discount": "有效中"
            case "event": "开放报名"
            default: "出售中"
            }
        default: "待补充"
        }
    }

    static func formatVerificationStatus(_ status: String) -> String {
        switch normalized(status) {
        case "verified": "认证"
        case "pending": "待核验"
        case "needs_review": "需复核"
        case "rejected": "认证拒绝"
        case "unverified": "未认证"
        default: "未认证"
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

    static func conditionKey(_ value: String) -> String {
        switch normalized(value) {
        case "全新", "brand_new", "new": "brand_new"
        case "几乎全新", "like_new": "like_new"
        case "有使用痕迹", "used": "used"
        case "可用", "fair": "fair"
        default: "good"
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

    static func formatPrice(_ listing: KaiXCityListingDTO) -> String {
        let type = listing.type
        let priceType = normalized(listing.price_type ?? "")
        if priceType == "free" { return "免费" }
        if ["appointment_only", "quote_required", "consultation", "negotiable"].contains(priceType) {
            return fallbackPriceLabel(for: type)
        }
        guard let price = listing.price, price.isFinite, price > 0 else {
            return fallbackPriceLabel(for: type)
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
        case "monthly", "month": return "\(rendered)/月"
        case "hourly", "hour": return "\(rendered)/小时"
        case "per_night", "nightly": return "\(rendered)/晚"
        case "daily": return "\(rendered)/日"
        case "weekly": return "\(rendered)/周"
        case "yearly", "annual": return "\(rendered)/年"
        case "starting_from": return "\(rendered) 起"
        default:
            if type == "rental" { return "\(rendered)/月" }
            if type == "job" || type == "hiring" { return "\(rendered)/小时" }
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

    static func priceLabel(_ listing: KaiXCityListingDTO) -> String {
        formatPrice(listing)
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

    static func compactMeta(_ listing: KaiXCityListingDTO) -> String {
        [cleanText(listing.location_text), attr(listing, "condition"), attr(listing, "available_time"), statusLabel(listing.status, type: listing.type)]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    static func structuredMeta(_ listing: KaiXCityListingDTO) -> String {
        switch listing.type {
        case "rental":
            return [cleanText(listing.location_text), attr(listing, "nearest_station"), attr(listing, "layout"), attr(listing, "area_sqm")]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        case "job", "hiring":
            return [attr(listing, "company_name"), cleanText(listing.location_text), attr(listing, "employment_type"), "日语 \(attr(listing, "japanese_level") ?? "未注明")"]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        case "local_service":
            return [attr(listing, "service_type"), attr(listing, "service_area"), attr(listing, "price_unit"), attr(listing, "availability")]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        case "discount":
            return [attr(listing, "merchant_name"), cleanText(listing.location_text), attr(listing, "valid_until").map { "有效至 \($0)" }]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        default:
            return compactMeta(listing)
        }
    }

    static func badges(for listing: KaiXCityListingDTO) -> [String] {
        var result: [String] = []
        if listing.verification_status == "pending" { result.append(formatVerificationStatus(listing.verification_status)) }
        if listing.verification_status == "verified" { result.append(formatVerificationStatus(listing.verification_status)) }
        switch listing.type {
        case "rental":
            if boolAttr(listing, "short_term_allowed") { result.append("短租") }
            if boolAttr(listing, "share_allowed") { result.append("合租") }
            if boolAttr(listing, "furnished") { result.append("家具家电") }
        case "job", "hiring":
            if boolAttr(listing, "visa_support") { result.append("签证支持") }
            if let level = attr(listing, "japanese_level") { result.append("日语 \(level)") }
            if let employment = attr(listing, "employment_type") { result.append(employment) }
        case "local_service":
            if let service = attr(listing, "service_type") { result.append(service) }
            if boolAttr(listing, "certified_provider") || listing.verification_status == "verified" { result.append("认证服务方") }
            if let area = attr(listing, "service_area") { result.append(area) }
        case "discount":
            if let merchant = attr(listing, "merchant_name") { result.append(merchant) }
            if let validUntil = attr(listing, "valid_until") { result.append("有效至 \(validUntil)") }
            if boolAttr(listing, "merchant_verified") || listing.verification_status == "verified" { result.append("认证商家") }
        default:
            if let condition = attr(listing, "condition") { result.append(condition) }
            if boolAttr(listing, "pickup_available") { result.append("可自取") }
            if boolAttr(listing, "shipping_available") { result.append("可邮寄") }
            if let time = attr(listing, "available_time") { result.append(time) }
        }
        return result
    }

    static func attributes(for listing: KaiXCityListingDTO) -> [(String, String)] {
        let base: [(String, String?)]
        switch listing.type {
        case "rental":
            base = [
                ("月租", priceLabel(listing)),
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
            base = [
                ("薪资", priceLabel(listing)),
                ("公司/店铺", attr(listing, "company_name")),
                ("地点", cleanText(listing.location_text)),
                ("雇佣形式", attr(listing, "employment_type")),
                ("日语要求", attr(listing, "japanese_level")),
                ("签证支持", boolAttr(listing, "visa_support") ? "支持" : "未注明"),
                ("工作时间", attr(listing, "working_hours")),
                ("审核状态", verificationLabel(listing.verification_status)),
            ]
        case "local_service":
            base = [
                ("起步价格", priceLabel(listing)),
                ("服务方", attr(listing, "business_name")),
                ("服务类型", attr(listing, "service_type")),
                ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                ("价格单位", attr(listing, "price_unit")),
                ("可预约时间", attr(listing, "availability")),
                ("服务流程", attr(listing, "service_process")),
                ("取消规则", attr(listing, "cancellation_rule")),
                ("审核状态", verificationLabel(listing.verification_status)),
            ]
        case "discount":
            base = [
                ("优惠", priceLabel(listing)),
                ("商家", attr(listing, "merchant_name")),
                ("地点", cleanText(listing.location_text)),
                ("优惠内容", attr(listing, "discount_info")),
                ("有效期", attr(listing, "valid_until")),
                ("使用规则", attr(listing, "usage_rules")),
                ("商家认证", boolAttr(listing, "merchant_verified") || listing.verification_status == "verified" ? "已认证" : "待核验"),
            ]
        default:
            base = [
                ("价格", priceLabel(listing)),
                ("地点", cleanText(listing.location_text)),
                ("分类", cleanText(listing.category)),
                ("品牌", attr(listing, "brand")),
                ("新旧程度", attr(listing, "condition")),
                ("可交易时间", attr(listing, "available_time")),
                ("交易方式", attr(listing, "delivery_method")),
                ("取货说明", attr(listing, "pickup_note")),
                ("状态", statusLabel(listing.status, type: listing.type)),
            ]
        }
        return base.compactMap { key, value in
            guard let value, !value.isEmpty else { return nil }
            return (key, value)
        }
    }

    static func safetyTips(for type: String) -> [String] {
        if type == "rental" {
            return ["Machi 不代收押金、订金或房租", "不要提前转账，先核实房源和发布者身份", "避免暴露完整住址，线下看房注意安全", "遇到虚假地址、假照片或可疑收费立即举报"]
        }
        if type == "work" || type == "job" || type == "hiring" {
            return ["招聘不允许押金、保证金或培训费骗局", "核实招聘方身份、工作地点和签证支持说明", "警惕虚假高薪、违法兼职和灰产招聘", "遇到可疑内容立即举报"]
        }
        if type == "local_service" {
            return ["商家与本地服务默认进入审核，服务方认证状态会展示", "酒店、票务、旅行、接送机等服务需写清资质、包含/不包含内容和取消规则", "暂不开放外卖配送；禁止成人服务、高风险线下服务和违法服务", "不要提前转账给未核验服务方，预约前确认服务范围、取消规则和所需材料"]
        }
        if type == "discount" {
            return ["确认优惠有效期、适用门店和使用规则", "不要把个人敏感信息发给未核验商家", "遇到虚假折扣、诱导转账或强制消费立即举报"]
        }
        return ["Machi 不代收二手交易款", "不要提前转账，交易建议选择公共场所", "核实对方身份，谨慎提供个人信息", "遇到可疑内容立即举报"]
    }

    static func sortForDisplay(_ lhs: KaiXCityListingDTO, _ rhs: KaiXCityListingDTO) -> Bool {
        let left = lhs.published_at ?? lhs.updated_at ?? lhs.created_at ?? ""
        let right = rhs.published_at ?? rhs.updated_at ?? rhs.created_at ?? ""
        return left > right
    }

    static func statusLabel(_ status: String, type: String? = nil) -> String {
        formatListingStatus(status, type: type)
    }

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "published": KXColor.accent
        case "pending_review": KXColor.heat
        default: .secondary
        }
    }

    static func verificationLabel(_ status: String) -> String {
        formatVerificationStatus(status)
    }

    static func attr(_ listing: KaiXCityListingDTO, _ key: String) -> String? {
        guard let raw = listing.attributes?[key]?.listingDisplayValue else { return nil }
        return formatAttribute(key: key, value: raw)
    }

    static func boolAttr(_ listing: KaiXCityListingDTO, _ key: String) -> Bool {
        listing.attributes?[key]?.boolValue ?? false
    }

    private static func fallbackPriceLabel(for type: String) -> String {
        switch type {
        case "rental": "租金咨询"
        case "job", "hiring": "薪资面议"
        case "local_service": "预约咨询"
        case "discount": "查看优惠"
        default: "价格咨询"
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
        if let cover = primaryCoverMedia, let url = cover.previewURL {
            return url
        }
        if let raw = card?.coverUrl ?? listingCard?.coverUrl ?? coverUrl ?? cover_url,
           let url = raw.kaixMediaURL {
            return url
        }
        return nil
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
        case .null:
            return ""
        }
    }
}
