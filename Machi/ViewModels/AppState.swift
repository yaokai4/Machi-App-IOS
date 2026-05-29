import Foundation
import Combine
import SwiftData

@MainActor
final class AppState: ObservableObject {
    @Published var currentUser: UserEntity?
    @Published var state: ScreenState = .idle
    @Published var databaseRecoveryNotice: DatabaseRecoveryNotice?

    func bootstrap(context: ModelContext, currentUserId: String) async {
        state = .loading
        #if DEBUG
        databaseRecoveryNotice = DatabaseRecoveryNoticeStore.load()
        #else
        databaseRecoveryNotice = nil
        #endif

        do {
            try await DatabaseSeeder.bootstrapIfNeeded(context: context)
            #if DEBUG
            let processInfo = ProcessInfo.processInfo
            let shouldAutoLoginForUITests = processInfo.environment["KAIX_UI_TEST_AUTO_LOGIN"] == "1"
                || processInfo.arguments.contains("-kaixUITestAutoLogin")
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
            } else {
                currentUser = try await UserRepository(context: context).fetchUser(id: currentUserId)
                if currentUser == nil {
                    AuthService.shared.logout()
                }
            }
            state = currentUser == nil ? .empty : .loaded
        } catch {
            state = .error("暂时无法打开本地内容，请稍后重试。")
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
