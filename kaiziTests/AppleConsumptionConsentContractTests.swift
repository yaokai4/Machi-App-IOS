import Foundation
import Testing
@testable import Machi

@MainActor
struct AppleConsumptionConsentContractTests {
    @Test func settingsDTOIsBackwardCompatibleWhenConsentFieldsAreAbsent() throws {
        let settings = try decodeSettings(consentFragment: "")

        #expect(settings.apple_consumption_consent == nil)
        #expect(settings.apple_consumption_consent_policy_version == nil)
        #expect(settings.apple_consumption_consented_at == nil)
        #expect(AppleConsumptionConsentContract.snapshot(from: settings) == .unavailable)
    }

    @Test func currentServerGrantRequiresBooleanVersionAndTimestamp() throws {
        let settings = try decodeSettings(consentFragment: """
        ,"apple_consumption_consent":true
        ,"apple_consumption_consent_policy_version":"2026-07-22.v1"
        ,"apple_consumption_consented_at":"2026-07-23T10:20:30Z"
        """)

        let snapshot = try #require(AppleConsumptionConsentContract.snapshot(from: settings))
        #expect(snapshot.isSupported)
        #expect(snapshot.isGranted)
        #expect(snapshot.policyVersion == "2026-07-22.v1")
        #expect(snapshot.consentedAt == "2026-07-23T10:20:30Z")
    }

    @Test func partialOrContradictoryServerStateFailsClosed() throws {
        let partial = try decodeSettings(consentFragment: """
        ,"apple_consumption_consent":true
        ,"apple_consumption_consent_policy_version":"2026-07-22.v1"
        """)
        let staleTimestamp = try decodeSettings(consentFragment: """
        ,"apple_consumption_consent":false
        ,"apple_consumption_consent_policy_version":"2026-07-22.v1"
        ,"apple_consumption_consented_at":"2026-07-23T10:20:30Z"
        """)

        #expect(AppleConsumptionConsentContract.snapshot(from: partial) == nil)
        #expect(AppleConsumptionConsentContract.snapshot(from: staleTimestamp) == nil)
    }

    @Test func grantPayloadBindsExactServerPolicyAndLocale() throws {
        let snapshot = AppleConsumptionConsentSnapshot(
            isSupported: true,
            isGranted: false,
            policyVersion: "2026-07-22.v1",
            consentedAt: nil
        )
        let payload = try AppleConsumptionConsentContract.updatePayload(
            granting: true,
            current: snapshot,
            language: .zh
        )
        let object = try jsonObject(payload)

        #expect(object["apple_consumption_consent"] as? Bool == true)
        #expect(object["apple_consumption_consent_policy_version"] as? String == "2026-07-22.v1")
        #expect(object["language"] as? String == "zh-Hans")
        #expect(object.count == 3)
    }

    @Test func withdrawalIsExplicitAndNeverBlockedByAClientPolicyVersion() throws {
        let snapshot = AppleConsumptionConsentSnapshot(
            isSupported: true,
            isGranted: true,
            policyVersion: "2026-07-22.v1",
            consentedAt: "2026-07-23T10:20:30Z"
        )
        let payload = try AppleConsumptionConsentContract.updatePayload(
            granting: false,
            current: snapshot,
            language: .ja
        )
        let object = try jsonObject(payload)

        #expect(object["apple_consumption_consent"] as? Bool == false)
        #expect(object["apple_consumption_consent_policy_version"] == nil)
        #expect(object["language"] as? String == "ja")
        #expect(object.count == 2)
    }

    @Test func confirmedResponseMustMatchTheRequestedDecisionAndExactPolicy() throws {
        let current = AppleConsumptionConsentSnapshot(
            isSupported: true,
            isGranted: false,
            policyVersion: "2026-07-22.v1",
            consentedAt: nil
        )
        let confirmed = try decodeSettings(consentFragment: """
        ,"apple_consumption_consent":true
        ,"apple_consumption_consent_policy_version":"2026-07-22.v1"
        ,"apple_consumption_consented_at":"2026-07-23T10:20:30Z"
        """)
        let mismatched = try decodeSettings(consentFragment: """
        ,"apple_consumption_consent":true
        ,"apple_consumption_consent_policy_version":"2026-07-23.v2"
        ,"apple_consumption_consented_at":"2026-07-23T10:20:30Z"
        """)

        let snapshot = try AppleConsumptionConsentContract.confirmedSnapshot(
            from: confirmed,
            granting: true,
            requestedPolicyVersion: current.policyVersion
        )
        #expect(snapshot.isGranted)
        #expect(throws: AppleConsumptionConsentContractError.self) {
            try AppleConsumptionConsentContract.confirmedSnapshot(
                from: mismatched,
                granting: true,
                requestedPolicyVersion: current.policyVersion
            )
        }
    }

    @Test func allSupportedLanguagesExplainPurposeDataOptionalityAndWithdrawal() {
        for language in [AppLanguage.zh, .ja, .en] {
            let copy = AppleConsumptionConsentCopy(language: language)
            #expect(!copy.purpose.isEmpty)
            #expect(!copy.dataShared.isEmpty)
            #expect(!copy.optionalAndWithdrawal.isEmpty)
            #expect(!copy.grantConfirmationMessage.isEmpty)
            #expect(!copy.withdrawConfirmationMessage.isEmpty)
            #expect(copy.voiceOverToggleHint.contains(copy.optionalKeyword))
        }
    }

    private func decodeSettings(consentFragment: String) throws -> KaiXSettingsDTO {
        try JSONDecoder().decode(KaiXSettingsDTO.self, from: Data("""
        {
          "user_id":"user-1",
          "language":"en",
          "appearance":"light",
          "push_likes":true,
          "push_comments":true,
          "push_follows":true,
          "push_messages":true,
          "push_inquiries":true,
          "privacy_protect":false,
          "privacy_allow_dm":"everyone",
          "recommend_following":true,
          "recommend_topics":true,
          "updated_at":"2026-07-23T10:00:00Z"
          \(consentFragment)
        }
        """.utf8))
    }

    private func jsonObject(_ payload: KaiXAppleConsumptionConsentUpdate) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
