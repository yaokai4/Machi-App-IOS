import Foundation

/// One logical user confirmation. Transport retries and a price-refresh loop
/// keep the same key so the backend can replay the original paid start safely.
struct JLPTExamStartIntent: Equatable, Identifiable {
    let examId: String
    let preflight: KaiXJLPTExamPreflight
    let idempotencyKey: String

    /// Sheet identity may change when the server refreshes price/section so the
    /// displayed confirmation is rebuilt, while the HTTP idempotency key stays
    /// stable for the same logical user intent.
    var id: String {
        "\(idempotencyKey):\(examId):\(preflight.requiredCoins):\(preflight.serverTime)"
    }
    var confirmedChargeCoins: Int { preflight.requiredCoins }

    init(
        preflight: KaiXJLPTExamPreflight,
        examId: String? = nil,
        idempotencyKey: String = "jlpt-exam-start-\(UUID().uuidString)"
    ) {
        self.examId = examId ?? preflight.examId
        self.preflight = preflight
        self.idempotencyKey = idempotencyKey
    }

    func refreshing(
        with preflight: KaiXJLPTExamPreflight,
        examId: String? = nil
    ) -> JLPTExamStartIntent {
        JLPTExamStartIntent(
            preflight: preflight,
            examId: examId ?? self.examId,
            idempotencyKey: idempotencyKey
        )
    }
}

/// Immutable credentials for the exact logical start that produced a live
/// session. Revision-conflict recovery must replay this receipt; minting a new
/// key or adopting a refreshed price could create or charge a different attempt.
struct JLPTExamStartReceipt: Equatable {
    let examId: String
    let confirmedChargeCoins: Int
    let idempotencyKey: String

    init(examId: String, confirmedChargeCoins: Int, idempotencyKey: String) {
        self.examId = examId
        self.confirmedChargeCoins = confirmedChargeCoins
        self.idempotencyKey = idempotencyKey
    }

    init(intent: JLPTExamStartIntent) {
        self.init(
            examId: intent.examId,
            confirmedChargeCoins: intent.confirmedChargeCoins,
            idempotencyKey: intent.idempotencyKey
        )
    }

