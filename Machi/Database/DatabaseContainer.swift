import Foundation
import os
import SwiftData

enum KaiXDatabaseContainer {
    private static let logger = Logger(subsystem: "com.yaokai.kaizi", category: "Database")

    /// 设计决策(与现实一致,勿再写成"微信式离线缓存"):**生产不把业务数据写进
    /// 这个磁盘 Store**。帖子/会话/聊天记录/资料一律由 `KaiXAPIClient` 直出、驻
    /// 内存,服务器是唯一真相(ec4472a"服务器唯一真相不落盘")。发布版里会落到
    /// 这个 Store 的只有游客占位行等非业务骨架;真正写库的通路
    /// (RemoteSyncService / DatabaseSeeder)全部 `#if DEBUG` 门控,只服务本地
    /// 夹具与 UI 测试。老版本升级残留的历史数据由登出/切号时的
    /// `requestLocalDataWipe()` 兜底清除(见 ContentView.resetPerAccountState)。
    ///
    /// Robustness (so the old "数据库恢复模式 / 本地数据库需要恢复" state can never
    /// surface): if the on-disk store is unreadable — corruption or a failed
    /// migration — we silently wipe it and start fresh; if even that fails we
    /// fall back to an in-memory store so the app always launches. No recovery
    /// banner is ever shown, and the user can clear this cache from 设置 ▸ 数据管理.
    /// 这些保护在生产守的是"空壳 + 残留",看似小题大做,但换来的是启动永不被
    /// 一个坏 SQLite 文件卡死——保留。
    static let shared: ModelContainer = {
        KXPerf.event("app.launch")
        let schema = Schema(KaiXSchemaV5.models)
        DatabaseRecoveryNoticeStore.clear()
        // Honor a user-requested "清除本地数据" from 设置 ▸ 数据管理: wipe the store
        // before it is opened (safe — the container is not live yet).
        if UserDefaults.standard.bool(forKey: pendingWipeKey) {
            wipeStore()
            UserDefaults.standard.removeObject(forKey: pendingWipeKey)
        }
        return KXPerf.measureSync("database.ready") {
            makeContainer(schema: schema)
        }
    }()

    static let models: [any PersistentModel.Type] = KaiXSchemaV5.models

    private static let pendingWipeKey = "kaix.pendingLocalDataWipe"

    /// Folder holding the on-disk cache — sized and shown by 设置 ▸ 数据管理.
    static var storeFolderURL: URL { storeURL.deletingLastPathComponent() }

    /// Request a full local-data wipe (帖子 / 聊天记录 / 页面数据). Applied on the next
    /// launch so we never delete a SQLite file the live container still holds open.
    static func requestLocalDataWipe() {
        UserDefaults.standard.set(true, forKey: pendingWipeKey)
    }

    /// Dedicated folder so the cache can be located, wiped and (later) cleared
    /// independently of any store left by older builds.
    private static var storeURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "KaiXLocalStore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Encrypt the store at rest. 生产虽不写 DM 正文进库(见上),但 DEBUG 夹具
        // 会写、老版本可能残留过——按"可能含 DM 正文"的最坏情况加密不吃亏。
        // Complete-until-first-unlock matches the session token's accessibility:
        // unreadable on a locked device that has never been unlocked since boot,
        // yet still available for background refresh after the first unlock.
        // Applied to the folder so the .store / -wal / -shm files inherit it.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: dir.path
        )
        return dir.appending(path: "KaiXLocal.store")
    }

    private static func makeContainer(schema: Schema) -> ModelContainer {
        // 1) Persistent on-disk store (with migrations).
        if let container = try? makePersistentContainer(schema: schema) {
            logger.info("local persistence: on-disk container ready")
            return container
        }
        // 2) Unreadable store -> wipe and rebuild fresh. Silent, no banner.
        logger.error("on-disk store unreadable; wiping and rebuilding")
        wipeStore()
        if let container = try? makePersistentContainer(schema: schema) {
            logger.info("local persistence: on-disk container rebuilt after wipe")
            return container
        }
        // 3) Last resort: in-memory, so the app still launches.
        logger.error("on-disk rebuild failed; falling back to in-memory cache")
        let fallback = ModelConfiguration(
            "KaiXInMemoryFallback",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        if let container = try? ModelContainer(for: schema, configurations: [fallback]) {
            return container
        }
        fatalError("Unable to create any SwiftData container")
    }

    private static func makePersistentContainer(schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: KaiXMigrationPlan.self, configurations: [configuration])
    }

    /// Remove the whole store folder (db + -wal + -shm) so a corrupt cache can't
    /// brick launch. The next `makePersistentContainer` recreates it fresh.
    private static func wipeStore() {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }
}
