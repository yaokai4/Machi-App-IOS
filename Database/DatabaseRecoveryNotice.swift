import Foundation

enum DatabaseStoreMode: String, Codable {
    case primary
    case rebuiltPrimary
    case recovery
    case ephemeral

    var isPersistentRecovery: Bool {
        switch self {
        case .recovery, .ephemeral:
            true
        case .primary, .rebuiltPrimary:
            false
        }
    }
}

struct DatabaseRecoveryNotice: Codable, Equatable {
    var mode: DatabaseStoreMode
    var userMessage: String
    var technicalDetails: String
    var occurredAt: Date

    var isRecovering: Bool {
        mode != .primary
    }

    var presentationKey: String {
        "\(mode.rawValue)-\(Int(occurredAt.timeIntervalSince1970))"
    }
}

enum DatabaseRecoveryNoticeStore {
    private static let key = "KaiXDatabaseRecoveryNotice"

    static func load() -> DatabaseRecoveryNotice? {
        #if DEBUG
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DatabaseRecoveryNotice.self, from: data)
        #else
        return nil
        #endif
    }

    static func save(_ notice: DatabaseRecoveryNotice) {
        #if DEBUG
        guard let data = try? JSONEncoder().encode(notice) else { return }
        UserDefaults.standard.set(data, forKey: key)
        #else
        _ = notice
        #endif
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