    fileprivate var isValid: Bool {
        !examId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && confirmedChargeCoins >= 0
            && !idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Identity gates around revision-conflict recovery. Both the read-only
/// preflight and replayed start response must identify the original live
/// session before any server answers are merged into the current coordinator.
enum JLPTExamResumeIdentityPolicy {
    static func acceptsPreflight(
        receipt: JLPTExamStartReceipt,
        expectedSessionId: String,
        resumeSessionId: String?,
        preflightExamId: String?,
        requiredCoins: Int
    ) -> Bool {
        guard receipt.isValid,
              !expectedSessionId.isEmpty,
              requiredCoins == 0 else { return false }
        return resumeSessionId == expectedSessionId
            && preflightExamId == receipt.examId
    }

    static func acceptsResponse(
        receipt: JLPTExamStartReceipt,
        expectedSessionId: String,
        expectedQuestionIDs: [String],
        responseSessionId: String?,
        responseExamId: String?,
        resumed: Bool?,
        responseQuestionIDs: [String]?
    ) -> Bool {
        guard receipt.isValid,
              !expectedSessionId.isEmpty,
              resumed == true else { return false }
        return responseSessionId == expectedSessionId
            && responseExamId == receipt.examId
            && responseQuestionIDs == expectedQuestionIDs
    }
}

enum JLPTExamRecoveryAction: Equatable {
    case refreshPrice
    case restoreAnswers(currentRevision: Int?)
    case restorePaper(
        currentSectionExamId: String?,
        currentSectionIndex: Int?,
        paperAttemptId: String?
    )
    /// 整卷本次 attempt 已经交完（服务端 409 paper_attempt_completed）。服务端
    /// 在 detail.paperAttempt 里给了完整 attempt，直接带着 attemptId 去成绩页；
    /// 只弹一句「已完成」会让用户卡在 intro/休息页，除了退出别无出路。
    case showPaperResult(paperAttemptId: String?)
    case openWallet
    case openMembership
    case retry
}

enum JLPTExamRecoveryPolicy {
    static func action(for error: KaiXAPIError) -> JLPTExamRecoveryAction {
        let code = error.error.code.lowercased()
        switch code {
        case "exam_price_changed":
            return .refreshPrice
        case "answer_revision_conflict":
            return .restoreAnswers(
                currentRevision: int(error.error.detail?["currentAnswerRevision"])
            )
        case "paper_section_out_of_order":
            return .restorePaper(
                currentSectionExamId: string(error.error.detail?["currentSectionExamId"]),
                currentSectionIndex: int(error.error.detail?["currentSectionIndex"]),
                paperAttemptId: string(error.error.detail?["paperAttemptId"])
            )
        case "paper_attempt_completed":
            // detail.paperAttempt 是一个对象，attemptId 在它里面。
            var attemptId = string(error.error.detail?["paperAttemptId"])
            if attemptId == nil, case .object(let attempt)? = error.error.detail?["paperAttempt"] {
                attemptId = string(attempt["id"]) ?? string(attempt["attemptId"])
            }
            return .showPaperResult(paperAttemptId: attemptId)
        case "exam_insufficient_coins", "insufficient_coins":
            return .openWallet
        case "member_required", "membership_required":
            return .openMembership
        default:
            if code.contains("quota") { return .openMembership }
            return .retry
        }
    }

    private static func string(_ value: KXJSONValue?) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }

    private static func int(_ value: KXJSONValue?) -> Int? {
        guard case .number(let number) = value, number.isFinite else { return nil }
        return Int(number)
    }
}

enum JLPTPaperProgressResolver {
    /// Resolve by the server's section id first. Index is only a compatibility
    /// fallback, never a locally incremented source of truth.
    static func index(
        sectionExamIDs: [String],
        currentSectionExamId: String?,
        currentSectionIndex: Int?
    ) -> Int {
        if let currentSectionExamId,
           !currentSectionExamId.isEmpty,
           let matched = sectionExamIDs.firstIndex(of: currentSectionExamId) {
            return matched
        }
        if let currentSectionIndex, sectionExamIDs.indices.contains(currentSectionIndex) {
            return currentSectionIndex
        }
        return 0
    }
}

enum JLPTExamCopy {
    /// 余额不足文案。服务端把 requiredCoins/balance 同时放在信封顶层与
    /// `error.detail`；能读到就告诉用户**还差多少币**，读不到才退回通用文案。
    /// 只弹「余额不足」而不说差额，用户无法判断该充多少，是付费产品的体验缺口。
    static func insufficientCoins(
        error: KaiXAPIError?,
        language: AppLanguage
    ) -> String {
        let detail = error?.error.detail
        let required = detail.flatMap { intValue($0["requiredCoins"]) }
        let balance = detail.flatMap { intValue($0["balance"]) }
        if let required, let balance, required > balance {
            let shortfall = detail.flatMap { intValue($0["shortfallCoins"]) } ?? (required - balance)
            return guideText(
                language,
                "本次开考需要 \(required) Machi 币，当前余额 \(balance) 币，还差 \(shortfall) 币。充值后即可参加全真模考。",
                "受験には \(required) Machi コインが必要です。現在の残高は \(balance) コインで、あと \(shortfall) コイン不足しています。チャージ後に受験できます。",
                "This attempt costs \(required) Machi Coins. Your balance is \(balance), so you need \(shortfall) more. Top up to take the full mock exam."
            )
        }
        return guideText(
            language,
            "开考需要 Machi 币，余额不足。充值后即可参加全真模考。",
            "受験には Machi コインが必要です。チャージ後に受験できます。",
            "Full mock exams cost Machi Coins. Top up to take one."
        )
    }

    private static func intValue(_ value: KXJSONValue?) -> Int? {
        guard case .number(let number) = value, number.isFinite else { return nil }
        return Int(number)
    }

