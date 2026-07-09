import Foundation
import Combine
import SwiftData

enum TrendingItemType: String, Hashable {
    case post
    case topic
    case user
    case news
}

struct TrendingItem: Identifiable, Hashable {
    let id: String
    let type: TrendingItemType
    let title: String
    let subtitle: String
    let sourceName: String
    let heatScore: Double
    let targetId: String?
    let postId: String?
    let topicId: String?
    let userId: String?
    let viewCount: Int
    let createdAt: Date
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var debouncedQuery = ""
    @Published var topics: [TopicEntity] = []
    @Published var happeningPosts: [PostEntity] = []
    @Published var hotPosts: [PostEntity] = []
    @Published var authors: [String: UserEntity] = [:]
    @Published var mediaByPostId: [String: [MediaEntity]] = [:]
    @Published var suggestedUsers: [UserEntity] = []
    @Published var followingIds: Set<String> = []
    @Published var state: ScreenState = .idle
    @Published private(set) var trendingItems: [TrendingItem] = []
    @Published private(set) var topicTrendingItems: [TrendingItem] = []
    @Published private(set) var userTrendingItems: [TrendingItem] = []
    @Published private(set) var latestItems: [TrendingItem] = []
    // O7: server-backed listing search results for the "信息/Listings" section.
    @Published private(set) var searchedListings: [KaiXCityListingDTO] = []
    // Server-backed global search (/api/search kind=all): posts / users /
    // topics beyond the ~30 preloaded hot items, plus cross-city listings.
    // The client-side filters stay as instant feedback; these arrive async.
    @Published private(set) var serverPostItems: [TrendingItem] = []
    @Published private(set) var serverTopics: [TopicEntity] = []
    @Published private(set) var serverUsers: [UserEntity] = []
    @Published private(set) var serverSearchLoading = false
    // Follow failures surface as a local, dismissible notice — never by
    // clobbering the whole page state with `.error` (which used to replace
    // Discover/Search with a full-screen error over a single failed follow).
    @Published var followErrorMessage: String?
    // 服务端搜索失败必须暴露给 UI：静默吞错会把"网络失败"伪装成"无结果"空态,
    // 用户会以为平台上真的没有这个内容。取消类错误(新查询顶替/清空)除外。
    @Published var searchErrorMessage: String?
    /// Monotonic ticket for server searches: "last issued wins".
    private var serverSearchGeneration = 0

