import SwiftUI

/// Six-way primary category picker for the city channel. Replaces the
/// 17-tab horizontal scroll the user complained about. Each primary
/// has its own set of secondary chips, surfaced by
/// `CitySecondaryFilterChips`.
struct CityPrimaryCategoryTabs: View {
    @Environment(\.appLanguage) private var language
    @Binding var selection: CityChannel.Primary

    var body: some View {
        KXFadingHScroll {
            HStack(spacing: KXSpacing.sm) {
                ForEach(CityChannel.Primary.tabbed) { primary in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            selection = primary
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: primary.icon)
                                .font(.system(size: 12, weight: .bold))
                            Text(primary.title(language))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .kxGlassCapsule(isSelected: selection == primary)
                        .foregroundStyle(selection == primary ? KXColor.accent : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.vertical, KXSpacing.sm)
        }
        .background(KXColor.cardBackground.opacity(0.78))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.18)
        }
    }
}
