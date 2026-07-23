import AVFoundation
import Combine
import SwiftUI

// MARK: - JLPT 听力音频播放器 ------------------------------------------------

/// AVPlayer 驱动的听力播放器控制器。周期性时间观察驱动进度;换 url 即重建。
@MainActor
final class JLPTAudioPlayerModel: ObservableObject {
    @Published var playing = false
    @Published var current: Double = 0
    @Published var duration: Double = 0
    @Published var failed = false
    @Published var blocked = false
    @Published var failurePresentation: JLPTListeningFailurePresentation?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var policy: JLPTListeningRuntimePolicy = .practice
    private var playbackIdentity: JLPTListeningPlaybackIdentity?
    private var gate = JLPTListeningPlaybackGate(policy: .practice, persistedPlaysStarted: 0)
    private var ended = false
    private let credentialStore = JLPTListeningPlaybackCredentialStore()

    func load(
        _ url: URL,
        policy: JLPTListeningRuntimePolicy,
        playbackIdentity: JLPTListeningPlaybackIdentity?
    ) {
        teardown()
        self.policy = policy
        self.playbackIdentity = playbackIdentity
        current = 0
        duration = 0
        failed = false
        failurePresentation = nil
        ended = false
        blocked = false
        let persisted: Int
        if policy.maxPlays > 0 {
            // A timed exam without a valid session/question identity cannot
            // satisfy relaunch persistence, so playback fails closed.
            guard let playbackIdentity, playbackIdentity.isValid else {
                gate = JLPTListeningPlaybackGate(
                    policy: policy,
                    persistedPlaysStarted: policy.maxPlays
                )
                blocked = true
                return
            }
            persisted = credentialStore.playsStarted(for: playbackIdentity)
        } else {
            persisted = 0
        }
        gate = JLPTListeningPlaybackGate(policy: policy, persistedPlaysStarted: persisted)
        blocked = policy.maxPlays > 0 && persisted >= policy.maxPlays
        // 听力要外放:即便手机静音开关拨到静音也应出声(考试场景)。
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        statusObservation = item.observe(\.status) { [weak self] it, _ in
            let isFailed = it.status == .failed
            let isReady = it.status == .readyToPlay
            let itemDuration = it.duration.seconds
            Task { @MainActor [weak self] in
                if isFailed {
                    guard let self else { return }
                    self.gate.failPendingStart()
                    let presentation = JLPTListeningFailurePresentation.resolve(
                        policy: self.policy,
                        didConsumePlay: self.gate.didConsumePlaybackInCurrentLoad
                    )
                    self.failurePresentation = presentation
                    self.failed = true
                    self.playing = false
                    if !presentation.canRetry {
                        self.blocked = true
                    }
                }
                else if isReady {
                    if itemDuration.isFinite, itemDuration > 0 {
                        self?.duration = itemDuration
                    }
                }
            }
        }
        timeControlObservation = p.observe(\.timeControlStatus) { [weak self] player, _ in
            let timeControlStatus = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch timeControlStatus {
                case .playing:
                    self.playing = true
                    if self.gate.confirmPlaybackStarted(),
                       let identity = self.playbackIdentity,
                       identity.isValid {
                        self.credentialStore.recordSuccessfulStart(for: identity)
                    }
                    self.blocked = false
                case .paused:
                    self.playing = false
                case .waitingToPlayAtSpecifiedRate:
                    self.playing = false
                @unknown default:
                    self.playing = false
                }
            }
        }
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.current = seconds.isFinite ? seconds : 0
                if self.duration == 0, let d = self.player?.currentItem?.duration.seconds,
                   d.isFinite, d > 0 { self.duration = d }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playing = false
                self.ended = true
                self.gate.markEnded()
                if self.policy.allowReplay {
                    self.player?.seek(to: .zero)
                    self.current = 0
                } else if self.policy.maxPlays > 0,
                          self.gate.playsStarted >= self.policy.maxPlays {
                    self.blocked = true
                }
            }
        }
    }

    func toggle() {
        guard let p = player else { return }
        if playing {
            guard policy.allowPause else { return }
            p.pause()
            playing = false
            return
        }
        switch gate.requestPlay(currentSeconds: current, ended: ended) {
        case .blocked:
            blocked = true
        case .resume, .startNew:
            blocked = false
            p.play()
        }
    }

    func replay() {
        guard let p = player else { return }
        switch gate.requestReplay() {
        case .blocked:
            blocked = true
        case .resume, .startNew:
            blocked = false
            ended = false
            p.seek(to: .zero) { [weak p] _ in p?.play() }
        }
    }

    func seek(toFraction f: Double) {
        guard policy.allowSeek, let p = player, duration > 0 else { return }
        let t = CMTime(seconds: max(0, min(1, f)) * duration, preferredTimescale: 600)
        p.seek(to: t)
        current = t.seconds
    }

    /// `isLeavingSession=false` 表示只是视图暂时消失（滚动、切页）。严格考场下
    /// 若这次播放已计次，就保留播放器——否则用户回来时会被判成「已播放过」而
    /// 彻底失去这道付费题的音频。真正离开会话时由调用方传 true 强制释放。
    func teardown(isLeavingSession: Bool = true) {
        guard JLPTListeningTeardownPolicy.shouldReleasePlayer(
            isStrict: policy.mode == .strict,
            didConsumePlayback: gate.didConsumePlaybackInCurrentLoad,
            isLeavingSession: isLeavingSession
        ) else {
            // 保留播放器与凭证状态，只把声音停下，避免离屏后仍在播。
            player?.pause()
            playing = false
            return
        }
        if let o = timeObserver { player?.removeTimeObserver(o); timeObserver = nil }
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
        statusObservation = nil
        timeControlObservation = nil
        gate.failPendingStart()
        player?.pause()
        player = nil
        playing = false
    }

    deinit {
        if let o = timeObserver { player?.removeTimeObserver(o) }
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
    }
}

