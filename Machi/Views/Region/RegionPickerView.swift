import SwiftUI

struct RegionSelectorView: View {
    var initialCountry: String? = nil
    var allowsAnyCountry: Bool = true
    var onSelect: (KaiXRegionDirectory.Region) -> Void

    var body: some View {
        RegionPickerView(
            initialCountry: initialCountry,
            allowsAnyCountry: allowsAnyCountry,
            onSelect: onSelect
        )
    }
}

/// Modal region picker. Three-pane navigation (国家 → 省 → 城市) with
/// a search box, a current-country city drilldown, and an optional
/// country switcher. Built on top of the in-process `KaiXRegionDirectory`
/// — no network calls, fully usable offline.
///
/// Result is delivered via `onSelect(region)`. Callers are free to
/// also store the result in `RegionStore.shared` themselves; this
/// view intentionally doesn't do that so it can be used both for
/// "set my browsing region" and "tag this single post with a region".
struct RegionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @ObservedObject private var store = RegionStore.shared

    var initialCountry: String? = nil
    var allowsAnyCountry: Bool = true
    var onSelect: (KaiXRegionDirectory.Region) -> Void

    @State private var searchText = ""
    @State private var path: NavigationPath = NavigationPath()

    private var allowedCountryCode: String? {
        guard !allowsAnyCountry, let initialCountry else { return nil }
        return initialCountry.lowercased()
    }

    private var availableCountries: [KaiXRegionDirectory.Country] {
        guard let allowedCountryCode else { return KaiXRegionDirectory.countries }
        return KaiXRegionDirectory.countries.filter { $0.code == allowedCountryCode }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    searchField

                    if !searchText.isEmpty {
                        searchResults
                    } else {
                        if allowsAnyCountry {
                            section(L("switchCountry", language)) {
                                countryList
                            }
                        }
                        if let landingCountry {
                            section(L("switchLocalRegion", language)) {
                                landingCountryDrilldown(landingCountry)
                            }
                        }
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, KXSpacing.md)
                .padding(.bottom, KXSpacing.xl)
            }
            .kxPageBackground()
            .navigationTitle(L("pickRegion", language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel", language)) { dismiss() }
                }
            }
            .navigationDestination(for: KaiXRegionDirectory.Country.self) { country in
                ProvinceListView(country: country) { region in
                    deliver(region)
                }
            }
            .navigationDestination(for: ProvinceRoute.self) { route in
                CityListView(country: route.country, province: route.province) { region in
                    deliver(region)
                }
            }
        }
    }

    // MARK: - sub views

    private var landingCountry: KaiXRegionDirectory.Country? {
        let code = (allowedCountryCode ?? initialCountry ?? store.current?.countryCode ?? "jp").lowercased()
        return availableCountries.first(where: { $0.code == code }) ?? availableCountries.first
    }

    private var searchField: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(L("searchRegion", language), text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, KXSpacing.md)
        .frame(height: 46)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func landingCountryDrilldown(_ country: KaiXRegionDirectory.Country) -> some View {
        VStack(spacing: 0) {
            if country.hasProvinces {
                ForEach(KaiXRegionDirectory.provinces(for: country.code)) { province in
                    NavigationLink(value: ProvinceRoute(country: country, province: province)) {
                        HStack(spacing: KXSpacing.sm) {
                            Text(province.name).font(.body)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.25)
                }
            } else {
                ForEach(KaiXRegionDirectory.cities(country: country.code, province: nil)) { city in
                    Button {
                        if let region = KaiXRegionDirectory.make(country: country.code, province: nil, city: city.code) {
                            deliver(region)
                        }
                    } label: {
                        HStack(spacing: KXSpacing.sm) {
                            Text(city.name).font(.body)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.25)
                }
            }
        }
        .padding(.horizontal, KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private var countryList: some View {
        VStack(spacing: 0) {
            ForEach(availableCountries) { country in
                NavigationLink(value: country) {
                    HStack(spacing: KXSpacing.sm) {
                        Text(country.emoji).font(.title3)
                        Text(country.name).font(.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.25)
            }
        }
        .padding(.horizontal, KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    @ViewBuilder
    private var searchResults: some View {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            EmptyView()
        } else {
            let matches = searchMatches(query: q)
            if matches.isEmpty {
                Text(L("regionNoMatches", language))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, KXSpacing.xl)
            } else {
                VStack(spacing: 0) {
                    ForEach(matches, id: \.regionCode) { region in
                        Button { deliver(region) } label: {
                            HStack(spacing: KXSpacing.sm) {
                                Text(region.countryEmoji).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(region.cityName).font(.body)
                                    Text("\(region.countryName)\(region.provinceName.isEmpty ? "" : " · \(region.provinceName)")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.25)
                    }
                }
                .padding(.horizontal, KXSpacing.md)
                .kxGlassSurface(radius: KXRadius.lg)
            }
        }
    }

    private func searchMatches(query: String) -> [KaiXRegionDirectory.Region] {
        Array(allSelectableRegions().filter { region in
            region.countryName.localizedCaseInsensitiveContains(query)
            || region.countryCode.contains(query)
            || region.provinceName.localizedCaseInsensitiveContains(query)
            || region.provinceCode.contains(query)
            || region.cityName.localizedCaseInsensitiveContains(query)
            || region.cityCode.contains(query)
            || region.regionCode.contains(query)
        }.prefix(80))
    }

    private func allSelectableRegions() -> [KaiXRegionDirectory.Region] {
        availableCountries.flatMap { country in
            if country.hasProvinces {
                return KaiXRegionDirectory.provinces(for: country.code).flatMap { province in
                    KaiXRegionDirectory.cities(country: country.code, province: province.code).compactMap { city in
                        KaiXRegionDirectory.make(country: country.code, province: province.code, city: city.code)
                    }
                }
            }
            return KaiXRegionDirectory.cities(country: country.code, province: nil).compactMap { city in
                KaiXRegionDirectory.make(country: country.code, province: nil, city: city.code)
            }
        }
    }

    private func deliver(_ region: KaiXRegionDirectory.Region) {
        onSelect(region)
        dismiss()
    }
}

private struct ProvinceRoute: Hashable {
    let country: KaiXRegionDirectory.Country
    let province: KaiXRegionDirectory.Province
}

private struct ProvinceListView: View {
    @Environment(\.appLanguage) private var language
    let country: KaiXRegionDirectory.Country
    let onSelect: (KaiXRegionDirectory.Region) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if country.hasProvinces {
                    ForEach(KaiXRegionDirectory.provinces(for: country.code)) { province in
                        NavigationLink(value: ProvinceRoute(country: country, province: province)) {
                            HStack {
                                Text(province.name).font(.body)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.25)
                    }
                } else {
                    // Flat country — jump straight to cities.
                    ForEach(KaiXRegionDirectory.cities(country: country.code, province: nil)) { city in
                        Button {
                            if let region = KaiXRegionDirectory.make(country: country.code, province: nil, city: city.code) {
                                onSelect(region)
                            }
                        } label: {
                            HStack {
                                Text(city.name).font(.body)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.25)
                    }
                }
            }
            .padding(.horizontal, KXSpacing.md)
            .kxGlassSurface(radius: KXRadius.lg)
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, KXSpacing.md)
        }
        .kxPageBackground()
        .navigationTitle(country.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CityListView: View {
    @Environment(\.appLanguage) private var language
    let country: KaiXRegionDirectory.Country
    let province: KaiXRegionDirectory.Province
    let onSelect: (KaiXRegionDirectory.Region) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(KaiXRegionDirectory.cities(country: country.code, province: province.code)) { city in
                    Button {
                        if let region = KaiXRegionDirectory.make(country: country.code, province: province.code, city: city.code) {
                            onSelect(region)
                        }
                    } label: {
                        HStack {
                            Text(city.name).font(.body)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.25)
                }
            }
            .padding(.horizontal, KXSpacing.md)
            .kxGlassSurface(radius: KXRadius.lg)
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, KXSpacing.md)
        }
        .kxPageBackground()
        .navigationTitle(province.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
