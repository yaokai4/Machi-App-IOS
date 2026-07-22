import Foundation
import Testing
@testable import Machi

@MainActor
struct JLPTExamContractTests {
    @Test func preflightDecodesAuthoritativePriceAndPaperProgress() throws {
        let value = try JSONDecoder().decode(KaiXJLPTExamPreflight.self, from: Data(#"""
        {
          "status": "ok",
          "examId": "n3-paper",
          "paperExamId": "n3-paper",
          "accessDecision": "COIN_PER_ATTEMPT",
          "canStart": true,
          "baseCoinCost": 250,
          "memberCoinCost": 125,
          "requiredCoins": 125,
          "pricingTier": "member",
          "balance": 300,
          "shortfall": 0,
          "unlockSource": "paper_payment",
          "oneTimePaperPayment": true,
          "currentSectionExamId": "n3-listening",
          "resumeSessionId": "session-listening",
          "paperAttempt": {
            "id": "attempt-1",
            "paperExamId": "n3-paper",
            "status": "in_progress",
            "currentSectionIndex": 2,
            "currentSectionExamId": "n3-listening",
            "sectionCount": 3,
            "baseCoinCost": 250,
            "chargedCoinCost": 125,
            "pricingTier": "member",
            "membershipSnapshot": true,
            "unlockSource": "paper_payment",
            "paymentStatus": "paid",
            "walletLedgerEntryId": "ledger-1",
            "startedAt": "2026-07-22T00:00:00Z",
            "completedAt": "",
            "sections": [
              {"examId":"n3-language","sortOrder":0,"status":"completed","sessionId":"s0","startedAt":"","completedAt":""},
              {"examId":"n3-reading","sortOrder":1,"status":"completed","sessionId":"s1","startedAt":"","completedAt":""},
              {"examId":"n3-listening","sortOrder":2,"status":"in_progress","sessionId":"session-listening","startedAt":"","completedAt":""}
            ]
          },
          "priceSnapshotSource": "live_exam",
          "refundPolicyCode": "operator_review",
          "refundPolicyCopy": "Refunds require support review.",
          "confirmationCopyKey": "jlpt.paper.one_time",
          "confirmationCopy": "Charge once for this paper.",
          "listeningPolicy": {
            "mode": "strict",
            "allowPause": true,
            "allowSeek": false,
            "allowReplay": false,
            "maxPlays": 1,
            "showTranscriptDuringAttempt": false
          },
          "serverTime": "2026-07-22T00:01:00Z",
          "disclaimer": "Original practice content."
        }
        """#.utf8))

        #expect(value.requiredCoins == 125)
        #expect(value.balance == 300)
        #expect(value.shortfall == 0)
        #expect(value.oneTimePaperPayment == true)
        #expect(value.paperAttempt?.id == "attempt-1")
        #expect(value.paperAttempt?.currentSectionExamId == "n3-listening")
        #expect(value.paperAttempt?.sections.map(\.examId) == ["n3-language", "n3-reading", "n3-listening"])
        #expect(value.listeningPolicy?.mode == "strict")
        #expect(value.listeningPolicy?.maxPlays == 1)
    }

    @Test func startDecodesResumeRevisionPaymentAndPaperAttempt() throws {
        let value = try JSONDecoder().decode(KaiXJLPTExamStartResponse.self, from: Data(#"""
        {
          "status":"started",
          "sessionId":"session-listening",
          "examId":"n3-listening",
          "level":"N3",
          "title":"Listening",
          "durationSeconds":2400,
          "remainingSeconds":1234,
          "passScore":60,
          "scoreMode":"percent",
          "total":0,
          "questions":[],
          "resumed":true,
          "answers":[{"questionId":"q1","selectedIndex":2,"revision":4}],
          "answerRevision":4,
          "coinCharged":125,
          "coinBalance":175,
          "paymentStatus":"paid",
          "walletLedgerEntryId":"ledger-1",
          "paperAttempt":{
            "id":"attempt-1","paperExamId":"n3-paper","status":"in_progress",
            "currentSectionIndex":2,"currentSectionExamId":"n3-listening","sectionCount":3,
            "baseCoinCost":250,"chargedCoinCost":125,"pricingTier":"member",
            "membershipSnapshot":true,"unlockSource":"paper_payment","paymentStatus":"paid",
            "walletLedgerEntryId":"ledger-1","startedAt":"","completedAt":"","sections":[]
          },
          "disclaimer":"Original practice content."
        }
        """#.utf8))

        #expect(value.answerRevision == 4)
        #expect(value.answers?.first?.revision == 4)
        #expect(value.remainingSeconds == 1234)
        #expect(value.coinCharged == 125)
        #expect(value.paperAttempt?.currentSectionIndex == 2)
    }

    @Test func answerAndSubmitRequestsEncodeAdjacentRevisionContract() throws {
        let answer = KaiXJLPTExamAnswerRequest(
            sessionId: "s1",
            questionId: "q1",
            selectedIndex: 2,
            baseRevision: 3,
            revision: 4
        )
        let answerJSON = try jsonObject(answer)
        #expect(answerJSON["baseRevision"] as? Int == 3)
        #expect(answerJSON["revision"] as? Int == 4)

        let submit = KaiXJLPTExamSubmitRequest(
            sessionId: "s1",
            answersSnapshot: [
                .init(questionId: "q2", selectedIndex: 1),
                .init(questionId: "q1", selectedIndex: 0)
            ],
            baseRevision: 4,
            revision: 5
        )
        let submitJSON = try jsonObject(submit)
        let snapshot = try #require(submitJSON["answersSnapshot"] as? [[String: Any]])
        #expect(snapshot.compactMap { $0["questionId"] as? String } == ["q2", "q1"])
        #expect(submitJSON["baseRevision"] as? Int == 4)
        #expect(submitJSON["revision"] as? Int == 5)
    }

    @Test func answerResponseAndResultRetainRevisionAndAttemptIdentity() throws {
        let answer = try JSONDecoder().decode(KaiXJLPTExamAnswerResponse.self, from: Data(#"""
        {"status":"ok","saved":true,"questionId":"q1","revision":4,"answerRevision":4,"idempotentReplay":true}
        """#.utf8))
        #expect(answer.answerRevision == 4)
        #expect(answer.idempotentReplay == true)

        let result = try JSONDecoder().decode(KaiXJLPTExamResult.self, from: Data(#"""
        {"status":"ok","sessionId":"s1","answerRevision":5,"deadlineExpired":false,"snapshotAccepted":true,"paperAttempt":{"id":"attempt-1","paperExamId":"n3-paper","status":"completed","currentSectionIndex":3,"currentSectionExamId":"","sectionCount":3,"baseCoinCost":250,"chargedCoinCost":125,"pricingTier":"member","membershipSnapshot":true,"unlockSource":"paper_payment","paymentStatus":"paid","walletLedgerEntryId":"ledger-1","startedAt":"","completedAt":"","sections":[]}}
        """#.utf8))
        #expect(result.answerRevision == 5)
        #expect(result.snapshotAccepted == true)
        #expect(result.paperAttempt?.id == "attempt-1")

        let paperResult = try JSONDecoder().decode(KaiXJLPTPaperResult.self, from: Data(#"""
        {"status":"ok","paperId":"n3-paper","paperAttemptId":"attempt-1","paperAttemptStatus":"completed","complete":true}
        """#.utf8))
        #expect(paperResult.paperAttemptId == "attempt-1")
    }

    @Test func structuredAPIErrorPreservesRecoveryDetail() throws {
        let value = try JSONDecoder().decode(KaiXAPIError.self, from: Data(#"""
        {
          "error": {
            "code": "paper_section_out_of_order",
            "message": "Resume the current section.",
            "detail": {
              "currentSectionExamId": "n3-listening",
              "currentSectionIndex": 2,
              "paperAttemptId": "attempt-1"
            }
          }
        }
        """#.utf8))

        #expect(value.error.detail?["currentSectionExamId"] == .string("n3-listening"))
        #expect(value.error.detail?["currentSectionIndex"] == .number(2))
        #expect(value.error.detail?["paperAttemptId"] == .string("attempt-1"))
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
