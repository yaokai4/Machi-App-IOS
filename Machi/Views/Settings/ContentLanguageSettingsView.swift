import SwiftUI
import SwiftData

/// User-facing settings for the content-language preferences
/// described in `LanguageManager`. The picker writes to
/// `LanguageManager.shared`, which broadcasts on `objectWillChange`;
/// every feed observing the manager refreshes immediately.
struct ContentLanguageSettingsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var message: String?

    let currentUser: UserEntity

    private let primaryOptions: [ContentLanguage] = [
        .followApp, .zh, .en, .ja, .ko, .fr, .es, .multi
    ]
    private let fallbackOptions: [ContentLanguage] = [
        .zh, .en, .ja, .ko, .fr, .es
    ]

    var body: some View {
        Form {
            Section {
                ForEach(primaryOptions) { option in
                    Button {
                        persistContentLanguage(preferred: option, fallbacks: languageManager.fallbacks)
                    } label: {
                        HStack {
                            Text(option.title(language))
                                .foregroundStyle(.primary)
                            Spacer()
                            if languageManager.preferred == option {
                                Image(systemName: "checkmark")
                                    .fontWeight(.bold)
                                    .foregroundStyle(KXColor.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(L("contentLanguagePrimary", language))
            } footer: {
                Text(L("contentLanguageSubtitle", language))
            }

            Section {
                ForEach(fallbackOptions) { option in
                    let isOn = Binding(
                        get: { languageManager.fallbacks.contains(option) },
                        set: { newValue in
                            var current = languageManager.fallbacks
                            if newValue {
                                if !current.contains(option) { current.append(option) }
                            } else {
                                current.removeAll { $0 == option }
                            }
                            persistContentLanguage(preferred: languageManager.preferred, fallbacks: current)
                        }
                    )
                    Toggle(option.title(language), isOn: isOn)
                }
            } header: {
                Text(L("contentLanguageFallback", language))
            } footer: {
                Text(L("contentLanguageFallbackHint", language))
            }

            if let message {
                Section {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L("contentLanguage", language))
    }

    private func persistContentLanguage(preferred: ContentLanguage, fallbacks: [ContentLanguage]) {
        var normalizedFallbacks: [ContentLanguage] = []
        for fallback in fallbacks where !normalizedFallbacks.contains(fallback) {
            normalizedFallbacks.append(fallback)
        }
        languageManager.preferred = preferred
        languageManager.fallbacks = normalizedFallbacks
        currentUser.contentLanguagePreference = preferred.rawValue
        currentUser.preferredContentLanguages = normalizedFallbacks.map(\.rawValue)
        try? modelContext.save()
        guard KaiXBackend.token != nil else { return }

        let patch = [
            "content_language_preference": preferred.rawValue,
            "preferred_content_languages": normalizedFallbacks.map(\.rawValue).joined(separator: "|")
        ]
        Task {
            do {
                let dto = try await KaiXAPIClient.shared.updateRegionLanguage(patch)
                await MainActor.run {
                    UserRepository.apply(dto, to: currentUser)
                    try? modelContext.save()
                    message = nil
                }
            } catch {
                await MainActor.run {
                    message = error.kaixUserMessage
                }
            }
        }
    }
}
