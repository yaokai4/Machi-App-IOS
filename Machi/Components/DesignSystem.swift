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
    static let card: CGFloat = 20
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

/// A fixed point-size font that *scales with Dynamic Type*. Plain
/// `Font.system(size:)` never scales, so any text built that way is frozen for
/// users who enlarge text for accessibility. This modifier keeps the exact same
/// size at the default content-size category (so the design is pixel-identical
/// today) but lets `@ScaledMetric` grow it relative to `textStyle` when the user
/// turns text up — the drop-in replacement for `.font(.system(size:weight:))` on
/// real reading text (post bodies, titles). Decorative glyphs/badges keep the
/// plain fixed font on purpose.
private struct KXScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, relativeTo textStyle: Font.TextStyle, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// Dynamic-Type-aware replacement for `.font(.system(size:weight:design:))`.
    func kxScaledFont(
        _ size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .body,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(KXScaledFont(size: size, relativeTo: textStyle, weight: weight, design: design))
    }
}

enum KXColor {
    static let pageBackground = Color(UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.secondarySystemGroupedBackground
        }
        return UIColor(red: 0.972, green: 0.967, blue: 0.958, alpha: 1)
    })
    static let cardBackground = Color(.systemBackground)
    static let elevatedBackground = Color(.systemBackground)
    static let softBackground = Color(UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor.tertiarySystemGroupedBackground
        }
        return UIColor(red: 0.948, green: 0.944, blue: 0.936, alpha: 1)
    })
    static let separator = Color(.separator).opacity(0.30)
    static let glassStroke = Color(.separator).opacity(0.44)
    static let glassTint = Color(.systemBackground).opacity(0.10)
    static let glassSurfaceTint = Color(.systemBackground).opacity(0.86)
    static let glassControlTint = Color(.systemBackground).opacity(0.74)
    static let glassBarTint = Color(.systemBackground).opacity(0.66)
    static let glassHighlight = Color.white.opacity(0.34)
    static let glassShadow = Color.black.opacity(0.052)
    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.11)
    static let livingBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.066, blue: 0.063, alpha: 1)
            : UIColor(red: 0.982, green: 0.973, blue: 0.950, alpha: 1)
    })
    static let livingSurface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.090, green: 0.106, blue: 0.101, alpha: 1)
            : UIColor(red: 0.998, green: 0.996, blue: 0.988, alpha: 1)
    })
    static let livingSoft = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.118, green: 0.139, blue: 0.132, alpha: 1)
            : UIColor(red: 0.946, green: 0.935, blue: 0.906, alpha: 1)
    })
    static let livingInk = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.948, green: 0.958, blue: 0.950, alpha: 1)
            : UIColor(red: 0.105, green: 0.125, blue: 0.118, alpha: 1)
    })
    static let livingMuted = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.670, green: 0.710, blue: 0.690, alpha: 1)
            : UIColor(red: 0.365, green: 0.392, blue: 0.378, alpha: 1)
    })
    /// Brand accent — deep teal-green in light, brighter teal in dark so it
    /// stays legible on dark surfaces. Matches the AccentColor asset exactly,
    /// so listing surfaces and app chrome read as one brand.
    static let livingAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.361, green: 0.745, blue: 0.698, alpha: 1)
            : UIColor(red: 0.075, green: 0.390, blue: 0.350, alpha: 1)
    })
    static let livingAccentSoft = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.361, green: 0.745, blue: 0.698, alpha: 0.16)
            : UIColor(red: 0.075, green: 0.390, blue: 0.350, alpha: 0.11)
    })
    static let livingWarm = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.910, green: 0.475, blue: 0.365, alpha: 1)
            : UIColor(red: 0.760, green: 0.326, blue: 0.220, alpha: 1)
    })
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

/// iOS-17-safe descriptor for the Liquid Glass styles. SwiftUI's `Glass`
/// type only exists on iOS 26+, so we never store one directly — we map this
/// to a `Glass` *inside* an availability check (`kxLiquidGlass`) and fall back
/// to a frosted `.ultraThinMaterial` (the standard pre-26 glass look) on
/// iOS 17–25. This is what lets the app deploy to iOS 17 while still showing
/// the real Liquid Glass on iOS 26+ devices.
enum KXGlassStyle {
    case surface, control, selected, bar, clear
}