    /// `allowRemote: false` keeps the load hermetic for UI/unit fixtures
    /// without live explore data bleeding into deterministic tests.
    func load(context: ModelContext, currentUser: UserEntity, postStore: PostStore? = nil, searchStore: SearchStore? = nil, allowRemote: Bool = true) async {
        let hasCachedContent = !topics.isEmpty || !hotPosts.isEmpty || !happeningPosts.isEmpty
        if !hasCachedContent {
            state = .loading
            searchStore?.setLoadingState(.loading)
        }

        do {
            let postRepository = PostRepository(context: context)
            let topicRepository = TopicRepository(context: context)
            let userRepository = UserRepository(context: context)
            let region = RegionStore.shared.current ?? KaiXRegionDirectory.resolve(regionCode: currentUser.currentRegionCode)

            var loadedHappening: [PostEntity] = []
            var loadedHot: [PostEntity] = []
            var loadedTopics: [TopicEntity] = []
            var loadedAuthors: [String: UserEntity] = [:]
            var loadedMediaByPostId: [String: [MediaEntity]] = [:]

            // The user-context lookups (recommended users + who-I-follow) don't
            // depend on the explore payloads, so they run concurrently with the
            // explore calls below instead of serially at the end. `try?` keeps
            // the old degrade-to-empty behavior for signed-out visitors (401).
            // Only the plain id is captured — not the SwiftData entity.
            let currentUserId = currentUser.id
            async let suggestedUsersFetch = try? userRepository.fetchRecommendedUsers(excluding: currentUserId, limit: 12)
            async let followingIdsFetch = try? userRepository.followingIds(for: currentUserId)

            // 三个 explore 请求是否全部失败(nil = 请求抛错被 try? 吞掉;成功但
            // 内容为空是合法的 loaded 空态,不算失败)。
            var remoteAllFailed = false
            if allowRemote {
                // The three explore requests are mutually independent — issue
                // them concurrently (async let) instead of back-to-back. Each
                // keeps its own error swallowing so a failed section degrades
                // to its fallback without touching the others, and the results
                // are consumed in the original order so the author/media merge
                // precedence (hot wins over happening) is unchanged.
                async let happeningFetch = try? KaiXAPIClient.shared.exploreHappening(region: region, limit: 30)
                async let hotFetch = try? KaiXAPIClient.shared.exploreHot(region: region, limit: 30)
                async let topicsFetch = try? KaiXAPIClient.shared.exploreTopics(region: region, limit: 20)

                let happeningResponse = await happeningFetch
                let hotResponse = await hotFetch
                let topicsResponse = await topicsFetch
                remoteAllFailed = happeningResponse == nil && hotResponse == nil && topicsResponse == nil

                if let response = happeningResponse {
                    let bundle = ServerEntityFactory.postBundle(from: response.orderedPosts)
                    loadedHappening = bundle.orderedPosts
                    loadedAuthors.merge(bundle.authors) { _, fresh in fresh }
                    loadedMediaByPostId.merge(bundle.mediaByPostId) { _, fresh in fresh }
                }

                if let response = hotResponse {
                    let bundle = ServerEntityFactory.postBundle(from: response.orderedPosts)
                    loadedHot = bundle.orderedPosts
                    loadedAuthors.merge(bundle.authors) { _, fresh in fresh }
                    loadedMediaByPostId.merge(bundle.mediaByPostId) { _, fresh in fresh }
                }

                if let response = topicsResponse {
                    loadedTopics = response.orderedTopics.map(ServerEntityFactory.topic(from:))
                }
            }

            if loadedHot.isEmpty {
                loadedHot = (try? await postRepository.fetchPage(mode: .hot, currentUserId: currentUser.id, page: 0, pageSize: 30)) ?? []
            }
            if loadedHappening.isEmpty {
                loadedHappening = loadedHot
            }
            if loadedTopics.isEmpty && KaiXRuntimeFlags.allowLocalStoreFallback {
                loadedTopics = try await topicRepository.fetchTrending(limit: 20)
            }

            // Release 下所有远端请求都是 try?、本地回退被 allowLocalStoreFallback
            // 关死,下面的 catch 实际不可达 —— 断网/后端全挂时页面会以 loaded
            // 渲染,把网络故障伪装成"你的城市暂无内容"。三个 explore 全部失败且
            // 无任何可展示内容时,显式走 .error(ErrorStateView 带重试);已有缓存
            // 内容时保留现有页面,不用空数组清掉。部分失败仍维持原有降级。
            if allowRemote, remoteAllFailed, loadedHappening.isEmpty, loadedHot.isEmpty, loadedTopics.isEmpty {
                if hasCachedContent {
                    state = .loaded
                    searchStore?.setLoadingState(.loaded)
                } else {
                    let lang = AppLanguage.resolved(
                        from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? AppLanguage.system.rawValue
                    )
                    state = .error(L("errNetwork", lang))
                    searchStore?.setLoadingState(state)
                }
                return
            }

            happeningPosts = loadedHappening
            hotPosts = loadedHot
            topics = loadedTopics

            let visiblePosts = orderedUniquePosts(loadedHappening + loadedHot)
            postStore?.register(visiblePosts)
            mediaByPostId = loadedMediaByPostId
            if mediaByPostId.isEmpty || visiblePosts.contains(where: { mediaByPostId[$0.id] == nil }) {
                let fetchedMedia = (try? await postRepository.fetchMedia(for: visiblePosts)) ?? [:]
                mediaByPostId.merge(fetchedMedia) { existing, fetched in existing.isEmpty ? fetched : existing }
            }
            for post in visiblePosts where mediaByPostId[post.id] == nil {
                mediaByPostId[post.id] = []
            }
            // Author / recommended-user / following lookups are user-specific and
            // 401 for signed-out visitors. Degrade gracefully with `try?` so a
            // guest still gets a fully-loaded Discover (public happening/hot/topics)
            // instead of an "加载失败" error screen.
            let missingAuthorIds = Set(visiblePosts.map(\.authorId)).subtracting(loadedAuthors.keys)
            let postAuthors = (try? await userRepository.fetchUsers(ids: missingAuthorIds)) ?? []
            loadedAuthors.merge(Dictionary(uniqueKeysWithValues: postAuthors.map { ($0.id, $0) })) { _, fresh in fresh }
            authors = loadedAuthors
            // Started concurrently above; published in the same order as before.
            suggestedUsers = (await suggestedUsersFetch) ?? []
            followingIds = (await followingIdsFetch) ?? []
            rebuildTrendingItems()
            // A successful load is .loaded even with zero preloaded content:
            // the discovery shell (search field + server-backed search) must
            // stay usable — an .empty takeover would kill search exactly when
            // the local pools have nothing (see searchLoadsDiscoveryShell test).
            state = .loaded
            searchStore?.setTrending(trendingItems + topicTrendingItems + userTrendingItems)
            searchStore?.setResults(trendingItems + topicTrendingItems + userTrendingItems)
            searchStore?.setLoadingState(state)
        } catch {
            if hasCachedContent {
                state = .loaded
                searchStore?.setLoadingState(.loaded)
            } else {
                state = .error(error.kaixUserMessage)
                searchStore?.setLoadingState(state)
            }
        }
    }

