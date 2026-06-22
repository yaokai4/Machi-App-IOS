import Foundation
import Combine
import SwiftUI

private func guideOSText(_ language: AppLanguage, _ zh: String, _ ja: String, _ en: String) -> String {
    KXListingCopy.pickText(language, zh, ja, en)
}

private func currentGuideOSLanguage() -> String {
    let appLanguage = AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? "")
    switch appLanguage {
    case .ja:
        return "ja"
    case .en:
        return "en"
    case .zh, .system:
        return "zh-CN"
    }
}

private enum GuideOSDate {
    static func iso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func today(offset days: Int = 0) -> String {
        iso(Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }

    static func short(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return String(raw.prefix(10)).replacingOccurrences(of: "-", with: ".")
    }
}

@MainActor
final class GuideOSViewModel: ObservableObject {
    @Published var dashboard: KaiXGuideActivePlanResponse?
    @Published var todos: [KaiXGuideTodoDTO] = []
    @Published var calendarItems: [KaiXGuideCalendarItemDTO] = []
    @Published var applications: [KaiXGuideApplicationDTO] = []
    @Published var lifeItems: [KaiXGuideLifeItemDTO] = []
    @Published var profile: KaiXGuideProfileDTO?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var message: String?

    var isLoggedIn: Bool { KaiXBackend.token != nil }

    func requireLogin(_ reason: String = "登录后可以同步 Guide 计划、Todo、日历提醒和服务记录。") -> Bool {
        guard isLoggedIn else {
            GuestGate.shared.requireLogin(reason)
            return false
        }
        return true
    }

    func loadDashboard() async {
        guard isLoggedIn else { dashboard = nil; return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            dashboard = try await KaiXAPIClient.shared.guideActivePlan(language: currentGuideOSLanguage())
        } catch {
            message = "Guide 计划暂时无法同步，请稍后下拉刷新。"
        }
    }

    func loadTodos(type: String? = nil, status: String = "open", limit: Int = 100) async {
        guard isLoggedIn else { todos = []; return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            todos = try await KaiXAPIClient.shared.guideTodos(status: status, type: type, limit: limit).items
        } catch {
            message = "任务列表加载失败，请稍后再试。"
        }
    }

    func loadCalendar(days: Int = 60) async {
        guard isLoggedIn else { calendarItems = []; return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            calendarItems = try await KaiXAPIClient.shared.guideCalendar(from: GuideOSDate.today(), to: GuideOSDate.today(offset: days)).items
        } catch {
            message = "日历暂时无法同步，请稍后再试。"
        }
    }

    func loadProfile() async {
        guard isLoggedIn else { profile = nil; return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            profile = try await KaiXAPIClient.shared.guideProfile().profile
        } catch {
            message = "身份信息加载失败，请稍后再试。"
        }
    }

    func saveProfile(_ payload: KaiXGuideProfileUpdatePayload) async {
        guard requireLogin() else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await KaiXAPIClient.shared.updateGuideProfile(payload).profile
            message = "身份路径已更新。"
        } catch {
            message = "保存失败，请检查网络后重试。"
        }
    }

    func complete(_ todo: KaiXGuideTodoDTO) async {
        guard requireLogin() else { return }
        do {
            _ = try await KaiXAPIClient.shared.completeGuideTodo(id: todo.id)
            todos.removeAll { $0.id == todo.id }
            await loadDashboard()
        } catch {
            message = "任务完成状态没有保存成功。"
        }
    }

    func loadApplications() async {
        guard isLoggedIn else { applications = []; return }
        do {
            applications = try await KaiXAPIClient.shared.guideApplications().items
        } catch {
            // A list failure shouldn't blank the whole planner; keep prior state.
        }
    }

