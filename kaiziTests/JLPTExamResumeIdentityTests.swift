import Testing
@testable import Machi

@MainActor
struct JLPTExamResumeIdentityTests {
    private let receipt = JLPTExamStartReceipt(
        examId: "exam-paid-1",
        confirmedChargeCoins: 120,
        idempotencyKey: "original-paid-start-key"
    )

    @Test func exactPreflightIdentityAllowsOriginalReceiptReplay() {
        #expect(JLPTExamResumeIdentityPolicy.acceptsPreflight(
            receipt: receipt,
            expectedSessionId: "session-1",
            resumeSessionId: "session-1",
            preflightExamId: "exam-paid-1",
            requiredCoins: 0
        ))
    }

    @Test func preflightFailsClosedForMissingOrChangedIdentity() {
        #expect(!JLPTExamResumeIdentityPolicy.acceptsPreflight(
            receipt: receipt,
            expectedSessionId: "session-1",
            resumeSessionId: nil,
            preflightExamId: "exam-paid-1",
            requiredCoins: 0
        ))
        #expect(!JLPTExamResumeIdentityPolicy.acceptsPreflight(
            receipt: receipt,
            expectedSessionId: "session-1",
            resumeSessionId: "session-2",
            preflightExamId: "exam-paid-1",
            requiredCoins: 0
        ))
        #expect(!JLPTExamResumeIdentityPolicy.acceptsPreflight(
            receipt: receipt,
            expectedSessionId: "session-1",
            resumeSessionId: "session-1",
            preflightExamId: "exam-free-new-attempt",
            requiredCoins: 0
        ))
        #expect(!JLPTExamResumeIdentityPolicy.acceptsPreflight(
            receipt: receipt,
            expectedSessionId: "session-1",
            resumeSessionId: "session-1",
            preflightExamId: "exam-paid-1",
            requiredCoins: 120
        ))
    }

    @Test func invalidOriginalReceiptFailsClosed() {
        let blankKey = JLPTExamStartReceipt(
            examId: "exam-paid-1",
            confirmedChargeCoins: 120,
            idempotencyKey: "   "
        )
        let negativeCharge = JLPTExamStartReceipt(
            examId: "exam-paid-1",
            confirmedChargeCoins: -1,
            idempotencyKey: "original-paid-start-key"
        )

        #expect(!JLPTExamResumeIdentityPolicy.acceptsPreflight(
            receipt: blankKey,
            expectedSessionId: "session-1",
            resumeSessionId: "session-1",
            preflightExamId: "exam-paid-1",
            requiredCoins: 0
        ))
        #expect(!JLPTExamResumeIdentityPolicy.acceptsPreflight(
            receipt: negativeCharge,
            expectedSessionId: "session-1",
            resumeSessionId: "session-1",
            preflightExamId: "exam-paid-1",
            requiredCoins: 0
        ))
    }

    @Test func exactResumedResponseAllowsAuthoritativeMerge() {
        #expect(JLPTExamResumeIdentityPolicy.acceptsResponse(
            receipt: receipt,
            expectedSessionId: "session-1",
            expectedQuestionIDs: ["q1", "q2"],
            responseSessionId: "session-1",
            responseExamId: "exam-paid-1",
            resumed: true,
            responseQuestionIDs: ["q1", "q2"]
        ))
    }

    @Test func responseFailsClosedForEveryMissingOrChangedIdentityField() {
        let candidates: [(String?, String?, Bool?, [String]?)] = [
            (nil, "exam-paid-1", true, ["q1", "q2"]),
            ("session-2", "exam-paid-1", true, ["q1", "q2"]),
            ("session-1", nil, true, ["q1", "q2"]),
            ("session-1", "exam-free-new-attempt", true, ["q1", "q2"]),
            ("session-1", "exam-paid-1", nil, ["q1", "q2"]),
            ("session-1", "exam-paid-1", false, ["q1", "q2"]),
            ("session-1", "exam-paid-1", true, nil),
            ("session-1", "exam-paid-1", true, ["q2", "q1"]),
            ("session-1", "exam-paid-1", true, ["q1", "q3"]),
        ]

        for candidate in candidates {
            #expect(!JLPTExamResumeIdentityPolicy.acceptsResponse(
                receipt: receipt,
                expectedSessionId: "session-1",
                expectedQuestionIDs: ["q1", "q2"],
                responseSessionId: candidate.0,
                responseExamId: candidate.1,
                resumed: candidate.2,
                responseQuestionIDs: candidate.3
            ))
        }
    }
}
