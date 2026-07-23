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
        defaults.set(Self.pruned(counts, keeping: identity.credentialKey), forKey: storageKey)
    }

    /// 凭证按 `sessionId:questionId` 逐题累积且从不清理——一场 N3 听力 40 题就是
    /// 40 个 key，长期使用无界增长。这里按会话粒度收口：只保留最近若干场考试的
    /// 凭证，且当前会话永远保留（否则正在考的人会被判成「没播过」而重获次数）。
    static func pruned(
        _ counts: [String: Int],
        keeping protectedKey: String,
        maximumSessions: Int = 12
    ) -> [String: Int] {
        func sessionId(of key: String) -> String {
            String(key.split(separator: ":", maxSplits: 1).first ?? "")
        }
        let protectedSession = sessionId(of: protectedKey)
        // 字典无序，需要一个稳定的淘汰序：按 sessionId 排序后保留末尾若干个。
        // sessionId 是服务端生成的，同一场考试的全部题目一起进退，不会半场被清。
        let sessions = Set(counts.keys.map(sessionId)).sorted()
        guard sessions.count > maximumSessions else { return counts }
        var survivors = Set(sessions.suffix(maximumSessions))
        survivors.insert(protectedSession)
        return counts.filter { survivors.contains(sessionId(of: $0.key)) }
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

/// 严格考场下「视图 onDisappear 时该不该销毁播放器」的判定。
///
/// 听力题在 ScrollView 里，SwiftUI 可能因滚动或切页触发 onDisappear。若此时
/// 无条件 teardown，正在播放的音频会被打断，而播放凭证**已经计入**——回来时
/// 直接 blocked，用户在一场付费考试里彻底失去这道题的音频。
/// 因此严格模式下只要这次播放已计次，就保留播放器，等真正离开会话再释放。
enum JLPTListeningTeardownPolicy {
    static func shouldReleasePlayer(
        isStrict: Bool,
        didConsumePlayback: Bool,
        isLeavingSession: Bool
    ) -> Bool {
        if isLeavingSession { return true }
        if !isStrict { return true }
        return !didConsumePlayback
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
