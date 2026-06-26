import Foundation
import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GuideOSDashboardSection: View {
    @Environment(\.appLanguage) private var language

    let data: KaiXGuideActivePlanResponse?
    let isLoading: Bool
    let message: String?
    let isGuest: Bool
    let onOpenPlan: () -> Void
    let onOpenCalendar: () -> Void
    let onOpenManage: () -> Void
    let onCompleteTodo: (KaiXGuideTodoDTO) -> Void
    let onCreateTodo: (_ content: String, _ plannedDate: String?) async -> Bool

    private var todayTodos: [KaiXGuideTodoDTO] { data?.todayTodos ?? [] }
    private var upcomingTodos: [KaiXGuideTodoDTO] { data?.upcomingTodos ?? [] }
    private var hasAnyTodos: Bool { !todayTodos.isEmpty || !upcomingTodos.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GuideOSHeaderRow(
                // The hero card above already says "今日 / Today"; name this
                // section by its function so the two headers don't read as a
                // duplicated "今日 / 今日" stack.
                title: guideOSText(language, "今日", "今日", "Today"),
                subtitle: isGuest
                    ? guideOSText(language, "登录后同步 Todo、日历和截止日", "ログインするとTodo・カレンダー・期限を同期できます", "Log in to sync todos, calendar, and deadlines")
                    : guideOSText(language, "今天要做的事和即将到期的截止日", "今日やることと近づく期限", "What's due today and coming up")
            )

            if let message, !message.isEmpty {
                GuideOSNotice(message: message)
            }

            // Only surface the goal card when there is a genuinely in-progress
            // plan (<100%). A finished or absent plan no longer takes the hero
            // slot — that was the source of the stale "刚到日本 7 天 100%" card.
            if let plan = data?.plan, plan.progressPercent < 100 {
                GuideOSPlanCard(plan: plan, isGuest: isGuest, isLoading: isLoading, onOpenPlan: onOpenPlan)
            }

            // ONE place to add a task. The full list (我的一天/重要/计划中/已完成)
            // is one "全部待办" tap away, so there are no duplicated 待办 buttons.
            GuideQuickTodoComposer(isSaving: isLoading, onCreate: onCreateTodo)

            if !todayTodos.isEmpty {
                GuideOSTodoStrip(title: guideOSText(language, "今天要做", "今日やること", "Today"), todos: todayTodos, onComplete: onCompleteTodo)
            }

            if !upcomingTodos.isEmpty {
                GuideOSTodoStrip(title: guideOSText(language, "即将到期", "まもなく期限", "Upcoming"), todos: Array(upcomingTodos.prefix(6)), onComplete: onCompleteTodo)
            }

            if !isGuest, hasAnyTodos {
                Button(action: onOpenPlan) {
                    Label(guideOSText(language, "全部待办", "すべてのTodo", "All tasks"), systemImage: "list.bullet")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.fullArea)
                .contentShape(Rectangle())
                .accessibilityIdentifier("guide.quick.todo")
            }

            // Two distinct destinations only: 待办 lives above, so the row keeps
            // just 日历 and 管理 (路径 is now an optional template inside 管理).
            GuideOSQuickRow(items: [
                .init(title: guideOSText(language, "日历", "カレンダー", "Calendar"), icon: "calendar", accessibilityId: "guide.quick.calendar", action: onOpenCalendar),
                .init(title: guideOSText(language, "管理", "管理", "Manage"), icon: "folder.fill.badge.gearshape", accessibilityId: "guide.quick.manage", action: onOpenManage)
            ])
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
                            GuideOSTodoCard(
                                todo: todo,
                                onComplete: { Task { await model.complete(todo) } },
                                onSetReminder: { at in await model.setReminder(todoId: todo.id, reminderAt: at) },
                                onReschedule: { date in Task { await model.reschedule(todo, to: date) } },
                                onUpdateSteps: { steps in Task { await model.updateTodoSteps(todo, steps: steps) } },
                                onUpdateNotes: { notes in Task { await model.updateTodoNotes(todo, notes: notes) } }
                            )
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
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(KXColor.livingSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.fullArea)
    }
}

struct GuideOSQuickRow: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        /// Stable, locale-independent accessibility identifier so UI tests can
        /// find the button by id (e.g. `guide.quick.calendar`) instead of the
        /// localized label, which shifts between zh/ja/en.
        var accessibilityId: String? = nil
        let action: () -> Void
    }
    let items: [Item]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(items) { item in
                Button(action: item.action) {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 30, height: 30)
                        Text(item.title)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .padding(.horizontal, 12)
                    .foregroundStyle(KXColor.accent)
                    .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.fullArea)
                .accessibilityIdentifier(item.accessibilityId ?? "")
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

