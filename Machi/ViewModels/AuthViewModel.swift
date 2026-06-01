import Foundation
import Combine
import SwiftData

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case login
        case register

        var id: String { rawValue }
    }

    enum Field: Hashable {
        case username
        case displayName
        case email
        case code
        case password
        case region
    }

    enum FieldAvailability: Equatable { case idle, checking, available, taken }

    @Published var mode: Mode = .login
    @Published var username = ""
    @Published var displayName = ""
    @Published var email = ""
    @Published var code = ""
    @Published var password = ""
    @Published var selectedRegion: KaiXRegionDirectory.Region?
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var fieldErrors: [Field: String] = [:]
    @Published var isLoading = false
    // Email verification + live duplicate-check (parity with web register).
    @Published var sendingCode = false
    @Published var codeSent = false
    @Published var codeCooldown = 0
    @Published var usernameAvailability: FieldAvailability = .idle
    @Published var emailAvailability: FieldAvailability = .idle
    private var cooldownTask: Task<Void, Never>?

    func submit(context: ModelContext, language: AppLanguage) async -> UserEntity? {
        guard !isLoading else { return nil }
        errorMessage = nil
        fieldErrors = validate(language: language)
        guard fieldErrors.isEmpty else { return nil }

        isLoading = true
        defer { isLoading = false }

        do {
            switch mode {
            case .login:
                guard let user = try await AuthService.shared.login(username: AuthValidation.normalizedHandle(username), password: password, context: context) else {
                    errorMessage = L("wrongCredentials", language)
                    return nil
                }
                return user

            case .register:
                guard let selectedRegion else { return nil }
                do {
                    return try await AuthService.shared.register(
                        username: AuthValidation.normalizedHandle(username),
                        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password,
                        email: optionalEmail,
                        code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                        region: selectedRegion,
                        context: context
                    )
                } catch RepositoryError.duplicate {
                    fieldErrors[.username] = L("handleTaken", language)
                    return nil
                }
            }
        } catch let apiError as KaiXAPIError {
            apply(apiError: apiError, language: language)
            return nil
        } catch {
            errorMessage = L("databaseSaveFailed", language)
            return nil
        }
    }

    func fieldError(_ field: Field) -> String? {
        fieldErrors[field]
    }

    private var optionalEmail: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func clearError(for field: Field) {
        fieldErrors[field] = nil
        errorMessage = nil
    }

    // MARK: - Email verification code

    func sendCode(language: AppLanguage) async {
        guard !sendingCode, codeCooldown == 0 else { return }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: AuthValidation.emailRegex, options: .regularExpression) != nil else {
            fieldErrors[.email] = L("authInvalidEmail", language)
            return
        }
        sendingCode = true
        infoMessage = nil
        defer { sendingCode = false }
        do {
            // Don't email a code to an address that's already registered.
            let avail = try await KaiXAPIClient.shared.checkEmail(trimmed)
            guard avail.available else {
                emailAvailability = .taken
                fieldErrors[.email] = L("authEmailTaken", language)
                return
            }
            emailAvailability = .available
            _ = try await KaiXAPIClient.shared.sendVerificationCode(email: trimmed, purpose: "register")
            codeSent = true
            infoMessage = L("authCodeSent", language)
            startCooldown(60)
        } catch let apiError as KaiXAPIError {
            apply(apiError: apiError, language: language)
        } catch {
            errorMessage = L("authNetworkError", language)
        }
    }

    private func startCooldown(_ seconds: Int) {
        cooldownTask?.cancel()
        codeCooldown = seconds
        cooldownTask = Task { @MainActor [weak self] in
            while let self, self.codeCooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.codeCooldown = max(0, self.codeCooldown - 1)
            }
        }
    }

    // MARK: - Live duplicate check (debounced by the view's .task(id:))

    func checkUsernameAvailability(language: AppLanguage) async {
        guard mode == .register else { usernameAvailability = .idle; return }
        let handle = AuthValidation.normalizedHandle(username)
        guard handle.range(of: AuthValidation.handleRegex, options: .regularExpression) != nil,
              !AuthValidation.isReserved(handle) else {
            usernameAvailability = .idle
            return
        }
        usernameAvailability = .checking
        do {
            let res = try await KaiXAPIClient.shared.checkUsername(handle)
            guard AuthValidation.normalizedHandle(username) == handle else { return }
            usernameAvailability = res.available ? .available : .taken
            if !res.available { fieldErrors[.username] = L("handleTaken", language) }
        } catch {
            usernameAvailability = .idle
        }
    }

    func checkEmailAvailability(language: AppLanguage) async {
        guard mode == .register else { emailAvailability = .idle; return }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: AuthValidation.emailRegex, options: .regularExpression) != nil else {
            emailAvailability = .idle
            return
        }
        emailAvailability = .checking
        do {
            let res = try await KaiXAPIClient.shared.checkEmail(trimmed)
            guard email.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            emailAvailability = res.available ? .available : .taken
            if !res.available { fieldErrors[.email] = L("authEmailTaken", language) }
        } catch {
            emailAvailability = .idle
        }
    }

    func validate(language: AppLanguage) -> [Field: String] {
        switch mode {
        case .login:
            return AuthValidation.loginErrors(username: username, password: password, language: language)
        case .register:
            return AuthValidation.registerErrors(
                username: username,
                displayName: displayName,
                email: email,
                code: code,
                password: password,
                region: selectedRegion,
                language: language
            )
        }
    }

    private func apply(apiError: KaiXAPIError, language: AppLanguage) {
        let code = apiError.error.code
        switch code {
        case "invalid_credentials", "http_401":
            fieldErrors[.password] = L("wrongCredentials", language)
        case "user_not_found":
            fieldErrors[.username] = L("authUserNotFound", language)
        case "handle_taken":
            fieldErrors[.username] = L("handleTaken", language)
        case "invalid_handle":
            fieldErrors[.username] = L("authInvalidHandle", language)
        case "weak_password", "invalid_password":
            fieldErrors[.password] = L("passwordTooShort", language)
        case "invalid_email", "email_taken":
            fieldErrors[.email] = code == "email_taken" ? L("authEmailTaken", language) : L("authInvalidEmail", language)
        case "invalid_code", "code_expired", "code_required":
            fieldErrors[.code] = L("authCodeInvalid", language)
        case "rate_limited":
            errorMessage = L("authRateLimited", language)
        case "network_error":
            errorMessage = L("authNetworkError", language)
        case "timeout":
            errorMessage = L("authTimeout", language)
        default:
            errorMessage = apiError.error.message
        }
    }
}

