import SwiftData
import SwiftUI
import UIKit
import UserNotifications

private func settingsText(_ language: AppLanguage, _ zh: String, _ ja: String, _ en: String) -> String {
    KXListingCopy.pickText(language, zh, ja, en)
}

private enum AccountSecurityVerificationMethod: String, CaseIterable, Identifiable {
    case password
    case emailCode

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .password:
            return settingsText(language, "当前密码", "現在のパスワード", "Current password")
        case .emailCode:
            return settingsText(language, "邮箱验证码", "メール認証コード", "Email code")
        }
    }
}

struct AccountPasswordSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var username: String
    @State private var verificationMethod: AccountSecurityVerificationMethod = .password
    @State private var currentPassword = ""
    @State private var passwordCode = ""
    @State private var passwordChallengeId: String?
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var usernameMessage: String?
    @State private var message: String?
    @State private var isSavingUsername = false
    @State private var isSavingPassword = false
    @State private var isSendingPasswordCode = false
    let user: UserEntity

    init(user: UserEntity) {
        self.user = user
        _username = State(initialValue: user.username)
    }

    var body: some View {
        SettingsFormPage(title: L("accountPassword", language)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("username", language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(L("username", language), text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .kxInputField()
                Button {
                    Task { await saveUsername() }
                } label: {
                    Group {
                        if isSavingUsername {
                            KXSpinner(size: 20, lineWidth: 2.2, tint: .white)
                        } else {
                            Text(L("saveUsername", language))
                        }
                    }
                    .kxGlassButton(enabled: canSaveUsername)
                }
                .buttonStyle(KXPressableStyle(scale: 0.98))
                .disabled(!canSaveUsername)

                if !username.normalizedUsername.isEmpty, username.normalizedUsername != username.trimmingCharacters(in: .whitespacesAndNewlines) {
                    Text(L("usernameWillNormalize", language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let usernameMessage {
                    Text(usernameMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(settingsText(language, "安全验证", "セキュリティ確認", "Security verification"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker(settingsText(language, "安全验证", "セキュリティ確認", "Security verification"), selection: $verificationMethod) {
                    ForEach(AccountSecurityVerificationMethod.allCases) { method in
                        Text(method.title(language)).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if verificationMethod == .password {
                    SecureField(L("currentPassword", language), text: $currentPassword)
                        .kxInputField()
                } else {
                    HStack(spacing: 10) {
                        TextField("输入当前邮箱验证码", text: $passwordCode)
                            .keyboardType(.numberPad)
                            .kxInputField()
                        Button {
                            Task { await sendPasswordCode() }
                        } label: {
                            Group {
                        if isSendingPasswordCode {
                            KXSpinner(size: 18, lineWidth: 2.2)
                        } else {
                            Text(settingsText(language, "发送", "送信", "Send")).font(.subheadline.weight(.bold))
                        }
                            }
                            .foregroundStyle(KXColor.accent)
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .kxGlassCapsule()
                        }
                        .buttonStyle(KXPressableStyle(scale: 0.97))
                        .disabled(isSendingPasswordCode || user.email.isEmpty)
                    }
                    Text(user.email.isEmpty ? noBoundEmailMessage : codeWillSendMessage(maskedEmail(user.email)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            SecureField(L("newPassword", language), text: $newPassword)
                .kxInputField()
            SecureField(L("confirmPassword", language), text: $confirmPassword)
                .kxInputField()
            Button {
                Task { await savePassword() }
            } label: {
                Group {
                    if isSavingPassword {
                        KXSpinner(size: 20, lineWidth: 2.2, tint: .white)
                    } else {
                        Text(L("savePassword", language))
                    }
                }
                .kxGlassButton(enabled: canSavePassword && !isSavingPassword)
            }
            .buttonStyle(KXPressableStyle(scale: 0.98))
            .disabled(!canSavePassword || isSavingPassword)
            if (hasPasswordDraft), !canSavePassword {
                Text(L("passwordValidationMessage", language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var canSavePassword: Bool {
        if KaiXBackend.token == nil {
            return !currentPassword.isEmpty && isStrongPassword(newPassword) && newPassword == confirmPassword
        }
        let hasVerification = verificationMethod == .password ? !currentPassword.isEmpty : !passwordCode.isEmpty
        return hasVerification && isStrongPassword(newPassword) && newPassword == confirmPassword
    }

    private var hasPasswordDraft: Bool {
        !currentPassword.isEmpty || !passwordCode.isEmpty || !newPassword.isEmpty || !confirmPassword.isEmpty
    }

    private var canSaveUsername: Bool {
        !isSavingUsername
        && !username.normalizedUsername.isEmpty
        && username.normalizedUsername != user.username
    }

    private func saveUsername() async {
        guard canSaveUsername else { return }
        isSavingUsername = true
        defer { isSavingUsername = false }
        do {
            try await UserRepository(context: modelContext).updateUsername(user: user, username: username)
            username = user.username
            usernameMessage = L("usernameUpdated", language)
        } catch RepositoryError.duplicate {
            usernameMessage = L("handleTaken", language)
        } catch RepositoryError.validationFailed {
            usernameMessage = L("usernameValidationMessage", language)
        } catch {
            usernameMessage = error.kaixUserMessage
        }
    }

    private func savePassword() async {
        guard canSavePassword else {
            message = L("passwordValidationMessage", language)
            return
        }
        guard newPassword != currentPassword else {
            message = L("passwordSameAsOld", language)
            return
        }

        isSavingPassword = true
        defer { isSavingPassword = false }

        do {
            if KaiXBackend.token != nil {
                if verificationMethod == .password {
                    try await KaiXAPIClient.shared.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                } else {
                    try await KaiXAPIClient.shared.changePassword(
                        code: passwordCode,
                        challengeId: passwordChallengeId,
                        newPassword: newPassword
                    )
                }
            } else if !user.passwordHash.isEmpty {
                guard PasswordHasher.verify(currentPassword, storedHash: user.passwordHash) else {
                    message = L("currentPasswordIncorrect", language)
                    return
                }
            }

            user.passwordHash = PasswordHasher.hash(newPassword)
            user.updatedAt = .now
            try modelContext.save()
            currentPassword = ""
            passwordCode = ""
            passwordChallengeId = nil
            newPassword = ""
            confirmPassword = ""
            message = settingsText(language, "密码已更新，请使用新密码登录。", "パスワードを更新しました。次回から新しいパスワードでログインしてください。", "Password updated. Please use the new password next time you sign in.")
        } catch let apiError as KaiXAPIError {
            if apiError.error.code == "invalid_credentials" {
                message = L("currentPasswordIncorrect", language)
            } else if apiError.error.code == "password_reuse" {
                message = L("passwordSameAsOld", language)
            } else if apiError.error.code == "invalid_code" || apiError.error.code == "code_expired" {
                message = invalidCodeMessage
            } else {
                message = apiError.error.message
            }
        } catch {
            message = error.kaixUserMessage
        }
    }

    private func isStrongPassword(_ password: String) -> Bool {
        password.count >= AuthValidation.passwordMinLength
        && password.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        && password.range(of: #"[0-9]"#, options: .regularExpression) != nil
    }

    private func sendPasswordCode() async {
        guard !user.email.isEmpty else {
            message = noBoundEmailMessage
            return
        }
        isSendingPasswordCode = true
        defer { isSendingPasswordCode = false }
        do {
            let response = try await KaiXAPIClient.shared.sendSecurityCode(purpose: "change_password")
            passwordChallengeId = response.challenge_id
            message = codeSentMessage(response.email_hint ?? maskedEmail(user.email))
        } catch {
            message = error.kaixUserMessage
        }
    }

    private var noBoundEmailMessage: String {
        settingsText(language, "当前账号未绑定邮箱，请使用当前密码验证。", "このアカウントにはメールが未登録です。現在のパスワードで確認してください。", "No email is bound to this account. Please verify with your current password.")
    }

    private var invalidCodeMessage: String {
        settingsText(language, "验证码无效或已过期", "認証コードが無効または期限切れです", "The verification code is invalid or expired")
    }

    private func codeWillSendMessage(_ email: String) -> String {
        settingsText(language, "验证码将发送到 \(email)。", "認証コードを \(email) に送信します。", "The verification code will be sent to \(email).")
    }

    private func codeSentMessage(_ email: String) -> String {
        settingsText(language, "验证码已发送到 \(email)。", "認証コードを \(email) に送信しました。", "Verification code sent to \(email).")
    }

    private func maskedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return email }
        let local = parts[0]
        let first = local.first.map(String.init) ?? "*"
        let last = local.count > 2 ? String(local.last!) : ""
        return "\(first)***\(last)@\(parts[1])"
    }
}

struct ContactSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @AppStorage("accountEmail") private var storedEmail = ""
    @AppStorage("accountPhone") private var phone = ""
    @State private var verificationMethod: AccountSecurityVerificationMethod = .password
    @State private var currentPassword = ""
    @State private var currentEmailCode = ""
    @State private var currentEmailChallengeId: String?
    @State private var email: String
    @State private var newEmailCode = ""
    @State private var newEmailChallengeId: String?
    @State private var message: String?
    @State private var isSavingEmail = false
    @State private var isSendingCurrentCode = false
    @State private var isSendingNewCode = false
    let user: UserEntity

    init(user: UserEntity) {
        self.user = user
        let fallbackEmail = UserDefaults.standard.string(forKey: "accountEmail") ?? ""
        _email = State(initialValue: user.email.isEmpty ? fallbackEmail : user.email)
    }

    var body: some View {
        SettingsFormPage(title: L("contactInfo", language)) {
            contactHero
            formBlock(title: settingsText(language, "绑定邮箱", "メールを連携", "Email binding"), subtitle: boundEmailSubtitle, icon: "envelope.badge", tint: .teal) {
                textField(L("email", language), text: $email, keyboard: .emailAddress)
            }
            formBlock(title: settingsText(language, "安全验证", "セキュリティ確認", "Security verification"), subtitle: verificationSubtitle, icon: "shield.lefthalf.filled", tint: .purple) {
                Picker(settingsText(language, "安全验证", "セキュリティ確認", "Security verification"), selection: $verificationMethod) {
                    ForEach(AccountSecurityVerificationMethod.allCases) { method in
                        Text(method.title(language)).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if verificationMethod == .password {
                    secureField(L("currentPassword", language), text: $currentPassword)
                } else {
                    HStack(spacing: 10) {
                        textField(settingsText(language, "当前邮箱验证码", "現在のメール認証コード", "Current email code"), text: $currentEmailCode, keyboard: .numberPad)
                        sendCodeButton(isLoading: isSendingCurrentCode, disabled: user.email.isEmpty) {
                            await sendCurrentEmailCode()
                        }
                    }
                    Text(user.email.isEmpty ? noCurrentEmailMessage : currentEmailCodeMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            formBlock(title: settingsText(language, "新邮箱验证", "新しいメールの確認", "New email verification"), subtitle: settingsText(language, "发送验证码到新的邮箱，验证通过后两端同步更新。", "新しいメールに認証コードを送信し、確認後に Web と iOS を同期します。", "Send a code to the new email. After verification, Web and iOS update together."), icon: "checkmark.message", tint: .blue) {
                HStack(spacing: 10) {
                    textField(settingsText(language, "新邮箱验证码", "新しいメール認証コード", "New email code"), text: $newEmailCode, keyboard: .numberPad)
                    sendCodeButton(isLoading: isSendingNewCode, disabled: !canSendNewEmailCode) {
                        await sendNewEmailCode()
                    }
                }
            }
            saveEmailButton
            formBlock(title: L("phone", language), subtitle: L("contactStored", language), icon: "iphone", tint: .orange) {
                textField(L("phone", language), text: $phone, keyboard: .phonePad)
            }
            if let message {
                statusBanner(message)
            }
        }
    }

    private var contactHero: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .blue.opacity(0.18), radius: 10, x: 0, y: 6)
            VStack(alignment: .leading, spacing: 5) {
                Text(settingsText(language, "安全修改联系方式", "連絡先を安全に変更", "Secure contact updates"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(settingsText(language, "邮箱会同步到 Machi 账号，Web 和 iOS 登录状态会一起更新。手机号目前只保存在本机。", "メールは Machi アカウントに同期され、Web と iOS のログイン情報も更新されます。電話番号は現在この端末にのみ保存されます。", "Email syncs to your Machi account and updates both Web and iOS sign-in. Phone number is currently stored on this device only."))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(KXColor.softBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(KXColor.separator.opacity(0.45), lineWidth: 0.6)
        }
    }

    private func formBlock<Content: View>(title: String, subtitle: String, icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.10), in: Circle())
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            Text(subtitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(12)
        .background(KXColor.softBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(KXColor.separator.opacity(0.45), lineWidth: 0.6)
        }
    }

    private func textField(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(KXColor.separator.opacity(0.65), lineWidth: 0.65)
            }
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Color(.systemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(KXColor.separator.opacity(0.65), lineWidth: 0.65)
            }
    }

    private func sendCodeButton(isLoading: Bool, disabled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Text(settingsText(language, "发送", "送信", "Send"))
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(width: 64, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Color.secondary : Color.white)
        .background(disabled ? KXColor.softBackground : KXColor.accent, in: Capsule())
        .overlay {
            Capsule().stroke(KXColor.separator.opacity(disabled ? 0.6 : 0), lineWidth: 0.6)
        }
        .disabled(disabled || isLoading)
    }

    private var saveEmailButton: some View {
        Button {
            Task { await saveEmail() }
        } label: {
            Group {
                if isSavingEmail {
                    ProgressView()
                } else {
                    Text(L("saveEmail", language))
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.plain)
        .foregroundStyle(canSaveEmail ? Color.white : Color.secondary)
        .background(canSaveEmail ? KXColor.accent : KXColor.softBackground, in: Capsule())
        .overlay {
            Capsule().stroke(KXColor.separator.opacity(canSaveEmail ? 0 : 0.55), lineWidth: 0.65)
        }
        .disabled(!canSaveEmail || isSavingEmail)
    }

    private func statusBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(KXColor.accent)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSaveEmail: Bool {
        guard canSendNewEmailCode, !newEmailCode.isEmpty else { return false }
        if KaiXBackend.token == nil {
            return !currentPassword.isEmpty || user.passwordHash.isEmpty
        }
        if verificationMethod == .password {
            return !currentPassword.isEmpty
        }
        return !currentEmailCode.isEmpty
    }

    private var canSendNewEmailCode: Bool {
        normalizedEmail.range(of: AuthValidation.emailRegex, options: .regularExpression) != nil
        && normalizedEmail != user.email.lowercased()
    }

    private func saveEmail() async {
        guard canSaveEmail else {
            message = L("emailValidationMessage", language)
            return
        }

        isSavingEmail = true
        defer { isSavingEmail = false }

        do {
            if KaiXBackend.token != nil {
                let dto = try await KaiXAPIClient.shared.changeEmail(
                    currentPassword: verificationMethod == .password ? currentPassword : nil,
                    oldCode: verificationMethod == .emailCode ? currentEmailCode : nil,
                    oldChallengeId: currentEmailChallengeId,
                    newEmail: normalizedEmail,
                    newCode: newEmailCode,
                    newChallengeId: newEmailChallengeId
                )
                user.email = dto.email ?? normalizedEmail
            } else {
                if !user.passwordHash.isEmpty, !PasswordHasher.verify(currentPassword, storedHash: user.passwordHash) {
                    message = L("currentPasswordIncorrect", language)
                    return
                }
                user.email = normalizedEmail
            }
            storedEmail = user.email
            user.updatedAt = .now
            try modelContext.save()
            currentPassword = ""
            currentEmailCode = ""
            currentEmailChallengeId = nil
            newEmailCode = ""
            newEmailChallengeId = nil
            message = L("emailUpdated", language)
        } catch let apiError as KaiXAPIError {
            if apiError.error.code == "invalid_credentials" {
                message = L("currentPasswordIncorrect", language)
            } else if apiError.error.code == "invalid_code" || apiError.error.code == "code_expired" {
                message = invalidCodeMessage
            } else {
                message = apiError.error.message
            }
        } catch {
            message = error.kaixUserMessage
        }
    }

    private func sendCurrentEmailCode() async {
        guard !user.email.isEmpty else {
            message = noBoundEmailMessage
            return
        }
        isSendingCurrentCode = true
        defer { isSendingCurrentCode = false }
        do {
            let response = try await KaiXAPIClient.shared.sendSecurityCode(purpose: "change_email_old")
            currentEmailChallengeId = response.challenge_id
            message = codeSentMessage(response.email_hint ?? maskedEmail(user.email))
        } catch {
            message = error.kaixUserMessage
        }
    }

    private func sendNewEmailCode() async {
        guard canSendNewEmailCode else {
            message = L("emailValidationMessage", language)
            return
        }
        isSendingNewCode = true
        defer { isSendingNewCode = false }
        do {
            let response = try await KaiXAPIClient.shared.sendSecurityCode(purpose: "change_email_new", email: normalizedEmail)
            newEmailChallengeId = response.challenge_id
            message = codeSentMessage(response.email_hint ?? maskedEmail(normalizedEmail))
        } catch {
            message = error.kaixUserMessage
        }
    }

    private var boundEmailSubtitle: String {
        user.email.isEmpty
        ? settingsText(language, "当前账号尚未绑定邮箱。", "このアカウントにはまだメールが登録されていません。", "No email is bound to this account yet.")
        : settingsText(language, "当前邮箱：\(maskedEmail(user.email))", "現在のメール: \(maskedEmail(user.email))", "Current email: \(maskedEmail(user.email))")
    }

    private var verificationSubtitle: String {
        verificationMethod == .password
        ? settingsText(language, "输入当前密码后才可以修改绑定邮箱。", "現在のパスワードを入力するとメールを変更できます。", "Enter your current password before changing the bound email.")
        : currentEmailCodeMessage
    }

    private var noCurrentEmailMessage: String {
        settingsText(language, "没有当前邮箱时，请使用当前密码验证。", "現在のメールがない場合は、現在のパスワードで確認してください。", "When there is no current email, verify with your current password.")
    }

    private var currentEmailCodeMessage: String {
        settingsText(language, "验证码将发送到当前邮箱。", "認証コードを現在のメールに送信します。", "The code will be sent to the current email.")
    }

    private var noBoundEmailMessage: String {
        settingsText(language, "当前账号未绑定邮箱，请使用当前密码验证。", "このアカウントにはメールが未登録です。現在のパスワードで確認してください。", "No email is bound to this account. Please verify with your current password.")
    }

    private var invalidCodeMessage: String {
        settingsText(language, "验证码无效或已过期", "認証コードが無効または期限切れです", "The verification code is invalid or expired")
    }

    private func codeSentMessage(_ email: String) -> String {
        settingsText(language, "验证码已发送到 \(email)。", "認証コードを \(email) に送信しました。", "Verification code sent to \(email).")
    }

    private func maskedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return email }
        let local = parts[0]
        let first = local.first.map(String.init) ?? "*"
        let last = local.count > 2 ? String(local.last!) : ""
        return "\(first)***\(last)@\(parts[1])"
    }
}

struct AccountProfileSettingsView: View {
    @Environment(\.appLanguage) private var language
    let currentUser: UserEntity
    var onSwitchAccount: ((UserEntity) -> Void)?
    var onDismissSettings: () -> Void

    var body: some View {
        SettingsFormPage(title: L("accountProfile", language)) {
            SettingsRowLink(icon: "person.crop.circle", tint: .blue, title: L("profile", language), subtitle: L("profileSubtitle", language)) {
                ProfileView(currentUser: currentUser, profileUserId: currentUser.id, showsBackButton: true)
            }
            SettingsDivider()
            SettingsRowLink(icon: "pencil", tint: .indigo, title: L("editProfile", language), subtitle: L("editProfileSubtitle", language)) {
                EditProfileView(user: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "arrow.triangle.2.circlepath", tint: .purple, title: L("switchAccount", language), subtitle: L("switchAccountSubtitle", language)) {
                AccountSwitcherView(currentUser: currentUser) { user in
                    onSwitchAccount?(user)
                    onDismissSettings()
                }
            }
        }
    }
}

struct RegionLanguageSettingsView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.light.rawValue
    @ObservedObject private var regionStore = RegionStore.shared
    let currentUser: UserEntity

    var body: some View {
        SettingsFormPage(title: L("regionAndLanguage", language)) {
            // Country is the only region control that lives in Settings —
            // the browsing CITY switches right on the home/discover headers,
            // so duplicating city pickers here only confused people.
            SettingsRowLink(icon: "globe.asia.australia.fill", tint: .blue, title: L("countrySetting", language), value: countryLabel, subtitle: L("countrySettingSubtitle", language)) {
                CountrySettingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "globe", tint: .blue, title: L("language", language), value: AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? AppLanguage.system.rawValue).title, subtitle: L("currentLanguage", language)) {
                LanguageSettingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "captions.bubble", tint: .purple, title: L("contentLanguage", language), value: LanguageManager.shared.preferred.title(language), subtitle: L("contentLanguageSubtitle", language)) {
                ContentLanguageSettingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "circle.lefthalf.filled", tint: .gray, title: L("appearance", language), value: AppAppearance.from(appAppearance).title(language), subtitle: L("appearanceSubtitle", language)) {
                AppearanceSettingsView()
            }
        }
    }

    private var countryLabel: String {
        let code = (currentUser.country.isEmpty ? "jp" : currentUser.country).lowercased()
        if let country = KaiXRegionDirectory.country(code: code) {
            return "\(country.emoji) \(KaiXRegionDirectory.localizedCountryName(code: code, language: language))"
        }
        return "🇯🇵 \(KaiXRegionDirectory.localizedCountryName(code: "jp", language: language))"
    }
}

struct CountrySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var pendingCountry: CountryOption?
    @State private var message: String?

    let currentUser: UserEntity

    @Environment(\.appLanguage) private var language

    private struct CountryOption: Identifiable, Equatable {
        let code: String
        let title: String
        let regionCode: String
        var id: String { code }
    }

    /// Every country the region directory knows, localized, each mapped to
    /// its default (most popular) city so switching lands somewhere sane.
    private var options: [CountryOption] {
        KaiXRegionDirectory.countries.compactMap { country in
            guard let regionCode = KaiXRegionDirectory.defaultRegionCode(forCountry: country.code) else { return nil }
            let name = KaiXRegionDirectory.localizedCountryName(code: country.code, language: language)
            return CountryOption(code: country.code, title: "\(country.emoji) \(name)", regionCode: regionCode)
        }
    }

    var body: some View {
        SettingsFormPage(title: settingsText(language, "国家", "国", "Country")) {
            Text(settingsText(language, "切换国家会同时把当前浏览城市切换到该国家的默认城市；其他入口只能切换当前国家下的城市。", "国を切り替えると現在の閲覧都市もその国のデフォルト都市に切り替わります。他の入口では現在の国の都市のみ選択できます。", "Changing country also switches your current browsing city to that country's default city. Other entry points can only switch cities within the current country."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(options) { option in
                Button {
                    pendingCountry = option
                } label: {
                    HStack {
                        Text(option.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if option.code == currentCountry {
                            Image(systemName: "checkmark")
                                .foregroundStyle(KXColor.accent)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                SettingsDivider()
            }
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .alert(settingsText(language, "确认切换国家？", "国を切り替えますか？", "Change country?"), isPresented: Binding(get: { pendingCountry != nil }, set: { if !$0 { pendingCountry = nil } })) {
            Button(settingsText(language, "取消", "キャンセル", "Cancel"), role: .cancel) { pendingCountry = nil }
            Button(settingsText(language, "确认切换", "切り替える", "Confirm")) {
                if let pendingCountry {
                    Task { await save(pendingCountry) }
                }
                pendingCountry = nil
            }
        } message: {
            Text(settingsText(language, "国家切换会影响首页、发现、资讯和发布页可选择的城市。", "国の切り替えはホーム、発見、情報、投稿ページで選べる都市に影響します。", "Changing country affects cities available on Home, Discover, Guide, and Publish."))
        }
    }

    private var currentCountry: String {
        currentUser.country.isEmpty ? "jp" : currentUser.country.lowercased()
    }

    private func save(_ option: CountryOption) async {
        guard let region = KaiXRegionDirectory.resolve(regionCode: option.regionCode) else { return }
        currentUser.country = region.countryCode
        currentUser.province = region.provinceCode
        currentUser.city = region.cityCode
        currentUser.currentRegionCode = region.regionCode
        regionStore.setCurrent(region)
        currentUser.recentRegionCodes = regionStore.recent.map(\.regionCode)
        currentUser.updatedAt = .now
        do {
            if KaiXBackend.token != nil {
                let dto = try await KaiXAPIClient.shared.updateRegionLanguage([
                    "country": region.countryCode,
                    "province": region.provinceCode,
                    "city": region.cityCode,
                    "current_region_code": region.regionCode,
                ])
                UserRepository.apply(dto, to: currentUser)
            } else {
                try modelContext.save()
            }
            message = settingsText(language, "国家已更新", "国を更新しました", "Country updated")
        } catch {
            message = error.kaixUserMessage
        }
    }
}

struct ProfileRegionSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var isShowingPicker = false
    @State private var message: String?
    let currentUser: UserEntity

    var body: some View {
        SettingsFormPage(title: L("profileRegion", language)) {
            Text(L("profileRegionHelp", language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                isShowingPicker = true
            } label: {
                Label(profileRegionLabel, systemImage: "mappin.and.ellipse")
                    .font(.headline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isShowingPicker) {
            RegionPickerView(initialCountry: currentUser.country.isEmpty ? "jp" : currentUser.country, allowsAnyCountry: true) { region in
                Task { await save(region) }
            }
        }
    }

    private var profileRegionLabel: String {
        if let region = KaiXRegionDirectory.make(country: currentUser.country, province: currentUser.province.isEmpty ? nil : currentUser.province, city: currentUser.city) {
            return "\(region.countryEmoji) \(region.displayName)"
        }
        return L("pickRegion", language)
    }

    private func save(_ region: KaiXRegionDirectory.Region) async {
        currentUser.country = region.countryCode
        currentUser.province = region.provinceCode
        currentUser.city = region.cityCode
        currentUser.updatedAt = .now
        do {
            if KaiXBackend.token != nil {
                let dto = try await KaiXAPIClient.shared.updateRegionLanguage([
                    "country": region.countryCode,
                    "province": region.provinceCode,
                    "city": region.cityCode
                ])
                UserRepository.apply(dto, to: currentUser)
            } else {
                try modelContext.save()
            }
            message = L("profileRegionUpdated", language)
        } catch {
            message = error.kaixUserMessage
        }
    }
}

struct AccountSecuritySettingsView: View {
    @Environment(\.appLanguage) private var language
    let currentUser: UserEntity
    let onDeleted: () -> Void

    var body: some View {
        SettingsFormPage(title: L("accountSecurity", language)) {
            SettingsRowLink(icon: "lock.rotation", tint: .purple, title: L("accountPassword", language), subtitle: L("accountPasswordSubtitle", language)) {
                AccountPasswordSettingsView(user: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "g.circle.fill", tint: .blue, title: settingsText(language, "Google 账号", "Google アカウント", "Google account"), subtitle: settingsText(language, "绑定后可用 Google 一键登录", "連携すると Google でワンタップログインできます", "Link Google for one-tap sign-in")) {
                GoogleAccountSettingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "envelope.badge", tint: .teal, title: L("contactInfo", language), value: currentUser.email.isEmpty ? nil : currentUser.email, subtitle: L("contactSubtitle", language)) {
                ContactSettingsView(user: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "desktopcomputer", tint: .cyan, title: L("loginDevices", language), subtitle: L("loginDevicesSubtitle", language)) {
                LoginDevicesView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "person.crop.circle.badge.xmark", tint: .red, title: L("blocklist", language), subtitle: L("blocklistSubtitle", language)) {
                BlocklistSettingsView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "trash", tint: .orange, title: L("clearCache", language), subtitle: L("clearCacheSubtitle", language)) {
                CacheSettingsView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "person.crop.circle.badge.minus", tint: .red, title: L("deleteAccount", language), subtitle: L("deleteAccountSubtitle", language)) {
                DeleteAccountView(currentUser: currentUser, onDeleted: onDeleted)
            }
        }
    }
}

/// Bind / unbind a Google account for the current Machi account. State is read
/// live from `me()` (no SwiftData column needed) and refreshed after each
/// action. Binding reuses the zero-dependency ASWebAuthenticationSession flow.
struct GoogleAccountSettingsView: View {
    @Environment(\.appLanguage) private var language
    let currentUser: UserEntity

    @State private var hasGoogle = false
    @State private var canUnlink = false
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var message: String?
    @State private var showUnlinkConfirm = false

    var body: some View {
        SettingsFormPage(title: settingsText(language, "Google 账号", "Google アカウント", "Google account")) {
            VStack(alignment: .leading, spacing: 10) {
                Label(hasGoogle ? settingsText(language, "已绑定 Google", "Google 連携済み", "Google linked") : settingsText(language, "未绑定 Google", "Google 未連携", "Google not linked"),
                      systemImage: hasGoogle ? "checkmark.seal.fill" : "g.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(hasGoogle ? .blue : .secondary)
                Text(hasGoogle
                     ? settingsText(language, "你可以使用 Google 一键登录这个 Machi 账号。", "この Machi アカウントに Google でログインできます。", "You can sign in to this Machi account with Google.")
                     : settingsText(language, "绑定后，下次可直接用 Google 一键登录，无需输入密码。", "連携すると次回から Google でログインでき、パスワード入力は不要です。", "After linking, you can sign in with Google without entering a password."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if isLoading {
                ProgressView().controlSize(.large)
            } else if hasGoogle {
                Button(role: .destructive) {
                    showUnlinkConfirm = true
                } label: {
                    if isWorking { ProgressView() } else { Text(settingsText(language, "解绑 Google", "Google 連携を解除", "Unlink Google")) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isWorking || !canUnlink)
                if !canUnlink {
                    Text(settingsText(language, "该账号通过 Google 创建，请先绑定邮箱并设置登录密码，再解绑 Google，以免无法再次登录。", "このアカウントは Google で作成されています。ログインできなくならないよう、先にメール連携とパスワード設定を行ってください。", "This account was created with Google. Add an email and password before unlinking so you can still sign in."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await link() }
                } label: {
                    if isWorking { ProgressView() } else { Text(settingsText(language, "绑定 Google 账号", "Google アカウントを連携", "Link Google account")) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking)
            }

            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .task { await refresh() }
        .confirmationDialog(settingsText(language, "解绑 Google 账号？", "Google 連携を解除しますか？", "Unlink Google account?"), isPresented: $showUnlinkConfirm, titleVisibility: .visible) {
            Button(settingsText(language, "解绑", "解除", "Unlink"), role: .destructive) { Task { await unlink() } }
            Button(settingsText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(settingsText(language, "解绑后将无法使用 Google 一键登录，仍可用用户名 / 邮箱和密码登录。", "解除後は Google ログインを利用できません。ユーザー名 / メールとパスワードでは引き続きログインできます。", "After unlinking, Google sign-in will no longer work. You can still sign in with username/email and password."))
        }
    }

    private func refresh() async {
        do {
            let me = try await KaiXAPIClient.shared.me()
            hasGoogle = me.has_google ?? false
            canUnlink = me.can_unlink_google ?? false
        } catch {
            message = error.kaixUserMessage
        }
        isLoading = false
    }

    private func link() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await GoogleAuthService.shared.linkAccount()
            await refresh()
            message = settingsText(language, "已绑定 Google 账号。", "Google アカウントを連携しました。", "Google account linked.")
        } catch let apiError as KaiXAPIError {
            message = Self.linkErrorMessage(apiError.error.code, language: language, fallback: apiError.error.message)
        } catch {
            // User cancelled the web auth session — leave silently.
            message = nil
        }
    }

    private func unlink() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            let me = try await KaiXAPIClient.shared.googleUnlink()
            hasGoogle = me.has_google ?? false
            canUnlink = me.can_unlink_google ?? false
            message = settingsText(language, "已解绑 Google 账号。", "Google 連携を解除しました。", "Google account unlinked.")
        } catch let apiError as KaiXAPIError {
            message = apiError.error.message
        } catch {
            message = error.kaixUserMessage
        }
    }

    private static func linkErrorMessage(_ code: String, language: AppLanguage, fallback: String) -> String {
        switch code {
        case "google_already_linked":
            return settingsText(language, "该 Google 账号已绑定到其他 Machi 账号。", "この Google アカウントは別の Machi アカウントに連携されています。", "This Google account is already linked to another Machi account.")
        case "already_linked_other":
            return settingsText(language, "当前账号已绑定了另一个 Google 账号，请先解绑。", "現在のアカウントは別の Google アカウントと連携済みです。先に解除してください。", "This account is already linked to another Google account. Unlink it first.")
        case "state_expired":
            return settingsText(language, "绑定会话已过期，请重试。", "連携セッションの期限が切れました。もう一度お試しください。", "The linking session expired. Please try again.")
        case "google_denied":
            return settingsText(language, "已取消 Google 授权。", "Google 認証をキャンセルしました。", "Google authorization was cancelled.")
        default:
            return fallback.isEmpty ? settingsText(language, "Google 绑定失败，请重试。", "Google 連携に失敗しました。もう一度お試しください。", "Google linking failed. Please try again.") : fallback
        }
    }
}

struct MembershipSettingsView: View {
    @Environment(\.appLanguage) private var language
    @State private var message: String?
    @State private var isSubmitting = false
    let user: UserEntity

    var body: some View {
        SettingsFormPage(title: L("membership", language)) {
            Label(user.isVerified ? L("verifiedAccount", language) : L("notVerified", language), systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(user.isVerified ? .blue : .secondary)
            Text(user.role == .member ? L("memberVerificationHelp", language) : L("creatorAccountHelp", language))
                .foregroundStyle(.secondary)
            Button(isSubmitting ? settingsText(language, "提交中", "送信中", "Submitting") : L("applyVerification", language)) {
                Task { await applyVerification() }
            }
                .buttonStyle(.borderedProminent)
                .disabled(user.isVerified || isSubmitting)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func applyVerification() async {
        if user.isVerified {
            message = L("alreadyVerifiedMessage", language)
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await KaiXAPIClient.shared.submitFeedback(
                category: "identity_verification",
                content: """
                iOS 账号认证申请
                用户: @\(user.username) / \(user.displayName)
                当前角色: \(user.role.rawValue)
                """
            )
            message = settingsText(language, "认证申请已提交，后台会人工审核并联系你补充材料。", "認証申請を送信しました。運営が確認し、必要に応じて追加資料について連絡します。", "Verification request submitted. The team will review it and contact you if more materials are needed.")
        } catch {
            message = error.kaixUserMessage
        }
    }
}

struct BookmarkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @StateObject private var viewModel = SavedContentViewModel()
    let currentUser: UserEntity

    var body: some View {
        ManagedPostListView(
            title: L("bookmarks", language),
            emptySubtitle: L("bookmarkEmptyHelp", language),
            state: viewModel.state,
            posts: viewModel.posts,
            mediaByPostId: viewModel.mediaByPostId,
            authors: viewModel.authors,
            currentUser: currentUser,
            reload: { await viewModel.loadBookmarks(context: modelContext, postStore: postStore) },
            onLike: { post in
                await viewModel.toggleLike(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                    await viewModel.loadBookmarks(context: modelContext, postStore: postStore)
                }
            },
            onBookmark: { post in
                await viewModel.toggleBookmark(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                    await viewModel.loadBookmarks(context: modelContext, postStore: postStore)
                }
            },
            onRepost: { post in
                await viewModel.repost(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                    await viewModel.loadBookmarks(context: modelContext, postStore: postStore)
                }
            },
            onQuoteRepost: { post, content in
                await viewModel.quoteRepost(context: modelContext, post: post, currentUser: currentUser, content: content, postStore: postStore) {
                    await viewModel.loadBookmarks(context: modelContext, postStore: postStore)
                }
            }
        )
        .task { await viewModel.loadBookmarks(context: modelContext, postStore: postStore) }
    }
}

struct MediaLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @StateObject private var viewModel = SavedContentViewModel()
    @State private var filter = MediaLibraryFilter.all
    let currentUser: UserEntity

    private var filteredPosts: [PostEntity] {
        switch filter {
        case .all:
            viewModel.posts
        case .images:
            viewModel.posts.filter { post in
                viewModel.mediaByPostId[post.id]?.contains { $0.type == .image } == true
            }
        case .videos:
            viewModel.posts.filter { post in
                viewModel.mediaByPostId[post.id]?.contains { $0.type == .video } == true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $filter) {
                ForEach(MediaLibraryFilter.allCases) { item in
                    Text(item.title(language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 10)

            ManagedPostListView(
                title: L("mediaLibrary", language),
                emptySubtitle: L("mediaEmptyHelp", language),
                state: viewModel.state,
                posts: filteredPosts,
                mediaByPostId: viewModel.mediaByPostId,
                authors: viewModel.authors,
                currentUser: currentUser,
                reload: { await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore) },
                onLike: { post in
                    await viewModel.toggleLike(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                        await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore)
                    }
                },
                onBookmark: { post in
                    await viewModel.toggleBookmark(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                        await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore)
                    }
                },
                onRepost: { post in
                    await viewModel.repost(context: modelContext, post: post, currentUser: currentUser, postStore: postStore) {
                        await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore)
                    }
                },
                onQuoteRepost: { post, content in
                    await viewModel.quoteRepost(context: modelContext, post: post, currentUser: currentUser, content: content, postStore: postStore) {
                        await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore)
                    }
                }
            )
        }
        .kxPageBackground()
        .navigationTitle(L("mediaLibrary", language))
        .task { await viewModel.loadMediaPosts(context: modelContext, currentUser: currentUser, postStore: postStore) }
    }
}

struct DraftsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @StateObject private var viewModel = DraftsViewModel()
    @State private var selectedDraft: PostEntity?
    let currentUser: UserEntity

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                switch viewModel.state {
                case .loading, .idle:
                    LoadingView()
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await viewModel.load(context: modelContext, currentUser: currentUser) }
                    }
                case .empty:
                    EmptyStateView(title: L("draftsEmpty", language), subtitle: L("draftsHelp", language), systemImage: "tray")
                        .padding(.top, 34)
                case .loaded:
                    ForEach(viewModel.drafts) { draft in
                        DraftCard(
                            draft: draft,
                            mediaItems: viewModel.mediaByPostId[draft.id] ?? [],
                            currentUser: currentUser,
                            edit: { selectedDraft = draft },
                            publish: { Task { await viewModel.publish(context: modelContext, draft: draft, currentUser: currentUser) } },
                            delete: { Task { await viewModel.delete(context: modelContext, draft: draft, currentUser: currentUser) } }
                        )
                    }
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, KaiXTheme.horizontalPadding)
            .kxTabBarSafeBottomPadding()
        }
        .kxPageBackground()
        .navigationTitle(L("drafts", language))
        .task { await viewModel.load(context: modelContext, currentUser: currentUser) }
        .sheet(item: $selectedDraft) { draft in
            DraftEditorView(draft: draft, mediaItems: viewModel.mediaByPostId[draft.id] ?? [], currentUser: currentUser) {
                Task { await viewModel.load(context: modelContext, currentUser: currentUser) }
            }
        }
    }
}

private enum MediaLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case images
    case videos

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .all: L("all", language)
        case .images: L("images", language)
        case .videos: L("videos", language)
        }
    }
}

private struct ManagedPostListView: View {
    @EnvironmentObject private var postStore: PostStore
    @State private var selectedDestination: ManagedPostDestination?
    let title: String
    let emptySubtitle: String
    let state: ScreenState
    let posts: [PostEntity]
    let mediaByPostId: [String: [MediaEntity]]
    let authors: [String: UserEntity]
    let currentUser: UserEntity
    let reload: () async -> Void
    let onLike: (PostEntity) async -> Void
    let onBookmark: (PostEntity) async -> Void
    let onRepost: (PostEntity) async -> Void
    let onQuoteRepost: (PostEntity, String) async -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                switch state {
                case .loading, .idle:
                    LoadingView()
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await reload() }
                    }
                case .empty:
                    EmptyStateView(title: title, subtitle: emptySubtitle, systemImage: "tray")
                        .padding(.top, 34)
                case .loaded:
                    if posts.isEmpty {
                        EmptyStateView(title: title, subtitle: emptySubtitle, systemImage: "tray")
                            .padding(.top, 34)
                    } else {
                        ForEach(posts) { post in
                            let displayedPost = postStore.post(id: post.id) ?? post
                            PostCardView(
                                post: displayedPost,
                                author: authors[displayedPost.authorId] ?? currentUser,
                                mediaItems: mediaByPostId[displayedPost.id] ?? [],
                                currentUser: currentUser,
                                onOpen: { selectedDestination = .post(postId: displayedPost.id, focusComments: false) },
                                onAuthor: { selectedDestination = .profile(userId: displayedPost.authorId) },
                                onTag: { selectedDestination = .topic(tag: $0) },
                                onComment: { selectedDestination = .post(postId: displayedPost.id, focusComments: true) },
                                onLike: { Task { await onLike(displayedPost) } },
                                onBookmark: { Task { await onBookmark(displayedPost) } },
                                onRepost: { Task { await onRepost(displayedPost) } },
                                onQuoteRepost: { content in Task { await onQuoteRepost(displayedPost, content) } }
                            )
                            .equatable()
                        }
                    }
                }
            }
            .padding(KaiXTheme.horizontalPadding)
            .kxTabBarSafeBottomPadding()
        }
        .kxPageBackground()
        .navigationTitle(title)
        .navigationDestination(item: $selectedDestination) { destination in
            switch destination {
            case .post(let postId, let focusComments):
                KXRoutedPostDetailView(
                    postId: postId,
                    currentUser: currentUser,
                    initialFocus: focusComments ? .comments : .none
                )
            case .profile(let userId):
                ManagedProfileRouteView(userId: userId, currentUser: currentUser)
            case .topic(let tag):
                ManagedTopicRouteView(tag: tag, currentUser: currentUser)
            }
        }
    }
}

private enum ManagedPostDestination: Identifiable, Hashable {
    case post(postId: String, focusComments: Bool)
    case profile(userId: String)
    case topic(tag: String)

    var id: String {
        switch self {
        case .post(let postId, let focusComments):
            "post:\(postId):\(focusComments)"
        case .profile(let userId):
            "profile:\(userId)"
        case .topic(let tag):
            "topic:\(tag.normalizedTopicName)"
        }
    }
}

private struct ManagedProfileRouteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var user: UserEntity?
    @State private var state: ScreenState = .idle

    let userId: String
    let currentUser: UserEntity

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                LoadingView()
            case .error(let message):
                ErrorStateView(message: message) {
                    Task { await load() }
                }
            case .empty:
                EmptyStateView(title: L("unknownUser", language), subtitle: L("noContent", language), systemImage: "person.crop.circle")
            case .loaded:
                ProfileView(currentUser: currentUser, profileUserId: userId, profileUser: user, tracksChrome: false, showsBackButton: true)
            }
        }
        .task(id: userId) {
            await load()
        }
    }

    private func load() async {
        state = .loading
        do {
            user = userId == currentUser.id ? currentUser : try await UserRepository(context: modelContext).fetchUser(id: userId)
            state = user == nil ? .empty : .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}

private struct ManagedTopicRouteView: View {
    let tag: String
    let currentUser: UserEntity

    var body: some View {
        TopicDetailView(tag: tag, currentUser: currentUser)
    }
}

private struct DraftCard: View {
    @Environment(\.appLanguage) private var language
    let draft: PostEntity
    let mediaItems: [MediaEntity]
    let currentUser: UserEntity
    let edit: () -> Void
    let publish: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AvatarView(user: currentUser, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("drafts", language))
                        .font(.headline.weight(.semibold))
                    Text(DateFormatterUtils.relativeText(from: draft.updatedAt, language: language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(draft.previewText.isEmpty ? L("placeholderPost", language) : draft.previewText)
                .font(.body)
                .foregroundStyle(draft.previewText.isEmpty ? .secondary : .primary)
                .lineLimit(4)

            MediaGridView(mediaItems: mediaItems)

            HStack {
                Button(L("continueEdit", language), action: edit)
                    .buttonStyle(.bordered)
                Spacer()
                Button(L("deleteDraft", language), role: .destructive, action: delete)
                    .buttonStyle(.bordered)
                Button(L("publishDraft", language), action: publish)
                    .buttonStyle(.borderedProminent)
            }
            .font(.subheadline.weight(.bold))
        }
        .padding(16)
        .kxGlassSurface(radius: KaiXTheme.cardRadius)
    }
}

private struct DraftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var content: String
    @State private var errorMessage: String?
    let draft: PostEntity
    let mediaItems: [MediaEntity]
    let currentUser: UserEntity
    let onDone: () -> Void

    init(draft: PostEntity, mediaItems: [MediaEntity], currentUser: UserEntity, onDone: @escaping () -> Void) {
        self.draft = draft
        self.mediaItems = mediaItems
        self.currentUser = currentUser
        self.onDone = onDone
        _content = State(initialValue: draft.content)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $content)
                    .font(.title3)
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .frame(minHeight: 220)
                    .kxGlassSurface(radius: KXRadius.lg)
                    .padding(KaiXTheme.horizontalPadding)
                    .padding(.top, 14)

                if !mediaItems.isEmpty {
                    MediaGridView(mediaItems: mediaItems)
                        .padding(KaiXTheme.horizontalPadding)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, KaiXTheme.horizontalPadding)
                }

                Spacer()
            }
            .kxPageBackground()
            .navigationTitle(L("continueEdit", language))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("cancel", language)) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("publish", language)) {
                        Task { await publish() }
                    }
                    .fontWeight(.black)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaItems.isEmpty)
                }
            }
        }
    }

    private func publish() async {
        do {
            let repository = PostRepository(context: modelContext)
            try await repository.updateDraft(post: draft, content: content)
            try await repository.publishDraft(post: draft)
            onDone()
            dismiss()
        } catch {
            errorMessage = error.kaixUserMessage
        }
    }
}

struct AppearanceSettingsView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.light.rawValue

    var body: some View {
        SettingsFormPage(title: L("appearance", language)) {
            ForEach(AppAppearance.allCases) { appearance in
                Button {
                    appAppearance = appearance.rawValue
                } label: {
                    HStack {
                        Text(appearance.title(language))
                        Spacer()
                        if appAppearance == appearance.rawValue {
                            Image(systemName: "checkmark")
                                .fontWeight(.black)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}

struct NotificationPreferencesView: View {
    @Environment(\.appLanguage) private var language
    @State private var notifyLikes = true
    @State private var notifyComments = true
    @State private var notifyReposts = true
    @State private var notifyFollows = true
    @State private var notifyMessages = true
    @State private var notifyInquiries = true
    @State private var notifySystem = true
    @State private var systemPermissionDenied = false
    let currentUser: UserEntity

    var body: some View {
        SettingsFormPage(title: L("notificationSettings", language)) {
            if systemPermissionDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("notifPermissionOff", language), systemImage: "bell.slash.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        Link(L("openSystemSettings", language), destination: url)
                            .font(.footnote.weight(.bold))
                    }
                }
                .padding(KXSpacing.md)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            }
            Toggle(L("likeNotifications", language), isOn: preferenceBinding(.like, $notifyLikes, serverKey: "push_likes"))
            Toggle(L("commentNotifications", language), isOn: preferenceBinding(.comment, $notifyComments, serverKey: "push_comments"))
            Toggle(L("repostNotifications", language), isOn: preferenceBinding(.repost, $notifyReposts, serverKey: nil))
            Toggle(L("followNotifications", language), isOn: preferenceBinding(.follow, $notifyFollows, serverKey: "push_follows"))
            Toggle(L("messageNotifications", language), isOn: messagePreferenceBinding)
            Toggle(L("inquiryNotifications", language), isOn: inquiryPreferenceBinding)
            Toggle(L("systemNotifications", language), isOn: preferenceBinding(.system, $notifySystem, serverKey: nil))
        }
        .onAppear {
            notifyLikes = NotificationPreferenceService.isEnabled(.like, recipientUserId: currentUser.id)
            notifyComments = NotificationPreferenceService.isEnabled(.comment, recipientUserId: currentUser.id)
            notifyReposts = NotificationPreferenceService.isEnabled(.repost, recipientUserId: currentUser.id)
            notifyFollows = NotificationPreferenceService.isEnabled(.follow, recipientUserId: currentUser.id)
            notifySystem = NotificationPreferenceService.isEnabled(.system, recipientUserId: currentUser.id)
            notifyMessages = UserDefaults.standard.object(forKey: messagePreferenceKey) as? Bool ?? true
            notifyInquiries = UserDefaults.standard.object(forKey: inquiryPreferenceKey) as? Bool ?? true
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            systemPermissionDenied = settings.authorizationStatus == .denied
            // Server is the source of truth when logged in — the same
            // toggles the Web settings page edits.
            guard KaiXBackend.token != nil else { return }
            guard let remote = try? await KaiXAPIClient.shared.settings() else { return }
            notifyLikes = remote.push_likes
            notifyComments = remote.push_comments
            notifyFollows = remote.push_follows
            notifyMessages = remote.push_messages
            NotificationPreferenceService.setEnabled(remote.push_likes, type: .like, recipientUserId: currentUser.id)
            NotificationPreferenceService.setEnabled(remote.push_comments, type: .comment, recipientUserId: currentUser.id)
            NotificationPreferenceService.setEnabled(remote.push_follows, type: .follow, recipientUserId: currentUser.id)
            UserDefaults.standard.set(remote.push_messages, forKey: messagePreferenceKey)
            notifyInquiries = remote.push_inquiries ?? true
            UserDefaults.standard.set(remote.push_inquiries ?? true, forKey: inquiryPreferenceKey)
        }
    }

    private func preferenceBinding(_ type: NotificationType, _ state: Binding<Bool>, serverKey: String?) -> Binding<Bool> {
        Binding {
            state.wrappedValue
        } set: { value in
            state.wrappedValue = value
            NotificationPreferenceService.setEnabled(value, type: type, recipientUserId: currentUser.id)
            // Mirror to the unified backend (best-effort) so Web shows the
            // same switches. repost/system have no server column yet.
            if let serverKey, KaiXBackend.token != nil {
                Task.detached { _ = try? await KaiXAPIClient.shared.updateSettings([serverKey: AnyEncodable(value)]) }
            }
        }
    }

    private var messagePreferenceKey: String {
        "notification.\(currentUser.id).message"
    }

    private var messagePreferenceBinding: Binding<Bool> {
        Binding {
            notifyMessages
        } set: { value in
            notifyMessages = value
            UserDefaults.standard.set(value, forKey: messagePreferenceKey)
            if KaiXBackend.token != nil {
                Task.detached { _ = try? await KaiXAPIClient.shared.updateSettings(["push_messages": AnyEncodable(value)]) }
            }
        }
    }

    // 申请/预约/线索 push category (listing inquiries, applications, bookings,
    // review results). Server-backed via push_inquiries; the APNs dispatcher
    // skips these pushes when off.
    private var inquiryPreferenceKey: String {
        "notification.\(currentUser.id).inquiries"
    }

    private var inquiryPreferenceBinding: Binding<Bool> {
        Binding {
            notifyInquiries
        } set: { value in
            notifyInquiries = value
            UserDefaults.standard.set(value, forKey: inquiryPreferenceKey)
            if KaiXBackend.token != nil {
                Task.detached { _ = try? await KaiXAPIClient.shared.updateSettings(["push_inquiries": AnyEncodable(value)]) }
            }
        }
    }
}

struct PrivacySettingsView: View {
    @Environment(\.appLanguage) private var language
    // Mirrors the server's `privacy_protect` / `privacy_allow_dm` —
    // identical semantics to the Web settings page. AppStorage keeps the
    // last known values for offline display.
    @AppStorage("privacyProtect") private var privacyProtect = false
    @AppStorage("privacyAllowDM") private var privacyAllowDM = "everyone"

    var body: some View {
        SettingsFormPage(title: L("privacySettings", language)) {
            Toggle(isOn: protectBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("privacyProtectTitle", language))
                    Text(L("privacyProtectSub", language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("dmPermission", language))
                    .font(.subheadline.weight(.semibold))
                Picker(L("dmPermission", language), selection: allowDMBinding) {
                    Text(L("dmEveryone", language)).tag("everyone")
                    Text(L("dmFollowing", language)).tag("following")
                    Text(L("dmNobody", language)).tag("nobody")
                }
                .pickerStyle(.segmented)
                Text(L("dmPrivacyFootnote", language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            Divider()

            NavigationLink {
                BlocklistSettingsView()
            } label: {
                HStack(spacing: KXSpacing.md) {
                    Label(L("blocklist", language), systemImage: "person.crop.circle.badge.xmark")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, KXSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .task {
            guard KaiXBackend.token != nil else { return }
            guard let remote = try? await KaiXAPIClient.shared.settings() else { return }
            privacyProtect = remote.privacy_protect
            if ["everyone", "following", "nobody"].contains(remote.privacy_allow_dm) {
                privacyAllowDM = remote.privacy_allow_dm
            }
        }
    }

    private var protectBinding: Binding<Bool> {
        Binding {
            privacyProtect
        } set: { value in
            privacyProtect = value
            if KaiXBackend.token != nil {
                Task.detached { _ = try? await KaiXAPIClient.shared.updateSettings(["privacy_protect": AnyEncodable(value)]) }
            }
        }
    }

    private var allowDMBinding: Binding<String> {
        Binding {
            privacyAllowDM
        } set: { value in
            privacyAllowDM = value
            if KaiXBackend.token != nil {
                Task.detached { _ = try? await KaiXAPIClient.shared.updateSettings(["privacy_allow_dm": AnyEncodable(value)]) }
            }
        }
    }
}

struct LoginDevicesView: View {
    @Environment(\.appLanguage) private var language
    @State private var devices: [KaiXDeviceDTO] = []
    @State private var state: ScreenState = .idle
    @State private var revoking: Set<String> = []

    var body: some View {
        SettingsFormPage(title: L("loginDevices", language)) {
            switch state {
            case .idle, .loading:
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, KXSpacing.lg)
            case .error(let message):
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    Label(message, systemImage: "xmark.octagon.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                    Button(L("retry", language)) { Task { await load() } }
                        .font(.footnote.weight(.semibold))
                }
                .padding(KXSpacing.md)
                .kxGlassSurface(radius: KXRadius.md)
            default:
                if devices.isEmpty {
                    Label(L("currentDevice", language), systemImage: "iphone")
                        .font(.headline.weight(.bold))
                    Text(L("noOtherDevices", language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(devices) { device in
                            deviceRow(device)
                            if device.id != devices.last?.id {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                    .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                            .stroke(KXColor.separator, lineWidth: 0.6)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func deviceRow(_ device: KaiXDeviceDTO) -> some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(KXColor.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let seen = deviceLastSeen(device) {
                    Text(seen)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if revoking.contains(device.id) {
                ProgressView().scaleEffect(0.8)
            } else {
                Button(L("revoke", language)) { Task { await revoke(device) } }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, 10)
    }

    private func deviceLastSeen(_ device: KaiXDeviceDTO) -> String? {
        guard let raw = device.last_seen_at, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: raw)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: raw)
        }
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func load() async {
        state = devices.isEmpty ? .loading : state
        do {
            devices = try await KaiXAPIClient.shared.loginDevices()
            state = .loaded
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }

    private func revoke(_ device: KaiXDeviceDTO) async {
        revoking.insert(device.id)
        defer { revoking.remove(device.id) }
        do {
            try await KaiXAPIClient.shared.revokeDevice(device.id)
            await load()
        } catch {
            state = .error(error.kaixUserMessage)
        }
    }
}

struct BlocklistSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @AppStorage("blockedUserIds") private var blockedUserIdsRaw = ""
    @State private var blockedUsers: [UserEntity] = []
    @State private var errorMessage: String?

    var body: some View {
        SettingsFormPage(title: L("blocklist", language)) {
            if blockedUserIds.isEmpty {
                Text(L("noBlockedUsers", language))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(blockedUserIds, id: \.self) { userId in
                        blockedUserRow(userId: userId)
                        if userId != blockedUserIds.last {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                        .stroke(KXColor.separator, lineWidth: 0.6)
                }
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    Label(errorMessage, systemImage: "xmark.octagon.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                    Button(L("retry", language)) {
                        Task { await loadBlockedUsers() }
                    }
                    .font(.footnote.weight(.semibold))
                }
                .padding(KXSpacing.md)
                .kxGlassSurface(radius: KXRadius.md)
            }
        }
        .task { await loadBlockedUsers() }
        .onChange(of: blockedUserIdsRaw) {
            Task { await loadBlockedUsers() }
        }
    }

    private var blockedUserIds: [String] {
        blockedUserIdsRaw
            .split(separator: "|")
            .map(String.init)
            .filter { !$0.isEmpty }
            .removingDuplicates()
    }

    private func blockedUserRow(userId: String) -> some View {
        let user = blockedUsers.first { $0.id == userId }

        return HStack(spacing: KXSpacing.md) {
            AvatarView(user: user, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(user?.displayName ?? L("unknownUser", language))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(user.map { "@\($0.username)" } ?? userId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(L("unblockUser", language)) {
                unblock(userId)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, 10)
    }

    private func loadBlockedUsers() async {
        // The server blocklist is the source of truth (shared with web);
        // merge any ids it returns into the local mirror that the rest of
        // the app uses for content filtering.
        if let serverBlocked = try? await KaiXAPIClient.shared.blockedUsers() {
            let merged = (blockedUserIds + serverBlocked.map(\.id)).removingDuplicates()
            let joined = merged.joined(separator: "|")
            if joined != blockedUserIdsRaw { blockedUserIdsRaw = joined }
        }
        guard !blockedUserIds.isEmpty else {
            blockedUsers = []
            errorMessage = nil
            return
        }
        do {
            blockedUsers = try await UserRepository(context: modelContext).fetchUsers(ids: Set(blockedUserIds))
            errorMessage = nil
        } catch {
            errorMessage = error.kaixUserMessage
        }
    }

    private func unblock(_ userId: String) {
        blockedUserIdsRaw = blockedUserIds
            .filter { $0 != userId }
            .joined(separator: "|")
        // Propagate to the server so the unblock sticks across devices/web.
        Task { try? await KaiXAPIClient.shared.setBlock(userId, false) }
    }
}

struct DataExportView: View {
    @Environment(\.appLanguage) private var language
    @State private var exported = false
    let postCount: Int
    let likeCount: Int
    let bookmarkCount: Int

    var body: some View {
        SettingsFormPage(title: L("dataExport", language)) {
            Text(L("localDataSummary", language))
                .font(.headline.weight(.semibold))
            Text("\(L("posts", language)) \(postCount) · \(L("likes", language)) \(likeCount) · \(L("bookmarks", language)) \(bookmarkCount)")
                .foregroundStyle(.secondary)
            Button(L("generateExport", language)) {
                exported = true
            }
                .buttonStyle(.borderedProminent)
            if exported {
                Text(L("exportSummaryGenerated", language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CacheSettingsView: View {
    @Environment(\.appLanguage) private var language
    @State private var showConfirm = false
    @State private var message: String?

    var body: some View {
        SettingsFormPage(title: L("clearCache", language)) {
            Text(L("cacheDescription", language))
                .foregroundStyle(.secondary)
            Button(L("clearCache", language), role: .destructive) {
                showConfirm = true
            }
            .buttonStyle(.borderedProminent)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(L("clearCacheConfirm", language), isPresented: $showConfirm, titleVisibility: .visible) {
            Button(L("clearCache", language), role: .destructive) {
                Task {
                    URLCache.shared.removeAllCachedResponses()
                    await ImageCacheService.shared.clear()
                    await VideoThumbnailService.shared.clear()
                    message = L("cacheCleared", language)
                }
            }
            Button(L("cancel", language), role: .cancel) {}
        }
    }
}

struct HelpCenterView: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        SettingsFormPage(title: L("helpCenter", language)) {
            Text(L("faq", language))
                .font(.headline.weight(.semibold))
            Text(L("helpPublishMedia", language))
                .foregroundStyle(.secondary)
            Text(L("helpLocalData", language))
                .foregroundStyle(.secondary)
        }
    }
}

struct FeedbackView: View {
    @Environment(\.appLanguage) private var language
    @State private var text = ""
    @State private var isSending = false
    @State private var submitted = false
    @State private var failed = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        SettingsFormPage(title: L("feedback", language)) {
            TextField(L("feedbackPlaceholder", language), text: $text, axis: .vertical)
                .lineLimit(5...8)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { _, _ in
                    // Editing again resets the result banners.
                    submitted = false
                    failed = false
                }
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 6) {
                    if isSending { KXSpinner(size: 18, lineWidth: 2.2, tint: .white) }
                    Text(isSending ? L("feedbackSending", language) : L("submitFeedback", language))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(trimmed.isEmpty || isSending)
            if submitted {
                Text(L("feedbackSaved", language))
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            if failed {
                Text(L("feedbackFailed", language))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            // Fallback channel if the user prefers email or is offline.
            if let mail = URL(string: "mailto:\(KaiXBackend.supportEmail)") {
                LegalLinkRow(icon: "envelope.fill", title: L("contactSupport", language), subtitle: KaiXBackend.supportEmail, url: mail)
                    .padding(.top, 4)
            }
        }
    }

    private func submit() async {
        guard !trimmed.isEmpty, !isSending else { return }
        isSending = true
        failed = false
        submitted = false
        defer { isSending = false }
        do {
            try await KaiXAPIClient.shared.submitFeedback(content: trimmed)
            submitted = true
            text = ""
        } catch {
            failed = true
        }
    }
}

struct AboutKaiXView: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        SettingsFormPage(title: L("aboutKaiX", language)) {
            Text("Machi")
                .font(.system(size: 38, weight: .black, design: .rounded))
            Text(L("aboutSubtitle", language))
                .foregroundStyle(.secondary)
            Text("\(L("version", language)) \(KaiXBackend.appVersionDisplay)")
                .font(.footnote.weight(.bold))

            Divider().padding(.vertical, 4)

            Text(L("legalAndSupport", language))
                .font(.headline.weight(.semibold))
            LegalLinkRow(icon: "hand.raised.fill", title: L("privacyPolicy", language), url: KaiXBackend.privacyPolicyURL)
            LegalLinkRow(icon: "doc.plaintext.fill", title: L("termsOfService", language), url: KaiXBackend.termsOfServiceURL)
            LegalLinkRow(icon: "building.columns.fill", title: L("commercialDisclosure", language), url: KaiXBackend.commercialDisclosureURL)
            if let mail = URL(string: "mailto:\(KaiXBackend.supportEmail)") {
                LegalLinkRow(icon: "envelope.fill", title: L("contactSupport", language), subtitle: KaiXBackend.supportEmail, url: mail)
            }
        }
    }
}

/// A tappable row that opens an external URL (web legal page or mailto).
/// Used for Privacy Policy / Terms / support so they're reachable in-app
/// as Apple requires. `Link` gives VoiceOver + a clear chevron affordance.
struct LegalLinkRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(KXColor.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
    }
}

struct DeveloperInfoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var counts: [(String, String)] = []
    let currentUser: UserEntity

    var body: some View {
        SettingsFormPage(title: L("developerInfo", language)) {
            Text(L("architecture", language))
                .font(.headline.weight(.semibold))
            Text("MVVM + Repository + Server API + Ephemeral Cache")
                .foregroundStyle(.secondary)
            Text(L("developerArchitectureText", language))
                .foregroundStyle(.secondary)

            Divider()

            Text(L("databaseStatus", language))
                .font(.headline.weight(.semibold))
            ForEach(counts, id: \.0) { item in
                HStack {
                    Text(item.0)
                    Spacer()
                    Text(item.1)
                        .fontWeight(.bold)
                }
                .font(.subheadline)
            }
        }
        .task { loadCounts() }
    }

    private func loadCounts() {
        let users = (try? modelContext.fetch(FetchDescriptor<UserEntity>()).count) ?? 0
        let posts = (try? modelContext.fetch(FetchDescriptor<PostEntity>()).count) ?? 0
        let comments = (try? modelContext.fetch(FetchDescriptor<CommentEntity>()).count) ?? 0
        let notifications = (try? modelContext.fetch(FetchDescriptor<NotificationEntity>()).count) ?? 0
        let threads = (try? modelContext.fetch(FetchDescriptor<MessageThreadEntity>()).count) ?? 0
        counts = [
            (L("currentUserId", language), currentUser.id),
            (L("databaseStatus", language), L("online", language)),
            (L("userCount", language), "\(users)"),
            (L("postCount", language), "\(posts)"),
            (L("commentCount", language), "\(comments)"),
            (L("notificationCount", language), "\(notifications)"),
            (L("threadCount", language), "\(threads)")
        ]
    }
}

struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @State private var confirmText = ""
    @State private var showFinalConfirm = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    let currentUser: UserEntity
    let onDeleted: () -> Void

    var body: some View {
        SettingsFormPage(title: L("deleteAccount", language)) {
            Text(L("deleteAccountDescription", language))
                .foregroundStyle(.secondary)
            TextField(L("enterDelete", language), text: $confirmText)
                .textInputAutocapitalization(.characters)
                .textFieldStyle(.roundedBorder)
            Button(L("deleteAccount", language), role: .destructive) {
                showFinalConfirm = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(confirmText != "DELETE" || isDeleting)
            if isDeleting {
                ProgressView()
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog(L("secondDeleteConfirm", language), isPresented: $showFinalConfirm, titleVisibility: .visible) {
            Button(L("confirmDelete", language), role: .destructive) {
                Task { await deleteAccount() }
            }
            Button(L("cancel", language), role: .cancel) {}
        }
    }

    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            if KaiXBackend.token != nil {
                try await KaiXAPIClient.shared.deleteMe()
            }
            try await UserRepository(context: modelContext).deleteAccount(user: currentUser)
            AuthService.shared.logout()
            onDeleted()
            dismiss()
        } catch {
            errorMessage = error.kaixUserMessage
        }
    }
}

struct SettingsFormPage<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .font(.body)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kxGlassSurface(radius: KXRadius.sheet)
            .padding(KaiXTheme.horizontalPadding)
            .padding(.top, KXSpacing.sm)
            .kxTabBarSafeBottomPadding()
        }
        .kxPageBackground()
        .navigationTitle(title)
    }
}
