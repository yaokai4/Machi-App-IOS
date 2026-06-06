import Foundation
import os
import SwiftData

enum KaiXDatabaseContainer {
    private static let primaryStoreName = "KaiXLocalDatabaseV2"
    private static let recoveryStoreName = "KaiXLocalDatabaseRecoveryV5"
    private static let storeDirectoryName = "KaiXStores"
    private static let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none
    private static let logger = Logger(subsystem: "com.yaokai.kaizi", category: "Database")

    static let shared: ModelContainer = {
        let schema = Schema(KaiXSchemaV5.models)

        if isRunningUnitTests {
            do {
                return try makeEphemeralContainer(schema: schema)
            } catch {
                fatalError("Unable to create in-memory SwiftData test container: \(error.localizedDescription)")
            }
        }

        DatabaseRecoveryNoticeStore.clear()

        do {
            let container = try makeContainer(schema: schema, name: primaryStoreName)
            logger.info("recovery success: primary store opened")
            return container
        } catch {
            let primaryError = error
            logger.error("primary store failed: \(primaryError.kaixTechnicalSummary, privacy: .public)")

            do {
                let container = try makeContainer(schema: schema, name: primaryStoreName, migrationPlan: nil)
                logger.info("recovery success: primary store opened with lightweight migration")
                return container
            } catch {
                let migrationError = error
                logger.error("migration failed: \(migrationError.kaixTechnicalSummary, privacy: .public)")

                do {
                    try archiveStore(named: primaryStoreName, reason: "primary-failed")
                    let container = try makeContainer(schema: schema, name: primaryStoreName)
                    saveDebugNotice(DatabaseRecoveryNotice(
                        mode: .rebuiltPrimary,
                        userMessage: "本地数据库已自动修复。",
                        technicalDetails: """
                        Primary: \(primaryError.kaixTechnicalSummary)
                        Migration: \(migrationError.kaixTechnicalSummary)
                        """,
                        occurredAt: .now
                    ))
                    logger.info("recovery success: primary store rebuilt after backup")
                    return container
                } catch {
                    let rebuildError = error
                    logger.error("rebuild failed: \(rebuildError.kaixTechnicalSummary, privacy: .public)")

                    saveDebugNotice(DatabaseRecoveryNotice(
                        mode: .recovery,
                        userMessage: "本地数据库暂时使用安全恢复模式，原数据已备份。",
                        technicalDetails: """
                        Primary: \(primaryError.kaixTechnicalSummary)
                        Migration: \(migrationError.kaixTechnicalSummary)
                        Rebuild: \(rebuildError.kaixTechnicalSummary)
                        """,
                        occurredAt: .now
                    ))
                }
            }

            do {
                let container = try makeContainer(schema: schema, name: recoveryStoreName)
                logger.info("recovery success: fallback recovery store opened")
                return container
            } catch {
                let recoveryError = error
                logger.error("recovery store failed: \(recoveryError.kaixTechnicalSummary, privacy: .public)")
                saveDebugNotice(DatabaseRecoveryNotice(
                    mode: .ephemeral,
                    userMessage: "本地数据库暂时不可用，当前使用临时会话。",
                    technicalDetails: """
                    Primary: \(primaryError.kaixTechnicalSummary)
                    Recovery: \(recoveryError.kaixTechnicalSummary)
                    """,
                    occurredAt: .now
                ))

                do {
                    let container = try makeEphemeralContainer(schema: schema)
                    logger.info("recovery success: ephemeral in-memory store opened")
                    return container
                } catch {
                    fatalError("Unable to create emergency in-memory SwiftData container: \(error.localizedDescription)")
                }
            }
        }
    }()

