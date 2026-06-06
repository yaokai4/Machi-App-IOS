import SwiftUI
import SwiftData

/// Browsing-region settings — separate from the user's declared home
/// (the latter lives in their profile). Pushing through here updates
/// the global `RegionStore` so every feed query immediately rebinds
/// to the new city without rewriting the profile city shown on the
/// account page.
struct RegionSettingsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var regionStore = RegionStore.shared
    @State private var isShowingPicker = false

    let currentUser: UserEntity

    var body: some View {
        Form {
            Section(L("currentRegion", language)) {
                if let region = regionStore.current {
                    HStack(spacing: 10) {
                        Text(region.countryEmoji)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(region.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(region.regionCode)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    Text(L("pickRegion", language))
                        .foregroundStyle(.secondary)
                }
                Button(L("changeRegion", language)) {
                    isShowingPicker = true
                }
            }

        }
        .navigationTitle(L("regionSettings", language))
        .sheet(isPresented: $isShowingPicker) {
            RegionPickerView(
                initialCountry: regionStore.current?.countryCode ?? (currentUser.country.isEmpty ? "jp" : currentUser.country),
                allowsAnyCountry: true
            ) { region in
                regionStore.setCurrent(region)
                persistBrowsingRegion(region)
            }
        }
    }

    private func persistBrowsingRegion(_ region: KaiXRegionDirectory.Region) {
        currentUser.country = region.countryCode
        currentUser.province = region.provinceCode
        currentUser.city = region.cityCode
        currentUser.currentRegionCode = region.regionCode
        currentUser.recentRegionCodes = regionStore.recent.map(\.regionCode)
        try? modelContext.save()
        guard KaiXBackend.token != nil else { return }
        Task {
            _ = try? await KaiXAPIClient.shared.updateRegionLanguage([
                "country": region.countryCode,
                "province": region.provinceCode,
                "city": region.cityCode,
                "current_region_code": region.regionCode
            ])
        }
    }
}
