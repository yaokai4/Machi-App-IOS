import SwiftUI

struct GuidePlanView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = GuidePlanViewModel()

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(title: guideOSText(language, "我的 Guide 计划", "マイ Guide 計画", "My Guide plan"), subtitle: guideOSText(language, "所有手续、学习、申请、面试和生活截止日都在这里推进", "手続き・学習・申請・面接・生活期限をここで進めます", "Move every task and deadline from here"))
                    GuideOSPlanCard(plan: model.dashboard?.plan, isGuest: !model.isLoggedIn, isLoading: model.isLoading, onOpenPlan: {}, onOpenProfile: { router.open(.guideProfile) })
                    GuideOSQuickRow(items: [
                        .init(title: guideOSText(language, "日历", "カレンダー", "Calendar"), icon: "calendar", action: { router.open(.guideCalendar) }),
                        .init(title: guideOSText(language, "添加生活截止", "生活期限を追加", "Life deadline"), icon: "yensign.circle", action: { router.open(.guideLifePlanner) }),
                        .init(title: guideOSText(language, "添加申请", "申請を追加", "Application"), icon: "doc.badge.plus", action: { router.open(.guideApplications) })
                    ])
                    GuideOSRecommendationStrip(
                        products: model.dashboard?.recommendedProducts ?? [],
                        services: model.dashboard?.recommendedServices ?? [],
                        onOpenProduct: { router.open(.guideProduct(slug: $0)) },
                        onOpenServices: { router.open(.guideServices) }
                    )
                    if model.todos.isEmpty && !model.isLoading {
                        GuideOSEmptyPanel(title: guideOSText(language, "还没有待办任务", "未完了タスクはありません", "No open todos"), subtitle: guideOSText(language, "从任意行动路径生成计划，或添加出愿、ES、面试、生活缴费日期。", "アクションパスから計画を作成するか、申請・面接・生活支払い日を追加してください。", "Create a plan from a journey, or add applications, interviews, and life bills."))
                    } else {
                        ForEach(model.todos.prefix(12)) { todo in
                            GuideOSTodoCard(
                                todo: todo,
                                onComplete: { Task { await model.complete(todo) } },
                                onSetReminder: { at in await model.setReminder(todoId: todo.id, reminderAt: at) }
                            )
                        }
                        NavigationLink {
                            GuideTodoListView()
                        } label: {
                            Label(guideOSText(language, "查看全部待办", "すべてのタスク", "All todos"), systemImage: "list.bullet")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(KXColor.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    NavigationLink {
                        GuideRecommendationsView()
                    } label: {
                        Label(guideOSText(language, "完成任务的资料与服务", "タスク用の資料・サービス", "Materials & services for your tasks"), systemImage: "bag.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "我的计划", "マイ計画", "My plan"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !model.requireLogin() { return }
            await model.loadDashboard()
            await model.loadTodos()
        }
        .refreshable {
            await model.loadDashboard()
            await model.loadTodos()
        }
    }
}

struct GuideOSPlanCard: View {
    @Environment(\.appLanguage) private var language
    let plan: KaiXGuidePlanDTO?
    let isGuest: Bool
    let isLoading: Bool
    let onOpenPlan: () -> Void
    let onOpenProfile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().stroke(KXColor.accentSoft, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: CGFloat((plan?.progressPercent ?? 0)) / 100)
                        .stroke(KXColor.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(plan?.progressPercent ?? 0)%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan?.title ?? (isGuest ? guideOSText(language, "登录生成你的日本计划", "ログインして計画を作成", "Log in to create your plan") : guideOSText(language, "选择一个目标开始", "目標を選んで開始", "Pick a goal to begin")))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(plan?.nextTodo?.title ?? guideOSText(language, "从下方行动路径、出愿/ES 或生活缴费开始添加 Todo。", "下のアクションパス、申請/ES、生活支払いからTodoを追加できます。", "Start from a journey, application, or life deadline."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button(action: isGuest ? { GuestGate.shared.requireLogin("登录后可以生成和同步 Guide 计划。") } : onOpenPlan) {
                    Text(isLoading ? guideOSText(language, "同步中", "同期中", "Syncing") : guideOSText(language, "进入计划", "計画へ", "Open plan"))
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
        .contentShape(Rectangle())
                .foregroundStyle(.white)
                .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(action: isGuest ? { GuestGate.shared.requireLogin("登录后可以设置身份路径。") } : onOpenProfile) {
                    Text(guideOSText(language, "身份设置", "属性設定", "Profile"))
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
        .contentShape(Rectangle())
                .foregroundStyle(KXColor.accent)
                .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(15)
        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
