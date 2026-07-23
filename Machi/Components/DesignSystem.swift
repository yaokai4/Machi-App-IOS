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
    // Single source of truth for corner radii — same-tier surfaces share one
    // token instead of hardcoding a literal. Tier semantics:
    //   xxs(4)   → progress bars, skeleton bones, hairline dividers, micro chips
    //   xs(8)    → small controls (thumbnails, mini buttons, tiny tags)
    //   sm(10)   → chips / compact tags
    //   md(14)   → controls & input fields (buttons, text fields, menus)
    //   tile(16) → compact tiles & standard cards in dense grids/lists
    //   card(20) → full-width primary content cards
    //   lg(20)   → legacy alias of the card tier (prefer `card` in new code)
    //   hero(22) → showcase / hero surfaces (feature banners, covers)
    //   sheet(26)→ bottom sheets / large panels
    //   pill(999)→ capsules (or use `Capsule()` directly)
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let tile: CGFloat = 16
    static let lg: CGFloat = 20
    static let card: CGFloat = 20
    static let hero: CGFloat = 22
    static let sheet: CGFloat = 26
    static let pill: CGFloat = 999
}

/// 悬浮玻璃 TabBar 的布局常量(非视觉 token):可滚动界面用
/// bottomContentPadding 预留底部内边距,保证最后一张卡不被悬浮栏盖住。
enum KXLayout {
    static let bottomBarHeight: CGFloat = 66
    static let bottomContentPadding: CGFloat = 98
}

enum KXTypography {
    // Wider type scale: pull the top end up and add a title2 so hierarchy reads
    // through SIZE, not just weight. Titles use semibold/bold, body stays
    // regular — `.black` is avoided on reading text (it muddies CJK glyphs).
    static let largeTitle = Font.system(size: 32, weight: .bold)
    static let title = Font.system(size: 22, weight: .semibold)
    static let title2 = Font.system(size: 19, weight: .semibold)
    static let section = Font.subheadline.weight(.semibold)
    static let body = Font.callout
    static let bodyEmphasis = Font.callout.weight(.semibold)
    static let meta = Font.caption
    static let metaEmphasis = Font.caption.weight(.semibold)
    static let tiny = Font.caption2
}

/// One motion language for the whole app — same gesture, same curve, same
/// duration. Replaces the scattered 0.16/0.18/0.2/0.24/0.26 ad-hoc timings.
enum KXMotion {
    static let tap = Animation.spring(response: 0.3, dampingFraction: 0.75)
    static let select = Animation.snappy(duration: 0.22)
    static let reveal = Animation.easeOut(duration: 0.25)
}

