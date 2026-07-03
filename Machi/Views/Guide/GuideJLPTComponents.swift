import SwiftUI

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
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
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
        HStack(alignment: .top, spacing: 8) {
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
        .padding(12)
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
                    .font(.system(size: 9, weight: .black))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: today ? "flame.fill" : "flame")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(KXColor.livingWarm)
                    .frame(width: 44, height: 44)
                    .background(KXColor.livingWarm.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(KXColor.livingWarm.opacity(0.24), lineWidth: 0.8))
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
                VStack(alignment: .trailing, spacing: 2) {
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
        .padding(16)
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
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(day.done ? KXColor.livingAccent : KXColor.livingSoft)
                    .frame(height: 26)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if day.done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(KXColor.livingSurface)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
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
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3.weight(.semibold))
                .foregroundStyle(KXColor.onAccent)
                .frame(width: 44, height: 44)
                .background(KXColor.livingAccent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
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
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(max(0, countdown.daysRemaining ?? 0))")
                    .font(.system(size: 30, weight: .black, design: .rounded))
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
        .padding(.horizontal, 12).padding(.vertical, 6)
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
            HStack(spacing: 8) {
                ForEach(JLPTLevel.allCases) { lv in
                    let active = lv == selection
                    Button {
                        withAnimation(KXMotion.select) { selection = lv }
                    } label: {
                        Text(lv.label)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(active ? KXColor.onAccent : KXColor.livingInk)
                            .frame(minWidth: 46)
                            .padding(.horizontal, 16)
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
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
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
            HStack(spacing: 8) {
                ForEach(JLPTSection.allCases) { sec in
                    let active = sec == selection
                    Button {
                        withAnimation(KXMotion.select) { selection = sec }
                    } label: {
                        Text(sec.label(language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(active ? KXColor.onAccent : KXColor.livingInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
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
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
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
            HStack(spacing: 8) {
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
            .padding(.horizontal, 16)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let passage = question.passage, !passage.isEmpty {
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
                            Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
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
        HStack(spacing: 8) {
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
                    .padding(.horizontal, 8).padding(.vertical, 3)
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
            HStack(alignment: .top, spacing: 12) {
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
                        .font(.system(size: 26, weight: .semibold))
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
                .padding(.top, 2)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
