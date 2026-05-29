import SwiftUI

enum KXSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let screen: CGFloat = 16
    static let card: CGFloat = 12
}

enum KXRadius {
    static let xs: CGFloat = 7
    static let sm: CGFloat = 9
    static let md: CGFloat = 13
    static let lg: CGFloat = 20
    static let card: CGFloat = 18
    static let sheet: CGFloat = 24
    static let pill: CGFloat = 999
}

enum KXTypography {
    static let largeTitle = Font.system(size: 30, weight: .semibold)
    static let title = Font.system(size: 21, weight: .semibold)
    static let section = Font.subheadline.weight(.semibold)
    static let body = Font.callout
    static let bodyEmphasis = Font.callout.weight(.semibold)
    static let meta = Font.caption
    static let metaEmphasis = Font.caption.weight(.semibold)
    static let tiny = Font.caption2
}

enum KXColor {
    static let pageBackground = Color(.secondarySystemGroupedBackground)
    static let cardBackground = Color(.systemBackground)
    static let elevatedBackground = Color(.systemBackground)
    static let softBackground = Color(.tertiarySystemGroupedBackground)
    static let separator = Color(.separator).opacity(0.42)
    static let glassStroke = Color(.separator).opacity(0.64)
    static let glassTint = Color(.systemBackground).opacity(0.10)
    static let glassSurfaceTint = Color(.systemBackground).opacity(0.86)
    static let glassControlTint = Color(.systemBackground).opacity(0.74)
    static let glassBarTint = Color(.systemBackground).opacity(0.66)
    static let glassHighlight = Color.white.opacity(0.34)
    static let glassShadow = Color.black.opacity(0.075)
    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.11)
    static let heat = Color(red: 0.85, green: 0.45, blue: 0.12)
    static let dangerSoft = Color.red.opacity(0.10)
    static let warningSoft = Color.orange.opacity(0.12)
    static let successSoft = Color.green.opacity(0.10)
    static let infoSoft = Color.blue.opacity(0.10)
    static let rankGold = Color(red: 1.000, green: 0.678, blue: 0.145)
    static let rankCoral = Color(red: 1.000, green: 0.346, blue: 0.384)
    static let rankViolet = Color(red: 0.514, green: 0.353, blue: 0.953)
    static let rankTeal = Color(red: 0.000, green: 0.651, blue: 0.561)
    static let rankSky = Color(red: 0.063, green: 0.557, blue: 0.969)
}

enum KXGlass {
    static let surface = Glass.regular.tint(KXColor.glassSurfaceTint)
    static let control = Glass.regular.tint(KXColor.glassControlTint)
    static let selected = Glass.regular.tint(KXColor.accent.opacity(0.13))
    static let bar = Glass.regular.tint(KXColor.glassBarTint)
    static let clear = Glass.clear
}

enum KXMaterial {
    static let page = Material.ultraThin
    static let card = Material.thin
    static let bar = Material.regular
    static let control = Material.ultraThin
}

enum KXIconSize {
    static let xs: CGFloat = 12
    static let sm: CGFloat = 16
    static let md: CGFloat = 20
    static let lg: CGFloat = 24
}

enum KXAvatarSize {
    static let xs: CGFloat = 30
    static let sm: CGFloat = 36
    static let md: CGFloat = 40
    static let lg: CGFloat = 56
    static let profile: CGFloat = 82
}

struct KXCard<Content: View>: View {
    var padding: CGFloat = KXSpacing.card
    var radius: CGFloat = KXRadius.card
    let content: Content

    init(padding: CGFloat = KXSpacing.card, radius: CGFloat = KXRadius.card, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .kxGlassSurface(radius: radius)
    }
}

struct KXAvatar: View {
    let user: UserEntity?
    var size: CGFloat = KXAvatarSize.md

    var body: some View {
        AvatarView(user: user, size: size)
    }
}

struct KXVerifiedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.blue)
            .accessibilityLabel("Verified")
    }
}

struct KXSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(KXTypography.section)
            .foregroundStyle(.secondary)
            .padding(.horizontal, KXSpacing.xs)
    }
}

struct KXSegmentedControl<Item: Hashable, Label: View>: View {
    let items: [Item]
    @Binding var selection: Item
    var itemMinWidth: CGFloat
    var itemHeight: CGFloat
    let label: (Item) -> Label

    init(
        _ items: [Item],
        selection: Binding<Item>,
        itemMinWidth: CGFloat = 64,
        itemHeight: CGFloat = 38,
        @ViewBuilder label: @escaping (Item) -> Label
    ) {
        self.items = items
        self._selection = selection
        self.itemMinWidth = itemMinWidth
        self.itemHeight = itemHeight
        self.label = label
    }