/// Carries the listing-stack zoom namespace down to a tab root (e.g. Discover)
/// so an entry card there can be the zoom SOURCE and the pushed channel screen
/// the DESTINATION — the two morph as one. nil → cards just push normally.
private struct KXListingZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var kxListingZoomNamespace: Namespace.ID? {
        get { self[KXListingZoomNamespaceKey.self] }
        set { self[KXListingZoomNamespaceKey.self] = newValue }
    }
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
    /// Foreground for content sitting ON an accent fill (button labels, sent
    /// chat bubbles, CTAs). Pure white on the light brand teal, near-black on
    /// the brighter dark-mode teal — a raw `.white` on the light dark-mode
    /// accent washes out and drops below AA. Use this instead of `.white`
    /// wherever the background is `KXColor.accent`.
    static let onAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.08, alpha: 1)
            : UIColor.white
    })
    /// One notification-badge red, replacing the four ad-hoc `Color(red:0.93…)`
    /// literals scattered across the tab bar and messages. Slightly deeper in
    /// dark mode so it doesn't glow on near-black chrome.
    static let badge = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.86, green: 0.20, blue: 0.34, alpha: 1)
            : UIColor(red: 0.93, green: 0.16, blue: 0.34, alpha: 1)
    })
    /// Machi 官方账号标识专用 teal。浅色 = 品牌深青;暗色提亮——
    /// 0.05/0.48/0.45 的深青在深底上对比度不足(原先四处硬编码)。
    static let official = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.78, blue: 0.72, alpha: 1)
            : UIColor(red: 0.05, green: 0.48, blue: 0.45, alpha: 1)
    })
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
    static let heat = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.980, green: 0.580, blue: 0.250, alpha: 1)
            : UIColor(red: 0.850, green: 0.450, blue: 0.120, alpha: 1)
    })
    static let dangerSoft = Color.red.opacity(0.10)
    static let warningSoft = Color.orange.opacity(0.12)
    static let successSoft = Color.green.opacity(0.10)
    static let infoSoft = Color.blue.opacity(0.10)
    // Rank / accent palette — brightened one step in dark so the same token
    // reads on dark surfaces whether used as a low-opacity gradient wash or a
    // full-opacity badge/icon foreground (previously flat single-value RGB).
    static let rankGold = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.000, green: 0.780, blue: 0.320, alpha: 1)
            : UIColor(red: 1.000, green: 0.678, blue: 0.145, alpha: 1)
    })
    static let rankCoral = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.000, green: 0.480, blue: 0.510, alpha: 1)
            : UIColor(red: 1.000, green: 0.346, blue: 0.384, alpha: 1)
    })
    static let rankViolet = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.640, green: 0.510, blue: 0.980, alpha: 1)
            : UIColor(red: 0.514, green: 0.353, blue: 0.953, alpha: 1)
    })
    static let rankTeal = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.180, green: 0.780, blue: 0.690, alpha: 1)
            : UIColor(red: 0.000, green: 0.651, blue: 0.561, alpha: 1)
    })
    static let rankSky = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.320, green: 0.680, blue: 1.000, alpha: 1)
            : UIColor(red: 0.063, green: 0.557, blue: 0.969, alpha: 1)
    })
    /// Warm/cool glow tail colors for the search rank gradients (were bare RGB
    /// literals inline in SearchView). Trait-aware so the dark gradient wash
    /// stays warm/cool instead of muddy.
    static let rankCoralGlow = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.000, green: 0.560, blue: 0.400, alpha: 1)
            : UIColor(red: 1.000, green: 0.486, blue: 0.286, alpha: 1)
    })
    static let rankVioletGlow = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.420, green: 0.600, blue: 1.000, alpha: 1)
            : UIColor(red: 0.245, green: 0.469, blue: 0.980, alpha: 1)
    })

    // MARK: Category semantic palette
    // The Discover category grid used ~25 unique tints — a confetti of hues
    // with no meaning. Collapse to a 5-colour semantic set so colour encodes
    // *kind of action*, not just "this tile is different from that one".
    //   brand   → core Machi surfaces (housing, community, guide)
    //   heat    → hot / trending / marketplace demand
    //   alert   → time-sensitive or money (jobs, deadlines, deals)
    //   info    → informational / directory / reference
    //   neutral → utilities & everything unclassified
    static let categoryBrand = accent
    static let categoryHeat = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.55, blue: 0.30, alpha: 1)
            : UIColor(red: 0.85, green: 0.45, blue: 0.12, alpha: 1)
    })
    static let categoryAlert = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.96, green: 0.44, blue: 0.42, alpha: 1)
            : UIColor(red: 0.84, green: 0.28, blue: 0.28, alpha: 1)
    })
    static let categoryInfo = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.66, blue: 0.95, alpha: 1)
            : UIColor(red: 0.20, green: 0.48, blue: 0.82, alpha: 1)
    })
    static let categoryNeutral = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.66, blue: 0.68, alpha: 1)
            : UIColor(red: 0.42, green: 0.46, blue: 0.48, alpha: 1)
    })

    // MARK: Chart / categorical extension palette
    // Trait-aware categorical colors for data visuals (记账 charts, Discover
    // social entry tiles) — replaces frozen `Color(red:)` literals and native
    // system-color rainbows that ignore dark mode. Same recipe as the rank
    // set: hand-tuned RGB via a UIColor trait closure, brightened one step in
    // dark mode so slices, legends and tinted tiles stay legible on dark
    // surfaces. The three new hues below fill gaps the rank set doesn't cover.
    static let chartGreen = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.380, green: 0.800, blue: 0.460, alpha: 1)
            : UIColor(red: 0.220, green: 0.620, blue: 0.300, alpha: 1)
    })
    static let chartPink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.980, green: 0.480, blue: 0.720, alpha: 1)
            : UIColor(red: 0.870, green: 0.320, blue: 0.600, alpha: 1)
    })
    static let chartSlate = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.620, green: 0.670, blue: 0.780, alpha: 1)
            : UIColor(red: 0.400, green: 0.450, blue: 0.580, alpha: 1)
    })
    /// Ordered categorical palette (8 hues) for pie/bar segments and tinted
    /// entry cards. Sequence is tuned so adjacent slices land on clearly
    /// separated hues (teal → coral → sky → gold → violet → green → pink →
    /// slate); index with `chartPalette[i % chartPalette.count]`.
    static let chartPalette: [Color] = [
        rankTeal, rankCoral, rankSky, rankGold, rankViolet,
        chartGreen, chartPink, chartSlate,
    ]

    /// Foreground for text/icons sitting ON an arbitrary colored fill (tinted
    /// chips, category tiles, chart legends, event covers). A hardcoded
    /// `.white` fails WCAG AA on bright tints (gold, brightened dark-mode
    /// hues); this picks the readable side per trait: it resolves the tint's
    /// RGB components for the current light/dark appearance, estimates
    /// perceived luminance (Rec. 601 luma on the UIColor components), and
    /// returns near-black ink (same 0.08 white as `onAccent`'s dark variant)
    /// on bright fills (> 0.6) or `.white` on deep fills — keeping label
    /// contrast at AA on both appearance variants of a trait-aware tint.
    static func onTint(_ tint: Color) -> Color {
        Color(UIColor { traits in
            let resolved = UIColor(tint).resolvedColor(with: traits)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else {
                // Non-RGB-convertible (e.g. pattern) fill — keep the
                // conventional light-on-color default.
                return .white
            }
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            return luminance > 0.6 ? UIColor(white: 0.08, alpha: 1) : .white
        })
    }
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
    @Environment(\.appLanguage) private var language
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.blue)
            // Localized so zh/ja VoiceOver users don't hear English on a badge
            // that sits beside author names across feeds/profiles/comments.
            .accessibilityLabel(KXListingCopy.pickText(language, "已认证", "認証済み", "Verified"))
    }
}

