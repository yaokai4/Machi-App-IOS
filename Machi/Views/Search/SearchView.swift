import Combine
import SwiftData
import SwiftUI

/// Result categories shown as a segmented tab row (X-style) once a query has
/// matches — replaces the old single long column that stacked 帖子 / 话题 / 用户 /
/// 信息 on top of each other. One tap switches category instead of scrolling past
/// every other kind of result.
private enum SearchResultTab: String, CaseIterable, Identifiable, Hashable {
    case posts
    case topics
    case users
    case listings

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .posts: L("posts", language)
        case .topics: L("topics", language)
        case .users: L("users", language)
        case .listings: L("listings", language)
        }
    }
}

struct SearchScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var searchStore: SearchStore
    @EnvironmentObject private var router: KXRouter
    @StateObject private var viewModel = SearchViewModel()
    // 最近搜索存 stringArray:旧版用 "|" 拼接单字符串,搜索词本身含竖线
    // (正则/店名/日文混排)会被拆碎且永久污染历史。首次读取做一次旧格式迁移。
    @State private var recentSearchItems: [String] = []
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var serverSearchTask: Task<Void, Never>?
    @State private var savedSearchSaving = false
    @State private var savedSearchDone = false
    @State private var selectedResultTab: SearchResultTab = .posts
    // 相关性结果里被硬截断的组「查看更多」展开态,换查询时清空。
    @State private var expandedResultTabs: Set<SearchResultTab> = []
    // 三大支柱(指南学校 / 公司 / 资料 + 商家目录)的搜索结果,做成独立于四个
    // 核心 Tab 的分组卡。某类无命中(或无 q 参数端点)时整组跳过。
    @StateObject private var pillars = SearchPillarLoader()
    @State private var pillarTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    let currentUser: UserEntity
    let initialQuery: String

    private var recentSearchKey: String {
        "recentSearches.\(currentUser.id)"
    }

    private var recentSearches: [String] {
        recentSearchItems.filter { !$0.isEmpty }
    }

    private var trimmedQuery: String {
        viewModel.debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Machi Guide 端点用的语言码(zh-CN / ja / en),与 Web 客户端一致。
    private var guideLanguageCode: String {
        switch language {
        case .ja: return "ja"
        case .en: return "en"
        default: return "zh-CN"
        }
    }

    private func t(_ zh: String, _ ja: String, _ en: String) -> String {
        KXListingCopy.pickText(language, zh, ja, en)
    }

    private var userResults: [UserEntity] {
        viewModel.filteredUsers
            .filter { $0.id != currentUser.id }
            .sorted { $0.followerCount > $1.followerCount }
    }

    // Server hits (/api/search) lead each section; the instant client-side
    // filters over the preloaded hot items fill in while the request runs
    // (and remain the offline fallback). Dedup keeps overlap invisible.
    private var combinedPostItems: [TrendingItem] {
        var seen = Set<String>()
        return (viewModel.serverPostItems + viewModel.filteredTrendingItems)
            .filter { seen.insert($0.id).inserted }
    }

    private var combinedTopics: [TopicEntity] {
        var seen = Set<String>()
        return (viewModel.serverTopics + viewModel.filteredTopics)
            .filter { seen.insert($0.name).inserted }
    }

    private var combinedUsers: [UserEntity] {
        var seen = Set<String>()
        return (viewModel.serverUsers + userResults)
            .filter { $0.id != currentUser.id && seen.insert($0.id).inserted }
    }

    private var hasResults: Bool {
        !combinedPostItems.isEmpty
        || !combinedTopics.isEmpty
        || !combinedUsers.isEmpty
        || !viewModel.searchedListings.isEmpty
    }

    // 落地页的"正在发生"与"热搜榜"曾同源同序(都取 trendingItems 头部,前 4 条
    // 100% 重复)。"正在发生"改用真实 recency 排序的 latestItems(名副其实),
    // 热搜榜过滤掉已在上方展示的条目,首屏不再连续两块一样的内容。
    private var landingHappeningItems: [TrendingItem] {
        Array(viewModel.latestItems.prefix(4))
    }

    private var landingHotRankItems: [TrendingItem] {
        let happeningIds = Set(landingHappeningItems.map(\.id))
        return viewModel.trendingItems.filter { !happeningIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch viewModel.state {
                case .loading, .idle:
                    ScrollView {
                        KXFeedSkeleton()
                            .padding(.horizontal, KXSpacing.screen)
                            .padding(.top, KXSpacing.md)
                    }
                case .empty:
                    // The preloaded hot/topic pool can be empty (fresh region,
                    // guest) — server search must still work, so an active
                    // query renders the results content, not a dead end.
                    if trimmedQuery.isEmpty {
                        KXEmptyState(title: L("emptySearch", language), subtitle: L("searchPlaceholder", language), systemImage: "magnifyingglass", illustration: .search)
                    } else {
                        resultsContent
                    }
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await load() }
                    }
                case .loaded:
                    resultsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .kxPageBackground()
        .overlay(alignment: .top) {
            if let message = viewModel.followErrorMessage {
                KXInlineNotice(message: message) {
                    viewModel.followErrorMessage = nil
                }
                .padding(.top, 64)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let stored = UserDefaults.standard.stringArray(forKey: recentSearchKey) {
                recentSearchItems = stored
            } else if let legacy = UserDefaults.standard.string(forKey: recentSearchKey) {
                // 旧 "|" 拼接格式:按旧规则拆开迁移一次并改写为数组存储。
                let migrated = legacy.split(separator: "|").map(String.init).filter { !$0.isEmpty }
                recentSearchItems = migrated
                UserDefaults.standard.set(migrated, forKey: recentSearchKey)
            }
            if !initialQuery.isEmpty {
                viewModel.query = initialQuery
                viewModel.updateDebouncedQuery(initialQuery)
            }
            // Focus (raise the keyboard) BEFORE the network load, so opening the
            // search screen feels instant instead of waiting on results first.
            isSearchFocused = true
            await load()
        }
        .onChange(of: viewModel.query) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    viewModel.updateDebouncedQuery(newValue)
                }
            }
        }
        .onChange(of: viewModel.debouncedQuery) { _, newValue in
            // Every settled query hits the server (/api/search) — the client
            // filters above only cover the ~30 preloaded hot items.
            savedSearchDone = false
            // 换新关键词回到"帖子"Tab:停在"信息"等 Tab 的用户对新查询会直接
            // 看到该类目的空态,误以为整个查询无结果。
            selectedResultTab = .posts
            expandedResultTabs = []
            serverSearchTask?.cancel()
            serverSearchTask = Task { await viewModel.searchServer() }
            // 三大支柱(指南 + 商家)与核心搜索并发,各自独立降级为空(跳过该组)。
            pillarTask?.cancel()
            pillarTask = Task { await pillars.search(newValue, language: guideLanguageCode) }
        }
        .onChange(of: isSearchFocused) { _, focused in
            chrome.setHidden(focused, reason: .input)
        }
        .onDisappear {
            chrome.setHidden(false, reason: .input)
            searchDebounceTask?.cancel()
            serverSearchTask?.cancel()
            pillarTask?.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: KXSpacing.sm) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("cancel", language))

            HStack(spacing: KXSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isSearchFocused ? KXColor.accent : .secondary)
                TextField(L("searchPlaceholder", language), text: $viewModel.query)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .tint(KXColor.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { saveRecentSearch(viewModel.query) }

                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                        viewModel.updateDebouncedQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("clear", language))
                }
            }
            .padding(.horizontal, KXSpacing.md)
            .frame(height: 42)
            .kxGlassCapsule()
            .overlay {
                Capsule()
                    .stroke(isSearchFocused ? KXColor.accent.opacity(0.58) : KXColor.glassStroke.opacity(0.88), lineWidth: isSearchFocused ? 1.1 : 0.8)
            }
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.md)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private var resultsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: KXSpacing.md) {
                if trimmedQuery.isEmpty {
                    recentSearchSection
                    happeningNowSection
                    rankingSection(title: L("hotSearchRank", language), items: landingHotRankItems, limit: 8)
                    topicSection(title: L("topics", language), topics: viewModel.topics, limit: 8)
                    usersSection(title: L("recommendedFollow", language), users: userResults, limit: 6)
                } else {
                    // 订阅入口在最前,四个核心 Tab 之后接三大支柱(指南 + 商家)分组卡。
                    subscribeSearchButton

                    if hasResults {
                        KXSegmentedControl(
                            SearchResultTab.allCases,
                            selection: $selectedResultTab,
                            itemMinWidth: 60,
                            itemHeight: 40
                        ) { tab in
                            Text(tab.title(language))
                        }
                        .padding(.bottom, KXSpacing.xs)
                        switch selectedResultTab {
                        case .posts:
                            // 相关性列表:去掉 1/2/3 名次徽章(那是热搜榜的排行语义),
                            // 超过 limit 时补「查看更多」就地展开已加载的长尾。
                            rankingSection(title: L("posts", language), items: combinedPostItems, limit: 10, ranked: false, tab: .posts)
                            // "最新"是对 ~30 条预载热帖的客户端过滤,真实长尾查询几乎
                            // 必空 —— 空时整块隐藏,不在有效结果下方挂"暂无内容"空态。
                            if !viewModel.latestTrendingItems.isEmpty {
                                rankingSection(title: L("newsRank", language), items: viewModel.latestTrendingItems, limit: 6, ranked: false)
                            }
                        case .topics:
                            topicSection(title: L("topics", language), topics: combinedTopics, limit: 8, tab: .topics)
                        case .users:
                            usersSection(title: L("users", language), users: combinedUsers, limit: 8, tab: .users)
                        case .listings:
                            if viewModel.searchedListings.isEmpty {
                                KXEmptyState(title: L("listings", language), subtitle: L("noContent", language), systemImage: "tray")
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, KXSpacing.xl)
                            } else {
                                listingsSection
                            }
                        }
                    }

                    pillarResultsSection

                    // 全空态(核心四类 + 三大支柱都无命中)才接管:加载中给 spinner,
                    // 失败给错误 + 重试,否则真·无结果。有支柱命中时不显示,避免盖住卡片。
                    if !hasResults && !pillars.hasAny {
                        if viewModel.serverSearchLoading || pillars.loading {
                            LoadingView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)
                        } else if let searchError = viewModel.searchErrorMessage {
                            // 服务端搜索失败 ≠ 无结果:断网 / 超时要给出错误 + 重试,
                            // 不能伪装成"未找到相关内容"让用户以为平台没有这条信息。
                            ErrorStateView(message: searchError) {
                                serverSearchTask?.cancel()
                                serverSearchTask = Task { await viewModel.searchServer() }
                                pillarTask?.cancel()
                                pillarTask = Task { await pillars.search(viewModel.debouncedQuery, language: guideLanguageCode) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                        } else {
                            KXEmptyState(title: L("emptySearch", language), subtitle: viewModel.query, systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)
                        }
                    }
                }
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.top, KXSpacing.md)
            .padding(.bottom, chrome.bottomContentPadding + KXSpacing.lg)
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private var recentSearchSection: some View {
        if recentSearches.isEmpty == false {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                HStack {
                    KXSectionHeader(title: L("recentSearches", language))
                    Spacer()
                    Button(L("clear", language)) {
                        recentSearchItems = []
                        UserDefaults.standard.set([String](), forKey: recentSearchKey)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: KXSpacing.sm) {
                        ForEach(recentSearches, id: \.self) { item in
                            Button {
                                viewModel.query = item
                                viewModel.updateDebouncedQuery(item)
                            } label: {
                                Text(item)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, KXSpacing.md)
                                    .frame(height: 34)
                                    .kxGlassCapsule()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Migrated from the retired SearchView's listings scope: subscribe to the
    /// current keyword (POST /api/saved_searches) so new matching listings
    /// notify the user. Hidden for guests — saved searches are per-account.
    @ViewBuilder
    private var subscribeSearchButton: some View {
        let q = trimmedQuery
        if !currentUser.isGuest, !q.isEmpty {
            Button {
                guard !savedSearchSaving, !savedSearchDone else { return }
                savedSearchSaving = true
                Task {
                    defer { savedSearchSaving = false }
                    do {
                        _ = try await KaiXAPIClient.shared.createSavedSearch(keyword: q, label: q)
                        savedSearchDone = true
                    } catch {
                        savedSearchDone = false
                        // 失败必须有反馈:否则 spinner 归位、按钮原样,用户以为
                        // 已订阅关键词提醒,实际服务端从未记录。复用页顶通知条。
                        viewModel.followErrorMessage = error.kaixUserMessage
                    }
                }
            } label: {
                Label(
                    savedSearchDone ? L("subscribedSearch", language) : L("subscribeSearch", language),
                    systemImage: savedSearchDone ? "bell.fill" : "bell.badge"
                )
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(savedSearchSaving || savedSearchDone)
            .accessibilityIdentifier("search.subscribeListing")
        }
    }

    /// Migrated from the retired SearchView's listings scope: cross-city
    /// listing hits from /api/search (kind=all) as structured rows.
    @ViewBuilder
    private var listingsSection: some View {
        if !viewModel.searchedListings.isEmpty {
            let items = viewModel.searchedListings
            let expanded = expandedResultTabs.contains(.listings)
            let visible = Array(items.prefix(expanded ? items.count : 10))
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                KXSectionHeader(title: L("listings", language))
                ForEach(visible) { item in
                    KXStructuredListingRow(listing: item) {
                        saveRecentSearch(viewModel.query)
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                }
                if items.count > 10 {
                    expandRow(tab: .listings, total: items.count)
                }
            }
        }
    }

    // MARK: - 三大支柱结果组(指南学校 / 公司 / 资料 + 商家目录)

    /// 相关性结果下方的分组卡:每组前 3 条 + 「查看更多」跳对应库页。空组自动
    /// 跳过。JLPT 无 q 参数搜索端点,故不单列 —— 指南资料(products)覆盖大部分
    /// 备考材料,查看更多跳会员资料库。
    @ViewBuilder
    private var pillarResultsSection: some View {
        if !trimmedQuery.isEmpty {
            if !pillars.schools.isEmpty {
                pillarCard(
                    title: t("学校库", "学校データベース", "Schools"),
                    systemImage: "graduationcap.fill",
                    tint: .blue,
                    moreRoute: .guideSchools
                ) {
                    let items = Array(pillars.schools.prefix(3))
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, school in
                        pillarRow(
                            icon: "graduationcap.fill",
                            tint: .blue,
                            title: localizedSchoolName(school),
                            subtitle: schoolSubtitle(school),
                            isLast: index == items.count - 1
                        ) {
                            saveRecentSearch(viewModel.query)
                            router.open(.guideSchool(id: school.id))
                        }
                    }
                }
            }

            if !pillars.companies.isEmpty {
                pillarCard(
                    title: t("公司库", "企業データベース", "Companies"),
                    systemImage: "building.2.fill",
                    tint: .indigo,
                    moreRoute: .guideCompanies
                ) {
                    let items = Array(pillars.companies.prefix(3))
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, company in
                        pillarRow(
                            icon: "building.2.fill",
                            tint: .indigo,
                            title: localizedCompanyName(company),
                            subtitle: companySubtitle(company),
                            isLast: index == items.count - 1
                        ) {
                            saveRecentSearch(viewModel.query)
                            router.open(.guideCompany(id: company.id))
                        }
                    }
                }
            }

            if !pillars.products.isEmpty {
                pillarCard(
                    title: t("指南资料", "ガイド資料", "Guide resources"),
                    systemImage: "doc.richtext.fill",
                    tint: .purple,
                    moreRoute: .guideMemberResources
                ) {
                    let items = Array(pillars.products.prefix(3))
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, product in
                        pillarRow(
                            icon: "doc.richtext.fill",
                            tint: .purple,
                            title: product.title,
                            subtitle: product.subtitle.isEmpty ? product.priceLabel : product.subtitle,
                            isLast: index == items.count - 1
                        ) {
                            saveRecentSearch(viewModel.query)
                            router.open(.guideProduct(slug: product.slug.isEmpty ? product.id : product.slug))
                        }
                    }
                }
            }

            if !pillars.articles.isEmpty {
                pillarCard(
                    title: t("指南文章", "ガイド記事", "Guide articles"),
                    systemImage: "text.book.closed.fill",
                    tint: .teal,
                    moreRoute: nil
                ) {
                    let items = Array(pillars.articles.prefix(3))
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, article in
                        pillarRow(
                            icon: "text.book.closed.fill",
                            tint: .teal,
                            title: article.title,
                            subtitle: article.summary,
                            isLast: index == items.count - 1
                        ) {
                            saveRecentSearch(viewModel.query)
                            router.open(.guideArticle(slug: article.slug.isEmpty ? article.id : article.slug))
                        }
                    }
                }
            }

            if !pillars.merchants.isEmpty {
                pillarCard(
                    title: L("verifiedMerchant", language),
                    systemImage: "storefront.fill",
                    tint: .green,
                    moreRoute: nil
                ) {
                    let items = Array(pillars.merchants.prefix(3))
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, business in
                        pillarRow(
                            icon: "storefront.fill",
                            tint: .green,
                            title: business.business_name ?? L("merchantFallbackName", language),
                            subtitle: merchantSubtitle(business),
                            isLast: index == items.count - 1
                        ) {
                            saveRecentSearch(viewModel.query)
                            router.open(.businessProfile(businessId: business.id))
                        }
                    }
                }
            }
        }
    }

    private func pillarCard<Content: View>(
        title: String,
        systemImage: String,
        tint: Color,
        moreRoute: KXRoute?,
        @ViewBuilder rows: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                if let moreRoute {
                    Button {
                        saveRecentSearch(viewModel.query)
                        router.open(moreRoute)
                    } label: {
                        HStack(spacing: 3) {
                            Text(L("seeAll", language))
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                rows()
            }
            .kxGlassSurface(radius: KXRadius.lg, elevated: true)
        }
    }

    private func pillarRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: KXSpacing.md) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, KXSpacing.md)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isLast {
                Divider().padding(.leading, 58)
            }
        }
    }

    private func localizedSchoolName(_ school: KaiXGuideSchoolDTO) -> String {
        switch language {
        case .ja: return school.schoolNameJp.isEmpty ? school.schoolName : school.schoolNameJp
        case .en: return school.schoolNameEn.isEmpty ? school.schoolName : school.schoolNameEn
        default: return school.schoolName
        }
    }

    private func schoolSubtitle(_ school: KaiXGuideSchoolDTO) -> String {
        [school.prefecture, school.city, school.schoolType]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " · ")
    }

    private func localizedCompanyName(_ company: KaiXGuideCompanyDTO) -> String {
        switch language {
        case .ja: return company.companyNameJp.isEmpty ? company.companyName : company.companyNameJp
        case .en: return (company.companyNameEn ?? "").isEmpty ? company.companyName : (company.companyNameEn ?? company.companyName)
        default: return company.companyName
        }
    }

    private func companySubtitle(_ company: KaiXGuideCompanyDTO) -> String {
        [company.industry, company.city]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func merchantSubtitle(_ business: KaiXBusinessPublicDTO) -> String {
        if let type = business.business_type, !type.isEmpty { return type }
        if let first = business.service_categories?.first, !first.isEmpty { return first }
        return L("localMerchant", language)
    }

    /// `ranked` 决定行样式:热搜榜 → 带 1/2/3 名次徽章(排行语义);相关性结果
    /// → 无徽章的列表行。传入 `tab` 时,超过 `limit` 的部分补「查看更多」就地展开。
    private func rankingSection(title: String, items: [TrendingItem], limit: Int, ranked: Bool = true, tab: SearchResultTab? = nil) -> some View {
        let expanded = tab.map { expandedResultTabs.contains($0) } ?? false
        let effectiveLimit = expanded ? items.count : limit
        let visibleItems = Array(items.prefix(effectiveLimit))
        let dividerInset: CGFloat = ranked ? 58 : 62
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader(title: title)

            if items.isEmpty {
                KXEmptyState(title: title, subtitle: L("noContent", language), systemImage: "tray")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            saveRecentSearch(viewModel.query)
                            open(item)
                        } label: {
                            if ranked {
                                SearchRankingRow(rank: index + 1, item: item, language: language)
                            } else {
                                SearchResultRow(item: item, language: language)
                            }
                        }
                        .buttonStyle(.plain)

                        if index < visibleItems.count - 1 {
                            Divider().padding(.leading, dividerInset)
                        }
                    }

                    if let tab, items.count > limit {
                        Divider().padding(.leading, dividerInset)
                        expandRow(tab: tab, total: items.count)
                    }
                }
                .kxGlassSurface(radius: KXRadius.lg, elevated: true)
            }
        }
    }

    /// 「查看更多 / 收起」——把已加载但被硬截断的长尾结果就地展开(无分页端点时
    /// 这是诚实可达的最优解:只显示确实已在手的结果,不假装能翻页)。
    private func expandRow(tab: SearchResultTab, total: Int) -> some View {
        let isExpanded = expandedResultTabs.contains(tab)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isExpanded { expandedResultTabs.remove(tab) } else { expandedResultTabs.insert(tab) }
            }
        } label: {
            HStack(spacing: KXSpacing.xs) {
                Text(isExpanded ? t("收起", "折りたたむ", "Show less") : "\(L("seeAll", language)) · \(total)")
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(KXColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func topicSection(title: String, topics: [TopicEntity], limit: Int = .max, tab: SearchResultTab? = nil) -> some View {
        let expanded = tab.map { expandedResultTabs.contains($0) } ?? false
        let effectiveLimit = expanded ? topics.count : limit
        let visibleTopics = Array(topics.prefix(effectiveLimit))
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader(title: title)

            if topics.isEmpty {
                KXEmptyState(title: title, subtitle: L("noTopicPosts", language), systemImage: "number")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: KXSpacing.sm) {
                    ForEach(visibleTopics) { topic in
                        Button {
                            saveRecentSearch(viewModel.query.isEmpty ? "#\(topic.name)" : viewModel.query)
                            router.open(.topic(tag: topic.name))
                        } label: {
                            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                                Text("#\(topic.name)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(topic.postCount) \(L("posts", language))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(KXSpacing.md)
                            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                            .kxGlassSurface(radius: KXRadius.md)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let tab, topics.count > limit {
                    expandRow(tab: tab, total: topics.count)
                }
            }
        }
    }

    private func usersSection(title: String, users: [UserEntity], limit: Int = .max, tab: SearchResultTab? = nil) -> some View {
        let expanded = tab.map { expandedResultTabs.contains($0) } ?? false
        let effectiveLimit = expanded ? users.count : limit
        let visibleUsers = Array(users.prefix(effectiveLimit))
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader(title: title)

            if users.isEmpty {
                KXEmptyState(title: title, subtitle: L("noContent", language), systemImage: "person.2")
            } else {
                ForEach(visibleUsers) { user in
                    SearchUserRow(
                        user: user,
                        isFollowing: viewModel.followingIds.contains(user.id),
                        onOpen: {
                            saveRecentSearch(viewModel.query.isEmpty ? user.displayName : viewModel.query)
                            router.open(.profile(userId: user.id))
                        },
                        onFollow: {
                            guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以关注感兴趣的人。", "ログインするとフォローできます。", "Sign in to follow people.")) else { return }
                            Task { await viewModel.toggleFollow(context: modelContext, currentUser: currentUser, target: user, userStore: userStore) }
                        }
                    )
                }
                if let tab, users.count > limit {
                    expandRow(tab: tab, total: users.count)
                }
            }
        }
    }

    @ViewBuilder
    private var happeningNowSection: some View {
        // 真实 recency 排序(latestItems),不再与下方热搜榜同源同序。
        let items = landingHappeningItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(alignment: .center, spacing: KXSpacing.sm) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(KXColor.accent)
                        .frame(width: 32, height: 32)
                        .background(KXColor.accent.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(L("happeningNow", language))
                            .font(.headline.weight(.semibold))
                        Text(L("happeningSubtitle", language))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                if let lead = items.first {
                    Button {
                        saveRecentSearch(viewModel.query)
                        open(lead)
                    } label: {
                        HappeningLeadCard(item: lead, language: language)
                    }
                    .buttonStyle(.plain)
                }

                let secondaryItems = Array(items.dropFirst().prefix(3))
                if !secondaryItems.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(secondaryItems.enumerated()), id: \.element.id) { index, item in
                            Button {
                                saveRecentSearch(viewModel.query)
                                open(item)
                            } label: {
                            HappeningCompactRow(index: index + 2, item: item, language: language)
                            }
                            .buttonStyle(.plain)

                            if index < secondaryItems.count - 1 {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                                    .fill(KXColor.cardBackground.opacity(0.54))
                            }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                            .stroke(KXColor.glassStroke.opacity(0.76), lineWidth: 0.8)
                    }
                }
            }
            .padding(KXSpacing.md)
            .kxGlassSurface(radius: KXRadius.lg, elevated: true)
        }
    }

    private func open(_ item: TrendingItem) {
        switch item.type {
        case .post, .news:
            guard let postId = item.targetId ?? item.postId, !postId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                router.routeErrorMessage = L("postDeletedHelp", language)
                return
            }
            router.open(.postDetail(postId: postId))
        case .topic:
            guard let topicId = item.targetId ?? item.topicId, !topicId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                router.routeErrorMessage = L("noTopicPosts", language)
                return
            }
            router.open(.topic(tag: topicId))
        case .user:
            guard let userId = item.targetId ?? item.userId, !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                router.routeErrorMessage = L("unknownUser", language)
                return
            }
            router.open(.profile(userId: userId))
        }
    }

    private func saveRecentSearch(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        var items = recentSearchItems.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        recentSearchItems = Array(items.prefix(8))
        UserDefaults.standard.set(recentSearchItems, forKey: recentSearchKey)
    }

    private func load() async {
        await viewModel.load(context: modelContext, currentUser: currentUser, postStore: postStore, searchStore: searchStore)
    }
}

