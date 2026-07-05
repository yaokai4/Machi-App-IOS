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
        SettingsFormPage(title: L("contentLanguage", language)) {
            // Primary — single select
            Text(L("contentLanguagePrimary", language))
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: KXSpacing.xxs) {
                ForEach(primaryOptions) { option in
                    KXSelectRow(
                        title: option.title(language),
                        isSelected: languageManager.preferred == option,
                        action: { persistContentLanguage(preferred: option, fallbacks: languageManager.fallbacks) }
                    )
                }
            }
            Text(L("contentLanguageSubtitle", language))
                .font(.caption)
                .foregroundStyle(.secondary)

            // Fallbacks — multi select (tap toggles inclusion)
            Text(L("contentLanguageFallback", language))
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.top, KXSpacing.sm)
            VStack(spacing: KXSpacing.xxs) {
                ForEach(fallbackOptions) { option in
                    KXSelectRow(
                        title: option.title(language),
                        isSelected: languageManager.fallbacks.contains(option),
                        action: { toggleFallback(option) }
                    )
                }
            }
            Text(L("contentLanguageFallbackHint", language))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleFallback(_ option: ContentLanguage) {
        var current = languageManager.fallbacks
        if current.contains(option) {
            current.removeAll { $0 == option }
        } else {
            current.append(option)
        }
        persistContentLanguage(preferred: languageManager.preferred, fallbacks: current)
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