/// Unified compact date field: a small caption label ABOVE a full-width date
/// pill, so labels never get truncated (the old inline DatePicker squeezed
/// 开始/结束 down to 开/结) and two can sit side-by-side cleanly.
struct GuideOSDateField: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct GuideQuickTodoComposer: View {
    @Environment(\.appLanguage) private var language
    let defaultDate: String?
    let isSaving: Bool
    /// Returns `true` only when the todo was actually persisted. A guest tap or
    /// an expired token returns `false` (after prompting login) so the composer
    /// can keep the draft instead of silently discarding it.
    let onCreate: (_ content: String, _ plannedDate: String?) async -> Bool

    @State private var text = ""
    @State private var selectedDate: String?
    @State private var customDate = Date()
    @State private var showDatePicker = false

    private var isPresetDate: Bool { selectedDate == shifted(0) || selectedDate == shifted(1) || selectedDate == shifted(7) }

    init(defaultDate: String? = nil, isSaving: Bool = false, onCreate: @escaping (_ content: String, _ plannedDate: String?) async -> Bool) {
        self.defaultDate = defaultDate
        self.isSaving = isSaving
        self.onCreate = onCreate
        _selectedDate = State(initialValue: defaultDate)
    }

    private func shifted(_ days: Int) -> String {
        GuideOSDate.iso(Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSaving else { return }
        // Keep the draft until the save actually succeeds. For a guest or an
        // expired token onCreate returns false (after prompting login), so the
        // user's text survives the login round-trip instead of vanishing.
        Task { @MainActor in
            if await onCreate(trimmed, selectedDate) {
                text = ""
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(KXColor.accent)
                    TextField(guideOSText(language, "直接输入 Todo：明天提交 ES / 7月25日前交房租", "Todoを直接入力：明日ES提出 / 7月25日までに家賃", "Quick add: submit ES tomorrow / rent by Jul 25"), text: $text)
                        .font(.subheadline.weight(.semibold))
                        .submitLabel(.done)
                        .onSubmit(submit)
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(KXColor.livingSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8)
                )

                Button(action: submit) {
                    Text(isSaving ? guideOSText(language, "添加中", "追加中", "Adding") : guideOSText(language, "添加", "追加", "Add"))
                        .font(.subheadline.weight(.bold))
                        .frame(width: 62, height: 46)
                }
                .buttonStyle(.fullArea)
                .contentShape(Rectangle())
                .foregroundStyle(.white)
                .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? KXColor.accent.opacity(0.42) : KXColor.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    GuideQuickDateChip(title: guideOSText(language, "今天", "今日", "Today"), isSelected: selectedDate == shifted(0)) { selectedDate = shifted(0) }
                    GuideQuickDateChip(title: guideOSText(language, "明天", "明日", "Tomorrow"), isSelected: selectedDate == shifted(1)) { selectedDate = shifted(1) }
                    GuideQuickDateChip(title: "+7 天", isSelected: selectedDate == shifted(7)) { selectedDate = shifted(7) }
                    GuideQuickDateChip(
                        title: (selectedDate != nil && !isPresetDate) ? GuideOSDate.short(selectedDate!) : guideOSText(language, "其他日期", "他の日付", "Pick date"),
                        isSelected: selectedDate != nil && !isPresetDate
                    ) { showDatePicker = true }
                    if selectedDate != nil {
                        Button {
                            selectedDate = nil
                        } label: {
                            Text(guideOSText(language, "不设日期", "日付なし", "No date"))
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                        }
                        .buttonStyle(.fullArea)
                        .contentShape(Rectangle())
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: defaultDate ?? "") { _, newValue in
            selectedDate = newValue.isEmpty ? nil : newValue
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker(guideOSText(language, "选择日期", "日付を選ぶ", "Pick a date"), selection: $customDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle(guideOSText(language, "选择日期", "日付", "Date"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(guideOSText(language, "完成", "完了", "Done")) {
                                selectedDate = GuideOSDate.iso(customDate)
                                showDatePicker = false
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button(guideOSText(language, "取消", "キャンセル", "Cancel")) { showDatePicker = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }
}

private struct GuideQuickDateChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 11)
                .frame(height: 30)
                .frame(minWidth: 50)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
        .foregroundStyle(isSelected ? .white : .secondary)
        .background(isSelected ? KXColor.accent : KXColor.livingSurface.opacity(0.82), in: Capsule())
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
        .buttonStyle(.fullArea)
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

struct GuideManageView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    private var items: [GuideManageItem] {
        [
            .init(
                // Journeys are now an *optional* template library here rather than
                // a top-level home tab:套用后会生成一组可删的待办，用户想要才用。
                title: guideOSText(language, "目标 / 路径", "目標 / パス", "Goals / paths"),
                subtitle: guideOSText(language, "可选模板：就职、升学、JLPT、租房等，套用后生成一组可删的待办", "任意テンプレート：就職・進学・JLPT・賃貸など。適用するとTodoを生成", "Optional templates: jobs, study, JLPT, housing — apply to seed deletable todos"),
                icon: "point.topleft.down.curvedto.point.bottomright.up",
                tint: .blue,
                action: { router.open(.guideGoals) }
            ),
            .init(
                title: guideOSText(language, "收支记账", "家計簿", "Finance"),
                subtitle: guideOSText(language, "记一笔收支、看本月结余、设分类预算；不连银行，只记你填的数", "収入・支出を記録、今月の収支、カテゴリ予算。銀行連携なし", "Log income/expense, monthly balance, budgets. No bank link."),
                icon: "wallet.bifold.fill",
                tint: .green,
                action: { router.open(.guideFinance) }
            ),
            .init(
                title: guideOSText(language, "生活缴费", "生活支払い", "Bills"),
                subtitle: guideOSText(language, "房租、水电、网络、手机、保险、年金、税金、学费", "家賃・公共料金・ネット・携帯・保険・年金・税金・学費", "Rent, utilities, phone, insurance, pension, tax, tuition"),
                icon: "yensign.circle.fill",
                tint: .orange,
                action: { router.open(.guideLifePlanner) }
            ),
            .init(
                title: guideOSText(language, "合同管理", "契約管理", "Contracts"),
                subtitle: guideOSText(language, "租房、手机、网络、保险、学校和工作合同的续约/解约提醒", "賃貸・携帯・ネット・保険・学校・仕事の契約リマインダー", "Lease, phone, internet, insurance, school and work contract reminders"),
                icon: "doc.text.fill",
                tint: KXColor.accent,
                action: { router.open(.guideContracts) }
            ),
            .init(
                title: guideOSText(language, "证件到期", "証明書期限", "Documents"),
                subtitle: guideOSText(language, "在留卡、护照、My Number、驾照；只填日期，不上传证件", "在留カード・パスポート・My Number・免許。日付だけでOK", "Residence card, passport, My Number, license. Dates only."),
                icon: "person.text.rectangle.fill",
                tint: .cyan,
                action: { router.open(.guideDocuments) }
            ),
            .init(
                title: guideOSText(language, "申请管理", "申請管理", "Applications"),
                subtitle: guideOSText(language, "大学、大学院、语言学校、新卒、转职、JLPT、签证申请", "大学・大学院・語学学校・新卒・転職・JLPT・ビザ申請", "School, job, transfer, JLPT, and visa applications"),
                icon: "briefcase.fill",
                tint: .pink,
                action: { router.open(.guideApplications) }
            ),
            .init(
                title: guideOSText(language, "个人提醒设置", "個人リマインダー設定", "Reminder settings"),
                subtitle: guideOSText(language, "可选填写城市、目标、毕业/在留/护照到期日", "都市・目標・卒業/在留/パスポート期限を任意入力", "Optional city, goals, graduation, visa, and passport dates"),
                icon: "bell.badge.fill",
                tint: .indigo,
                action: { router.open(.guideProfile) }
            ),
            .init(
                title: guideOSText(language, "文件与资料", "資料・サービス", "Resources"),
                subtitle: guideOSText(language, "履历书、研究计划书、JLPT、面试、签证、租房资料服务", "履歴書・研究計画書・JLPT・面接・ビザ・賃貸資料", "Resume, research plan, JLPT, interviews, visa, housing resources"),
                icon: "bag.fill",
                tint: .purple,
                action: { router.open(.guideServices) }
            )
        ]
    }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(
                        title: guideOSText(language, "管理", "管理", "Manage"),
                        subtitle: guideOSText(language, "生活缴费、合同、证件、申请和资料服务统一管理，日期会同步到 Todo 和日历。", "支払い・契約・証明書・申請・資料を一元管理し、日付はTodoとカレンダーへ同期します。", "Bills, contracts, documents, applications, and resources sync dates into Tasks and Calendar.")
                    )
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(items) { item in
                            Button(action: item.action) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 21, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 42, height: 42)
                                        .background(item.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    Text(item.title)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(item.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 166, alignment: .topLeading)
                                .padding(14)
                                .background(KXColor.livingSurface.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8))
                            }
                            .buttonStyle(.fullArea)
                            .contentShape(Rectangle())
                        }
                    }
                    GuideOSEmptyMini(text: guideOSText(language, "隐私原则：不需要上传在留卡或护照。你可以只填写希望提醒的日期，也可以完全不填写。", "プライバシー：在留カードやパスポートのアップロードは不要です。必要な日付だけ入力できます。", "Privacy: no residence card or passport upload is needed. Add only the reminder dates you want."))
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "管理", "管理", "Manage"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GuideContractsView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideTodoViewModel()
    @State private var editingId: String?
    @State private var category = "housing"
    @State private var title = ""
    @State private var provider = ""
    // Smart defaults: a contract usually runs ~1 year, and the Japanese
    // cancellation window is typically the 1–2 months before expiry — far more
    // useful than four identical "today" dates.
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var cancellationStart = Calendar.current.date(byAdding: .day, value: 305, to: Date()) ?? Date()
    @State private var cancellationEnd = Calendar.current.date(byAdding: .day, value: 335, to: Date()) ?? Date()
    @State private var autoRenew = false
    @State private var monthlyCost = ""
    @State private var yearlyCost = ""
    @State private var reminderDays = 30
    @State private var contactInfo = ""
    @State private var notes = ""

    private let categories = [
        ("housing", "租房合同"),
        ("phone", "手机合约"),
        ("internet", "网络合约"),
        ("insurance", "保险合同"),
        ("school", "学校合同"),
        ("employment", "工作合同"),
        ("subscription", "订阅服务"),
        ("other", "其他合同"),
    ]

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(
                        title: guideOSText(language, "合同管理", "契約管理", "Contracts"),
                        subtitle: guideOSText(language, "只记到期、续约与解约窗口并自动提醒——不需要上传合同原件，重要文件请你自己保管。", "満了・更新・解約期間だけ記録して自動通知します。契約書のアップロードは不要、原本はご自身で保管を。", "Just the expiry / renewal / cancellation dates with reminders — no need to upload the contract itself; keep the original yourself.")
                    )
                    contractForm
                    if let message = model.message { GuideOSNotice(message: message) }
                    if model.contracts.isEmpty && !model.isLoading {
                        GuideOSEmptyPanel(
                            title: guideOSText(language, "还没有合同", "契約はまだありません", "No contracts yet"),
                            subtitle: guideOSText(language, "添加租房、手机、网络、保险、学校或工作合同。", "賃貸・携帯・ネット・保険・学校・仕事の契約を追加できます。", "Add housing, phone, internet, insurance, school, or employment contracts.")
                        )
                    } else {
                        ForEach(model.contracts) { item in
                            GuideContractRow(
                                item: item,
                                onEdit: { beginEditing(item) },
                                onArchive: {
                                    Task {
                                        _ = await model.saveContract(
                                            id: item.id,
                                            payload: contractPayload(for: item, status: "archived")
                                        )
                                    }
                                },
                                onDelete: { Task { await model.deleteContract(item) } }
                            )
                        }
                    }
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "合同管理", "契約管理", "Contracts"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.requireLogin("登录后可以管理合同和到期提醒。") {
                await model.loadContracts()
            }
        }
        .refreshable { await model.loadContracts() }
    }

    private var contractForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingId == nil ? "添加合同" : "编辑合同")
                    .font(.headline.weight(.bold))
                Spacer()
                if editingId != nil {
                    Button("取消") { resetForm() }
                        .font(.caption.weight(.bold))
                        .frame(minHeight: 44)
                }
            }
            Label(guideOSText(language, "只记关键信息，不收合同原件 · 你的隐私由你掌握", "重要情報のみ記録、契約書は預かりません", "We store only key details, never the contract file"), systemImage: "lock.shield.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 32)
                .background(KXColor.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Picker("合同类型", selection: $category) {
                ForEach(categories, id: \.0) { key, label in Text(label).tag(key) }
            }
            .pickerStyle(.menu)
            GuideOSTextField(title: "合同名称", text: $title)
            GuideOSTextField(title: "机构 / 对方", text: $provider)
            HStack(alignment: .top, spacing: 10) {
                GuideOSDateField(title: "开始日期", date: $startDate)
                GuideOSDateField(title: "到期日期", date: $endDate)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("解约窗口")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 10) {
                    GuideOSDateField(title: "可解约起", date: $cancellationStart)
                    GuideOSDateField(title: "可解约止", date: $cancellationEnd)
                }
            }
            Toggle("自动续约", isOn: $autoRenew)
            HStack(spacing: 10) {
                GuideOSTextField(title: "月费 JPY", text: $monthlyCost)
                    .keyboardType(.numberPad)
                GuideOSTextField(title: "年费 JPY", text: $yearlyCost)
                    .keyboardType(.numberPad)
            }
            Stepper("提前 \(reminderDays) 天提醒", value: $reminderDays, in: 0...365)
            GuideOSTextField(title: "联系方式", text: $contactInfo)
            TextField("备注", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            GuideOSPrimaryButton(title: model.isSaving ? "保存中" : "保存合同") {
                Task {
                    let ok = await model.saveContract(id: editingId, payload: currentPayload())
                    if ok { resetForm() }
                }
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving)
        }
        .padding(15)
        .kxGlassSurface(radius: 22)
    }

    private func currentPayload() -> KaiXGuideContractPayload {
        .init(
            category: category,
            title: title,
            provider: provider,
            startDate: GuideOSDate.iso(startDate),
            endDate: GuideOSDate.iso(endDate),
            cancellationWindowStart: GuideOSDate.iso(cancellationStart),
            cancellationWindowEnd: GuideOSDate.iso(cancellationEnd),
            autoRenew: autoRenew,
            monthlyCost: Int(monthlyCost) ?? 0,
            yearlyCost: Int(yearlyCost) ?? 0,
            currency: "JPY",
            reminderDaysBefore: reminderDays,
            contactInfo: contactInfo,
            notes: notes,
            status: "active"
        )
    }

    private func contractPayload(for item: KaiXGuideContractDTO, status: String) -> KaiXGuideContractPayload {
        .init(
            category: item.category,
            title: item.title,
            provider: item.provider,
            startDate: item.startDate,
            endDate: item.endDate,
            cancellationWindowStart: item.cancellationWindowStart,
            cancellationWindowEnd: item.cancellationWindowEnd,
            autoRenew: item.autoRenew,
            monthlyCost: item.monthlyCost,
            yearlyCost: item.yearlyCost,
            currency: item.currency,
            reminderDaysBefore: item.reminderDaysBefore,
            contactInfo: item.contactInfo,
            notes: item.notes,
            status: status
        )
    }

    private func beginEditing(_ item: KaiXGuideContractDTO) {
        editingId = item.id
        category = item.category
        title = item.title
        provider = item.provider
        startDate = guideOSDate(item.startDate)
        endDate = guideOSDate(item.endDate)
        cancellationStart = guideOSDate(item.cancellationWindowStart)
        cancellationEnd = guideOSDate(item.cancellationWindowEnd)
        autoRenew = item.autoRenew
        monthlyCost = item.monthlyCost > 0 ? String(item.monthlyCost) : ""
        yearlyCost = item.yearlyCost > 0 ? String(item.yearlyCost) : ""
        reminderDays = item.reminderDaysBefore
        contactInfo = item.contactInfo
        notes = item.notes
    }

    private func resetForm() {
        editingId = nil
        category = "housing"
        title = ""
        provider = ""
        startDate = Date()
        endDate = Date()
        cancellationStart = Date()
        cancellationEnd = Date()
        autoRenew = false
        monthlyCost = ""
        yearlyCost = ""
        reminderDays = 30
        contactInfo = ""
        notes = ""
    }
}

