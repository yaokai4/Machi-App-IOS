import CryptoKit
import Foundation
import Security

/// ⚠️ DEBUG / test-only. Reached ONLY through the local-store fallback auth
/// path, which is compiled out in Release (`KaiXRuntimeFlags.allowLocalStoreFallback`
/// is false there — production auth is entirely server-side). Do NOT wire this
/// into any Release code path.
///
/// Hardened from the earlier demo hasher: now per-hash **salted** (random 16-byte
/// salt embedded in the stored string) and the dangerous **plaintext-equality
/// fallback in `verify` has been removed** — a non-`v2$` stored value now simply
/// fails to verify instead of matching the raw password. (A single salted SHA-256
/// is still not a slow hash; if local authentication ever ships for real, upgrade
/// to PBKDF2/scrypt with a high iteration count.)
enum PasswordHasher {
    private static let prefix = "v2$sha256$"
    private static let namespace = "KaiX.password.v1"
    private static let saltBytes = 16

    /// `v2$sha256$<saltHex>$<digestHex>`, digest = SHA256(salt || namespace:password).
    static func hash(_ password: String) -> String {
        let salt = randomSalt()
        let digest = digest(password: password, salt: salt)
        return prefix + hex(salt) + "$" + hex(Data(digest))
    }

    static func verify(_ password: String, storedHash: String) -> Bool {
        // No plaintext fallback: anything not in the current salted format fails.
        guard storedHash.hasPrefix(prefix) else { return false }
        let body = storedHash.dropFirst(prefix.count)
        let parts = body.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let salt = data(fromHex: String(parts[0])),
              !salt.isEmpty else { return false }
        let expected = hex(Data(digest(password: password, salt: salt)))
        // Constant-time compare to avoid a timing side-channel on the hash.
        return constantTimeEquals(expected, String(parts[1]))
    }

    static func needsUpgrade(_ storedHash: String) -> Bool {
        !storedHash.hasPrefix(prefix)
    }

    // MARK: - helpers

    private static func digest(password: String, salt: Data) -> SHA256.Digest {
        SHA256.hash(data: salt + Data("\(namespace):\(password)".utf8))
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: saltBytes)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // Extremely unlikely; fail closed with a non-empty (but weaker) salt
            // rather than an empty one.
            bytes = Array("\(namespace):fallback-salt".utf8).prefix(saltBytes).map { $0 }
        }
        return Data(bytes)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func data(fromHex hexString: String) -> Data? {
        guard hexString.count % 2 == 0 else { return nil }
        var out = Data(capacity: hexString.count / 2)
        var idx = hexString.startIndex
        while idx < hexString.endIndex {
            let next = hexString.index(idx, offsetBy: 2)
            guard let byte = UInt8(hexString[idx..<next], radix: 16) else { return nil }
            out.append(byte)
            idx = next
        }
        return out
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        guard ab.count == bb.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }
}
