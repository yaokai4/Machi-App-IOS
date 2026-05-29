import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedLanguageRaw: String = AppLanguage.system.rawValue

    func language(from storedValue: String) -> AppLanguage {
        AppLanguage(rawValue: storedValue) ?? .system
    }
}
