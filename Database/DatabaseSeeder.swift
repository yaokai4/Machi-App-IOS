import Foundation
import SwiftData

@MainActor
enum DatabaseSeeder {
    static func bootstrapIfNeeded(context: ModelContext) async throws {
        try migrateMetadataIfNeeded(context: context)
        let didPurgeDemoData = try purgeDemoData(context: context)
        let metadata = try context.fetch(FetchDescriptor<DatabaseMetadataEntity>()).first
        let needsIntegrityRepair = didPurgeDemoData || (metadata?.seedVersion ?? 0) < KaiXConfig.seedVersion

        if needsIntegrityRepair {
            try DataIntegrityRepairer.repair(context: context)
            try rebuildTopicTable(context: context)
        }
        try ensureTopicTableExists(context: context)

        if let metadata = try context.fetch(FetchDescriptor<DatabaseMetadataEntity>()).first,
           metadata.seedVersion < KaiXConfig.seedVersion {
            metadata.seedVersion = KaiXConfig.seedVersion
            try context.save()
        }
        try context.save()
    }

    static func resetForDevelopment(context: ModelContext) throws {
        #if DEBUG
        try context.delete(model: UserEntity.self)
        try context.delete(model: PostEntity.self)
        try context.delete(model: MediaEntity.self)
        try context.delete(model: CommentEntity.self)
        try context.delete(model: MessageThreadEntity.self)
        try context.delete(model: MessageEntity.self)
        try context.delete(model: NotificationEntity.self)
        try context.delete(model: TopicEntity.self)
        try context.delete(model: FollowEntity.self)
        try context.delete(model: DatabaseMetadataEntity.self)
        context.insert(DatabaseMetadataEntity(
            schemaVersion: KaiXConfig.schemaVersion,
            seedVersion: KaiXConfig.seedVersion
        ))
        try context.save()
        #else
        _ = context
        throw RepositoryError.validationFailed
        #endif
    }

    @discardableResult
    static func purgeDemoData(context: ModelContext) throws -> Bool {
        let users = try context.fetch(FetchDescriptor<UserEntity>())
        // Treat both classic seeded users and the newer "rich" demo
        // dataset as demo. On a schema/seed bump both are wiped so the
        // generator can lay them out again with the latest shape.
        let demoUserIds = Set(users.filter { isDemoUser($0) || $0.id.hasPrefix("rich-user-") }.map(\.id))

        let posts = try context.fetch(FetchDescriptor<PostEntity>())
        var demoPostIds = Set(posts.filter { post in
            post.id.hasPrefix("seed-post-")
            || demoUserIds.contains(post.authorId)
        }.map(\.id))

        var foundLinkedRepost = true
        while foundLinkedRepost {
            foundLinkedRepost = false
            for post in posts {
                guard let originalId = post.repostOfPostId,
                      demoPostIds.contains(originalId),
                      !demoPostIds.contains(post.id)
                else { continue }
                demoPostIds.insert(post.id)
                foundLinkedRepost = true
            }
        }

        let comments = try context.fetch(FetchDescriptor<CommentEntity>())
        var demoCommentIds = Set(comments.filter { comment in
            comment.id.hasPrefix("seed-comment-")
            || demoPostIds.contains(comment.postId)
            || demoUserIds.contains(comment.authorId)
        }.map(\.id))

        var foundLinkedReply = true
        while foundLinkedReply {
            foundLinkedReply = false
            for comment in comments {
                guard let parentId = comment.parentCommentId,
                      demoCommentIds.contains(parentId),
                      !demoCommentIds.contains(comment.id)
                else { continue }
                demoCommentIds.insert(comment.id)
                foundLinkedReply = true
            }
        }

        let threads = try context.fetch(FetchDescriptor<MessageThreadEntity>())
        let demoThreadIds = Set(threads.filter { thread in
            thread.id.hasPrefix("seed-thread-")
            || thread.id.hasPrefix("starter-thread-")
            || thread.participantIds.contains(where: demoUserIds.contains)
        }.map(\.id))

        let messages = try context.fetch(FetchDescriptor<MessageEntity>())
        let demoMessageIds = Set(messages.filter { message in
            message.id.hasPrefix("seed-message-")
            || message.id.hasPrefix("starter-message-")
            || demoThreadIds.contains(message.threadId)
            || demoUserIds.contains(message.senderId)
        }.map(\.id))

        let media = try context.fetch(FetchDescriptor<MediaEntity>())
        let demoMedia = media.filter { item in
            demoPostIds.contains(item.postId)
            || demoMessageIds.contains(item.postId)
        }

        let notifications = try context.fetch(FetchDescriptor<NotificationEntity>())
        let demoNotifications = notifications.filter { notification in
            notification.id.hasPrefix("seed-notification-")
            || demoUserIds.contains(notification.actorId)
            || notification.targetPostId.map(demoPostIds.contains) == true
            || notification.targetCommentId.map(demoCommentIds.contains) == true
        }

        let follows = try context.fetch(FetchDescriptor<FollowEntity>())
        let demoFollows = follows.filter { follow in
            demoUserIds.contains(follow.followerId)
            || demoUserIds.contains(follow.followingId)
        }

        let topics = try context.fetch(FetchDescriptor<TopicEntity>())
        let hasDemoTopics = topics.contains { demoTopicNames.contains($0.name.normalizedTopicName) }

        let demoPosts = posts.filter { demoPostIds.contains($0.id) }
        let demoComments = comments.filter { demoCommentIds.contains($0.id) }
        let demoThreads = threads.filter { demoThreadIds.contains($0.id) }
        let demoMessages = messages.filter { demoMessageIds.contains($0.id) }
        let demoUsers = users.filter { demoUserIds.contains($0.id) }

        let didChange = !demoUsers.isEmpty
            || !demoPosts.isEmpty
            || !demoComments.isEmpty
            || !demoMedia.isEmpty
            || !demoNotifications.isEmpty
            || !demoThreads.isEmpty
            || !demoMessages.isEmpty
            || !demoFollows.isEmpty
            || hasDemoTopics

        guard didChange else { return false }

        demoNotifications.forEach(context.delete)
        demoMedia.forEach(context.delete)
        demoComments.forEach(context.delete)
        demoMessages.forEach(context.delete)
        demoThreads.forEach(context.delete)
        demoFollows.forEach(context.delete)
        demoPosts.forEach(context.delete)
        demoUsers.forEach(context.delete)
        try rebuildTopicTable(context: context)

        if let metadata = try context.fetch(FetchDescriptor<DatabaseMetadataEntity>()).first {
            metadata.seedVersion = KaiXConfig.seedVersion
        }
        try context.save()
        return true
    }