struct KXOfficialBadge: View {
    @Environment(\.appLanguage) private var language
    var body: some View {
        Image(systemName: "checkmark.shield.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(KXColor.official)
            .accessibilityLabel(KXListingCopy.pickText(language, "Machi 官方", "Machi 公式", "Machi Official"))
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
                    withAnimation(KXMotion.select) {
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
        .padding(KXSpacing.xs)
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
    /// Optional brand illustration motif; nil keeps the plain icon-in-circle.
    var illustration: KXBrandIllustration.Motif? = nil

    var body: some View {
        EmptyStateView(title: title, subtitle: subtitle, systemImage: systemImage, illustration: illustration)
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
            .animation(KXMotion.tap, value: configuration.isPressed)
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

// MARK: - Surface ownership
//
// Two surface families, picked by *what the card is about* — not by screen:
//   • kxLivingSurface — warm, paper-toned. Belongs to COMMERCE content:
//     房源 listings, 商家 merchants, 民宿 stays, JLPT / 资料商城 "product" cards.
//   • kxGlassSurface  — cool, translucent glass. Belongs to SOCIAL & REFERENCE
//     content: community posts, messages, and Guide 资料 (informational) cards.
// When in doubt, a screen should not mix both families in the same section.

extension View {
    /// Shared product surface for cards and panels.
    func kxGlassSurface(
        radius: CGFloat = KXRadius.card,
        stroke: Color = KXColor.glassStroke,
        elevated: Bool = false
    ) -> some View {
        // One clean hairline + one soft shadow. The old inset "glass highlight"
        // second stroke was Big-Sur-era skeuomorphism that read as plasticky and
        // cost an extra draw per card — dropped for a calmer, more premium edge.
        self
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(KXColor.cardBackground)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke.opacity(0.7), lineWidth: 0.75)
            }
            // Cast the drop shadow from a plain opaque rounded rect *behind* the
            // (already opaque) card, instead of applying `.shadow` to the whole
            // composited card. The silhouette is pixel-identical — the card fills
            // exactly this rounded rect — but SwiftUI no longer has to rasterize
            // every card's text / avatars / images into an offscreen buffer each
            // frame just to derive the shadow's alpha mask. That per-card offscreen
            // pass, ×N visible cards, was the biggest hidden cost against the
            // 120 Hz (8.3 ms) scroll budget. Placed *after* the clip so the soft
            // edge isn't clipped away.
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(KXColor.cardBackground)
                    .modifier(_SurfaceShadow(elevated: elevated))
            }
    }

    func kxLivingSurface(radius: CGFloat = KXRadius.card, elevated: Bool = false) -> some View {
        self
            .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(KXColor.livingInk.opacity(0.075), lineWidth: 0.8)
            }
            // Same 120 Hz optimization as kxGlassSurface: cast the shadow from the
            // opaque surface shape rather than from the whole composited card, so
            // there's no per-frame offscreen rasterization. Identical look.
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(KXColor.livingSurface)
                    .shadow(
                        color: Color.black.opacity(elevated ? 0.075 : 0.035),
                        radius: elevated ? 12 : 5,
                        y: elevated ? 5 : 2
                    )
            }
    }

