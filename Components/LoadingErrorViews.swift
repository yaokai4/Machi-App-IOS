import SwiftUI

struct LoadingView: View {
    @Environment(\.appLanguage) private var language
    @State private var pulse = false

    var body: some View {
        VStack(spacing: KXSpacing.sm) {
            // Branded breathing dot — replaces the system spinner so
            // the loading state matches the rest of the app's visual
            // language and gives the user a more "alive" cue.
            ZStack {
                Circle()
                    .fill(KXColor.accent.opacity(0.18))
                    .frame(width: pulse ? 44 : 28, height: pulse ? 44 : 28)
                Circle()
                    .fill(KXColor.accent.opacity(0.35))
                    .frame(width: pulse ? 26 : 18, height: pulse ? 26 : 18)
                Circle()
                    .fill(LinearGradient(colors: [KXColor.accent, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 12, height: 12)
                    .shadow(color: KXColor.accent.opacity(0.45), radius: 6, y: 2)
            }
            .frame(width: 48, height: 48)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            Text(L("loading", language))
                .font(KXTypography.meta)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .onAppear { pulse = true }
    }
}

/// Full-screen splash used during app cold-bootstrap (before the
/// model context is ready). Shows the Machi logo with a soft
/// gradient + breathing animation so the user has something
/// branded to look at instead of the system launch screen.
///
/// **Reduce-motion aware:** when the user has enabled accessibility
/// "Reduce Motion", we render a static frame so we don't burn GPU
/// with two parallel `repeatForever` animations on devices that
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
                    Circle()
                        .fill(KXColor.accent.opacity(pulse ? 0.20 : 0.10))
                        .frame(width: 132, height: 132)
                    Circle()
                        .fill(KXColor.accent.opacity(pulse ? 0.32 : 0.16))
                        .frame(width: 100, height: 100)
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

struct ErrorStateView: View {
    @Environment(\.appLanguage) private var language
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: KXSpacing.sm) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(L("error", language))
                .font(KXTypography.section)
            Text(message)
                .font(KXTypography.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("retry", language), action: retry)
                .buttonStyle(.bordered)
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
                .font(.title3)
                .foregroundStyle(.secondary)
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
