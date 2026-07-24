import Foundation

struct AppleConsumptionConsentSnapshot: Equatable {
    let isSupported: Bool
    let isGranted: Bool
    let policyVersion: String?
    let consentedAt: String?

    static let unavailable = AppleConsumptionConsentSnapshot(
        isSupported: false,
        isGranted: false,
        policyVersion: nil,
        consentedAt: nil
    )
}

enum AppleConsumptionConsentContractError: Error, Equatable {
    case unsupportedServer
    case missingPolicyVersion
    case malformedServerState
    case unconfirmedDecision
    case policyVersionChanged
}

struct KaiXAppleConsumptionConsentUpdate: Encodable, Equatable {
    let apple_consumption_consent: Bool
    let apple_consumption_consent_policy_version: String?
    let language: String
}

enum AppleConsumptionConsentContract {
    /// Converts the settings response into a fail-closed, server-authoritative
    /// state. A legacy response with none of the three fields is supported as
    /// an unavailable/false state; a partial or contradictory response is
    /// rejected instead of accidentally displaying consent as granted.
    static func snapshot(from settings: KaiXSettingsDTO) -> AppleConsumptionConsentSnapshot? {
        let granted = settings.apple_consumption_consent
        let rawVersion = settings.apple_consumption_consent_policy_version
        let rawConsentedAt = settings.apple_consumption_consented_at

        if granted == nil, rawVersion == nil, rawConsentedAt == nil {
            return .unavailable
        }
        guard let granted, let rawVersion, let rawConsentedAt else {
            return nil
        }
        let version = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let consentedAt = rawConsentedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return nil }
        guard granted ? !consentedAt.isEmpty : consentedAt.isEmpty else { return nil }

        return AppleConsumptionConsentSnapshot(
            isSupported: true,
            isGranted: granted,
            policyVersion: rawVersion,
            consentedAt: granted ? rawConsentedAt : nil
        )
    }

    /// Builds the exact typed PATCH body. Grants are bound to the policy
    /// version supplied by the server; withdrawals intentionally omit it so a
    /// stale client can always withdraw immediately.
    static func updatePayload(
        granting: Bool,
        current: AppleConsumptionConsentSnapshot,
        language: AppLanguage
    ) throws -> KaiXAppleConsumptionConsentUpdate {
        guard current.isSupported else {
            throw AppleConsumptionConsentContractError.unsupportedServer
        }
        var policyVersion: String?
        if granting {
            guard let version = current.policyVersion,
                  !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppleConsumptionConsentContractError.missingPolicyVersion
            }
            // Send the original value byte-for-byte. Trimming is validation,
            // never mutation: the backend requires an exact policy match.
            policyVersion = version
        }
        return KaiXAppleConsumptionConsentUpdate(
            apple_consumption_consent: granting,
            apple_consumption_consent_policy_version: policyVersion,
            language: localeCode(language)
        )
    }

    /// Accepts a mutation only after the returned settings prove that the
    /// server persisted the requested decision. The caller can therefore keep
    /// the previous UI snapshot on every error without optimistic drift.
    static func confirmedSnapshot(
        from settings: KaiXSettingsDTO,
        granting: Bool,
        requestedPolicyVersion: String?
    ) throws -> AppleConsumptionConsentSnapshot {
        guard let snapshot = snapshot(from: settings), snapshot.isSupported else {
            throw AppleConsumptionConsentContractError.malformedServerState
        }
        guard snapshot.isGranted == granting else {
            throw AppleConsumptionConsentContractError.unconfirmedDecision
        }
        if granting {
            guard let requestedPolicyVersion,
                  snapshot.policyVersion == requestedPolicyVersion else {
                throw AppleConsumptionConsentContractError.policyVersionChanged
            }
        }
        return snapshot
    }

    private static func localeCode(_ language: AppLanguage) -> String {
        switch language {
        case .ja: "ja"
        case .en: "en"
        case .zh, .system: "zh-Hans"
        }
    }
}

extension KaiXAPIClient {
    func updateAppleConsumptionConsent(
        _ payload: KaiXAppleConsumptionConsentUpdate
    ) async throws -> KaiXSettingsDTO {
        struct Wrapper: Codable { let settings: KaiXSettingsDTO }
        let data = try await request("PATCH", "/api/settings", body: payload)
        return try JSONDecoder().decode(Wrapper.self, from: data).settings
    }
}

/// The disclosure is kept beside the wire contract so every UI state and its
/// VoiceOver description use the same reviewed zh-Hans / ja / en meaning.
struct AppleConsumptionConsentCopy: Equatable {
    let sectionTitle: String
    let toggleTitle: String
    let purpose: String
    let dataShared: String
    let optionalAndWithdrawal: String
    let policyVersionLabel: String
    let loading: String
    let enabled: String
    let disabled: String
    let unavailable: String
    let retry: String
    let grantConfirmationTitle: String
    let grantConfirmationMessage: String
    let grantButton: String
    let withdrawConfirmationTitle: String
    let withdrawConfirmationMessage: String
    let withdrawButton: String
    let cancel: String
    let saving: String
    let loadError: String
    let saveError: String
    let policyChanged: String
    let voiceOverToggleHint: String
    let optionalKeyword: String

