import CryptoKit
import Foundation

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
