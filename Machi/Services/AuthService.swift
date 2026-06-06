import Foundation
import SwiftData

@MainActor
final class AuthService {
    static let shared = AuthService()

    private let currentUserKey = "currentUserID"

    var currentUserId: String {
        UserDefaults.standard.string(forKey: currentUserKey) ?? ""
    }

    func persistSession(user: UserEntity) {
        UserDefaults.standard.set(user.id, forKey: currentUserKey)
        RegionStore.shared.applyUserRegion(user)
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: currentUserKey)
        // Drop the unified-backend token too so the next login starts clean.
        KaiXBackend.token = nil
        // Region selection is per-account context: clearing it on
        // logout avoids account A's last city showing up as account
        // B's default after a switch.
        RegionStore.shared.reset()
    }

    func switchAccount(to user: UserEntity) {
        persistSession(user: user)
    }

    /// Login flow.
    ///
    /// The KaiX iOS App and the Web client share one backend
    /// (`web/server.py`). When that backend is reachable we always go
    /// through it so the resulting `UserEntity` is the same row that
    /// the Web client sees. The local SwiftData login path remains as
    /// a strict offline fallback for already-registered local accounts.
    func login(username: String, password: String, context: ModelContext) async throws -> UserEntity? {
        if usesLocalAuthOnly {
            if let user = try await UserRepository(context: context).login(username: username, password: password) {
                persistSession(user: user)
                return user
            }
            return nil
        }

        // 1. Remote-first.
        do {
            let entity = try await RemoteSyncService.shared.loginAndSync(
                handle: username, password: password, context: context,
            )
            return entity
        } catch {
            // 2. Fallback to the local SwiftData credential store. Only kicks
            //    in when the backend is unreachable (so we don't lock users
            //    out of the App in airplane mode / dev with no server).
            if let user = try await UserRepository(context: context).login(username: username, password: password) {
                persistSession(user: user)
                return user
            }
            // 3. If both paths fail, surface the original network error.
            throw error
        }
    }

    func register(username: String, displayName: String, password: String, email: String? = nil, code: String? = nil, region: KaiXRegionDirectory.Region, appLanguage: AppLanguage? = nil, context: ModelContext) async throws -> UserEntity {
        if usesLocalAuthOnly {
            let user = try await UserRepository(context: context).register(
                username: username, displayName: displayName, password: password, region: region,
            )
            persistSession(user: user)
            return user
        }

        do {
            return try await RemoteSyncService.shared.registerAndSync(
                handle: username, displayName: displayName, password: password, email: email, code: code, region: region, appLanguage: appLanguage, context: context,
            )
        } catch {
            // Offline fallback — register locally so the user can keep using
            // the App; the next login (online) will reconcile against the
            // server, which is the authoritative store.
            let user = try await UserRepository(context: context).register(
                username: username, displayName: displayName, password: password, region: region,
            )
            persistSession(user: user)
            return user
        }
    }

    private var usesLocalAuthOnly: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.environment["KAIX_UI_TEST_LOCAL_AUTH"] == "1"
            || processInfo.arguments.contains("-kaixUITestLocalAuth")
    }
}