    var body: some View {
        HStack(spacing: KXSpacing.xs) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = item
                    }
                } label: {
                    label(item)
                        .font(.subheadline.weight(selection == item ? .bold : .semibold))
                        .foregroundStyle(selection == item ? KXColor.accent : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .truncationMode(.tail)
                        .allowsTightening(true)
                        .frame(minWidth: itemMinWidth)
                        .frame(maxWidth: .infinity)
                        .frame(height: itemHeight)
                        .padding(.horizontal, KXSpacing.xs)
                        .background {
                            if selection == item {
                                KXSelectedSegmentBackground()
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(KXColor.softBackground.opacity(0.92))
        }
        .overlay(Capsule().stroke(KXColor.glassStroke.opacity(0.72), lineWidth: 0.8))
    }
}

private struct KXSelectedSegmentBackground: View {
    var body: some View {
        Capsule()
            .fill(KXColor.cardBackground.opacity(0.96))
            .shadow(color: KXColor.glassShadow.opacity(0.22), radius: 5, y: 2)
            .overlay {
                Capsule()
                    .stroke(KXColor.glassStroke.opacity(0.75), lineWidth: 0.75)
            }
    }
}

struct KXEmptyState: View {
    let title: String
    let subtitle: String
    var systemImage: String = "tray"

    var body: some View {
        EmptyStateView(title: title, subtitle: subtitle, systemImage: systemImage)
    }
}

struct KXFloatingComposeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: KXIconSize.md, weight: .semibold))
                .foregroundStyle(KXColor.accent)
                .frame(width: 54, height: 54)
                .background {
                    Circle()
                        .fill(KXColor.accent.opacity(0.09))
                }
                .glassEffect(KXGlass.selected.interactive(), in: Circle())
                .overlay(Circle().stroke(KXColor.glassStroke, lineWidth: 1))
                .shadow(color: KXColor.glassShadow, radius: 7, y: 3)
        }
        .buttonStyle(.plain)
    }
}

struct KXGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // Single soft gradient instead of stacking two: cuts the
        // background draw cost in half and looks calmer / less
        // "busy". Falls back to a solid system colour when the user
        // has reduce-transparency on.
        Group {
            if reduceTransparency {
                KXColor.pageBackground
            } else {
                LinearGradient(
                    colors: backgroundPalette,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }

    private var backgroundPalette: [Color] {
        if colorScheme == .dark {
            return [
                Color(.systemGroupedBackground),
                Color(red: 0.062, green: 0.072, blue: 0.072),
            ]
        }
        return [
            Color(.systemGroupedBackground),
            Color(red: 0.966, green: 0.972, blue: 0.978),
        ]
    }
}

extension View {
    /// Shared product surface for cards and panels.
    func kxGlassSurface(
        radius: CGFloat = KXRadius.card,
        stroke: Color = KXColor.glassStroke,
        elevated: Bool = false
    ) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(KXColor.cardBackground)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: elevated ? 0.9 : 0.75)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(KXColor.glassHighlight.opacity(elevated ? 0.65 : 0.48), lineWidth: 0.45)
                    .padding(0.8)
            }
            .modifier(_SurfaceShadow(elevated: elevated))
    }

    func kxGlassCapsule(isSelected: Bool = false) -> some View {
        self
            .background {
                Capsule()
                    .fill(isSelected ? KXColor.accent.opacity(0.12) : KXColor.glassControlTint)
            }
            .glassEffect((isSelected ? KXGlass.selected : KXGlass.control).interactive(), in: Capsule())
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? KXColor.accent.opacity(0.55) : KXColor.glassStroke, lineWidth: isSelected ? 0.95 : 0.75)
            }
            .overlay {
                Capsule()
                    .stroke(KXColor.glassHighlight.opacity(isSelected ? 0.85 : 0.62), lineWidth: 0.45)
                    .padding(0.8)
            }
            .shadow(color: KXColor.glassShadow.opacity(isSelected ? 0.55 : 0.32), radius: isSelected ? 6 : 3, y: isSelected ? 2 : 1)
    }

    func kxGlassCircle(isSelected: Bool = false) -> some View {
        self
            .background {
                Circle()
                    .fill(isSelected ? KXColor.accent.opacity(0.13) : KXColor.glassControlTint)
            }
            .glassEffect((isSelected ? KXGlass.selected : KXGlass.control).interactive(), in: Circle())
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(isSelected ? KXColor.accent.opacity(0.56) : KXColor.glassStroke, lineWidth: isSelected ? 0.95 : 0.75)
            }
            .overlay {
                Circle()
                    .stroke(KXColor.glassHighlight.opacity(isSelected ? 0.85 : 0.62), lineWidth: 0.45)
                    .padding(0.8)
            }
            .shadow(color: KXColor.glassShadow.opacity(isSelected ? 0.55 : 0.32), radius: isSelected ? 6 : 3, y: isSelected ? 2 : 1)
    }

    /// Translucent bar (top nav / bottom toolbar). Previously layered
    /// `.ultraThinMaterial` AND an overlay tint, which doubles the
    /// blur cost on every frame; the material already provides the
    /// right glass look on iOS 17+.
    func kxGlassBar(ignoresTopSafeArea: Bool = false) -> some View {
        self
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Rectangle().fill(KXColor.cardBackground.opacity(0.24)))
                    .ignoresSafeArea(edges: ignoresTopSafeArea ? .top : [])
            }
    }

    func kxPageBackground() -> some View {
        self
            .background {
                KXGlassBackground()
            }
    }
}

private struct _SurfaceShadow: ViewModifier {
    let elevated: Bool
    func body(content: Content) -> some View {
        if elevated {
            content
                .shadow(color: KXColor.glassShadow.opacity(0.55), radius: 9, y: 4)
                .shadow(color: KXColor.glassShadow.opacity(0.22), radius: 1.5, y: 1)
        } else {
            content.shadow(color: KXColor.glassShadow.opacity(0.32), radius: 5, y: 1)
        }
    }
}

typealias KXPostCard = PostCardView
typealias KXSettingsRow = SettingsRowContent
typealias KXBottomTabBar = BottomTabBarView
