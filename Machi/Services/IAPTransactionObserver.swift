import Foundation
import os
import StoreKit

/// App-level StoreKit 2 transaction pipeline. Started once after login (from
/// MainTabView) so a paid transaction is re-verified with the backend even if
/// the user never re-opens the membership / wallet pages — previously an
/// unfinished transaction could stay "charged but never credited" forever
/// unless the right page happened to be visited.
///
/// Security model (unchanged): the SERVER is the only source of truth. A
/// transaction is finished ONLY after the backend confirmed it; if verify
/// fails the transaction stays unfinished and StoreKit re-delivers it, so a
/// paid purchase can never be silently dropped.
///
/// Routing: `machi_points_*` consumables settle against the wallet top-up
/// endpoint; `machi_guide_*` non-consumables settle against the guide
/// purchase endpoint (`/api/payments/apple/guide-verify`); everything else
/// is a membership product and settles against `/api/payments/apple/verify`.
/// All endpoints are idempotent per transaction id, so re-verifying is
/// always safe. NAMING CONVENTION: every single-product guide IAP id MUST
/// start with `machi_guide_` — an id outside both prefixes lands on the
/// membership endpoint, is rejected (`product_not_membership`) and the
/// transaction stays unfinished forever.
@MainActor
final class IAPTransactionObserver {
    static let shared = IAPTransactionObserver()

    /// True while this observer owns `Transaction.unfinished` +
    /// `Transaction.updates`. Page stores (MembershipStore / WalletStore)
    /// check this to skip their own listeners, avoiding a double
    /// verify/finish race for the same transaction.
    private(set) var isActive = false

    private var updatesTask: Task<Void, Never>?

    private init() {}

    /// Idempotent — safe to call on every login / account switch.
    func start() {
        guard updatesTask == nil else { return }
        isActive = true
        updatesTask = Task.detached { [weak self] in
            // First drain everything StoreKit still has open (e.g. the app
            // was killed between the charge and our server verify), then stay
            // resident for transactions that arrive while the app runs
            // (Ask to Buy approvals, purchases from other devices, …).
            await self?.verifyUnfinished()
            for await result in Transaction.updates {
                if Task.isCancelled { return }
                await self?.verify(result)
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        isActive = false
    }

    /// Re-run server verification for every transaction StoreKit still has
    /// open. The backend is idempotent per transaction id, so calling this at
    /// any time (login, manual "confirm again" button) is always safe.
    func verifyUnfinished() async {
        for await result in Transaction.unfinished {
            await verify(result)
        }
    }

    private func verify(_ verification: VerificationResult<Transaction>) async {
        // Send the signed JWS regardless of the local verification result —
        // the server re-verifies the signature chain and is the source of
        // truth for what gets credited.
        let transaction = unwrap(verification)
        do {
            if WalletStore.isPointsProduct(transaction.productID) {
                _ = try await KaiXAPIClient.shared.verifyAppleWalletTopup(
                    productId: transaction.productID,
                    transactionId: String(transaction.id),
                    originalTransactionId: String(transaction.originalID),
                    signedTransaction: verification.jwsRepresentation,
                    environment: transaction.environment.rawValue
                )
            } else if Self.isGuideProduct(transaction.productID) {
                _ = try await KaiXAPIClient.shared.verifyAppleGuidePurchase(
                    productId: transaction.productID,
                    transactionId: String(transaction.id),
                    originalTransactionId: String(transaction.originalID),
                    signedTransaction: verification.jwsRepresentation,
                    environment: transaction.environment.rawValue
                )
            } else {
                _ = try await KaiXAPIClient.shared.verifyAppleTransaction(
                    productId: transaction.productID,
                    transactionId: String(transaction.id),
                    originalTransactionId: String(transaction.originalID),
                    signedTransaction: verification.jwsRepresentation,
                    environment: transaction.environment.rawValue
                )
            }
            // Finish ONLY after the server gave a definitive answer. On
            // failure the transaction is deliberately left unfinished and is
            // retried on the next launch / next verifyUnfinished() pass.
            await transaction.finish()
            // 广播结算成功:观察者激活时页面 store(WalletStore 等)只是镜像,
            // Ask to Buy 事后批准若无此通知,已打开的钱包/会员页会停在 .pending、
            // 余额陈旧。userInfo 只带 productID,绝不携带 JWS/token。
            NotificationCenter.default.post(
                name: .kaixIAPTransactionSettled,
                object: nil,
                userInfo: ["productID": transaction.productID]
            )
        } catch {
            // Never finish on failure — a paid transaction must survive until
            // the server has actually credited it. StoreKit re-delivers it, so
            // it's not lost; log it (no JWS/token) so a stuck "charged but
            // pending" transaction is observable in diagnostics. A user-visible
            // "purchase confirming…" toast for these observer-owned background
            // transactions still needs UI wiring (deferred).
            Logger(subsystem: "com.yaokai.kaizi", category: "iap")
                .warning("Apple transaction verify failed for product \(transaction.productID, privacy: .public); left unfinished for retry")
            // Surface it: a UI layer shows a "purchase confirming, retries
            // automatically" toast so an observer-owned background transaction
            // isn't silently stuck pending. No JWS/token in the notification.
            NotificationCenter.default.post(name: .kaixIAPVerificationPending, object: nil)
        }
    }

    /// Single-product guide IAP ids share the `machi_guide_` prefix (enforced
    /// as a naming convention server-side in GUIDE_HERO_IAP_PRODUCTS).
    nonisolated static func isGuideProduct(_ productID: String) -> Bool {
        productID.hasPrefix("machi_guide_")
    }

    nonisolated private func unwrap(_ verification: VerificationResult<Transaction>) -> Transaction {
        switch verification {
        case .verified(let transaction), .unverified(let transaction, _):
            return transaction
        }
    }
}
