import Combine
import Foundation
import SwiftData
import UIKit

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
        guard KaiXRuntimeFlags.allowLocalStoreFallback else {
            return makeGuest()
        }
        let targetId = guestID
        let descriptor = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.id == targetId })
        if let existing = try? context.fetch(descriptor).first {
            if existing.displayName.trimmingCharacters(in: .whitespacesAndNewlines) == "访客" {
                existing.displayName = "Machi Guest"
                try? context.save()
            }
            return existing
        }
        let guest = makeGuest()
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

    @MainActor
    private static func makeGuest() -> UserEntity {
        let guest = UserEntity(
            // Distinctive username so it can't clash with a real `@unique`
            // handle that may have synced into the local store.
            id: guestID,
            username: "machi_guest_local",
            displayName: "Machi Guest",
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
        return guest
    }
}

extension UserEntity {
    /// True for the local guest account (logged-out browsing). Used to gate
    /// write actions behind a login prompt without threading a separate flag
    /// through every view.
    var isGuest: Bool { id == GuestSession.guestID }
}

extension GuestSession {
    /// Stable per-device client id for signed-out callers, sent as the
    /// `X-Machi-Guest-Id` header so the server can grant (and enforce) the
    /// tiny guest taster quota for Machi AI without an account. Prefers the
    /// vendor id; falls back to a generated UUID persisted in UserDefaults so
    /// it survives relaunches. Contains nothing user-identifying, and the
    /// server only ever stores a hash of it.
    @MainActor
    static var stableClientId: String {
        if let vendor = UIDevice.current.identifierForVendor?.uuidString, !vendor.isEmpty {
            return vendor
        }
        let key = "machi-guest-stable-client-id"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    /// Unified guest gate for write actions (favorite / publish / inquire /
    /// follow / message / report / RSVP …). Returns `true` when the action may
    /// proceed; for guests it presents the login sheet via `GuestGate` and
    /// returns `false`, so call sites read as a plain guard:
    ///
    ///     guard GuestSession.requireSignedIn(currentUser, reason: …) else { return }
    ///
    /// Pass the current user when the call site has one. Views without a user
    /// in scope (e.g. listing cards) can omit it — the guest holds no backend
    /// token, so a missing token is the same signal.
    @MainActor
    @discardableResult
    static func requireSignedIn(_ user: UserEntity? = nil, reason: String? = nil) -> Bool {
        let isGuest = user.map(\.isGuest) ?? (KaiXBackend.token == nil)
        guard isGuest else { return true }
        GuestGate.shared.requireLogin(reason)
        return false
    }
}

/// 邀请裂变: a small pending-invite store. When a user taps a
/// `https://machicity.com/i/<code>` Universal Link, `ContentView` stashes the
/// code here; the register flow prefills + submits it (`referral_code`), and a
/// user who was already signed in when they tapped can late-`bind` it. Persisted
/// to UserDefaults so it survives the whole sign-up flow and relaunches until
/// consumed. Holds nothing user-identifying — just an opaque invite code.
enum ReferralInvite {
    private static let key = "machi-pending-referral-code"

    /// The last-tapped invite code awaiting registration/bind, if any.
    static var pendingCode: String? {
        let raw = (UserDefaults.standard.string(forKey: key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    /// Record a freshly-tapped invite code. Normalized to the server's charset
    /// (uppercase, alphanumeric); a blank/garbage code is ignored.
    static func remember(_ code: String) {
        let cleaned = String(
            code.trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
        )
        guard !cleaned.isEmpty, cleaned.count <= 16 else { return }
        UserDefaults.standard.set(cleaned, forKey: key)
    }

    /// Clear the pending code once it has been bound (or is no longer wanted).
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
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
