import Foundation
import SwiftData

@MainActor
final class TopicRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchTrending(limit: Int = 20) async throws -> [TopicEntity] {
        var descriptor = FetchDescriptor<TopicEntity>(
            sortBy: [SortDescriptor(\.heatScore, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func fetchTopic(name: String) async throws -> TopicEntity? {
        let normalized = name.normalizedTopicName
        guard normalized.isEmpty == false else { return nil }

        var descriptor = FetchDescriptor<TopicEntity>(
            predicate: #Predicate { $0.name == normalized }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func rebuildFromPosts() async throws {
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