private struct GuideContractRow: View {
    let item: KaiXGuideContractDTO
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(KXColor.accent)
                    .frame(width: 42, height: 42)
                    .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(item.title).font(.subheadline.weight(.bold)).lineLimit(2)
                        if item.autoRenew { GuideOSMiniBadge(text: "自动续约") }
                    }
                    if !item.provider.isEmpty { Text(item.provider).font(.caption).foregroundStyle(.secondary) }
                    HStack(spacing: 6) {
                        if let date = item.cancellationWindowStart ?? item.endDate {
                            GuideOSDeleteCardChip(text: GuideOSDate.short(date))
                        }
                        if item.monthlyCost > 0 { GuideOSDeleteCardChip(text: "月 ¥\(item.monthlyCost)") }
                        if item.yearlyCost > 0 { GuideOSDeleteCardChip(text: "年 ¥\(item.yearlyCost)") }
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("编辑", action: onEdit)
                    if item.status == "active" { Button("归档", action: onArchive) }
                    Button("删除", role: .destructive) { confirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .contentShape(Rectangle())
            }
            GuideAttachmentSection(entityType: "guide_contract", entityId: item.id, title: "合同附件")
        }
        .padding(13)
        .kxGlassSurface(radius: 18)
        .confirmationDialog("删除该合同及关联提醒？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        }
    }
}

