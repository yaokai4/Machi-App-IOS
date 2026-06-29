import SwiftUI
import UIKit

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
    @ObservedObject private var location = LocationService.shared
    @State private var showLocationDeniedAlert = false

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

                    if searchText.isEmpty {
                        locateButton
                    }

                    if !searchText.isEmpty {
                        searchResults
                    } else if allowsAnyCountry {
                        // 国家列表本身就能点进去选城市，再叠一个
                        // 「切换本国城市」区块是重复入口 —— 只留国家列表。
                        section(L("switchCountry", language)) {
                            countryList
                        }
                    } else if let landingCountry {
                        // 固定国家场景（首页/发现页切城市）：直接展示该国的
                        // 省份/城市钻取。
                        section(L("switchLocalRegion", language)) {
                            landingCountryDrilldown(landingCountry)
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
            .alert(L("locationUnavailableTitle", language), isPresented: $showLocationDeniedAlert) {
                Button(L("locationOpenSettings", language)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button(L("cancel", language), role: .cancel) {}
            } message: {
                Text(L("locationDeniedMessage", language))
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
            .navigationDestination(for: CircleRoute.self) { route in
                CircleCityListView(country: route.country, circleCode: route.circleCode, circleName: route.circleName) { region in
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

    private var isLocating: Bool {
        location.phase == .requesting || location.phase == .locating
    }

    /// One-tap "use my current city" — requests When-In-Use permission, takes a
    /// single fix, reverse-geocodes it, and delivers the matched region.
    private var locateButton: some View {
        Button {
            Task {
                if let region = await location.detectRegion() {
                    deliver(region)
                } else if location.isDenied {
                    showLocationDeniedAlert = true
                }
            }
        } label: {
            HStack(spacing: KXSpacing.sm) {
                Group {
                    if isLocating {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.headline)
                            .foregroundStyle(KXColor.accent)
                    }
                }
                .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("useCurrentLocation", language))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(isLocating ? L("locatingCurrentCity", language) : L("autoDetectCity", language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !isLocating {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, KXSpacing.md)
            .frame(minHeight: 58)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous)
                    .strokeBorder(KXColor.accent.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLocating)
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
                .accessibilityLabel("清除")
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
            if country.code == "jp" {
                ForEach(KaiXRegionDirectory.jpMetroCircles) { circle in
                    NavigationLink(value: CircleRoute(country: country, circleCode: circle.code, circleName: circle.name)) {
                        HStack(spacing: KXSpacing.sm) {
                            Text(circle.name).font(.body)
                            Spacer()
                            Text(metroCircleCountLabel(KaiXRegionDirectory.regionsForMetroCircle(circle.code).count))
                                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            Image(systemName: "chevron.right").font(.footnote.weight(.medium)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.25)
                }
            } else if country.hasProvinces {
                ForEach(KaiXRegionDirectory.provinces(for: country.code)) { province in
                    NavigationLink(value: ProvinceRoute(country: country, province: province)) {
                        HStack(spacing: KXSpacing.sm) {
                            Text(KaiXRegionDirectory.localizedProvinceName(countryCode: country.code, province: province, language: language)).font(.body)
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
                            Text(KaiXRegionDirectory.localizedCityName(countryCode: country.code, city: city, language: language)).font(.body)
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
                        Text(KaiXRegionDirectory.localizedCountryName(country, language: language)).font(.body)
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
                                    Text(KaiXRegionDirectory.localizedShortLabel(region, language: language)).font(.body)
                                    Text(regionSubtitle(region))
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
            // Match across scripts so "东京 / 東京 / tokyo / jp.tokyo" all hit,
            // regardless of the app's current display language.
            region.countryName.localizedCaseInsensitiveContains(query)
            || KaiXRegionDirectory.localizedDisplayName(region, language: language).localizedCaseInsensitiveContains(query)
            || KaiXRegionDirectory.localizedDisplayName(region, language: .ja).localizedCaseInsensitiveContains(query)
            || KaiXRegionDirectory.localizedDisplayName(region, language: .en).localizedCaseInsensitiveContains(query)
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

    private func regionSubtitle(_ region: KaiXRegionDirectory.Region) -> String {
        let country = KaiXRegionDirectory.localizedCountryName(
            .init(code: region.countryCode, name: region.countryName, emoji: region.countryEmoji, tier: 1, hasProvinces: !region.provinceCode.isEmpty),
            language: language
        )
        if region.provinceName.isEmpty { return country }
        let province = KaiXRegionDirectory.localizedProvinceName(
            countryCode: region.countryCode,
            province: .init(code: region.provinceCode, name: region.provinceName),
            language: language
        )
        return "\(country) · \(province)"
    }

    private func metroCircleCountLabel(_ count: Int) -> String {
        KXListingCopy.pickText(language, "\(count) 城", "\(count) 都市", "\(count) cities")
    }
}

private struct ProvinceRoute: Hashable {
    let country: KaiXRegionDirectory.Country
    let province: KaiXRegionDirectory.Province
}

private struct CircleRoute: Hashable {
    let country: KaiXRegionDirectory.Country
    let circleCode: String
    let circleName: String
}

/// Cities inside a Japan metro circle (关东圈 → 东京/横滨/川崎…），with a
/// trailing prefecture label so the origin stays clear.
private struct CircleCityListView: View {
    @Environment(\.appLanguage) private var language
    let country: KaiXRegionDirectory.Country
    let circleCode: String
    let circleName: String
    let onSelect: (KaiXRegionDirectory.Region) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(KaiXRegionDirectory.regionsForMetroCircle(circleCode), id: \.region.regionCode) { pair in
                    Button {
                        onSelect(pair.region)
                    } label: {
                        HStack {
                            Text(pair.region.cityName).font(.body)
                            Spacer()
                            Text(KaiXRegionDirectory.localizedProvinceName(countryCode: country.code, province: pair.province, language: language))
                                .font(.caption.weight(.semibold))
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
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, KXSpacing.md)
        }
        .kxPageBackground()
        .navigationTitle(circleName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProvinceListView: View {
    @Environment(\.appLanguage) private var language
    let country: KaiXRegionDirectory.Country
    let onSelect: (KaiXRegionDirectory.Region) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if country.code == "jp" {
                    // 日本：先选都市圈（关东圈/关西圈/名古屋…），再进城市。
                    ForEach(KaiXRegionDirectory.jpMetroCircles) { circle in
                        NavigationLink(value: CircleRoute(country: country, circleCode: circle.code, circleName: circle.name)) {
                            HStack {
                                Text(circle.name).font(.body)
                                Spacer()
                                Text(metroCircleCountLabel(KaiXRegionDirectory.regionsForMetroCircle(circle.code).count))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
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
                } else if country.hasProvinces {
                    ForEach(KaiXRegionDirectory.provinces(for: country.code)) { province in
                        NavigationLink(value: ProvinceRoute(country: country, province: province)) {
                            HStack {
                                Text(KaiXRegionDirectory.localizedProvinceName(countryCode: country.code, province: province, language: language)).font(.body)
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
                                Text(KaiXRegionDirectory.localizedCityName(countryCode: country.code, city: city, language: language)).font(.body)
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
        .navigationTitle(KaiXRegionDirectory.localizedCountryName(country, language: language))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metroCircleCountLabel(_ count: Int) -> String {
        KXListingCopy.pickText(language, "\(count) 城", "\(count) 都市", "\(count) cities")
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
                            Text(KaiXRegionDirectory.localizedCityName(countryCode: country.code, provinceCode: province.code, city: city, language: language)).font(.body)
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
        .navigationTitle(KaiXRegionDirectory.localizedProvinceName(countryCode: country.code, province: province, language: language))
        .navigationBarTitleDisplayMode(.inline)
    }
}