    func createApplication(_ payload: KaiXGuideApplicationPayload) async -> Bool {
        guard requireLogin("登录后可以保存出愿、ES、面试和结果日期。") else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.createGuideApplication(payload)
            message = "已加入申请/面试计划。"
            await loadApplications()
            await loadTodos(status: "open")
            return true
        } catch {
            message = "添加失败，请确认名称和日期。"
            return false
        }
    }

    func deleteApplication(_ app: KaiXGuideApplicationDTO) async {
        guard requireLogin() else { return }
        do {
            try await KaiXAPIClient.shared.deleteGuideApplication(id: app.id)
            applications.removeAll { $0.id == app.id }
            message = "已删除该申请及其待办。"
            await loadTodos(status: "open")
        } catch {
            message = "删除失败，请稍后重试。"
        }
    }

    func loadLifeItems() async {
        guard isLoggedIn else { lifeItems = []; return }
        do {
            lifeItems = try await KaiXAPIClient.shared.guideLifeItems().items
        } catch {
            // Keep prior state on a transient list failure.
        }
    }

    func createLifeItem(_ payload: KaiXGuideLifeItemPayload) async -> Bool {
        guard requireLogin("登录后可以保存房租、水电、网络、手机费等生活截止日。") else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.createGuideLifeItem(payload)
            message = "已加入生活缴费提醒。"
            await loadLifeItems()
            await loadTodos(type: "life_payment")
            return true
        } catch {
            message = "添加失败，请确认标题和截止日。"
            return false
        }
    }

    func deleteLifeItem(_ item: KaiXGuideLifeItemDTO) async {
        guard requireLogin() else { return }
        do {
            try await KaiXAPIClient.shared.deleteGuideLifeItem(id: item.id)
            lifeItems.removeAll { $0.id == item.id }
            message = "已删除该生活事项及其待办。"
            await loadTodos(type: "life_payment")
        } catch {
            message = "删除失败，请稍后重试。"
        }
    }
}

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

            GuideOSRecommendationStrip(
                products: data?.recommendedProducts ?? [],
                services: data?.recommendedServices ?? [],
                onOpenProduct: onOpenProduct,
                onOpenServices: onOpenServices
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                GuideOSActionTile(title: guideOSText(language, "我的计划", "マイ計画", "My plan"), icon: "list.bullet.clipboard.fill", tint: KXColor.accent, action: onOpenPlan)
                GuideOSActionTile(title: guideOSText(language, "日历", "カレンダー", "Calendar"), icon: "calendar", tint: .indigo, action: onOpenCalendar)
                GuideOSActionTile(title: guideOSText(language, "身份路径", "属性ルート", "Profile"), icon: "person.crop.circle.badge.checkmark", tint: .teal, action: onOpenProfile)
                GuideOSActionTile(title: guideOSText(language, "生活缴费", "生活支払い", "Life bills"), icon: "yensign.circle.fill", tint: .orange, action: onOpenLife)
                GuideOSActionTile(title: guideOSText(language, "出愿 / ES", "出願 / ES", "Applications"), icon: "doc.text.magnifyingglass", tint: .pink, action: onOpenApplications)
                GuideOSActionTile(title: guideOSText(language, "资料服务", "資料・サービス", "Services"), icon: "bag.fill", tint: .purple, action: onOpenServices)
            }
        }
        .padding(15)
        .kxGlassSurface(radius: 24, elevated: true)
    }
}

struct GuidePlanView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = GuideOSViewModel()

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
                        ForEach(model.todos) { todo in
                            GuideOSTodoCard(todo: todo) { Task { await model.complete(todo) } }
                        }
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

