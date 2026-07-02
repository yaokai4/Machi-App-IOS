import SwiftUI

/// Tiny runtime probe. `isUITesting` is true only when the app was launched
/// by XCUITest (one of the `-kaixUITest*` / `-KXAutoGuest` launch args is
/// present). We use it to suppress `repeatForever` animations during UI
/// tests: a perpetual Core Animation keeps the app from ever reaching the
/// "idle" state XCUITest waits on, so every accessibility query times out
/// ("Failed to get matching snapshots: Timed out while evaluating UI query").
/// These launch args are never passed to a real App Store / TestFlight
/// build, so production visuals are completely unchanged.
enum KXRuntime {
    static let isUITesting: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-kaixUITestEphemeralStore")
            || args.contains("-kaixUITestLocalAuth")
            || args.contains("-kaixUITestAutoLogin")
            || args.contains("-KXAutoGuest")
            || ProcessInfo.processInfo.environment["KAIX_UI_TESTING"] == "1"
    }()
}

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
    @Environment(\.appLanguage) private var language
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
            guard !reduceMotion, !KXRuntime.isUITesting else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                isSpinning = true
            }
        }
        .accessibilityLabel(Text(L("loading", language)))
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
        // Expand to fill the available area (centering the spinner) when given a
        // bounded region, e.g. as the sole content of a state switch. Under a
        // ScrollView's unbounded proposal `maxHeight: .infinity` collapses back
        // to the content height, so inline "loading" rows stay compact.
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
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
    @Environment(\.appLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal = false
    @State private var appeared = false
    @State private var breathing = false
    @State private var shimmer: CGFloat = -1.2
    @State private var progressActive = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    KXColor.pageBackground,
                    // Trait-aware mid stops: the old fixed near-white pair made
                    // the dark-mode splash flash a bright wash on cold start.
                    Color(UIColor { traits in
                        traits.userInterfaceStyle == .dark
                            ? UIColor(red: 0.075, green: 0.095, blue: 0.090, alpha: 1)
                            : UIColor(red: 0.968, green: 0.982, blue: 0.976, alpha: 1)
                    }),
                    Color(UIColor { traits in
                        traits.userInterfaceStyle == .dark
                            ? UIColor(red: 0.090, green: 0.100, blue: 0.096, alpha: 1)
                            : UIColor(red: 0.988, green: 0.988, blue: 0.982, alpha: 1)
                    }),
                    KXColor.pageBackground,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            .ignoresSafeArea()

            if reveal {
                VStack(spacing: 20) {
                    KXSplashLogoMark(shimmer: shimmer)
                        .scaleEffect(breathing ? 1.0 : 0.986)
                        .opacity(appeared ? 1 : 0)

                    VStack(spacing: 8) {
                        Text("Machi")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(L("splashTagline", language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .opacity(appeared ? 1 : 0)

                    KXSplashProgressRail(isActive: progressActive)
                        .padding(.top, 4)
                        .opacity(appeared ? 1 : 0)
                }
                .padding(.horizontal, 36)
                .offset(y: -10)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .task {
            if reduceMotion || KXRuntime.isUITesting {
                reveal = true
                appeared = true
                breathing = true
                shimmer = 1
                progressActive = true
                return
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                reveal = true
            }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 1.65).repeatForever(autoreverses: true)) {
                breathing = true
            }
            withAnimation(.easeInOut(duration: 1.8).delay(0.16).repeatForever(autoreverses: false)) {
                shimmer = 1.2
            }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                progressActive = true
            }
        }
    }
}

private struct KXSplashLogoMark: View {
    let shimmer: CGFloat

    var body: some View {
        let pulse = max(0, min(1, (shimmer + 1.2) / 2.4))

        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            KXColor.accent.opacity(0.10),
                            KXColor.accent.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 108, height: 108)
                .scaleEffect(1 + pulse * 0.025)
                .blur(radius: 0.2)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.812, green: 0.922, blue: 0.851),
                            Color(red: 0.643, green: 0.851, blue: 0.733),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 78, height: 78)
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(.white.opacity(0.20))
                        .frame(width: 30, height: 30)
                        .blur(radius: 8)
                        .offset(x: 14, y: 10)
                }
                .overlay(
                    Text("M")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.122, green: 0.541, blue: 0.424))
                )
                .shadow(color: KXColor.accent.opacity(0.22), radius: 24, y: 12)
        }
        .accessibilityHidden(true)
    }
}

private struct KXSplashProgressRail: View {
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Capsule()
                .fill(KXColor.accent.opacity(0.10))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(KXColor.accent.opacity(0.46))
                        .frame(width: 36, height: 3)
                        .offset(x: isActive ? max(width - 36, 0) : 0)
                }
        }
        .frame(width: 112, height: 3)
        .clipShape(Capsule())
        .accessibilityHidden(true)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: String
    /// Defaults to a neutral server/cloud glyph — the old fixed
    /// `wifi.exclamationmark` told users to check their Wi-Fi even for a 500 or
    /// a parse error. Callers can pass a more specific icon.
    var systemImage: String = "exclamationmark.icloud"
    let retry: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: KXSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(KXColor.accent)
                .frame(width: 56, height: 56)
                .background(KXColor.accent.opacity(0.10), in: Circle())
                .symbolEffect(.bounce, value: appeared)
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
        // Fill a bounded state region (centering the message) so a header above
        // it stays pinned at the top instead of drifting to mid-screen; stays
        // compact inside a ScrollView (unbounded proposal → content height).
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: .infinity)
        .onAppear { if !reduceMotion { appeared = true } }
    }
}

struct KXInlineNotice: View {
    let message: String
    var systemImage: String = "exclamationmark.circle.fill"
    var tint: Color = KXColor.accent
    let onDismiss: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10), in: Circle())

            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)   // ≥44pt HIG tap target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language == .ja ? "閉じる" : language == .en ? "Dismiss" : "关闭")
        }
        .padding(.horizontal, KXSpacing.md)
        .padding(.vertical, 10)
        .kxGlassSurface(radius: KXRadius.md, elevated: true)
        .padding(.horizontal, KXSpacing.screen)
    }
}

struct EmptyStateView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let subtitle: String
    var systemImage: String = "tray"
    @State private var appeared = false

    var body: some View {
        VStack(spacing: KXSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, height: 52)
                .background(KXColor.softBackground, in: Circle())
                .symbolEffect(.bounce, value: appeared)
            Text(title)
                .font(KXTypography.section)
            Text(subtitle)
                .font(KXTypography.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        // Fill a bounded state region (centering the content) so a header/picker
        // above it stays pinned at the top instead of the whole block drifting to
        // mid-screen; stays compact inside a ScrollView (unbounded → content).
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: .infinity)
        .onAppear { if !reduceMotion { appeared = true } }
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