    /// Guide 首页顶部「hero 级」面板共用 surface(搜索条 / AI hero / JLPT 卡):
    /// livingSoft 底 + sheet 圆角 + livingInk 细描边 + 软阴影,收敛此前三处
    /// 手写的同一 recipe,避免参数各自漂移。
    func kxHeroPanel(radius: CGFloat = KXRadius.sheet) -> some View {
        self
            .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(KXColor.livingInk.opacity(0.06), lineWidth: 0.8)
            }
            // 与 kxGlassSurface 相同的 120 Hz 优化:阴影由背后同形的不透明
            // 圆角矩形投射(livingSoft 不透明,轮廓逐像素一致),避免整卡
            // 每帧离屏合成取 alpha 蒙版。
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(KXColor.livingSoft)
                    .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
            }
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
            .shadow(color: KXColor.glassShadow.opacity(isSelected ? 0.4 : 0.22), radius: isSelected ? 6 : 3, y: isSelected ? 2 : 1)
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
            .shadow(color: KXColor.glassShadow.opacity(isSelected ? 0.4 : 0.22), radius: isSelected ? 6 : 3, y: isSelected ? 2 : 1)
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
            .background(KXColor.softBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                    .stroke(focused ? KXColor.accent.opacity(0.5) : KXColor.separator.opacity(0.7), lineWidth: focused ? 1.4 : 1)
            }
    }

    /// Primary action button content styled like the profile "编辑资料" capsule —
    /// a raised liquid-glass pill. Use on a label inside a Button; pass
    /// `prominent: true` for the brand-accent fill (main submit actions).
    func kxGlassButton(prominent: Bool = true, enabled: Bool = true) -> some View {
        self
            .font(.subheadline.weight(.black))
            .foregroundStyle(prominent ? (enabled ? KXColor.onAccent : Color.secondary) : KXColor.accent)
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
        // A single, soft, lifted shadow. Premium reads as "one clean edge + one
        // soft shadow", not a stack of stacked micro-shadows.
        content.shadow(
            color: KXColor.glassShadow.opacity(elevated ? 0.5 : 0.28),
            radius: elevated ? 11 : 6,
            y: elevated ? 4 : 2
        )
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
                    RoundedRectangle(cornerRadius: KXRadius.xxs, style: .continuous)
                        .fill(bone)
                        .frame(width: 118, height: 11)
                    RoundedRectangle(cornerRadius: KXRadius.xxs, style: .continuous)
                        .fill(bone)
                        .frame(width: 74, height: 9)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: KXRadius.xxs, style: .continuous)
                    .fill(bone)
                    .frame(maxWidth: .infinity)
                    .frame(height: 11)
                RoundedRectangle(cornerRadius: KXRadius.xxs, style: .continuous)
                    .fill(bone)
                    .frame(width: 210, height: 11)
            }
            HStack(spacing: KXSpacing.xl) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: KXRadius.xxs, style: .continuous)
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
        VStack(spacing: KXSpacing.sm) {
            ForEach(0..<count, id: \.self) { _ in
                KXSkeletonFeedCard()
            }
        }
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}

/// Guide list/article placeholder — a hero block over a column of rounded
/// content-card blocks, mirroring the Guide home's real card geometry (icon
/// bubble + title line + body line) instead of a bare spinner. Used on the
/// Guide directory/list pages, which render cards, not post feeds.
struct KXGuideListSkeleton: View {
    var count: Int = 5
    private var bone: some ShapeStyle { KXColor.softBackground }

