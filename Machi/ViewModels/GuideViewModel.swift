import Foundation
import Combine

@MainActor
final class GuideViewModel: ObservableObject {
    @Published private(set) var home: KaiXGuideHomeResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var searchResults: [KaiXGuideArticleDTO] = []
    @Published private(set) var isSearching = false
    @Published var searchText = ""

    private var loadedCountry = ""
    private var loadedLanguage = ""

    var isComingSoon: Bool {
        home?.status == "coming_soon"
    }

    func load(country: String, force: Bool = false) async {
        let normalizedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let language = currentGuideLanguage()
        if !force, loadedCountry == normalizedCountry, loadedLanguage == language, home != nil { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            home = try await KaiXAPIClient.shared.guideHome(country: normalizedCountry.isEmpty ? "jp" : normalizedCountry, language: language)
            loadedCountry = normalizedCountry
            loadedLanguage = language
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search(country: String, keyword: String? = nil) async {
        let q = (keyword ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let response = try await KaiXAPIClient.shared.guideArticles(country: country, language: currentGuideLanguage(), keyword: q, pageSize: 20)
            searchResults = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
    }

    private func currentGuideLanguage() -> String {
        let appLanguage = AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? "")
        switch appLanguage {
        case .ja:
            return "ja"
        case .en:
            return "en"
        case .zh, .system:
            return "zh-CN"
        }
    }
}
