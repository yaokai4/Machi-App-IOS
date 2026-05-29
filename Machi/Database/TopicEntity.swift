import Foundation
import SwiftData

@Model
final class TopicEntity {
    @Attribute(.unique) var id: String
    @Attribute(.unique) var name: String
    var postCount: Int
    var heatScore: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        postCount: Int = 0,
        heatScore: Double = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name.normalizedTopicName
        self.postCount = postCount
        self.heatScore = heatScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
