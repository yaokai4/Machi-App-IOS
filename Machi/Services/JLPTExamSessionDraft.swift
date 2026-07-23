import Combine
import Foundation

/// One exact revision write waiting for an authoritative server acknowledgement.
/// The tuple is persisted before the network task starts so a relaunch can replay
/// the same request instead of inventing a new revision.
struct JLPTExamPendingAnswer: Codable, Equatable, Hashable, Identifiable {
    let questionId: String
    let selectedIndex: Int
    let baseRevision: Int
    let revision: Int

    var id: Int { revision }

    func request(sessionId: String) -> KaiXJLPTExamAnswerRequest {
        KaiXJLPTExamAnswerRequest(
            sessionId: sessionId,
            questionId: questionId,
            selectedIndex: selectedIndex,
            baseRevision: baseRevision,
            revision: revision
        )
    }
}

/// Crash-safe local overlay for one server-owned exam session.
struct JLPTExamSessionDraft: Codable, Equatable {
    let sessionId: String
    var serverRevision: Int
    var answers: [String: Int]
    var pendingAnswers: [JLPTExamPendingAnswer]
    /// 最后一次写入时间，仅用于回收。可选且默认 nil，因为旧版本存下的草稿没有
    /// 这个字段——设成必填会让升级后所有既有草稿解码失败、正在考试的用户丢答案。
    var updatedAt: Date? = nil

    func orderedSnapshot(questionIDs: [String]) -> [KaiXJLPTAnswerSnapshot] {
        questionIDs.compactMap { questionId in
            answers[questionId].map {
                KaiXJLPTAnswerSnapshot(questionId: questionId, selectedIndex: $0)
            }
        }
    }

    /// The start/resume response is authoritative for acknowledged state. Only
    /// a contiguous local suffix above its global answer revision is replayable.
    static func merging(
        sessionId: String,
        serverAnswers: [String: Int],
        serverRevision: Int,
        local: JLPTExamSessionDraft?
    ) -> JLPTExamSessionDraft {
        var mergedAnswers = serverAnswers
        var retained: [JLPTExamPendingAnswer] = []
        var expectedBaseRevision = serverRevision

        if local?.sessionId == sessionId {
            for pending in (local?.pendingAnswers ?? []).sorted(by: { $0.revision < $1.revision }) {
                guard pending.revision > serverRevision else { continue }
                guard pending.baseRevision == expectedBaseRevision,
                      pending.revision == expectedBaseRevision + 1 else {
                    // A gap means the durable queue is no longer safe to replay.
                    // Keep the server snapshot authoritative rather than sending
                    // a speculative write that is guaranteed to conflict.
                    break
                }
                retained.append(pending)
                mergedAnswers[pending.questionId] = pending.selectedIndex
                expectedBaseRevision = pending.revision
            }
        }

        return JLPTExamSessionDraft(
            sessionId: sessionId,
            serverRevision: serverRevision,
            answers: mergedAnswers,
            pendingAnswers: retained
        )
    }
}

