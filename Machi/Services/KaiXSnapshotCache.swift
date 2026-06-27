import Foundation

/// Generic best-effort on-disk snapshot cache — the sibling of `KaiXFeedCache`,
/// for any `Codable` screen payload (Guide home, notifications, a profile
/// bundle, …). The app's SwiftData store is **in-memory** (server stays the
/// single source of truth), so it does not survive app termination; this lets a
/// screen paint its last-seen content instantly on a cold launch instead of a
/// skeleton, then refresh from the live server.
///
/// Like `KaiXFeedCache` this is **not** a database: a purgeable, size/age-capped
/// JSON file in the Caches directory (iOS may evict it under disk pressure). Any
/// miss — missing, stale, or unreadable — returns `nil` so callers fall straight
/// back to the network. It can never put the app into a "recovery" state.
enum KaiXSnapshotCache {
    private static let defaultMaxAge: TimeInterval = 60 * 60 * 24 * 3   // 3 days
    private static let folderName = "KaiXSnapshotCache"

    private struct Envelope<T: Codable>: Codable {
        let savedAt: Date
        let value: T
    }

    private static func fileURL(for key: String) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeKey = String(key.map { char in
            char.isLetter || char.isNumber || char == "-" || char == "_" ? char : "_"
        })
        return folder.appendingPathComponent("\(safeKey).json")
    }

    /// Persist a snapshot. No-op on any failure; the disk write is detached so it
    /// never stalls the (main-actor) caller.
    static func save<T: Codable>(_ value: T, key: String) {
        guard let url = fileURL(for: key),
              let data = try? JSONEncoder().encode(Envelope(savedAt: .now, value: value)) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Load a snapshot if present and fresher than `maxAge`. Returns `nil` on any
    /// miss so callers treat it as "no cache" and fetch from the server.
    static func load<T: Codable>(_ type: T.Type, key: String, maxAge: TimeInterval = defaultMaxAge) -> T? {
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let env = try? JSONDecoder().decode(Envelope<T>.self, from: data),
              Date().timeIntervalSince(env.savedAt) < maxAge else { return nil }
        return env.value
    }

    /// Folder this cache lives in (used by the data-management screen).
    static var directory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Drop every page snapshot. Safe: screens just re-fetch from the server.
    static func clearAll() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