@available(iOS 26, *)
private func kxResolveGlass(_ style: KXGlassStyle, interactive: Bool, tint: Color?) -> Glass {
    var glass: Glass
    if let tint {
        glass = Glass.regular.tint(tint)
    } else {
        switch style {
        case .surface:  glass = Glass.regular.tint(KXColor.glassSurfaceTint)
        case .control:  glass = Glass.regular.tint(KXColor.glassControlTint)
        case .selected: glass = Glass.regular.tint(KXColor.accent.opacity(0.13))
        case .bar:      glass = Glass.regular.tint(KXColor.glassBarTint)
        case .clear:    glass = Glass.clear
        }
    }
    return interactive ? glass.interactive() : glass
}

extension View {
    /// Liquid Glass on iOS 26+, frosted `.ultraThinMaterial` on iOS 17–25.
    /// Call sites keep their own tint fill + strokes + shadow, so the
    /// downlevel look stays cohesive even without the glass refraction.
    @ViewBuilder
    func kxLiquidGlass<S: Shape>(_ style: KXGlassStyle = .control, in shape: S, interactive: Bool = true, tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(kxResolveGlass(style, interactive: interactive, tint: tint), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Zoom navigation transition source (iOS 18+); no-op on iOS 17 — the
    /// preview still presents, just with the default animation.
    @ViewBuilder
    func kxMatchedTransitionSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func kxZoomTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    /// Conditional zoom source/destination — applies the matched-transition
    /// pair only when a namespace is threaded through (router-built listing
    /// screens share one), otherwise a plain no-op so other call sites and the
    /// DEBUG push path are unaffected.
    @ViewBuilder
    func kxListingZoomSource(_ id: String, _ namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.kxMatchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func kxListingZoomDestination(_ id: String, _ namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.kxZoomTransition(sourceID: id, in: namespace)
        } else {
            self
        }
    }

    /// Drives a `collapsed` flag from a scroll view's vertical offset so a
    /// pinned header can condense once the user scrolls past `threshold`.
    /// iOS 18+ only (uses scroll geometry); on 17 the header stays expanded.
    @ViewBuilder
    func kxScrollCollapse(threshold: CGFloat = 24, _ collapsed: Binding<Bool>) -> some View {
        if #available(iOS 18, *) {
            self.onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > threshold
            } action: { _, newValue in
                if collapsed.wrappedValue != newValue {
                    withAnimation(.snappy(duration: 0.24)) { collapsed.wrappedValue = newValue }
                }
            }
        } else {
            self
        }
    }
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

struct KXOfficialBadge: View {
    var body: some View {
        Image(systemName: "checkmark.shield.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.45))
            .accessibilityLabel("Machi Official")
    }
}

struct KXUserBadge: View {
    let user: UserEntity?

