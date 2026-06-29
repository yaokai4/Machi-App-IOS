import SwiftUI

private enum GuideCalendarMode: String, CaseIterable, Identifiable {
    case month
    case week
    case agenda

    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .month: return guideOSText(language, "月", "月", "Month")
        case .week: return guideOSText(language, "周", "週", "Week")
        case .agenda: return guideOSText(language, "日程", "予定", "Agenda")
        }
    }
}

private enum GuideCalendarScope: String, CaseIterable, Identifiable {
    case all
    case next7
    case next30
    case overdue

    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .all: return guideOSText(language, "全部", "すべて", "All")
        case .next7: return guideOSText(language, "未来 7 天", "今後7日間", "Next 7 days")
        case .next30: return guideOSText(language, "未来 30 天", "今後30日間", "Next 30 days")
        case .overdue: return guideOSText(language, "逾期", "期限切れ", "Overdue")
        }
    }
}

struct GuideCalendarView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideCalendarViewModel()
    @State private var selectedDate = GuideOSDate.today()
    @State private var mode: GuideCalendarMode = .month
    @State private var scope: GuideCalendarScope = .all
    // Auto-generated journey steps (套用「目标/路径」模板时批量生成) used to flood
    // the calendar with items the user never typed — the "数据很脏" complaint.
    // They are hidden by default; the toggle below brings them back when wanted.
    @State private var showJourneySteps = false

    /// A todo created from a journey template (todoType == "guide_step"), as
    /// opposed to something the user added themselves.
    private func isJourneyStep(_ item: KaiXGuideCalendarItemDTO) -> Bool {
        item.todo?.todoType == "guide_step"
    }

    private var hasJourneySteps: Bool {
        model.calendarItems.contains { isJourneyStep($0) }
    }

    private var scopedItems: [KaiXGuideCalendarItemDTO] {
        let today = GuideOSDate.today()
        let end7 = GuideOSDate.today(offset: 7)
        let end30 = GuideOSDate.today(offset: 30)
        return model.calendarItems.filter { item in
            if !showJourneySteps, isJourneyStep(item) { return false }
            let date = String((item.date ?? "").prefix(10))
            guard !date.isEmpty else { return scope == .all }
            switch scope {
            case .all: return true
            case .next7: return date >= today && date <= end7
            case .next30: return date >= today && date <= end30
            case .overdue: return date < today && item.status != "done"
            }
        }
    }

    private var grouped: [(String, [KaiXGuideCalendarItemDTO])] {
        Dictionary(grouping: scopedItems) { $0.date ?? "" }
            .filter { !$0.key.isEmpty }
            .sorted { $0.key < $1.key }
    }

    private var countdowns: [(date: String, title: String, days: Int)] {
        grouped.compactMap { date, items in
            guard let days = GuideCalendarCountdown.daysUntil(date), days >= 0 else { return nil }
            return (date, items.first?.title ?? guideOSText(language, "\(items.count) 项任务", "\(items.count)件のタスク", "\(items.count) tasks"), days)
        }
        .sorted { $0.days < $1.days }
        .prefix(5)
        .map { $0 }
    }

    private var groupedMap: [String: [KaiXGuideCalendarItemDTO]] {
        Dictionary(grouping: scopedItems) { String(($0.date ?? "").prefix(10)) }
    }

    private var selectedItems: [KaiXGuideCalendarItemDTO] {
        groupedMap[selectedDate] ?? []
    }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(title: guideOSText(language, "Guide 日历", "Guide カレンダー", "Guide calendar"), subtitle: guideOSText(language, "出愿、ES、面试、JLPT、签证、房租水电都按日期聚合", "出願・ES・面接・JLPT・ビザ・家賃公共料金を日付で整理", "Applications, interviews, exams, visa, and bills by date"))
                    Picker("", selection: $mode) {
                        ForEach(GuideCalendarMode.allCases) { item in
                            Text(item.title(language)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(GuideCalendarScope.allCases) { item in
                                Button {
                                    scope = item
                                } label: {
                                    Text(item.title(language))
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 13)
                                        .frame(minHeight: 44)
                                }
                                .buttonStyle(.fullArea)
                                .contentShape(Rectangle())
                                .foregroundStyle(scope == item ? Color.white : Color.secondary)
                                .background(scope == item ? KXColor.accent : KXColor.livingSurface.opacity(0.78), in: Capsule())
                                .accessibilityAddTraits(scope == item ? .isSelected : [])
                            }
                        }
                    }
                    if hasJourneySteps {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showJourneySteps.toggle() }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: showJourneySteps ? "eye.fill" : "eye.slash")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(KXColor.accent)
                                Text(showJourneySteps
                                     ? guideOSText(language, "正在显示路径自动生成的步骤", "パスの自動ステップを表示中", "Showing journey steps")
                                     : guideOSText(language, "已隐藏路径自动生成的步骤", "パスの自動ステップは非表示", "Journey steps hidden"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Text(showJourneySteps ? guideOSText(language, "隐藏", "非表示", "Hide") : guideOSText(language, "显示", "表示", "Show"))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(KXColor.accent)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .padding(.horizontal, 12)
                            .background(KXColor.livingSurface.opacity(0.68), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.fullArea)
                    }
                    GuideCalendarEventComposer(model: model, defaultDate: selectedDate)
                    if let message = model.message, !message.isEmpty {
                        Text(message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(message.contains("失败") ? Color.orange : KXColor.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(KXColor.livingSurface.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    switch mode {
                    case .month:
                        GuideCalendarMonthGrid(
                            grouped: groupedMap,
                            selectedDate: $selectedDate,
                            onMove: { id, date in Task { await model.moveCalendarItem(id: id, to: date) } }
                        )
                        GuideQuickTodoComposer(defaultDate: selectedDate, isSaving: model.isSaving) { content, plannedDate in
                            await model.createQuickTodo(content: content, plannedDate: plannedDate ?? selectedDate)
                        }
                        GuideCalendarSelectedDay(date: selectedDate, items: selectedItems, model: model)
                        GuideCalendarCountdownStrip(items: countdowns)
                    case .week:
                        GuideCalendarWeekBoard(
                            grouped: groupedMap,
                            selectedDate: $selectedDate,
                            onMove: { id, date in Task { await model.moveCalendarItem(id: id, to: date) } }
                        )
                        GuideQuickTodoComposer(defaultDate: selectedDate, isSaving: model.isSaving) { content, plannedDate in
                            await model.createQuickTodo(content: content, plannedDate: plannedDate ?? selectedDate)
                        }
                        GuideCalendarSelectedDay(date: selectedDate, items: selectedItems, model: model)
                    case .agenda:
                        GuideQuickTodoComposer(defaultDate: selectedDate, isSaving: model.isSaving) { content, plannedDate in
                            await model.createQuickTodo(content: content, plannedDate: plannedDate ?? selectedDate)
                        }
                        GuideCalendarAgendaList(grouped: grouped, model: model)
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
            // Don't pop the login sheet just for opening the screen; load only
            // when already signed in. Write actions still prompt via requireLogin().
            guard model.isLoggedIn else { return }
            await model.loadCalendar()
        }
        .refreshable { await model.loadCalendar() }
    }
}

private struct GuideCalendarMonthGrid: View {
    @Environment(\.appLanguage) private var language
    let grouped: [String: [KaiXGuideCalendarItemDTO]]
    @Binding var selectedDate: String
    let onMove: (_ id: String, _ date: String) -> Void
    @State private var cursor = Date()

    private var weekdays: [String] {
        [
            guideOSText(language, "日", "日", "Sun"),
            guideOSText(language, "一", "月", "Mon"),
            guideOSText(language, "二", "火", "Tue"),
            guideOSText(language, "三", "水", "Wed"),
            guideOSText(language, "四", "木", "Thu"),
            guideOSText(language, "五", "金", "Fri"),
            guideOSText(language, "六", "土", "Sat")
        ]
    }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var cells: [Date] {
        let calendar = Calendar.current
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: cursor)) ?? Date()
        let start = calendar.date(byAdding: .day, value: -calendar.component(.weekday, from: first) + 1, to: first) ?? first
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var monthTitle: String {
        let comps = Calendar.current.dateComponents([.year, .month], from: cursor)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        return guideOSText(language, "\(year) 年 \(month) 月", "\(year)年\(month)月", "\(monthName(month)) \(year)")
    }

    private func monthName(_ month: Int) -> String {
        let names = ["", "January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"]
        guard month >= 1, month <= 12 else { return "\(month)" }
        return names[month]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(monthTitle)
                    .font(.headline.weight(.bold))
                Spacer()
                HStack(spacing: 8) {
                    monthButton("chevron.left") {
                        cursor = Calendar.current.date(byAdding: .month, value: -1, to: cursor) ?? cursor
                    }
                    .accessibilityLabel("上个月")
                    Button {
                        cursor = Date()
                        selectedDate = GuideOSDate.today()
                    } label: {
                        Text(guideOSText(language, "今天", "今日", "Today"))
                            .font(.caption.weight(.bold))
                            .frame(minHeight: 44)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .background(KXColor.livingSurface.opacity(0.78), in: Capsule())
                    monthButton("chevron.right") {
                        cursor = Calendar.current.date(byAdding: .month, value: 1, to: cursor) ?? cursor
                    }
                    .accessibilityLabel("下个月")
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(cells, id: \.self) { date in
                    dayCell(date)
                }
            }
        }
        .padding(14)
        .kxGlassSurface(radius: 22, elevated: true)
    }

    private func monthButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
        .background(KXColor.livingSurface.opacity(0.78), in: Circle())
    }

    private func dayCell(_ date: Date) -> some View {
        let iso = GuideOSDate.iso(date)
        let inMonth = Calendar.current.component(.month, from: date) == Calendar.current.component(.month, from: cursor)
        let isSelected = iso == selectedDate
        let isToday = iso == GuideOSDate.today()
        let count = grouped[iso]?.count ?? 0
        return Button {
            selectedDate = iso
        } label: {
            VStack(spacing: 3) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.caption.weight(.bold))
                Circle()
                    .fill(count > 0 ? (isSelected ? Color.white : KXColor.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
        .foregroundStyle(isSelected ? .white : (inMonth ? Color.primary : Color.secondary.opacity(0.45)))
        .background(isSelected ? KXColor.accent : (isToday ? KXColor.accentSoft : KXColor.livingSurface.opacity(0.55)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            selectedDate = iso
            onMove(id, iso)
            return true
        }
    }
}

private struct GuideCalendarWeekBoard: View {
    @Environment(\.appLanguage) private var language
    let grouped: [String: [KaiXGuideCalendarItemDTO]]
    @Binding var selectedDate: String
    let onMove: (_ id: String, _ date: String) -> Void
    @State private var cursor = Date()

    private var weekdays: [String] {
        [
            guideOSText(language, "日", "日", "Sun"),
            guideOSText(language, "一", "月", "Mon"),
            guideOSText(language, "二", "火", "Tue"),
            guideOSText(language, "三", "水", "Wed"),
            guideOSText(language, "四", "木", "Thu"),
            guideOSText(language, "五", "金", "Fri"),
            guideOSText(language, "六", "土", "Sat")
        ]
    }

    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -calendar.component(.weekday, from: cursor) + 1, to: cursor) ?? cursor
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var rangeTitle: String {
        guard let first = days.first, let last = days.last else { return "" }
        let c = Calendar.current
        let m1 = c.component(.month, from: first)
        let d1 = c.component(.day, from: first)
        let m2 = c.component(.month, from: last)
        let d2 = c.component(.day, from: last)
        return guideOSText(language,
                           "\(m1)月\(d1)日 - \(m2)月\(d2)日",
                           "\(m1)月\(d1)日 - \(m2)月\(d2)日",
                           "\(m1)/\(d1) - \(m2)/\(d2)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(rangeTitle)
                    .font(.headline.weight(.bold))
                Spacer()
                HStack(spacing: 8) {
                    weekButton("chevron.left") { shiftWeek(-1) }
                        .accessibilityLabel("上一周")
                    Button {
                        cursor = Date()
                        selectedDate = GuideOSDate.today()
                    } label: {
                        Text(guideOSText(language, "本周", "今週", "This week"))
                            .font(.caption.weight(.bold))
                            .frame(minHeight: 44)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .background(KXColor.livingSurface.opacity(0.78), in: Capsule())
                    weekButton("chevron.right") { shiftWeek(1) }
                        .accessibilityLabel("下一周")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(days, id: \.self) { date in
                        dayColumn(date)
                    }
                }
            }
        }
        .padding(14)
        .kxGlassSurface(radius: 22, elevated: true)
    }

    private func shiftWeek(_ delta: Int) {
        cursor = Calendar.current.date(byAdding: .day, value: delta * 7, to: cursor) ?? cursor
    }

    private func weekButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
        .background(KXColor.livingSurface.opacity(0.78), in: Circle())
    }

    private func dayColumn(_ date: Date) -> some View {
        let iso = GuideOSDate.iso(date)
        let isSelected = iso == selectedDate
        let isToday = iso == GuideOSDate.today()
        let items = grouped[iso] ?? []
        let dayIndex = Calendar.current.component(.weekday, from: date) - 1
        return Button {
            selectedDate = iso
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isToday
                         ? guideOSText(language, "今天", "今日", "Today")
                         : guideOSText(language,
                                       "周\(weekdays[max(0, min(dayIndex, weekdays.count - 1))])",
                                       weekdays[max(0, min(dayIndex, weekdays.count - 1))],
                                       weekdays[max(0, min(dayIndex, weekdays.count - 1))]))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(isSelected ? .white : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(isSelected ? KXColor.accent : (isToday ? KXColor.accentSoft : KXColor.livingSurface.opacity(0.72)), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    if items.isEmpty {
                        Text(guideOSText(language, "空", "なし", "Empty"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(items.prefix(4)) { item in
                            Text(item.todo?.title ?? item.title)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(item.status == "done" ? .secondary : .primary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(item.status == "done" ? KXColor.softBackground : KXColor.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .draggable(item.id)
                        }
                        if items.count > 4 {
                            Text(guideOSText(language, "+\(items.count - 4) 项", "+\(items.count - 4)件", "+\(items.count - 4)"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(KXColor.accent)
                        }
                    }
                }
                .frame(minHeight: 96, alignment: .top)
            }
            .frame(width: 118, alignment: .topLeading)
        }
        .buttonStyle(.fullArea)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            selectedDate = iso
            onMove(id, iso)
            return true
        }
    }
}

private struct GuideCalendarSelectedDay: View {
    @Environment(\.appLanguage) private var language
    let date: String
    let items: [KaiXGuideCalendarItemDTO]
    @ObservedObject var model: GuideCalendarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(GuideOSDate.short(date))
                    .font(.headline.weight(.bold))
                Spacer()
                Text(guideOSText(language, "\(items.count) 项", "\(items.count)件", "\(items.count) items"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            if items.isEmpty {
                GuideOSEmptyMini(text: guideOSText(language, "这一天还没有任务，可以直接在上方添加。", "この日の予定はまだありません。上から追加できます。", "No tasks for this day yet. Add one above."))
            } else {
                ForEach(items) { item in
                    if let todo = item.todo {
                        GuideOSTodoCard(
                            todo: todo,
                            onComplete: { Task { await model.complete(todo) } },
                            onSetReminder: { at in await model.setReminder(todoId: todo.id, reminderAt: at) },
                            onReschedule: { date in Task { await model.reschedule(todo, to: date) } },
                            onUpdateSteps: { steps in Task { await model.updateTodoSteps(todo, steps: steps) } },
                            onUpdateNotes: { notes in Task { await model.updateTodoNotes(todo, notes: notes) } },
                            onUpdate: { payload in await model.updateTodo(todo, payload: payload) },
                            onDuplicate: { await model.duplicateTodo(todo) },
                            onArchive: { await model.archiveTodo(todo) },
                            onDelete: { await model.deleteTodo(todo) }
                        )
                        .draggable(item.id)
                    } else {
                        GuideCalendarEventRow(event: item, model: model)
                            .draggable(item.id)
                    }
                }
            }
        }
    }
}

private struct GuideCalendarAgendaList: View {
    @Environment(\.appLanguage) private var language
    let grouped: [(String, [KaiXGuideCalendarItemDTO])]
    @ObservedObject var model: GuideCalendarViewModel

    var body: some View {
        if grouped.isEmpty {
            GuideOSEmptyPanel(
                title: guideOSText(language, "还没有日程", "予定はまだありません", "No agenda yet"),
                subtitle: guideOSText(language, "添加 Todo、申请、面试或生活缴费后，会自动出现在这里。", "Todo・出願・面接・公共料金などを追加すると、ここに自動で表示されます。", "Add a todo, application, interview, or bill and it will appear here automatically.")
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(grouped, id: \.0) { date, items in
                    agendaSection(date: date, items: items)
                }
            }
        }
    }

    private func agendaSection(date: String, items: [KaiXGuideCalendarItemDTO]) -> some View {
        let day = String(date.prefix(10))
        let overdue = day < GuideOSDate.today()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateLabel(day))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(overdue ? Color.orange : Color.primary)
                Spacer()
                Text(guideOSText(language, "\(items.count) 项", "\(items.count)件", "\(items.count) items"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                if let todo = item.todo {
                    GuideOSTodoCard(
                        todo: todo,
                        onComplete: { Task { await model.complete(todo) } },
                        onSetReminder: { at in await model.setReminder(todoId: todo.id, reminderAt: at) },
                        onReschedule: { date in Task { await model.reschedule(todo, to: date) } },
                        onUpdateSteps: { steps in Task { await model.updateTodoSteps(todo, steps: steps) } },
                        onUpdateNotes: { notes in Task { await model.updateTodoNotes(todo, notes: notes) } },
                        onUpdate: { payload in await model.updateTodo(todo, payload: payload) },
                        onDuplicate: { await model.duplicateTodo(todo) },
                        onArchive: { await model.archiveTodo(todo) },
                        onDelete: { await model.deleteTodo(todo) }
                    )
                    .draggable(item.id)
                } else {
                    GuideCalendarEventRow(event: item, model: model)
                        .draggable(item.id)
                }
            }
        }
    }

    private func dateLabel(_ date: String) -> String {
        if date == GuideOSDate.today() { return guideOSText(language, "今天", "今日", "Today") }
        if date == GuideOSDate.today(offset: 1) { return guideOSText(language, "明天", "明日", "Tomorrow") }
        if date < GuideOSDate.today() { return guideOSText(language, "逾期 · \(GuideOSDate.short(date))", "期限切れ · \(GuideOSDate.short(date))", "Overdue · \(GuideOSDate.short(date))") }
        return GuideOSDate.short(date)
    }
}

private struct GuideCalendarEventComposer: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject var model: GuideCalendarViewModel
    let defaultDate: String
    @State private var isExpanded = false
    @State private var title = ""
    @State private var date = Date()
    @State private var time = Date()
    @State private var allDay = true
    @State private var recurrence = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if !isExpanded {
                    date = GuideOSDate.parse(defaultDate) ?? Date()
                }
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(KXColor.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(guideOSText(language, "新建日程", "予定を作成", "New event"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(guideOSText(language, "会议、预约和个人安排，独立于 Todo", "会議・予約・個人の予定。Todoとは別管理。", "Meetings, appointments, and personal plans, separate from todos"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.fullArea)

            if isExpanded {
                Divider().opacity(0.55)
                TextField(guideOSText(language, "日程标题，例如：大学院线上说明会", "予定のタイトル（例：大学院オンライン説明会）", "Event title, e.g. grad school online info session"), text: $title)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                DatePicker(guideOSText(language, "日期", "日付", "Date"), selection: $date, displayedComponents: .date)
                    .font(.subheadline.weight(.semibold))
                Toggle(guideOSText(language, "全天", "終日", "All-day"), isOn: $allDay)
                    .font(.subheadline.weight(.semibold))
                if !allDay {
                    DatePicker(guideOSText(language, "时间", "時刻", "Time"), selection: $time, displayedComponents: .hourAndMinute)
                        .font(.subheadline.weight(.semibold))
                }
                Picker(guideOSText(language, "重复", "繰り返し", "Repeat"), selection: $recurrence) {
                    Text(guideOSText(language, "不重复", "繰り返さない", "Never")).tag("")
                    Text(guideOSText(language, "每天", "毎日", "Daily")).tag("daily")
                    Text(guideOSText(language, "每周", "毎週", "Weekly")).tag("weekly")
                    Text(guideOSText(language, "每月", "毎月", "Monthly")).tag("monthly")
                    Text(guideOSText(language, "每年", "毎年", "Yearly")).tag("yearly")
                }
                .font(.subheadline.weight(.semibold))
                TextField(guideOSText(language, "备注（可选）", "メモ（任意）", "Notes (optional)"), text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Button {
                    let dateText = GuideOSDate.iso(date)
                    let timeText = allDay ? nil : Self.timeFormatter.string(from: time)
                    Task {
                        if await model.createCalendarEvent(
                            title: title,
                            date: dateText,
                            time: timeText,
                            allDay: allDay,
                            recurrence: recurrence,
                            notes: notes
                        ) {
                            title = ""
                            notes = ""
                            recurrence = ""
                            allDay = true
                            withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
                        }
                    }
                } label: {
                    HStack {
                        if model.isSaving { ProgressView().tint(.white) }
                        Text(model.isSaving ? guideOSText(language, "添加中", "追加中", "Adding") : guideOSText(language, "添加日程", "予定を追加", "Add event"))
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.fullArea)
                .foregroundStyle(.white)
                .background(KXColor.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(model.isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(model.isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }
        }
        .padding(14)
        .kxGlassSurface(radius: 20)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct GuideCalendarEventRow: View {
    @Environment(\.appLanguage) private var language
    let event: KaiXGuideCalendarItemDTO
    @ObservedObject var model: GuideCalendarViewModel
    @State private var showEditor = false

    var body: some View {
        Button {
            showEditor = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.indigo)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(event.allDay == false ? GuideCalendarEventEditor.timeText(event.startAt, language) : guideOSText(language, "全天", "終日", "All-day"))
                        if let recurrence = event.recurrence, !recurrence.isEmpty {
                            Text(GuideCalendarEventEditor.recurrenceLabel(recurrence, language))
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(12)
            .contentShape(Rectangle())
            .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.fullArea)
        .sheet(isPresented: $showEditor) {
            GuideCalendarEventEditor(event: event, model: model)
        }
    }
}

private struct GuideCalendarEventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    let event: KaiXGuideCalendarItemDTO
    @ObservedObject var model: GuideCalendarViewModel
    @State private var title: String
    @State private var date: Date
    @State private var time: Date
    @State private var allDay: Bool
    @State private var recurrence: String
    @State private var notes: String
    @State private var confirmDelete = false

    init(event: KaiXGuideCalendarItemDTO, model: GuideCalendarViewModel) {
        self.event = event
        self.model = model
        _title = State(initialValue: event.title)
        _date = State(initialValue: GuideOSDate.parse(event.date) ?? Date())
        _time = State(initialValue: Self.timeDate(event.startAt))
        _allDay = State(initialValue: event.allDay ?? true)
        _recurrence = State(initialValue: event.recurrence ?? "")
        _notes = State(initialValue: event.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GuideBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField(guideOSText(language, "标题", "タイトル", "Title"), text: $title)
                            .font(.title3.weight(.bold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(KXColor.livingSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(spacing: 4) {
                            DatePicker(guideOSText(language, "日期", "日付", "Date"), selection: $date, displayedComponents: .date)
                            Toggle(guideOSText(language, "全天", "終日", "All-day"), isOn: $allDay)
                            if !allDay {
                                DatePicker(guideOSText(language, "时间", "時刻", "Time"), selection: $time, displayedComponents: .hourAndMinute)
                            }
                            Picker(guideOSText(language, "重复", "繰り返し", "Repeat"), selection: $recurrence) {
                                Text(guideOSText(language, "不重复", "繰り返さない", "Never")).tag("")
                                Text(guideOSText(language, "每天", "毎日", "Daily")).tag("daily")
                                Text(guideOSText(language, "每周", "毎週", "Weekly")).tag("weekly")
                                Text(guideOSText(language, "每月", "毎月", "Monthly")).tag("monthly")
                                Text(guideOSText(language, "每年", "毎年", "Yearly")).tag("yearly")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(14)
                        .background(KXColor.livingSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(guideOSText(language, "备注", "メモ", "Notes"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            TextField(guideOSText(language, "地址、链接、联系人或准备事项", "住所・リンク・連絡先・持ち物など", "Address, link, contact, or things to prepare"), text: $notes, axis: .vertical)
                                .lineLimit(4...10)
                        }
                        .padding(14)
                        .background(KXColor.livingSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label(guideOSText(language, "删除日程", "予定を削除", "Delete event"), systemImage: "trash")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.fullArea)
                        .foregroundStyle(.red)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(KXSpacing.screen)
                }
            }
            .navigationTitle(guideOSText(language, "日程详情", "予定の詳細", "Event details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(guideOSText(language, "取消", "キャンセル", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? guideOSText(language, "保存中", "保存中", "Saving") : guideOSText(language, "保存", "保存", "Save")) {
                        let dateText = GuideOSDate.iso(date)
                        let startAt = allDay ? dateText : "\(dateText)T\(Self.timeFormatter.string(from: time))"
                        Task {
                            if await model.updateCalendarEvent(
                                event,
                                payload: .init(
                                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                    date: dateText,
                                    startAt: startAt,
                                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                    recurrence: recurrence,
                                    allDay: allDay
                                )
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(guideOSText(language, "删除这个日程？", "この予定を削除しますか？", "Delete this event?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(guideOSText(language, "删除", "削除", "Delete"), role: .destructive) {
                    Task {
                        if await model.deleteCalendarEvent(event) { dismiss() }
                    }
                }
                Button(guideOSText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
            } message: {
                Text(guideOSText(language, "删除后无法恢复。", "削除すると元に戻せません。", "This cannot be undone."))
            }
        }
    }

    static func timeText(_ raw: String?, _ language: AppLanguage) -> String {
        guard let raw, let marker = raw.range(of: "T") else {
            return guideOSText(language, "定时日程", "時間指定の予定", "Timed event")
        }
        return String(raw[marker.upperBound...].prefix(5))
    }

    static func recurrenceLabel(_ raw: String, _ language: AppLanguage) -> String {
        switch raw {
        case "daily": return guideOSText(language, "每天", "毎日", "Daily")
        case "weekly": return guideOSText(language, "每周", "毎週", "Weekly")
        case "monthly": return guideOSText(language, "每月", "毎月", "Monthly")
        case "yearly": return guideOSText(language, "每年", "毎年", "Yearly")
        default: return raw
        }
    }

    private static func timeDate(_ raw: String?) -> Date {
        // Only the HH:mm parse matters here; pass any language for the placeholder fallback.
        let value = timeText(raw, .zh)
        return timeFormatter.date(from: value) ?? Date()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private enum GuideCalendarCountdown {
    static func daysUntil(_ raw: String) -> Int? {
        let dateText = String(raw.prefix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let target = formatter.date(from: dateText),
              let today = formatter.date(from: formatter.string(from: Date())) else { return nil }
        return Calendar.current.dateComponents([.day], from: today, to: target).day
    }
}

private struct GuideCalendarCountdownStrip: View {
    let items: [(date: String, title: String, days: Int)]
    @Environment(\.appLanguage) private var language

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(guideOSText(language, "最近倒数", "直近のカウントダウン", "Upcoming countdown"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items, id: \.date) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.days == 0 ? guideOSText(language, "今天", "今日", "Today") : guideOSText(language, "\(item.days) 天", "あと\(item.days)日", "\(item.days) days"))
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(item.days <= 3 ? .orange : KXColor.accent)
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                Text(GuideOSDate.short(item.date))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 138, alignment: .leading)
                            .padding(12)
                            .kxGlassSurface(radius: 16)
                        }
                    }
                }
            }
        }
    }
}
