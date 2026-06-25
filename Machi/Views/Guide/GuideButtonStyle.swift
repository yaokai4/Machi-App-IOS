import SwiftUI

/// A plain-looking button whose **entire rendered label area** is tappable —
/// not just the text/icon glyphs.
///
/// Fixes a widespread bug in the Guide views: `.contentShape(Rectangle())` and
/// `.background(…)` were applied *after* `.buttonStyle(.plain)`, i.e. to the
/// button view rather than to its label. With `.plain`, the button's tap region
/// is the label's own hit-test area, so a label like `Text(...).frame(maxWidth:
/// .infinity).frame(height: 44)` with no background left its empty padding/Spacer
/// regions dead to taps — only the text responded. Applying
/// `.contentShape(Rectangle())` to `configuration.label` makes the full label
/// frame hit-test, which matches the visible (outside) background since the
/// button is the same size as its label. Press dimming mirrors `.plain`.
struct FullAreaButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == FullAreaButtonStyle {
    /// Plain button whose whole label area (incl. padding/Spacer/background) is tappable.
    static var fullArea: FullAreaButtonStyle { FullAreaButtonStyle() }
}
