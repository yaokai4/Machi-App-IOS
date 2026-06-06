import AuthenticationServices
import SwiftData
import UIKit

@MainActor
final class GoogleAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuthService()

    private var session: ASWebAuthenticationSession?

    func signIn(context: ModelContext) async throws -> UserEntity {
        let start = try await KaiXAPIClient.shared.googleAuthStart()
        let rawURL = start.url ?? start.authorization_url
        guard let url = URL(string: rawURL) else {
            throw KaiXAPIError(error: .init(code: "google_oauth_invalid_url", message: "Google login URL is invalid."))
        }
        let callback = try await authenticate(url: url)
        let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            throw KaiXAPIError(error: .init(code: error, message: "Google sign-in was not completed."))
        }
        guard let token = components?.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty else {
            throw KaiXAPIError(error: .init(code: "google_missing_token", message: "Google sign-in did not return a session."))
        }
        KaiXBackend.token = token
        let dto = try await KaiXAPIClient.shared.me()
        let entity = RemoteSyncService.shared.upsertUser(dto, context: context)
        AuthService.shared.persistSession(user: entity)
        try? context.save()
        Task { await RemoteSyncService.shared.bootstrap(context: context) }
        return entity
    }

    /// Bind Google to the CURRENT (already-authenticated) account. The backend
    /// captures the active user from the bearer token at `/start?intent=link`,
    /// so the unauthenticated callback can only ever attach Google to *this*
    /// account — it never signs in as someone else and issues no new session.
    /// Throws `KaiXAPIError` (with the server's code) on failure; a user cancel
    /// surfaces as a plain `ASWebAuthenticationSessionError`.
    func linkAccount() async throws {
        let start = try await KaiXAPIClient.shared.googleAuthStart(intent: "link")
        let rawURL = start.url ?? start.authorization_url
        guard let url = URL(string: rawURL) else {
            throw KaiXAPIError(error: .init(code: "google_oauth_invalid_url", message: "Google 绑定地址无效。"))
        }
        let callback = try await authenticate(url: url)
        let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value, !error.isEmpty {
            throw KaiXAPIError(error: .init(code: error, message: "Google 绑定未完成。"))
        }
        guard components?.queryItems?.first(where: { $0.name == "linked" })?.value == "1" else {
            throw KaiXAPIError(error: .init(code: "google_link_failed", message: "Google 绑定未完成。"))
        }
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: "machi") { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.session = nil
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: error ?? URLError(.userAuthenticationRequired))
                    }
                }
            }
            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = false
            self.session = authSession
            if !authSession.start() {
                self.session = nil
                continuation.resume(throwing: URLError(.cannotLoadFromNetwork))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        return scenes.first?.windows.first ?? ASPresentationAnchor(frame: .zero)
    }
}