/// UserDefaults-backed draft storage. Exam selections are non-sensitive app
/// state, and using the app's existing declared preference store makes each
/// accepted tap durable before its request leaves the device.
@MainActor
final class JLPTExamSessionDraftStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "guide.jlpt.exam.session-drafts.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func draft(sessionId: String) -> JLPTExamSessionDraft? {
        allDrafts()[sessionId]
    }

    func save(_ draft: JLPTExamSessionDraft) {
        var drafts = allDrafts()
        var stamped = draft
        stamped.updatedAt = Date()
        drafts[draft.sessionId] = stamped
        persist(Self.pruned(drafts, keeping: draft.sessionId))
    }

    /// 回收：草稿只在交卷成功时才被 clearDraft 删掉，中途退出且再不回来的会话
    /// 会永久驻留；而 allDrafts() 每次读写都全量编解码，开销是 O(全部历史草稿)
    /// 且压在每一次点选答案的主线程上。这里按「过期 + 总量上限」双重收口，并且
    /// 永远保留当前正在写的会话。没有 updatedAt 的旧草稿视为刚写入，给它们一个
    /// 完整的过期周期，不会一升级就被清掉。
    static func pruned(
        _ drafts: [String: JLPTExamSessionDraft],
        keeping protectedSessionId: String?,
        now: Date = Date(),
        maximumAge: TimeInterval = 7 * 24 * 60 * 60,
        maximumCount: Int = 24
    ) -> [String: JLPTExamSessionDraft] {
        var kept = drafts.filter { key, draft in
            if key == protectedSessionId { return true }
            guard let updatedAt = draft.updatedAt else { return true }
            return now.timeIntervalSince(updatedAt) <= maximumAge
        }
        guard kept.count > maximumCount else { return kept }
        let ordered = kept.sorted { left, right in
            let leftAt = left.value.updatedAt ?? .distantPast
            let rightAt = right.value.updatedAt ?? .distantPast
            if leftAt == rightAt { return left.key < right.key }
            return leftAt > rightAt
        }
        var survivors: [String: JLPTExamSessionDraft] = [:]
        if let protectedSessionId, let draft = kept[protectedSessionId] {
            survivors[protectedSessionId] = draft
        }
        for (key, draft) in ordered where survivors.count < maximumCount {
            survivors[key] = draft
        }
        kept = survivors
        return kept
    }

    @discardableResult
    func merge(
        sessionId: String,
        serverAnswers: [String: Int],
        serverRevision: Int
    ) -> JLPTExamSessionDraft {
        let merged = JLPTExamSessionDraft.merging(
            sessionId: sessionId,
            serverAnswers: serverAnswers,
            serverRevision: serverRevision,
            local: draft(sessionId: sessionId)
        )
        save(merged)
        return merged
    }

    func remove(sessionId: String) {
        var drafts = allDrafts()
        drafts.removeValue(forKey: sessionId)
        persist(drafts)
    }

    private func allDrafts() -> [String: JLPTExamSessionDraft] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: JLPTExamSessionDraft].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persist(_ drafts: [String: JLPTExamSessionDraft]) {
        guard !drafts.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

@MainActor
final class JLPTExamAnswerSaveCoordinator: ObservableObject {
    typealias RevisionSaveOperation = (KaiXJLPTExamAnswerRequest) async throws -> KaiXJLPTExamAnswerResponse
    typealias SaveOperation = (_ questionId: String, _ selectedIndex: Int) async throws -> Void

    @Published private(set) var draft: JLPTExamSessionDraft

    private let draftStore: JLPTExamSessionDraftStore?
    private let saveOperation: RevisionSaveOperation
    private var tail: Task<Void, Never>?
    private(set) var isSealed = false

    var unsavedQuestionIDs: Set<String> {
        Set(draft.pendingAnswers.map(\.questionId))
    }

    var authoritativeRevision: Int { draft.serverRevision }
    var currentAnswers: [String: Int] { draft.answers }

    init(
        sessionId: String,
        serverAnswers: [String: Int],
        answerRevision: Int,
        draftStore: JLPTExamSessionDraftStore,
        saveOperation: @escaping RevisionSaveOperation
    ) {
        self.draftStore = draftStore
        self.saveOperation = saveOperation
        self.draft = draftStore.merge(
            sessionId: sessionId,
            serverAnswers: serverAnswers,
            serverRevision: answerRevision
        )
        schedulePendingReplayIfNeeded()
    }

    convenience init(
        sessionId: String,
        serverAnswers: [String: Int],
        answerRevision: Int,
        saveOperation: @escaping RevisionSaveOperation
    ) {
        self.init(
            sessionId: sessionId,
            serverAnswers: serverAnswers,
            answerRevision: answerRevision,
            draftStore: JLPTExamSessionDraftStore(),
            saveOperation: saveOperation
        )
    }

    /// Compatibility entry point retained for the existing submit-boundary
    /// correctness tests while production uses the revision-aware initializer.
    init(saveOperation legacySaveOperation: @escaping SaveOperation) {
        let sessionId = "legacy-\(UUID().uuidString)"
        self.draftStore = nil
        self.draft = JLPTExamSessionDraft(
            sessionId: sessionId,
            serverRevision: 0,
            answers: [:],
            pendingAnswers: []
        )
        self.saveOperation = { request in
            try await legacySaveOperation(request.questionId, request.selectedIndex)
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
    }

    /// Durably reserves the next adjacent revision before launching its request.
    @discardableResult
    func enqueue(questionId: String, selectedIndex: Int) -> Bool {
        guard !isSealed else { return false }
        let baseRevision = draft.pendingAnswers.last?.revision ?? draft.serverRevision
        let pending = JLPTExamPendingAnswer(
            questionId: questionId,
            selectedIndex: selectedIndex,
            baseRevision: baseRevision,
            revision: baseRevision + 1
        )
        draft.answers[questionId] = selectedIndex
        draft.pendingAnswers.append(pending)
        persistDraft()

        let predecessor = tail
        tail = Task { [self] in
            _ = await predecessor?.value
            await persist(pending)
        }
        return true
    }

    /// Establishes a MainActor-linearized submit boundary, then retries the
    /// exact durable requests in order. New answers remain rejected until reopen.
    func sealAndFlush() async -> Set<String> {
        isSealed = true
        await tail?.value

        while let pending = draft.pendingAnswers.first {
            let revisionBeforeRetry = draft.serverRevision
            await persist(pending)
            guard draft.serverRevision > revisionBeforeRetry else { break }
        }
        return unsavedQuestionIDs
    }

    func reopen() {
        isSealed = false
    }

    func orderedSnapshot(questionIDs: [String]) -> [KaiXJLPTAnswerSnapshot] {
        draft.orderedSnapshot(questionIDs: questionIDs)
    }

    /// Replaces acknowledged state with a fresh start/resume snapshot and then
    /// reapplies only the durable contiguous suffix above its revision.
    func mergeAuthoritative(serverAnswers: [String: Int], answerRevision: Int) {
        tail = nil
        if let draftStore {
            draft = draftStore.merge(
                sessionId: draft.sessionId,
                serverAnswers: serverAnswers,
                serverRevision: answerRevision
            )
        } else {
            draft = JLPTExamSessionDraft.merging(
                sessionId: draft.sessionId,
                serverAnswers: serverAnswers,
                serverRevision: answerRevision,
                local: draft
            )
        }
        schedulePendingReplayIfNeeded()
    }

    func clearDraft() {
        draftStore?.remove(sessionId: draft.sessionId)
        draft.pendingAnswers.removeAll()
    }

    private func schedulePendingReplayIfNeeded() {
        guard tail == nil, !draft.pendingAnswers.isEmpty else { return }
        let pending = draft.pendingAnswers
        tail = Task { [self] in
            for write in pending {
                await persist(write)
                guard draft.serverRevision >= write.revision else { break }
            }
        }
    }

    private func persist(_ pending: JLPTExamPendingAnswer) async {
        guard draft.pendingAnswers.contains(where: { $0.revision == pending.revision }) else { return }
        // Never send a successor while an earlier revision remains unresolved.
        guard draft.serverRevision == pending.baseRevision else { return }

        do {
            let response = try await saveOperation(pending.request(sessionId: draft.sessionId))
            guard response.saved != false else { return }
            guard let acknowledgedRevision = response.answerRevision ?? response.revision,
                  acknowledgedRevision == pending.revision else { return }

            draft.serverRevision = acknowledgedRevision
            draft.pendingAnswers.removeAll { $0.revision <= acknowledgedRevision }
            persistDraft()
        } catch {
            // The exact request remains durable. A submit flush or resumed
            // session replays the same tuple, which the server treats idempotently.
        }
    }

    private func persistDraft() {
        draftStore?.save(draft)
    }
}
