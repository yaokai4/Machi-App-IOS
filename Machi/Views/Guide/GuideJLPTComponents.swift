import SwiftUI

// MARK: - JLPT 备考核心 (iOS-3) — shared building blocks
//
// Reused across the placement / practice / review / vocab / exam surfaces.
// Compliance: all study content is Machi original or licensed import, never
// unauthorized official past-paper text. `JLPTComplianceNote` restates this on
// every screen.

/// N5…N1. Ordered easy→hard so pickers ramp naturally.
enum JLPTLevel: String, CaseIterable, Identifiable, Hashable {
    case n5 = "N5", n4 = "N4", n3 = "N3", n2 = "N2", n1 = "N1"
    var id: String { rawValue }
    var label: String { rawValue }
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

/// Compliance restatement — shown at the foot of every JLPT surface.
struct JLPTComplianceNote: View {
    @Environment(\.appLanguage) private var language
    var text: String?
    var body: some View {
        Text(text ?? guideText(language,
            "Machi 的 JLPT 题库为原创/授权导入内容，不含未授权官方历年真题原文；请以 JLPT 官方最新公告为准。",
            "Machi の JLPT 問題はオリジナル／許諾済みで、無断の公式過去問原文は含みません。最新は JLPT 公式でご確認ください。",
            "Machi's JLPT questions are original / licensed content (no unauthorized official past-paper text). Verify with official JLPT announcements."))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 打卡 streak badge — flame + current streak + a 7-day dot row.
struct JLPTStreakBadge: View {
    @Environment(\.appLanguage) private var language
    let streak: KaiXJLPTStreak

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: (streak.todayDone ?? false) ? "flame.fill" : "flame")
                    .font(.title3)
                    .foregroundStyle((streak.todayDone ?? false) ? Color.orange : KXColor.livingMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streak.currentStreak ?? 0)")
                        .font(.title2.weight(.black))
                        .foregroundStyle(KXColor.livingInk)
                    + Text(guideText(language, " 天连续", " 日連続", " day streak"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KXColor.livingMuted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(guideText(language, "最长 \(streak.longestStreak ?? 0) 天", "最長 \(streak.longestStreak ?? 0) 日", "Best \(streak.longestStreak ?? 0)d"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KXColor.livingMuted)
                    Text(guideText(language, "累计 \(streak.totalDays ?? 0) 天", "累計 \(streak.totalDays ?? 0) 日", "\(streak.totalDays ?? 0) days total"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(streak.last7days ?? []) { day in
                    Circle()
                        .fill(day.done ? KXColor.livingAccent : KXColor.softBackground)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(KXColor.livingAccentSoft, lineWidth: day.done ? 0 : 1))
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(KXColor.livingAccentSoft, lineWidth: 1))
    }
}

/// Hero 倒计时条 — days remaining until the next JLPT sitting.
struct JLPTCountdownBar: View {
    @Environment(\.appLanguage) private var language
    let countdown: KaiXJLPTCountdown

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(KXColor.livingAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(guideText(language, "距 \(countdown.sessionLabel ?? "") 考试", "\(countdown.sessionLabel ?? "") 試験まで", "Until the \(countdown.sessionLabel ?? "") exam"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.livingInk)
                if let date = countdown.examDate, !date.isEmpty {
                    Text(date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text("\(max(0, countdown.daysRemaining ?? 0))")
                .font(.title3.weight(.black))
                .foregroundStyle(KXColor.livingAccent)
            + Text(guideText(language, " 天", " 日", "d"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(KXColor.livingMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A labelled accuracy bar (section breakdown, placement result, stats).
struct JLPTAccuracyBar: View {
    let label: String
    let accuracy: Double   // 0…1
    let total: Int
    let correct: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KXColor.livingInk)
                Spacer(minLength: 0)
                Text(total > 0 ? "\(correct)/\(total) · \(Int((accuracy * 100).rounded()))%" : "—")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(KXColor.softBackground)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geo.size.width * CGFloat(total > 0 ? accuracy : 0)))
                }
            }
            .frame(height: 8)
        }
    }

    private var barColor: Color {
        if total == 0 { return KXColor.softBackground }
        if accuracy >= 0.7 { return KXColor.livingAccent }
        if accuracy >= 0.4 { return .orange }
        return .red
    }
}

/// Level pill selector row (N5…N1). Binds to a JLPTLevel.
struct JLPTLevelPicker: View {
    @Binding var selection: JLPTLevel
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(JLPTLevel.allCases) { lv in
                    let active = lv == selection
                    Button {
                        selection = lv
                    } label: {
                        Text(lv.label)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(active ? .white : KXColor.livingInk)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(active ? KXColor.livingAccent : KXColor.livingSurface, in: Capsule())
                            .overlay(Capsule().stroke(KXColor.livingAccentSoft, lineWidth: active ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
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
                        selection = sec
                    } label: {
                        Text(sec.label(language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(active ? .white : KXColor.livingInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(active ? KXColor.livingAccent : KXColor.livingSurface, in: Capsule())
                            .overlay(Capsule().stroke(KXColor.livingAccentSoft, lineWidth: active ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

/// Big level badge chip (placement result, exam header).
struct JLPTLevelBadge: View {
    let level: String
    var size: CGFloat = 64
    var body: some View {
        Text(level)
            .font(.system(size: size * 0.36, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [KXColor.livingAccent, KXColor.livingAccent.opacity(0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            )
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("\(index + 1) / \(total)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(KXColor.livingMuted)
                if let sl = question.sectionLabel, !sl.isEmpty {
                    Text(sl)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KXColor.livingAccent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(KXColor.livingAccentSoft, in: Capsule())
                }
                Text(question.level)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(KXColor.livingMuted)
                Spacer(minLength: 0)
            }

            if let passage = question.passage, !passage.isEmpty {
                Text(passage)
                    .font(.footnote)
                    .foregroundStyle(KXColor.livingInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text(question.stem)
                .font(.body.weight(.semibold))
                .foregroundStyle(KXColor.livingInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(guideText(language, "解析", "解説", "Explanation"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                    Text(exp)
                        .font(.footnote)
                        .foregroundStyle(KXColor.livingInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if revealed, let onExplain {
                Button(action: onExplain) {
                    HStack(spacing: 6) {
                        if explaining {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(guideText(language, "AI 讲解", "AI 解説", "AI explanation"))
                            .font(.caption.weight(.bold))
                        if !isMember {
                            Image(systemName: "lock.fill").font(.caption2)
                        }
                    }
                    .foregroundStyle(KXColor.livingAccent)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(KXColor.livingSurface, in: Capsule())
                    .overlay(Capsule().stroke(KXColor.livingAccentSoft, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(explaining)
            }

            if revealed, let ai = explanationText, !ai.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label(guideText(language, "Machi AI 讲解", "Machi AI 解説", "Machi AI explanation"),
                          systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                    Text(ai)
                        .font(.footnote)
                        .foregroundStyle(KXColor.livingInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(KXColor.livingSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KXColor.livingAccentSoft, lineWidth: 1))
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
            HStack(alignment: .top, spacing: 10) {
                Text(letter)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(foreground)
                    .frame(width: 26, height: 26)
                    .background(badgeFill, in: Circle())
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(KXColor.livingInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                if state == .correct {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(KXColor.livingAccent)
                } else if state == .wrong {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(rowFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(borderColor, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }

    private var foreground: Color {
        switch state {
        case .selected, .correct: return .white
        case .wrong: return .white
        case .idle: return KXColor.livingMuted
        }
    }
    private var badgeFill: Color {
        switch state {
        case .selected, .correct: return KXColor.livingAccent
        case .wrong: return .red
        case .idle: return KXColor.softBackground
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
        case .wrong: return .red.opacity(0.6)
        case .selected: return KXColor.livingAccent
        case .idle: return KXColor.livingAccentSoft
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
        VStack(spacing: 12) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(KXColor.livingMuted)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KXColor.livingInk)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(KXColor.livingAccent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
