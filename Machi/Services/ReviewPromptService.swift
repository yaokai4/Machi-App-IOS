import Combine
import StoreKit
import SwiftUI

/// Decides *when* to ask for an App Store rating and coordinates the actual
/// `requestReview` call (which can only run from a SwiftUI view via the
/// environment). The Apple guidance is: prompt only at a genuine moment of
/// delight, never more than a few times a year, and never twice for the same
/// build. So this service:
///
/// - fires at three delight moments — a post that just published *and* earned
///   its first like/comment, a consultation that just got its first reply, and
///   the third cold launch (a returning, engaged user);
/// - hard-caps to **one** prompt per `MARKETING_VERSION` (Apple already
///   rate-limits system-side, but we don't want to burn the yearly budget on a
///   single build);
/// - decouples the *decision* (made anywhere, including non-view code) from the
///   *presentation* (a `@Published` trigger the root view observes and turns
///   into `requestReview()`).
@MainActor
final class ReviewPromptService: ObservableObject {
    static let shared = ReviewPromptService()

    /// Bumped whenever a trigger fires and the gate allows a prompt. The root
    /// view watches this and calls the environment `requestReview` action.
    @Published private(set) var requestToken: Int = 0

    private let defaults = UserDefaults.standard
    private let coldLaunchCountKey = "review.coldLaunchCount"
    /// Stores the MARKETING_VERSION for which a prompt was last shown, so we
    /// prompt at most once per app version.
    private let lastPromptedVersionKey = "review.lastPromptedVersion"
    /// One-shot guard so the first-engagement trigger doesn't re-fire every
    /// launch (the "first like/comment received" milestone is per install).
    private let firstEngagementSeenKey = "review.firstEngagementSeen"
    /// Conversation ids the user opened by sending a listing inquiry — so a
    /// later `message` notification on one of them reads as a *consultation
    /// reply*, distinct from an ordinary DM. Bounded to the most recent handful.
    private let inquiryConversationIdsKey = "review.inquiryConversationIds"

    private init() {}

    /// Remember that the user just started a consultation in this conversation.
    /// Called from the listing inquiry success path. Keeps only the last 20 ids.
    func rememberInquiryConversation(_ conversationId: String) {
        guard !conversationId.isEmpty else { return }
        var ids = defaults.stringArray(forKey: inquiryConversationIdsKey) ?? []
        guard !ids.contains(conversationId) else { return }
        ids.append(conversationId)
        if ids.count > 20 { ids.removeFirst(ids.count - 20) }
        defaults.set(ids, forKey: inquiryConversationIdsKey)
    }

    /// Whether `conversationId` belongs to a consultation the user started —
    /// used to tell a "your inquiry got a reply" message apart from a plain DM.
    func isInquiryConversation(_ conversationId: String?) -> Bool {
        guard let conversationId, !conversationId.isEmpty else { return false }
        return (defaults.stringArray(forKey: inquiryConversationIdsKey) ?? []).contains(conversationId)
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// True only if we have not already prompted on this build.
    private var canPromptThisVersion: Bool {
        defaults.string(forKey: lastPromptedVersionKey) != currentVersion
    }

    /// Record a prompt and raise the presentation trigger. No-op (silently) if
    /// this build already asked — callers can fire freely without checking.
    private func promptIfAllowed() {
        guard canPromptThisVersion else { return }
        defaults.set(currentVersion, forKey: lastPromptedVersionKey)
        requestToken &+= 1
    }

    // MARK: - Triggers

    /// Called once per cold launch (scene first becomes active). Prompts on the
    /// third launch — an established habit, not a first-run stranger.
    func noteColdLaunch() {
        let count = defaults.integer(forKey: coldLaunchCountKey) + 1
        defaults.set(count, forKey: coldLaunchCountKey)
        if count == 3 {
            promptIfAllowed()
        }
    }

    /// A post the user just published has received its first like or comment —
    /// the clearest "people like my thing" moment. Fires at most once per
    /// install, then defers to the version cap.
    func noteFirstPostEngagement() {
        guard !defaults.bool(forKey: firstEngagementSeenKey) else { return }
        defaults.set(true, forKey: firstEngagementSeenKey)
        promptIfAllowed()
    }

    /// A consultation / inquiry the user sent just got its first reply — the
    /// core "the app worked for me" payoff.
    func noteConsultationReply() {
        promptIfAllowed()
    }
}

private struct ReviewPromptModifier: ViewModifier {
    @ObservedObject private var service = ReviewPromptService.shared
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content.onChange(of: service.requestToken) { _, token in
            // token == 0 is the initial value; only act on real increments.
            guard token > 0 else { return }
            requestReview()
        }
    }
}

extension View {
    /// Install at the app root so any `ReviewPromptService` trigger can surface
    /// the system rating sheet. The environment `requestReview` action is only
    /// available inside a view, which is why the trigger indirection exists.
    func kxReviewPrompts() -> some View {
        modifier(ReviewPromptModifier())
    }
}
