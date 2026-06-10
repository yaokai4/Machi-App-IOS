import Foundation
import SwiftData
import Testing
@testable import Machi

/// Regression guard for the home-feed "looping posts" bug: paging used
/// overlapping SQL windows (over-fetch 2x, keep the best half), so the same
/// post could be served by consecutive pages. These tests pin the invariant
/// that pages are disjoint and exhaustive for every timeline mode.
@MainActor
struct FeedPaginationTests {
    private let pageSize = 10

    @Test func recommendPagesAreDisjointAndCoverEveryPost() async throws {
        let context = try makeContext()
        let total = 35
        seedPosts(count: total, context: context)
        try context.save()

        let repository = PostRepository(context: context)
        var seen = Set<String>()
        var page = 0
        var fetchedTotal = 0
        while true {
            let posts = try await repository.fetchPage(mode: .recommend, currentUserId: "viewer", page: page, pageSize: pageSize)
            if posts.isEmpty { break }
            for post in posts {
                #expect(seen.insert(post.id).inserted, "post \(post.id) appeared on more than one page (page \(page))")
            }
            fetchedTotal += posts.count
            page += 1
            #expect(page < 20, "runaway pagination")
            if posts.count < pageSize { break }
        }
        #expect(fetchedTotal == total, "pagination must surface every post exactly once (got \(fetchedTotal)/\(total))")
    }

    @Test func hotPagesAreDisjoint() async throws {
        let context = try makeContext()
        seedPosts(count: 25, context: context)
        try context.save()

        let repository = PostRepository(context: context)
        let first = try await repository.fetchPage(mode: .hot, currentUserId: "viewer", page: 0, pageSize: pageSize)
        let second = try await repository.fetchPage(mode: .hot, currentUserId: "viewer", page: 1, pageSize: pageSize)
        let overlap = Set(first.map(\.id)).intersection(Set(second.map(\.id)))
        #expect(overlap.isEmpty, "hot pages overlap: \(overlap)")
    }

    @Test func notificationMirrorUpsertsOnceAndReportsFreshness() async throws {
        let context = try makeContext()
        let sync = RemoteSyncService.shared
        let dto = KaiXNotificationDTO(
            id: "server-notif-1",
            type: "like",
            actor_id: "actor-1",
            user_id: "me",
            target_post_id: "server-post-9",
            target_comment_id: nil,
            target_conversation_id: nil,
            content: "喜欢了你的帖子",
            is_read: false,
            created_at: "2026-06-10T03:00:00+00:00",
            actor: nil
        )

        let (first, isNewFirst) = sync.upsertNotification(dto, context: context)
        #expect(isNewFirst, "first sight of a server notification must report as new")
        #expect(first.remoteId == "server-notif-1")
        #expect(first.type == .like)
        #expect(!first.isRead)

        let (second, isNewSecond) = sync.upsertNotification(dto, context: context)
        #expect(!isNewSecond, "re-syncing the same server notification must not report as new again")
        #expect(second.id == first.id)

        let all = try context.fetch(FetchDescriptor<NotificationEntity>())
        #expect(all.count == 1, "mirror must never duplicate a server notification")
    }

    // MARK: - helpers

    private func seedPosts(count: Int, context: ModelContext) {
        // Hermetic against host-app state: the repository's recommend/hot
        // paths filter by the persisted browse region (UserDefaults) and by
        // a rolling 10-day window. Seed posts that match whatever region
        // the environment has, with recent timestamps, so the invariants
        // are exercised on real rows instead of passing vacuously on [].
        let country = RegionStore.shared.current?.countryCode ?? ""
        let base = Date().addingTimeInterval(-Double(count + 1) * 60)
        for index in 0..<count {
            let post = PostEntity(
                id: "post-\(index)",
                authorId: "author-\(index % 5)",
                content: "Post number \(index)",
                createdAt: base.addingTimeInterval(Double(index) * 60),
                likeCount: index % 7,
                heatScore: Double(index % 11),
                status: .published
            )
            post.country = country
            context.insert(post)
        }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(KaiXDatabaseContainer.models)
        // SQLite-backed temp store, NOT in-memory: production uses the
        // SQLite engine, and in-memory stores have shown unstable
        // fetchOffset windows under custom sort descriptors — the very
        // behavior these tests exist to pin down.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("KaiXFeedTests-\(UUID().uuidString).store")
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
