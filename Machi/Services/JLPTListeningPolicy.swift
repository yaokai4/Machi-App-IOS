import Foundation

enum JLPTListeningContext: Equatable {
    case liveTimedExam
    case nonExam
}

/// Canonical client runtime controls. Timed exam sessions are always strict,
/// including when an older or malformed server omits/contradicts the new DTO.
struct JLPTListeningRuntimePolicy: Equatable {
    enum Mode: String, Equatable {
        case strict
        case practice
    }

    let mode: Mode
    let allowPause: Bool
    let allowSeek: Bool
    let allowReplay: Bool
    let maxPlays: Int
    let showTranscriptDuringAttempt: Bool

    static let strict = JLPTListeningRuntimePolicy(
        mode: .strict,
        allowPause: true,
        allowSeek: false,
        allowReplay: false,
        maxPlays: 1,
        showTranscriptDuringAttempt: false
    )

    static let practice = JLPTListeningRuntimePolicy(
        mode: .practice,
        allowPause: true,
        allowSeek: true,
        allowReplay: true,
        maxPlays: 0,
        showTranscriptDuringAttempt: true
    )

    static func resolve(
        serverPolicy: KaiXJLPTListeningPolicy?,
        context: JLPTListeningContext
    ) -> JLPTListeningRuntimePolicy {
        switch context {
        case .liveTimedExam:
            // The client contract is the permissiveness ceiling for a live
            // exam. A valid strict server policy may tighten pause behavior,
            // while malformed/missing/future payloads can never enable seek,
            // replay, transcripts, or extra plays.
            guard let serverPolicy,
                  serverPolicy.mode.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == Mode.strict.rawValue else {
                return .strict
            }
            return JLPTListeningRuntimePolicy(
                mode: .strict,
                allowPause: Self.strict.allowPause && serverPolicy.allowPause,
                allowSeek: false,
                allowReplay: false,
                maxPlays: Self.strict.maxPlays,
                showTranscriptDuringAttempt: false
            )
        case .nonExam: return .practice
        }
    }
}

/// Copy/action policy for a player failure. A failure before AVPlayer reaches
/// `.playing` is retryable and does not consume a play. Once strict playback
/// has actually started, a later stream failure is truthful about the consumed
/// attempt and cannot expose a replay path.
struct JLPTListeningFailurePresentation: Equatable {
    let didConsumePlay: Bool
    let canRetry: Bool

    static func resolve(
        policy: JLPTListeningRuntimePolicy,
        didConsumePlay: Bool
    ) -> JLPTListeningFailurePresentation {
        JLPTListeningFailurePresentation(
            didConsumePlay: didConsumePlay,
            canRetry: !didConsumePlay || policy.maxPlays <= 0 || policy.allowReplay
        )
    }
}

struct JLPTListeningPlaybackIdentity: Equatable, Hashable {
    let sessionId: String
    let questionId: String

    var credentialKey: String { "\(sessionId):\(questionId)" }

    var isValid: Bool {
        !sessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !questionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Durable successful-start count. Only a confirmed AVPlayer transition to
/// `.playing` writes a credential; loading/waiting/failure never consumes one.
final class JLPTListeningPlaybackCredentialStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "jlpt.listening.successful-starts.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func playsStarted(for identity: JLPTListeningPlaybackIdentity) -> Int {
        guard identity.isValid else { return 0 }
        return max(0, storedCounts()[identity.credentialKey] ?? 0)
    }

    func recordSuccessfulStart(for identity: JLPTListeningPlaybackIdentity) {
        guard identity.isValid else { return }
        var counts = storedCounts()
        counts[identity.credentialKey] = max(0, counts[identity.credentialKey] ?? 0) + 1
        defaults.set(counts, forKey: storageKey)
    }

    private func storedCounts() -> [String: Int] {
        guard let raw = defaults.dictionary(forKey: storageKey) else { return [:] }
        return raw.reduce(into: [:]) { result, pair in
            if let value = pair.value as? Int {
                result[pair.key] = value
            } else if let value = pair.value as? NSNumber {
                result[pair.key] = value.intValue
            }
        }
    }
}

enum JLPTListeningPlaybackDecision: Equatable {
    case startNew
    case resume
    case blocked
}

/// Pure state machine used by AVPlayer and unit tests. A start is first
/// reserved, then consumed only after actual playback is observed.
struct JLPTListeningPlaybackGate: Equatable {
    let policy: JLPTListeningRuntimePolicy
    private(set) var playsStarted: Int
    private(set) var didConsumePlaybackInCurrentLoad = false
    private var pendingStart = false
    private var currentPlaybackStarted = false

    init(policy: JLPTListeningRuntimePolicy, persistedPlaysStarted: Int) {
        self.policy = policy
        playsStarted = max(0, persistedPlaysStarted)
    }

    mutating func requestPlay(
        currentSeconds: Double,
        ended: Bool
    ) -> JLPTListeningPlaybackDecision {
        if currentPlaybackStarted, !ended { return .resume }
        if pendingStart { return .resume }
        if !ended, currentSeconds.isFinite, currentSeconds > 0.05 { return .resume }
        return reserveNewStart()
    }

    mutating func requestReplay() -> JLPTListeningPlaybackDecision {
        guard policy.allowReplay else { return .blocked }
        currentPlaybackStarted = false
        pendingStart = false
        return reserveNewStart()
    }

    /// Returns true exactly once for each newly confirmed playback start.
    mutating func confirmPlaybackStarted() -> Bool {
        guard pendingStart else { return false }
        pendingStart = false
        currentPlaybackStarted = true
        playsStarted += 1
        didConsumePlaybackInCurrentLoad = true
        return true
    }

    mutating func failPendingStart() {
        pendingStart = false
    }

    mutating func markEnded() {
        pendingStart = false
        currentPlaybackStarted = false
    }

    private mutating func reserveNewStart() -> JLPTListeningPlaybackDecision {
        guard policy.maxPlays <= 0 || playsStarted < policy.maxPlays else {
            return .blocked
        }
        pendingStart = true
        return .startNew
    }
}
