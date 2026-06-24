import SwiftUI

struct GuideOSTodoStrip: View {
    let title: String
    let todos: [KaiXGuideTodoDTO]
    let onComplete: (KaiXGuideTodoDTO) -> Void
    /// Locally hide a todo the moment it's checked, so it disappears instantly
    /// (the server reload then drops it from the payload for good).
    @State private var hidden: Set<String> = []

    private var visible: [KaiXGuideTodoDTO] {
        Array(todos.filter { !hidden.contains($0.id) }.prefix(4))
    }

    var body: some View {
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                ForEach(visible) { todo in
                    GuideOSTodoCard(todo: todo) {
                        withAnimation(.easeInOut(duration: 0.2)) { _ = hidden.insert(todo.id) }
                        onComplete(todo)
                    }
                }
            }
        }
    }
}

struct GuideOSTodoCard: View {
    let todo: KaiXGuideTodoDTO
    let onComplete: () -> Void
    /// When provided, a bell button appears that opens `GuideReminderSheet`.
    var onSetReminder: ((_ reminderAt: String) async -> Bool)? = nil
    /// When provided, a "改期" menu reschedules the todo's planned date (spec P2).
    var onReschedule: ((_ plannedDate: String) -> Void)? = nil
    /// When provided, the subtask checklist becomes interactive (toggle / add /
    /// delete); otherwise steps render read-only.
    var onUpdateSteps: ((_ steps: [KaiXGuideTodoStep]) -> Void)? = nil
    /// When provided, a Notion-style inline note editor appears on the todo.
    var onUpdateNotes: ((_ notes: String) -> Void)? = nil
    /// Full task-detail actions. The card itself opens the detail sheet while
    /// nested controls continue to perform their direct actions.
    var onUpdate: ((_ payload: KaiXGuideTodoUpdatePayload) async -> Bool)? = nil
    var onDuplicate: (() async -> Bool)? = nil
    var onArchive: (() async -> Bool)? = nil
    var onDelete: (() async -> Bool)? = nil
    @State private var showReminder = false
    @State private var showDatePicker = false
    @State private var pickedDate = Date()
    @State private var newStep = ""
    @State private var noteOpen = false
    @State private var noteDraft = ""
    @State private var showDetail = false

    private var tint: Color {
        switch todo.priority {
        case "high": return .orange
        case "low": return .secondary
        default: return KXColor.accent
        }
    }

