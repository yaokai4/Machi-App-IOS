import SwiftUI

/// Merchant-verification intake. This submits a real backend feedback ticket
/// and never mutates local verification flags optimistically.
struct MerchantSettingsView: View {
    @Environment(\.appLanguage) private var language
    let currentUser: UserEntity
    @State private var contact = ""
    @State private var serviceSummary = ""
    @State private var didSubmit = false
    @State private var isSubmitting = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                statusRow
            } header: {
                Text(L("merchantStatus", language))
            }

            Section {
                TextField("联系方式 / 官网 / 社媒", text: $contact, axis: .vertical)
                    .lineLimit(1...3)
                TextField("服务内容、城市和资质说明", text: $serviceSummary, axis: .vertical)
                    .lineLimit(3...6)
                Button(isSubmitting ? "提交中" : applyButtonTitle) {
                    Task { await apply() }
                }
                .disabled(currentUser.merchantVerified || currentUser.isMerchant || didSubmit || isSubmitting)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(L("merchantApplyFooter", language))
            }
        }
        .navigationTitle(L("becomeMerchant", language))
    }

    private var applyButtonTitle: String {
        if currentUser.merchantVerified {
            return L("merchantVerified", language)
        }
        if currentUser.isMerchant {
            return L("merchantPending", language)
        }
        if didSubmit {
            return "已提交审核"
        }
        return L("becomeMerchant", language)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: currentUser.merchantVerified ? "checkmark.seal.fill" : (currentUser.isMerchant ? "hourglass" : "storefront"))
                .font(.title3)
                .foregroundStyle(currentUser.merchantVerified ? .green : (currentUser.isMerchant ? .orange : .secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(applyButtonTitle)
                    .font(.subheadline.weight(.semibold))
                Text(currentUser.merchantVerified ? L("merchantStatusVerified", language) : (didSubmit ? "申请已提交，后台会按资料联系你。" : L("merchantStatusNone", language)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func apply() async {
        let trimmedContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = serviceSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContact.isEmpty, !trimmedSummary.isEmpty else {
            message = "请填写联系方式和服务/资质说明。"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await KaiXAPIClient.shared.submitFeedback(
                category: "merchant_application",
                content: """
                iOS 商家认证申请
                用户: @\(currentUser.username) / \(currentUser.displayName)
                联系方式: \(trimmedContact)
                服务内容与资质: \(trimmedSummary)
                """
            )
            didSubmit = true
            message = "认证申请已提交，后台会人工审核并联系你。"
        } catch {
            message = error.kaixUserMessage
        }
    }
}
