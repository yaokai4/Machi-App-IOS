import Foundation
import Combine
import SwiftUI

struct GuideOSDashboardSection: View {
    @Environment(\.appLanguage) private var language

    let data: KaiXGuideActivePlanResponse?
    let isLoading: Bool
    let message: String?
    let isGuest: Bool
    let onOpenPlan: () -> Void
    let onOpenCalendar: () -> Void
    let onOpenProfile: () -> Void
    let onOpenLife: () -> Void
    let onOpenApplications: () -> Void
    let onOpenServices: () -> Void
    let onOpenProduct: (String) -> Void
    let onCompleteTodo: (KaiXGuideTodoDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideOSHeaderRow(
                title: guideOSText(language, "今日 Guide OS", "今日の Guide OS", "Guide OS today"),
                subtitle: isGuest
                    ? guideOSText(language, "登录后把指南变成计划、Todo、日历和服务记录", "ログインするとガイドを計画・Todo・カレンダーにできます", "Log in to turn guides into plans, todos, and calendar")
                    : guideOSText(language, "把日本生活、升学、就职和日语计划推进到下一步", "生活・進学・就職・日本語を次の一歩へ", "Move life, study, career, and Japanese forward")
            )

            if let message, !message.isEmpty {
                GuideOSNotice(message: message)
            }

            GuideOSPlanCard(plan: data?.plan, isGuest: isGuest, isLoading: isLoading, onOpenPlan: onOpenPlan, onOpenProfile: onOpenProfile)

            if let todos = data?.todayTodos, !todos.isEmpty {
                GuideOSTodoStrip(title: guideOSText(language, "今天要做", "今日やること", "Today"), todos: todos, onComplete: onCompleteTodo)
            } else if !isGuest {
                GuideOSEmptyMini(text: guideOSText(language, "今天没有到期任务。可以从路径生成计划，或添加生活/申请截止日。", "今日の期限タスクはありません。パスから計画を作成するか、生活/申請期限を追加できます。", "No due tasks today. Create a plan or add life/application deadlines."))
            }

            if let upcoming = data?.upcomingTodos, !upcoming.isEmpty {
                GuideOSTodoStrip(title: guideOSText(language, "未来 7 天", "今後 7 日", "Next 7 days"), todos: Array(upcoming.prefix(6)), onComplete: onCompleteTodo)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                GuideOSActionTile(title: guideOSText(language, "我的计划", "マイ計画", "My plan"), icon: "list.bullet.clipboard.fill", tint: KXColor.accent, action: onOpenPlan)
                GuideOSActionTile(title: guideOSText(language, "日历", "カレンダー", "Calendar"), icon: "calendar", tint: .indigo, action: onOpenCalendar)
                GuideOSActionTile(title: guideOSText(language, "身份路径", "属性ルート", "Profile"), icon: "person.crop.circle.badge.checkmark", tint: .teal, action: onOpenProfile)
                GuideOSActionTile(title: guideOSText(language, "生活缴费", "生活支払い", "Life bills"), icon: "yensign.circle.fill", tint: .orange, action: onOpenLife)
                GuideOSActionTile(title: guideOSText(language, "出愿 / ES", "出願 / ES", "Applications"), icon: "doc.text.magnifyingglass", tint: .pink, action: onOpenApplications)
                GuideOSActionTile(title: guideOSText(language, "资料服务", "資料・サービス", "Services"), icon: "bag.fill", tint: .purple, action: onOpenServices)
            }

            GuideOSRecommendationStrip(
                products: data?.recommendedProducts ?? [],
                services: data?.recommendedServices ?? [],
                onOpenProduct: onOpenProduct,
                onOpenServices: onOpenServices
            )
        }
        .padding(15)
        .kxGlassSurface(radius: 24, elevated: true)
    }
}

struct GuidePlannerFormShell<Fields: View, Saved: View>: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let subtitle: String
    @ObservedObject var model: GuideOSViewModel
    @ViewBuilder let fields: () -> Fields
    @ViewBuilder let savedSection: () -> Saved

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(title: title, subtitle: subtitle)
                    VStack(spacing: 12) { fields() }
                        .padding(15)
                        .kxGlassSurface(radius: 22)
                    if let message = model.message { GuideOSNotice(message: message) }
                    savedSection()
                    if model.todos.isEmpty && !model.isLoading {
                        GuideOSEmptyMini(text: guideOSText(language, "添加后会自动出现在我的计划和日历里。", "追加するとマイ計画とカレンダーに表示されます。", "New items will appear in My plan and Calendar."))
                    } else {
                        ForEach(model.todos.prefix(30)) { todo in
                            GuideOSTodoCard(todo: todo) { Task { await model.complete(todo) } }
                        }
                    }
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GuideOSHeaderRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GuideOSActionTile: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct GuideOSQuickRow: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let action: () -> Void
    }
    let items: [Item]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                Button(action: item.action) {
                    Label(item.title, systemImage: item.icon)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
        .contentShape(Rectangle())
                .foregroundStyle(KXColor.accent)
                .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }
}

struct GuideOSTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .font(.subheadline)
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct GuideOSDeleteCardChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(KXColor.softBackground, in: Capsule())
    }
}

struct GuideOSPrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .foregroundStyle(.white)
        .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct GuideOSNotice: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct GuideOSMiniBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(KXColor.softBackground, in: Capsule())
    }
}

struct GuideOSEmptyMini: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct GuideOSEmptyPanel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(KXColor.accent)
            Text(title)
                .font(.headline.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .kxGlassSurface(radius: 20)
    }
}
