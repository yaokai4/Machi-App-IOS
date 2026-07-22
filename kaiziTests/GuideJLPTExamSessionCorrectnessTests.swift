import Testing
@testable import Machi

@MainActor
struct GuideJLPTExamSessionCorrectnessTests {
    @Test func sealAndFlushRejectsLateAnswersAndWaitsForBoundaryTail() async {
        let recorder = ControlledAnswerSave()
        let coordinator = JLPTExamAnswerSaveCoordinator { questionId, selectedIndex in
            try await recorder.save(questionId: questionId, selectedIndex: selectedIndex)
        }

        #expect(coordinator.enqueue(questionId: "q1", selectedIndex: 0))
        await recorder.waitUntilFirstSaveStarts()
        #expect(coordinator.enqueue(questionId: "q1", selectedIndex: 1))

        let completion = CompletionProbe()
        let flushTask = Task { @MainActor in
            let failures = await coordinator.sealAndFlush()
            await completion.markFinished()
            return failures
        }
        while !coordinator.isSealed {
            await Task.yield()
        }

        #expect(await recorder.savedIndexes() == [0])
        #expect(!(await completion.isFinished()))
        #expect(!coordinator.enqueue(questionId: "q1", selectedIndex: 2))

        await recorder.releaseFirstSave()
        let failures = await flushTask.value

        #expect(failures.isEmpty)
        #expect(await recorder.savedIndexes() == [0, 1])
        #expect(await completion.isFinished())
    }

    @Test func flushRetriesLatestSelectionAfterTransientFailure() async {
        let recorder = TransientFailureAnswerSave()
        let coordinator = JLPTExamAnswerSaveCoordinator { questionId, selectedIndex in
            try await recorder.save(questionId: questionId, selectedIndex: selectedIndex)
        }

        coordinator.enqueue(questionId: "q1", selectedIndex: 2)
        let failures = await coordinator.sealAndFlush()

        #expect(failures.isEmpty)
        #expect(await recorder.attemptCount() == 2)
        #expect(await recorder.savedIndexes() == [2])
    }

    @Test func reopenAllowsAnswersAfterAbortedSubmit() async {
        let coordinator = JLPTExamAnswerSaveCoordinator { _, _ in }

        #expect(coordinator.enqueue(questionId: "q1", selectedIndex: 0))
        #expect((await coordinator.sealAndFlush()).isEmpty)
        #expect(!coordinator.enqueue(questionId: "q1", selectedIndex: 1))

        coordinator.reopen()

        #expect(coordinator.enqueue(questionId: "q1", selectedIndex: 2))
        #expect((await coordinator.sealAndFlush()).isEmpty)
    }

    @Test func acceptedSaveRetainsCoordinatorUntilCompletionThenReleasesIt() async {
        let recorder = ControlledAnswerSave()
        let completion = CompletionProbe()
        var coordinator: JLPTExamAnswerSaveCoordinator? = JLPTExamAnswerSaveCoordinator { questionId, selectedIndex in
            try await recorder.save(questionId: questionId, selectedIndex: selectedIndex)
            await completion.markFinished()
        }
        let weakCoordinator = WeakBox(coordinator)

        #expect(coordinator?.enqueue(questionId: "q1", selectedIndex: 0) == true)
        coordinator = nil

        #expect(weakCoordinator.value != nil)
        guard weakCoordinator.value != nil else { return }
        await recorder.waitUntilFirstSaveStarts()
        #expect(weakCoordinator.value != nil)

        await recorder.releaseFirstSave()
        await completion.waitUntilFinished()
        for _ in 0..<100 where weakCoordinator.value != nil {
            await Task.yield()
        }
        #expect(weakCoordinator.value == nil)
    }

