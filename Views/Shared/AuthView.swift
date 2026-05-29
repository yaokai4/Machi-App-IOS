import SwiftData
import SwiftUI
import UIKit

struct AuthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @StateObject private var viewModel = AuthViewModel()
    @State private var isPasswordVisible = false
    @State private var isShowingRegionPicker = false

    let onAuthenticated: (UserEntity) -> Void

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
        }
        .padding(18)
        .kxGlassSurface(radius: KXRadius.sheet)
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