struct GuideCalendarView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideOSViewModel()

    private var grouped: [(String, [KaiXGuideCalendarItemDTO])] {
        Dictionary(grouping: model.calendarItems) { $0.date ?? "" }
            .filter { !$0.key.isEmpty }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(title: guideOSText(language, "Guide 日历", "Guide カレンダー", "Guide calendar"), subtitle: guideOSText(language, "出愿、ES、面试、JLPT、签证、房租水电都按日期聚合", "出願・ES・面接・JLPT・ビザ・家賃公共料金を日付で整理", "Applications, interviews, exams, visa, and bills by date"))
                    if grouped.isEmpty && !model.isLoading {
                        GuideOSEmptyPanel(title: guideOSText(language, "暂无未来截止日", "今後の期限はありません", "No upcoming deadlines"), subtitle: guideOSText(language, "添加申请或生活缴费后，这里会变成你的日本时间线。", "申請や生活支払いを追加すると、日本生活のタイムラインになります。", "Add applications or life bills to build your timeline."))
                    } else {
                        ForEach(grouped, id: \.0) { date, items in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(GuideOSDate.short(date))
                                    .font(.headline.weight(.bold))
                                ForEach(items) { item in
                                    if let todo = item.todo {
                                        GuideOSTodoCard(todo: todo) { Task { await model.complete(todo) } }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "日历", "カレンダー", "Calendar"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !model.requireLogin() { return }
            await model.loadCalendar()
        }
        .refreshable { await model.loadCalendar() }
    }
}

struct GuideProfileSetupView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideOSViewModel()
    @State private var identityType = "student"
    @State private var city = "tokyo"
    @State private var isInJapan = true
    @State private var visaStatus = ""
    @State private var japaneseLevel = "N3"
    @State private var targetJapaneseLevel = "N2"
    @State private var targetEntryTerm = ""
    @State private var targetIndustry = ""
    @State private var targetSchoolType = ""
    @State private var weeklyMinutes = 360
    @State private var needsMaterials = true
    @State private var needsServices = false

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(title: guideOSText(language, "身份路径", "属性ルート", "Profile route"), subtitle: guideOSText(language, "不同身份看到不同目标：大学生、语言学校、社会人、转职、升学、日语计划都分开", "属性ごとに目標を分けます", "Personalize goals by identity"))
                    VStack(spacing: 12) {
                        Picker(guideOSText(language, "身份", "属性", "Identity"), selection: $identityType) {
                            Text("大学生").tag("student")
                            Text("语言学校").tag("language_school_student")
                            Text("社会人").tag("worker")
                            Text("转职").tag("career_change")
                            Text("升学").tag("applicant")
                        }
                        .pickerStyle(.segmented)
                        GuideOSTextField(title: "城市", text: $city)
                        Toggle("目前在日本", isOn: $isInJapan)
                        GuideOSTextField(title: "签证 / 在留状态", text: $visaStatus)
                        HStack {
                            GuideOSTextField(title: "当前日语", text: $japaneseLevel)
                            GuideOSTextField(title: "目标日语", text: $targetJapaneseLevel)
                        }
                        GuideOSTextField(title: "目标入学期 / 入社期", text: $targetEntryTerm)
                        GuideOSTextField(title: "目标行业", text: $targetIndustry)
                        GuideOSTextField(title: "目标学校类型", text: $targetSchoolType)
                        Stepper("每周可投入 \(weeklyMinutes) 分钟", value: $weeklyMinutes, in: 60...2400, step: 60)
                        Toggle("需要资料包", isOn: $needsMaterials)
                        Toggle("需要咨询/代办服务", isOn: $needsServices)
                        Button {
                            Task {
                                await model.saveProfile(.init(
                                    identityType: identityType,
                                    city: city,
                                    isInJapan: isInJapan,
                                    visaStatus: visaStatus,
                                    japaneseLevel: japaneseLevel,
                                    targetJapaneseLevel: targetJapaneseLevel,
                                    targetEntryTerm: targetEntryTerm,
                                    targetIndustry: targetIndustry,
                                    targetSchoolType: targetSchoolType,
                                    weeklyAvailableMinutes: weeklyMinutes,
                                    needsMaterials: needsMaterials,
                                    needsServices: needsServices
                                ))
                            }
                        } label: {
                            Text(model.isSaving ? "保存中" : "保存身份路径")
                                .font(.headline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .padding(15)
                    .kxGlassSurface(radius: 22)
                    if let message = model.message { GuideOSNotice(message: message) }
                }
                .padding(KXSpacing.screen)
                .guideBottomInset()
                .kxReadableWidth()
            }
        }
        .navigationTitle(guideOSText(language, "身份", "属性", "Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !model.requireLogin() { return }
            await model.loadProfile()
            if let profile = model.profile {
                identityType = profile.identityType.isEmpty ? identityType : profile.identityType
                city = profile.city.isEmpty ? city : profile.city
                isInJapan = profile.isInJapan
                visaStatus = profile.visaStatus
                japaneseLevel = profile.japaneseLevel.isEmpty ? japaneseLevel : profile.japaneseLevel
                targetJapaneseLevel = profile.targetJapaneseLevel.isEmpty ? targetJapaneseLevel : profile.targetJapaneseLevel
                targetEntryTerm = profile.targetEntryTerm
                targetIndustry = profile.targetIndustry
                targetSchoolType = profile.targetSchoolType
                weeklyMinutes = max(60, profile.weeklyAvailableMinutes)
                needsMaterials = profile.needsMaterials
                needsServices = profile.needsServices
            }
        }
    }
}

struct GuideLifePlannerView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideOSViewModel()
    @State private var type = "rent"
    @State private var title = "房租"
    @State private var provider = ""
    @State private var amount = ""
    @State private var dueDate = Date()
    @State private var reminderDays = 3

    var body: some View {
        GuidePlannerFormShell(
            title: guideOSText(language, "生活缴费与手续", "生活支払い・手続き", "Life bills"),
            subtitle: guideOSText(language, "房租、水电、网络、手机费、保险、年金、签证、租约截止日统一进日历", "家賃・公共料金・通信・保険・年金・ビザ・契約期限をまとめます", "Rent, utilities, phone, visa, insurance, and contract deadlines"),
            model: model
        ) {
            Picker("类型", selection: $type) {
                Text("房租").tag("rent")
                Text("电费").tag("electric")
                Text("燃气").tag("gas")
                Text("水费").tag("water")
                Text("网络").tag("internet")
                Text("手机").tag("phone")
                Text("保险").tag("insurance")
                Text("签证").tag("visa")
            }
            .pickerStyle(.menu)
            GuideOSTextField(title: "标题", text: $title)
            GuideOSTextField(title: "公司 / 房东 / 机构", text: $provider)
            GuideOSTextField(title: "金额（JPY）", text: $amount)
                .keyboardType(.numberPad)
            DatePicker("截止日期", selection: $dueDate, displayedComponents: .date)
            Stepper("提前 \(reminderDays) 天提醒", value: $reminderDays, in: 0...30)
            GuideOSPrimaryButton(title: model.isSaving ? "添加中" : "添加生活截止日") {
                Task {
                    let ok = await model.createLifeItem(.init(
                        type: type,
                        title: title,
                        provider: provider,
                        amount: Int(amount),
                        currency: "JPY",
                        dueAt: GuideOSDate.iso(dueDate),
                        recurrence: "monthly",
                        reminderDaysBefore: reminderDays
                    ))
                    if ok {
                        provider = ""
                        amount = ""
                    }
                }
            }
        } savedSection: {
            if !model.lifeItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(guideOSText(language, "我的生活事项", "マイ生活項目", "My life items"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    ForEach(model.lifeItems) { item in
                        GuideOSLifeItemRow(item: item) { Task { await model.deleteLifeItem(item) } }
                    }
                }
            }
        }
        .task {
            if !model.requireLogin() { return }
            await model.loadLifeItems()
            await model.loadTodos(type: "life_payment")
        }
    }
}

