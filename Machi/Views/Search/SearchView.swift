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
    @State private var recentSearchesStorage = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var serverSearchTask: Task<Void, Never>?
    @State private var savedSearchSaving = false
    @State private var savedSearchDone = false
    @State private var selectedResultTab: SearchResultTab = .posts
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
            recentSearchesStorage = UserDefaults.standard.string(forKey: recentSearchKey) ?? ""
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
        .onChange(of: viewModel.debouncedQuery) { _, _ in
            // Every settled query hits the server (/api/search) — the client
            // filters above only cover the ~30 preloaded hot items.
            savedSearchDone = false
            serverSearchTask?.cancel()
            serverSearchTask = Task { await viewModel.searchServer() }
        }
        .onChange(of: isSearchFocused) { _, focused in
            chrome.setHidden(focused, reason: .input)
        }
        .onDisappear {
            chrome.setHidden(false, reason: .input)
            searchDebounceTask?.cancel()
            serverSearchTask?.cancel()
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
                    subscribeSearchButton
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
                        rankingSection(title: L("posts", language), items: combinedPostItems, limit: 10)
                        rankingSection(title: L("newsRank", language), items: viewModel.latestTrendingItems, limit: 6)
                    case .topics:
                        topicSection(title: L("topics", language), topics: Array(combinedTopics.prefix(8)))
                    case .users:
                        usersSection(title: L("users", language), users: Array(combinedUsers.prefix(8)))
                    case .listings:
                        if viewModel.searchedListings.isEmpty {
                            KXEmptyState(title: L("listings", language), subtitle: L("noContent", language), systemImage: "tray")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                        } else {
                            listingsSection
                        }
                    }
                } else if viewModel.serverSearchLoading {
                    // First server round-trip for this query — don't flash
                    // "no results" while it's still in flight.
                    LoadingView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                } else {
                    KXEmptyState(title: L("emptySearch", language), subtitle: viewModel.query, systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                    subscribeSearchButton
                        .frame(maxWidth: .infinity)
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
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                KXSectionHeader(title: L("listings", language))
                ForEach(viewModel.searchedListings.prefix(10)) { item in
                    KXStructuredListingRow(listing: item) {
                        saveRecentSearch(viewModel.query)
                        router.open(.cityListingDetail(listingId: item.id))
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
                            guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以关注感兴趣的人。", "ログインするとフォローできます。", "Sign in to follow people.")) else { return }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
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
