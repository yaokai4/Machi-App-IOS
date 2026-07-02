import SwiftUI

/// 我的工作台 — the personal action hub, split out of the Guide tab.
///
/// Guide (指南) is now a pure reference library: 查学校、公司、签证、申请方法.
/// Everything you *do* — Todo、日历、申请、家计簿、生活支付、合同、证件期限 — lives
/// here under 我的, reached via the `.personalWorkbench` route from both the 我的
/// entry card and the Guide-home light CTA. This removes the "大杂烩" where Guide
/// mixed "帮我查" with "帮我办完事".
///
/// Guests can browse the full structure as a preview; saving/syncing prompts
/// login at the point of action (the Todo composer and each leaf page already
/// gate on save), so there is no heavy login wall just to look around.
struct PersonalWorkbenchView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = GuideViewModel()
    /// Bumped on pull-to-refresh / re-appear; drives GuideDigestCardView's
    /// `.task(id:)` so 本月要点 numbers never go stale after 记账 in a leaf page.
    @State private var digestRefreshToken = 0
    @State private var hasAppeared = false

    let currentUser: UserEntity

    private var isGuest: Bool { currentUser.isGuest }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header

                    if isGuest {
                        guestNotice
                    }

                    // 1) 今日摘要:今日待办 / 即将到期 / 最近重要日期 + 「继续下一步」。
                    todaySummaryCard

                    // 2) 本月要点 — finance digest (账单/解约窗口/预算/证件到期). Hidden
                    //    for guests by the card itself.
                    GuideDigestCardView(isGuest: isGuest, refreshToken: digestRefreshToken)

                    // 3) 我的事务 — the canonical action directory.
                    affairsSection

                    // 4) 我的资料与服务 — purchased library / service requests / orders.
                    //    These are inherently personal + login-only, so hide them
                    //    for guests (who already see the login CTA above) rather
                    //    than pushing views that 401.
                    if !isGuest {
                        resourcesSection
                    }
                }
                .padding(.horizontal, KXSpacing.screen)
                .padding(.top, 10)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideText(language, "我的工作台", "マイワークベンチ", "My Workbench"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadGuideOS() }
        .refreshable {
            digestRefreshToken &+= 1
            await viewModel.loadGuideOS(force: true)
        }
        .onAppear {
            // First appearance is loaded by .task; re-appearing (popping back
            // from 记账/合同 etc.) force-refreshes both the digest and the
            // summary so the dashboard reflects what was just saved.
            guard hasAppeared else { hasAppeared = true; return }
            digestRefreshToken &+= 1
            Task { await viewModel.loadGuideOS(force: true) }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                Text(guideText(language, "今日管理", "今日の管理", "Today"))
            }
            .font(.caption.weight(.black))
            .tracking(0.8)
            .foregroundStyle(KXColor.accent)

            Text(guideText(language, "我的工作台", "マイワークベンチ", "My Workbench"))
                .kxScaledFont(28, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                .foregroundStyle(.primary)

            Text(guideText(
                language,
                "Todo、日历、申请、账单、合同和证件期限，集中在这里管理。",
                "Todo・カレンダー・申請・支払い・契約・証明書の期限をここで管理。",
                "Tasks, calendar, applications, bills, contracts, and document expiries — all managed here."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var guestNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.badge.clock")
                .font(.title3.weight(.bold))
                .foregroundStyle(KXColor.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(guideText(language, "先看看，登录后再保存", "まず確認、ログインで保存", "Browse now, log in to save"))
                    .font(.subheadline.weight(.bold))
                Text(guideText(
                    language,
                    "可以随意浏览这些工具；添加 Todo、设提醒或保存时再登录即可。",
                    "ツールは自由に閲覧できます。Todo追加・リマインダー・保存時にログイン。",
                    "Explore freely. Log in only when you add a todo, set a reminder, or save."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(guideText(language, "登录", "ログイン", "Log in")) {
                GuestGate.shared.requireLogin(guideText(
                    language,
                    "登录后可以保存并同步你的 Todo、日历、申请和提醒。",
                    "ログインするとTodo・カレンダー・申請・リマインダーを保存・同期できます。",
                    "Log in to save and sync your tasks, calendar, applications, and reminders."
                ))
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(KXColor.accent)
        }
        .padding(14)
        .background(KXColor.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KXColor.accent.opacity(0.25), lineWidth: 1))
    }

    // MARK: 今日摘要

    private var todayCount: Int { viewModel.guideOS?.todayTodos.count ?? 0 }
    /// Overdue = open todos dated before the local today. `openTodos` is the
    /// server's date-ascending open list, so overdue items sort first and this
    /// count is honest up to the payload's limit.
    private var overdueCount: Int {
        let today = GuideOSDate.today()
        return (viewModel.guideOS?.openTodos ?? []).filter {
            let when = String(($0.displayDate ?? "").prefix(10))
            return !when.isEmpty && when < today
        }.count
    }
    /// Upcoming excludes today's items so the three tiles don't double-count.
    private var upcomingCount: Int {
        let today = GuideOSDate.today()
        return (viewModel.guideOS?.upcomingTodos ?? []).filter {
            String(($0.displayDate ?? "").prefix(10)) > today
        }.count
    }

    private var todaySummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                // 逾期 / 今日 land on the todo list (逾期 group tops "我的一天");
                // 即将到期 lands on the calendar agenda of the coming days.
                summaryStat("\(overdueCount)", guideText(language, "逾期", "期限切れ", "Overdue"), tint: overdueCount > 0 ? .red : .secondary) {
                    router.open(.guidePlan)
                }
                summaryStat("\(todayCount)", guideText(language, "今日待办", "今日のTodo", "Today"), tint: KXColor.accent) {
                    router.open(.guidePlan)
                }
                summaryStat("\(upcomingCount)", guideText(language, "即将到期", "まもなく期限", "Upcoming"), tint: .orange) {
                    router.open(.guideCalendar)
                }
            }
            Button {
                if isGuest {
                    GuestGate.shared.requireLogin(guideText(language, "登录后可以安排和同步今天的待办。", "ログインすると今日のTodoを計画・同期できます。", "Log in to plan and sync today's tasks."))
                } else {
                    router.open(.guidePlan)
                }
            } label: {
                HStack {
                    Text(isGuest
                         ? guideText(language, "登录后开始安排今天", "ログインして今日を計画", "Log in to plan today")
                         : (todayCount > 0
                            ? guideText(language, "继续完成今天的待办", "今日のTodoを続ける", "Continue today's tasks")
                            : guideText(language, "去安排今天要做的事", "今日の予定を立てる", "Plan what to do today")))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .frame(maxWidth: .infinity)
                .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.fullArea)
            .contentShape(Rectangle())
            .accessibilityIdentifier("workbench.continue")
        }
        .padding(16)
        .kxGlassSurface(radius: KXRadius.hero, elevated: true)
    }

    private func summaryStat(_ value: String, _ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(value)
                    .kxScaledFont(22, relativeTo: .title2, weight: .black, design: .rounded)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(KXColor.accentSoft.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.fullArea)
        .accessibilityHint(guideText(language, "查看对应的待办", "該当するTodoを見る", "Open matching tasks"))
    }

    // MARK: 我的事务

    private struct Affair: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let tint: Color
        let route: KXRoute
    }

    private var affairs: [Affair] {
        [
            .init(
                title: guideText(language, "日历", "カレンダー", "Calendar"),
                subtitle: guideText(language, "月 / 周 / 日程与未来 30 天提醒", "月・週・日程と今後30日", "Month / week / agenda & next 30 days"),
                icon: "calendar", tint: .blue, route: .guideCalendar
            ),
            .init(
                title: guideText(language, "目标路径", "目標 / パス", "Goals & paths"),
                subtitle: guideText(language, "就职、升学、JLPT、租房模板", "就職・進学・JLPT・賃貸テンプレート", "Jobs, study, JLPT, housing templates"),
                icon: "point.topleft.down.curvedto.point.bottomright.up", tint: .indigo, route: .guideGoals
            ),
            .init(
                title: guideText(language, "申请管理", "申請管理", "Applications"),
                subtitle: guideText(language, "大学、新卒、转职、JLPT、签证申请", "大学・新卒・転職・JLPT・ビザ申請", "School, job, JLPT, visa applications"),
                icon: "briefcase.fill", tint: .pink, route: .guideApplications
            ),
            .init(
                title: guideText(language, "家计簿", "家計簿", "Finance"),
                subtitle: guideText(language, "记一笔收支、看本月结余与分类预算", "収支記録・今月の収支・予算", "Log income/expense, balance & budgets"),
                icon: "wallet.bifold.fill", tint: .green, route: .guideFinance
            ),
            .init(
                title: guideText(language, "生活支付", "生活支払い", "Bills"),
                subtitle: guideText(language, "房租、水电、通信、保险、年金、税金", "家賃・公共料金・通信・保険・年金・税金", "Rent, utilities, telecom, insurance, tax"),
                icon: "yensign.circle.fill", tint: .orange, route: .guideLifePlanner
            ),
            .init(
                title: guideText(language, "合同管理", "契約管理", "Contracts"),
                subtitle: guideText(language, "续约 / 解约窗口提醒", "更新・解約期限のリマインダー", "Renewal / cancellation window alerts"),
                icon: "doc.text.fill", tint: .teal, route: .guideContracts
            ),
            .init(
                title: guideText(language, "证件期限", "証明書の期限", "Documents"),
                subtitle: guideText(language, "在留卡、护照、My Number、驾照", "在留カード・パスポート・My Number・免許", "Residence card, passport, My Number, license"),
                icon: "person.text.rectangle.fill", tint: .cyan, route: .guideDocuments
            ),
        ]
    }

    private var affairsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideSectionHeader(
                title: guideText(language, "我的事务", "マイタスク", "My affairs"),
                subtitle: guideText(language, "需要时进入对应管理页，日期会自动同步到 Todo 和日历。", "必要に応じて各管理ページへ。日付はTodoとカレンダーに同期。", "Open any tool when you need it; dates sync into Tasks and Calendar.")
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(affairs) { affair in
                    Button {
                        router.open(affair.route)
                    } label: {
                        affairTile(affair)
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("workbench.affair.\(routeKey(affair.route))")
                }
            }
        }
    }

    private func affairTile(_ affair: Affair) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: affair.icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(affair.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(affair.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(affair.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(14)
        .background(KXColor.livingSurface.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8))
    }

    private func routeKey(_ route: KXRoute) -> String {
        switch route {
        case .guidePlan: return "todo"
        case .guideCalendar: return "calendar"
        case .guideGoals: return "goals"
        case .guideApplications: return "applications"
        case .guideFinance: return "finance"
        case .guideLifePlanner: return "bills"
        case .guideContracts: return "contracts"
        case .guideDocuments: return "documents"
        default: return "item"
        }
    }

    // MARK: 我的资料与服务

    private var resourcesSection: some View {
        SettingsSectionCard(title: guideText(language, "我的资料与服务", "資料・サービス", "Library & services")) {
            SettingsRowLink(
                icon: "books.vertical.fill", tint: KXColor.accent,
                title: guideText(language, "我的资料库", "マイ資料庫", "My library"),
                subtitle: guideText(language, "已购买和会员解锁的资料", "購入・会員解放した資料", "Purchased & member-unlocked resources")
            ) {
                GuideMyLibraryView()
            }
            SettingsDivider()
            SettingsRowLink(
                icon: "bag.fill", tint: .purple,
                title: guideText(language, "我的服务", "マイサービス", "My services"),
                subtitle: guideText(language, "履历书、研究计划书、面试、签证、租房服务", "履歴書・研究計画書・面接・ビザ・賃貸サービス", "Resume, research plan, interview, visa, housing")
            ) {
                GuideServicesView()
            }
            SettingsDivider()
            SettingsRowLink(
                icon: "doc.plaintext.fill", tint: .green,
                title: guideText(language, "我的订单", "注文履歴", "My orders"),
                subtitle: guideText(language, "购买记录与支付状态", "購入履歴と支払い状況", "Purchase history & payment status")
            ) {
                MyOrdersView()
            }
        }
    }
}