    var body: some View {
        VStack(spacing: KXSpacing.md) {
            RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous)
                .fill(bone)
                .frame(height: 96)
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: KXSpacing.md) {
                    RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                        .fill(bone)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: KXRadius.xxs, style: .continuous)
                            .fill(bone)
                            .frame(width: 150, height: 11)
                        RoundedRectangle(cornerRadius: KXRadius.xxs, style: .continuous)
                            .fill(bone)
                            .frame(maxWidth: .infinity)
                            .frame(height: 9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(KXSpacing.card)
                .kxGlassSurface(radius: KXRadius.card)
            }
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.md)
        .accessibilityHidden(true)
        .kxShimmer()
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
        .padding(.horizontal, KXSpacing.sm)
        .padding(.vertical, 5)
        .background(.black.opacity(0.22), in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
        .animation(.snappy(duration: 0.2), value: index)
    }
}

/// Tiny "N photos" hint shown on a static list cover — the cheap stand-in for
/// a swipeable gallery. Signals there are more photos without the cost of a
/// real pager in every cell.
struct KXCoverPhotoCount: View {
    let count: Int
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "square.stack.fill")
                .kxScaledFont(9, weight: .bold)
            Text("\(count)")
                .font(.caption2.weight(.black))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, KXSpacing.xs)
        .background(.black.opacity(0.42), in: Capsule())
    }
}

extension View {
    /// Opaque badge background for pills/circles that sit ON a scrolling photo
    /// cover. Replaces `.regularMaterial`/`.ultraThinMaterial` — a live backdrop
    /// blur that recomposites every frame as the cover scrolls underneath, the
    /// single most expensive thing to put in a list cell — with a near-opaque
    /// solid: one cheap blend, no offscreen blur, and reads cleaner over photos.
    func kxCoverBadge<S: InsettableShape>(in shape: S) -> some View {
        self
            .background(KXColor.cardBackground.opacity(0.92), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7))
            // One cheap drop shadow (NOT a live blur) so the badge always reads
            // as floating — keeps contrast on dark covers / dark mode, where a
            // near-black opaque badge would otherwise melt into the photo.
            .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
    }

    /// VoiceOver label/value for a favorite (heart) toggle, so it reads
    /// "Favorite · Saved/Not saved" instead of just "Button".
    func kxFavoriteAccessibility(_ favorited: Bool, _ language: AppLanguage) -> some View {
        self
            .accessibilityLabel(KXListingCopy.pickText(language, "收藏", "お気に入り", "Favorite"))
            .accessibilityValue(favorited
                ? KXListingCopy.pickText(language, "已收藏", "登録済み", "Saved")
                : KXListingCopy.pickText(language, "未收藏", "未登録", "Not saved"))
            .accessibilityAddTraits(favorited ? [.isSelected] : [])
    }
}

/// Photo-led cover. On the detail screen (`interactive: true`) it swipes
/// between a listing's images (with dots); in list cells (`interactive: false`,
/// the default) it renders only the FIRST image plus an "N photos" hint — never
/// a paged `TabView` (a UIPageViewController per cell is the biggest scroll-jank
/// source). Reserves an exact aspect box with a zero-intrinsic Color.clear so an
/// odd source photo can't warp the card.
struct KXCoverCarousel<Placeholder: View>: View {
    let urls: [URL]
    var aspectRatio: CGFloat = 4.0 / 3.0
    var targetPixelSize: CGFloat = 960
    /// `false` (default) = static first-photo cover for cheap list cells;
    /// `true` = real swipeable gallery, for detail screens only.
    var interactive: Bool = false
    let placeholder: Placeholder

    @State private var page = 0

    init(
        urls: [URL],
        aspectRatio: CGFloat = 4.0 / 3.0,
        targetPixelSize: CGFloat = 960,
        interactive: Bool = false,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.urls = urls
        self.aspectRatio = aspectRatio
        self.targetPixelSize = targetPixelSize
        self.interactive = interactive
        self.placeholder = placeholder()
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                ZStack {
                    placeholder
                    if !urls.isEmpty, urls.count == 1 || !interactive {
                        // Static first-photo cover (cheap — used in every list cell).
                        CachedMediaImageView(url: urls[0], targetPixelSize: targetPixelSize, failureMode: .transparent)
                        if !interactive, urls.count > 1 {
                            KXCoverPhotoCount(count: urls.count)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(KXSpacing.sm)
                        }
                    } else if urls.count > 1 {
                        // Swipeable gallery — detail screens only (interactive: true).
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