struct GuideDocumentsView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideTodoViewModel()
    @State private var editingId: String?
    @State private var category = "residence_card"
    @State private var title = "在留卡"
    @State private var expiresAt = Date()
    @State private var reminderDays = 60
    @State private var notes = ""

    private let categories = [
        ("residence_card", "在留卡"),
        ("passport", "护照"),
        ("my_number", "My Number"),
        ("drivers_license", "驾照"),
        ("health_insurance", "健康保险证"),
        ("other", "其他证件"),
    ]

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(
                        title: guideOSText(language, "证件到期", "証明書期限", "Document expiry"),
                        subtitle: guideOSText(language, "只填写到期日期即可，不上传证件图片，也不需要证件号码。", "有効期限だけ入力し、画像や番号は不要です。", "Add only an expiry date. No image or document number is needed.")
                    )
                    GuideOSEmptyMini(text: "隐私优先：所有日期都可选；不填写任何身份资料也能完整使用 Guide。")
                    documentForm
                    if let message = model.message { GuideOSNotice(message: message) }
                    if model.documents.isEmpty && !model.isLoading {
                        GuideOSEmptyPanel(title: "还没有证件提醒", subtitle: "添加日期后，会自动生成高优先级 Todo 和日历提醒。")
                    } else {
                        ForEach(model.documents) { item in
                            GuideDocumentRow(
                                item: item,
                                onEdit: { beginEditing(item) },
                                onDelete: { Task { await model.deleteDocument(item) } }
                            )
                        }
                    }
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "证件到期", "証明書期限", "Document expiry"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.requireLogin("登录后可以保存证件到期提醒。") {
                await model.loadDocuments()
            }
        }
        .refreshable { await model.loadDocuments() }
    }

    private var documentForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editingId == nil ? "添加证件提醒" : "编辑证件提醒")
                    .font(.headline.weight(.bold))
                Spacer()
                if editingId != nil {
                    Button("取消") { resetForm() }
                        .font(.caption.weight(.bold))
                        .frame(minHeight: 44)
                }
            }
            Picker("证件类型", selection: $category) {
                ForEach(categories, id: \.0) { key, label in Text(label).tag(key) }
            }
            .pickerStyle(.menu)
            .onChange(of: category) { _, value in
                if let label = categories.first(where: { $0.0 == value })?.1 { title = label }
            }
            GuideOSTextField(title: "显示名称", text: $title)
            DatePicker("到期日期", selection: $expiresAt, displayedComponents: .date)
            Stepper("提前 \(reminderDays) 天提醒", value: $reminderDays, in: 0...365)
            TextField("备注", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            GuideOSPrimaryButton(title: model.isSaving ? "保存中" : "保存提醒") {
                Task {
                    let ok = await model.saveDocument(
                        id: editingId,
                        payload: .init(
                            category: category,
                            title: title,
                            expiresAt: GuideOSDate.iso(expiresAt),
                            reminderDaysBefore: reminderDays,
                            notes: notes,
                            status: "active"
                        )
                    )
                    if ok { resetForm() }
                }
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving)
        }
        .padding(15)
        .kxGlassSurface(radius: 22)
    }

    private func beginEditing(_ item: KaiXGuideDocumentDTO) {
        editingId = item.id
        category = item.category
        title = item.title
        expiresAt = guideOSDate(item.expiresAt)
        reminderDays = item.reminderDaysBefore
        notes = item.notes
    }

    private func resetForm() {
        editingId = nil
        category = "residence_card"
        title = "在留卡"
        expiresAt = Date()
        reminderDays = 60
        notes = ""
    }
}

