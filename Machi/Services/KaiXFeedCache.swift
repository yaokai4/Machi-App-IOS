import Foundation

/// Best-effort on-disk snapshot of the last feed page, so a cold launch with no
/// network can still show the most recent content instead of a blank screen.
///
/// This is **not** the app's data store — the production server remains the
/// single source of truth. It is a small, silently-failing JSON snapshot in the
/// Caches directory (which iOS may purge under disk pressure), capped in size
/// and age. It can never get the app into a "recovery" state: if the file is
/// missing, stale or unreadable, callers simply get an empty array and fall
/// back to the live server.
enum KaiXFeedCache {
    private static let maxAge: TimeInterval = 60 * 60 * 24 * 3   // 3 days
    private static let maxItems = 40

    private struct Snapshot: Codable {
        let savedAt: Date
        let items: [KaiXPostDTO]
    }

    private static func fileURL(for key: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent("KaiXFeedCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeKey = String(key.map { char in
            char.isLetter || char.isNumber || char == "-" || char == "_" ? char : "_"
        })
        return folder.appendingPathComponent("feed-\(safeKey).json")
    }

    /// Persist the latest page for a feed. No-op on empty input or any failure.
    ///
    /// The blocking disk write is handed to a background task so it never
    /// stalls the main actor: under the project's main-actor-by-default
    /// isolation this static call runs on the main thread, and `save` fires on
    /// every successful first-page load (cold start, pull-to-refresh, region /
    /// language change). Encoding stays inline (cheap, ~40 small DTOs); only the
    /// `Data` + `URL` (both Sendable) cross into the detached writer.
    static func save(_ items: [KaiXPostDTO], key: String) {
        guard !items.isEmpty, let url = fileURL(for: key) else { return }
        let snapshot = Snapshot(savedAt: .now, items: Array(items.prefix(maxItems)))
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Load the cached page if present and not older than `maxAge`. Returns an
    /// empty array on any miss so callers can treat it as "no cache".
    static func load(key: String) -> [KaiXPostDTO] {
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) < maxAge else { return [] }
        return snapshot.items
    }
}