struct GuideApplicationPlannerView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideOSViewModel()
    @State private var type = "school"
    @State private var name = ""
    @State private var department = ""
    @State private var position = ""
    @State private var deadline = Date()
    @State private var interview = Date()
    @State private var hasInterview = false
    @State private var notes = ""

    var body: some View {
        GuidePlannerFormShell(
            title: guideOSText(language, "出愿 / ES / 面试计划", "出願 / ES / 面接計画", "Applications"),
            subtitle: guideOSText(language, "大学出愿、公司 ES、面试、结果确认全部生成 Todo 和日历项", "大学出願・会社ES・面接・結果確認をTodoとカレンダーにします", "Turn applications, ES deadlines, interviews, and results into todos"),
            model: model
        ) {
            Picker("类型", selection: $type) {
                Text("大学 / 大学院").tag("school")
                Text("公司 / 转职").tag("company")
            }
            .pickerStyle(.segmented)
            GuideOSLibraryPickerField(type: type, text: $name)
            GuideOSTextField(title: type == "school" ? "研究科 / 学部" : "部门 / 岗位方向", text: $department)
            GuideOSTextField(title: "职位 / 教授 / 备注对象", text: $position)
            DatePicker(type == "school" ? "出愿截止" : "ES 截止", selection: $deadline, displayedComponents: .date)
            Toggle("已有面试时间", isOn: $hasInterview)
            if hasInterview {
                DatePicker("面试日期", selection: $interview, displayedComponents: .date)
            }
            GuideOSTextField(title: "备注", text: $notes)
            GuideOSPrimaryButton(title: model.isSaving ? "添加中" : "添加申请计划") {
                Task {
                    let ok = await model.createApplication(.init(
                        type: type,
                        name: name,
                        department: department,
                        position: position,
                        deadline: GuideOSDate.iso(deadline),
                        interviewAt: hasInterview ? GuideOSDate.iso(interview) : nil,
                        notes: notes
                    ))
                    if ok {
                        name = ""
                        department = ""
                        position = ""
                        notes = ""
                    }
                }
            }
        } savedSection: {
            if !model.applications.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(guideOSText(language, "我的申请", "マイ申請", "My applications"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    ForEach(model.applications) { app in
                        GuideOSApplicationRow(app: app) { Task { await model.deleteApplication(app) } }
                    }
                }
            }
        }
        .task {
            if !model.requireLogin() { return }
            await model.loadApplications()
            await model.loadTodos(status: "open")
        }
    }
}