private extension TrendingItemType {
    var rankingIcon: String {
        switch self {
        case .post: "text.bubble.fill"
        case .topic: "number"
        case .user: "person.crop.circle.fill"
        case .news: "newspaper.fill"
        }
    }

    var palette: [Color] {
        switch self {
        case .post:
            [KXColor.rankSky, KXColor.accent]
        case .topic:
            [KXColor.rankTeal, Color.green]
        case .user:
            [KXColor.rankViolet, Color.pink]
        case .news:
            [KXColor.rankGold, KXColor.rankCoral]
        }
    }
}

private struct SearchRankStyle {
    let colors: [Color]
    let foreground: Color
    let stroke: Color
    let shadow: Color
    let isProminent: Bool

    static func style(for rank: Int, itemType: TrendingItemType) -> SearchRankStyle {
        switch rank {
        case 1:
            return SearchRankStyle(
                colors: [KXColor.rankGold.opacity(0.26), Color.orange.opacity(0.15)],
                foreground: KXColor.heat,
                stroke: KXColor.rankGold.opacity(0.34),
                shadow: .clear,
                isProminent: true
            )
        case 2:
            return SearchRankStyle(
                colors: [KXColor.rankCoral.opacity(0.23), KXColor.rankCoralGlow.opacity(0.13)],
                foreground: KXColor.rankCoral,
                stroke: KXColor.rankCoral.opacity(0.32),
                shadow: .clear,
                isProminent: true
            )
        case 3:
            return SearchRankStyle(
                colors: [KXColor.rankViolet.opacity(0.22), KXColor.rankVioletGlow.opacity(0.13)],
                foreground: KXColor.rankViolet,
                stroke: KXColor.rankViolet.opacity(0.30),
                shadow: .clear,
                isProminent: true
            )
        case 4...6:
            let colors = itemType.palette
            return SearchRankStyle(
                colors: colors.map { $0.opacity(0.23) } + [KXColor.softBackground.opacity(0.86)],
                foreground: colors.first ?? KXColor.accent,
                stroke: (colors.first ?? KXColor.accent).opacity(0.32),
                shadow: .clear,
                isProminent: false
            )
        default:
            return SearchRankStyle(
                colors: [KXColor.softBackground, Color(.systemBackground).opacity(0.72)],
                foreground: .secondary,
                stroke: KXColor.separator,
                shadow: .clear,
                isProminent: false
            )
        }
    }
}