    static func startConfirmation(
        preflight: KaiXJLPTExamPreflight,
        language: AppLanguage
    ) -> String {
        if preflight.oneTimePaperPayment {
            if preflight.requiredCoins > 0 {
                return guideText(
                    language,
                    "本次完整卷一次扣除 \(preflight.requiredCoins) Machi 币，后续科目不再扣费。",
                    "この模試全体で \(preflight.requiredCoins) Machi コインを一度だけ消費し、後続科目では再課金しません。",
                    "This full paper charges \(preflight.requiredCoins) Machi Coins once; later sections are not charged again."
                )
            }
            return guideText(
                language,
                "本次完整卷已解锁，可以继续当前科目，不会重复扣费。",
                "この模試はすでに利用可能です。現在の科目から再開でき、二重課金されません。",
                "This full paper is already unlocked. Resume the current section without another charge."
            )
        }
        if preflight.requiredCoins > 0 {
            return guideText(
                language,
                "本次开考将扣除 \(preflight.requiredCoins) Machi 币。",
                "開始時に \(preflight.requiredCoins) Machi コインを消費します。",
                "Starting this attempt charges \(preflight.requiredCoins) Machi Coins."
            )
        }
        return guideText(language, "本次考试免费。", "この試験は無料です。", "This attempt is free.")
    }

    static func refundPolicy(language: AppLanguage) -> String {
        guideText(
            language,
            "开考后不自动退款；若因平台故障无法作答，可依据审计记录申请人工冲正。",
            "開始後の自動返金はありません。プラットフォーム障害で受験できない場合は、監査記録に基づき個別対応を申請できます。",
            "Attempts are not automatically refunded after starting. If a platform failure prevents completion, support can review the audit trail for a manual reversal."
        )
    }

    static func paperStructure(sectionCount: Int, language: AppLanguage) -> String {
        guideText(
            language,
            "本卷共 \(sectionCount) 科，每科独立计时；完成全部科目后合并出分。",
            "全 \(sectionCount) 科目で、各科目は個別に計時されます。すべて完了後に総合結果を表示します。",
            "This paper has \(sectionCount) independently timed sections. Results are combined after all sections are complete."
        )
    }

    static func listeningHint(language: AppLanguage) -> String {
        guideText(
            language,
            "本科目包含听力音频，建议提前准备耳机。",
            "この科目には音声問題があります。イヤホンの準備をおすすめします。",
            "This section includes audio. Headphones are recommended."
        )
    }

    static func exitMessage(
        isTimed: Bool,
        pendingAnswerCount: Int,
        language: AppLanguage
    ) -> String {
        let pending = pendingAnswerCount > 0
            ? guideText(
                language,
                "其中 \(pendingAnswerCount) 题仍仅保存在本机，重新进入后会继续同步。",
                "うち \(pendingAnswerCount) 問は端末内だけに保存されており、再入室後に同期を再開します。",
                "\(pendingAnswerCount) answer(s) are still stored only on this device and will retry after you re-enter."
            )
            : guideText(
                language,
                "当前答案已获服务器确认。",
                "現在の回答はサーバーで確認済みです。",
                "Your current answers are confirmed by the server."
            )
        let timer = isTimed
            ? guideText(
                language,
                "计时不会暂停，请在时间用尽前重新进入。",
                "タイマーは止まりません。制限時間内に再入室してください。",
                "The timer will not pause, so re-enter before time runs out."
            )
            : ""
        return [pending, timer].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func submissionNotice(
        deadlineExpired: Bool,
        snapshotAccepted: Bool,
        pendingAnswerCount: Int,
        language: AppLanguage
    ) -> String {
        if deadlineExpired, !snapshotAccepted, pendingAnswerCount > 0 {
            return guideText(
                language,
                "截止时间前有 \(pendingAnswerCount) 题未获服务器确认，可能未计入本次成绩。",
                "締切前に \(pendingAnswerCount) 問がサーバーで確認されず、今回の採点に含まれていない可能性があります。",
                "The server did not confirm \(pendingAnswerCount) answer(s) before the deadline, so they may not be included in this result."
            )
        }
        return ""
    }
}