private struct GuidePlannerFormShell<Fields: View, Saved: View>: View {
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

private struct GuideOSHeaderRow: View {
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

private struct GuideOSPlanCard: View {
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
                .foregroundStyle(.white)
                .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(action: isGuest ? { GuestGate.shared.requireLogin("登录后可以设置身份路径。") } : onOpenProfile) {
                    Text(guideOSText(language, "身份设置", "属性設定", "Profile"))
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
                .foregroundStyle(KXColor.accent)
                .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(15)
        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct GuideOSTodoStrip: View {
    let title: String
    let todos: [KaiXGuideTodoDTO]
    let onComplete: (KaiXGuideTodoDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
            ForEach(todos.prefix(4)) { todo in
                GuideOSTodoCard(todo: todo) { onComplete(todo) }
            }
        }
    }
}

private struct GuideOSRecommendationStrip: View {
    @Environment(\.appLanguage) private var language

    let products: [KaiXGuideProductDTO]
    let services: [KaiXGuideProductDTO]
    let onOpenProduct: (String) -> Void
    let onOpenServices: () -> Void

    private var items: [KaiXGuideProductDTO] {
        Array((products + services).prefix(5))
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guideOSText(language, "完成任务的工具", "タスク用ツール", "Tools for tasks"))
                            .font(.subheadline.weight(.bold))
                        Text(guideOSText(language, "按你的 Todo 自动推荐资料和服务", "Todoに合わせて資料とサービスを推薦", "Recommended from your todos"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(action: onOpenServices) {
                        Text(guideOSText(language, "全部", "すべて", "All"))
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KXColor.accent)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            Button {
                                onOpenProduct(item.slug)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 7) {
                                        Image(systemName: item.isService ? "sparkles" : "doc.text.fill")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 28, height: 28)
                                            .background(item.isService ? Color.purple : KXColor.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                        Text(item.isService ? guideOSText(language, "服务", "サービス", "Service") : guideOSText(language, "资料", "資料", "Material"))
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                    }
                                    Text(item.title)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(item.subtitle.isEmpty ? (item.ctaLabel ?? item.priceLabel) : item.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(width: 176, alignment: .leading)
                                .padding(12)
                                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
    }
}

private struct GuideOSTodoCard: View {
    let todo: KaiXGuideTodoDTO
    let onComplete: () -> Void

    private var tint: Color {
        switch todo.priority {
        case "high": return .orange
        case "low": return .secondary
        default: return KXColor.accent
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onComplete) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(todo.isDone ? KXColor.accent : tint.opacity(0.65))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(todo.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let date = todo.displayDate, !date.isEmpty {
                        Text(GuideOSDate.short(date))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.12), in: Capsule())
                    }
                }
                if !todo.summary.isEmpty {
                    Text(todo.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    GuideOSMiniBadge(text: todo.todoType.replacingOccurrences(of: "_", with: " "))
                    if todo.estimatedMinutes > 0 { GuideOSMiniBadge(text: "\(todo.estimatedMinutes) 分") }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.8)
        )
    }
}

private struct GuideOSActionTile: View {
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
    }
}

private struct GuideOSQuickRow: View {
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
                .foregroundStyle(KXColor.accent)
                .background(KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }
}

private struct GuideOSTextField: View {
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

private struct GuideOSDeleteCardChip: View {
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

/// A saved application row with its key dates + a delete button. Deleting the
/// application also clears its generated reverse-countdown todos + reminders
/// server-side. A confirmation dialog guards against accidental loss.
private struct GuideOSApplicationRow: View {
    let app: KaiXGuideApplicationDTO
    let onDelete: () -> Void
    @State private var confirming = false

