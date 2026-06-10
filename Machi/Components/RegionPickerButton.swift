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
/// - `lineLimit(1)` + `minimumScaleFactor(0.78)` so short labels stay
///   bold while long ones quietly shrink one notch instead of ellipsing.
/// - `maxWidth` capped to 180 (118 in compact headers) so it can sit alongside other header
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
                Text(region?.countryEmoji ?? "🌐")
                    .font(.system(size: compact ? 17 : 18))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: compact ? 13 : 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(compact ? 0.72 : 0.78)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(KXColor.accent.opacity(compact ? 0.85 : 0.7))
            }
            .padding(.leading, compact ? 10 : 12)
            .padding(.trailing, compact ? 10 : 12)
            .frame(minHeight: compact ? 40 : 38)
            .frame(maxWidth: compact ? 118 : 180, alignment: .leading)
            .fixedSize(horizontal: !compact, vertical: false)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color(.systemBackground).opacity(0.72), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(KXColor.separator.opacity(0.55), lineWidth: 0.8)
            }
            .shadow(color: KXColor.glassShadow.opacity(0.14), radius: 10, y: 4)
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
