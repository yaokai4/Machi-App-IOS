import Foundation
import Testing
@testable import Machi

/// 2026-07-23 交接文档 §5.7 列出的三个产品缺口的回归测试：
/// ① 余额不足只说「不足」不说差额；② 整卷已完成 409 不跳成绩页、用户卡死；
/// ③ 两个 UserDefaults 存储无上限无过期。
@MainActor
struct JLPTExamProductGapTests {

    // MARK: - ① 余额不足要说清还差多少

    private func insufficientError(required: Double?, balance: Double?, shortfall: Double?) -> KaiXAPIError {
        var detail: [String: KXJSONValue] = [:]
        if let required { detail["requiredCoins"] = .number(required) }
        if let balance { detail["balance"] = .number(balance) }
        if let shortfall { detail["shortfallCoins"] = .number(shortfall) }
        return KaiXAPIError(
            error: .init(
                code: "EXAM_INSUFFICIENT_COINS",
                message: "Machi 币不足，充值后即可开考。",
                detail: detail.isEmpty ? nil : detail
            )
        )
    }

    @Test func insufficientCoinsCopySpellsOutTheShortfall() {
        let error = insufficientError(required: 400, balance: 120, shortfall: 280)
        let zh = JLPTExamCopy.insufficientCoins(error: error, language: .zh)
        #expect(zh.contains("400"))
        #expect(zh.contains("120"))
        #expect(zh.contains("280"))
    }

    @Test func insufficientCoinsCopyIsLocalisedInThreeLanguages() {
        let error = insufficientError(required: 350, balance: 50, shortfall: 300)
        for language in [AppLanguage.zh, .ja, .en] {
            let copy = JLPTExamCopy.insufficientCoins(error: error, language: language)
            #expect(copy.contains("350"), "\(language) 应写明所需币数")
            #expect(copy.contains("300"), "\(language) 应写明差额")
        }
    }

    @Test func insufficientCoinsFallsBackWhenServerOmitsTheNumbers() {
        // 旧后端只给顶层字段、不给 detail 时不能崩，也不能编造数字。
        let error = insufficientError(required: nil, balance: nil, shortfall: nil)
        let copy = JLPTExamCopy.insufficientCoins(error: error, language: .zh)
        #expect(copy.contains("余额不足"))
        #expect(!copy.contains("还差"))
    }

    @Test func insufficientCoinsFallsBackWhenBalanceAlreadyCoversTheCost() {
        // 数字自相矛盾（余额够却报不足）时不显示误导性的差额。
        let error = insufficientError(required: 100, balance: 400, shortfall: 0)
        let copy = JLPTExamCopy.insufficientCoins(error: error, language: .zh)
        #expect(!copy.contains("还差"))
    }

    // MARK: - ② 整卷已完成必须跳成绩页

    @Test func completedPaperAttemptRoutesToTheResultPage() {
        let error = KaiXAPIError(
            error: .init(
                code: "paper_attempt_completed",
                message: "本次整卷已经完成。",
                detail: ["paperAttempt": .object([
                    "id": .string("attempt-abc"),
                    "status": .string("completed"),
                ])]
            )
        )
        #expect(
            JLPTExamRecoveryPolicy.action(for: error)
                == .showPaperResult(paperAttemptId: "attempt-abc")
        )
    }

    @Test func completedPaperAttemptStillRoutesWithoutAnAttemptId() {
        let error = KaiXAPIError(
            error: .init(code: "paper_attempt_completed", message: "已完成。", detail: nil)
        )
        #expect(
            JLPTExamRecoveryPolicy.action(for: error) == .showPaperResult(paperAttemptId: nil)
        )
    }

    // MARK: - ③ 存储回收

    private func draft(_ sessionId: String, updatedAt: Date?) -> JLPTExamSessionDraft {
        JLPTExamSessionDraft(
            sessionId: sessionId,
            serverRevision: 1,
            answers: [:],
            pendingAnswers: [],
            updatedAt: updatedAt
        )
    }

    @Test func draftPruningDropsStaleSessions() {
        let now = Date()
        let drafts = [
            "fresh": draft("fresh", updatedAt: now.addingTimeInterval(-60)),
            "stale": draft("stale", updatedAt: now.addingTimeInterval(-30 * 24 * 3600)),
        ]
        let kept = JLPTExamSessionDraftStore.pruned(drafts, keeping: nil, now: now)
        #expect(kept.keys.sorted() == ["fresh"])
    }

    @Test func draftPruningNeverDropsTheSessionBeingWritten() {
        let now = Date()
        let drafts = [
            "live": draft("live", updatedAt: now.addingTimeInterval(-365 * 24 * 3600)),
        ]
        let kept = JLPTExamSessionDraftStore.pruned(drafts, keeping: "live", now: now)
        #expect(kept["live"] != nil, "正在写的会话即便时间戳很旧也不能被回收")
    }

    @Test func draftPruningKeepsLegacyDraftsWithoutATimestamp() {
        // 升级前存下的草稿没有 updatedAt，不能一升级就被清空。
        let drafts = ["legacy": draft("legacy", updatedAt: nil)]
        let kept = JLPTExamSessionDraftStore.pruned(drafts, keeping: nil)
        #expect(kept["legacy"] != nil)
    }

    @Test func draftPruningCapsTheTotalCount() {
        let now = Date()
        var drafts: [String: JLPTExamSessionDraft] = [:]
        for index in 0..<40 {
            drafts["s\(index)"] = draft("s\(index)", updatedAt: now.addingTimeInterval(-Double(index)))
        }
        let kept = JLPTExamSessionDraftStore.pruned(drafts, keeping: "s39", now: now, maximumCount: 10)
        #expect(kept.count == 10)
        #expect(kept["s39"] != nil, "受保护的会话必须留下")
        #expect(kept["s0"] != nil, "最近写入的会话应优先保留")
    }

    @Test func listeningCredentialPruningKeepsRecentSessionsWhole() {
        var counts: [String: Int] = [:]
        for session in 0..<20 {
            for question in 0..<3 {
                counts["sess\(String(format: "%02d", session)):q\(question)"] = 1
            }
        }
        let kept = JLPTListeningPlaybackCredentialStore.pruned(
            counts, keeping: "sess00:q0", maximumSessions: 5
        )
        // 当前会话整场保留，不能只剩半场——否则同场其他题会被判成「没播过」。
        #expect(kept["sess00:q0"] != nil)
        #expect(kept["sess00:q1"] != nil)
        #expect(kept["sess00:q2"] != nil)
        let sessions = Set(kept.keys.map { String($0.split(separator: ":")[0]) })
        #expect(sessions.count <= 6, "保留的会话数应被上限收口（含受保护会话）")
        #expect(kept.count < counts.count, "必须真的回收掉一部分")
    }

    @Test func listeningCredentialPruningIsANoOpBelowTheCap() {
        let counts = ["a:q0": 1, "a:q1": 1, "b:q0": 1]
        let kept = JLPTListeningPlaybackCredentialStore.pruned(
            counts, keeping: "a:q0", maximumSessions: 12
        )
        #expect(kept == counts)
    }
}
