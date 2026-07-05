import Foundation
import Security

/// Minimal Keychain wrapper for the KaiX bearer token.
///
/// Why this exists: the token used to live in `UserDefaults`, which
/// writes plaintext to a plist in the app sandbox. That file is
/// included in unencrypted device backups and is readable by anyone
/// who can mount the sandbox (jailbroken devices, leaked backups,
/// some MDM debugging tools). Moving it into the Keychain — with
/// `AfterFirstUnlockThisDeviceOnly` accessibility (see `write`) — both
/// encrypts it at rest and prevents it from migrating to a new device via
/// iCloud / encrypted backups. AfterFirstUnlock (not WhenUnlocked) is used so
/// background refresh / notification handling can still read the session token
/// while the device is locked, after the first post-boot unlock.
///
/// API mirrors a tiny KV store so `KaiXBackend` can swap in without
/// touching any call sites.
enum KaiXTokenStore {
    private static let service = "com.yaokai.kaizi.session"
    private static let account = "bearer"
    private static let legacyDefaultsKey = "kaix.token"
    private static let migrationDoneKey = "kaix.token.migrated"

    // Process-in-memory cache so the hot path (every request builds an
    // Authorization header, and the 401 branch re-reads) doesn't issue a
    // synchronous SecItemCopyMatching each time — DM polling + feed paging
    // hammered the Keychain. Guarded by a lock (read/write happen off the main
    // thread). Outer optional = "loaded"; inner = the token (nil = no token).
    // Correctness holds because every mutation routes through write()/delete().
    private static let cacheLock = NSLock()
    private static var cachedToken: String??

    static func read() -> String? {
        cacheLock.lock()
        if let loaded = cachedToken {
            cacheLock.unlock()
            return loaded
        }
        cacheLock.unlock()

        migrateLegacyIfNeeded()
        let value = keychainRead()

        cacheLock.lock()
        // Don't clobber a token a concurrent write() just cached.
        if cachedToken == nil { cachedToken = .some(value) }
        let resolved = cachedToken ?? value
        cacheLock.unlock()
        return resolved
    }

    private static func keychainRead() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func write(_ token: String) {
        cacheLock.lock(); cachedToken = .some(token); cacheLock.unlock()
        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Try to update first so we don't accumulate duplicate items
        // when the token rotates.
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    static func delete() {
        cacheLock.lock(); cachedToken = .some(nil); cacheLock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Move any value still living in UserDefaults (left over from
    /// previous builds) into the Keychain on first launch of the new
    /// code. Runs at most once per install.
    private static func migrateLegacyIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationDoneKey) { return }
        defer { defaults.set(true, forKey: migrationDoneKey) }
        guard let legacy = defaults.string(forKey: legacyDefaultsKey), !legacy.isEmpty else { return }
        write(legacy)
        defaults.removeObject(forKey: legacyDefaultsKey)
    }
}
