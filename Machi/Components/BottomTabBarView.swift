import SwiftUI

struct BottomTabBarView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var selection: AppTab
    var currentUser: UserEntity?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 2) {
                        tabIcon(tab, isSelected: isSelected)
                            .frame(width: 34, height: 30, alignment: .center)

                        Text(tab.title(language))
                            .font(.system(size: 10, weight: isSelected ? .bold : .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .frame(height: 12, alignment: .center)
                    }
                    .foregroundStyle(isSelected ? KXColor.accent : Color.primary.opacity(0.88))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56, alignment: .center)
                    .background {
                        if isSelected {
                            SelectedTabBubble()
                                .frame(width: 74, height: 54)
                        }
                    }
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title(language))
                .accessibilityIdentifier("tabbar.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: 430)
        .background {
            if reduceTransparency {
                Capsule().fill(KXColor.elevatedBackground.opacity(0.94))
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.032))
                    .glassEffect(Glass.regular.tint(Color.white.opacity(0.026)), in: Capsule())
                    .overlay(Capsule().fill(Color.white.opacity(0.024)))
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().stroke(KXColor.glassStroke.opacity(0.34), lineWidth: 0.65))
        .overlay(Capsule().stroke(Color.white.opacity(0.46), lineWidth: 0.4).padding(1))
        .shadow(color: Color.black.opacity(0.09), radius: 14, y: 7)
        .shadow(color: Color.white.opacity(0.42), radius: 1, y: -0.5)
        .padding(.horizontal, 22)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("main.bottomTabBar")
    }

    @ViewBuilder
    private func tabIcon(_ tab: AppTab, isSelected: Bool) -> some View {
        if tab == .profile {
            AvatarView(user: currentUser, size: 24)
                .saturation(isSelected ? 1 : 0.85)
                .overlay {
                    Circle()
                        .stroke(isSelected ? KXColor.accent.opacity(0.58) : KXColor.glassStroke.opacity(0.42), lineWidth: isSelected ? 1.1 : 0.45)
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: tab.icon)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .frame(width: 30, height: 30, alignment: .center)
        }
    }
}

private struct SelectedTabBubble: View {
    var body: some View {
        Capsule()
            .fill(KXColor.accent.opacity(0.085))
            .glassEffect(Glass.regular.tint(KXColor.accent.opacity(0.075)).interactive(), in: Capsule())
            .overlay(Capsule().stroke(KXColor.accent.opacity(0.16), lineWidth: 0.65))
            .overlay(Capsule().stroke(Color.white.opacity(0.58), lineWidth: 0.4).padding(1))
            .shadow(color: KXColor.accent.opacity(0.10), radius: 7, y: 3)
    }
}
