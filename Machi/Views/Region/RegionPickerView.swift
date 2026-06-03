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
/// a search box and shortcut rows for "popular cities" + "recently
/// used" up top. Built on top of the in-process `KaiXRegionDirectory`
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

    private var supportedCountryCodes: Set<String> {
        ["jp", "cn", "us", "ca"]
    }

    private var availableCountries: [KaiXRegionDirectory.Country] {
        let supported = KaiXRegionDirectory.countries.filter { supportedCountryCodes.contains($0.code) }
        guard let allowedCountryCode else { return supported }
        return supported.filter { $0.code == allowedCountryCode }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    searchField

                    if !searchText.isEmpty {
                        searchResults
                    } else {
                        if !store.recent.isEmpty {
                            section(L("recentRegions", language)) {
                                regionChipsGrid(store.recent)
                            }
                        }
                        if allowsAnyCountry {
                            section("热门国内城市") {
                                regionChipsGrid(domesticPopularRegions)
                            }
                            section("海外热门城市") {
                                overseasPopularGroups
                            }
                        } else {
                            section(L("availableCities", language)) {
                                regionChipsGrid(countryPopularRegions)
                            }
                        }
                        // The "中国 · 按省份选择" block lived here in
                        // an earlier draft, but it duplicated what the
                        // country list below already offers (tap 中国
                        // → 省份 → 城市). Removed per user feedback —
                        // the country list is the single canonical
                        // drill-down path.
                        if allowsAnyCountry {
                            section(L("allCountries", language)) {
                                countryList
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
        .onAppear {
            if allowsAnyCountry,
               let initialCountry,
               let country = KaiXRegionDirectory.country(code: initialCountry) {
                path.append(country)
            }
        }
    }

    // MARK: - sub views

    private var domesticPopularRegions: [KaiXRegionDirectory.Region] {
        canonicalRegions(for: "cn")
    }

    private var countryPopularRegions: [KaiXRegionDirectory.Region] {
        guard let allowedCountryCode else { return KaiXRegionDirectory.popular }
        let canonical = canonicalRegions(for: allowedCountryCode)
        return canonical.isEmpty ? KaiXRegionDirectory.popular.filter { $0.countryCode == allowedCountryCode } : canonical
    }

    private func canonicalRegions(for countryCode: String) -> [KaiXRegionDirectory.Region] {
        let codes: [String]
        switch countryCode.lowercased() {
        case "jp":
            codes = ["jp.tokyo.tokyo", "jp.osaka.osaka", "jp.kyoto.kyoto"]
        case "cn":
            codes = ["cn.shanghai.shanghai", "cn.zhejiang.hangzhou"]
        case "us":
            codes = ["us.ca.la"]
        case "ca":
            codes = ["ca.montreal"]
        default:
            codes = []
        }
        return codes.compactMap { KaiXRegionDirectory.resolve(regionCode: $0) }
    }

    private var overseasPopularRegions: [KaiXRegionDirectory.Region] {
        ["jp", "us", "ca"].flatMap { canonicalRegions(for: $0) }
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

    private var overseasPopularGroups: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            ForEach(groupedOverseasCountries, id: \.country.code) { group in
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    Text("\(group.country.emoji) \(group.country.name)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    regionChipsGrid(group.regions)
                }
            }
        }
    }

    private var groupedOverseasCountries: [(country: KaiXRegionDirectory.Country, regions: [KaiXRegionDirectory.Region])] {
        KaiXRegionDirectory.countries.compactMap { country in
            guard country.code != "cn" else { return nil }
            let regions = overseasPopularRegions.filter { $0.countryCode == country.code }
            return regions.isEmpty ? nil : (country, regions)
        }
    }

    private func regionChipsGrid(_ regions: [KaiXRegionDirectory.Region]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(regions, id: \.regionCode) { region in
                Button {
                    deliver(region)
                } label: {
                    Text(region.headerLabel)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .kxGlassCapsule(isSelected: region.regionCode == store.current?.regionCode)
                }
                .buttonStyle(.plain)
            }
        }
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
                Text("没有匹配的地区")
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
        let supportedCanonicalRegions = ["jp", "cn", "us", "ca"].flatMap { canonicalRegions(for: $0) }
        if let allowedCountryCode {
            return canonicalRegions(for: allowedCountryCode).filter { region in
                region.countryName.localizedCaseInsensitiveContains(query)
                || region.countryCode.contains(query)
                || region.provinceName.localizedCaseInsensitiveContains(query)
                || region.provinceCode.contains(query)
                || region.cityName.localizedCaseInsensitiveContains(query)
                || region.cityCode.contains(query)
            }
        }
        return supportedCanonicalRegions.filter { region in
            region.countryName.localizedCaseInsensitiveContains(query)
            || region.countryCode.contains(query)
            || region.provinceName.localizedCaseInsensitiveContains(query)
            || region.provinceCode.contains(query)
            || region.cityName.localizedCaseInsensitiveContains(query)
            || region.cityCode.contains(query)
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
                if !canonicalRegions.isEmpty {
                    ForEach(canonicalRegions, id: \.regionCode) { region in
                        Button {
                            onSelect(region)
                        } label: {
                            HStack {
                                Text(region.cityName).font(.body)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.25)
                    }
                } else if country.hasProvinces {
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

    private var canonicalRegions: [KaiXRegionDirectory.Region] {
        let codes: [String]
        switch country.code.lowercased() {
        case "jp":
            codes = ["jp.tokyo.tokyo", "jp.osaka.osaka", "jp.kyoto.kyoto"]
        case "cn":
            codes = ["cn.shanghai.shanghai", "cn.zhejiang.hangzhou"]
        case "us":
            codes = ["us.ca.la"]
        case "ca":
            codes = ["ca.montreal"]
        default:
            codes = []
        }
        return codes.compactMap { KaiXRegionDirectory.resolve(regionCode: $0) }
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