struct JLPTAudioPlayer: View {
    @Environment(\.appLanguage) private var language
    let url: URL
    var policy: JLPTListeningRuntimePolicy = .practice
    var playbackIdentity: JLPTListeningPlaybackIdentity? = nil
    @StateObject private var model = JLPTAudioPlayerModel()
    @State private var scrubbing = false
    @State private var scrubFraction: Double = 0

    private static func clock(_ s: Double) -> String {
        let v = (s.isFinite && s > 0) ? Int(s) : 0
        return String(format: "%d:%02d", v / 60, v % 60)
    }

    private var fraction: Double {
        if scrubbing { return scrubFraction }
        return model.duration > 0 ? min(1, model.current / model.duration) : 0
    }

    private var taskID: String {
        [
            url.absoluteString,
            policy.mode.rawValue,
            playbackIdentity?.credentialKey ?? "practice"
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "headphones")
                Text(guideText(language, "听力音频", "リスニング音声", "Listening audio"))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(KXColor.livingAccent)

            if model.failed {
                VStack(alignment: .leading, spacing: 8) {
                    Text(failureCopy)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(KXColor.livingMuted)
                    if model.failurePresentation?.canRetry == true {
                        Button(guideText(language, "重试加载", "再読み込み", "Retry loading")) {
                            model.load(url, policy: policy, playbackIdentity: playbackIdentity)
                        }
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                        .accessibilityHint(retryAccessibilityHint)
                    }
                }
            } else {
                HStack(spacing: KXSpacing.md) {
                    Button(action: model.toggle) {
                        Image(systemName: playButtonIcon)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(KXColor.onTint(KXColor.livingAccent))
                            .frame(width: 46, height: 46)
                            .background(KXColor.livingAccent, in: Circle())
                            .shadow(color: KXColor.livingAccent.opacity(0.24), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playButtonAccessibilityLabel)
                    .accessibilityHint(playButtonAccessibilityHint)
                    .disabled((model.blocked && !model.playing) || (model.playing && !policy.allowPause))
                    .opacity((model.blocked && !model.playing) || (model.playing && !policy.allowPause) ? 0.48 : 1)

                    VStack(spacing: 3) {
                        if policy.allowSeek {
                            Slider(
                                value: Binding(
                                    get: { fraction },
                                    set: { scrubFraction = $0 }
                                ),
                                in: 0...1,
                                onEditingChanged: { editing in
                                    scrubbing = editing
                                    if !editing { model.seek(toFraction: scrubFraction) }
                                }
                            )
                            .tint(KXColor.livingAccent)
                        } else {
                            ProgressView(value: fraction)
                                .tint(KXColor.livingAccent)
                                .accessibilityLabel(guideText(language, "播放进度，不可拖动", "再生位置（変更不可）", "Playback progress, seeking unavailable"))
                        }
                        HStack {
                            Text(Self.clock(scrubbing ? scrubFraction * model.duration : model.current))
                            Spacer()
                            Text(Self.clock(model.duration))
                        }
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(KXColor.livingMuted)
                    }

                    if policy.allowReplay {
                        Button(action: model.replay) {
                            Image(systemName: "gobackward")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(KXColor.livingAccent)
                                .frame(width: 38, height: 38)
                                .overlay(Circle().stroke(KXColor.livingAccent.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(guideText(language, "重播", "もう一度", "Replay"))
                    }
                }
                if policy.mode == .strict {
                    Text(model.blocked
                         ? guideText(language, "本题仅可播放一次，已无法重播。", "この問題は1回のみ再生でき、再生し直せません。", "This question allows one play and cannot be replayed.")
                         : strictRulesCopy)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.blocked ? KXColor.livingWarm : KXColor.livingMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(model.blocked
                                            ? guideText(language, "听力播放次数已用完", "聴解の再生回数を使い切りました", "Listening play limit used")
                                            : strictRulesAccessibilityLabel)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KXColor.livingAccentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.livingAccent.opacity(0.25), lineWidth: 0.8))
        .task(id: taskID) {
            model.load(url, policy: policy, playbackIdentity: playbackIdentity)
        }
        // 离屏不等于离开考试：严格考场下已计次的播放要保住，见 teardown 注释。
        .onDisappear { model.teardown(isLeavingSession: false) }
    }

    private var failureCopy: String {
        if model.failurePresentation?.didConsumePlay == true {
            if model.failurePresentation?.canRetry == true {
                return guideText(
                    language,
                    "音频播放中断，本次播放已计入；你可以重新加载。",
                    "音声再生が中断され、この再生は回数に含まれました。再読み込みできます。",
                    "Playback was interrupted and this play was counted. You can reload the audio."
                )
            }
            return guideText(
                language,
                "音频播放中断，本次播放已计入；严格考试中不能重播。",
                "音声再生が中断され、この再生は回数に含まれました。厳格試験では再生し直せません。",
                "Playback was interrupted and this play was counted. Strict exam mode does not allow a replay."
            )
        }
        return guideText(
            language,
            "音频加载失败，尚未计入播放次数。",
            "音声を読み込めませんでした。再生回数には含まれていません。",
            "The audio failed to load and did not consume your play."
        )
    }

    private var playButtonIcon: String {
        if model.playing { return policy.allowPause ? "pause.fill" : "waveform" }
        return "play.fill"
    }

    private var playButtonAccessibilityLabel: String {
        if model.playing {
            return policy.allowPause
                ? guideText(language, "暂停听力音频", "聴解音声を一時停止", "Pause listening audio")
                : guideText(language, "听力音频正在播放，不能暂停", "聴解音声を再生中です。一時停止できません", "Listening audio is playing and cannot be paused")
        }
        return model.blocked
            ? guideText(language, "本题音频已播放，不能重播", "この問題の音声は再生済みで、再生し直せません", "This question's audio has already been played and cannot be replayed")
            : guideText(language, "播放听力音频", "聴解音声を再生", "Play listening audio")
    }

    private var playButtonAccessibilityHint: String {
        if model.blocked {
            return guideText(language, "一次播放限制已用完", "1回の再生制限を使い切りました", "The one-play limit has been used")
        }
        if !policy.allowPause {
            return guideText(language, "播放开始后会连续播放，不能暂停", "再生開始後は連続再生され、一時停止できません", "Playback continues without pause after it starts")
        }
        return guideText(language, "播放后可以暂停并继续", "再生後は一時停止して再開できます", "After playback starts, you may pause and resume")
    }

    private var strictRulesCopy: String {
        policy.allowPause
            ? guideText(language, "仅可播放一次；可以暂停并继续，不能拖动或重播。考试中不显示原文。", "再生は1回のみです。一時停止と再開はできますが、位置変更・再再生はできません。試験中はスクリプトを表示しません。", "One play only. You may pause and resume, but cannot seek or replay. The transcript stays hidden during the exam.")
            : guideText(language, "仅可连续播放一次；不能暂停、拖动或重播。考试中不显示原文。", "連続再生は1回のみです。一時停止・位置変更・再再生はできません。試験中はスクリプトを表示しません。", "One continuous play only. You cannot pause, seek, or replay. The transcript stays hidden during the exam.")
    }

    private var strictRulesAccessibilityLabel: String {
        policy.allowPause
            ? guideText(language, "听力规则：一次播放，可暂停继续，不可拖动重播，考试中隐藏原文", "聴解ルール：1回再生、一時停止と再開は可能、位置変更と再再生は不可、試験中は原文非表示", "Listening rules: one play, pause and resume allowed, no seeking or replay, transcript hidden during exam")
            : guideText(language, "听力规则：一次连续播放，不可暂停、拖动或重播，考试中隐藏原文", "聴解ルール：1回の連続再生、一時停止・位置変更・再再生は不可、試験中は原文非表示", "Listening rules: one continuous play, no pausing, seeking, or replay, transcript hidden during exam")
    }

    private var retryAccessibilityHint: String {
        if model.failurePresentation?.didConsumePlay == true {
            return guideText(
                language,
                "练习模式允许重新加载",
                "練習モードでは再読み込みできます",
                "Practice mode allows the audio to be reloaded"
            )
        }
        return guideText(
            language,
            "失败的加载不会占用播放次数",
            "読み込み失敗では再生回数を消費しません",
            "A failed load does not consume the play limit"
        )
    }
}

// MARK: - JLPT 备考核心 (iOS-3) — shared building blocks
//
// Reused across the placement / practice / review / vocab / exam surfaces.
// Compliance: all study content is Machi original or licensed import, never
// unauthorized official past-paper text. `JLPTComplianceNote` restates this on
// every screen.
//
// 视觉方向「考场里的静气」: 暖纸底 livingSurface + 青墨 livingAccent + 一点暖火
// livingWarm(streak),靠深度/层级/留白/字体而非堆色。共享视觉常量集中在
// JLPTStyle 里,让所有 JLPT 表面共享同一套圆角与描边节奏。

/// Shared visual tokens for the whole JLPT zone so every surface breathes the
/// same rhythm — one hairline weight, one soft shadow, one warm-paper stroke.
enum JLPTStyle {
    /// Hairline that reads as a warm paper edge on the living surface.
    static let hairline = KXColor.livingInk.opacity(0.08)
    static let hairlineStrong = KXColor.livingInk.opacity(0.14)
    /// Accent-tinted rim for accent-soft tiles / selected controls.
    static let accentRim = KXColor.livingAccent.opacity(0.22)
}

/// A warm-paper card surface with a single hairline edge + soft lifted shadow —
/// the base for every JLPT panel. Depth comes from ONE clean edge and ONE soft
/// shadow, never a stack of strokes.
private struct JLPTSurface: ViewModifier {
    var radius: CGFloat = KXRadius.hero
    var elevated: Bool = false
    var stroke: Color = JLPTStyle.hairline
    func body(content: Content) -> some View {
        content
            .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(elevated ? 0.075 : 0.035),
                    radius: elevated ? 14 : 6, y: elevated ? 6 : 2)
    }
}

extension View {
    func jlptSurface(radius: CGFloat = KXRadius.hero, elevated: Bool = false, stroke: Color = JLPTStyle.hairline) -> some View {
        modifier(JLPTSurface(radius: radius, elevated: elevated, stroke: stroke))
    }
}

/// N5…N1. Ordered easy→hard so pickers ramp naturally.
enum JLPTLevel: String, CaseIterable, Identifiable, Hashable {
    case n5 = "N5", n4 = "N4", n3 = "N3", n2 = "N2", n1 = "N1"
    var id: String { rawValue }
    var label: String { rawValue }

    /// 1…5 difficulty rank (N5 = 1 easiest … N1 = 5 hardest). Drives the tier
    /// tint depth and the 5-dot difficulty meter on the level ladder.
    var tier: Int {
        switch self {
        case .n5: return 1
        case .n4: return 2
        case .n3: return 3
        case .n2: return 4
        case .n1: return 5
        }
    }

    /// Short human name for the level (入门 / 初级 / 过渡 / 就职门槛 / 高级).
    func tierName(_ language: AppLanguage) -> String {
        switch self {
        case .n5: return guideText(language, "入门", "入門", "Beginner")
        case .n4: return guideText(language, "初级", "初級", "Elementary")
        case .n3: return guideText(language, "过渡", "中級への橋", "Bridge")
        case .n2: return guideText(language, "就职门槛", "就活の壁", "Work-ready")
        case .n1: return guideText(language, "高级", "上級", "Advanced")
        }
    }

    /// Accent depth for the level badge — N5 lightest, N1 deepest. Subtle so the
    /// ladder reads as a gradient of one hue, not five colours.
    var badgeTint: Color {
        // 0.10 → 0.26 across N5→N1, all on the single brand teal.
        KXColor.livingAccent.opacity(0.09 + Double(tier - 1) * 0.042)
    }

    static func from(_ raw: String?) -> JLPTLevel {
        JLPTLevel(rawValue: raw ?? "N5") ?? .n5
    }
}

/// The four JLPT sections. `all` is a UI-only "mixed" choice (empty section on
/// the wire).
enum JLPTSection: String, CaseIterable, Identifiable, Hashable {
    case all = ""
    case vocab, grammar, reading, listening
    var id: String { rawValue.isEmpty ? "all" : rawValue }
    /// Empty string = server "all sections".
    var wire: String { rawValue }
    func label(_ language: AppLanguage) -> String {
        switch self {
        case .all: return guideText(language, "综合", "総合", "Mixed")
        case .vocab: return guideText(language, "文字词汇", "文字・語彙", "Vocabulary")
        case .grammar: return guideText(language, "语法", "文法", "Grammar")
        case .reading: return guideText(language, "读解", "読解", "Reading")
        case .listening: return guideText(language, "听解", "聴解", "Listening")
        }
    }
}

/// An eyebrow label — small, uppercase, tracked accent text that sits above a
/// big title. The quiet "signature" of the JLPT zone.
struct JLPTEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.heavy))
            .tracking(1.4)
            .foregroundStyle(KXColor.livingAccent)
    }
}

