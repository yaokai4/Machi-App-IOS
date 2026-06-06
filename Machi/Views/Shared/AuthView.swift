import SwiftData
import SwiftUI
import UIKit

struct AuthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue
    @StateObject private var viewModel = AuthViewModel()
    @State private var isPasswordVisible = false
    @State private var isShowingRegionPicker = false
    @State private var isGoogleLoading = false

    let onAuthenticated: (UserEntity) -> Void
    /// When provided, shows a "browse as guest" affordance so people can
    /// look around before creating an account (App Store 5.1.1(v)).
    var onBrowseAsGuest: (() -> Void)? = nil

    private var isFormReady: Bool {
        viewModel.validate(language: language).isEmpty
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
                        .fill(KXColor.accent.opacity(0.18))
                        .glassEffect(KXGlass.selected, in: Circle())
                        .frame(width: 62, height: 62)
                    Image(systemName: "bolt.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(KXColor.accent)
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

                    HStack(spacing: 7) {
                        Circle()
                            .fill(.green)
                            .frame(width: 9, height: 9)
                        Text(L("localDatabaseOnline", language))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 13)
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
            // Removed the three "国家 / 城市 / 生活" stat pills — they
            // were decorative placeholders that didn't communicate
            // actual product state and added visual weight above the
            // form. Header now reads: logo + DB-online indicator +
            // brand title + tagline, then straight into the login
            // card.
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
                        ProgressView()
                            .tint(KXColor.accent)
                    } else {
                        Text("G")
                            .font(.headline.weight(.black))
                            .foregroundStyle(KXColor.accent)
                            .frame(width: 24, height: 24)
                            .background(.white, in: Circle())
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

            VStack(spacing: 14) {
                AuthInputField(
                    title: L("username", language),
                    placeholder: "your_handle",
                    text: usernameBinding,
                    icon: "at",
                    accessibilityIdentifier: "auth.username",
                    error: viewModel.fieldError(.username),
                    keyboardType: .asciiCapable
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
                    ProgressView()
                        .tint(KXColor.accent)
                    }
                    Text(viewModel.mode == .login ? L("loginMachi", language) : L("createAccount", language))
                    Image(systemName: "arrow.right")
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(isFormReady ? KXColor.accent : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .kxGlassCapsule(isSelected: isFormReady)
            }
            .disabled(!isFormReady || viewModel.isLoading)
            .buttonStyle(.plain)
            .accessibilityIdentifier("auth.submit")

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
                        if sending { ProgressView().scaleEffect(0.8) }
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
                        Text(region?.displayName ?? L("selectRegisterRegion", language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(region == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        if let region {
                            Text(L("registerRegionHelp", language).replacingOccurrences(of: "{country}", with: region.countryName))
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
