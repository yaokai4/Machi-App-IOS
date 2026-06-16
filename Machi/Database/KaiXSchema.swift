import SwiftData

enum KaiXSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserEntity.self,
            PostEntity.self,
            MediaEntity.self,
            CommentEntity.self,
            MessageThreadEntity.self,
            MessageEntity.self,
            NotificationEntity.self,
            TopicEntity.self,
            FollowEntity.self,
            DatabaseMetadataEntity.self
        ]
    }
}

enum KaiXMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [KaiXSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
