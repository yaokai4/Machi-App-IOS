import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var searchStore: SearchStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = SearchViewModel()
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var scope = SearchScope.hot
    @State private var recentSearchesStorage = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    let currentUser: UserEntity

    private var recommendedUsers: [UserEntity] {
        var uniqueUsers: [String: UserEntity] = [:]
        for user in viewModel.suggestedUsers + Array(viewModel.authors.values) {
            uniqueUsers[user.id] = user
        }
        return uniqueUsers.values
            .filter { $0.id != currentUser.id }
            .filter { viewModel.query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(viewModel.query) || $0.username.localizedCaseInsensitiveContains(viewModel.query.normalizedUsername) }
            .sorted { $0.followerCount > $1.followerCount }
    }

    private var recentSearches: [String] {
        recentSearchesStorage.split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    private var recentSearchKey: String {
        "recentSearches.\(currentUser.id)"
    }

    private var visiblePopularRegions: [KaiXRegionDirectory.Region] {
        let country = currentUser.country.isEmpty ? regionStore.current?.countryCode : currentUser.country
        guard let country, !country.isEmpty else {
            return Array(KaiXRegionDirectory.popular.prefix(16))
        }
        return Array(KaiXRegionDirectory.popular.filter { $0.countryCode == country }.prefix(16))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading, .idle:
                LoadingView()
            case .empty:
                EmptyStateView(title: L("emptySearch", language), subtitle: L("searchPlaceholder", language), systemImage: "magnifyingglass")
            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await viewModel.load(context: modelContext, currentUser: currentUser, postStore: postStore, searchStore: searchStore) }
                }
            case .loaded:
                content
            }
        }
        .kxPageBackground()
        .accessibilityIdentifier("search.root")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            recentSearchesStorage = UserDefaults.standard.string(forKey: recentSearchKey) ?? ""
            await viewModel.load(context: modelContext, currentUser: currentUser, postStore: postStore, searchStore: searchStore)
        }
        .onChange(of: viewModel.query) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    viewModel.updateDebouncedQuery(newValue)
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            discoverHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                recentSearchSection
                localPulseSection
                trendingOverviewSection
                popularRegionsSection
                contentTypeHotGrid
                SearchScopePicker(selection: $scope)

                switch scope {
                case .hot:
                    rankedItems(title: L("hotSearchRank", language), items: viewModel.filteredTrendingItems)
                case .news:
                    rankedItems(title: L("newsRank", language), items: viewModel.latestTrendingItems)
                case .topics:
                    topicGrid
                case .users:
                    recommendedUserSection
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 14)
            .padding(.bottom, chrome.bottomContentPadding + KXSpacing.lg)
            }
            .refreshable {
                await viewModel.load(context: modelContext, currentUser: currentUser, postStore: postStore, searchStore: searchStore)
            }
        }
    }

    private var discoverHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: KXSpacing.md) {
                Button {
                    router.open(.profile(userId: currentUser.id))
                } label: {
                    AvatarView(user: currentUser, size: 42)
                        .overlay(Circle().stroke(KXColor.cardBackground, lineWidth: 2))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L("discover", language))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Button {
                        if let region = regionStore.current {
                            router.open(.city(regionCode: region.regionCode))
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2.weight(.bold))
                            Text(regionStore.current.map { KaiXRegionDirectory.localizedHeaderLabel($0, language: language) } ?? L("pickRegion", language))
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    if let region = regionStore.current {
                        router.open(.city(regionCode: region.regionCode))
                    }
                } label: {
                    Image(systemName: "map.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(KXColor.accent)
                        .frame(width: 40, height: 40)
                        .kxGlassCircle()
                }
                .buttonStyle(.plain)
            }

            Button {
                router.open(.search(initialQuery: nil))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.headline.weight(.bold))
                    Text(L("searchPlaceholder", language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, KXSpacing.md)
                .frame(height: 46)
                .kxGlassCapsule()
                .overlay {
                    Capsule()
                        .stroke(KXColor.glassStroke.opacity(0.86), lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
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

    @ViewBuilder
    private var recentSearchSection: some View {
        if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            EmptyView()
        } else if recentSearches.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("recentSearches", language))
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button(L("clear", language)) {
                        recentSearchesStorage = ""
                        UserDefaults.standard.set("", forKey: recentSearchKey)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(recentSearches, id: \.self) { item in
                            Button {
                                viewModel.query = item
                            } label: {
                                Text(item)
                                    .font(.subheadline.weight(.bold))
                                    .padding(.horizontal, 12)
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

    private func saveRecentSearch() {
        let trimmed = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        var items = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        recentSearchesStorage = items.prefix(8).joined(separator: "|")
        UserDefaults.standard.set(recentSearchesStorage, forKey: recentSearchKey)
    }

    private var cityHotItems: [TrendingItem] {
        let local = viewModel.trendingItems(region: regionStore.current, limit: 8)
        return local.isEmpty ? Array(viewModel.trendingItems.prefix(8)) : local
    }

    private var countryHotItems: [TrendingItem] {
        let country = viewModel.countryTrendingItems(region: regionStore.current, limit: 8)
        return country.isEmpty ? Array(viewModel.trendingItems.prefix(8)) : country
    }

    private var heroItems: [TrendingItem] {
        let merged = cityHotItems + countryHotItems + viewModel.trendingItems
        var seen = Set<String>()
        return merged.filter { seen.insert($0.id).inserted }.prefix(6).map { $0 }
    }

    @ViewBuilder
    private var localPulseSection: some View {
        let items = heroItems
        if !items.isEmpty {
            DiscoverPulseCard(
                region: regionStore.current,
                items: items,
                topics: Array(viewModel.topics.prefix(8)),
                language: language,
                onOpenItem: { item in
                    saveRecentSearch()
                    open(item)
                },
                onOpenTopic: { topic in
                    router.open(.topic(tag: topic.name))
                }
            )
        }
    }

    private var trendingOverviewSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: KXSpacing.sm) {
                DiscoverOverviewCard(
                    title: regionStore.current.map { "\($0.cityName) \(L("hot", language))" } ?? L("hot", language),
                    icon: "location.fill",
                    tint: KXColor.rankSky,
                    item: cityHotItems.first,
                    language: language,
                    onOpen: { if let item = cityHotItems.first { open(item) } }
                )
                DiscoverOverviewCard(
                    title: regionStore.current.map {
                        let country = KaiXRegionDirectory.localizedCountryName(.init(code: $0.countryCode, name: $0.countryName, emoji: $0.countryEmoji, tier: 1, hasProvinces: !$0.provinceCode.isEmpty), language: language)
                        return "\(country) \(L("hot", language))"
                    } ?? L("trending", language),
                    icon: "globe.asia.australia.fill",
                    tint: KXColor.rankTeal,
                    item: countryHotItems.first,
                    language: language,
                    onOpen: { if let item = countryHotItems.first { open(item) } }
                )
                DiscoverOverviewCard(
                    title: L("trending", language),
                    icon: "flame.fill",
                    tint: KXColor.heat,
                    item: viewModel.trendingItems.first,
                    language: language,
                    onOpen: { if let item = viewModel.trendingItems.first { open(item) } }
                )
            }
        }
    }

    private func rankedItems(title: String, items: [TrendingItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if items.isEmpty {
                KXEmptyState(title: title, subtitle: L("noContent", language), systemImage: "tray")
            } else {
                VStack(spacing: 0) {
                    let visibleItems = Array(items.prefix(12))
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            saveRecentSearch()
                            open(item)
                        } label: {
                            SearchRankingRow(rank: index + 1, item: item, language: language)
                        }
                        .buttonStyle(.plain)

                        if index < visibleItems.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .kxGlassSurface(radius: KXRadius.lg)
            }

            if scope != .users && !recommendedUsers.isEmpty {
                recommendedUserSection
                    .padding(.top, 10)
            }
        }
    }

    private var discoverSections: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            if let region = regionStore.current {
                compactRankingSection(title: "\(region.cityName) \(L("hot", language))", items: viewModel.trendingItems(region: region, limit: 5))
                compactRankingSection(title: "\(KaiXRegionDirectory.localizedCountryName(.init(code: region.countryCode, name: region.countryName, emoji: region.countryEmoji, tier: 1, hasProvinces: !region.provinceCode.isEmpty), language: language)) \(L("hot", language))", items: viewModel.countryTrendingItems(region: region, limit: 5))
            }
            popularRegionsSection
            contentTypeHotGrid
        }
    }

    private func compactRankingSection(title: String, items: [TrendingItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if items.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                        Button {
                            open(item)
                        } label: {
                            SearchRankingRow(rank: index + 1, item: item, language: language)
                        }
                        .buttonStyle(.plain)
                        if index < min(items.count, 5) - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .kxGlassSurface(radius: KXRadius.lg)
            }
        }
    }

    private var popularRegionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("popularCities", language))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(visiblePopularRegions, id: \.regionCode) { region in
                        Button {
                            router.open(.city(regionCode: region.regionCode))
                        } label: {
                            Text(KaiXRegionDirectory.localizedHeaderLabel(region, language: language))
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .padding(.horizontal, 11)
                                .frame(height: 32)
                                .kxGlassCapsule()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var contentTypeHotGrid: some View {
        let groups: [(String, String, Color, [ContentType])] = [
            (L("ct_news", language), "newspaper.fill", Color(red: 0.09, green: 0.48, blue: 0.94), [.news, .local_info]),
            (L("ct_guide", language), "map.fill", KXColor.rankTeal, [.guide]),
            (L("ct_secondhand", language), "shippingbox.fill", Color(red: 0.74, green: 0.45, blue: 0.13), [.secondhand]),
            (L("ct_housing", language), "house.lodge.fill", Color(red: 0.13, green: 0.55, blue: 0.42), [.housing, .roommate]),
            (L("ct_jobseek", language), "briefcase.fill", KXColor.rankViolet, [.job_seek]),
            (L("ct_jobpost", language), "person.text.rectangle.fill", Color(red: 0.92, green: 0.35, blue: 0.30), [.job_post, .referral]),
            (L("ct_event", language), "calendar.badge.clock", Color(red: 0.00, green: 0.52, blue: 0.72), [.event]),
            (L("ct_meetup", language), "person.2.fill", Color(red: 0.52, green: 0.45, blue: 0.91), [.meetup, .dining]),
            (L("ct_merchant", language), "storefront.fill", Color(red: 0.83, green: 0.39, blue: 0.61), [.merchant, .service]),
            (L("ct_coupon", language), "ticket.fill", KXColor.heat, [.coupon]),
        ]
        return VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack {
                Text(L("discoverRadar", language))
                    .font(.headline.weight(.bold))
                Spacer()
                Text(regionStore.current?.cityName ?? L("trending", language))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(groups, id: \.0) { group in
                    let localLead = viewModel.trendingItems(region: regionStore.current, contentTypes: group.3, limit: 1).first
                    let globalLead = viewModel.trendingItems(region: nil, contentTypes: group.3, limit: 1).first
                    let lead = localLead ?? globalLead
                    Button {
                        if let lead { open(lead) }
                    } label: {
                        DiscoverTypeCard(
                            title: group.0,
                            icon: group.1,
                            tint: group.2,
                            item: lead,
                            isLocal: localLead != nil,
                            language: language
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(lead == nil)
                }
            }
        }
    }

    private var topicGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("topics", language))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(viewModel.topics) { topic in
                    Button {
                        router.open(.topic(tag: topic.name))
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("#\(topic.name)")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(topic.postCount) \(L("posts", language))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                        .kxGlassSurface(radius: KXRadius.md)
                    }
                    .buttonStyle(.plain)
                }
            }
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

    private var recommendedUserSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("recommendedFollow", language))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(recommendedUsers.prefix(6)) { user in
                SearchUserRow(
                    user: user,
                    isFollowing: viewModel.followingIds.contains(user.id),
                    onOpen: { router.open(.profile(userId: user.id)) },
                    onFollow: {
                        Task { await viewModel.toggleFollow(context: modelContext, currentUser: currentUser, target: user, userStore: userStore) }
                    }
                )
            }
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
    @State private var recentSearchesStorage = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    let currentUser: UserEntity
    let initialQuery: String

    private var recentSearchKey: String {
        "recentSearches.\(currentUser.id)"
    }

    private var recentSearches: [String] {
        recentSearchesStorage.split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    private var trimmedQuery: String {
        viewModel.debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var userResults: [UserEntity] {
        viewModel.filteredUsers
            .filter { $0.id != currentUser.id }
            .sorted { $0.followerCount > $1.followerCount }
    }

    private var hasResults: Bool {
        !viewModel.filteredTrendingItems.isEmpty
        || !viewModel.filteredTopics.isEmpty
        || !userResults.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch viewModel.state {
                case .loading, .idle:
                    LoadingView()
                case .empty:
                    KXEmptyState(title: L("emptySearch", language), subtitle: L("searchPlaceholder", language), systemImage: "magnifyingglass")
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
        .toolbar(.hidden, for: .navigationBar)
        .task {
            recentSearchesStorage = UserDefaults.standard.string(forKey: recentSearchKey) ?? ""
            if !initialQuery.isEmpty {
                viewModel.query = initialQuery
                viewModel.updateDebouncedQuery(initialQuery)
            }
            await load()
            isSearchFocused = true
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
        .onChange(of: isSearchFocused) { _, focused in
            chrome.setHidden(focused, reason: .input)
        }
        .onDisappear {
            chrome.setHidden(false, reason: .input)
            searchDebounceTask?.cancel()
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
                    rankingSection(title: L("hotSearchRank", language), items: viewModel.trendingItems, limit: 8)
                    topicSection(title: L("topics", language), topics: viewModel.topics.prefix(8).map { $0 })
                    usersSection(title: L("recommendedFollow", language), users: userResults.prefix(6).map { $0 })
                } else if hasResults {
                    rankingSection(title: L("posts", language), items: viewModel.filteredTrendingItems, limit: 10)
                    topicSection(title: L("topics", language), topics: Array(viewModel.filteredTopics.prefix(8)))
                    usersSection(title: L("users", language), users: Array(userResults.prefix(8)))
                    rankingSection(title: L("newsRank", language), items: viewModel.latestTrendingItems, limit: 6)
                } else {
                    KXEmptyState(title: L("emptySearch", language), subtitle: viewModel.query, systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 12)
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
                        recentSearchesStorage = ""
                        UserDefaults.standard.set("", forKey: recentSearchKey)
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

    private func rankingSection(title: String, items: [TrendingItem], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader(title: title)

            if items.isEmpty {
                KXEmptyState(title: title, subtitle: L("noContent", language), systemImage: "tray")
            } else {
                VStack(spacing: 0) {
                    let visibleItems = Array(items.prefix(limit))
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            saveRecentSearch(viewModel.query)
                            open(item)
                        } label: {
                            SearchRankingRow(rank: index + 1, item: item, language: language)
                        }
                        .buttonStyle(.plain)

                        if index < visibleItems.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .kxGlassSurface(radius: KXRadius.lg, elevated: true)
            }
        }
    }

    private func topicSection(title: String, topics: [TopicEntity]) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader(title: title)

            if topics.isEmpty {
                KXEmptyState(title: title, subtitle: L("noTopicPosts", language), systemImage: "number")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: KXSpacing.sm) {
                    ForEach(topics) { topic in
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
            }
        }
    }

    private func usersSection(title: String, users: [UserEntity]) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            KXSectionHeader(title: title)

            if users.isEmpty {
                KXEmptyState(title: title, subtitle: L("noContent", language), systemImage: "person.2")
            } else {
                ForEach(users) { user in
                    SearchUserRow(
                        user: user,
                        isFollowing: viewModel.followingIds.contains(user.id),
                        onOpen: {
                            saveRecentSearch(viewModel.query.isEmpty ? user.displayName : viewModel.query)
                            router.open(.profile(userId: user.id))
                        },
                        onFollow: {
                            Task { await viewModel.toggleFollow(context: modelContext, currentUser: currentUser, target: user, userStore: userStore) }
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var happeningNowSection: some View {
        let items = Array(viewModel.trendingItems.prefix(4))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(alignment: .center, spacing: KXSpacing.sm) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(KXColor.accent)
                        .frame(width: 32, height: 32)
                        .background(KXColor.accent.opacity(0.10), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
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
        var items = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        items.insert(trimmed, at: 0)
        recentSearchesStorage = items.prefix(8).joined(separator: "|")
        UserDefaults.standard.set(recentSearchesStorage, forKey: recentSearchKey)
    }

    private func load() async {
        await viewModel.load(context: modelContext, currentUser: currentUser, postStore: postStore, searchStore: searchStore)
    }
}

private enum SearchScope: String, CaseIterable, Identifiable {
    case hot
    case news
    case topics
    case users

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .hot: L("hotSearch", language)
        case .news: L("news", language)
        case .topics: L("topics", language)
        case .users: L("users", language)
        }
    }
}

private struct SearchScopePicker: View {
    @Environment(\.appLanguage) private var language
    @Binding var selection: SearchScope

    var body: some View {
        KXSegmentedControl(SearchScope.allCases, selection: $selection) { scope in
            Text(scope.title(language))
        }
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
                colors: [KXColor.rankCoral.opacity(0.23), Color(red: 1.000, green: 0.486, blue: 0.286).opacity(0.13)],
                foreground: KXColor.rankCoral,
                stroke: KXColor.rankCoral.opacity(0.32),
                shadow: .clear,
                isProminent: true
            )
        case 3:
            return SearchRankStyle(
                colors: [KXColor.rankViolet.opacity(0.22), Color(red: 0.245, green: 0.469, blue: 0.980).opacity(0.13)],
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
            .font(.system(size: rank <= 3 ? 16 : 15, weight: .bold, design: .rounded).monospacedDigit())
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

        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: compact ? 10 : 11, weight: .black, design: .rounded))
                .frame(width: compact ? 10 : 11)

            Text(NumberFormatterUtils.compact(Int(score.rounded())))
                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded).monospacedDigit())
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
        HStack(spacing: 4) {
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
                        HStack(spacing: 4) {
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
            LazyVStack(alignment: .leading, spacing: 12) {
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
            .padding(KaiXTheme.horizontalPadding)
            .padding(.bottom, chrome.bottomContentPadding)
        }
        .kxPageBackground()
        .navigationTitle("#\(topicName)")
        .task(id: tag.normalizedTopicName) { await load() }
    }

    private var topicHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        KXSegmentedControl(TopicDetailScope.allCases, selection: $scope) { item in
            Text(item.title(language))
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
                FlowLayout(spacing: 8) {
                    ForEach(relatedRegions, id: \.regionCode) { region in
                        Button {
                            router.open(.city(regionCode: region.regionCode))
                        } label: {
                            Text(KaiXRegionDirectory.localizedHeaderLabel(region, language: language))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
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
