import Foundation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Subtle haptics for Guide OS interactions (spec #2 polish).
enum GuideHaptics {
    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

func guideOSText(_ language: AppLanguage, _ zh: String, _ ja: String, _ en: String) -> String {
    KXListingCopy.pickText(language, zh, ja, en)
}

func currentGuideOSLanguage() -> String {
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

enum GuideOSDate {
    // The workbench is a *local-day* system: "今天" must be the user's calendar
    // day (JST for users in Japan — the backend's _guide_today_date is JST too),
    // not UTC. The old UTC formatter shifted every date by a day between 00:00
    // and 09:00 JST: new todos landed in 逾期, the calendar highlighted the
    // wrong cell, and 改期 moved dates by -1.
    static func iso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        // DatePicker hands back a Date at the picker's wall-clock time; snap to
        // the local start-of-day so serialization is stable across the day.
        return formatter.string(from: Calendar.current.startOfDay(for: date))
    }

    static func today(offset days: Int = 0) -> String {
        iso(Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }

    static func short(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return String(raw.prefix(10)).replacingOccurrences(of: "-", with: ".")
    }

    /// Parse a server `yyyy-MM-dd` (or ISO) string back into a Date for editors.
    /// Local timezone to round-trip with `iso(_:)` — a UTC parse showed the
    /// previous day in DatePickers for negative-offset timezones.
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(raw.prefix(10)))
    }
}

// The cohesive Guide OS state engine. The spec lists five view-models; rather
// than duplicate fetch/state across five classes (which would re-request the
// same server data), they are thin focused subclasses that share this one
// server-first implementation — one source of truth, five named entry points.
@MainActor
class GuideOSViewModel: ObservableObject {
    @Published var dashboard: KaiXGuideActivePlanResponse?
    @Published var todos: [KaiXGuideTodoDTO] = []
    @Published var calendarItems: [KaiXGuideCalendarItemDTO] = []
    @Published var applications: [KaiXGuideApplicationDTO] = []
    @Published var lifeItems: [KaiXGuideLifeItemDTO] = []
    @Published var lifePayments: [String: [KaiXGuideLifePaymentDTO]] = [:]
    @Published var contracts: [KaiXGuideContractDTO] = []
    @Published var documents: [KaiXGuideDocumentDTO] = []
    @Published var plans: [KaiXGuidePlanDTO] = []
    @Published var goalJourneys: [KaiXGuideJourneyDTO] = []
    @Published var profile: KaiXGuideProfileDTO?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var message: String?
    /// 显式错误标志,与 message 同步设置。View 层判断提示颜色必须用它——绝不能靠
    /// `message.contains("失败")` 这类字符串包含判断(消息一旦本地化立刻失效)。
    @Published var messageIsError = false

    var isLoggedIn: Bool { KaiXBackend.token != nil }

    /// When set, `loadTodos` keeps only todos generated from these sources
    /// (e.g. the applications planner shows application todos, not 房租/背单词 —
    /// the server's `type` filter is a single exact todo_type, so the multi-type
    /// application ladder is filtered client-side by sourceType instead).
    var todoSourceTypeFilter: Set<String>? = nil

    /// 记住最近一次显式 loadTodos 的过滤参数。改期 / 复制 / 快速添加后的刷新必须
    /// 复用它(reloadTodos),否则计划域(planId)列表会在一次操作后突然混入
    /// 全部计划与手动任务,标题与内容不再对应。
    private var lastTodoQuery: (type: String?, status: String, planId: String?, limit: Int) = (nil, "open", nil, 100)

    /// 当前界面语言。VM 层的提示文案必须三语——此前 40 余处硬编码中文,
    /// 日/英用户在所有工作台操作里只能看到中文报错。
    private var uiLanguage: AppLanguage {
        AppLanguage.resolved(from: UserDefaults.standard.string(forKey: "appLanguageCode") ?? AppLanguage.system.rawValue)
    }

    /// 统一的三语提示出口,同时维护 messageIsError。
    private func notify(_ zh: String, _ ja: String, _ en: String, isError: Bool = false) {
        messageIsError = isError
        message = guideOSText(uiLanguage, zh, ja, en)
    }

    func requireLogin(_ reason: String? = nil) -> Bool {
        guard isLoggedIn else {
            GuestGate.shared.requireLogin(reason ?? guideOSText(
                uiLanguage,
                "登录后可以同步 Guide 计划、Todo、日历提醒和服务记录。",
                "ログインすると Guide の計画・Todo・カレンダー通知・サービス記録を同期できます。",
                "Sign in to sync Guide plans, todos, calendar reminders and records."
            ))
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
            let fresh = try await KaiXAPIClient.shared.guideActivePlan(language: currentGuideOSLanguage())
            dashboard = fresh
        } catch {
            notify("Guide 计划暂时无法同步。当前页面不会写入本地核心状态，请联网后下拉刷新。",
                   "Guide プランを同期できません。ローカルには保存されないため、接続を確認して下に引っ張って更新してください。",
                   "Couldn't sync your Guide plan. Nothing is saved locally — check your connection and pull to refresh.",
                   isError: true)
        }
    }

    func loadTodos(type: String? = nil, status: String = "open", planId: String? = nil, limit: Int = 100) async {
        lastTodoQuery = (type, status, planId, limit)
        guard isLoggedIn else { todos = []; return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            let items = try await KaiXAPIClient.shared.guideTodos(status: status, type: type, planId: planId, limit: limit).items
            if let filter = todoSourceTypeFilter {
                todos = items.filter { filter.contains($0.sourceType) }
            } else {
                todos = items
            }
        } catch {
            notify("任务列表加载失败。Guide 核心状态仅以服务器为准，请联网后重试。",
                   "タスクの読み込みに失敗しました。Guide のデータはサーバーが正となるため、接続を確認して再試行してください。",
                   "Couldn't load your tasks. Guide state lives on the server — check your connection and try again.",
                   isError: true)
        }
    }

    /// 用与上一次 loadTodos 完全相同的过滤参数刷新列表(见 lastTodoQuery)。
    func reloadTodos() async {
        await loadTodos(type: lastTodoQuery.type, status: lastTodoQuery.status, planId: lastTodoQuery.planId, limit: lastTodoQuery.limit)
    }

    func loadCalendar(days: Int = 90, pastDays: Int = 30) async {
        guard isLoggedIn else { calendarItems = []; return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            let items = try await KaiXAPIClient.shared.guideCalendar(from: GuideOSDate.today(offset: -pastDays), to: GuideOSDate.today(offset: days)).items
            calendarItems = items
        } catch {
            notify("日历暂时无法同步。Guide 核心状态仅以服务器为准，请联网后重试。",
                   "カレンダーを同期できません。接続を確認して再試行してください。",
                   "Couldn't sync the calendar. Check your connection and try again.",
                   isError: true)
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
            notify("提醒设置加载失败，请稍后再试。",
                   "リマインダー設定の読み込みに失敗しました。しばらくしてからお試しください。",
                   "Couldn't load reminder settings. Please try again later.",
                   isError: true)
        }
    }

    func saveProfile(_ payload: KaiXGuideProfileUpdatePayload) async {
        guard requireLogin() else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await KaiXAPIClient.shared.updateGuideProfile(payload)
            profile = response.profile
            if let count = response.generatedTodoCount, count > 0 {
                notify("个人提醒设置已更新，已同步 \(count) 项 Todo / 日历提醒。",
                       "リマインダー設定を更新し、\(count) 件の Todo・カレンダー通知を同期しました。",
                       "Reminder settings updated — synced \(count) todo/calendar reminders.")
            } else {
                notify("个人提醒设置已更新。",
                       "リマインダー設定を更新しました。",
                       "Reminder settings updated.")
            }
        } catch {
            notify("保存失败，请检查网络后重试。",
                   "保存に失敗しました。接続を確認して再試行してください。",
                   "Couldn't save. Check your connection and try again.",
                   isError: true)
        }
    }

    func complete(_ todo: KaiXGuideTodoDTO) async {
        guard requireLogin() else { return }
        do {
            let response = try await KaiXAPIClient.shared.completeGuideTodo(id: todo.id)
            GuideHaptics.success()
            withAnimation(.easeInOut(duration: 0.25)) {
                todos.removeAll { $0.id == todo.id }
            }
            // Mirror the completion into calendarItems immediately so the
            // calendar's month/week/agenda cards show the 勾+划线 state on the
            // spot — before this, the server marked it done but the card sat
            // untouched and users tapped (and POSTed) again.
            if let updated = response.todo {
                patchTodo(updated)
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    calendarItems.removeAll { $0.todoId == todo.id }
                }
            }
            await loadDashboard()
        } catch {
            notify("任务完成状态没有保存成功。",
                   "完了状態を保存できませんでした。",
                   "Couldn't save the completion.",
                   isError: true)
        }
    }

    /// MS To Do / Notion-style subtask checklist: persist a todo's new step list
    /// and patch it back into the in-memory list so the card updates instantly.
    func updateTodoSteps(_ todo: KaiXGuideTodoDTO, steps: [KaiXGuideTodoStep]) async {
        guard requireLogin() else { return }
        do {
            let resp = try await KaiXAPIClient.shared.updateGuideTodo(id: todo.id, payload: .init(steps: steps))
            if let updated = resp.todo {
                patchTodo(updated)
            }
        } catch {
            notify("子任务更新失败，请稍后再试。",
                   "サブタスクの更新に失敗しました。しばらくしてからお試しください。",
                   "Couldn't update the subtasks. Please try again later.",
                   isError: true)
        }
    }

    /// Notion-style task note: links, addresses, phone numbers, caveats and
    /// small context belong on the todo itself, synced by the server.
    func updateTodoNotes(_ todo: KaiXGuideTodoDTO, notes: String) async {
        guard requireLogin() else { return }
        do {
            let resp = try await KaiXAPIClient.shared.updateGuideTodo(id: todo.id, payload: .init(notes: notes))
            if let updated = resp.todo {
                patchTodo(updated)
                if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    notify("备注已清空。", "メモをクリアしました。", "Note cleared.")
                } else {
                    notify("备注已保存。", "メモを保存しました。", "Note saved.")
                }
            }
        } catch {
            notify("备注保存失败，请稍后再试。",
                   "メモの保存に失敗しました。しばらくしてからお試しください。",
                   "Couldn't save the note. Please try again later.",
                   isError: true)
        }
    }

    func updateTodo(_ todo: KaiXGuideTodoDTO, payload: KaiXGuideTodoUpdatePayload) async -> Bool {
        guard requireLogin() else { return false }
        do {
            let response = try await KaiXAPIClient.shared.updateGuideTodo(id: todo.id, payload: payload)
            if let updated = response.todo {
                patchTodo(updated)
            }
            notify("Todo 已更新。", "Todo を更新しました。", "Todo updated.")
            await loadCalendar()
            await loadDashboard()
            return true
        } catch {
            notify("Todo 更新失败，请稍后重试。",
                   "Todo の更新に失敗しました。しばらくしてからお試しください。",
                   "Couldn't update the todo. Please try again later.",
                   isError: true)
            return false
        }
    }

    func duplicateTodo(_ todo: KaiXGuideTodoDTO) async -> Bool {
        guard requireLogin() else { return false }
        do {
            _ = try await KaiXAPIClient.shared.createGuideTodo(.init(
                content: todo.title + "（副本）",
                summary: todo.summary,
                todoType: todo.todoType,
                priority: todo.priority,
                plannedDate: todo.plannedDate,
                dueAt: todo.dueAt,
                reminderAt: nil,
                planId: todo.planId.isEmpty ? nil : todo.planId,
                notes: todo.notes,
                recurrence: todo.recurrence,
                listName: todo.listName,
                tags: todo.tags
            ))
            notify("已复制 Todo。", "Todo を複製しました。", "Todo duplicated.")
            await reloadTodos()
            await loadCalendar()
            return true
        } catch {
            notify("复制失败，请稍后重试。",
                   "複製に失敗しました。しばらくしてからお試しください。",
                   "Couldn't duplicate. Please try again later.",
                   isError: true)
            return false
        }
    }

    func archiveTodo(_ todo: KaiXGuideTodoDTO) async -> Bool {
        guard requireLogin() else { return false }
        do {
            _ = try await KaiXAPIClient.shared.updateGuideTodo(id: todo.id, payload: .init(status: "archived"))
            withAnimation(.easeInOut(duration: 0.2)) {
                todos.removeAll { $0.id == todo.id }
                calendarItems.removeAll { $0.todoId == todo.id }
            }
            notify("Todo 已归档。", "Todo をアーカイブしました。", "Todo archived.")
            return true
        } catch {
            notify("归档失败，请稍后重试。",
                   "アーカイブに失敗しました。しばらくしてからお試しください。",
                   "Couldn't archive. Please try again later.",
                   isError: true)
            return false
        }
    }

    func deleteTodo(_ todo: KaiXGuideTodoDTO) async -> Bool {
        guard requireLogin() else { return false }
        do {
            try await KaiXAPIClient.shared.deleteGuideTodo(id: todo.id)
            withAnimation(.easeInOut(duration: 0.2)) {
                todos.removeAll { $0.id == todo.id }
                calendarItems.removeAll { $0.todoId == todo.id }
            }
            notify("Todo 已删除。", "Todo を削除しました。", "Todo deleted.")
            await loadDashboard()
            return true
        } catch {
            notify("删除失败，请稍后重试。",
                   "削除に失敗しました。しばらくしてからお試しください。",
                   "Couldn't delete. Please try again later.",
                   isError: true)
            return false
        }
    }

    private func patchTodo(_ updated: KaiXGuideTodoDTO) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let idx = todos.firstIndex(where: { $0.id == updated.id }) {
                todos[idx] = updated
            }
            if let idx = calendarItems.firstIndex(where: { $0.todoId == updated.id }) {
                let item = calendarItems[idx]
                calendarItems[idx] = KaiXGuideCalendarItemDTO(
                    id: item.id,
                    todoId: item.todoId,
                    title: updated.title,
                    date: item.date,
                    startAt: item.startAt,
                    endAt: item.endAt,
                    type: item.type,
                    status: updated.status,
                    planId: item.planId,
                    notes: item.notes,
                    recurrence: item.recurrence,
                    reminderAt: item.reminderAt,
                    allDay: item.allDay,
                    todo: updated
                )
            }
        }
    }

    func createCalendarEvent(title: String, date: String, time: String?, allDay: Bool, recurrence: String, notes: String) async -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !date.isEmpty else { return false }
        guard requireLogin(guideOSText(uiLanguage,
                                       "登录后可以保存日程并在 Web 与 iOS 同步。",
                                       "ログインすると予定を保存し、Web と iOS で同期できます。",
                                       "Sign in to save events and sync across web and iOS.")) else { return false }
        isSaving = true
        defer { isSaving = false }
        let startAt = allDay || (time ?? "").isEmpty ? date : "\(date)T\(time!)"
        do {
            _ = try await KaiXAPIClient.shared.createGuideCalendarEvent(.init(
                title: cleanTitle,
                date: date,
                startAt: startAt,
                type: "event",
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                recurrence: recurrence,
                allDay: allDay
            ))
            notify("日程已添加。", "予定を追加しました。", "Event added.")
            await loadCalendar()
            GuideHaptics.success()
            return true
        } catch {
            notify("日程添加失败，请稍后重试。",
                   "予定の追加に失敗しました。しばらくしてからお試しください。",
                   "Couldn't add the event. Please try again later.",
                   isError: true)
            return false
        }
    }

    func updateCalendarEvent(_ event: KaiXGuideCalendarItemDTO, payload: KaiXGuideCalendarEventPayload) async -> Bool {
        guard requireLogin() else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await KaiXAPIClient.shared.updateGuideCalendarEvent(id: event.id, payload: payload)
            if let updated = response.event,
               let index = calendarItems.firstIndex(where: { $0.id == updated.id }) {
                calendarItems[index] = updated
            } else {
                await loadCalendar()
            }
            notify("日程已更新。", "予定を更新しました。", "Event updated.")
            return true
        } catch {
            notify("日程更新失败，请稍后重试。",
                   "予定の更新に失敗しました。しばらくしてからお試しください。",
                   "Couldn't update the event. Please try again later.",
                   isError: true)
            return false
        }
    }

    func deleteCalendarEvent(_ event: KaiXGuideCalendarItemDTO) async -> Bool {
        guard requireLogin() else { return false }
        do {
            try await KaiXAPIClient.shared.deleteGuideCalendarEvent(id: event.id)
            withAnimation(.easeInOut(duration: 0.2)) {
                calendarItems.removeAll { $0.id == event.id }
            }
            notify("日程已删除。", "予定を削除しました。", "Event deleted.")
            return true
        } catch {
            notify("日程删除失败，请稍后重试。",
                   "予定の削除に失敗しました。しばらくしてからお試しください。",
                   "Couldn't delete the event. Please try again later.",
                   isError: true)
            return false
        }
    }

    /// Spec P2 planning depth: move a todo's planned date (今天/明天/+7天/自定义).
    func reschedule(_ todo: KaiXGuideTodoDTO, to date: String) async {
        guard requireLogin() else { return }
        do {
            _ = try await KaiXAPIClient.shared.updateGuideTodo(id: todo.id, payload: .init(plannedDate: date))
            notify("已改期。", "日付を変更しました。", "Rescheduled.")
            await reloadTodos()
            await loadCalendar()
            await loadDashboard()
        } catch {
            notify("改期失败，请稍后重试。",
                   "日付の変更に失敗しました。しばらくしてからお試しください。",
                   "Couldn't reschedule. Please try again later.",
                   isError: true)
        }
    }

    func moveCalendarItem(id: String, to date: String) async {
        guard let item = calendarItems.first(where: { $0.id == id }) else {
            notify("没有找到要改期的事项，请刷新后重试。",
                   "変更対象が見つかりません。更新して再試行してください。",
                   "Couldn't find that item. Refresh and try again.",
                   isError: true)
            return
        }
        if let todo = item.todo {
            await reschedule(todo, to: date)
            return
        }

        let startAt = replacingCalendarDate(item.startAt, with: date)
        let endAt = replacingCalendarDate(item.endAt, with: date)
        _ = await updateCalendarEvent(
            item,
            payload: .init(date: date, startAt: startAt, endAt: endAt)
        )
    }

    private func replacingCalendarDate(_ raw: String?, with date: String) -> String? {
        guard let raw, !raw.isEmpty else { return date }
        if let marker = raw.firstIndex(of: "T") {
            return date + raw[marker...]
        }
        return date
    }

    func createQuickTodo(content: String, plannedDate: String? = nil, planId: String? = nil) async -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard requireLogin(guideOSText(uiLanguage,
                                       "登录后可以保存 Todo、日历和提醒。",
                                       "ログインすると Todo・カレンダー・リマインダーを保存できます。",
                                       "Sign in to save todos, calendar items and reminders.")) else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.createGuideTodo(.init(
                content: text,
                todoType: "manual",
                plannedDate: plannedDate,
                planId: planId
            ))
            notify("Todo 已添加。", "Todo を追加しました。", "Todo added.")
            await reloadTodos()
            await loadCalendar()
            await loadDashboard()
            GuideHaptics.success()
            return true
        } catch {
            notify("添加 Todo 失败，请稍后重试。",
                   "Todo の追加に失敗しました。しばらくしてからお試しください。",
                   "Couldn't add the todo. Please try again later.",
                   isError: true)
            return false
        }
    }

    @Published var studyTodos: [KaiXGuideTodoDTO] = []
    @Published var lifePresets: [KaiXGuideLifePreset] = []

    func loadLifePresets() async {
        guard lifePresets.isEmpty else { return }
        do {
            lifePresets = try await KaiXAPIClient.shared.guideLifePresets(language: currentGuideOSLanguage()).items
        } catch {
            // Presets are a nicety; the editor still works with manual entry.
        }
    }

    /// Spec P0.2: generate recurring JLPT/study habits from target + exam date.
    func generateStudyPlan(level: String, examDate: String, dailyMinutes: Int) async -> Bool {
        guard requireLogin(guideOSText(uiLanguage,
                                       "登录后可以保存日语学习计划和提醒。",
                                       "ログインすると学習計画とリマインダーを保存できます。",
                                       "Sign in to save your study plan and reminders.")) else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let resp = try await KaiXAPIClient.shared.generateStudyPlan(targetLevel: level, examDate: examDate, dailyMinutes: dailyMinutes)
            studyTodos = resp.todos
            notify("已生成 \(resp.todos.count) 个学习任务。",
                   "\(resp.todos.count) 件の学習タスクを生成しました。",
                   "Generated \(resp.todos.count) study tasks.")
            await loadTodos(status: "open")
            return true
        } catch {
            notify("生成失败，请确认考试日期。",
                   "生成に失敗しました。試験日を確認してください。",
                   "Couldn't generate — check the exam date.",
                   isError: true)
            return false
        }
    }

    /// Set a server-side reminder for a todo (APNs is the primary channel).
    func setReminder(todoId: String, reminderAt: String) async -> Bool {
        guard requireLogin(guideOSText(uiLanguage,
                                       "登录后可以设置提醒。",
                                       "ログインするとリマインダーを設定できます。",
                                       "Sign in to set reminders.")) else { return false }
        do {
            _ = try await KaiXAPIClient.shared.setGuideTodoReminder(id: todoId, reminderAt: reminderAt)
            notify("提醒已设置。", "リマインダーを設定しました。", "Reminder set.")
            return true
        } catch {
            notify("提醒设置失败，请稍后重试。",
                   "リマインダーの設定に失敗しました。しばらくしてからお試しください。",
                   "Couldn't set the reminder. Please try again later.",
                   isError: true)
            return false
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

    func loadGoals() async {
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            async let journeysRequest = KaiXAPIClient.shared.guideJourneys(language: currentGuideOSLanguage())
            if isLoggedIn {
                async let plansRequest = KaiXAPIClient.shared.guidePlans()
                let (journeysResponse, plansResponse) = try await (journeysRequest, plansRequest)
                goalJourneys = journeysResponse.journeys
                plans = plansResponse.items
            } else {
                goalJourneys = try await journeysRequest.journeys
                plans = []
            }
        } catch {
            notify("路径加载失败，请检查网络后重试。",
                   "パスの読み込みに失敗しました。接続を確認して再試行してください。",
                   "Couldn't load journeys. Check your connection and try again.",
                   isError: true)
        }
    }

    func createCustomGoal(title: String, targetDate: String?) async -> Bool {
        guard requireLogin(guideOSText(uiLanguage,
                                       "登录后可以创建并同步自定义目标。",
                                       "ログインするとカスタム目標を作成・同期できます。",
                                       "Sign in to create and sync custom goals.")) else { return false }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.createCustomGuidePlan(title: cleanTitle, targetDate: targetDate)
            notify("目标已创建，可以从待办中添加下一步。",
                   "目標を作成しました。Todo から次のステップを追加できます。",
                   "Goal created — add next steps from your todos.")
            await loadGoals()
            return true
        } catch {
            notify("目标创建失败，请稍后重试。",
                   "目標の作成に失敗しました。しばらくしてからお試しください。",
                   "Couldn't create the goal. Please try again later.",
                   isError: true)
            return false
        }
    }

    func createApplication(_ payload: KaiXGuideApplicationPayload) async -> Bool {
        guard requireLogin(guideOSText(uiLanguage,
                                       "登录后可以保存出愿、ES、面试和结果日期。",
                                       "ログインすると出願・ES・面接・結果の日程を保存できます。",
                                       "Sign in to save application, ES, interview and result dates.")) else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.createGuideApplication(payload)
            notify("已加入申请/面试计划。",
                   "出願・面接プランに追加しました。",
                   "Added to your application plan.")
            await loadApplications()
            await loadTodos(status: "open")
            return true
        } catch {
            notify("添加失败，请确认名称和日期。",
                   "追加に失敗しました。名前と日付を確認してください。",
                   "Couldn't add — check the name and dates.",
                   isError: true)
            return false
        }
    }

    func updateApplication(id: String, payload: KaiXGuideApplicationPayload) async -> Bool {
        guard requireLogin() else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.updateGuideApplication(id: id, payload: payload)
            notify("已更新申请信息。", "出願情報を更新しました。", "Application updated.")
            await loadApplications()
            await loadTodos(status: "open")
            return true
        } catch {
            notify("更新失败，请稍后重试。",
                   "更新に失敗しました。しばらくしてからお試しください。",
                   "Couldn't update. Please try again later.",
                   isError: true)
            return false
        }
    }

    func deleteApplication(_ app: KaiXGuideApplicationDTO) async {
        guard requireLogin() else { return }
        do {
            try await KaiXAPIClient.shared.deleteGuideApplication(id: app.id)
            applications.removeAll { $0.id == app.id }
            notify("已删除该申请及其待办。",
                   "この出願と関連 Todo を削除しました。",
                   "Application and its todos deleted.")
            await loadTodos(status: "open")
        } catch {
            notify("删除失败，请稍后重试。",
                   "削除に失敗しました。しばらくしてからお試しください。",
                   "Couldn't delete. Please try again later.",
                   isError: true)
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

    func loadLifePayments(itemId: String) async {
        guard isLoggedIn else { return }
        do {
            lifePayments[itemId] = try await KaiXAPIClient.shared.guideLifePayments(itemId: itemId).items
        } catch {
            notify("支付历史加载失败，请稍后重试。",
                   "支払い履歴の読み込みに失敗しました。しばらくしてからお試しください。",
                   "Couldn't load payment history. Please try again later.",
                   isError: true)
        }
    }

    func recordLifePayment(item: KaiXGuideLifeItemDTO, amount: Int, paidAt: String, method: String, notes: String) async -> Bool {
        guard requireLogin() else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await KaiXAPIClient.shared.createGuideLifePayment(
                itemId: item.id,
                payload: .init(
                    amount: max(0, amount),
                    currency: item.currency.isEmpty ? "JPY" : item.currency,
                    paymentMethod: method,
                    paidAt: paidAt,
                    notes: notes
                )
            )
            if let index = lifeItems.firstIndex(where: { $0.id == item.id }) {
                lifeItems[index] = response.item
            }
            await loadLifePayments(itemId: item.id)
            await loadTodos(type: "life_payment")
            await loadCalendar()
            if let next = response.nextDueAt {
                notify("已记录支付，下一期 \(GuideOSDate.short(next))。",
                       "支払いを記録しました。次回は \(GuideOSDate.short(next)) です。",
                       "Payment logged — next due \(GuideOSDate.short(next)).")
            } else {
                notify("已记录支付。", "支払いを記録しました。", "Payment logged.")
            }
            GuideHaptics.success()
            return true
        } catch {
            notify("支付记录保存失败，请稍后重试。",
                   "支払い記録の保存に失敗しました。しばらくしてからお試しください。",
                   "Couldn't save the payment. Please try again later.",
                   isError: true)
            return false
        }
    }

    func createLifeItem(_ payload: KaiXGuideLifeItemPayload) async -> Bool {
        guard requireLogin(guideOSText(uiLanguage,
                                       "登录后可以保存房租、水电、网络、手机费等生活截止日。",
                                       "ログインすると家賃・水道光熱費・ネット・携帯代などの期日を保存できます。",
                                       "Sign in to save rent, utilities and other bill due dates.")) else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.createGuideLifeItem(payload)
            notify("已加入生活缴费提醒。",
                   "生活費の支払いリマインダーに追加しました。",
                   "Added to your bill reminders.")
            await loadLifeItems()
            await loadTodos(type: "life_payment")
            return true
        } catch {
            notify("添加失败，请确认标题和截止日。",
                   "追加に失敗しました。タイトルと期日を確認してください。",
                   "Couldn't add — check the title and due date.",
                   isError: true)
            return false
        }
    }

    func updateLifeItem(id: String, payload: KaiXGuideLifeItemPayload) async -> Bool {
        guard requireLogin() else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.updateGuideLifeItem(id: id, payload: payload)
            notify("已更新生活事项。", "生活項目を更新しました。", "Item updated.")
            await loadLifeItems()
            await loadTodos(type: "life_payment")
            return true
        } catch {
            notify("更新失败，请稍后重试。",
                   "更新に失敗しました。しばらくしてからお試しください。",
                   "Couldn't update. Please try again later.",
                   isError: true)
            return false
        }
    }

    func deleteLifeItem(_ item: KaiXGuideLifeItemDTO) async {
        guard requireLogin() else { return }
        do {
            try await KaiXAPIClient.shared.deleteGuideLifeItem(id: item.id)
            lifeItems.removeAll { $0.id == item.id }
            notify("已删除该生活事项及其待办。",
                   "この項目と関連 Todo を削除しました。",
                   "Item and its todos deleted.")
            await loadTodos(type: "life_payment")
        } catch {
            notify("删除失败，请稍后重试。",
                   "削除に失敗しました。しばらくしてからお試しください。",
                   "Couldn't delete. Please try again later.",
                   isError: true)
        }
    }

    func loadContracts() async {
        guard isLoggedIn else { contracts = []; return }
        do {
            contracts = try await KaiXAPIClient.shared.guideContracts().items
        } catch {
            notify("合同加载失败，请检查网络后重试。",
                   "契約の読み込みに失敗しました。接続を確認して再試行してください。",
                   "Couldn't load contracts. Check your connection and try again.",
                   isError: true)
        }
    }

    func saveContract(id: String? = nil, payload: KaiXGuideContractPayload) async -> Bool {
        guard requireLogin(guideOSText(uiLanguage,
                                       "登录后可以保存合同到期与解约提醒。",
                                       "ログインすると契約期限・解約リマインダーを保存できます。",
                                       "Sign in to save contract expiry and cancellation reminders.")) else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            if let id {
                _ = try await KaiXAPIClient.shared.updateGuideContract(id: id, payload: payload)
            } else {
                _ = try await KaiXAPIClient.shared.createGuideContract(payload)
            }
            notify("合同提醒已保存。", "契約リマインダーを保存しました。", "Contract reminder saved.")
            await loadContracts()
            await loadTodos(status: "open")
            await loadCalendar()
            GuideHaptics.success()
            return true
        } catch {
            notify("合同保存失败，请稍后重试。",
                   "契約の保存に失敗しました。しばらくしてからお試しください。",
                   "Couldn't save the contract. Please try again later.",
                   isError: true)
            return false
        }
    }

    func deleteContract(_ item: KaiXGuideContractDTO) async {
        guard requireLogin() else { return }
        do {
            try await KaiXAPIClient.shared.deleteGuideContract(id: item.id)
            contracts.removeAll { $0.id == item.id }
            notify("合同和关联提醒已删除。",
                   "契約と関連リマインダーを削除しました。",
                   "Contract and its reminders deleted.")
            await loadTodos(status: "open")
            await loadCalendar()
        } catch {
            notify("合同删除失败，请稍后重试。",
                   "契約の削除に失敗しました。しばらくしてからお試しください。",
                   "Couldn't delete the contract. Please try again later.",
                   isError: true)
        }
    }

    func loadDocuments() async {
        guard isLoggedIn else { documents = []; return }
        do {
            documents = try await KaiXAPIClient.shared.guideDocuments().items
        } catch {
            notify("证件提醒加载失败，请检查网络后重试。",
                   "証明書リマインダーの読み込みに失敗しました。接続を確認して再試行してください。",
                   "Couldn't load document reminders. Check your connection and try again.",
                   isError: true)
        }
    }

    func saveDocument(id: String? = nil, payload: KaiXGuideDocumentPayload) async -> Bool {
        guard requireLogin(guideOSText(uiLanguage,
                                       "登录后可以保存证件到期提醒。",
                                       "ログインすると証明書の期限リマインダーを保存できます。",
                                       "Sign in to save document expiry reminders.")) else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            if let id {
                _ = try await KaiXAPIClient.shared.updateGuideDocument(id: id, payload: payload)
            } else {
                _ = try await KaiXAPIClient.shared.createGuideDocument(payload)
            }
            notify("证件到期提醒已保存。",
                   "証明書の期限リマインダーを保存しました。",
                   "Document expiry reminder saved.")
            await loadDocuments()
            await loadTodos(status: "open")
            await loadCalendar()
            GuideHaptics.success()
            return true
        } catch {
            notify("证件提醒保存失败，请稍后重试。",
                   "証明書リマインダーの保存に失敗しました。しばらくしてからお試しください。",
                   "Couldn't save the reminder. Please try again later.",
                   isError: true)
            return false
        }
    }

    func deleteDocument(_ item: KaiXGuideDocumentDTO) async {
        guard requireLogin() else { return }
        do {
            try await KaiXAPIClient.shared.deleteGuideDocument(id: item.id)
            documents.removeAll { $0.id == item.id }
            notify("证件提醒已删除。",
                   "証明書リマインダーを削除しました。",
                   "Document reminder deleted.")
            await loadTodos(status: "open")
            await loadCalendar()
        } catch {
            notify("证件提醒删除失败，请稍后重试。",
                   "証明書リマインダーの削除に失敗しました。しばらくしてからお試しください。",
                   "Couldn't delete the reminder. Please try again later.",
                   isError: true)
        }
    }
}

// --- Spec §十三 named view-models -----------------------------------------
// Each Guide OS screen owns its own instance via @StateObject; sharing the base
// implementation keeps every screen server-first without code duplication.

/// Drives the Guide OS home dashboard + the consolidated todo list.
@MainActor final class GuideHomeViewModel: GuideOSViewModel {}
/// Drives `GuideGoalsView` (active plans + progress + journey templates).
@MainActor final class GuidePlanViewModel: GuideOSViewModel {}
/// Drives todo-centric planners (applications, life bills) and `GuideTodoListView`.
@MainActor final class GuideTodoViewModel: GuideOSViewModel {}
/// Drives `GuideCalendarView` (today / 7 days / month / overdue).
@MainActor final class GuideCalendarViewModel: GuideOSViewModel {}
/// Drives `GuideProfileSetupView` (identity → personalized plan).
@MainActor final class GuideProfileViewModel: GuideOSViewModel {}
