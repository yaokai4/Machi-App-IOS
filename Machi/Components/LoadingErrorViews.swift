import SwiftUI

/// Brand spinner — a comet-tail arc that rotates continuously.
///
/// The previous loader pulsed circle *sizes* (28→44pt), which forces a
/// layout pass on every animation frame and reads as stutter on busy
/// screens. A `rotationEffect` is a pure Core Animation transform: the
/// render server spins it on the GPU at a solid 60/120fps even while
/// SwiftUI is busy diffing the rest of the page.
struct KXSpinner: View {
    var size: CGFloat = 34
    var lineWidth: CGFloat = 3.4
    var tint: Color = KXColor.accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.68)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.02), tint.opacity(0.45), tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(245)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                isSpinning = true
            }
        }
        .accessibilityLabel(Text("Loading"))
    }
}

struct LoadingView: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(spacing: KXSpacing.md) {
            KXSpinner()
            Text(L("loading", language))
                .font(KXTypography.meta)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

/// Full-screen splash used during app cold-bootstrap (before the
/// model context is ready). Shows the Machi logo with a soft
/// gradient + breathing animation so the user has something
/// branded to look at instead of the system launch screen.
///
/// **Reduce-motion aware:** when the user has enabled accessibility
/// "Reduce Motion", we render a static frame so we don't burn GPU
/// with parallel `repeatForever` animations on devices that
/// explicitly opted out.
struct KXSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var shimmer: CGFloat = -1

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.91, green: 0.93, blue: 0.99),
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    KXColor.pageBackground,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    // Halo rings animate opacity + scale (transform-only,
                    // no layout) instead of resizing frames.
                    Circle()
                        .fill(KXColor.accent.opacity(0.14))
                        .frame(width: 132, height: 132)
                        .scaleEffect(pulse ? 1.0 : 0.86)
                        .opacity(pulse ? 1 : 0.6)
                    Circle()
                        .fill(KXColor.accent.opacity(0.22))
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulse ? 1.0 : 0.9)
                        .opacity(pulse ? 1 : 0.7)
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [Color.indigo, Color.purple, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)
                        .overlay(
                            Text("M")
                                .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundStyle(.white),
                        )
                        .shadow(color: KXColor.accent.opacity(0.45), radius: 22, y: 12)
                        .overlay(
                            // Sheen sweeping across the logo.
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.35), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing,
                                    ),
                                )
                                .blendMode(.plusLighter)
                                .mask(RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .offset(x: shimmer * 80),
                        )
                }
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)

                Text("Machi")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.primary)
                Text("一个城市,一个生活广场")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            pulse = true
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                shimmer = 1
            }
        }
    }
}

/// Compact inline loader for "load more" rows — a small brand spinner,
/// visually quieter than a full LoadingView and consistent with it.
struct KXInlineLoader: View {
    var body: some View {
        KXSpinner(size: 22, lineWidth: 2.6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
    }
}

struct ErrorStateView: View {
    @Environment(\.appLanguage) private var language
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: KXSpacing.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(KXColor.accent)
                .frame(width: 56, height: 56)
                .background(KXColor.accent.opacity(0.10), in: Circle())
            VStack(spacing: 4) {
                Text(L("error", language))
                    .font(.headline.weight(.semibold))
                Text(message)
                    .font(KXTypography.meta)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: retry) {
                Label(L("retry", language), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.accent)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(KXColor.accent.opacity(0.10), in: Capsule())
                    .overlay(Capsule().stroke(KXColor.accent.opacity(0.28), lineWidth: 0.8))
            }
            .buttonStyle(KXPressableStyle())
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 170)
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: KXSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(KXColor.softBackground, in: Circle())
            Text(title)
                .font(KXTypography.section)
            Text(subtitle)
                .font(KXTypography.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 170)
    }
}

struct KXStatePanel: View {
    let title: String
    let subtitle: String
    var systemImage: String = "tray"
    var accent: Color = KXColor.accent

    var body: some View {
        VStack(spacing: KXSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 52, height: 52)
                .background(accent.opacity(0.10), in: Circle())

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, KXSpacing.lg)
        .padding(.vertical, KXSpacing.xl)
        .frame(maxWidth: .infinity)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}