    private var isSchool: Bool { app.type == "school" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSchool ? "graduationcap.fill" : "briefcase.fill")
                .font(.subheadline)
                .foregroundStyle(KXColor.accent)
                .frame(width: 30, height: 30)
                .background(KXColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
                let sub = isSchool ? app.department : app.position
                if !sub.isEmpty {
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let d = app.deadline, !d.isEmpty { GuideOSDeleteCardChip(text: (isSchool ? "出愿 " : "ES ") + GuideOSDate.short(d)) }
                    if let i = app.interviewAt, !i.isEmpty { GuideOSDeleteCardChip(text: "面试 " + GuideOSDate.short(i)) }
                    if let r = app.resultAt, !r.isEmpty { GuideOSDeleteCardChip(text: "结果 " + GuideOSDate.short(r)) }
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { confirming = true } label: {
                Image(systemName: "trash").font(.subheadline).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .kxGlassSurface(radius: 16)
        .confirmationDialog("删除该申请？", isPresented: $confirming, titleVisibility: .visible) {
            Button("删除（含倒排待办）", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        }
    }
}

/// A saved life item row with amount + due day and a delete button. Deleting
/// also removes its generated payment todos + reminders server-side.
private struct GuideOSLifeItemRow: View {
    let item: KaiXGuideLifeItemDTO
    let onDelete: () -> Void
    @State private var confirming = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "yensign.circle.fill")
                .font(.subheadline)
                .foregroundStyle(KXColor.accent)
                .frame(width: 30, height: 30)
                .background(KXColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
                if !item.provider.isEmpty {
                    Text(item.provider).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if item.amount > 0 { GuideOSDeleteCardChip(text: "\(item.currency.isEmpty ? "JPY" : item.currency) \(item.amount)") }
                    if item.dueDay > 0 {
                        GuideOSDeleteCardChip(text: "每月 \(item.dueDay) 号")
                    } else if let d = item.dueAt, !d.isEmpty {
                        GuideOSDeleteCardChip(text: GuideOSDate.short(d))
                    }
                    if !item.paymentMethod.isEmpty { GuideOSDeleteCardChip(text: item.paymentMethod) }
                }
            }
            Spacer(minLength: 0)
            Button(role: .destructive) { confirming = true } label: {
                Image(systemName: "trash").font(.subheadline).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .kxGlassSurface(radius: 16)
        .confirmationDialog("删除该生活事项？", isPresented: $confirming, titleVisibility: .visible) {
            Button("删除（含待办）", role: .destructive, action: onDelete)
            Button("取消", role: .cancel) {}
        }
    }
}

private struct GuideOSLibrarySuggestion: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
}

/// Name field that supports BOTH free typing AND picking from the server school
/// / company library — mirrors the Web `LibraryPickerField`. Type ≥2 chars and
/// matches from the库 surface as tappable suggestions; "库里没有？直接输入即可"
/// keeps manual entry first-class. Pure presentation over the existing
/// `guideSearch` endpoint — no local DB, server-first.
private struct GuideOSLibraryPickerField: View {
    @Environment(\.appLanguage) private var language
    let type: String      // "school" | "company"
    @Binding var text: String