private struct GuideDocumentRow: View {
    let item: KaiXGuideDocumentDTO
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.cyan)
                    .frame(width: 42, height: 42)
                    .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.subheadline.weight(.bold))
                    if let expiresAt = item.expiresAt {
                        Label(GuideOSDate.short(expiresAt), systemImage: "calendar.badge.exclamationmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("提前 \(item.reminderDaysBefore) 天提醒")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.fullArea)
                .contentShape(Rectangle())
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.fullArea)
                .contentShape(Rectangle())
            }
            GuideAttachmentSection(entityType: "guide_document", entityId: item.id, title: "可选附件")
        }
        .padding(13)
        .kxGlassSurface(radius: 18)
        .confirmationDialog("删除该证件提醒？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        }
    }
}

struct GuideGoalsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = GuidePlanViewModel()
    @State private var showingCreate = false
    @State private var goalTitle = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()

    private var activePlans: [KaiXGuidePlanDTO] {
        model.plans.filter { $0.status == "active" }
    }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    GuideOSHeaderRow(
                        title: guideOSText(language, "路径", "目標", "Goals"),
                        subtitle: guideOSText(language, "目标只保存一份进度，Todo 是执行主线，日历负责时间。", "目標の進捗は一つ。実行はTodo、時間はカレンダーで管理します。", "One goal progress source; tasks drive execution and calendar owns time.")
                    )

                    Button {
                        if model.requireLogin("登录后可以创建并同步自定义目标。") {
                            showingCreate.toggle()
                        }
                    } label: {
                        Label(guideOSText(language, "创建自定义目标", "カスタム目標を作成", "Create custom goal"), systemImage: "plus")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .foregroundStyle(.white)
                    .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if showingCreate {
                        VStack(alignment: .leading, spacing: 12) {
                            GuideOSTextField(
                                title: guideOSText(language, "目标名称", "目標名", "Goal title"),
                                text: $goalTitle
                            )
                            Toggle(guideOSText(language, "设置目标日期", "目標日を設定", "Set target date"), isOn: $hasTargetDate)
                            if hasTargetDate {
                                DatePicker(
                                    guideOSText(language, "目标日期", "目標日", "Target date"),
                                    selection: $targetDate,
                                    displayedComponents: .date
                                )
                            }
                            GuideOSPrimaryButton(title: model.isSaving ? "创建中" : "创建目标") {
                                Task {
                                    let ok = await model.createCustomGoal(
                                        title: goalTitle,
                                        targetDate: hasTargetDate ? GuideOSDate.iso(targetDate) : nil
                                    )
                                    if ok {
                                        goalTitle = ""
                                        hasTargetDate = false
                                        showingCreate = false
                                    }
                                }
                            }
                            .disabled(goalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving)
                        }
                        .padding(15)
                        .kxGlassSurface(radius: 20)
                    }

                    if let message = model.message {
                        GuideOSNotice(message: message)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        Text(guideOSText(language, "进行中目标", "進行中の目標", "Active goals"))
                            .font(.headline.weight(.bold))
                        if !model.isLoggedIn {
                            GuideOSEmptyMini(text: guideOSText(language, "登录后保存目标进度；下方模板仍可浏览。", "ログインすると目標の進捗を保存できます。", "Log in to save goal progress; templates remain browsable."))
                        } else if activePlans.isEmpty && !model.isLoading {
                            GuideOSEmptyMini(text: guideOSText(language, "还没有进行中目标，从下方选择模板或创建自己的目标。", "進行中の目標はありません。", "No active goals yet. Pick a template or create your own."))
                        } else {
                            ForEach(activePlans) { plan in
                                VStack(alignment: .leading, spacing: 12) {
                                    Button {
                                        if plan.sourceJourneyKey.isEmpty {
                                            router.open(.guideGoalPlan(planId: plan.id, title: plan.title))
                                        } else {
                                            router.open(.guideJourney(key: plan.sourceJourneyKey))
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 9) {
                                            HStack(alignment: .top) {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(plan.title)
                                                        .font(.subheadline.weight(.bold))
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(2)
                                                    if !plan.subtitle.isEmpty {
                                                        Text(plan.subtitle)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                            .lineLimit(2)
                                                    }
                                                }
                                                Spacer(minLength: 8)
                                                Text("\(plan.progressPercent)%")
                                                    .font(.subheadline.weight(.black))
                                                    .foregroundStyle(KXColor.accent)
                                            }
                                            GeometryReader { geometry in
                                                ZStack(alignment: .leading) {
                                                    Capsule().fill(KXColor.softBackground)
                                                    Capsule().fill(KXColor.accent)
                                                        .frame(width: geometry.size.width * CGFloat(plan.progressPercent) / 100)
                                                }
                                            }
                                            .frame(height: 7)
                                            if let next = plan.nextTodo {
                                                Text("下一步：\(next.title)")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.fullArea)
                                    .contentShape(Rectangle())
                                    GuideAttachmentSection(entityType: "guide_goal", entityId: plan.id, title: "目标附件")
                                }
                                .padding(14)
                                .kxGlassSurface(radius: 18)
                            }
                        }
                    }

                    GuideJourneyGrid(
                        journeys: model.goalJourneys,
                        suggestedKeys: model.dashboard?.suggestedJourneys?.map(\.key) ?? []
                    )
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "路径", "目標", "Goals"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.loadGoals()
            if model.isLoggedIn { await model.loadDashboard() }
        }
        .refreshable {
            await model.loadGoals()
            if model.isLoggedIn { await model.loadDashboard() }
        }
    }
}

