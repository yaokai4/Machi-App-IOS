import Foundation
import Combine
import SwiftUI

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