    private static func isDemoUser(_ user: UserEntity) -> Bool {
        demoUserIds.contains(user.id)
        || demoUsernames.contains(user.username.normalizedUsername)
    }

    private static let demoUserIds: Set<String> = [
        "user-kaix",
        "user-swift",
        "user-product",
        "user-city",
        "user-ai",
        "user-life"
    ]

    private static let demoUsernames: Set<String> = [
        "kaizi",
        "swiftuilab",
        "productdaily",
        "citylive",
        "aiproductwatch",
        "tokyolife",
        "tokyo_daily",
        "japan_now",
        "culture_tokyo",
        "campusjp",
        "foodwalk",
        "metro_watch",
        "market_brief",
        "weekendjp",
        "konbini_lab",
        "rent_tokyo",
        "visa_helper",
        "eventline",
        "weather_room",
        "job_board_jp",
        "startup_jp",
        "design_ops",
        "local_voice",
        "osaka_life",
        "kyoto_walk",
        "fukuoka_now",
        "ai_productwatch",
        "mobile_dev_jp",
        "photo_tokyo",
        "community_rules"
    ]

    private static let demoTopicNames: Set<String> = [
        "kaix",
        "swiftdata",
        "swiftui",
        "ios架构",
        "产品设计",
        "产品观察",
        "热榜",
        "搜索",
        "话题",
        "repository",
        "媒体处理",
        "性能优化",
        "热度算法",
        "数据流",
        "ai产品",
        "agent",
        "移动开发",
        "东京生活",
        "东京交通",
        "东京美食",
        "东京新闻",
        "日本生活",
        "本地活动",
        "社区公告",
        "城市观察",
        "生活小技巧",
        "搬家",
        "交通",
        "美食",
        "活动",
        "留学",
        "新闻",
        "租房",
        "便利店",
        "便利店新品",
        "咖啡店",
        "周末",
        "展览",
        "市集",
        "电车延误",
        "天气",
        "签证",
        "兼职",
        "求职",
        "日语学习",
        "旅行",
        "京都",
        "大阪",
        "福冈",
        "赏花",
        "夜间经济",
        "购物",
        "药妆",
        "银行卡",
        "手机合约"
    ].map { $0.normalizedTopicName }.reduce(into: Set<String>()) { $0.insert($1) }

    private static func migrateMetadataIfNeeded(context: ModelContext) throws {
        let metadata = try context.fetch(FetchDescriptor<DatabaseMetadataEntity>()).first
        if let metadata {
            if metadata.schemaVersion < KaiXConfig.schemaVersion {
                metadata.schemaVersion = KaiXConfig.schemaVersion
                metadata.lastMigrationAt = .now
            }
            return
        }

        context.insert(DatabaseMetadataEntity(
            schemaVersion: KaiXConfig.schemaVersion,
            seedVersion: 0
        ))
        try context.save()
    }

    private static func rebuildTopicTable(context: ModelContext) throws {
        let topics = try context.fetch(FetchDescriptor<TopicEntity>())
        topics.forEach(context.delete)
        let posts = try context.fetch(FetchDescriptor<PostEntity>())
        let grouped = Dictionary(grouping: posts.flatMap { post in
            post.hashtags.map { ($0, post.heatScore) }
        }, by: { $0.0 })

        for (name, values) in grouped {
            let heat = values.reduce(0) { $0 + $1.1 }
            context.insert(TopicEntity(name: name, postCount: values.count, heatScore: heat))
        }
    }

    private static func ensureTopicTableExists(context: ModelContext) throws {
        var descriptor = FetchDescriptor<TopicEntity>()
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        let posts = try context.fetch(FetchDescriptor<PostEntity>())
        guard posts.contains(where: { !$0.hashtags.isEmpty }) else { return }
        try rebuildTopicTable(context: context)
        try context.save()
    }
}