/// Section heading used between blocks on the zone / sub-screens: a short accent
/// tick + bold ink title, so sections read as chapters without a heavy rule.
struct JLPTSectionHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: KXSpacing.sm) {
            RoundedRectangle(cornerRadius: KXRadius.xxs, style: .continuous)
                .fill(KXColor.livingAccent)
                .frame(width: 3, height: 15)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(KXColor.livingInk)
        }
    }
}

/// Compliance restatement — shown at the foot of every JLPT surface.
struct JLPTComplianceNote: View {
    @Environment(\.appLanguage) private var language
    var text: String?
    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.sm) {
            Image(systemName: "checkmark.shield")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(KXColor.livingMuted)
                .padding(.top, 1)
            Text(text ?? guideText(language,
                "Machi 的 JLPT 题库为原创/授权导入内容，不含未授权官方历年真题原文；请以 JLPT 官方最新公告为准。",
                "Machi の JLPT 問題はオリジナル／許諾済みで、無断の公式過去問原文は含みません。最新は JLPT 公式でご確認ください。",
                "Machi's JLPT questions are original / licensed content (no unauthorized official past-paper text). Verify with official JLPT announcements."))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(KXSpacing.md)
        .background(KXColor.livingSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(JLPTStyle.hairline, lineWidth: 0.8))
    }
}

