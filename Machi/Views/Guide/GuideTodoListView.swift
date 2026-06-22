import SwiftUI

struct GuideOSTodoStrip: View {
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

struct GuideOSTodoCard: View {
    let todo: KaiXGuideTodoDTO
    let onComplete: () -> Void
    /// When provided, a bell button appears that opens `GuideReminderSheet`.
    var onSetReminder: ((_ reminderAt: String) async -> Bool)? = nil
    /// When provided, a "改期" menu reschedules the todo's planned date (spec P2).
    var onReschedule: ((_ plannedDate: String) -> Void)? = nil
    @State private var showReminder = false
    @State private var showDatePicker = false
    @State private var pickedDate = Date()

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
    }
}

/// Spec §十三 GuideTodoListView — a dedicated, filterable list of every open
/// Guide todo (today / upcoming / all). Server-first via `GuideTodoViewModel`;
/// each row can be completed or given a reminder.
struct GuideTodoListView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var model = GuideTodoViewModel()
    @State private var filter = "open"

    // Spec P2: bucket todos into 逾期 / 今天 / 未来 7 天 / 以后, urgent-first.
    private var groupedTodos: [(String, [KaiXGuideTodoDTO], Bool)] {
        if filter == "done" { return [(guideOSText(language, "已完成", "完了", "Done"), model.todos, false)] }
        let today = GuideOSDate.today()
        let week = GuideOSDate.today(offset: 7)
        var overdue: [KaiXGuideTodoDTO] = [], todayList: [KaiXGuideTodoDTO] = []
        var soon: [KaiXGuideTodoDTO] = [], later: [KaiXGuideTodoDTO] = []
        for t in model.todos {
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
                    Picker("", selection: $filter) {
                        Text(guideOSText(language, "未完成", "未完了", "Open")).tag("open")
                        Text(guideOSText(language, "已完成", "完了", "Done")).tag("done")
                    }
                    .pickerStyle(.segmented)
                    if let message = model.message { GuideOSNotice(message: message) }
                    if model.todos.isEmpty && !model.isLoading {
                        GuideOSEmptyMini(text: guideOSText(language, "这里会汇总你所有计划的待办。", "すべての計画のタスクがここに集まります。", "Every plan's todos collect here."))
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
                                        onReschedule: { date in Task { await model.reschedule(todo, to: date) } }
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
        .task { if model.requireLogin() { await model.loadTodos(status: filter) } }
        .onChange(of: filter) { _, newValue in Task { await model.loadTodos(status: newValue) } }
        .refreshable { await model.loadTodos(status: filter) }
    }
}