    private func shifted(_ days: Int) -> String {
        GuideOSDate.iso(Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }

    private var steps: [KaiXGuideTodoStep] { todo.steps ?? [] }

    private func toggleStep(_ step: KaiXGuideTodoStep) {
        onUpdateSteps?(steps.map { $0.id == step.id ? KaiXGuideTodoStep(id: $0.id, text: $0.text, done: !$0.done) : $0 })
    }
    private func removeStep(_ step: KaiXGuideTodoStep) {
        onUpdateSteps?(steps.filter { $0.id != step.id })
    }
    private func addStep() {
        let t = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        onUpdateSteps?(steps + [KaiXGuideTodoStep(id: UUID().uuidString, text: t, done: false)])
        newStep = ""
    }

    private func openNote() {
        noteDraft = todo.notes
        noteOpen = true
    }

    private func saveNote() {
        onUpdateNotes?(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        noteOpen = false
    }

    @ViewBuilder private var stepsChecklist: some View {
        if !steps.isEmpty || (onUpdateSteps != nil && !todo.isDone) {
            VStack(alignment: .leading, spacing: 5) {
                if !steps.isEmpty {
                    let doneN = steps.filter(\.done).count
                    HStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.15))
                                Capsule().fill(KXColor.accent)
                                    .frame(width: geo.size.width * CGFloat(doneN) / CGFloat(max(steps.count, 1)))
                            }
                        }
                        .frame(height: 5)
                        Text("\(doneN)/\(steps.count)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                ForEach(steps) { step in
                    HStack(spacing: 7) {
                        Button { toggleStep(step) } label: {
                            Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(step.done ? KXColor.accent : Color.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .disabled(onUpdateSteps == nil)
                        Text(step.text)
                            .font(.caption)
                            .strikethrough(step.done)
                            .foregroundStyle(step.done ? .secondary : .primary)
                        Spacer(minLength: 0)
                        if onUpdateSteps != nil {
                            Button { removeStep(step) } label: {
                                Image(systemName: "xmark").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if onUpdateSteps != nil && !todo.isDone {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.caption2).foregroundStyle(.secondary)
                        TextField("添加步骤…", text: $newStep)
                            .font(.caption)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addStep)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder private var noteSection: some View {
        if onUpdateNotes != nil {
            if noteOpen {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $noteDraft)
                        .font(.caption)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 72)
                        .padding(8)
                        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(KXColor.separator.opacity(0.85), lineWidth: 0.8)
                        )
                    HStack(spacing: 10) {
                        Button(action: saveNote) {
                            Text("保存备注")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .foregroundStyle(.white)
                        .background(KXColor.accent, in: Capsule())
                        Button {
                            noteDraft = todo.notes
                            noteOpen = false
                        } label: {
                            Text("取消")
                                .font(.caption.weight(.bold))
                                .frame(height: 30)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            } else if !todo.notes.isEmpty {
                Button(action: openNote) {
                    Text(todo.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.top, 4)
            } else if !todo.isDone {
                Button(action: openNote) {
                    Label("备注", systemImage: "note.text")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.top, 2)
            }
        } else if !todo.notes.isEmpty {
            Text(todo.notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .padding(.top, 4)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onComplete) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(todo.isDone ? KXColor.accent : tint.opacity(0.65))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        .contentShape(Rectangle())
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
                    if let onReschedule, !todo.isDone {
                        Menu {
                            Button("今天") { onReschedule(shifted(0)) }
                            Button("明天") { onReschedule(shifted(1)) }
                            Button("+7 天") { onReschedule(shifted(7)) }
                            Button("自定义日期…") { showDatePicker = true }
                        } label: {
                            Image(systemName: "calendar.badge.clock")
                                .font(.caption)
                                .foregroundStyle(tint)
                                .frame(width: 32, height: 32)
                        }
                        .contentShape(Rectangle())
                    }
                    if onSetReminder != nil {
                        Button { showReminder = true } label: {
                            Image(systemName: (todo.reminderAt ?? "").isEmpty ? "bell" : "bell.fill")
                                .font(.caption)
                                .foregroundStyle(tint)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
        .contentShape(Rectangle())
                    }
                }
                if !todo.summary.isEmpty {
                    Text(todo.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                stepsChecklist
                noteSection
                HStack(spacing: 6) {
                    GuideOSMiniBadge(text: todo.todoType.replacingOccurrences(of: "_", with: " "))
                    if let r = todo.recurrenceLabel {
                        Label(r + "循环", systemImage: "repeat")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(KXColor.accent.opacity(0.12), in: Capsule())
                    }
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
        .contentShape(Rectangle())
        .onTapGesture {
            if onUpdate != nil {
                showDetail = true
            }
        }
        .accessibilityHint(onUpdate == nil ? "" : "打开 Todo 详情")
        .sheet(isPresented: $showReminder) {
            if let onSetReminder {
                GuideReminderSheet(todo: todo, onSave: onSetReminder)
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("改到", selection: $pickedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("改期")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("确定") { onReschedule?(GuideOSDate.iso(pickedDate)); showDatePicker = false }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showDatePicker = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showDetail) {
            if let onUpdate {
                GuideTodoDetailSheet(
                    todo: todo,
                    onComplete: onComplete,
                    onUpdate: onUpdate,
                    onDuplicate: onDuplicate,
                    onArchive: onArchive,
                    onDelete: onDelete
                )
            }
        }
    }
}

/// Spec §十三 GuideTodoListView — a dedicated, filterable list of every open
/// Guide todo (today / upcoming / all). Server-first via `GuideTodoViewModel`;
/// each row can be completed or given a reminder.
struct GuideTodoListView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideTodoViewModel()
    @State private var filter = "my_day"
    @State private var searchText = ""
    @State private var listFilter = ""
    @State private var tagFilter = ""
    var planId: String? = nil
    var customTitle: String? = nil

    private var apiStatus: String { filter == "completed" ? "done" : "open" }

    private var filteredTodos: [KaiXGuideTodoDTO] {
        let today = GuideOSDate.today()
        let scoped: [KaiXGuideTodoDTO]
        switch filter {
        case "my_day":
            scoped = model.todos.filter {
                let when = String(($0.displayDate ?? "").prefix(10))
                return when.isEmpty || when <= today
            }
        case "planned":
            scoped = model.todos.filter { !(($0.displayDate ?? "").isEmpty) }
        case "important":
            scoped = model.todos.filter { $0.priority == "high" }
        case "completed":
            scoped = model.todos
        default:
            scoped = model.todos
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = scoped
        if !listFilter.isEmpty {
            result = result.filter { ($0.listName ?? "") == listFilter }
        }
        if !tagFilter.isEmpty {
            result = result.filter { ($0.tags ?? []).contains(tagFilter) }
        }
        guard !query.isEmpty else { return result }
        return result.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.summary.localizedCaseInsensitiveContains(query)
                || $0.notes.localizedCaseInsensitiveContains(query)
        }
    }

    private var customLists: [String] {
        Array(Set(model.todos.compactMap { value in
            let list = (value.listName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return list.isEmpty ? nil : list
        })).sorted()
    }

    private var tags: [String] {
        Array(Set(model.todos.flatMap { $0.tags ?? [] })).sorted()
    }

    // Spec P2: bucket todos into 逾期 / 今天 / 未来 7 天 / 以后, urgent-first.
    private var groupedTodos: [(String, [KaiXGuideTodoDTO], Bool)] {
        if filter == "completed" { return [(guideOSText(language, "已完成", "完了", "Done"), filteredTodos, false)] }
        let today = GuideOSDate.today()
        let week = GuideOSDate.today(offset: 7)
        var overdue: [KaiXGuideTodoDTO] = [], todayList: [KaiXGuideTodoDTO] = []
        var soon: [KaiXGuideTodoDTO] = [], later: [KaiXGuideTodoDTO] = []
        for t in filteredTodos {
            let when = String((t.displayDate ?? "").prefix(10))
            if when.isEmpty { later.append(t) }
            else if when < today { overdue.append(t) }
            else if when == today { todayList.append(t) }
            else if when <= week { soon.append(t) }
            else { later.append(t) }
        }
        return [
            (guideOSText(language, "逾期", "期限切れ", "Overdue"), overdue, true),
            (guideOSText(language, "今天", "今日", "Today"), todayList, false),
            (guideOSText(language, "未来 7 天", "今後 7 日", "Next 7 days"), soon, false),
            (guideOSText(language, "以后 / 待安排", "以降 / 未定", "Later"), later, false),
        ]
    }

    var body: some View {
        ZStack {
            GuideBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    GuideOSHeaderRow(
                        title: customTitle ?? guideOSText(language, "我的 Todo", "マイ Todo", "My Todo"),
                        subtitle: guideOSText(language, "像 Microsoft To Do 一样，把今天、计划中、重要和已完成放进同一个系统。", "今日・予定・重要・完了を一つにまとめます。", "My Day, Planned, Important, and Done in one system.")
                    )
                    GuideQuickTodoComposer(isSaving: model.isSaving) { content, plannedDate in
                        Task { await model.createQuickTodo(content: content, plannedDate: plannedDate, planId: planId) }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            GuideTodoFilterChip(title: guideOSText(language, "我的一天", "今日", "My Day"), value: "my_day", selection: $filter)
                            GuideTodoFilterChip(title: guideOSText(language, "重要", "重要", "Important"), value: "important", selection: $filter)
                            GuideTodoFilterChip(title: guideOSText(language, "计划中", "予定", "Planned"), value: "planned", selection: $filter)
                            GuideTodoFilterChip(title: guideOSText(language, "所有任务", "すべて", "All"), value: "all", selection: $filter)
                            GuideTodoFilterChip(title: guideOSText(language, "已完成", "完了", "Done"), value: "completed", selection: $filter)
                        }
                    }
                    if !customLists.isEmpty || !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                GuideTodoFilterChip(title: "全部清单", value: "", selection: Binding(
                                    get: { listFilter.isEmpty && tagFilter.isEmpty ? "" : "__none__" },
                                    set: { _ in listFilter = ""; tagFilter = "" }
                                ))
                                ForEach(customLists, id: \.self) { list in
                                    Button {
                                        listFilter = list
                                        tagFilter = ""
                                    } label: {
                                        Text(list)
                                            .font(.caption.weight(.bold))
                                            .padding(.horizontal, 13)
                                            .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .foregroundStyle(listFilter == list ? Color.white : Color.secondary)
                                    .background(listFilter == list ? KXColor.accent : Color.white.opacity(0.78), in: Capsule())
                                }
                                ForEach(tags, id: \.self) { tag in
                                    Button {
                                        tagFilter = tag
                                        listFilter = ""
                                    } label: {
                                        Text("#\(tag)")
                                            .font(.caption.weight(.bold))
                                            .padding(.horizontal, 13)
                                            .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .foregroundStyle(tagFilter == tag ? Color.white : Color.secondary)
                                    .background(tagFilter == tag ? KXColor.accent : Color.white.opacity(0.78), in: Capsule())
                                }
                            }
                        }
                    }
                    if let message = model.message { GuideOSNotice(message: message) }
                    if filteredTodos.isEmpty && !model.isLoading {
                        GuideOSEmptyMini(text: guideOSText(language, "这里会汇总你所有计划的待办，也可以直接输入一条 Todo。", "すべての計画のタスクがここに集まり、直接追加もできます。", "Every plan's todos collect here, and you can add directly."))
                    } else {
                        ForEach(groupedTodos, id: \.0) { section in
                            if !section.1.isEmpty {
                                Text(section.0)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(section.2 ? Color.orange : Color.primary)
                                ForEach(section.1) { todo in
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
        .navigationTitle(guideOSText(language, "全部待办", "すべてのタスク", "All todos"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: guideOSText(language, "搜索任务", "タスクを検索", "Search tasks"))
        .task { if model.requireLogin() { await model.loadTodos(status: apiStatus, planId: planId) } }
        .onChange(of: filter) { _, _ in Task { await model.loadTodos(status: apiStatus, planId: planId) } }
        .refreshable { await model.loadTodos(status: apiStatus, planId: planId) }
    }
}

private struct GuideTodoDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let todo: KaiXGuideTodoDTO
    let onComplete: () -> Void
    let onUpdate: (KaiXGuideTodoUpdatePayload) async -> Bool
    let onDuplicate: (() async -> Bool)?
    let onArchive: (() async -> Bool)?
    let onDelete: (() async -> Bool)?

    @State private var title: String
    @State private var summary: String
    @State private var notes: String
    @State private var priority: String
    @State private var recurrence: String
    @State private var plannedDate: Date
    @State private var dueDate: Date
    @State private var hasPlannedDate: Bool
    @State private var hasDueDate: Bool
    @State private var listName: String
    @State private var tagsText: String
    @State private var saving = false
    @State private var confirmingDelete = false
    @State private var restoredDraft: Bool
    @State private var shouldPreserveDraft = true

    init(
        todo: KaiXGuideTodoDTO,
        onComplete: @escaping () -> Void,
        onUpdate: @escaping (KaiXGuideTodoUpdatePayload) async -> Bool,
        onDuplicate: (() async -> Bool)?,
        onArchive: (() async -> Bool)?,
        onDelete: (() async -> Bool)?
    ) {
        self.todo = todo
        self.onComplete = onComplete
        self.onUpdate = onUpdate
        self.onDuplicate = onDuplicate
        self.onArchive = onArchive
        self.onDelete = onDelete
        let draft = GuideTodoDraftCache.draft(for: todo.id)
        _title = State(initialValue: draft?.title ?? todo.title)
        _summary = State(initialValue: draft?.summary ?? todo.summary)
        _notes = State(initialValue: draft?.notes ?? todo.notes)
        _priority = State(initialValue: draft?.priority ?? (todo.priority.isEmpty ? "normal" : todo.priority))
        _recurrence = State(initialValue: draft?.recurrence ?? (todo.recurrence ?? ""))
        _plannedDate = State(initialValue: draft?.plannedDate ?? GuideOSDate.parse(todo.plannedDate) ?? Date())
        _dueDate = State(initialValue: draft?.dueDate ?? GuideOSDate.parse(todo.dueAt) ?? Date())
        _hasPlannedDate = State(initialValue: draft?.hasPlannedDate ?? !(todo.plannedDate ?? "").isEmpty)
        _hasDueDate = State(initialValue: draft?.hasDueDate ?? !(todo.dueAt ?? "").isEmpty)
        _listName = State(initialValue: draft?.listName ?? (todo.listName ?? ""))
        _tagsText = State(initialValue: draft?.tagsText ?? (todo.tags ?? []).joined(separator: ", "))
        _restoredDraft = State(initialValue: draft != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if restoredDraft {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundStyle(KXColor.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("已恢复未保存草稿")
                                    .font(.subheadline.weight(.bold))
                                Text("关闭详情后再次打开，刚才的编辑仍会保留。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Button("清除") {
                                resetToSavedTodo()
                            }
                            .font(.caption.weight(.bold))
                        }
                    }
                }
                Section("任务") {
                    TextField("Todo 标题", text: $title, axis: .vertical)
                    TextField("说明", text: $summary, axis: .vertical)
                    Picker("优先级", selection: $priority) {
                        Text("高").tag("high")
                        Text("普通").tag("normal")
                        Text("低").tag("low")
                    }
                }
                Section("安排") {
                    Toggle("计划日期", isOn: $hasPlannedDate)
                    if hasPlannedDate {
                        DatePicker("开始", selection: $plannedDate, displayedComponents: .date)
                    }
                    Toggle("截止日期", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("截止", selection: $dueDate, displayedComponents: .date)
                    }
                    Picker("重复", selection: $recurrence) {
                        Text("不重复").tag("")
                        Text("每天").tag("daily")
                        Text("每周").tag("weekly")
                        Text("每月").tag("monthly")
                    }
                }
                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 110)
                }
                Section("附件") {
                    GuideAttachmentSection(entityType: "guide_task", entityId: todo.id, title: "任务附件")
                }
                Section("整理") {
                    TextField("自定义清单", text: $listName)
                    TextField("标签（逗号分隔）", text: $tagsText)
                }
                if !todo.sourceType.isEmpty {
                    Section("来源") {
                        LabeledContent("类型", value: todo.sourceType.replacingOccurrences(of: "_", with: " "))
                        if !todo.journeyKey.isEmpty {
                            LabeledContent("关联路径", value: todo.journeyKey)
                        }
                    }
                }
                Section {
                    if !todo.isDone {
                        Button {
                            clearDraft()
                            onComplete()
                            dismiss()
                        } label: {
                            Label("标记完成", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    if let onDuplicate {
                        Button {
                            Task {
                                if await onDuplicate() {
                                    clearDraft()
                                    dismiss()
                                }
                            }
                        } label: {
                            Label("复制 Todo", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    if let onArchive {
                        Button {
                            Task {
                                if await onArchive() {
                                    clearDraft()
                                    dismiss()
                                }
                            }
                        } label: {
                            Label("归档", systemImage: "archivebox")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                    if onDelete != nil {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("删除", systemImage: "trash")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
            }
            .navigationTitle("Todo 详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "保存") {
                        Task {
                            saving = true
                            let ok = await onUpdate(.init(
                                title: title,
                                summary: summary,
                                priority: priority,
                                notes: notes,
                                plannedDate: hasPlannedDate ? GuideOSDate.iso(plannedDate) : "",
                                dueAt: hasDueDate ? GuideOSDate.iso(dueDate) : "",
                                recurrence: recurrence,
                                listName: listName,
                                tags: tagsText
                                    .split(whereSeparator: { $0 == "," || $0 == "，" })
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                            ))
                            saving = false
                            if ok {
                                clearDraft()
                                dismiss()
                            }
                        }
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("删除这个 Todo？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    guard let onDelete else { return }
                    Task {
                        if await onDelete() {
                            clearDraft()
                            dismiss()
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后无法恢复；如果只是暂时不需要，可以选择归档。")
            }
            .onDisappear {
                if shouldPreserveDraft, hasUnsavedChanges {
                    GuideTodoDraftCache.save(currentDraft, for: todo.id)
                }
            }
        }
    }

    private var currentDraft: GuideTodoDraft {
        GuideTodoDraft(
            title: title,
            summary: summary,
            notes: notes,
            priority: priority,
            recurrence: recurrence,
            plannedDate: plannedDate,
            dueDate: dueDate,
            hasPlannedDate: hasPlannedDate,
            hasDueDate: hasDueDate,
            listName: listName,
            tagsText: tagsText
        )
    }

    private var hasUnsavedChanges: Bool {
        title != todo.title
            || summary != todo.summary
            || notes != todo.notes
            || priority != (todo.priority.isEmpty ? "normal" : todo.priority)
            || recurrence != (todo.recurrence ?? "")
            || (hasPlannedDate ? GuideOSDate.iso(plannedDate) : "") != (todo.plannedDate ?? "")
            || (hasDueDate ? GuideOSDate.iso(dueDate) : "") != (todo.dueAt ?? "")
            || listName != (todo.listName ?? "")
            || normalizedTags(tagsText) != (todo.tags ?? [])
    }

    private func normalizedTags(_ value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func clearDraft() {
        shouldPreserveDraft = false
        restoredDraft = false
        GuideTodoDraftCache.clear(todo.id)
    }

    private func resetToSavedTodo() {
        title = todo.title
        summary = todo.summary
        notes = todo.notes
        priority = todo.priority.isEmpty ? "normal" : todo.priority
        recurrence = todo.recurrence ?? ""
        plannedDate = GuideOSDate.parse(todo.plannedDate) ?? Date()
        dueDate = GuideOSDate.parse(todo.dueAt) ?? Date()
        hasPlannedDate = !(todo.plannedDate ?? "").isEmpty
        hasDueDate = !(todo.dueAt ?? "").isEmpty
        listName = todo.listName ?? ""
        tagsText = (todo.tags ?? []).joined(separator: ", ")
        restoredDraft = false
        GuideTodoDraftCache.clear(todo.id)
    }
}

private struct GuideTodoDraft {
    let title: String
    let summary: String
    let notes: String
    let priority: String
    let recurrence: String
    let plannedDate: Date
    let dueDate: Date
    let hasPlannedDate: Bool
    let hasDueDate: Bool
    let listName: String
    let tagsText: String
}

@MainActor
private enum GuideTodoDraftCache {
    private static var drafts: [String: GuideTodoDraft] = [:]

    static func draft(for id: String) -> GuideTodoDraft? {
        drafts[id]
    }

    static func save(_ draft: GuideTodoDraft, for id: String) {
        drafts[id] = draft
    }

    static func clear(_ id: String) {
        drafts.removeValue(forKey: id)
    }
}

private struct GuideTodoFilterChip: View {
    let title: String
    let value: String
    @Binding var selection: String

    var body: some View {
        Button {
            selection = value
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 13)
                .frame(minWidth: 64, minHeight: 44)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .foregroundStyle(selection == value ? Color.white : Color.secondary)
        .background(
            selection == value ? KXColor.accent : Color.white.opacity(0.78),
            in: Capsule()
        )
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}
