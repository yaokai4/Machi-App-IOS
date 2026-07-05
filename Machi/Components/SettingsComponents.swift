import SwiftUI

enum KXSettingsRowStatus: Equatable {
    case implemented
    case disabled(String)
    case comingSoon

    var isInteractive: Bool {
        if case .implemented = self { return true }
        return false
    }

    func title(_ language: AppLanguage) -> String? {
        switch self {
        case .implemented:
            nil
        case .disabled(let reason):
            reason
        case .comingSoon:
            L("comingSoon", language)
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, KXSpacing.xs)
                .padding(.top, KXSpacing.xs)

            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 6)
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(KXColor.separator.opacity(0.4), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.03), radius: 6, y: 1)
        }
    }
}

struct SettingsRowLink<Destination: View>: View {
    @Environment(\.appLanguage) private var language
    @State private var isShowingStatusMessage = false

    let icon: String
    let tint: Color
    let title: String
    var value: String?
    let subtitle: String
    var status: KXSettingsRowStatus
    /// When the destination already draws its own in-content glass header
    /// (with a back button), keep the system navigation bar hidden so the
    /// user doesn't see two stacked back buttons. Defaults to revealing the
    /// nav bar for the common case of plain list/detail destinations.
    var revealsNavBar: Bool = true
    let destination: () -> Destination

    init(
        icon: String,
        tint: Color,
        title: String,
        value: String? = nil,
        subtitle: String,
        status: KXSettingsRowStatus = .implemented,
        revealsNavBar: Bool = true,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.status = status
        self.revealsNavBar = revealsNavBar
        self.destination = destination
    }

    var body: some View {
        Group {
            if status.isInteractive {
                NavigationLink {
                    destination()
                        .toolbar(revealsNavBar ? .visible : .hidden, for: .navigationBar)
                } label: {
                    SettingsRowContent(icon: icon, tint: tint, title: title, value: value, subtitle: subtitle, status: status)
                }
            } else {
                Button {
                    isShowingStatusMessage = true
                } label: {
                    SettingsRowContent(icon: icon, tint: tint, title: title, value: value, subtitle: subtitle, status: status)
                }
            }
        }
        .buttonStyle(KXPressableStyle(scale: 0.985, dim: 0.9))
        .alert(title, isPresented: $isShowingStatusMessage) {
            Button(L("ok", language), role: .cancel) {}
        } message: {
            Text(status.title(language) ?? subtitle)
        }
    }
}

struct SettingsRowContent: View {
    let icon: String
    let tint: Color
    let title: String
    var value: String?
    let subtitle: String
    var status: KXSettingsRowStatus = .implemented
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack(spacing: 13) {
            // Restrained: tinted glyph on a faint same-colour wash (was a
            // saturated gradient square with a coloured drop-shadow — iOS-14-era
            // "Shortcuts" look that made the settings list feel busy).
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: KXRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: KXSpacing.xs) {
                if let value, !value.isEmpty {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .truncationMode(.middle)
                        .frame(maxWidth: 132, alignment: .trailing)
                }

                if let statusTitle = status.title(language) {
                    Text(statusTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(status.isInteractive ? .secondary : KXColor.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .kxGlassCapsule(isSelected: false)
                }
            }

            if status.isInteractive {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 60)
        // Without an explicit hit shape, SwiftUI only registers taps on the
        // rendered glyphs (icon/text) — the gaps and trailing space fall
        // through, so the row "doesn't respond unless you hit the text".
        // Make the whole row rectangle tappable.
        .contentShape(Rectangle())
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 62)
            .padding(.trailing, KXSpacing.md)
    }
}

struct ProfileMetricBox: View {
    let icon: String
    let value: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
            HStack(spacing: KXSpacing.xs) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(NumberFormatterUtils.compact(value))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KXSpacing.sm)
        .kxGlassSurface(radius: KXRadius.sm, stroke: KaiXTheme.mutedGlassStroke)
    }
}