    private static func makeContainer(
        schema: Schema,
        name: String,
        migrationPlan: (any SchemaMigrationPlan.Type)? = nil
    ) throws -> ModelContainer {
        try copyLegacyStoreIfNeeded(named: name)
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            url: try storeURL(named: name),
            allowsSave: true,
            cloudKitDatabase: cloudKitDatabase
        )
        return try ModelContainer(for: schema, migrationPlan: migrationPlan, configurations: [configuration])
    }

    private static func makeEphemeralContainer(schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "KaiXUnitTests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, migrationPlan: KaiXMigrationPlan.self, configurations: [configuration])
    }

    static let models: [any PersistentModel.Type] = KaiXSchemaV5.models

    private static var isRunningUnitTests: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("-kaixUITestEphemeralStore") ||
            processInfo.environment["KAIX_UI_TEST_EPHEMERAL_STORE"] == "1" ||
            processInfo.environment["XCTestConfigurationFilePath"] != nil ||
            processInfo.environment["XCTestBundlePath"] != nil ||
            NSClassFromString("XCTestCase") != nil {
            return true
        }

        guard let plugInsURL = Bundle.main.builtInPlugInsURL,
              let plugIns = try? FileManager.default.contentsOfDirectory(
                at: plugInsURL,
                includingPropertiesForKeys: nil
              ) else {
            return false
        }

        return plugIns.contains { $0.pathExtension == "xctest" }
    }

    private static func saveDebugNotice(_ notice: DatabaseRecoveryNotice) {
        #if DEBUG
        DatabaseRecoveryNoticeStore.save(notice)
        #else
        _ = notice
        #endif
    }

    private static func archiveStore(named name: String, reason: String) throws {
        let fileManager = FileManager.default
        let directory = try storeDirectory()
        let backupDirectory = directory.appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        var movedFiles = 0
        for url in try archiveCandidates(named: name) where fileManager.fileExists(atPath: url.path) {
            let target = backupDirectory.appendingPathComponent("\(timestamp)-\(reason)-\(url.lastPathComponent)")
            try? fileManager.removeItem(at: target)
            try fileManager.moveItem(at: url, to: target)
            movedFiles += 1
        }
        logger.info("primary store backup completed: \(movedFiles) files moved for \(name, privacy: .public)")
    }

    private static func copyLegacyStoreIfNeeded(named name: String) throws {
        let fileManager = FileManager.default
        let destinationURL = try storeURL(named: name)
        guard !fileManager.fileExists(atPath: destinationURL.path) else { return }

        let legacyDirectory = try applicationSupportDirectory()
        let explicitDirectory = try storeDirectory()
        guard legacyDirectory.path != explicitDirectory.path else { return }

        var copiedFiles = 0
        for legacyURL in candidateStoreFiles(named: name, in: legacyDirectory) where fileManager.fileExists(atPath: legacyURL.path) {
            let target = explicitDirectory.appendingPathComponent(legacyURL.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try fileManager.copyItem(at: legacyURL, to: target)
            copiedFiles += 1
        }

        if copiedFiles > 0 {
            logger.info("copied legacy SwiftData store into managed store directory: \(copiedFiles) files")
        }
    }

    private static func candidateStoreFiles(named name: String, in directory: URL) -> [URL] {
        let sqliteNames = [
            "\(name).store",
            "\(name).store-shm",
            "\(name).store-wal",
            "\(name).sqlite",
            "\(name).sqlite-shm",
            "\(name).sqlite-wal"
        ]
        return sqliteNames.map { directory.appendingPathComponent($0) }
    }

    private static func archiveCandidates(named name: String) throws -> [URL] {
        try candidateStoreFiles(named: name, in: storeDirectory()) +
        candidateStoreFiles(named: name, in: applicationSupportDirectory())
    }

    private static func storeURL(named name: String) throws -> URL {
        try storeDirectory().appendingPathComponent("\(name).store")
    }

    private static func storeDirectory() throws -> URL {
        let directory = try applicationSupportDirectory().appendingPathComponent(storeDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func applicationSupportDirectory() throws -> URL {
        let fileManager = FileManager.default
        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
}

private extension Error {
    var kaixTechnicalSummary: String {
        "\(type(of: self)): \(localizedDescription)"
    }
}
