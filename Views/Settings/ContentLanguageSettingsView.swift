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
                        languageManager.preferred = option
                        currentUser.contentLanguagePreference = option.rawValue
                        try? modelContext.save()
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
                            languageManager.fallbacks = current
                            currentUser.preferredContentLanguages = current.map(\.rawValue)
                            try? modelContext.save()
                        }
                    )
                    Toggle(option.title(language), isOn: isOn)
                }
            } header: {
                Text(L("contentLanguageFallback", language))
            } footer: {
                Text(L("contentLanguageFallbackHint", language))
            }
        }
        .navigationTitle(L("contentLanguage", language))
    }
}
