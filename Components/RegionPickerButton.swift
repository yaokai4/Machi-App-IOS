import SwiftUI

/// Self-sizing region quick-switcher used in the home + discover headers
/// and (optionally) the composer. Replaces the inline button that
/// rendered "蒙..." when a long city name didn't fit a fixed-width
/// capsule.
///
/// Sizing rules:
/// - prefers `city`; falls back to `province · city` only when the
///   country has provinces (CN/JP/US) and the city/province codes
///   actually differ (so we don't print "上海 · 上海").
/// - `lineLimit(1)` + `minimumScaleFactor(0.85)` so short labels stay
///   bold while long ones quietly shrink one notch instead of ellipsing.
/// - `maxWidth` capped to 180 so it can sit alongside other header
///   chips without pushing them off-screen.
/// - When too narrow to show province+city, falls back to city only —
///   never to a "蒙..." half-truncated string.
struct RegionPickerButton: View {
    @Environment(\.appLanguage) private var language
    let region: KaiXRegionDirectory.Region?
    var compact: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                regionIcon
                Text(label)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .frame(maxWidth: 180, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .kxGlassCapsule()
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        guard let region else { return L("pickRegion", language) }
        // Province + city only when it actually adds information.
        // Country with provinces (CN/JP/US) and province != city codes.
        let countryHasProvinces = KaiXRegionDirectory
            .countries.first(where: { $0.code == region.countryCode })?
            .hasProvinces ?? false
        if countryHasProvinces,
           !region.provinceName.isEmpty,
           region.provinceCode != region.cityCode,
           region.provinceName != region.cityName {
            // For CN we render "浙江 · 杭州" — JP/US likewise. If the
            // combined label gets too long, the .minimumScaleFactor on
            // the Text will shrink it instead of clipping; if it's
            // still too wide, fall back to the city alone.
            let combined = "\(region.provinceName) · \(region.cityName)"
            return combined.count > 8 ? region.cityName : combined
        }
        return region.cityName
    }

    @ViewBuilder
    private var regionIcon: some View {
        if let region {
            Text(region.countryEmoji)
                .font(.system(size: compact ? 13 : 15))
        } else {
            Image(systemName: "globe.asia.australia.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(KXColor.accent)
        }
    }

    private var accessibilityLabel: String {
        guard let region else { return L("pickRegion", language) }
        return region.displayName
    }
}

#Preview {
    VStack(spacing: 12) {
        RegionPickerButton(region: nil) {}
        RegionPickerButton(
            region: KaiXRegionDirectory.resolve(regionCode: "ca.toronto")
        ) {}
        RegionPickerButton(
            region: KaiXRegionDirectory.resolve(regionCode: "cn.zhejiang.hangzhou")
        ) {}
        RegionPickerButton(
            region: KaiXRegionDirectory.resolve(regionCode: "jp.tokyo.tokyo")
        ) {}
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
