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
        case captcha
    }

    enum FieldAvailability: Equatable { case idle, checking, available, taken }

    @Published var mode: Mode = .login
    @Published var username = ""
    @Published var displayName = ""
    @Published var email = ""
    @Published var code = ""
    /// 邀请裂变: the friend's invite code (`referral_code`), SEPARATE from the
    /// email-verification `code` above. Optional — prefilled from a tapped
    /// `/i/<code>` link but freely editable, and a blank/bad code never blocks
    /// sign-up (the server silently ignores it).
    @Published var referralCode = ""
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
    // Image captcha (anonymous-auth bot guard, parity with web).
    @Published var captchaEnabled = false
    @Published var captchaImage: Data?
    @Published var captchaCode = ""
    @Published var captchaLoading = false
    // After a successful email-code request the server has *consumed* the
    // captcha challenge (registration itself needs no captcha), so the row
    // collapses into a "verified" confirmation instead of re-prompting. A
    // resend (cooldown end) re-arms it with a fresh challenge.
    @Published var captchaVerified = false
    // Bumped to ask the view to move keyboard focus to the captcha field
    // (used when a bad captcha forces a re-entry).
    @Published var captchaFocusRequest = 0
    private var captchaId = ""

    func submit(context: ModelContext, language: AppLanguage) async -> UserEntity? {
        guard !isLoading else { return nil }
        errorMessage = nil
        fieldErrors = validate(language: language)
        if mode == .login, captchaEnabled, !captchaId.isEmpty,
           captchaCode.trimmingCharacters(in: .whitespaces).isEmpty {
            fieldErrors[.captcha] = L("authCaptchaRequired", language)
        }
        guard fieldErrors.isEmpty else { return nil }

        isLoading = true
        defer { isLoading = false }

        do {
            switch mode {
            case .login:
                guard let user = try await AuthService.shared.login(
                    username: AuthValidation.normalizedLoginIdentifier(username),
                    password: password,
                    captchaId: captchaEnabled && !captchaId.isEmpty ? captchaId : nil,
                    captchaCode: captchaCode.trimmingCharacters(in: .whitespaces),
                    context: context
                ) else {
                    errorMessage = L("wrongCredentials", language)
                    return nil
                }
                return user

            case .register:
                guard let selectedRegion else { return nil }
                do {
                    let user = try await AuthService.shared.register(
                        username: AuthValidation.normalizedHandle(username),
                        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password,
                        email: optionalEmail,
                        code: code.trimmingCharacters(in: .whitespacesAndNewlines),
                        referralCode: referralCode.trimmingCharacters(in: .whitespacesAndNewlines),
                        region: selectedRegion,
                        appLanguage: language,
                        context: context
                    )
                    // 邀请裂变: the code (if any) rode along in the register call
                    // as a pending bind — consume the stashed link so we don't
                    // re-apply it later.
                    ReferralInvite.clear()
                    return user
                } catch RepositoryError.duplicate {
                    fieldErrors[.username] = L("handleTaken", language)
                    return nil
                }
            }
        } catch let apiError as KaiXAPIError {
            apply(apiError: apiError, language: language)
            // The server burns the captcha challenge on every attempt —
            // whatever failed, the old image can't be reused.
            if mode == .login { await refreshCaptcha() }
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
        if captchaEnabled, !captchaId.isEmpty,
           captchaCode.trimmingCharacters(in: .whitespaces).isEmpty {
            fieldErrors[.captcha] = L("authCaptchaRequired", language)
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
            _ = try await KaiXAPIClient.shared.sendVerificationCode(
                email: trimmed,
                purpose: "register",
                captchaId: captchaEnabled && !captchaId.isEmpty ? captchaId : nil,
                captchaCode: captchaCode.trimmingCharacters(in: .whitespaces)
            )
            codeSent = true
            infoMessage = L("authCodeSent", language)
            startCooldown(60)
            // Success: the server consumed the captcha and registration won't
            // ask for it again. Keep the user's input visible — collapse the
            // row into a "verified" badge rather than wiping + reloading it.
            if captchaEnabled, !captchaId.isEmpty {
                captchaVerified = true
                fieldErrors[.captcha] = nil
            }
        } catch let apiError as KaiXAPIError {
            // The challenge was submitted to the server, which burns it on every
            // verify — so any server verdict needs a fresh image. Refresh, then
            // surface the precise reason and pull focus back to the captcha.
            let consumed = captchaEnabled && !captchaId.isEmpty
            if consumed { await refreshCaptcha() }
            apply(apiError: apiError, language: language)
            if consumed {
                let code = apiError.error.code
                let isCaptchaVerdict = ["invalid_captcha", "captcha_expired", "captcha_required"].contains(code)
                // Non-captcha failures (e.g. rate limit) still invalidated the
                // image; say so explicitly instead of silently clearing it.
                if !isCaptchaVerdict, fieldErrors[.captcha] == nil {
                    fieldErrors[.captcha] = L("authCaptchaRefreshed", language)
                }
                captchaFocusRequest += 1
            }
        } catch {
            // Network failure never reached the server, so the captcha is still
            // valid — leave the user's input untouched.
            errorMessage = L("authNetworkError", language)
        }
    }

    // MARK: - Image captcha

    private var captchaFetchSeq = 0

    /// Fetch a fresh challenge for the current mode's scene. Hides the row
    /// entirely when the server reports enforcement disabled. Stale fetches
    /// (e.g. a mode switch mid-flight) are discarded by sequence number so
    /// the shown image always matches the stored challenge id.
    func refreshCaptcha() async {
        captchaFetchSeq += 1
        let seq = captchaFetchSeq
        captchaLoading = true
        captchaCode = ""
        captchaVerified = false
        fieldErrors[.captcha] = nil
        do {
            let res = try await KaiXAPIClient.shared.fetchCaptcha(scene: mode == .login ? "login" : "register")
            guard seq == captchaFetchSeq else { return }
            captchaEnabled = res.enabled
            captchaId = res.captcha_id ?? ""
            captchaImage = res.pngData
        } catch {
            guard seq == captchaFetchSeq else { return }
            // Keep current visibility; show the retry affordance. Submitting
            // without a challenge id simply omits the captcha fields, and the
            // server's verdict (if it requires one) lands on the captcha field.
            captchaId = ""
            captchaImage = nil
        }
        captchaLoading = false
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
            // Cooldown ended: a resend needs a brand-new challenge because the
            // previous one was consumed. Re-arm it so the user can solve a fresh
            // image before tapping "resend".
            if let self, !Task.isCancelled, self.captchaVerified {
                await self.refreshCaptcha()
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
        case "captcha_required":
            captchaEnabled = true
            fieldErrors[.captcha] = L("authCaptchaRequired", language)
        case "invalid_captcha", "captcha_expired":
            captchaEnabled = true
            fieldErrors[.captcha] = L("authCaptchaInvalid", language)
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

    /// Login accepts a handle OR an email. Emails must keep their "@", so only
    /// trim + lowercase them; plain handles still get the strict normalization.
    static func normalizedLoginIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("@") { return trimmed.lowercased() }
        return normalizedHandle(trimmed)
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
        if normalizedLoginIdentifier(username).isEmpty {
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