    @State private var suggestions: [GuideOSLibrarySuggestion] = []
    @State private var isSearching = false
    @State private var justPicked = false

    private var label: String {
        type == "school"
            ? guideOSText(language, "学校 / 研究科名称", "学校・研究科名", "School / graduate program")
            : guideOSText(language, "公司名称", "会社名", "Company name")
    }
    private var placeholder: String {
        type == "school"
            ? guideOSText(language, "输入或从学校库选择，如 东京大学大学院", "学校ライブラリから選択・入力（例：東京大学大学院）", "Type or pick from the school library")
            : guideOSText(language, "输入或从公司库选择，如 Mercari", "会社ライブラリから選択・入力（例：Mercari）", "Type or pick from the company library")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                if isSearching {
                    ProgressView().controlSize(.mini)
                } else if !text.isEmpty {
                    Button {
                        text = ""
                        suggestions = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button {
                            justPicked = true
                            text = suggestion.name
                            suggestions = []
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: type == "school" ? "graduationcap.fill" : "building.2.fill")
                                    .font(.caption)
                                    .foregroundStyle(KXColor.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(suggestion.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < suggestions.count - 1 {
                            Divider().padding(.leading, 32)
                        }
                    }
                    Text(guideOSText(language, "库里没有？直接输入名称即可", "ライブラリに無ければそのまま入力でOK", "Not in the library? Just type the name"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(KXColor.accent.opacity(0.18), lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: suggestions)
        .task(id: "\(type)|\(text)") { await runSearch() }
    }

    private func runSearch() async {
        // A tap just filled the field — swallow exactly one re-trigger so the
        // dropdown doesn't immediately reopen on the chosen name.
        if justPicked { justPicked = false; return }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { suggestions = []; isSearching = false; return }
        // Debounce keystrokes; .task(id:) cancels the previous run for us.
        try? await Task.sleep(nanoseconds: 280_000_000)
        if Task.isCancelled { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let scope = type == "school" ? "schools" : "companies"
            let resp = try await KaiXAPIClient.shared.guideSearch(language: currentGuideOSLanguage(), keyword: query, scope: scope)
            if Task.isCancelled { return }
            if type == "school" {
                suggestions = (resp.groups.schools ?? []).prefix(6).map {
                    GuideOSLibrarySuggestion(id: $0.id, name: $0.schoolName, subtitle: $0.prefecture)
                }
            } else {
                suggestions = (resp.groups.companies ?? []).prefix(6).map {
                    GuideOSLibrarySuggestion(id: $0.id, name: $0.companyName, subtitle: $0.industry)
                }
            }
        } catch {
            suggestions = []
        }
    }
}

private struct GuideOSPrimaryButton: View {
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
        .foregroundStyle(.white)
        .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct GuideOSNotice: View {
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

private struct GuideOSMiniBadge: View {
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

private struct GuideOSEmptyMini: View {
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

private struct GuideOSEmptyPanel: View {
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