private func guideOSDate(_ value: String?) -> Date {
    guard let value, !value.isEmpty else { return Date() }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: String(value.prefix(10))) ?? Date()
}

private struct GuideManageItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void
}

struct GuideAttachmentSection: View {
    @Environment(\.appLanguage) private var language

    let entityType: String
    let entityId: String
    var title: String = "附件"

    @State private var files: [KaiXUploadedFileDTO] = []
    @State private var isLoading = false
    @State private var isUploading = false
    @State private var showingImporter = false
    @State private var message: String?
    @State private var deleteTarget: KaiXUploadedFileDTO?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "paperclip")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(KXColor.accent)
                Text(title)
                    .font(.subheadline.weight(.black))
                if !files.isEmpty {
                    Text("\(files.count)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(KXColor.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(KXColor.accentSoft))
                }
                Spacer()
                Button {
                    showingImporter = true
                } label: {
                    Label(isUploading ? guideOSText(language, "上传中", "アップロード中", "Uploading") : guideOSText(language, "上传", "アップロード", "Upload"), systemImage: isUploading ? "arrow.triangle.2.circlepath" : "square.and.arrow.up")
                        .font(.caption.weight(.black))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(Capsule().fill(KXColor.accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.fullArea)
                .disabled(isUploading)
                .contentShape(Rectangle())
            }

            if isLoading {
                ProgressView()
                    .tint(KXColor.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else if files.isEmpty {
                Text(guideOSText(language, "可上传 PDF、截图、合同、缴费凭证、履历书或 ES 草稿。", "PDF、スクショ、契約書、支払い控え、履歴書などを添付できます。", "Attach PDFs, screenshots, receipts, resumes, or drafts."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.softBackground))
            } else {
                VStack(spacing: 8) {
                    ForEach(files, id: \.id) { file in
                        HStack(spacing: 10) {
                            Image(systemName: fileIcon(file))
                                .font(.body.weight(.bold))
                                .foregroundStyle(KXColor.accent)
                                .frame(width: 28)
                            Button {
                                Task { await open(file) }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(displayName(file))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(formatBytes(file.fileSize ?? 0)) · \(file.contentType ?? file.fileType ?? "file")")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.fullArea)
                            .contentShape(Rectangle())
                            Button(role: .destructive) {
                                deleteTarget = file
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.fullArea)
                            .contentShape(Rectangle())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.cardBackground))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KXColor.separator.opacity(0.45), lineWidth: 1))
                    }
                }
            }

            if let message {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.contains("失败") || message.lowercased().contains("fail") ? Color.red : KXColor.accent)
            }
        }
        .task(id: entityId) {
            await reload()
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await upload(urls) }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert(guideOSText(language, "删除附件？", "添付を削除しますか？", "Delete attachment?"), isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button(guideOSText(language, "删除", "削除", "Delete"), role: .destructive) {
                if let target = deleteTarget {
                    Task { await delete(target) }
                }
            }
            Button(guideOSText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text(guideOSText(language, "删除后无法恢复。", "削除後は元に戻せません。", "This cannot be undone."))
        }
    }

    private func reload() async {
        guard !entityId.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            files = try await KaiXAPIClient.shared.guideAttachments(entityType: entityType, entityId: entityId).items
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func upload(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            for url in urls.prefix(10) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
                _ = try await KaiXAPIClient.shared.uploadFile(
                    fileURL: url,
                    mime: mimeType(for: url),
                    fileName: url.lastPathComponent,
                    purpose: "guide_attachment",
                    entityType: entityType,
                    entityId: entityId,
                    metadata: ["fileName": url.lastPathComponent]
                )
            }
            message = guideOSText(language, "附件已上传", "添付をアップロードしました", "Attachment uploaded")
            await reload()
        } catch {
            message = guideOSText(language, "上传失败：", "アップロード失敗：", "Upload failed: ") + error.localizedDescription
        }
    }

    private func open(_ file: KaiXUploadedFileDTO) async {
        do {
            let raw: String
            if file.isPrivate == true {
                raw = try await KaiXAPIClient.shared.uploadPrivateViewURL(fileId: file.id).resolvedURL
            } else {
                raw = file.cdnUrl ?? file.url ?? ""
            }
            guard let url = URL(string: raw, relativeTo: KaiXBackend.baseURL)?.absoluteURL else {
                message = guideOSText(language, "文件暂时不可查看", "ファイルを表示できません", "File is not available")
                return
            }
            await MainActor.run {
                UIApplication.shared.open(url)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete(_ file: KaiXUploadedFileDTO) async {
        do {
            try await KaiXAPIClient.shared.deleteUploadedFile(file.id)
            deleteTarget = nil
            message = guideOSText(language, "附件已删除", "添付を削除しました", "Attachment deleted")
            await reload()
        } catch {
            message = error.localizedDescription
        }
    }

    private func displayName(_ file: KaiXUploadedFileDTO) -> String {
        if let name = file.fileName, !name.isEmpty { return name }
        if let name = file.originalFileName, !name.isEmpty { return name }
        if let key = file.objectKey, let last = key.split(separator: "/").last { return String(last) }
        return guideOSText(language, "附件", "添付", "Attachment")
    }

    private func fileIcon(_ file: KaiXUploadedFileDTO) -> String {
        let mime = (file.contentType ?? "").lowercased()
        if mime.hasPrefix("image/") { return "photo" }
        if mime == "application/pdf" { return "doc.richtext" }
        return "doc"
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default:
            if let type = UTType(filenameExtension: ext) {
                if type.conforms(to: .pdf) { return "application/pdf" }
                if type.conforms(to: .image) { return "image/jpeg" }
            }
        }
        return "application/pdf"
    }

    private func formatBytes(_ value: Int) -> String {
        if value < 1_048_576 { return "\(max(1, value / 1024)) KB" }
        return String(format: "%.1f MB", Double(value) / 1_048_576)
    }
}
