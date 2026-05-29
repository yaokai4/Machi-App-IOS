import Foundation
import SwiftData

@Model
final class FollowEntity {
    @Attribute(.unique) var id: String
    var followerId: String
    var followingId: String
    var createdAt: Date

    init(id: String = UUID().uuidString, followerId: String, followingId: String, createdAt: Date = .now) {
        self.id = id
        self.followerId = followerId
        self.followingId = followingId
        self.createdAt = createdAt
    }
}

@Model
final class DatabaseMetadataEntity {
    @Attribute(.unique) var id: String
    var schemaVersion: Int
    var seedVersion: Int
    var lastMigrationAt: Date

    init(id: String = "database.metadata", schemaVersion: Int, seedVersion: Int, lastMigrationAt: Date = .now) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.seedVersion = seedVersion
        self.lastMigrationAt = lastMigrationAt
    }
}
