import Foundation
import Combine
import SwiftData

@MainActor
final class AppState: ObservableObject {
    @Published var currentUser: UserEntity?
    @Published var state: ScreenState = .idle
    @Published var databaseRecoveryNotice: DatabaseRecoveryNotice?

    func bootstrap(context: ModelContext, currentUserId: String) async {
        // `.task` can be cancelled and restarted when the app returns from
        // the background. If the user is already inside the app, keep the
        // current screen on display and refresh the session quietly instead
        // of flashing the full cold-start splash again.
        let shouldShowBlockingLoader: Bool = {
            if currentUser != nil, state == .loaded { return false }
            switch state {
            case .idle, .loading, .error:
                return true
            case .empty:
                return !currentUserId.isEmpty
            case .loaded:
                return currentUser == nil
            }
        }()
        if shouldShowBlockingLoader {
            state = .loading
        }
        #if DEBUG
        databaseRecoveryNotice = DatabaseRecoveryNoticeStore.load()
        #else
        databaseRecoveryNotice = nil
        #endif

        do {
            let processInfo = ProcessInfo.processInfo
            #if DEBUG
            let shouldUseLocalFixtures = processInfo.environment["KAIX_UI_TEST_LOCAL_AUTH"] == "1"
                || processInfo.arguments.contains("-kaixUITestLocalAuth")
                || processInfo.environment["KAIX_UI_TEST_AUTO_LOGIN"] == "1"
                || processInfo.arguments.contains("-kaixUITestAutoLogin")
            if shouldUseLocalFixtures {
                try await DatabaseSeeder.bootstrapIfNeeded(context: context)
            }
            let shouldAutoLoginForUITests = shouldUseLocalFixtures
                && (processInfo.environment["KAIX_UI_TEST_AUTO_LOGIN"] == "1"
                    || processInfo.arguments.contains("-kaixUITestAutoLogin"))
            if shouldAutoLoginForUITests {
                let repository = UserRepository(context: context)
                let user: UserEntity
                do {
                    user = try await repository.register(
                        username: "ui_test_runner",
                        displayName: "UI Test",
                        password: "secret123"
                    )
                } catch RepositoryError.duplicate {
                    guard let existingUser = try await repository.login(username: "ui_test_runner", password: "secret123") else {
                        throw RepositoryError.duplicate
                    }
                    user = existingUser
                }
                AuthService.shared.persistSession(user: user)
                currentUser = user
                state = .loaded
                return
            }
            #endif
            if currentUserId.isEmpty {
                currentUser = nil
            } else if currentUserId == GuestSession.guestID && KaiXBackend.token == nil {
                currentUser = GuestSession.ensureGuestUser(context: context)
            } else if KaiXBackend.token != nil {
                currentUser = try await UserRepository(context: context).fetchUser(id: currentUserId)
                if currentUser == nil {
                    AuthService.shared.logout()
                }
            } else {
                AuthService.shared.logout()
                currentUser = nil
            }
            state = currentUser == nil ? .empty : .loaded
        } catch {
            state = .error("暂时无法连接服务器，请稍后重试。")
            #if DEBUG
            databaseRecoveryNotice = DatabaseRecoveryNotice(
                mode: .ephemeral,
                userMessage: "本地数据库需要恢复。",
                technicalDetails: error.kaixTechnicalSummary,
                occurredAt: .now
            )
            #endif
        }
    }
}

private extension Error {
    var kaixTechnicalSummary: String {
        "\(type(of: self)): \(localizedDescription)"
    }
}
