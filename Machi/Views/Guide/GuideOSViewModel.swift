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

    /// Parse a server `yyyy-MM-dd` (or ISO) string back into a Date for editors.
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
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
            let fresh = try await KaiXAPIClient.shared.guideActivePlan(language: currentGuideOSLanguage())
            dashboard = fresh
        } catch {
            message = "Guide 计划暂时无法同步。当前页面不会写入本地核心状态，请联网后下拉刷新。"
        }
    }

    func loadTodos(type: String? = nil, status: String = "open", planId: String? = nil, limit: Int = 100) async {
        guard isLoggedIn else { todos = []; return }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            let items = try await KaiXAPIClient.shared.guideTodos(status: status, type: type, planId: planId, limit: limit).items
            todos = items
        } catch {
            message = "任务列表加载失败。Guide 核心状态仅以服务器为准，请联网后重试。"
        }
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
            message = "日历暂时无法同步。Guide 核心状态仅以服务器为准，请联网后重试。"
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
            message = "提醒设置加载失败，请稍后再试。"
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
                message = "个人提醒设置已更新，已同步 \(count) 项 Todo / 日历提醒。"
            } else {
                message = "个人提醒设置已更新。"
            }
        } catch {
            message = "保存失败，请检查网络后重试。"
        }
    }

    func complete(_ todo: KaiXGuideTodoDTO) async {
        guard requireLogin() else { return }
        do {
            _ = try await KaiXAPIClient.shared.completeGuideTodo(id: todo.id)
            GuideHaptics.success()
            withAnimation(.easeInOut(duration: 0.25)) {
                todos.removeAll { $0.id == todo.id }
            }
            await loadDashboard()
        } catch {
            message = "任务完成状态没有保存成功。"
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
            message = "子任务更新失败，请稍后再试。"
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
                message = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "备注已清空。" : "备注已保存。"
            }
        } catch {
            message = "备注保存失败，请稍后再试。"
        }
    }

    func updateTodo(_ todo: KaiXGuideTodoDTO, payload: KaiXGuideTodoUpdatePayload) async -> Bool {
        guard requireLogin() else { return false }
        do {
            let response = try await KaiXAPIClient.shared.updateGuideTodo(id: todo.id, payload: payload)
            if let updated = response.todo {
                patchTodo(updated)
            }
            message = "Todo 已更新。"
            await loadCalendar()
            await loadDashboard()
            return true
        } catch {
            message = "Todo 更新失败，请稍后重试。"
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
            message = "已复制 Todo。"
            await loadTodos(status: "open")
            await loadCalendar()
            return true
        } catch {
            message = "复制失败，请稍后重试。"
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
            message = "Todo 已归档。"
            return true
        } catch {
            message = "归档失败，请稍后重试。"
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
            message = "Todo 已删除。"
            await loadDashboard()
            return true
        } catch {
            message = "删除失败，请稍后重试。"
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
        guard requireLogin("登录后可以保存日程并在 Web 与 iOS 同步。") else { return false }
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
            message = "日程已添加。"
            await loadCalendar()
            GuideHaptics.success()
            return true
        } catch {
            message = "日程添加失败，请稍后重试。"
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
            message = "日程已更新。"
            return true
        } catch {
            message = "日程更新失败，请稍后重试。"
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
            message = "日程已删除。"
            return true
        } catch {
            message = "日程删除失败，请稍后重试。"
            return false
        }
    }

    /// Spec P2 planning depth: move a todo's planned date (今天/明天/+7天/自定义).
    func reschedule(_ todo: KaiXGuideTodoDTO, to date: String) async {
        guard requireLogin() else { return }
        do {
            _ = try await KaiXAPIClient.shared.updateGuideTodo(id: todo.id, payload: .init(plannedDate: date))
            message = "已改期。"
            await loadTodos()
            await loadCalendar()
            await loadDashboard()
        } catch {
            message = "改期失败，请稍后重试。"
        }
    }

    func moveCalendarItem(id: String, to date: String) async {
        guard let item = calendarItems.first(where: { $0.id == id }) else {
            message = "没有找到要改期的事项，请刷新后重试。"
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
        guard requireLogin("登录后可以保存 Todo、日历和提醒。") else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.createGuideTodo(.init(
                content: text,
                todoType: "manual",
                plannedDate: plannedDate,
                planId: planId
            ))
            message = "Todo 已添加。"
            await loadTodos(status: "open")
            await loadCalendar()
            await loadDashboard()
            GuideHaptics.success()
            return true
        } catch {
            message = "添加 Todo 失败，请稍后重试。"
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
        guard requireLogin("登录后可以保存日语学习计划和提醒。") else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let resp = try await KaiXAPIClient.shared.generateStudyPlan(targetLevel: level, examDate: examDate, dailyMinutes: dailyMinutes)
            studyTodos = resp.todos
            message = "已生成 \(resp.todos.count) 个学习任务。"
            await loadTodos(status: "open")
            return true
        } catch {
            message = "生成失败，请确认考试日期。"
            return false
        }
    }

    /// Set a server-side reminder for a todo (APNs is the primary channel).
    func setReminder(todoId: String, reminderAt: String) async -> Bool {
        guard requireLogin("登录后可以设置提醒。") else { return false }
        do {
            _ = try await KaiXAPIClient.shared.setGuideTodoReminder(id: todoId, reminderAt: reminderAt)
            message = "提醒已设置。"
            return true
        } catch {
            message = "提醒设置失败，请稍后重试。"
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
            message = "路径加载失败，请检查网络后重试。"
        }
    }

    func createCustomGoal(title: String, targetDate: String?) async -> Bool {
        guard requireLogin("登录后可以创建并同步自定义目标。") else { return false }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.createCustomGuidePlan(title: cleanTitle, targetDate: targetDate)
            message = "目标已创建，可以从待办中添加下一步。"
            await loadGoals()
            return true
        } catch {
            message = "目标创建失败，请稍后重试。"
            return false
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

    func updateApplication(id: String, payload: KaiXGuideApplicationPayload) async -> Bool {
        guard requireLogin() else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.updateGuideApplication(id: id, payload: payload)
            message = "已更新申请信息。"
            await loadApplications()
            await loadTodos(status: "open")
            return true
        } catch {
            message = "更新失败，请稍后重试。"
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

    func loadLifePayments(itemId: String) async {
        guard isLoggedIn else { return }
        do {
            lifePayments[itemId] = try await KaiXAPIClient.shared.guideLifePayments(itemId: itemId).items
        } catch {
            message = "支付历史加载失败，请稍后重试。"
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
            message = response.nextDueAt.map { "已记录支付，下一期 \((GuideOSDate.short($0)))。" } ?? "已记录支付。"
            GuideHaptics.success()
            return true
        } catch {
            message = "支付记录保存失败，请稍后重试。"
            return false
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

    func updateLifeItem(id: String, payload: KaiXGuideLifeItemPayload) async -> Bool {
        guard requireLogin() else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KaiXAPIClient.shared.updateGuideLifeItem(id: id, payload: payload)
            message = "已更新生活事项。"
            await loadLifeItems()
            await loadTodos(type: "life_payment")
            return true
        } catch {
            message = "更新失败，请稍后重试。"
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

    func loadContracts() async {
        guard isLoggedIn else { contracts = []; return }
        do {
            contracts = try await KaiXAPIClient.shared.guideContracts().items
        } catch {
            message = "合同加载失败，请检查网络后重试。"
        }
    }

    func saveContract(id: String? = nil, payload: KaiXGuideContractPayload) async -> Bool {
        guard requireLogin("登录后可以保存合同到期与解约提醒。") else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            if let id {
                _ = try await KaiXAPIClient.shared.updateGuideContract(id: id, payload: payload)
            } else {
                _ = try await KaiXAPIClient.shared.createGuideContract(payload)
            }
            message = "合同提醒已保存。"
            await loadContracts()
            await loadTodos(status: "open")
            await loadCalendar()
            GuideHaptics.success()
            return true
        } catch {
            message = "合同保存失败，请稍后重试。"
            return false
        }
    }

    func deleteContract(_ item: KaiXGuideContractDTO) async {
        guard requireLogin() else { return }
        do {
            try await KaiXAPIClient.shared.deleteGuideContract(id: item.id)
            contracts.removeAll { $0.id == item.id }
            message = "合同和关联提醒已删除。"
            await loadTodos(status: "open")
            await loadCalendar()
        } catch {
            message = "合同删除失败，请稍后重试。"
        }
    }

    func loadDocuments() async {
        guard isLoggedIn else { documents = []; return }
        do {
            documents = try await KaiXAPIClient.shared.guideDocuments().items
        } catch {
            message = "证件提醒加载失败，请检查网络后重试。"
        }
    }

    func saveDocument(id: String? = nil, payload: KaiXGuideDocumentPayload) async -> Bool {
        guard requireLogin("登录后可以保存证件到期提醒。") else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            if let id {
                _ = try await KaiXAPIClient.shared.updateGuideDocument(id: id, payload: payload)
            } else {
                _ = try await KaiXAPIClient.shared.createGuideDocument(payload)
            }
            message = "证件到期提醒已保存。"
            await loadDocuments()
            await loadTodos(status: "open")
            await loadCalendar()
            GuideHaptics.success()
            return true
        } catch {
            message = "证件提醒保存失败，请稍后重试。"
            return false
        }
    }

    func deleteDocument(_ item: KaiXGuideDocumentDTO) async {
        guard requireLogin() else { return }
        do {
            try await KaiXAPIClient.shared.deleteGuideDocument(id: item.id)
            documents.removeAll { $0.id == item.id }
            message = "证件提醒已删除。"
            await loadTodos(status: "open")
            await loadCalendar()
        } catch {
            message = "证件提醒删除失败，请稍后重试。"
        }
    }
}

// --- Spec §十三 named view-models -----------------------------------------
// Each Guide OS screen owns its own instance via @StateObject; sharing the base
// implementation keeps every screen server-first without code duplication.

/// Drives the Guide OS home dashboard + the consolidated todo list.
@MainActor final class GuideHomeViewModel: GuideOSViewModel {}
/// Drives `GuidePlanView` (active plan + progress + next-step todos).
@MainActor final class GuidePlanViewModel: GuideOSViewModel {}
/// Drives todo-centric planners (applications, life bills) and `GuideTodoListView`.
@MainActor final class GuideTodoViewModel: GuideOSViewModel {}
/// Drives `GuideCalendarView` (today / 7 days / month / overdue).
@MainActor final class GuideCalendarViewModel: GuideOSViewModel {}
/// Drives `GuideProfileSetupView` (identity → personalized plan).
@MainActor final class GuideProfileViewModel: GuideOSViewModel {}
