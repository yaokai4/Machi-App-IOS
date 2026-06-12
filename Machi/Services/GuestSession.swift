import Combine
import Foundation
import SwiftData

/// Guest (logged-out) browsing support.
///
/// App Store Review Guideline 5.1.1(v) expects an app with lots of
/// browsable content (Guide, schools, companies, articles, feed) to let
/// people look around before forcing an account. Machi historically had a
/// hard login wall; guest mode removes it.
///
/// Implementation is deliberately additive and low-risk: a guest is a real
/// local `UserEntity` with a fixed sentinel id, so every existing view that
/// expects a non-optional `currentUser` keeps working unchanged. The guest
/// has no backend token, so all authenticated write APIs are no-ops/401 —
/// and the UI gates the visible write actions (compose, like, follow,
/// comment, message, purchase) behind `GuestGate` instead, prompting login.
enum GuestSession {
    /// Sentinel id for the single local guest account.
    static let guestID = "guest-local"

    /// Fetch the existing guest user or create it. Never throws — on any
    /// failure it returns an in-memory guest so the app can still open.
    @MainActor
    static func ensureGuestUser(context: ModelContext) -> UserEntity {
        let targetId = guestID
        let descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.id == targetId })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let guest = UserEntity(
            // Distinctive username so it can't clash with a real `@unique`
            // handle that may have synced into the local store.
            id: guestID,
            username: "machi_guest_local",
            displayName: "访客",
            role: .member,
            avatarSymbol: "person.fill",
            avatarColorName: "gray"
        )
        guest.syncStatus = .local
        // 游客默认落在东京：首屏立即有本地内容，而不是空白 feed +
        // 「选择城市」。之后游客自选的城市会写回这个实体并在重启后恢复。
        guest.country = "jp"
        guest.province = "tokyo"
        guest.city = "tokyo"
        guest.currentRegionCode = "jp.tokyo.tokyo"
        context.insert(guest)
        do {
            try context.save()
        } catch {
            // Extremely rare (a synced account already holds the username):
            // roll back and reuse whatever exists, else return the in-memory
            // guest so the app still opens to browse.
            context.rollback()
            if let existing = try? context.fetch(descriptor).first { return existing }
        }
        return guest
    }
}

extension UserEntity {
    /// True for the local guest account (logged-out browsing). Used to gate
    /// write actions behind a login prompt without threading a separate flag
    /// through every view.
    var isGuest: Bool { id == GuestSession.guestID }
}

/// Global, app-wide login prompt for guests. Any action handler can call
/// `GuestGate.shared.requireLogin()`; `ContentView` observes it and presents
/// the auth sheet. Kept as a shared singleton so individual views/stores
/// don't need extra plumbing to reach it.
@MainActor
final class GuestGate: ObservableObject {
    static let shared = GuestGate()
    private init() {}

    /// When true, `ContentView` shows the login / register sheet.
    @Published var isPromptingLogin = false

    /// Optional context line shown on the prompt (e.g. "登录后即可发布").
    @Published var reason: String?

    /// Ask the host to present login. Returns immediately; the caller should
    /// also `return` without performing the gated action.
    func requireLogin(_ reason: String? = nil) {
        self.reason = reason
        isPromptingLogin = true
    }

    func dismiss() {
        isPromptingLogin = false
        reason = nil
    }
}