    var body: some View {
        if user?.displaysOfficialBadge == true {
            KXOfficialBadge()
        } else if user?.displaysVerifiedBadge == true {
            KXVerifiedBadge()
        }
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
                                // Was matchedGeometryEffect(id:) to slide the indicator between
                                // segments. That cross-view geometry preference (PairPreference
                                // Combiner) could recurse when this control sits inside a
                                // ScrollView during a NavigationStack push transition, overflowing
                                // the main-thread stack (SystemScrollView layout SIGSEGV seen on
                                // TestFlight 1.3). A plain conditional background cross-fades under
                                // the existing withAnimation — no cross-view preference, no
                                // layout-recursion risk.
                                KXSelectedSegmentBackground()
                                    .transition(.opacity)
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
        .sensoryFeedback(.selection, trigger: selection)
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

/// Horizontal chip rail with soft edge fades that appear only while
/// content actually overflows in that direction — the visual cue that
/// the row scrolls, which plain `ScrollView(.horizontal)` never gives.
struct KXFadingHScroll<Content: View>: View {
    var fadeWidth: CGFloat = 22
    @ViewBuilder let content: Content

    private struct Edges: Equatable {
        var leading = false
        var trailing = false
    }

    @State private var edges = Edges()

    var body: some View {
        scroller
        .mask {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [edges.leading ? .clear : .black, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
                Rectangle().fill(.black)
                LinearGradient(
                    colors: [.black, edges.trailing ? .clear : .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: edges)
    }

    // iOS 18+ tracks scroll geometry to fade the leading/trailing edges; on
    // iOS 17 the edges simply stay un-faded (a subtle polish, not a feature).
    @ViewBuilder
    private var scroller: some View {
        if #available(iOS 18, *) {
            ScrollView(.horizontal, showsIndicators: false) {
                content
            }
            .onScrollGeometryChange(for: Edges.self) { geometry in
                Edges(
                    leading: geometry.contentOffset.x > 4,
                    trailing: geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 4
                )
            } action: { _, newEdges in
                if newEdges != edges { edges = newEdges }
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                content
            }
        }
    }
}

/// On wide layouts (iPad / regular width class) cap content to a readable,
/// centred column so single-column screens don't stretch edge-to-edge. On
/// iPhone (compact) it's a no-op. Apply to the inner scroll content (e.g. the
/// feed LazyVStack), not the whole screen, so the page background stays
/// full-bleed behind the centred column.
private struct KXReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize
    var maxWidth: CGFloat = 740
    func body(content: Content) -> some View {
        if hSize == .regular {
            content.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// Centre and cap content width on iPad / regular size class. No-op on iPhone.
    func kxReadableWidth(_ maxWidth: CGFloat = 740) -> some View {
        modifier(KXReadableWidth(maxWidth: maxWidth))
    }
}

struct KXFloatingComposeButton: View {
    let action: () -> Void
    @State private var tapCount = 0

    var body: some View {
        Button {
            tapCount += 1
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: KXIconSize.md, weight: .semibold))
                .foregroundStyle(KXColor.accent)
                .frame(width: 54, height: 54)
                .background {
                    Circle()
                        .fill(KXColor.accent.opacity(0.09))
                }
                .kxLiquidGlass(.selected, in: Circle())
                .overlay(Circle().stroke(KXColor.glassStroke, lineWidth: 1))
                .shadow(color: KXColor.glassShadow, radius: 7, y: 3)
        }
        .buttonStyle(KXPressableStyle(scale: 0.90))
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
        // Stable hook for UI tests (Home + Discover both use this button) and a
        // VoiceOver-friendly target. Only the active tab's copy is hit-testable,
        // so the duplicate id across tabs is never ambiguous.
        .accessibilityIdentifier("compose.floating")
    }
}

/// Press feedback shared by every tappable product control: a quick
/// spring-down to `scale` with a slight dim, springing back on release.
/// SwiftUI's `.plain` style gives zero pressed-state affordance, which
/// reads as "dead" — this is the single biggest cheap win for perceived
/// quality on physical devices.
struct KXPressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var dim: CGFloat = 0.86

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? dim : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == KXPressableStyle {
    static var kxPressable: KXPressableStyle { KXPressableStyle() }
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
            Color(red: 0.982, green: 0.978, blue: 0.970),
            Color(red: 0.960, green: 0.954, blue: 0.944),
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

    func kxLivingSurface(radius: CGFloat = KXRadius.card, elevated: Bool = false) -> some View {
        self
            .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(KXColor.livingInk.opacity(0.075), lineWidth: 0.8)
            }
            .shadow(
                color: Color.black.opacity(elevated ? 0.075 : 0.035),
                radius: elevated ? 12 : 5,
                y: elevated ? 5 : 2
            )
    }

    func kxGlassCapsule(isSelected: Bool = false) -> some View {
        self
            .background {
                Capsule()
                    .fill(isSelected ? KXColor.accent.opacity(0.12) : KXColor.glassControlTint)
            }
            .kxLiquidGlass(isSelected ? .selected : .control, in: Capsule())
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
            .kxLiquidGlass(isSelected ? .selected : .control, in: Circle())
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

    /// Shared input-field surface — replaces the stock `.roundedBorder` (which
    /// reads as a cramped grey hairline box) with a soft, tappable 48pt field:
    /// living surface, generous corner radius, faint accent-able rim. Works for
    /// TextField and SecureField alike via `.textFieldStyle(.plain)`.
    func kxInputField(focused: Bool = false) -> some View {
        self
            .textFieldStyle(.plain)
            .font(.body)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.softBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focused ? KXColor.accent.opacity(0.5) : KXColor.separator.opacity(0.7), lineWidth: focused ? 1.4 : 1)
            }
    }

    /// Primary action button content styled like the profile "编辑资料" capsule —
    /// a raised liquid-glass pill. Use on a label inside a Button; pass
    /// `prominent: true` for the brand-accent fill (main submit actions).
    func kxGlassButton(prominent: Bool = true, enabled: Bool = true) -> some View {
        self
            .font(.subheadline.weight(.black))
            .foregroundStyle(prominent ? (enabled ? Color.white : Color.secondary) : KXColor.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                Capsule().fill(prominent ? (enabled ? KXColor.accent : KXColor.softBackground) : KXColor.cardBackground)
            }
            .kxLiquidGlass(prominent && enabled ? .selected : .control, in: Capsule())
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(prominent && enabled ? Color.white.opacity(0.25) : KXColor.accent.opacity(0.32), lineWidth: 0.9)
            }
            .shadow(color: (prominent && enabled ? KXColor.accent : KXColor.glassShadow).opacity(0.3), radius: 14, y: 6)
    }
}

private struct _SurfaceShadow: ViewModifier {
    let elevated: Bool
    func body(content: Content) -> some View {
        if elevated {
            content
                .shadow(color: KXColor.glassShadow.opacity(0.42), radius: 7, y: 3)
                .shadow(color: KXColor.glassShadow.opacity(0.16), radius: 1.2, y: 1)
        } else {
            content.shadow(color: KXColor.glassShadow.opacity(0.22), radius: 4, y: 1)
        }
    }
}

// MARK: - Skeleton loading

/// Loading placeholder motion. The old white light-sweep (plusLighter)
/// read as a bright flash on every refresh; placeholders now BREATHE —
/// the same quiet opacity pulse the system's redacted skeletons use.
/// Static under Reduce Motion.
private struct KXShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1 : (dimmed ? 0.55 : 1))
            .onAppear {
                guard !reduceMotion, !KXRuntime.isUITesting else { return }
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

extension View {
    func kxShimmer() -> some View {
        modifier(KXShimmerModifier())
    }
}

/// Feed-card-shaped placeholder: avatar + name lines, two body lines and
/// a metric row, mirroring `PostCardView`'s geometry so the swap from
/// skeleton to content doesn't jump.
struct KXSkeletonFeedCard: View {
    private var bone: some ShapeStyle { KXColor.softBackground }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(spacing: KXSpacing.sm) {
                Circle()
                    .fill(bone)
                    .frame(width: KXAvatarSize.md, height: KXAvatarSize.md)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(bone)
                        .frame(width: 118, height: 11)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(bone)
                        .frame(width: 74, height: 9)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(bone)
                    .frame(maxWidth: .infinity)
                    .frame(height: 11)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(bone)
                    .frame(width: 210, height: 11)
            }
            HStack(spacing: KXSpacing.xl) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(bone)
                        .frame(width: 34, height: 9)
                }
                Spacer()
            }
        }
        .padding(KXSpacing.card)
        .kxGlassSurface(radius: KXRadius.card)
        .kxShimmer()
    }
}