    init(language: AppLanguage) {
        switch language {
        case .ja:
            sectionTitle = "Appleへの購入利用情報の共有"
            toggleTitle = "返金審査用の購入利用情報を共有"
            purpose = "Appleが返金審査のために情報を求めた場合に限り、購入品が提供・利用されたかを伝え、返金判断を補助します。"
            dataShared = "Appleの購入取引識別子に紐づけて、購入品の提供状況、サンプル提供の有無、および安全に算出できるコイン商品の利用率・返金推奨を送信します。氏名、投稿、メッセージ、位置情報は送信しません。"
            optionalAndWithdrawal = "これは任意です。同意しなくてもMachiを利用できます。いつでもここで撤回でき、撤回後は新たに送信しません（すでにAppleへ送信済みの情報は取り消せません）。"
            policyVersionLabel = "同意ポリシー"
            loading = "サーバーの設定を確認中…"
            enabled = "サーバーで同意済み"
            disabled = "同意していません"
            unavailable = "現在の同意ポリシーをサーバーから確認できないため、この設定は無効です。"
            retry = "再読み込み"
            grantConfirmationTitle = "Appleへの共有に同意しますか？"
            grantConfirmationMessage = "これは任意です。同意すると、Appleから返金審査の照会があった場合に限り、上記の提供・利用情報をAppleへ送信します。いつでも撤回できます。"
            grantButton = "同意して有効にする"
            withdrawConfirmationTitle = "同意を撤回しますか？"
            withdrawConfirmationMessage = "撤回すると、今後のAppleへの購入利用情報の送信を停止します。すでに送信済みの情報は取り消せません。"
            withdrawButton = "同意を撤回"
            cancel = "キャンセル"
            saving = "サーバーへ保存中…"
            loadError = "同意設定を読み込めませんでした。再読み込みしてください。"
            saveError = "変更を保存できませんでした。サーバーで確認済みの以前の設定を保持しています。"
            policyChanged = "同意ポリシーが更新されました。再読み込みして内容を確認してください。"
            optionalKeyword = "任意"
            voiceOverToggleHint = "任意の設定です。変更前に確認画面を表示し、いつでも撤回できます。"
        case .en:
            sectionTitle = "Share purchase-use information with Apple"
            toggleTitle = "Share purchase-use information for refund review"
            purpose = "Only when Apple asks about a refund, Machi can report whether the purchase was delivered or used to help Apple review the request."
            dataShared = "Using Apple's purchase transaction identifier, Machi sends delivery status, whether sample content was provided, and—only when safely calculated for coin packs—usage percentage and a refund preference. It does not send your name, posts, messages, or location."
            optionalAndWithdrawal = "This is optional. You can use Machi without agreeing. You can withdraw here at any time; no new reports are sent afterward (data already sent to Apple cannot be recalled)."
            policyVersionLabel = "Consent policy"
            loading = "Checking the server setting…"
            enabled = "Consent confirmed by server"
            disabled = "Not agreed"
            unavailable = "The current consent policy could not be confirmed with the server, so this setting is disabled."
            retry = "Reload"
            grantConfirmationTitle = "Agree to share with Apple?"
            grantConfirmationMessage = "This is optional. If you agree, Machi sends the delivery and use information described above only when Apple asks during a refund review. You can withdraw at any time."
            grantButton = "Agree and enable"
            withdrawConfirmationTitle = "Withdraw consent?"
            withdrawConfirmationMessage = "Withdrawing stops future purchase-use reports to Apple. It cannot recall information that was already sent."
            withdrawButton = "Withdraw consent"
            cancel = "Cancel"
            saving = "Saving with the server…"
            loadError = "The consent setting could not be loaded. Please reload."
            saveError = "The change could not be saved. The last setting confirmed by the server is still shown."
            policyChanged = "The consent policy changed. Reload and review the updated information."
            optionalKeyword = "optional"
            voiceOverToggleHint = "This setting is optional. A confirmation appears before any change, and you can withdraw at any time."
        case .zh, .system:
            sectionTitle = "向 Apple 共享购买使用信息"
            toggleTitle = "为退款审核共享购买使用信息"
            purpose = "仅当 Apple 因退款审核向我们查询时，Machi 才会说明购买内容是否已交付或使用，帮助 Apple 审核该退款请求。"
            dataShared = "会关联 Apple 的购买交易标识符，发送购买内容的交付状态、是否提供过试用内容；仅在能可靠计算金币包使用情况时，还会发送使用比例和退款建议。不会发送你的姓名、帖子、私信或位置。"
            optionalAndWithdrawal = "此项完全自愿。不同意也可以正常使用 Machi。你可随时在这里撤回；撤回后不再进行新的发送（已发送给 Apple 的信息无法收回）。"
            policyVersionLabel = "同意政策"
            loading = "正在向服务器确认设置…"
            enabled = "服务器已确认同意"
            disabled = "尚未同意"
            unavailable = "暂时无法向服务器确认当前同意政策，因此此设置已停用。"
            retry = "重新加载"
            grantConfirmationTitle = "同意向 Apple 共享吗？"
            grantConfirmationMessage = "此项完全自愿。同意后，仅当 Apple 进行退款审核并向我们查询时，Machi 才会发送上面说明的交付和使用信息。你可以随时撤回。"
            grantButton = "同意并开启"
            withdrawConfirmationTitle = "撤回同意吗？"
            withdrawConfirmationMessage = "撤回后，我们会停止今后向 Apple 发送购买使用信息；已经发送的信息无法收回。"
            withdrawButton = "撤回同意"
            cancel = "取消"
            saving = "正在保存到服务器…"
            loadError = "无法读取同意设置，请重新加载。"
            saveError = "修改未能保存，页面仍保留服务器上次确认的设置。"
            policyChanged = "同意政策已经更新，请重新加载并阅读新内容。"
            optionalKeyword = "自愿"
            voiceOverToggleHint = "这是自愿设置。每次修改前都会再次确认，并可随时撤回。"
        }
    }
}
