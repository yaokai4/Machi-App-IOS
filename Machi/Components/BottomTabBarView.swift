import SwiftUI

struct BottomTabBarView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var messageStore: MessageStore
    @EnvironmentObject private var notificationStore: NotificationStore
    @Binding var selection: AppTab
    var currentUser: UserEntity?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(KXMotion.select) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: KXSpacing.xxs) {
                        tabIcon(tab, isSelected: isSelected)
                            .frame(width: 42, height: 32, alignment: .center)
                            .overlay(alignment: .topTrailing) {
                                if let count = badgeCount(for: tab), count > 0 {
                                    TabUnreadBadge(count: count)
                                        .offset(x: 2, y: -5)
                                }
                            }

                        Text(tab.title(language))
                            .kxScaledFont(10, relativeTo: .caption2, weight: isSelected ? .bold : .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            // Scale with Dynamic Type (was frozen at 10pt), but
                            // cap so very large accessibility sizes can't blow out
                            // the fixed-height bar.
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            .frame(minHeight: 12, alignment: .center)
                    }
                    .foregroundStyle(isSelected ? KXColor.accent : Color.primary.opacity(0.88))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58, alignment: .center)
                    .background {
                        if isSelected {
                            SelectedTabBubble()
                                .frame(width: 76, height: 56)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title(language))
                .accessibilityValue(unreadAccessibilityValue(for: tab))
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
                // Single glass layer + one hairline + one soft shadow. Dropped
                // the triple white fills, the inset white stroke, and the fake
                // white negative-offset "highlight" shadow (which flashed a pale
                // rim over dark/coloured page backgrounds — cheap-looking).
                Capsule()
                    .fill(Color.white.opacity(0.03))
                    .kxLiquidGlass(.bar, in: Capsule(), interactive: false)
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().stroke(KXColor.glassStroke.opacity(0.4), lineWidth: 0.7))
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 8)
        .padding(.horizontal, 22)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("main.bottomTabBar")
    }

    private func badgeCount(for tab: AppTab) -> Int? {
        switch tab {
        case .messages:
            return messageStore.totalUnreadCount
        default:
            return nil
        }
    }

    /// Spoken unread count for VoiceOver — the badge overlay is
    /// accessibilityHidden, so without this the unread number is unreachable to
    /// screen-reader users (they'd only hear "消息"). Empty when there's none.
    private func unreadAccessibilityValue(for tab: AppTab) -> String {
        guard let count = badgeCount(for: tab), count > 0 else { return "" }
        return KXListingCopy.pickText(language, "\(count) 条未读", "未読 \(count) 件", "\(count) unread")
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
        } else if tab == .guide {
            // 自有 Machi AI 标志(M + 灵光),继承上方 .foregroundStyle 的选中/未选中着色。
            MachiAIGlyph(lineWidth: isSelected ? 2.5 : 2.0)
                .frame(width: 28, height: 28, alignment: .center)
                .frame(width: 30, height: 30, alignment: .center)
        } else {
            Image(systemName: tab.icon)
                .kxScaledFont(22, weight: .semibold)
                // Scales for accessibility but capped so a very large Dynamic
                // Type size can't blow the icon out of the fixed-height bar
                // (matches the label cap above).
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .symbolRenderingMode(.monochrome)
                .frame(width: 30, height: 30, alignment: .center)
        }
    }
}

private struct TabUnreadBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: count > 99 ? 9 : count > 9 ? 9.5 : 10, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(minWidth: badgeWidth, minHeight: 17)
            .padding(.horizontal, count > 99 ? 3 : count > 9 ? 2 : 0)
            .background(KXColor.badge, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.95), lineWidth: 1.4))
            .shadow(color: KXColor.badge.opacity(0.18), radius: 3.5, y: 1)
            .accessibilityHidden(true)
    }

    private var badgeWidth: CGFloat {
        if count > 99 { return 25 }
        if count > 9 { return 21 }
        return 17
    }
}

private struct SelectedTabBubble: View {
    var body: some View {
        Capsule()
            .fill(KXColor.accent.opacity(0.085))
            .kxLiquidGlass(.selected, in: Capsule(), tint: KXColor.accent.opacity(0.075))
            .overlay(Capsule().stroke(KXColor.accent.opacity(0.16), lineWidth: 0.65))
            .shadow(color: KXColor.accent.opacity(0.10), radius: 7, y: 3)
    }
}
