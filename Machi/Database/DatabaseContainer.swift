import Foundation
import os
import SwiftData

enum KaiXDatabaseContainer {
    private static let logger = Logger(subsystem: "com.yaokai.kaizi", category: "Database")

    /// The app keeps **no persistent local database**. The production server is
    /// the single source of truth; SwiftData runs purely in-memory as a
    /// per-session cache populated entirely from the server. Nothing is written
    /// to disk, so there is no SQLite store to corrupt or migrate and the
    /// "数据库恢复模式 / 本地数据库需要恢复" state can never occur. Any recovery notice
    /// left behind by older builds is cleared on launch.
    static let shared: ModelContainer = {
        let schema = Schema(KaiXSchemaV5.models)
        DatabaseRecoveryNoticeStore.clear()
        do {
            logger.info("local persistence disabled: in-memory container backed by production data")
            return try makeEphemeralContainer(schema: schema)
        } catch {
            fatalError("Unable to create in-memory SwiftData container: \(error.localizedDescription)")
        }
    }()

    static let models: [any PersistentModel.Type] = KaiXSchemaV5.models

    private static func makeEphemeralContainer(schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "KaiXInMemory",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: KaiXMigrationPlan.self, configurations: [configuration])
    }
}
