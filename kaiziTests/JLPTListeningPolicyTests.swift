import Foundation
import Testing
@testable import Machi

@MainActor
struct JLPTListeningPolicyTests {
    @Test func liveTimedExamAlwaysUsesCanonicalStrictPolicy() {
        let contradictory = KaiXJLPTListeningPolicy(
            mode: "practice",
            allowPause: false,
            allowSeek: true,
            allowReplay: true,
            maxPlays: 0,
            showTranscriptDuringAttempt: true
        )
        let unknown = KaiXJLPTListeningPolicy(
            mode: "future-mode",
            allowPause: true,
            allowSeek: true,
            allowReplay: true,
            maxPlays: 99,
            showTranscriptDuringAttempt: true
        )

        for raw in [contradictory, unknown, nil] {
            let policy = JLPTListeningRuntimePolicy.resolve(
                serverPolicy: raw,
                context: .liveTimedExam
            )
            #expect(policy.mode == .strict)
            #expect(policy.allowPause)
            #expect(!policy.allowSeek)
            #expect(!policy.allowReplay)
            #expect(policy.maxPlays == 1)
            #expect(!policy.showTranscriptDuringAttempt)
        }
    }

    @Test func nonExamSurfacesKeepCanonicalPracticeBehavior() {
        let strictFromServer = KaiXJLPTListeningPolicy(
            mode: "strict",
            allowPause: false,
            allowSeek: false,
            allowReplay: false,
            maxPlays: 1,
            showTranscriptDuringAttempt: false
        )
        let policy = JLPTListeningRuntimePolicy.resolve(
            serverPolicy: strictFromServer,
            context: .nonExam
        )

        #expect(policy.mode == .practice)
        #expect(policy.allowPause)
        #expect(policy.allowSeek)
        #expect(policy.allowReplay)
        #expect(policy.maxPlays == 0)
        #expect(policy.showTranscriptDuringAttempt)
    }

    @Test func validServerStrictPolicyMayTightenPauseButNeverLoosenExamRules() {
        let server = KaiXJLPTListeningPolicy(
            mode: "strict",
            allowPause: false,
            allowSeek: true,
            allowReplay: true,
            maxPlays: 99,
            showTranscriptDuringAttempt: true
        )
        let policy = JLPTListeningRuntimePolicy.resolve(
            serverPolicy: server,
            context: .liveTimedExam
        )

        #expect(policy.mode == .strict)
        #expect(!policy.allowPause)
        #expect(!policy.allowSeek)
        #expect(!policy.allowReplay)
        #expect(policy.maxPlays == 1)
        #expect(!policy.showTranscriptDuringAttempt)
    }

    @Test func failedLoadBeforePlaybackDoesNotConsumeStrictAttempt() {
        var gate = JLPTListeningPlaybackGate(policy: .strict, persistedPlaysStarted: 0)

        #expect(gate.requestPlay(currentSeconds: 0, ended: false) == .startNew)
        gate.failPendingStart()
        #expect(gate.playsStarted == 0)
        #expect(gate.requestPlay(currentSeconds: 0, ended: false) == .startNew)
    }

    @Test func oneSuccessfulStartAllowsPauseResumeButBlocksReplay() {
        var gate = JLPTListeningPlaybackGate(policy: .strict, persistedPlaysStarted: 0)

        #expect(gate.requestPlay(currentSeconds: 0, ended: false) == .startNew)
        let confirmed = gate.confirmPlaybackStarted()
        #expect(confirmed)
        #expect(gate.didConsumePlaybackInCurrentLoad)
        #expect(gate.playsStarted == 1)
        #expect(gate.requestPlay(currentSeconds: 0, ended: false) == .resume)

        gate.markEnded()
        #expect(gate.requestPlay(currentSeconds: 120, ended: true) == .blocked)
        #expect(gate.requestReplay() == .blocked)
    }

    @Test func persistedCredentialBlocksReplayAfterRelaunch() {
        var gate = JLPTListeningPlaybackGate(policy: .strict, persistedPlaysStarted: 1)

        #expect(gate.requestPlay(currentSeconds: 0, ended: false) == .blocked)
        let confirmed = gate.confirmPlaybackStarted()
        #expect(!confirmed)
        #expect(gate.playsStarted == 1)
    }

    @Test func practicePlaybackRemainsUnlimitedAndReplayable() {
        var gate = JLPTListeningPlaybackGate(policy: .practice, persistedPlaysStarted: 0)

        #expect(gate.requestPlay(currentSeconds: 0, ended: false) == .startNew)
        let firstConfirmed = gate.confirmPlaybackStarted()
        #expect(firstConfirmed)
        gate.markEnded()
        #expect(gate.requestReplay() == .startNew)
        let replayConfirmed = gate.confirmPlaybackStarted()
        #expect(replayConfirmed)
        #expect(gate.playsStarted == 2)
    }

    @Test func failurePresentationDistinguishesPreplayRetryFromConsumedFailure() {
        let beforePlayback = JLPTListeningFailurePresentation.resolve(
            policy: .strict,
            didConsumePlay: false
        )
        let strictAfterPlayback = JLPTListeningFailurePresentation.resolve(
            policy: .strict,
            didConsumePlay: true
        )
        let practiceAfterPlayback = JLPTListeningFailurePresentation.resolve(
            policy: .practice,
            didConsumePlay: true
        )

        #expect(!beforePlayback.didConsumePlay)
        #expect(beforePlayback.canRetry)
        #expect(strictAfterPlayback.didConsumePlay)
        #expect(!strictAfterPlayback.canRetry)
        #expect(practiceAfterPlayback.didConsumePlay)
        #expect(practiceAfterPlayback.canRetry)
    }

    @Test func successfulPlaybackCredentialPersistsBySessionAndQuestion() throws {
        let suite = "JLPTListeningPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let identity = JLPTListeningPlaybackIdentity(sessionId: "session-1", questionId: "q-1")

        let writer = JLPTListeningPlaybackCredentialStore(defaults: defaults)
        #expect(writer.playsStarted(for: identity) == 0)
        writer.recordSuccessfulStart(for: identity)

        let relaunched = JLPTListeningPlaybackCredentialStore(defaults: defaults)
        #expect(relaunched.playsStarted(for: identity) == 1)
        #expect(relaunched.playsStarted(for: .init(sessionId: "session-1", questionId: "q-2")) == 0)
    }

    @Test func startDTOCarriesExactListeningPolicyShape() throws {
        let value = try JSONDecoder().decode(KaiXJLPTExamStartResponse.self, from: Data(#"""
        {
          "status":"started",
          "sessionId":"s1",
          "examId":"n2-listening",
          "listeningPolicy":{
            "mode":"strict",
            "allowPause":true,
            "allowSeek":false,
            "allowReplay":false,
            "maxPlays":1,
            "showTranscriptDuringAttempt":false
          }
        }
        """#.utf8))

        #expect(value.listeningPolicy?.mode == "strict")
        #expect(value.listeningPolicy?.allowPause == true)
        #expect(value.listeningPolicy?.allowSeek == false)
        #expect(value.listeningPolicy?.allowReplay == false)
        #expect(value.listeningPolicy?.maxPlays == 1)
        #expect(value.listeningPolicy?.showTranscriptDuringAttempt == false)
    }
}
