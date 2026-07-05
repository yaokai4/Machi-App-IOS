import CryptoKit
import Foundation

/// ⚠️ DEBUG / test-only. This is a demo-grade hasher (unsalted SHA-256, with a
/// plaintext-equality fallback in `verify`) reached ONLY through the local-store
/// fallback auth path, which is compiled out in Release
/// (`KaiXRuntimeFlags.allowLocalStoreFallback` is false there — production auth
/// is entirely server-side). Do NOT wire this into any Release code path: if
/// local authentication ever ships, replace it with a per-user-salted slow hash
/// (PBKDF2/scrypt) and delete the plaintext fallback below first.
enum PasswordHasher {
    private static let prefix = "v1$sha256$"
    private static let namespace = "KaiX.password.v1"

    static func hash(_ password: String) -> String {
        let data = Data("\(namespace):\(password)".utf8)
        let digest = SHA256.hash(data: data)
        return prefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    static func verify(_ password: String, storedHash: String) -> Bool {
        if storedHash.hasPrefix(prefix) {
            return hash(password) == storedHash
        }

        return storedHash == password
    }

    static func needsUpgrade(_ storedHash: String) -> Bool {
        !storedHash.hasPrefix(prefix)
    }
}
