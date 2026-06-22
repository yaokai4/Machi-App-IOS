import Foundation
import CryptoKit

/// Best-effort on-disk snapshot of the Guide OS dashboard / todos / calendar, so
/// a cold launch or a network blip shows the last known plan instead of a blank
/// screen. Same contract as `KaiXFeedCache`: silently-failing JSON in the Caches
/// directory (which iOS may purge), age-capped, and **never authoritative** —
/// the production server stays the single source of truth.
///
/// Snapshots are namespaced by a stable hash of the current session token, so a
/// different account never reads another user's cached plan, and a logged-out
/// client (no token) reads nothing.
enum GuideOSCache {
    private static let maxAge: TimeInterval = 60 * 60 * 24 * 3   // 3 days

    private struct Snapshot<T: Codable>: Codable {
        let savedAt: Date
        let value: T
    }

    /// 8-byte hex of SHA256(token) — stable across launches, not the raw token.
    private static func userScope() -> String? {
        guard let token = KaiXBackend.token, !token.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func fileURL(for key: String) -> URL? {
        guard let scope = userScope(),
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent("GuideOSCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeKey = String(key.map { c in c.isLetter || c.isNumber || c == "-" || c == "_" ? c : "_" })
        return folder.appendingPathComponent("\(scope)-\(safeKey).json")
    }

    /// Persist a value for `key`. No-op on any failure or when logged out.
    static func save<T: Codable>(_ value: T, key: String) {
        guard let url = fileURL(for: key),
              let data = try? JSONEncoder().encode(Snapshot(savedAt: .now, value: value)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Load a cached value if present for the current user and not older than
    /// `maxAge`. Returns nil on any miss so callers fall back to the live server.
    static func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot<T>.self, from: data),
              Date().timeIntervalSince(snapshot.savedAt) < maxAge else { return nil }
        return snapshot.value
    }

    /// Drop every Guide snapshot (e.g. on logout). Silently ignores failure.
    static func clearAll() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: caches.appendingPathComponent("GuideOSCache", isDirectory: true))
    }
}