/// Initial-load placeholder for post feeds — a column of skeleton cards
/// in place of a lone spinner, so the page keeps its visual structure
/// while data arrives.
struct KXFeedSkeleton: View {
    var count: Int = 4

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { _ in
                KXSkeletonFeedCard()
            }
        }
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}

// MARK: - Cover carousel (Airbnb-style swipeable photos on list cards)

/// Page dots drawn for legibility over any photo: white dots in a soft dark
/// pill, the active one larger + opaque. Caps at 7 dots so long galleries
/// don't overflow a card's width.
struct KXCarouselDots: View {
    let count: Int
    let index: Int

    var body: some View {
        let shown = min(count, 7)
        HStack(spacing: 5) {
            ForEach(0..<shown, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == index ? 1 : 0.55))
                    .frame(width: i == index ? 6.5 : 5, height: i == index ? 6.5 : 5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.22), in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
        .animation(.snappy(duration: 0.2), value: index)
    }
}

/// Photo-led cover that swipes between a listing's images (with dots) when
/// there is more than one, and degrades to a single fill — or the supplied
/// `placeholder` — otherwise. Reserves an exact aspect box with a
/// zero-intrinsic Color.clear so an odd source photo can't warp the card.
struct KXCoverCarousel<Placeholder: View>: View {
    let urls: [URL]
    var aspectRatio: CGFloat = 4.0 / 3.0
    var targetPixelSize: CGFloat = 960
    let placeholder: Placeholder

    @State private var page = 0

    init(
        urls: [URL],
        aspectRatio: CGFloat = 4.0 / 3.0,
        targetPixelSize: CGFloat = 960,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.urls = urls
        self.aspectRatio = aspectRatio
        self.targetPixelSize = targetPixelSize
        self.placeholder = placeholder()
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                ZStack {
                    placeholder
                    if urls.count == 1 {
                        CachedMediaImageView(url: urls[0], targetPixelSize: targetPixelSize, failureMode: .transparent)
                    } else if urls.count > 1 {
                        TabView(selection: $page) {
                            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                                CachedMediaImageView(url: url, targetPixelSize: targetPixelSize, failureMode: .transparent)
                                    .clipped()
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .overlay(alignment: .bottom) {
                            KXCarouselDots(count: urls.count, index: page)
                                .padding(.bottom, 9)
                        }
                    }
                }
            }
            .clipped()
    }
}

typealias KXPostCard = PostCardView
typealias KXSettingsRow = SettingsRowContent
typealias KXBottomTabBar = BottomTabBarView
