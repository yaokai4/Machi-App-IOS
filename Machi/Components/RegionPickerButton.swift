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
            HStack(spacing: compact ? 6 : 7) {
                regionIcon
                Text(label)
                    .font(.system(size: compact ? 14 : 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(KXColor.accent.opacity(compact ? 0.85 : 0.7))
            }
            .padding(.leading, compact ? 6 : 10)
            .padding(.trailing, compact ? 10 : 12)
            .frame(minHeight: compact ? 38 : 36)
            .frame(maxWidth: compact ? 150 : 180, alignment: .leading)
            .fixedSize(horizontal: !compact, vertical: false)
            .background(Color(.systemBackground).opacity(0.92), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(KXColor.accent.opacity(compact ? 0.22 : 0.16), lineWidth: 1)
            }
            .shadow(color: KXColor.accent.opacity(0.10), radius: 14, y: 5)
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
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "location.fill")
                    .font(.system(size: compact ? 13 : 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 28 : 28, height: compact ? 28 : 28)
                    .background(KXColor.accent, in: Circle())
                Text(region.countryEmoji)
                    .font(.system(size: compact ? 9 : 10))
                    .padding(1)
                    .background(Color(.systemBackground), in: Circle())
                    .offset(x: 4, y: 4)
            }
        } else {
            Image(systemName: "location.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: compact ? 28 : 28, height: compact ? 28 : 28)
                .background(KXColor.accent, in: Circle())
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
