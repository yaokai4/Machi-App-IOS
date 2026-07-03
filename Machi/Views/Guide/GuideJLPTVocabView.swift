import SwiftUI

/// 我的单词 — vocab deck list → deck detail (word cards, mark mastered) → 考单词
/// online quiz. Member-only decks surface an upgrade prompt (server 403
/// `MEMBER_REQUIRED`). Progress is per-user and server-authoritative.
///
/// Compliance: original / licensed word lists, not official past papers.
struct GuideJLPTVocabView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    var initialLevel: JLPTLevel = .n5

    @State private var level: JLPTLevel = .n5
    @State private var decks: [KaiXJLPTVocabDeck] = []
    @State private var progress: KaiXJLPTVocabProgress?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var upgradeMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JLPTLevelPicker(selection: $level)
                    .onChange(of: level) { _, _ in Task { await load() } }
                content
            }
            .padding(16)
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(guideText(language, "我的单词", "単語", "Vocabulary"))
        .navigationBarTitleDisplayMode(.inline)
        .task { level = initialLevel; await load() }
        .alert(guideText(language, "会员专享", "会員限定", "Members only"),
               isPresented: Binding(get: { upgradeMessage != nil }, set: { if !$0 { upgradeMessage = nil } })) {
            Button(guideText(language, "查看会员", "会員を見る", "See membership")) {
                router.open(.guideMemberResources, in: .guide)
            }
            Button(guideText(language, "以后再说", "あとで", "Later"), role: .cancel) {}
        } message: {
            Text(upgradeMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            JLPTStateView(title: guideText(language, "正在加载词表…", "単語帳を読み込み中…", "Loading decks…"), isLoading: true)
                .frame(minHeight: 320)
        } else if loadFailed {
            JLPTStateView(systemImage: "wifi.slash",
                          title: guideText(language, "加载失败", "読み込みに失敗しました", "Couldn't load"),
                          actionTitle: guideText(language, "重试", "再試行", "Retry"),
                          action: { Task { await load() } })
                .frame(minHeight: 320)
        } else {
            if let p = progress, (p.total ?? 0) > 0 {
                progressCard(p)
            }
            if decks.isEmpty {
                JLPTStateView(systemImage: "character.book.closed",
                              title: guideText(language, "该等级暂无词表", "このレベルの単語帳はまだありません", "No decks for this level"),
                              message: guideText(language, "换个等级看看。", "レベルを変えてみてください。", "Try another level."))
                    .frame(minHeight: 260)
            } else {
                ForEach(decks) { deck in
                    NavigationLink {
                        GuideJLPTDeckDetailView(deckId: deck.id, deckTitle: deck.title ?? "", level: level)
                    } label: {
                        deckRow(deck)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func progressCard(_ p: KaiXJLPTVocabProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(guideText(language, "\(level.rawValue) 掌握进度", "\(level.rawValue) の習得状況", "\(level.rawValue) mastery"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KXColor.livingInk)
                Spacer(minLength: 0)
                Text("\(p.mastered ?? 0)/\(p.total ?? 0)")
                    .font(.subheadline.weight(.black).monospacedDigit())
                    .foregroundStyle(KXColor.livingAccent)
            }
            ProgressView(value: p.progress ?? 0).tint(KXColor.livingAccent)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .jlptSurface(radius: KXRadius.hero)
    }

    private func deckRow(_ deck: KaiXJLPTVocabDeck) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(KXColor.livingAccent)
                .frame(width: 46, height: 46)
                .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(JLPTStyle.accentRim, lineWidth: 0.8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(deck.title ?? "")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(KXColor.livingInk)
                    if deck.isMemberOnly ?? false {
                        Image(systemName: "crown.fill").font(.caption2).foregroundStyle(KXColor.livingWarm)
                    }
                }
                Text(guideText(language, "\(deck.wordCount ?? 0) 词", "\(deck.wordCount ?? 0) 語", "\(deck.wordCount ?? 0) words"))
                    .font(.caption.weight(.medium)).foregroundStyle(KXColor.livingMuted)
                if let d = deck.description, !d.isEmpty {
                    Text(d).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(KXColor.livingMuted)
                .frame(width: 24, height: 24)
                .background(KXColor.livingSoft, in: Circle())
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .jlptSurface(radius: KXRadius.hero)
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            async let decksResp = KaiXAPIClient.shared.jlptVocabDecks(level: level.rawValue)
            async let progResp = try? KaiXAPIClient.shared.jlptVocabProgress(level: level.rawValue)
            decks = try await decksResp.decks ?? []
            progress = await progResp
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

/// Deck detail — word cards with tap-to-flip (Japanese → reading + meaning) and a
/// "mark mastered" toggle. A "考单词" button launches the vocab quiz.
struct GuideJLPTDeckDetailView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter

    let deckId: String
    let deckTitle: String
    let level: JLPTLevel

    @State private var words: [KaiXJLPTVocabWord] = []
    @State private var mastered: Set<String> = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var memberRequired = false

    var body: some View {
        ScrollView {
            if isLoading {
                JLPTStateView(title: guideText(language, "正在加载单词…", "単語を読み込み中…", "Loading words…"), isLoading: true)
            } else if memberRequired {
                JLPTStateView(systemImage: "crown.fill",
                              title: guideText(language, "该词表为会员专属", "この単語帳は会員限定です", "This deck is members-only"),
                              message: guideText(language, "开通会员解锁全部单词与「考单词」测验。", "会員登録で全単語と「単語テスト」が解放されます。", "Membership unlocks all words and the vocab quiz."),
                              actionTitle: guideText(language, "查看会员", "会員を見る", "See membership"),
                              action: { router.open(.guideMemberResources, in: .guide) })
            } else if loadFailed {
                JLPTStateView(systemImage: "wifi.slash",
                              title: guideText(language, "加载失败", "読み込みに失敗しました", "Couldn't load"),
                              actionTitle: guideText(language, "重试", "再試行", "Retry"),
                              action: { Task { await load() } })
            } else if words.isEmpty {
                JLPTStateView(systemImage: "tray", title: guideText(language, "暂无单词", "単語がありません", "No words yet"))
            } else {
                content
            }
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(deckTitle.isEmpty ? guideText(language, "词表", "単語帳", "Deck") : deckTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                GuideJLPTVocabQuizView(level: level, deckId: deckId, deckTitle: deckTitle)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.subheadline.weight(.bold))
                    Text(guideText(language, "考单词（测验）", "単語テスト", "Vocab quiz"))
                        .font(.subheadline.weight(.bold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").font(.subheadline.weight(.bold))
                }
                .foregroundStyle(KXColor.onAccent)
                .padding(15)
                .frame(maxWidth: .infinity)
                .background(KXColor.livingAccent, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                .shadow(color: KXColor.livingAccent.opacity(0.24), radius: 9, y: 3)
            }
            .buttonStyle(KXPressableStyle(scale: 0.98))

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.livingAccent)
                Text(guideText(language, "已掌握 \(mastered.count)/\(words.count)", "習得 \(mastered.count)/\(words.count)", "Mastered \(mastered.count)/\(words.count)"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.livingMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)

            ForEach(words) { word in
                GuideJLPTWordCard(
                    word: word,
                    mastered: mastered.contains(word.id),
                    onToggle: { Task { await toggle(word) } }
                )
            }

            JLPTComplianceNote()
        }
        .padding(16)
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        memberRequired = false
        do {
            let resp = try await KaiXAPIClient.shared.jlptVocabDeck(deckId: deckId)
            words = resp.words ?? []
            mastered = Set((resp.words ?? []).filter { $0.mastered ?? false }.map { $0.id })
        } catch let err as KaiXAPIError where err.error.code == "MEMBER_REQUIRED" {
            memberRequired = true
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func toggle(_ word: KaiXJLPTVocabWord) async {
        let willMaster = !mastered.contains(word.id)
        if willMaster { mastered.insert(word.id) } else { mastered.remove(word.id) }
        _ = try? await KaiXAPIClient.shared.jlptVocabMark(
            wordId: word.id, state: willMaster ? "mastered" : "learning")
    }
}

/// A flippable word card. Front = Japanese word; tap reveals reading + meaning.
struct GuideJLPTWordCard: View {
    @Environment(\.appLanguage) private var language
    let word: KaiXJLPTVocabWord
    let mastered: Bool
    let onToggle: () -> Void

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // 日文大字 — the star of the card.
                Text(word.word)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(KXColor.livingInk)
                if revealed, let reading = word.reading, !reading.isEmpty {
                    Text(reading)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KXColor.livingAccent)
                }
                if let pos = word.pos, !pos.isEmpty, revealed {
                    Text(pos).font(.caption2.weight(.semibold)).foregroundStyle(KXColor.livingMuted)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(KXColor.livingSoft, in: Capsule())
                }
                Spacer(minLength: 0)
                Button(action: onToggle) {
                    Image(systemName: mastered ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(mastered ? KXColor.livingAccent : KXColor.livingMuted)
                }
                .buttonStyle(KXPressableStyle(scale: 0.9))
                .sensoryFeedback(.selection, trigger: mastered)
            }
            if revealed {
                if let mz = word.meaningZh, !mz.isEmpty {
                    Text(mz)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(KXColor.livingInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let ex = word.example, !ex.isEmpty {
                    Text(ex)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            } else {
                Label(guideText(language, "点按查看释义", "タップして意味を見る", "Tap to reveal"),
                      systemImage: "hand.tap")
                    .font(.caption.weight(.medium)).foregroundStyle(KXColor.livingMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (mastered ? KXColor.livingAccentSoft : KXColor.livingSurface),
            in: RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous)
            .stroke(mastered ? JLPTStyle.accentRim : JLPTStyle.hairline, lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.035), radius: 6, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: KXRadius.hero, style: .continuous))
        .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { revealed.toggle() } }
    }
}

/// 考单词 — an on-the-fly multiple-choice vocab quiz. Answers are collected then
/// submitted together; the result shows score + per-question correctness.
struct GuideJLPTVocabQuizView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    let level: JLPTLevel
    var deckId: String? = nil
    var deckTitle: String = ""

    @State private var sessionId: String?
    @State private var questions: [KaiXJLPTVocabQuizQuestion] = []
    @State private var cursor = 0
    @State private var answers: [Int] = []
    @State private var selected: Int?
    @State private var result: KaiXJLPTVocabQuizSubmitResponse?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var notEnough = false
    @State private var submitting = false

    var body: some View {
        ScrollView {
            if isLoading {
                JLPTStateView(title: guideText(language, "正在出题…", "問題を作成中…", "Building quiz…"), isLoading: true)
            } else if notEnough {
                JLPTStateView(systemImage: "tray",
                              title: guideText(language, "词汇不足，暂时无法生成测验", "単語が足りず、テストを作成できません", "Not enough words to build a quiz"),
                              message: guideText(language, "词表补充后再来。", "単語が増えたら再度お試しください。", "Come back once the deck is filled."))
            } else if loadFailed {
                JLPTStateView(systemImage: "wifi.slash",
                              title: guideText(language, "加载失败", "読み込みに失敗しました", "Couldn't load"),
                              actionTitle: guideText(language, "重试", "再試行", "Retry"),
                              action: { Task { await start() } })
            } else if let r = result {
                resultView(r)
            } else {
                quizView
            }
        }
        .background(KXColor.livingBackground.ignoresSafeArea())
        .navigationTitle(guideText(language, "考单词", "単語テスト", "Vocab quiz"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await start() }
    }

    @ViewBuilder
    private var quizView: some View {
        if cursor < questions.count {
            let q = questions[cursor]
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    ProgressView(value: Double(cursor), total: Double(max(1, questions.count)))
                        .tint(KXColor.livingAccent)
                    Text("\(cursor + 1)/\(questions.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(KXColor.livingMuted)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(guideText(language, "选择正确释义", "正しい意味を選択", "Pick the meaning"))
                        .font(.caption2.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(KXColor.livingMuted)
                    // 日文大字题干.
                    Text(q.stem)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(KXColor.livingInk)
                    if let reading = q.reading, !reading.isEmpty {
                        Text(reading)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KXColor.livingAccent)
                    }
                    VStack(spacing: 9) {
                        ForEach(Array(q.choices.enumerated()), id: \.offset) { i, choice in
                            JLPTChoiceRow(
                                text: choice,
                                letter: String(UnicodeScalar(65 + i)!),
                                state: selected == i ? .selected : .idle,
                                onTap: { selected = i }
                            )
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .jlptSurface(radius: KXRadius.sheet)

                JLPTPrimaryButton(
                    title: cursor + 1 < questions.count
                        ? guideText(language, "下一题", "次へ", "Next")
                        : guideText(language, "交卷", "提出", "Submit"),
                    icon: cursor + 1 < questions.count ? nil : "checkmark.circle.fill",
                    trailingArrow: cursor + 1 < questions.count,
                    loading: submitting,
                    enabled: selected != nil,
                    action: next)

                JLPTComplianceNote()
            }
            .padding(16)
        }
    }

    private func resultView(_ r: KaiXJLPTVocabQuizSubmitResponse) -> some View {
        let total = max(1, r.total ?? 1)
        let frac = Double(r.correct ?? 0) / Double(total)
        return VStack(spacing: 18) {
            JLPTEyebrow(text: guideText(language, "单词测验结果", "単語テスト結果", "Quiz result"))
            JLPTScoreRing(score: r.score ?? 0, fraction: frac, passed: r.passed ?? false, size: 140)
            Text(guideText(language, "答对 \(r.correct ?? 0)/\(r.total ?? 0) 题", "正解 \(r.correct ?? 0)/\(r.total ?? 0)", "\(r.correct ?? 0)/\(r.total ?? 0) correct"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(KXColor.livingMuted)
            JLPTPassPill(passed: r.passed ?? false,
                         title: (r.passed ?? false)
                            ? guideText(language, "通过", "合格", "Passed")
                            : guideText(language, "再接再厉", "もう一歩", "Keep going"))
            Button(action: { Task { await start() } }) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.clockwise").font(.subheadline.weight(.bold))
                    Text(guideText(language, "再考一次", "もう一度", "Try again"))
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(KXColor.onAccent)
                .padding(.horizontal, 24).padding(.vertical, 13)
                .background(KXColor.livingAccent, in: Capsule())
                .shadow(color: KXColor.livingAccent.opacity(0.24), radius: 8, y: 3)
            }
            .buttonStyle(KXPressableStyle(scale: 0.96))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func start() async {
        isLoading = true
        loadFailed = false
        notEnough = false
        result = nil
        cursor = 0
        answers = []
        selected = nil
        do {
            let resp = try await KaiXAPIClient.shared.jlptVocabQuizStart(level: level.rawValue, deckId: deckId)
            sessionId = resp.sessionId
            questions = resp.questions ?? []
            if questions.isEmpty { notEnough = true }
        } catch let err as KaiXAPIError where err.error.code == "not_enough_words" {
            notEnough = true
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func next() {
        guard let sel = selected else { return }
        answers.append(sel)
        selected = nil
        if cursor + 1 < questions.count {
            cursor += 1
        } else {
            Task { await submit() }
        }
    }

    private func submit() async {
        guard let sid = sessionId, !submitting else { return }
        submitting = true
        defer { submitting = false }
        do {
            result = try await KaiXAPIClient.shared.jlptVocabQuizSubmit(sessionId: sid, answers: answers)
        } catch {
            loadFailed = true
        }
    }
}
