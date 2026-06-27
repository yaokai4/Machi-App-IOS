import Combine
import Foundation

/// Aggregates the app's on-device storage for Settings ▸ 数据管理: reports how
/// much space each cache uses and clears it on demand. Everything here is a
/// rebuildable cache — the production server stays the single source of truth —
/// so clearing just means content re-loads/syncs on the next launch.
@MainActor
final class KaiXCacheManager: ObservableObject {
    static let shared = KaiXCacheManager()

    /// Downloaded images + videos (posts, avatars, chat media…).
    @Published private(set) var mediaBytes: Int64 = 0
    /// Cached page/feed snapshots + crash diagnostics.
    @Published private(set) var dataBytes: Int64 = 0
    /// The local database (帖子 / 会话 / 聊天记录 / 资料) — WeChat-style offline cache.
    @Published private(set) var dbBytes: Int64 = 0
    @Published private(set) var isWorking = false
    /// Set after the user clears local data: the DB wipe takes effect on restart.
    @Published private(set) var localDataWipeScheduled = false

    var totalBytes: Int64 { mediaBytes + dataBytes + dbBytes }

    private static let mediaFolders = ["KaiXImageCache"]
    private static let dataFolders = ["KaiXFeedCache", "KaiXSnapshotCache", "Diagnostics"]

    func refresh() async {
        let dbURL = KaiXDatabaseContainer.storeFolderURL
        let sizes = await Task.detached(priority: .utility) {
            (media: Self.size(ofCachesFolders: Self.mediaFolders),
             data: Self.size(ofCachesFolders: Self.dataFolders),
             db: Self.folderSize(dbURL))
        }.value
        mediaBytes = sizes.media
        dataBytes = sizes.data
        dbBytes = sizes.db
    }

    /// Clear downloaded images/videos (usually the biggest cache).
    func clearMedia() async {
        isWorking = true
        await ImageCacheService.shared.clear()
        await refresh()
        isWorking = false
    }

    /// Clear cached page/feed snapshots + diagnostics (does not touch chat).
    func clearData() async {
        isWorking = true
        KaiXFeedCache.clearAll()
        KaiXSnapshotCache.clearAll()
        Self.clearCachesFolder("Diagnostics")
        await refresh()
        isWorking = false
    }

    /// Clear the local database — 帖子 / 会话 / **聊天记录** / 资料. Applied on the next
    /// launch (we never delete a SQLite file the live store still holds open), so
    /// the UI marks it "restart to fully clear".
    func clearLocalData() {
        KaiXDatabaseContainer.requestLocalDataWipe()
        localDataWipeScheduled = true
    }

    /// Clear everything: media + snapshots now, local DB on next launch.
    func clearAll() async {
        isWorking = true
        await ImageCacheService.shared.clear()
        KaiXFeedCache.clearAll()
        KaiXSnapshotCache.clearAll()
        Self.clearCachesFolder("Diagnostics")
        KaiXDatabaseContainer.requestLocalDataWipe()
        localDataWipeScheduled = true
        await refresh()
        isWorking = false
    }

    static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    nonisolated private static func cachesURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private static func clearCachesFolder(_ name: String) {
        guard let dir = cachesURL()?.appendingPathComponent(name, isDirectory: true) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    nonisolated private static func size(ofCachesFolders folders: [String]) -> Int64 {
        guard let caches = cachesURL() else { return 0 }
        return folders.reduce(0) { $0 + folderSize(caches.appendingPathComponent($1, isDirectory: true)) }
    }

    nonisolated private static func folderSize(_ dir: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
