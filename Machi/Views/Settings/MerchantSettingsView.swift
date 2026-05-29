import SwiftUI
import SwiftData

/// Placeholder for the merchant-verification flow. Wires the existing
/// `isMerchant` / `merchantVerified` fields on UserEntity to a single
/// UI surface so users can register interest before payments /
/// review tooling lands. Real verification will plug in here in a
/// later milestone (back-of-house tooling, document upload, …).
struct MerchantSettingsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.modelContext) private var modelContext
    let currentUser: UserEntity
    @State private var didSubmit = false

    var body: some View {
        Form {
            Section {
                statusRow
            } header: {
                Text(L("merchantStatus", language))
            }

            Section {
                Button(applyButtonTitle) {
                    apply()
                }
                .disabled(currentUser.merchantVerified)
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
                Text(currentUser.merchantVerified ? L("merchantStatusVerified", language) : L("merchantStatusNone", language))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func apply() {
        currentUser.isMerchant = true
        try? modelContext.save()
        didSubmit = true
    }
}
