import AuthenticationServices
import SwiftData
import SwiftUI
import UIKit

struct AuthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue
    @StateObject private var viewModel = AuthViewModel()
    @State private var isPasswordVisible = false
    @State private var isShowingRegionPicker = false
    @State private var isGoogleLoading = false
    @State private var appleNonce = ""
    @FocusState private var captchaFieldFocused: Bool

    let onAuthenticated: (UserEntity) -> Void
    /// When provided, shows a "browse as guest" affordance so people can
    /// look around before creating an account (App Store 5.1.1(v)).
    var onBrowseAsGuest: (() -> Void)? = nil

    private var isFormReady: Bool {
        viewModel.validate(language: language).isEmpty
    }

    /// Terms + Privacy consent shown under the register button (App Store
    /// requirement). Markdown links open the hosted pages in Safari.
    private var registerAgreement: AttributedString {
        let terms = "https://machicity.com/terms"
        let privacy = "https://machicity.com/privacy"
        let raw: String
        switch language {
        case .ja:
            raw = "登録すると[利用規約](\(terms))と[プライバシーポリシー](\(privacy))に同意したものとみなされます"
        case .en:
            raw = "By creating an account you agree to our [Terms of Service](\(terms)) and [Privacy Policy](\(privacy))"
        default:
            raw = "注册即代表你已阅读并同意[《用户协议》](\(terms))与[《隐私政策》](\(privacy))"
        }
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    private var usernameBinding: Binding<String> {
        Binding {
            viewModel.username
        } set: { value in
            viewModel.username = viewModel.mode == .register ? AuthValidation.sanitizedRegisterHandle(value) : value
            viewModel.clearError(for: .username)
        }
    }

    private var displayNameBinding: Binding<String> {
        Binding {
            viewModel.displayName
        } set: { value in
            viewModel.displayName = AuthValidation.limitedDisplayName(value)
            viewModel.clearError(for: .displayName)
        }
    }

    private var emailBinding: Binding<String> {
        Binding {
            viewModel.email
        } set: { value in
            viewModel.email = value.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.clearError(for: .email)
        }
    }

    private var passwordBinding: Binding<String> {
        Binding {
            viewModel.password
        } set: { value in
            viewModel.password = value
            viewModel.clearError(for: .password)
        }
    }

    private var codeBinding: Binding<String> {
        Binding {
            viewModel.code
        } set: { value in
            viewModel.code = String(value.filter(\.isNumber).prefix(6))
            viewModel.clearError(for: .code)
        }
    }

    private var captchaBinding: Binding<String> {
        Binding {
            viewModel.captchaCode
        } set: { value in
            viewModel.captchaCode = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
            viewModel.clearError(for: .captcha)
        }
    }

    @ViewBuilder
    private func availabilityHint(_ state: AuthViewModel.FieldAvailability, takenKey: String, okKey: String) -> some View {
        switch state {
        case .checking:
            Label(L("authChecking", language), systemImage: "ellipsis")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        case .available:
            Label(L(okKey, language), systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(.green)
        case .taken:
            Label(L(takenKey, language), systemImage: "xmark.circle.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(Color.red.opacity(0.78))
        case .idle:
            EmptyView()
        }
    }

    var body: some View {
        ZStack {
            KXGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    authHeader
                    authCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
        }
        .animation(.snappy(duration: 0.2), value: viewModel.mode)
        .onChange(of: viewModel.mode) { _, _ in
            viewModel.fieldErrors = [:]
            viewModel.errorMessage = nil
        }
        .sheet(isPresented: $isShowingRegionPicker) {
            RegionPickerView(
                initialCountry: viewModel.selectedRegion?.countryCode,
                allowsAnyCountry: true
            ) { region in
                viewModel.selectedRegion = region
                viewModel.clearError(for: .region)
            }
        }
    }

    private var authHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [KXColor.accent, KXColor.accent.opacity(0.74)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 62, height: 62)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: KXColor.accent.opacity(0.36), radius: 14, y: 7)
                    Image(systemName: "bolt.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(spacing: 10) {
                    Menu {
                        ForEach([AppLanguage.zh, .ja, .en]) { option in
                            Button(option.title) {
                                appLanguageCode = option.rawValue
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                            Text(language.title)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("auth.language")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .kxGlassCapsule()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L("appName", language))
                    .font(.system(size: 52, weight: .black, design: .rounded))
                Text(L("welcomeBack", language))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            // Removed the three "国家 / 城市 / 生活" stat pills and the
            // "本地数据库在线" indicator — decorative placeholders that
            // didn't communicate actual product state. Header now reads:
            // logo + language switcher + brand title + tagline, then
            // straight into the login card.
        }
    }

    private var authCard: some View {
        VStack(spacing: 18) {
            AuthModePicker(selection: $viewModel.mode)

            Button {
                Task {
                    guard !isGoogleLoading else { return }
                    isGoogleLoading = true
                    defer { isGoogleLoading = false }
                    do {
                        let user = try await GoogleAuthService.shared.signIn(context: modelContext)
                        onAuthenticated(user)
                    } catch {
                        viewModel.errorMessage = L("googleLoginFailed", language)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if isGoogleLoading {
                        KXSpinner(size: 22, lineWidth: 2.4)
                    } else {
                        Image("GoogleLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .frame(width: 26, height: 26)
                            .background(.white, in: Circle())
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.06)))
                    }
                    Text(isGoogleLoading ? L("googleSigningIn", language) : L("continueWithGoogle", language))
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(KXColor.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .kxGlassCapsule(isSelected: false)
            }
            .buttonStyle(.plain)
            .disabled(isGoogleLoading || viewModel.isLoading)
            .accessibilityIdentifier("auth.google")

            SignInWithAppleButton(.continue) { request in
                let nonce = AppleAuthService.randomNonce()
                appleNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleAuthService.sha256(nonce)
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    Task {
                        do {
                            let user = try await AppleAuthService.completeSignIn(
                                authorization: authorization,
                                rawNonce: appleNonce,
                                context: modelContext
                            )
                            onAuthenticated(user)
                        } catch {
                            viewModel.errorMessage = L("appleLoginFailed", language)
                        }
                    }
                case .failure(let error):
                    // A user cancel is not an error worth surfacing.
                    let nsError = error as NSError
                    let canceled = nsError.domain == ASAuthorizationError.errorDomain
                        && nsError.code == ASAuthorizationError.Code.canceled.rawValue
                    if !canceled {
                        viewModel.errorMessage = L("appleLoginFailed", language)
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .clipShape(Capsule())
            .shadow(color: KXColor.glassShadow.opacity(0.5), radius: 8, y: 3)
            .disabled(isGoogleLoading || viewModel.isLoading)
            .accessibilityIdentifier("auth.apple")

            VStack(spacing: 14) {
                AuthInputField(
                    title: viewModel.mode == .register ? L("username", language) : L("loginIdentifier", language),
                    placeholder: viewModel.mode == .register ? "your_handle" : L("loginIdentifier", language),
                    text: usernameBinding,
                    icon: "at",
                    accessibilityIdentifier: "auth.username",
                    error: viewModel.fieldError(.username),
                    keyboardType: viewModel.mode == .register ? .asciiCapable : .emailAddress
                )

                if viewModel.mode == .register {
                    availabilityHint(viewModel.usernameAvailability, takenKey: "handleTaken", okKey: "authUsernameAvailable")

                    AuthInputField(
                        title: L("displayName", language),
                        placeholder: "Machi User",
                        text: displayNameBinding,
                        icon: "person.text.rectangle",
                        accessibilityIdentifier: "auth.displayName",
                        error: viewModel.fieldError(.displayName)
                    )

                    AuthInputField(
                        title: L("email", language),
                        placeholder: "you@example.com",
                        text: emailBinding,
                        icon: "envelope",
                        accessibilityIdentifier: "auth.email",
                        error: viewModel.fieldError(.email),
                        keyboardType: .emailAddress
                    )
                    availabilityHint(viewModel.emailAvailability, takenKey: "authEmailTaken", okKey: "authEmailAvailable")

                    // Solving the captcha is what unlocks "send code" — the
                    // email-code request is the bot-abuse vector being gated.
                    // Once the code is sent the challenge is spent, so the row
                    // collapses into a "verified" confirmation instead of
                    // wiping itself and re-prompting.
                    if viewModel.captchaEnabled {
                        if viewModel.captchaVerified {
                            AuthCaptchaVerifiedRow()
                        } else {
                            AuthCaptchaField(
                                code: captchaBinding,
                                image: viewModel.captchaImage,
                                loading: viewModel.captchaLoading,
                                error: viewModel.fieldError(.captcha),
                                focus: $captchaFieldFocused,
                                onRefresh: { Task { await viewModel.refreshCaptcha() } }
                            )
                        }
                    }

                    AuthCodeField(
                        code: codeBinding,
                        sending: viewModel.sendingCode,
                        cooldown: viewModel.codeCooldown,
                        canSend: viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                        error: viewModel.fieldError(.code),
                        onSend: { Task { await viewModel.sendCode(language: language) } }
                    )

                    AuthRegionField(region: viewModel.selectedRegion, error: viewModel.fieldError(.region)) {
                        isShowingRegionPicker = true
                    }
                }

                AuthPasswordField(
                    password: passwordBinding,
                    isVisible: $isPasswordVisible,
                    placeholder: viewModel.mode == .login ? L("enterPassword", language) : L("passwordMin", language),
                    error: viewModel.fieldError(.password)
                )

                if viewModel.mode == .login, viewModel.captchaEnabled {
                    AuthCaptchaField(
                        code: captchaBinding,
                        image: viewModel.captchaImage,
                        loading: viewModel.captchaLoading,
                        error: viewModel.fieldError(.captcha),
                        focus: $captchaFieldFocused,
                        onRefresh: { Task { await viewModel.refreshCaptcha() } }
                    )
                }
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(KXColor.warningSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let info = viewModel.infoMessage {
                Label(info, systemImage: "checkmark.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(KXColor.successSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task {
                    if let user = await viewModel.submit(context: modelContext, language: language) {
                        onAuthenticated(user)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                if viewModel.isLoading {
                    KXSpinner(size: 22, lineWidth: 2.4)
                    }
                    Text(viewModel.mode == .login ? L("loginMachi", language) : L("createAccount", language))
                    Image(systemName: "arrow.right")
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(isFormReady ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    if isFormReady {
                        Capsule().fill(
                            LinearGradient(
                                colors: [KXColor.accent, KXColor.accent.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    } else {
                        Capsule().fill(KXColor.softBackground)
                            .overlay(Capsule().stroke(KXColor.separator, lineWidth: 0.7))
                    }
                }
                .clipShape(Capsule())
                .shadow(color: isFormReady ? KXColor.accent.opacity(0.30) : .clear, radius: 14, y: 7)
            }
            .disabled(!isFormReady || viewModel.isLoading)
            .buttonStyle(KXPressableStyle(scale: 0.98, dim: 0.9))
            .accessibilityIdentifier("auth.submit")

            if viewModel.mode == .register {
                Text(registerAgreement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tint(KXColor.accent)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .accessibilityIdentifier("auth.agreement")
            }

            HStack(spacing: 10) {
                AuthFeature(icon: "house.fill", title: L("housing", language))
                AuthFeature(icon: "briefcase.fill", title: L("work", language))
                AuthFeature(icon: "bag.fill", title: L("secondhand", language))
                AuthFeature(icon: "calendar", title: L("events", language))
            }

            if let onBrowseAsGuest {
                Button(action: onBrowseAsGuest) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                        Text(L("browseAsGuest", language))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("auth.browseAsGuest")
            }
        }
        .padding(18)
        .kxGlassSurface(radius: KXRadius.sheet)
        .task(id: viewModel.username) {
            guard viewModel.mode == .register else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            await viewModel.checkUsernameAvailability(language: language)
        }
        .task(id: viewModel.email) {
            guard viewModel.mode == .register else { return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            await viewModel.checkEmailAvailability(language: language)
        }
        // Runs on appear and again on every login↔register switch — the two
        // scenes can be enforced independently server-side.
        .task(id: viewModel.mode) {
            await viewModel.refreshCaptcha()
        }
        // A rejected captcha re-arms a fresh image and pulls focus straight to
        // the input so the user can retype without hunting for the field.
        .onChange(of: viewModel.captchaFocusRequest) { _, _ in
            captchaFieldFocused = true
        }
    }
}

/// Collapsed confirmation shown after the captcha has done its job (the email
/// code was sent). Reassures the user they don't need to solve it again.
private struct AuthCaptchaVerifiedRow: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("authCaptcha", language))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.green)
                Text(L("authCaptchaVerified", language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.successSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.28))
            )
        }
        .transition(.opacity)
    }
}

private struct AuthCodeField: View {
    @Environment(\.appLanguage) private var language
    @Binding var code: String
    let sending: Bool
    let cooldown: Int
    let canSend: Bool
    var error: String?
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("authVerificationCode", language))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                HStack(spacing: 13) {
                    Image(systemName: "number")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("auth.code")
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .kxGlassSurface(radius: KXRadius.md, stroke: error == nil ? KXColor.glassStroke : Color.red.opacity(0.36))

                Button(action: onSend) {
                    HStack(spacing: 6) {
                        if sending { KXSpinner(size: 16, lineWidth: 2) }
                        Text(cooldown > 0 ? "\(cooldown)s" : L("authSendCode", language))
                            .font(.subheadline.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .foregroundStyle((canSend && cooldown == 0 && !sending) ? KXColor.accent : .secondary)
                    .kxGlassCapsule(isSelected: canSend && cooldown == 0 && !sending)
                }
                .buttonStyle(.plain)
                .disabled(!canSend || cooldown > 0 || sending)
                .accessibilityIdentifier("auth.sendCode")
            }

            if let error {
                AuthFieldErrorText(error)
            }
        }
    }
}

private struct AuthCaptchaField: View {
    @Environment(\.appLanguage) private var language
    @Binding var code: String
    let image: Data?
    let loading: Bool
    var error: String?
    var focus: FocusState<Bool>.Binding
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(L("authCaptcha", language))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(L("authCaptchaRefreshHint", language))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                HStack(spacing: 13) {
                    Image(systemName: "checkmark.shield")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    TextField(L("authCaptchaPlaceholder", language), text: $code)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused(focus)
                        .accessibilityIdentifier("auth.captcha")
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .kxGlassSurface(radius: KXRadius.md, stroke: error == nil ? KXColor.glassStroke : Color.red.opacity(0.36))

                Button(action: onRefresh) {
                    Group {
                        if loading {
                            KXSpinner(size: 24, lineWidth: 2.4)
                        } else if let image, let uiImage = UIImage(data: image) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .padding(.horizontal, 4)
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.subheadline.weight(.bold))
                                Text(L("authCaptchaLoadFailed", language))
                                    .font(.caption2.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(2)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        }
                    }
                    .frame(width: 128, height: 56)
                    // Captcha PNGs come on a fixed light background; pin the
                    // tile to white so they look intentional in dark mode too.
                    .background(.white, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                            .strokeBorder(KXColor.glassStroke)
                    )
                }
                .buttonStyle(.plain)
                .disabled(loading)
                .accessibilityIdentifier("auth.captcha.refresh")
                .accessibilityLabel(L("authCaptchaRefreshHint", language))
            }

            if let error {
                AuthFieldErrorText(error)
            }
        }
    }
}

private struct AuthRegionField: View {
    @Environment(\.appLanguage) private var language
    let region: KaiXRegionDirectory.Region?
    let error: String?
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("registerRegion", language))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Button(action: onTap) {
                HStack(spacing: 13) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(region.map { KaiXRegionDirectory.localizedDisplayName($0, language: language) } ?? L("selectRegisterRegion", language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(region == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        if let region {
                            Text(L("registerRegionHelp", language).replacingOccurrences(
                                of: "{country}",
                                with: KaiXRegionDirectory.localizedCountryName(
                                    .init(code: region.countryCode, name: region.countryName, emoji: region.countryEmoji, tier: 1, hasProvinces: !region.provinceCode.isEmpty),
                                    language: language
                                )
                            ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
                .kxGlassSurface(radius: KXRadius.md, stroke: error == nil ? KXColor.glassStroke : Color.red.opacity(0.36))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("auth.region")

            if let error {
                AuthFieldErrorText(error)
            }
        }
    }
}

private struct AuthModePicker: View {
    @Environment(\.appLanguage) private var language
    @Binding var selection: AuthViewModel.Mode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AuthViewModel.Mode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode == .login ? L("login", language) : L("register", language))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .kxGlassCapsule(isSelected: selection == mode)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(mode == .login ? "auth.mode.login" : "auth.mode.register")
            }
        }
        .padding(4)
        .kxGlassCapsule()
    }
}

private struct AuthInputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    let accessibilityIdentifier: String
    var error: String?
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(accessibilityIdentifier)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .kxGlassSurface(radius: KXRadius.md, stroke: error == nil ? KXColor.glassStroke : Color.red.opacity(0.36))

            if let error {
                AuthFieldErrorText(error)
            }
        }
    }
}

private struct AuthPasswordField: View {
    @Environment(\.appLanguage) private var language
    @Binding var password: String
    @Binding var isVisible: Bool
    let placeholder: String
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("password", language))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 13) {
                Image(systemName: "lock")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Group {
                    if isVisible {
                        TextField(placeholder, text: $password)
                    } else {
                        SecureField(placeholder, text: $password)
                    }
                }
                .accessibilityIdentifier("auth.password")

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.blue.opacity(0.65))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isVisible ? "隐藏密码" : "显示密码")
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .kxGlassSurface(radius: KXRadius.md, stroke: error == nil ? KXColor.glassStroke : Color.red.opacity(0.36))

            if let error {
                AuthFieldErrorText(error)
            }
        }
    }
}

private struct AuthFieldErrorText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.red.opacity(0.78))
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AuthFeature: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .kxGlassSurface(radius: KXRadius.md)
    }
}
