import Foundation
import SwiftData

@MainActor
final class TopicRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchTrending(limit: Int = 20) async throws -> [TopicEntity] {
        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let response = try await KaiXAPIClient.shared.exploreTopics(region: RegionStore.shared.current, limit: limit)
            return response.orderedTopics.map(ServerEntityFactory.topic(from:))
        }
        var descriptor = FetchDescriptor<TopicEntity>(
            sortBy: [SortDescriptor(\.heatScore, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func fetchTopic(name: String) async throws -> TopicEntity? {
        let normalized = name.normalizedTopicName
        guard normalized.isEmpty == false else { return nil }

        if KaiXBackend.token != nil || !KaiXRuntimeFlags.allowLocalStoreFallback {
            let posts = try await KaiXAPIClient.shared.topic(normalized)
            return TopicEntity(
                name: normalized,
                postCount: posts.count,
                heatScore: posts.reduce(0) { $0 + ($1.heatScore ?? $1.heat_score) }
            )
        }

        var descriptor = FetchDescriptor<TopicEntity>(
            predicate: #Predicate { $0.name == normalized }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func rebuildFromPosts() async throws {
        guard KaiXRuntimeFlags.allowLocalStoreFallback else { return }
        let published = PostStatus.published.rawValue
        let active = PostStatus.active.rawValue
        let posts = try context.fetch(FetchDescriptor<PostEntity>(
            predicate: #Predicate { $0.statusRaw == published || $0.statusRaw == active }
        ))
        let topics = try context.fetch(FetchDescriptor<TopicEntity>())
        topics.forEach(context.delete)

        let grouped = Dictionary(grouping: posts.flatMap { post in
            post.hashtags.map { ($0.normalizedTopicName, post.heatScore) }
        }, by: { $0.0 })

        for (name, values) in grouped where !name.isEmpty {
            context.insert(TopicEntity(
                name: name,
                postCount: values.count,
                heatScore: values.reduce(0) { $0 + $1.1 }
            ))
        }

        try context.save()
    }
}
