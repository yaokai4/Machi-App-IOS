import XCTest
@testable import Machi

/// End-to-end smoke tests for `KaiXAPIClient`. Requires the unified
/// backend (`web/server.py`) to be running at the default URL
/// (`http://127.0.0.1:8787`). The tests are guarded so they soft-skip
/// when the backend is unreachable, keeping CI green when the local
/// server isn't booted.
@MainActor
final class KaiXAPIClientTests: XCTestCase {
    func testLoginThenFeedThenLogout() async throws {
        guard await backendReachable() else {
            throw XCTSkip("Unified backend not reachable at \(KaiXBackend.baseURL.absoluteString)")
        }
        let client = KaiXAPIClient.shared

        let login = try await client.login(handle: "kaizi", password: "123456")
        XCTAssertEqual(login.user.handle, "kaizi")
        XCTAssertNotNil(KaiXBackend.token)

        let me = try await client.me()
        XCTAssertEqual(me.handle, login.user.handle)

        let feed = try await client.feed(mode: .recommend)
        XCTAssertFalse(feed.items.isEmpty)
        XCTAssertEqual(feed.mode, "recommend")

        try await client.logout()
        XCTAssertNil(KaiXBackend.token)
    }

    func testCreateLikeDeletePost() async throws {
        guard await backendReachable() else {
            throw XCTSkip("Unified backend not reachable at \(KaiXBackend.baseURL.absoluteString)")
        }
        let client = KaiXAPIClient.shared
        _ = try await client.login(handle: "kaizi", password: "123456")

        let created = try await client.createPost(content: "iOS smoke test #UnitTest")
        XCTAssertEqual(created.author.unsafelyUnwrapped.handle, "kaizi")
        XCTAssertEqual(created.tags, ["unittest"])

        let liked = try await client.setLike(created.id, true)
        XCTAssertTrue(liked.liked)
        XCTAssertEqual(liked.like_count, 1)

        let unliked = try await client.setLike(created.id, false)
        XCTAssertFalse(unliked.liked)
        XCTAssertEqual(unliked.like_count, 0)

        try await client.deletePost(created.id)

        do {
            _ = try await client.post(created.id)
            XCTFail("Expected the deleted post to 404")
        } catch is KaiXAPIError {
            // expected
        }
    }

    private func backendReachable() async -> Bool {
        guard shouldRunBackendSmokeTests else { return false }
        var req = URLRequest(url: KaiXBackend.baseURL.appendingPathComponent("/api/trending"))
        req.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode != nil
        } catch {
            return false
        }
    }

    private var shouldRunBackendSmokeTests: Bool {
        if ProcessInfo.processInfo.environment["KAIX_RUN_BACKEND_SMOKE_TESTS"] == "1" {
            return true
        }
        let host = KaiXBackend.baseURL.host?.lowercased() ?? ""
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
