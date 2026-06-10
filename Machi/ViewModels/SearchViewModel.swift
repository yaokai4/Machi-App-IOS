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

    func load(context: ModelContext, currentUser: UserEntity, postStore: PostStore? = nil, searchStore: SearchStore? = nil) async {
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

            do {
                let response = try await KaiXAPIClient.shared.exploreHappening(region: region, limit: 30)
                loadedHappening = upsertRemotePosts(response.orderedPosts, context: context)
            } catch {
                loadedHappening = []
            }

            do {
                let response = try await KaiXAPIClient.shared.exploreHot(region: region, limit: 30)
                loadedHot = upsertRemotePosts(response.orderedPosts, context: context)
            } catch {
                loadedHot = []
            }

            do {
                let response = try await KaiXAPIClient.shared.exploreTopics(region: region, limit: 20)
                loadedTopics = try upsertRemoteTopics(response.orderedTopics, context: context)
            } catch {
                loadedTopics = []
            }

            if loadedHot.isEmpty {
                loadedHot = try await postRepository.fetchPage(mode: .hot, currentUserId: currentUser.id, page: 0, pageSize: 30)
            }
            if loadedHappening.isEmpty {
                loadedHappening = loadedHot
            }
            if loadedTopics.isEmpty {
                loadedTopics = try await topicRepository.fetchTrending(limit: 20)
            }

            happeningPosts = loadedHappening
            hotPosts = loadedHot
            topics = loadedTopics

            let visiblePosts = orderedUniquePosts(loadedHappening + loadedHot)
            postStore?.register(visiblePosts)
            mediaByPostId = try await postRepository.fetchMedia(for: visiblePosts)
            for post in visiblePosts where mediaByPostId[post.id] == nil {
                mediaByPostId[post.id] = []
            }
            let postAuthors = try await userRepository.fetchUsers(ids: Set(visiblePosts.map(\.authorId)))
            authors = Dictionary(uniqueKeysWithValues: postAuthors.map { ($0.id, $0) })
            suggestedUsers = try await userRepository.fetchRecommendedUsers(excluding: currentUser.id, limit: 12)
            followingIds = try await userRepository.followingIds(for: currentUser.id)
            rebuildTrendingItems()
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
        do {
            let isFollowing = try await UserRepository(context: context).toggleFollow(currentUser: currentUser, targetUser: target)
            userStore?.register([currentUser, target])
            userStore?.setFollowing(isFollowing, userId: target.id)
            userStore?.updateCounts(userId: currentUser.id, followers: currentUser.followerCount, following: currentUser.followingCount)
            userStore?.updateCounts(userId: target.id, followers: target.followerCount, following: target.followingCount)
            followingIds = try await UserRepository(context: context).followingIds(for: currentUser.id)
            rebuildTrendingItems()
        } catch {
            state = .error(error.kaixUserMessage)
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

    func trendingItems(region: KaiXRegionDirectory.Region?, contentTypes: [ContentType]? = nil, limit: Int = 8) -> [TrendingItem] {
        let filtered = hotPosts.filter { post in
            let matchesRegion: Bool
            if let region {
                matchesRegion = post.regionCode == region.regionCode || (post.country == region.countryCode && post.city == region.cityCode)
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

    private func upsertRemotePosts(_ posts: [KaiXPostDTO], context: ModelContext) -> [PostEntity] {
        guard !posts.isEmpty else { return [] }
        var result: [PostEntity] = []
        for dto in posts {
            if let author = dto.author {
                _ = RemoteSyncService.shared.upsertUser(author, context: context)
            }
            if let originalAuthor = dto.original_post?.author {
                _ = RemoteSyncService.shared.upsertUser(originalAuthor, context: context)
            }
            result.append(RemoteSyncService.shared.upsertPost(dto, context: context))
        }
        try? context.save()
        return orderedUniquePosts(result)
    }

    private func upsertRemoteTopics(_ remoteTopics: [KaiXTopicDTO], context: ModelContext) throws -> [TopicEntity] {
        guard !remoteTopics.isEmpty else { return [] }
        var result: [TopicEntity] = []
        for dto in remoteTopics {
            let name = dto.normalizedTag
            guard !name.isEmpty else { continue }
            var descriptor = FetchDescriptor<TopicEntity>(
                predicate: #Predicate { $0.name == name }
            )
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.postCount = dto.postCountValue
                existing.heatScore = dto.heatScoreValue
                existing.updatedAt = .now
                result.append(existing)
            } else {
                let topic = TopicEntity(
                    id: "topic-\(name)",
                    name: name,
                    postCount: dto.postCountValue,
                    heatScore: dto.heatScoreValue
                )
                context.insert(topic)
                result.append(topic)
            }
        }
        try? context.save()
        return result
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
