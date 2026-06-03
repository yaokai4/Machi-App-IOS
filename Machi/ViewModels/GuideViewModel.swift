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

    var isComingSoon: Bool {
        home?.status == "coming_soon"
    }

    func load(country: String, force: Bool = false) async {
        let normalizedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !force, loadedCountry == normalizedCountry, home != nil { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            home = try await KaiXAPIClient.shared.guideHome(country: normalizedCountry.isEmpty ? "jp" : normalizedCountry)
            loadedCountry = normalizedCountry
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
            let response = try await KaiXAPIClient.shared.guideArticles(country: country, keyword: q, pageSize: 20)
            searchResults = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
    }
}