enum AuthValidation {
    static let passwordMinLength = 8
    static let displayNameMaxLength = 32
    private static let handlePattern = #"^[a-z0-9_.]{3,20}$"#
    private static let emailPattern = #"^[^\s@]+@[^\s@.]+\.[^\s@.]+$"#
    private static let reservedHandles: Set<String> = [
        "admin", "administrator", "root", "machi", "machicity", "kaix",
        "official", "support", "help", "news",
    ]

    static var handleRegex: String { handlePattern }
    static var emailRegex: String { emailPattern }
    static func isReserved(_ handle: String) -> Bool { reservedHandles.contains(handle) }

    static func normalizedHandle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
    }

    static func sanitizedRegisterHandle(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
        return String(normalizedHandle(value).filter { allowed.contains($0) }.prefix(20))
    }

    static func limitedDisplayName(_ value: String) -> String {
        String(value.prefix(displayNameMaxLength))
    }

    static func loginErrors(username: String, password: String, language: AppLanguage) -> [AuthViewModel.Field: String] {
        var errors: [AuthViewModel.Field: String] = [:]
        if normalizedHandle(username).isEmpty {
            errors[.username] = L("authUsernameRequired", language)
        }
        if password.isEmpty {
            errors[.password] = L("authPasswordRequired", language)
        }
        return errors
    }

    static func registerErrors(
        username: String,
        displayName: String,
        email: String,
        code: String,
        password: String,
        region: KaiXRegionDirectory.Region?,
        language: AppLanguage
    ) -> [AuthViewModel.Field: String] {
        var errors: [AuthViewModel.Field: String] = [:]
        let handle = normalizedHandle(username)
        if handle.isEmpty {
            errors[.username] = L("authUsernameRequired", language)
        } else if handle.range(of: handlePattern, options: .regularExpression) == nil {
            errors[.username] = L("authInvalidHandle", language)
        } else if reservedHandles.contains(handle) {
            errors[.username] = L("authInvalidHandle", language)
        }

        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            errors[.displayName] = L("authDisplayNameRequired", language)
        } else if name.count > displayNameMaxLength {
            errors[.displayName] = L("authDisplayNameTooLong", language)
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty {
            errors[.email] = L("authEmailRequired", language)
        } else if trimmedEmail.range(of: emailPattern, options: .regularExpression) == nil {
            errors[.email] = L("authInvalidEmail", language)
        }

        if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.code] = L("authCodeRequired", language)
        }

        if password.isEmpty {
            errors[.password] = L("authPasswordRequired", language)
        } else if password.count < passwordMinLength {
            errors[.password] = L("passwordTooShort", language)
        } else if password.range(of: #"[A-Za-z]"#, options: .regularExpression) == nil
                    || password.range(of: #"\d"#, options: .regularExpression) == nil {
            errors[.password] = L("passwordTooShort", language)
        }

        if region == nil {
            errors[.region] = L("selectRegisterRegionError", language)
        }
        return errors
    }
}