private struct SearchRankBadge: View {
    let rank: Int
    let itemType: TrendingItemType
    var size: CGFloat = 34

    var body: some View {
        let style = SearchRankStyle.style(for: rank, itemType: itemType)

        Text("\(rank)")
            .monospacedDigit()
            .kxScaledFont(rank <= 3 ? 16 : 15, relativeTo: .callout, weight: .bold, design: .rounded)
            .foregroundStyle(style.foreground)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: style.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [KXColor.glassHighlight, .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .opacity(rank <= 6 ? 1 : 0.45)
                    }
            }
            .overlay {
                Circle()
                    .stroke(style.stroke, lineWidth: rank <= 3 ? 1.2 : 1)
            }
            .shadow(color: style.shadow, radius: 0, y: 0)
    }
}

private struct RankingHeatPill: View {
    let score: Double
    let style: SearchRankStyle
    var compact = false

    var body: some View {
        let color = style.colors.first ?? KXColor.accent

        HStack(spacing: KXSpacing.xs) {
            Image(systemName: "flame.fill")
                .kxScaledFont(compact ? 10 : 11, relativeTo: .caption2, weight: .black, design: .rounded)
                .frame(width: compact ? 10 : 11)

            Text(NumberFormatterUtils.compact(Int(score.rounded())))
                .monospacedDigit()
                .kxScaledFont(compact ? 10 : 11, relativeTo: .caption2, weight: .bold, design: .rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
            .foregroundStyle(color.opacity(0.92))
            .padding(.horizontal, compact ? 7 : 8)
            .frame(minWidth: compact ? 48 : 62, minHeight: compact ? 22 : 24)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                Capsule()
                    .fill(color.opacity(style.isProminent ? 0.16 : 0.13))
            }
            .overlay {
                Capsule()
                    .stroke(color.opacity(0.30), lineWidth: 1)
            }
    }
}

private struct HappeningLeadCard: View {
    let item: TrendingItem
    let language: AppLanguage