/// 打卡 streak — a warm "暖火" capsule: flame in a low-opacity warm tile,
/// current streak count, today's ✓, and a 7-day dot row (completed = accent
/// fill with a check, today ringed). The one place warm shows in the zone.
struct JLPTStreakBadge: View {
    @Environment(\.appLanguage) private var language
    let streak: KaiXJLPTStreak
    /// Compact = the pill that floats in the hero (count + flame only). Full =
    /// the standalone card with the 7-day row.
    var compact: Bool = false

    private var today: Bool { streak.todayDone ?? false }

    var body: some View {
        if compact {
            compactPill
        } else {
            fullCard
        }
    }

    private var compactPill: some View {
        HStack(spacing: 7) {
            Image(systemName: today ? "flame.fill" : "flame")
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.livingWarm)
            Text("\(streak.currentStreak ?? 0)")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(KXColor.livingInk)
            Text(guideText(language, "天", "日", "d"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(KXColor.livingMuted)
            if today {
                Image(systemName: "checkmark")
                    .kxScaledFont(9, weight: .black)
                    .foregroundStyle(KXColor.livingWarm)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(KXColor.livingWarm.opacity(0.13), in: Capsule())
        .overlay(Capsule().stroke(KXColor.livingWarm.opacity(0.28), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(guideText(language,
            "连续打卡 \(streak.currentStreak ?? 0) 天",
            "\(streak.currentStreak ?? 0) 日連続",
            "\(streak.currentStreak ?? 0) day streak"))
    }

    private var fullCard: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: today ? "flame.fill" : "flame")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(KXColor.livingWarm)
                    .frame(width: 44, height: 44)
                    .background(KXColor.livingWarm.opacity(0.13), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.livingWarm.opacity(0.24), lineWidth: 0.8))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(streak.currentStreak ?? 0)")
                            .font(.title.weight(.black))
                            .foregroundStyle(KXColor.livingInk)
                        Text(guideText(language, "天连续", "日連続", "day streak"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KXColor.livingMuted)
                    }
                    Text(today
                         ? guideText(language, "今天已打卡 ✓", "今日は達成 ✓", "Done today ✓")
                         : guideText(language, "今天还没练，来一组吧", "今日はまだ。1セットどうぞ", "Not yet today — do a set"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(today ? KXColor.livingWarm : KXColor.livingMuted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: KXSpacing.xxs) {
                    Text(guideText(language, "最长 \(streak.longestStreak ?? 0) 天", "最長 \(streak.longestStreak ?? 0) 日", "Best \(streak.longestStreak ?? 0)d"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(KXColor.livingMuted)
                    Text(guideText(language, "累计 \(streak.totalDays ?? 0) 天", "累計 \(streak.totalDays ?? 0) 日", "\(streak.totalDays ?? 0) days"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            JLPTWeekStrip(days: streak.last7days ?? [], todayDone: today)
        }
        .padding(KXSpacing.lg)
        .frame(maxWidth: .infinity)
        .jlptSurface(radius: KXRadius.hero)
    }
}

/// 近7天 week strip — each day is a rounded cell; completed days are accent-
/// filled with a check, the last (today) cell is ringed. Used inside the hero.
struct JLPTWeekStrip: View {
    @Environment(\.appLanguage) private var language
    let days: [KaiXJLPTStreakDay]
    var todayDone: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            let list = Array(days.suffix(7))
            ForEach(Array(list.enumerated()), id: \.element.id) { idx, day in
                let isToday = idx == list.count - 1
                RoundedRectangle(cornerRadius: KXRadius.xs, style: .continuous)
                    .fill(day.done ? KXColor.livingAccent : KXColor.livingSoft)
                    .frame(height: 26)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if day.done {
                            Image(systemName: "checkmark")
                                .kxScaledFont(10, weight: .black)
                                .foregroundStyle(KXColor.livingSurface)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: KXRadius.xs, style: .continuous)
                            .stroke(isToday ? KXColor.livingAccent : JLPTStyle.hairline,
                                    lineWidth: isToday ? 1.5 : 0.8)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(guideText(language, "近 7 天打卡", "直近7日の記録", "Last 7 days"))
    }
}

/// Hero 倒计时条 — days remaining until the next JLPT sitting. Timer tile +
/// big day count + session line.
struct JLPTCountdownBar: View {
    @Environment(\.appLanguage) private var language
    let countdown: KaiXJLPTCountdown

    var body: some View {
        HStack(spacing: KXSpacing.md) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3.weight(.semibold))
                .foregroundStyle(KXColor.onAccent)
                .frame(width: 44, height: 44)
                .background(KXColor.livingAccent, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(guideText(language,
                               "距 \(countdown.sessionLabel ?? "") 考试",
                               "\(countdown.sessionLabel ?? "") 試験まで",
                               "Until the \(countdown.sessionLabel ?? "") exam"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.livingInk)
                if let date = countdown.examDate, !date.isEmpty {
                    Text(date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.xxs) {
                Text("\(max(0, countdown.daysRemaining ?? 0))")
                    .kxScaledFont(30, weight: .black, design: .rounded)
                    .foregroundStyle(KXColor.livingAccent)
                Text(guideText(language, "天", "日", "d"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.livingMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .jlptSurface(radius: KXRadius.hero)
    }
}

/// A labelled accuracy bar (section breakdown, placement result, stats).
struct JLPTAccuracyBar: View {
    let label: String
    let accuracy: Double   // 0…1
    let total: Int
    let correct: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KXColor.livingInk)
                Spacer(minLength: 0)
                Text(total > 0 ? "\(correct)/\(total) · \(Int((accuracy * 100).rounded()))%" : "—")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(total > 0 ? barColor : KXColor.livingMuted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(KXColor.livingSoft)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(total > 0 ? 6 : 0, geo.size.width * CGFloat(total > 0 ? accuracy : 0)))
                }
            }
            .frame(height: 9)
        }
    }

    private var barColor: Color {
        if total == 0 { return KXColor.livingSoft }
        if accuracy >= 0.7 { return KXColor.livingAccent }
        if accuracy >= 0.4 { return KXColor.livingWarm }
        return .red
    }
}

/// Big circular score ring for exam / quiz results — a large number ringed by a
/// progress arc, passing = accent, failing = warm. More premium than a flat
/// number, and reads the pass state at a glance.
struct JLPTScoreRing: View {
    let score: Int
    /// 0…1 fraction of the ring to fill (usually score/100 or correct/total).
    let fraction: Double
    let passed: Bool
    var size: CGFloat = 132

    private var tint: Color { passed ? KXColor.livingAccent : KXColor.livingWarm }

    var body: some View {
        ZStack {
            Circle()
                .stroke(KXColor.livingSoft, lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: size * 0.32, weight: .black, design: .rounded))
                    .foregroundStyle(KXColor.livingInk)
                Image(systemName: passed ? "checkmark.seal.fill" : "arrow.clockwise")
                    .font(.system(size: size * 0.12, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.5), value: fraction)
    }
}

/// Pass / fail pill for result screens.
struct JLPTPassPill: View {
    let passed: Bool
    let title: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(passed ? KXColor.livingAccent : KXColor.livingWarm)
        .padding(.horizontal, KXSpacing.md).padding(.vertical, 6)
        .background((passed ? KXColor.livingAccent : KXColor.livingWarm).opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke((passed ? KXColor.livingAccent : KXColor.livingWarm).opacity(0.28), lineWidth: 0.8))
    }
}

/// Level pill selector row (N5…N1). Binds to a JLPTLevel. Selected = accent
/// fill with a soft lifted shadow; unselected = warm-paper tile.
struct JLPTLevelPicker: View {
    @Binding var selection: JLPTLevel
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KXSpacing.sm) {
                ForEach(JLPTLevel.allCases) { lv in
                    let active = lv == selection
                    Button {
                        withAnimation(KXMotion.select) { selection = lv }
                    } label: {
                        Text(lv.label)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(active ? KXColor.onAccent : KXColor.livingInk)
                            .frame(minWidth: 46)
                            .padding(.horizontal, KXSpacing.lg)
                            .padding(.vertical, 9)
                            .background {
                                if active {
                                    Capsule().fill(KXColor.livingAccent)
                                        .shadow(color: KXColor.livingAccent.opacity(0.28), radius: 7, y: 3)
                                } else {
                                    Capsule().fill(KXColor.livingSurface)
                                }
                            }
                            .overlay(Capsule().stroke(active ? Color.clear : JLPTStyle.hairlineStrong, lineWidth: 0.8))
                    }
                    .buttonStyle(KXPressableStyle(scale: 0.94))
                }
            }
            .padding(.horizontal, KXSpacing.xxs)
            .padding(.vertical, KXSpacing.xxs)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Section pill selector row (综合 / 词汇 / 语法 / 读解 / 听解).
struct JLPTSectionPicker: View {
    @Environment(\.appLanguage) private var language
    @Binding var selection: JLPTSection
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: KXSpacing.sm) {
                ForEach(JLPTSection.allCases) { sec in
                    let active = sec == selection
                    Button {
                        withAnimation(KXMotion.select) { selection = sec }
                    } label: {
                        Text(sec.label(language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(active ? KXColor.onAccent : KXColor.livingInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, KXSpacing.sm)
                            .background {
                                if active {
                                    Capsule().fill(KXColor.livingAccent)
                                        .shadow(color: KXColor.livingAccent.opacity(0.26), radius: 6, y: 2)
                                } else {
                                    Capsule().fill(KXColor.livingSurface)
                                }
                            }
                            .overlay(Capsule().stroke(active ? Color.clear : JLPTStyle.hairlineStrong, lineWidth: 0.8))
                    }
                    .buttonStyle(KXPressableStyle(scale: 0.94))
                }
            }
            .padding(.horizontal, KXSpacing.xxs)
            .padding(.vertical, KXSpacing.xxs)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Big level badge chip (placement result, exam header). Accent gradient tile
/// with a soft inner highlight.
struct JLPTLevelBadge: View {
    let level: String
    var size: CGFloat = 64
    var body: some View {
        Text(level)
            .font(.system(size: size * 0.36, weight: .black, design: .rounded))
            .foregroundStyle(KXColor.onAccent)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [KXColor.livingAccent, KXColor.livingAccent.opacity(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
            )
            .shadow(color: KXColor.livingAccent.opacity(0.24), radius: 8, y: 4)
    }
}

/// Primary filled / secondary ghost action button used across the JLPT
/// surfaces so every CTA shares one shape, one press feel.
struct JLPTPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var trailingArrow: Bool = false
    var loading: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: KXSpacing.sm) {
                if loading {
                    ProgressView().controlSize(.small).tint(KXColor.onAccent)
                } else if let icon {
                    Image(systemName: icon).font(.subheadline.weight(.bold))
                }
                Text(title).font(.subheadline.weight(.bold))
                if trailingArrow {
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").font(.subheadline.weight(.bold))
                }
            }
            .foregroundStyle(enabled ? KXColor.onAccent : KXColor.livingMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .padding(.horizontal, KXSpacing.lg)
            .background(
                enabled ? KXColor.livingAccent : KXColor.livingSoft,
                in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
            )
            .shadow(color: enabled ? KXColor.livingAccent.opacity(0.24) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(KXPressableStyle(scale: 0.97))
        .disabled(!enabled || loading)
    }
}

// MARK: - Interactive question card (practice / review / exam)

/// A single multiple-choice question card. Selecting an option and (optionally)
/// submitting flips it to show the correct answer + explanation. The parent owns
/// grading (server round-trip) and passes `revealed`/`correctIndex` back down.
struct JLPTQuestionCard: View {
    @Environment(\.appLanguage) private var language

    let question: KaiXJLPTQuestionDTO
    let index: Int
    let total: Int
    @Binding var selectedIndex: Int?
    /// When true the card is graded: correct/incorrect coloring + explanation.
    let revealed: Bool
    /// The correct option index once revealed (from the grade result / reveal).
    let correctIndex: Int?
    /// Explanation once revealed.
    let explanation: String?
    /// Member-only "AI 讲解" affordance; nil hides it.
    var onExplain: (() -> Void)? = nil
    var isMember: Bool = false
    var explaining: Bool = false
    var explanationText: String? = nil
    /// Live timed exams pass the canonical strict policy and a durable
    /// session/question identity. Practice, placement, and review keep defaults.
    var listeningPolicy: JLPTListeningRuntimePolicy = .practice
    var playbackIdentity: JLPTListeningPlaybackIdentity? = nil

    /// 听力题:答题时默认不显示脚本(听力就是要「听」);已判分/回看时或手动展开
    /// 后才显示原文，便于对照学习。
    @State private var showScript = false

    private var audioURL: URL? {
        guard let raw = question.audioUrl, !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") {
            return URL(string: raw, relativeTo: KaiXBackend.baseURL)?.absoluteURL
        }
        return URL(string: raw)
    }
    private var scriptVisible: Bool {
        audioURL == nil
            || revealed
            || (listeningPolicy.showTranscriptDuringAttempt && showScript)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.lg) {
            header

            if let url = audioURL {
                JLPTAudioPlayer(
                    url: url,
                    policy: listeningPolicy,
                    playbackIdentity: playbackIdentity
                )
            }

            if let passage = question.passage,
               !passage.isEmpty,
               audioURL != nil,
               !scriptVisible,
               listeningPolicy.showTranscriptDuringAttempt {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showScript = true }
                } label: {
                    Label(guideText(language, "显示听力原文", "スクリプトを表示", "Show transcript"), systemImage: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.livingMuted)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .overlay(Capsule().stroke(KXColor.livingInk.opacity(0.12), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }

            if let passage = question.passage, !passage.isEmpty, scriptVisible {
                Text(passage)
                    .font(.footnote)
                    .foregroundStyle(KXColor.livingInk)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(KXColor.livingSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                            .stroke(JLPTStyle.hairline, lineWidth: 0.8)
                    )
            }

            Text(question.stem)
                .font(.title3.weight(.semibold))
                .foregroundStyle(KXColor.livingInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 9) {
                ForEach(Array(question.choices.enumerated()), id: \.offset) { i, choice in
                    JLPTChoiceRow(
                        text: choice,
                        letter: optionLetter(i),
                        state: rowState(i),
                        onTap: revealed ? nil : { selectedIndex = i }
                    )
                }
            }

            if revealed, let exp = explanation, !exp.isEmpty {
                explanationBlock(title: guideText(language, "解析", "解説", "Explanation"),
                                 body: exp, icon: "text.book.closed.fill", warm: false)
            }

            if revealed, let onExplain {
                Button(action: onExplain) {
                    HStack(spacing: 6) {
                        if explaining {
                            ProgressView().controlSize(.small).tint(KXColor.rankViolet)
                        } else {
                            Image(systemName: "sparkles").font(.caption.weight(.bold))
                        }
                        Text(guideText(language, "AI 讲解", "AI 解説", "AI explanation"))
                            .font(.caption.weight(.bold))
                        if !isMember {
                            Image(systemName: "lock.fill").kxScaledFont(9, weight: .bold)
                        }
                    }
                    .foregroundStyle(KXColor.rankViolet)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(KXColor.rankViolet.opacity(0.10), in: Capsule())
                    .overlay(Capsule().stroke(KXColor.rankViolet.opacity(0.28), lineWidth: 0.8))
                }
                .buttonStyle(KXPressableStyle(scale: 0.96))
                .disabled(explaining)
            }

            if revealed, let ai = explanationText, !ai.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Label(guideText(language, "Machi AI 讲解", "Machi AI 解説", "Machi AI explanation"),
                          systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.rankViolet)
                    Text(ai)
                        .font(.footnote)
                        .foregroundStyle(KXColor.livingInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(KXColor.rankViolet.opacity(0.07), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(KXColor.rankViolet.opacity(0.18), lineWidth: 0.8))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .jlptSurface(radius: KXRadius.sheet)
    }

    private var header: some View {
        HStack(spacing: KXSpacing.sm) {
            Text("\(index + 1)")
                .font(.caption.weight(.black))
                .foregroundStyle(KXColor.livingAccent)
            + Text(" / \(total)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(KXColor.livingMuted)
            if let sl = question.sectionLabel, !sl.isEmpty {
                Text(sl)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(KXColor.livingAccent)
                    .padding(.horizontal, KXSpacing.sm).padding(.vertical, 3)
                    .background(KXColor.livingAccentSoft, in: Capsule())
            }
            Spacer(minLength: 0)
            Text(question.level)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(KXColor.livingMuted)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(KXColor.livingSoft, in: Capsule())
        }
    }

    @ViewBuilder
    private func explanationBlock(title: String, body text: String, icon: String, warm: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(KXColor.livingAccent)
            Text(text)
                .font(.footnote)
                .foregroundStyle(KXColor.livingInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(JLPTStyle.accentRim, lineWidth: 0.8))
    }

    private func optionLetter(_ i: Int) -> String {
        guard i >= 0, i < 26 else { return "\(i + 1)" }
        return String(UnicodeScalar(65 + i)!)
    }

    private func rowState(_ i: Int) -> JLPTChoiceRow.State {
        if !revealed {
            return selectedIndex == i ? .selected : .idle
        }
        if let ci = correctIndex, i == ci { return .correct }
        if selectedIndex == i { return .wrong }
        return .idle
    }
}

struct JLPTChoiceRow: View {
    enum State { case idle, selected, correct, wrong }
    let text: String
    let letter: String
    let state: State
    let onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(alignment: .top, spacing: KXSpacing.md) {
                Text(letter)
                    .font(.caption.weight(.black))
                    .foregroundStyle(badgeForeground)
                    .frame(width: 28, height: 28)
                    .background(badgeFill, in: Circle())
                    .overlay(Circle().stroke(badgeStroke, lineWidth: 1))
                Text(text)
                    .font(.subheadline.weight(state == .idle ? .regular : .semibold))
                    .foregroundStyle(KXColor.livingInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                if state == .correct {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(KXColor.livingAccent)
                } else if state == .wrong {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .padding(13)
            .background(rowFill, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous).stroke(borderColor, lineWidth: borderWidth))
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        }
        .buttonStyle(KXPressableStyle(scale: 0.98, dim: 0.94))
        .disabled(onTap == nil)
        .animation(KXMotion.select, value: state)
    }

    private var badgeForeground: Color {
        switch state {
        case .selected, .correct, .wrong: return KXColor.onAccent
        case .idle: return KXColor.livingMuted
        }
    }
    private var badgeFill: Color {
        switch state {
        case .selected, .correct: return KXColor.livingAccent
        case .wrong: return .red
        case .idle: return KXColor.livingSoft
        }
    }
    private var badgeStroke: Color {
        switch state {
        case .idle: return JLPTStyle.hairline
        default: return .clear
        }
    }
    private var rowFill: Color {
        switch state {
        case .correct: return KXColor.livingAccentSoft
        case .wrong: return Color.red.opacity(0.08)
        case .selected: return KXColor.livingAccentSoft
        case .idle: return KXColor.livingSurface
        }
    }
    private var borderColor: Color {
        switch state {
        case .correct: return KXColor.livingAccent
        case .wrong: return .red.opacity(0.55)
        case .selected: return KXColor.livingAccent
        case .idle: return JLPTStyle.hairlineStrong
        }
    }
    private var borderWidth: CGFloat {
        switch state {
        case .idle: return 0.8
        default: return 1.4
        }
    }
}

// MARK: - Reusable full-height state views (maxHeight infinity — layout安全)

/// Centered state (loading / empty / error) that fills the remaining height so
/// the parent VStack doesn't drift toward center (machi-ios-state-view-fill).
struct JLPTStateView: View {
    var systemImage: String = "sparkles"
    let title: String
    var message: String? = nil
    var isLoading: Bool = false
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(KXColor.livingAccentSoft)
                    .frame(width: 68, height: 68)
                if isLoading {
                    ProgressView().controlSize(.large).tint(KXColor.livingAccent)
                } else {
                    Image(systemName: systemImage)
                        .kxScaledFont(26, weight: .semibold)
                        .foregroundStyle(KXColor.livingAccent)
                }
            }
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(KXColor.livingInk)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.onAccent)
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(KXColor.livingAccent, in: Capsule())
                        .shadow(color: KXColor.livingAccent.opacity(0.24), radius: 8, y: 3)
                }
                .buttonStyle(KXPressableStyle(scale: 0.96))
                .padding(.top, KXSpacing.xxs)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