    @Test func completedResultReplacesAnsweringContent() {
        #expect(
            JLPTExamSessionContentState.resolve(
                questionCount: 1,
                cursor: 0,
                timedOut: false,
                submitting: false,
                hasResult: true
            ) == .result
        )
        #expect(
            JLPTExamSessionContentState.resolve(
                questionCount: 1,
                cursor: 0,
                timedOut: false,
                submitting: false,
                hasResult: false
            ) == .answering
        )
    }

    @Test func submittingReplacesInteractiveAnsweringAndTimeUpContent() {
        #expect(
            JLPTExamSessionContentState.resolve(
                questionCount: 1,
                cursor: 0,
                timedOut: false,
                submitting: true,
                hasResult: false
            ) == .submitting
        )
        #expect(
            JLPTExamSessionContentState.resolve(
                questionCount: 1,
                cursor: 0,
                timedOut: true,
                submitting: true,
                hasResult: false
            ) == .submitting
        )
        #expect(
            JLPTExamSessionContentState.resolve(
                questionCount: 1,
                cursor: 0,
                timedOut: false,
                submitting: true,
                hasResult: true
            ) == .result
        )
    }

    @Test func submittingBlocksExitEvenBeforeAnyAnswer() {
        #expect(
            JLPTExamSessionInteractionPolicy.shouldGuardExit(
                questionCount: 1,
                answerCount: 0,
                submitting: true,
                hasResult: false
            )
        )
        #expect(
            !JLPTExamSessionInteractionPolicy.shouldGuardExit(
                questionCount: 1,
                answerCount: 0,
                submitting: true,
                hasResult: true
            )
        )
        #expect(
            JLPTExamSessionInteractionPolicy.shouldGuardExit(
                questionCount: 1,
                answerCount: 1,
                submitting: false,
                hasResult: false
            )
        )
        #expect(
            !JLPTExamSessionInteractionPolicy.shouldGuardExit(
                questionCount: 1,
                answerCount: 0,
                submitting: false,
                hasResult: false
            )
        )
    }

    @Test func beginningSubmissionDismissesEveryLegacyPresentation() {
        var presentation = JLPTExamSessionPresentationState(
            leaveConfirmationPresented: true,
            unsyncedConfirmationPresented: true,
            answerSheetPresented: true
        )

        presentation.beginSubmitting()

        #expect(!presentation.leaveConfirmationPresented)
        #expect(!presentation.unsyncedConfirmationPresented)
        #expect(!presentation.answerSheetPresented)
    }

    @Test func submittingRejectsLegacyExitAction() {
        #expect(!JLPTExamSessionInteractionPolicy.canExit(submitting: true))
        #expect(JLPTExamSessionInteractionPolicy.canExit(submitting: false))
    }
}

private actor ControlledAnswerSave {
    private var indexes: [Int] = []
    private var firstSaveContinuation: CheckedContinuation<Void, Never>?

    func save(questionId: String, selectedIndex: Int) async throws {
        indexes.append(selectedIndex)
        if indexes.count == 1 {
            await withCheckedContinuation { continuation in
                firstSaveContinuation = continuation
            }
        }
    }

    func waitUntilFirstSaveStarts() async {
        while indexes.isEmpty {
            await Task.yield()
        }
    }

    func releaseFirstSave() {
        firstSaveContinuation?.resume()
        firstSaveContinuation = nil
    }

    func savedIndexes() -> [Int] {
        indexes
    }
}

private actor TransientFailureAnswerSave {
    private enum Failure: Error { case transient }

    private var attempts = 0
    private var indexes: [Int] = []

    func save(questionId: String, selectedIndex: Int) async throws {
        attempts += 1
        if attempts == 1 {
            throw Failure.transient
        }
        indexes.append(selectedIndex)
    }

    func attemptCount() -> Int {
        attempts
    }

    func savedIndexes() -> [Int] {
        indexes
    }
}

private actor CompletionProbe {
    private var finished = false

    func markFinished() {
        finished = true
    }

    func isFinished() -> Bool {
        finished
    }

    func waitUntilFinished() async {
        while !finished {
            await Task.yield()
        }
    }
}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}
