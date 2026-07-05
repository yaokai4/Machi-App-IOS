import SwiftUI

/// Second-level chip row shown under the primary tabs. Only renders
/// the channels associated with the currently-selected primary so the
/// user is never confronted with the whole 17-channel list at once.
struct CitySecondaryFilterChips: View {
    @Environment(\.appLanguage) private var language
    let primary: CityChannel.Primary
    @Binding var channel: CityChannel

    var body: some View {
        KXFadingHScroll {
            HStack(spacing: KXSpacing.sm) {
                ForEach(primary.channels) { entry in
                    Button {
                        withAnimation(KXMotion.select) {
                            channel = entry
                        }
                    } label: {
                        Text(entry.title(language))
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, KXSpacing.md)
                            .frame(height: 30)
                            .kxGlassCapsule(isSelected: channel == entry)
                            .foregroundStyle(channel == entry ? KXColor.accent : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.vertical, 7)
        }
        .background(KXColor.softBackground.opacity(0.6))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.14)
        }
    }
}
