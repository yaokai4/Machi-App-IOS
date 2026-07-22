import Foundation
import Testing
@testable import Machi

@MainActor
struct JLPTExamPolicyTests {
    @Test func refreshedPriceKeepsTheLogicalStartIntentIdempotencyKey() throws {
        let original = JLPTExamStartIntent(
            preflight: try preflight(requiredCoins: 100),
            idempotencyKey: "jlpt-start-stable-key"
        )

        let refreshed = original.refreshing(with: try preflight(requiredCoins: 50))

        #expect(refreshed.idempotencyKey == "jlpt-start-stable-key")
        #expect(refreshed.preflight.requiredCoins == 50)
        #expect(refreshed.confirmedChargeCoins == 50)
    }

    @Test func structuredErrorsResolveToActionableRecovery() {
        #expect(
            JLPTExamRecoveryPolicy.action(for: apiError(code: "exam_price_changed"))
                == .refreshPrice
        )
        #expect(
            JLPTExamRecoveryPolicy.action(for: apiError(
                code: "answer_revision_conflict",
                detail: ["currentAnswerRevision": .number(7)]
            )) == .restoreAnswers(currentRevision: 7)
        )
        #expect(
            JLPTExamRecoveryPolicy.action(for: apiError(
                code: "paper_section_out_of_order",
                detail: [
                    "currentSectionExamId": .string("n3-listening"),
                    "currentSectionIndex": .number(2),
                    "paperAttemptId": .string("attempt-3"),
                ]
            )) == .restorePaper(
                currentSectionExamId: "n3-listening",
                currentSectionIndex: 2,
                paperAttemptId: "attempt-3"
            )
        )
        #expect(JLPTExamRecoveryPolicy.action(for: apiError(code: "EXAM_INSUFFICIENT_COINS")) == .openWallet)
        #expect(JLPTExamRecoveryPolicy.action(for: apiError(code: "MEMBER_REQUIRED")) == .openMembership)
    }

    @Test func paperProgressUsesServerExamIdBeforeIndexAndSupportsTwoOrThreeSections() {
        let two = ["n1-written", "n1-listening"]
        let three = ["n3-language", "n3-reading", "n3-listening"]

        #expect(JLPTPaperProgressResolver.index(
            sectionExamIDs: two,
            currentSectionExamId: "n1-listening",
            currentSectionIndex: 0
        ) == 1)
        #expect(JLPTPaperProgressResolver.index(
            sectionExamIDs: three,
            currentSectionExamId: "missing",
            currentSectionIndex: 2
        ) == 2)
        #expect(JLPTPaperProgressResolver.index(
            sectionExamIDs: three,
            currentSectionExamId: "",
            currentSectionIndex: 9
        ) == 0)
    }

    @Test func sectionAndListeningCopyIsDynamicAndDoesNotInventSequentialAudioPolicy() {
        #expect(JLPTExamCopy.paperStructure(sectionCount: 2, language: .zh).contains("2"))
        #expect(JLPTExamCopy.paperStructure(sectionCount: 3, language: .ja).contains("3"))
        #expect(JLPTExamCopy.paperStructure(sectionCount: 3, language: .en).contains("3"))

        let hints = [
            JLPTExamCopy.listeningHint(language: .zh),
            JLPTExamCopy.listeningHint(language: .ja),
            JLPTExamCopy.listeningHint(language: .en),
        ]
        #expect(!hints[0].contains("顺次"))
        #expect(!hints[1].contains("順に"))
        #expect(!hints[2].lowercased().contains("sequence"))
        #expect(hints.allSatisfy { !$0.isEmpty })
    }

    @Test func deadlineCopyDoesNotClaimLateLocalAnswersWereAccepted() {
        let copy = JLPTExamCopy.submissionNotice(
            deadlineExpired: true,
            snapshotAccepted: false,
            pendingAnswerCount: 2,
            language: .en
        )

        #expect(copy.contains("2"))
        #expect(copy.lowercased().contains("not be included"))
        #expect(!copy.lowercased().contains("saved successfully"))
    }

    private func apiError(
        code: String,
        detail: [String: KXJSONValue]? = nil
    ) -> KaiXAPIError {
        KaiXAPIError(error: .init(code: code, message: code, detail: detail))
    }

    private func preflight(requiredCoins: Int) throws -> KaiXJLPTExamPreflight {
        try JSONDecoder().decode(KaiXJLPTExamPreflight.self, from: Data(#"""
        {
          "status":"ok","examId":"exam-1","paperExamId":"","accessDecision":"ALLOWED",
          "canStart":true,"baseCoinCost":100,"memberCoinCost":50,"requiredCoins":\#(requiredCoins),
          "pricingTier":"member","balance":300,"shortfall":0,"unlockSource":"wallet",
          "oneTimePaperPayment":false,"currentSectionExamId":"","resumeSessionId":"",
          "paperAttempt":{},"priceSnapshotSource":"server","refundPolicyCode":"exam_refund_v1",
          "refundPolicyCopy":"Server refund policy","confirmationCopyKey":"exam_confirm_v1",
          "confirmationCopy":"Confirm charge","serverTime":"2026-07-22T13:00:00Z",
          "disclaimer":"Practice material"
        }
        """#.utf8))
    }
}