    func toggleFollow(context: ModelContext, currentUser: UserEntity, target: UserEntity, userStore: UserStore? = nil) async {
        guard GuestSession.requireSignedIn(currentUser) else { return }
        do {
            let isFollowing = try await UserRepository(context: context).toggleFollow(currentUser: currentUser, targetUser: target)
            userStore?.register([currentUser, target])
            userStore?.setFollowing(isFollowing, userId: target.id)
            userStore?.updateCounts(userId: currentUser.id, followers: currentUser.followerCount, following: currentUser.followingCount)
            userStore?.updateCounts(userId: target.id, followers: target.followerCount, following: target.followingCount)
            followingIds = try await UserRepository(context: context).followingIds(for: currentUser.id)
            rebuildTrendingItems()
        } catch {
            followErrorMessage = error.kaixUserMessage
        }
    }

    var filteredPosts: [PostEntity] {
        let trimmed = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return hotPosts }
        return hotPosts.filter {
            $0.content.localizedCaseInsensitiveContains(trimmed)
            || $0.hashtags.contains { $0.localizedCaseInsensitiveContains(trimmed.normalizedTopicName) }
        }
    }

    var filteredTrendingItems: [TrendingItem] {
        let trimmed = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trendingItems }
        return trendingItems.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmed)
            || item.subtitle.localizedCaseInsensitiveContains(trimmed)
            || item.sourceName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var latestTrendingItems: [TrendingItem] {
        let trimmed = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return latestItems }
        return latestItems.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmed)
            || item.subtitle.localizedCaseInsensitiveContains(trimmed)
            || item.sourceName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var filteredTopics: [TopicEntity] {
        let trimmed = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).normalizedTopicName
        guard !trimmed.isEmpty else { return topics }
        return topics.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var filteredUsers: [UserEntity] {
        let trimmed = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = trimmed.normalizedUsername
        guard !trimmed.isEmpty else { return suggestedUsers }
        return suggestedUsers.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
            || $0.username.localizedCaseInsensitiveContains(username)
            || $0.bio.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func updateDebouncedQuery(_ value: String) {
        debouncedQuery = value
    }

    /// Global server search (/api/search, kind=all): posts + users + topics +
    /// cross-city listings in one round trip. Called on every debounced query
    /// change; an empty query clears the server sections. Failures degrade to
    /// the client-side instant filters (no page-level error).
    func searchServer() async {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            // 清空查询也必须作废在途请求(generation +1):否则旧关键词的迟到响应
            // 会穿过下面的 stale guard(gen 未变),把已清空的四个数组整体写回,
            // 下一个关键词在途期间旧结果会被当作新查询的命中展示。
            serverSearchGeneration += 1
            serverPostItems = []
            serverTopics = []
            serverUsers = []
            searchedListings = []
            searchErrorMessage = nil
            return
        }
        serverSearchGeneration += 1
        let generation = serverSearchGeneration
        // 换新非空查询:先把上一查询的服务端命中作用域化清空,否则从'东京'改查
        // '拉面'时 combinedPostItems 仍拼上冻结的'东京'结果冒充新词命中,且非空
        // 的陈旧结果令 SearchView.hasResults 恒真,把其后的 serverSearchLoading
        // (LoadingView) 分支彻底挡死 —— 用户在整个网络往返窗口看到旧词结果挂在
        // 新词下且无任何加载提示。清空后:客户端即时过滤仍提供新词的瞬时反馈,
        // 无命中时 hasResults 转假,LoadingView 得以在结果回来前显示。
        serverPostItems = []
        serverTopics = []
        serverUsers = []
        searchedListings = []
        serverSearchLoading = true
        searchErrorMessage = nil
        defer {
            // Only the newest request may clear the spinner — a cancelled
            // predecessor unwinding late must not hide the in-flight one.
            if generation == serverSearchGeneration {
                serverSearchLoading = false
            }
        }
        do {
            let response = try await KaiXAPIClient.shared.search(q, kind: .all)
            // Stale guard: the user kept typing while this was in flight.
            // Task.isCancelled 双保险:取消未及时以错误形式传播时也不写状态。
            guard generation == serverSearchGeneration, !Task.isCancelled else { return }
            let bundle = ServerEntityFactory.postBundle(from: response.posts)
            authors.merge(bundle.authors) { _, fresh in fresh }
            serverPostItems = bundle.orderedPosts.map(makePostTrendingItem)
            serverTopics = response.topics.map(ServerEntityFactory.topic(from:))
            serverUsers = response.users.map(UserRepository.entity(from:))
            searchedListings = response.listings ?? []
            searchErrorMessage = nil
        } catch {
            // 取消(新查询顶替/清空)不是失败;真实失败要暴露给 UI,否则断网时
            // 搜索呈现"无结果"空态误导用户。仅最新一代请求可写错误。
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                return
            }
            guard generation == serverSearchGeneration else { return }
            searchErrorMessage = error.kaixUserMessage
        }
    }

    func trendingItems(region: KaiXRegionDirectory.Region?, contentTypes: [ContentType]? = nil, limit: Int = 8) -> [TrendingItem] {
        let regionCodes = KaiXRegionDirectory.regionCodesForMetro(region: region)
        let cityCodes = KaiXRegionDirectory.cityCodesForMetro(region: region)
        let filtered = hotPosts.filter { post in
            let matchesRegion: Bool
            if let region {
                matchesRegion = regionCodes.contains(post.regionCode)
                    || (post.country == region.countryCode && cityCodes.contains(post.city))
                    || (post.regionCode.isEmpty && post.country.isEmpty && post.city.isEmpty)
            } else {
                matchesRegion = true
            }
            let matchesType = contentTypes?.contains(post.contentType) ?? true
            return matchesRegion && matchesType
        }
        return Array(filtered.sorted { $0.heatScore > $1.heatScore }.prefix(limit).map(makePostTrendingItem))
    }

    func countryTrendingItems(region: KaiXRegionDirectory.Region?, limit: Int = 8) -> [TrendingItem] {
        guard let region else { return Array(trendingItems.prefix(limit)) }
        return Array(hotPosts
            .filter { $0.country == region.countryCode }
            .sorted { $0.heatScore > $1.heatScore }
            .prefix(limit)
            .map(makePostTrendingItem))
    }

    private func rebuildTrendingItems() {
        trendingItems = hotPosts.map(makePostTrendingItem)
        latestItems = trendingItems.sorted { $0.createdAt > $1.createdAt }
        topicTrendingItems = topics.map(makeTopicTrendingItem)
        userTrendingItems = suggestedUsers.map(makeUserTrendingItem)
    }

    private func orderedUniquePosts(_ posts: [PostEntity]) -> [PostEntity] {
        var seen = Set<String>()
        var result: [PostEntity] = []
        for post in posts where seen.insert(post.id).inserted {
            result.append(post)
        }
        return result
    }

    private func makePostTrendingItem(_ post: PostEntity) -> TrendingItem {
        let author = authors[post.authorId]
        return TrendingItem(
            id: "post-\(post.id)",
            type: .post,
            title: post.searchDisplayTitle,
            subtitle: post.hashtags.prefix(3).map { "#\($0)" }.joined(separator: " "),
            sourceName: author?.displayName ?? "@\(post.authorId.prefix(8))",
            heatScore: post.heatScore,
            targetId: post.repostOfPostId ?? post.id,
            postId: post.repostOfPostId ?? post.id,
            topicId: nil,
            userId: nil,
            viewCount: post.viewCount,
            createdAt: post.createdAt
        )
    }

    private func makeTopicTrendingItem(_ topic: TopicEntity) -> TrendingItem {
        TrendingItem(
            id: "topic-\(topic.name)",
            type: .topic,
            title: "#\(topic.name)",
            subtitle: "\(topic.postCount) posts",
            sourceName: "Machi",
            heatScore: topic.heatScore,
            targetId: topic.name,
            postId: nil,
            topicId: topic.name,
            userId: nil,
            viewCount: topic.postCount,
            createdAt: topic.updatedAt
        )
    }

    private func makeUserTrendingItem(_ user: UserEntity) -> TrendingItem {
        TrendingItem(
            id: "user-\(user.id)",
            type: .user,
            title: user.displayName,
            subtitle: "@\(user.username)",
            sourceName: user.isVerified ? "Verified" : "Machi",
            heatScore: Double(user.followerCount),
            targetId: user.id,
            postId: nil,
            topicId: nil,
            userId: user.id,
            viewCount: user.followerCount,
            createdAt: user.updatedAt
        )
    }
}

private extension PostEntity {
    var searchDisplayTitle: String {
        let withoutTags = content.replacingOccurrences(
            of: #"#[\p{L}\p{N}_-]+"#,
            with: "",
            options: .regularExpression
        )
        let collapsed = withoutTags
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sentence = collapsed
            .components(separatedBy: CharacterSet(charactersIn: "。！？.!?\n"))
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = sentence?.isEmpty == false ? sentence ?? collapsed : collapsed
        guard !candidate.isEmpty else { return previewText }
        if candidate.count > 42 {
            return "\(candidate.prefix(42))..."
        }
        return candidate
    }
}