    var body: some View {
        let style = SearchRankStyle.style(for: 1, itemType: item.type)
        let backgroundColors = style.colors.map { $0.opacity(0.24) } + [KXColor.cardBackground.opacity(0.94)]

        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(spacing: KXSpacing.sm) {
                Text(L("topStory", language))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(style.foreground)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background((style.colors.first ?? KXColor.accent).opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke((style.colors.first ?? KXColor.accent).opacity(0.22), lineWidth: 0.7))

                Spacer()

                RankingHeatPill(score: item.heatScore, style: style, compact: true)
            }

            Text(item.title)
                .searchTitleFallback(item: item, language: language)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: KXSpacing.sm) {
                Text(item.sourceName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.86))
                        .lineLimit(1)
                }
            }
        }
        .padding(KXSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .stroke((style.colors.first ?? KXColor.accent).opacity(0.32), lineWidth: 0.9)
        }
    }
}

private struct HappeningCompactRow: View {
    let index: Int
    let item: TrendingItem
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .center, spacing: KXSpacing.sm) {
            SearchRankBadge(rank: index, itemType: item.type, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .searchTitleFallback(item: item, language: language)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                RankingMetaLabel(icon: item.type.rankingIcon, text: item.sourceName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, KXSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SearchRankingRow: View {
    let rank: Int
    let item: TrendingItem
    let language: AppLanguage

    var body: some View {
        let style = SearchRankStyle.style(for: rank, itemType: item.type)

        HStack(alignment: .center, spacing: KXSpacing.sm) {
            SearchRankBadge(rank: rank, itemType: item.type)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .searchTitleFallback(item: item, language: language)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    RankingMetaLabel(icon: item.type.rankingIcon, text: item.sourceName)
                }

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)
            HStack(spacing: 7) {
                RankingHeatPill(score: item.heatScore, style: style, compact: false)
                    .accessibilityLabel("\(Int(item.heatScore.rounded()))")

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }
}

private extension Text {
    func searchTitleFallback(item: TrendingItem, language: AppLanguage) -> Text {
        guard item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return self
        }

        switch item.type {
        case .post, .news:
            return Text(L("untitledPost", language))
        case .topic:
            return Text(L("untitledTopic", language))
        case .user:
            return Text(item.sourceName.isEmpty ? L("unknownUser", language) : item.sourceName)
        }
    }
}

private struct RankingMetaLabel: View {
    var icon: String?
    let text: String

    var body: some View {
        HStack(spacing: KXSpacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

/// 相关性结果行:与 `SearchRankingRow` 同信息量,但用类型图标替代 1/2/3 名次
/// 徽章 —— 搜索命中是相关性列表,不该套热搜榜的排行语义。
private struct SearchResultRow: View {
    let item: TrendingItem
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .center, spacing: KXSpacing.md) {
            Image(systemName: item.type.rankingIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(item.type.palette.first ?? KXColor.accent)
                .frame(width: 38, height: 38)
                .background((item.type.palette.first ?? KXColor.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .searchTitleFallback(item: item, language: language)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    RankingMetaLabel(icon: item.type.rankingIcon, text: item.sourceName)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.86))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
}

/// 三大支柱(指南学校 / 公司 / 资料 / 文章 + 商家目录)的搜索加载器,独立于
/// `SearchViewModel`。用 generation 票据做「最后发起者胜出」的竞态防护,与主
/// 搜索一致。任一端点失败(try?)即降级为空组 —— 该组在 UI 上被跳过,不误导
/// 用户以为平台没有该类内容。
@MainActor
final class SearchPillarLoader: ObservableObject {
    @Published private(set) var schools: [KaiXGuideSchoolDTO] = []
    @Published private(set) var companies: [KaiXGuideCompanyDTO] = []
    @Published private(set) var products: [KaiXGuideProductDTO] = []
    @Published private(set) var articles: [KaiXGuideArticleDTO] = []
    @Published private(set) var merchants: [KaiXBusinessPublicDTO] = []
    @Published private(set) var loading = false

    private var generation = 0

    var hasAny: Bool {
        !schools.isEmpty || !companies.isEmpty || !products.isEmpty || !articles.isEmpty || !merchants.isEmpty
    }

    func search(_ query: String, language: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        generation += 1
        let gen = generation
        guard !q.isEmpty else {
            reset()
            loading = false
            return
        }
        reset()
        loading = true
        defer {
            if gen == generation { loading = false }
        }
        // 指南统一搜索(articles/schools/companies/products,分组)+ 商家目录并发。
        async let guideFetch = try? KaiXAPIClient.shared.guideSearch(language: language, keyword: q)
        async let merchantFetch = try? KaiXAPIClient.shared.businessesDirectory(query: q)
        let guide = await guideFetch
        let merchant = await merchantFetch
        // Stale guard:用户在往返期间继续输入,只有最新一代请求可写状态。
        guard gen == generation else { return }
        if let groups = guide?.groups {
            schools = groups.schools ?? []
            companies = groups.companies ?? []
            products = groups.products ?? []
            articles = groups.articles ?? []
        }
        merchants = merchant?.items ?? []
    }

    private func reset() {
        schools = []
        companies = []
        products = []
        articles = []
        merchants = []
    }
}

private struct SearchUserRow: View {
    @Environment(\.appLanguage) private var language
    let user: UserEntity
    let isFollowing: Bool
    let onOpen: () -> Void
    let onFollow: () -> Void

    var body: some View {
        HStack(spacing: KXSpacing.md) {
            Button(action: onOpen) {
                HStack(spacing: KXSpacing.md) {
                    AvatarView(user: user, size: KXAvatarSize.md)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: KXSpacing.xs) {
                            Text(user.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            KXUserBadge(user: user)
                        }
                        Text("@\(user.username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(user.bio)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onFollow) {
                Text(isFollowing ? L("followed", language) : L("follow", language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFollowing ? Color.primary : KXColor.accent)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .kxGlassCapsule(isSelected: !isFollowing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, KXSpacing.sm)
        .kxGlassSurface(radius: KXRadius.md)
    }
}

struct TopicDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var router: KXRouter
    @StateObject private var viewModel = TopicDetailViewModel()
    @State private var scope = TopicDetailScope.hot

    let tag: String
    let currentUser: UserEntity

    private var topicName: String {
        (viewModel.topic?.name ?? tag.normalizedTopicName).normalizedTopicName
    }

    private var topicPostCount: Int {
        viewModel.topic?.postCount ?? viewModel.posts.count
    }

    private var filteredPosts: [PostEntity] {
        let posts = viewModel.posts.map { postStore.post(id: $0.id) ?? $0 }
        switch scope {
        case .hot:
            return posts.sorted { $0.heatScore > $1.heatScore }
        case .latest:
            return posts.sorted { $0.createdAt > $1.createdAt }
        case .highHeat:
            return posts.sorted {
                if Int($0.heatScore) == Int($1.heatScore) {
                    return $0.createdAt > $1.createdAt
                }
                return $0.heatScore > $1.heatScore
            }
        case .media:
            return posts.filter { viewModel.mediaByPostId[$0.id]?.isEmpty == false }
        case .contributors, .cities:
            return []
        }
    }

    private var participantCount: Int {
        Set(viewModel.posts.map(\.authorId)).count
    }

    private var contributors: [UserEntity] {
        let heatByAuthor = Dictionary(grouping: viewModel.posts, by: \.authorId)
            .mapValues { posts in posts.reduce(0) { $0 + $1.heatScore } }
        return viewModel.authors.values.sorted { (heatByAuthor[$0.id] ?? 0) > (heatByAuthor[$1.id] ?? 0) }
    }

    private var relatedRegions: [KaiXRegionDirectory.Region] {
        var seen = Set<String>()
        return viewModel.posts.compactMap { post in
            let region: KaiXRegionDirectory.Region?
            if !post.regionCode.isEmpty {
                region = KaiXRegionDirectory.resolve(regionCode: post.regionCode)
            } else if !post.country.isEmpty, !post.city.isEmpty {
                region = KaiXRegionDirectory.make(country: post.country, province: post.province.isEmpty ? nil : post.province, city: post.city)
            } else {
                region = nil
            }
            guard let region, seen.insert(region.regionCode).inserted else { return nil }
            return region
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: KXSpacing.md) {
                topicHeader
                topicScopePicker

                switch viewModel.state {
                case .loading, .idle:
                    LoadingView()
                case .empty:
                    EmptyStateView(title: "#\(topicName)", subtitle: L("noTopicPosts", language), systemImage: "number")
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await load() }
                    }
                case .loaded:
                    if scope == .contributors {
                        contributorsSection
                    } else if scope == .cities {
                        relatedCitiesSection
                    } else if filteredPosts.isEmpty {
                        EmptyStateView(title: "#\(topicName)", subtitle: L("noTopicPosts", language), systemImage: "number")
                            .padding(.top, 18)
                    }
                    ForEach(filteredPosts) { post in
                        let displayedPost = postStore.post(id: post.id) ?? post
                        let originalPost = displayedPost.repostOfPostId.flatMap { postStore.post(id: $0) }
                        let isQuoteRepost = originalPost != nil && !displayedPost.previewText.isEmpty
                        let targetPost = isQuoteRepost ? displayedPost : (originalPost ?? displayedPost)
                        let author = viewModel.authors[post.authorId]
                        PostCardView(
                            post: displayedPost,
                            author: author,
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
                            onLike: { Task { await viewModel.toggleLike(context: modelContext, post: targetPost, currentUser: currentUser, postStore: postStore) } },
                            onBookmark: { Task { await viewModel.toggleBookmark(context: modelContext, post: targetPost, currentUser: currentUser, postStore: postStore) } },
                            onRepost: { Task { await viewModel.repost(context: modelContext, post: targetPost, currentUser: currentUser, postStore: postStore) } },
                            onQuoteRepost: { content in
                                Task { await viewModel.quoteRepost(context: modelContext, post: targetPost, currentUser: currentUser, content: content, postStore: postStore) }
                            }
                        )
                        .equatable()
                    }
                }
            }
            .padding(KXSpacing.screen)
            .padding(.bottom, chrome.bottomContentPadding)
        }
        .kxPageBackground()
        .navigationTitle("#\(topicName)")
        .task(id: tag.normalizedTopicName) { await load() }
    }

    private var topicHeader: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Text("#\(topicName)")
                .font(.title.weight(.semibold))
            Text("\(topicPostCount) \(L("posts", language))")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("\(participantCount) \(L("participants", language)) · \(L("topicIntro", language))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private var topicScopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KXSpacing.sm) {
                ForEach(TopicDetailScope.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            scope = item
                        }
                    } label: {
                        Text(item.title(language))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(scope == item ? .white : .primary)
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(scope == item ? KXColor.accent : Color.clear, in: Capsule())
                            .overlay(Capsule().stroke(scope == item ? Color.clear : KXColor.separator, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, KXSpacing.xxs)
            .padding(.vertical, KXSpacing.xxs)
        }
    }

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader(title: L("topicContributors", language))
            if contributors.isEmpty {
                EmptyStateView(title: L("topicContributors", language), subtitle: L("noContent", language), systemImage: "person.2")
            } else {
                ForEach(contributors.prefix(12)) { user in
                    Button {
                        router.open(.profile(userId: user.id))
                    } label: {
                        HStack(spacing: KXSpacing.md) {
                            AvatarView(user: user, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("@\(user.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(KXSpacing.md)
                        .kxGlassSurface(radius: KXRadius.md)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var relatedCitiesSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader(title: L("relatedCities", language))
            if relatedRegions.isEmpty {
                EmptyStateView(title: L("relatedCities", language), subtitle: L("noContent", language), systemImage: "mappin")
            } else {
                FlowLayout(spacing: KXSpacing.sm) {
                    ForEach(relatedRegions, id: \.regionCode) { region in
                        Button {
                            router.open(.city(regionCode: region.regionCode))
                        } label: {
                            Text(KaiXRegionDirectory.localizedHeaderLabel(region, language: language))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, KXSpacing.md)
                                .frame(height: 34)
                                .kxGlassCapsule()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    @MainActor
    private func load() async {
        await viewModel.load(context: modelContext, topicName: topicName, postStore: postStore)
    }
}

private enum TopicDetailScope: String, CaseIterable, Identifiable {
    case hot
    case latest
    case highHeat
    case contributors
    case cities
    case media

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .hot: L("topicHot", language)
        case .latest: L("topicLatest", language)
        case .highHeat: L("topicHighHeat", language)
        case .contributors: L("topicContributors", language)
        case .cities: L("relatedCities", language)
        case .media: L("topicMedia", language)
        }
    }
}
