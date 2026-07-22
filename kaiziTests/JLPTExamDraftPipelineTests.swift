import Foundation
import Testing
@testable import Machi

@MainActor
struct JLPTExamDraftPipelineTests {
    @Test func durableDraftSurvivesStoreRecreationAndReplaysOnlyUnacknowledgedAnswers() throws {
        let suiteName = "JLPTExamDraftPipelineTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = JLPTExamSessionDraftStore(defaults: defaults)
        firstStore.save(
            JLPTExamSessionDraft(
                sessionId: "session-1",
                serverRevision: 1,
                answers: ["server-old": 0, "local-new": 2],
                pendingAnswers: [
                    JLPTExamPendingAnswer(
                        questionId: "local-new",
                        selectedIndex: 2,
                        baseRevision: 1,
                        revision: 2
                    )
                ]
            )
        )

        let recreatedStore = JLPTExamSessionDraftStore(defaults: defaults)
        let merged = recreatedStore.merge(
            sessionId: "session-1",
            serverAnswers: ["server-old": 1, "server-new": 3],
            serverRevision: 1
        )

        #expect(merged.serverRevision == 1)
        #expect(merged.answers == ["server-old": 1, "server-new": 3, "local-new": 2])
        #expect(merged.pendingAnswers.map(\.revision) == [2])

        let acknowledged = recreatedStore.merge(
            sessionId: "session-1",
            serverAnswers: ["server-old": 1, "server-new": 3, "local-new": 2],
            serverRevision: 2
        )

        #expect(acknowledged.serverRevision == 2)
        #expect(acknowledged.pendingAnswers.isEmpty)
    }

    @Test func queuedWritesUseAdjacentRevisionsAndReplayTheExactRequestAfterResponseLoss() async throws {
        let suiteName = "JLPTExamDraftPipelineTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let recorder = ResponseLossAnswerServer()
        let coordinator = JLPTExamAnswerSaveCoordinator(
            sessionId: "session-2",
            serverAnswers: [:],
            answerRevision: 0,
            draftStore: JLPTExamSessionDraftStore(defaults: defaults)
        ) { request in
            try await recorder.save(request)
        }

        #expect(coordinator.enqueue(questionId: "q1", selectedIndex: 0))
        #expect(coordinator.enqueue(questionId: "q2", selectedIndex: 3))

        let failures = await coordinator.sealAndFlush()
        let requests = recorder.requests()

        #expect(failures.isEmpty)
        #expect(requests.count == 3)
        #expect(requests[0] == requests[1])
        #expect(requests.map(\.baseRevision) == [0, 0, 1])
        #expect(requests.map(\.revision) == [1, 1, 2])
        #expect(coordinator.authoritativeRevision == 2)
        #expect(coordinator.unsavedQuestionIDs.isEmpty)
    }

    @Test func enqueuePersistsBeforeNetworkCompletion() async throws {
        let suiteName = "JLPTExamDraftPipelineTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let recorder = BlockingRevisionServer()
        let store = JLPTExamSessionDraftStore(defaults: defaults)
        let coordinator = JLPTExamAnswerSaveCoordinator(
            sessionId: "session-3",
            serverAnswers: ["q0": 1],
            answerRevision: 4,
            draftStore: store
        ) { request in
            try await recorder.save(request)
        }

        #expect(coordinator.enqueue(questionId: "q1", selectedIndex: 2))

        let persisted = try #require(store.draft(sessionId: "session-3"))
        #expect(persisted.answers["q1"] == 2)
        #expect(persisted.pendingAnswers.first?.baseRevision == 4)
        #expect(persisted.pendingAnswers.first?.revision == 5)

        await recorder.waitUntilStarted()
        recorder.release()
        #expect((await coordinator.sealAndFlush()).isEmpty)
    }

    @Test func submitSnapshotContainsEveryAnswerInQuestionOrder() {
        let draft = JLPTExamSessionDraft(
            sessionId: "session-4",
            serverRevision: 8,
            answers: ["q3": 2, "q1": 0, "q2": 1],
            pendingAnswers: []
        )

        let snapshot = draft.orderedSnapshot(questionIDs: ["q1", "q2", "q3", "missing"])

        #expect(snapshot == [
            KaiXJLPTAnswerSnapshot(questionId: "q1", selectedIndex: 0),
            KaiXJLPTAnswerSnapshot(questionId: "q2", selectedIndex: 1),
            KaiXJLPTAnswerSnapshot(questionId: "q3", selectedIndex: 2),
        ])
    }
}

@MainActor
private final class ResponseLossAnswerServer {
    private enum LostResponse: Error { case lost }

    private var received: [KaiXJLPTExamAnswerRequest] = []
    private var lostFirstResponse = false

    func save(_ request: KaiXJLPTExamAnswerRequest) async throws -> KaiXJLPTExamAnswerResponse {
        received.append(request)
        if !lostFirstResponse {
            lostFirstResponse = true
            throw LostResponse.lost
        }
        return KaiXJLPTExamAnswerResponse(
            status: "ok",
            saved: true,
            questionId: request.questionId,
            revision: request.revision,
            answerRevision: request.revision,
            idempotentReplay: received.dropLast().contains(request),
            legacyRevisionAssigned: false
        )
    }

    func requests() -> [KaiXJLPTExamAnswerRequest] {
        received
    }
}

@MainActor
private final class BlockingRevisionServer {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    func save(_ request: KaiXJLPTExamAnswerRequest) async throws -> KaiXJLPTExamAnswerResponse {
        started = true
        await withCheckedContinuation { continuation = $0 }
        return KaiXJLPTExamAnswerResponse(
            status: "ok",
            saved: true,
            questionId: request.questionId,
            revision: request.revision,
            answerRevision: request.revision,
            idempotentReplay: false,
            legacyRevisionAssigned: false
        )
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
