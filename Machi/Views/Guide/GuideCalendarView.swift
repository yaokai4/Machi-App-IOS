import SwiftUI

private enum GuideCalendarMode: String, CaseIterable, Identifiable {
    case month
    case week
    case agenda

    var id: String { rawValue }
    var title: String {
        switch self {
        case .month: return "月"
        case .week: return "周"
        case .agenda: return "日程"
        }
    }
}

private enum GuideCalendarScope: String, CaseIterable, Identifiable {
    case all
    case next7
    case next30
    case overdue

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .next7: return "未来 7 天"
        case .next30: return "未来 30 天"
        case .overdue: return "逾期"
        }
    }
}

struct GuideCalendarView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideCalendarViewModel()
    @State private var selectedDate = GuideOSDate.today()
    @State private var mode: GuideCalendarMode = .month
    @State private var scope: GuideCalendarScope = .all

    private var scopedItems: [KaiXGuideCalendarItemDTO] {
        let today = GuideOSDate.today()
        let end7 = GuideOSDate.today(offset: 7)
        let end30 = GuideOSDate.today(offset: 30)
        return model.calendarItems.filter { item in
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
            return (date, items.first?.title ?? "\(items.count) 项任务", days)
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
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(GuideCalendarScope.allCases) { item in
                                Button {
                                    scope = item
                                } label: {
                                    Text(item.title)
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
            if !model.requireLogin() { return }
            await model.loadCalendar()
        }
        .refreshable { await model.loadCalendar() }
    }
}

private struct GuideCalendarMonthGrid: View {
    let grouped: [String: [KaiXGuideCalendarItemDTO]]
    @Binding var selectedDate: String
    let onMove: (_ id: String, _ date: String) -> Void
    @State private var cursor = Date()

    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var cells: [Date] {
        let calendar = Calendar.current
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: cursor)) ?? Date()
        let start = calendar.date(byAdding: .day, value: -calendar.component(.weekday, from: first) + 1, to: first) ?? first
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var monthTitle: String {
        let comps = Calendar.current.dateComponents([.year, .month], from: cursor)
        return "\(comps.year ?? 0) 年 \(comps.month ?? 0) 月"
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
                    Button {
                        cursor = Date()
                        selectedDate = GuideOSDate.today()
                    } label: {
                        Text("今天")
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
    let grouped: [String: [KaiXGuideCalendarItemDTO]]
    @Binding var selectedDate: String
    let onMove: (_ id: String, _ date: String) -> Void
    @State private var cursor = Date()

    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -calendar.component(.weekday, from: cursor) + 1, to: cursor) ?? cursor
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var rangeTitle: String {
        guard let first = days.first, let last = days.last else { return "" }
        let c = Calendar.current
        return "\(c.component(.month, from: first))月\(c.component(.day, from: first))日 - \(c.component(.month, from: last))月\(c.component(.day, from: last))日"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(rangeTitle)
                    .font(.headline.weight(.bold))
                Spacer()
                HStack(spacing: 8) {
                    weekButton("chevron.left") { shiftWeek(-1) }
                    Button {
                        cursor = Date()
                        selectedDate = GuideOSDate.today()
                    } label: {
                        Text("本周")
                            .font(.caption.weight(.bold))
                            .frame(minHeight: 44)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.fullArea)
                    .contentShape(Rectangle())
                    .background(KXColor.livingSurface.opacity(0.78), in: Capsule())
                    weekButton("chevron.right") { shiftWeek(1) }
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
                    Text(isToday ? "今天" : "周\(weekdays[max(0, min(dayIndex, weekdays.count - 1))])")
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
                        Text("空")
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
                            Text("+\(items.count - 4) 项")
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
    let date: String
    let items: [KaiXGuideCalendarItemDTO]
    @ObservedObject var model: GuideCalendarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(GuideOSDate.short(date))
                    .font(.headline.weight(.bold))
                Spacer()
                Text("\(items.count) 项")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            if items.isEmpty {
                GuideOSEmptyMini(text: "这一天还没有任务，可以直接在上方添加。")
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
    let grouped: [(String, [KaiXGuideCalendarItemDTO])]
    @ObservedObject var model: GuideCalendarViewModel

    var body: some View {
        if grouped.isEmpty {
            GuideOSEmptyPanel(
                title: "还没有日程",
                subtitle: "添加 Todo、申请、面试或生活缴费后，会自动出现在这里。"
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
                Text("\(items.count) 项")
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
        if date == GuideOSDate.today() { return "今天" }
        if date == GuideOSDate.today(offset: 1) { return "明天" }
        if date < GuideOSDate.today() { return "逾期 · \(GuideOSDate.short(date))" }
        return GuideOSDate.short(date)
    }
}

private struct GuideCalendarEventComposer: View {
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
                        Text("新建日程")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("会议、预约和个人安排，独立于 Todo")
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
                TextField("日程标题，例如：大学院线上说明会", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                DatePicker("日期", selection: $date, displayedComponents: .date)
                    .font(.subheadline.weight(.semibold))
                Toggle("全天", isOn: $allDay)
                    .font(.subheadline.weight(.semibold))
                if !allDay {
                    DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                        .font(.subheadline.weight(.semibold))
                }
                Picker("重复", selection: $recurrence) {
                    Text("不重复").tag("")
                    Text("每天").tag("daily")
                    Text("每周").tag("weekly")
                    Text("每月").tag("monthly")
                    Text("每年").tag("yearly")
                }
                .font(.subheadline.weight(.semibold))
                TextField("备注（可选）", text: $notes, axis: .vertical)
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
                        Text(model.isSaving ? "添加中" : "添加日程")
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
                        Text(event.allDay == false ? GuideCalendarEventEditor.timeText(event.startAt) : "全天")
                        if let recurrence = event.recurrence, !recurrence.isEmpty {
                            Text(GuideCalendarEventEditor.recurrenceLabel(recurrence))
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
                        TextField("标题", text: $title)
                            .font(.title3.weight(.bold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(KXColor.livingSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(spacing: 4) {
                            DatePicker("日期", selection: $date, displayedComponents: .date)
                            Toggle("全天", isOn: $allDay)
                            if !allDay {
                                DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                            }
                            Picker("重复", selection: $recurrence) {
                                Text("不重复").tag("")
                                Text("每天").tag("daily")
                                Text("每周").tag("weekly")
                                Text("每月").tag("monthly")
                                Text("每年").tag("yearly")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(14)
                        .background(KXColor.livingSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        VStack(alignment: .leading, spacing: 8) {
                            Text("备注")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            TextField("地址、链接、联系人或准备事项", text: $notes, axis: .vertical)
                                .lineLimit(4...10)
                        }
                        .padding(14)
                        .background(KXColor.livingSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("删除日程", systemImage: "trash")
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
            .navigationTitle("日程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isSaving ? "保存中" : "保存") {
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
            .confirmationDialog("删除这个日程？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    Task {
                        if await model.deleteCalendarEvent(event) { dismiss() }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后无法恢复。")
            }
        }
    }

    static func timeText(_ raw: String?) -> String {
        guard let raw, let marker = raw.range(of: "T") else { return "定时日程" }
        return String(raw[marker.upperBound...].prefix(5))
    }

    static func recurrenceLabel(_ raw: String) -> String {
        switch raw {
        case "daily": return "每天"
        case "weekly": return "每周"
        case "monthly": return "每月"
        case "yearly": return "每年"
        default: return raw
        }
    }

    private static func timeDate(_ raw: String?) -> Date {
        let value = timeText(raw)
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
                                Text(item.days == 0 ? "今天" : "\(item.days) 天")
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
