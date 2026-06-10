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
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            context.insert(PostEntity(
                id: "post-\(index)",
                authorId: "author-\(index % 5)",
                content: "Post number \(index)",
                createdAt: base.addingTimeInterval(Double(index) * 60),
                likeCount: index % 7,
                heatScore: Double(index % 11),
                status: .published
            ))
        }
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(KaiXDatabaseContainer.models)
        let configuration = ModelConfiguration("KaiXFeedTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
