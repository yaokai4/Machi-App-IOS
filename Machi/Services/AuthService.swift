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
        // Unbind this device's push token first so the next account on
        // this phone never receives the previous account's notifications.
        PushTokenService.unregisterForLogout()
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
    /// (`web/server.py`). Production login is server-only so the user,
    /// payment, messaging, notification and workbench state cannot diverge.
    func login(username: String, password: String, captchaId: String? = nil, captchaCode: String? = nil, context: ModelContext) async throws -> UserEntity? {
        if usesLocalAuthOnly {
            if let user = try await UserRepository(context: context).login(username: username, password: password) {
                persistSession(user: user)
                return user
            }
            return nil
        }

        let response = try await KaiXAPIClient.shared.login(
            handle: username,
            password: password,
            captchaId: captchaId,
            captchaCode: captchaCode
        )
        let user = UserRepository.entity(from: response.user)
        persistSession(user: user)
        _ = context
        return user
    }

    func register(username: String, displayName: String, password: String, email: String? = nil, code: String? = nil, referralCode: String? = nil, region: KaiXRegionDirectory.Region, appLanguage: AppLanguage? = nil, context: ModelContext) async throws -> UserEntity {
        if usesLocalAuthOnly {
            let user = try await UserRepository(context: context).register(
                username: username, displayName: displayName, password: password, region: region,
            )
            persistSession(user: user)
            return user
        }

        let response = try await KaiXAPIClient.shared.register(
            handle: username,
            displayName: displayName,
            password: password,
            email: email,
            code: code,
            referralCode: referralCode,
            region: region,
            appLanguage: appLanguage
        )
        let user = UserRepository.entity(from: response.user)
        persistSession(user: user)
        _ = context
        return user
    }

    private var usesLocalAuthOnly: Bool {
        let processInfo = ProcessInfo.processInfo
        return KaiXRuntimeFlags.allowLocalStoreFallback
            && (processInfo.environment["KAIX_UI_TEST_LOCAL_AUTH"] == "1"
                || processInfo.arguments.contains("-kaixUITestLocalAuth"))
    }
}
