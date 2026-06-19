import Combine
import Foundation
import StoreKit

/// StoreKit 2 driver for Machi Verified purchases.
///
/// The purchase is NEVER trusted on-device: after StoreKit returns a
/// transaction we send its signed JWS to the backend
/// (`/api/payments/apple/verify`), which is the only place membership is
/// actually opened/extended. The backend is idempotent on the
/// transaction id, so restore / re-verify never double-extends.
///
/// Per App Store rules the iOS app buys digital membership ONLY through
/// IAP — it never shows WeChat/Alipay or any external payment for the
/// in-app entitlement. Membership is treated as a paid validity period:
/// buying one month extends one month, buying one year extends one year.
@MainActor
final class MembershipStore: ObservableObject {
    enum PurchaseState: Equatable {
        case idle, loading, purchasing, verifying, success, pending, cancelled
        case failed(String)
    }

    /// Default one-month product id; overridden by the server's configured id when
    /// `/api/membership/plan` is reachable.
    static let defaultProductID = "machi_verified_monthly_cny_10"

    @Published private(set) var product: Product?
    @Published private(set) var plans: [KaiXMembershipPlanDTO] = []
    @Published private(set) var selectedPlanKey: String = ""
    @Published private(set) var state: PurchaseState = .idle
    @Published private(set) var membershipActive = false
    @Published private(set) var currentPeriodEnd: String = ""
    /// Localized store price (e.g. "¥10.00"); falls back to the server plan.
    @Published private(set) var displayPrice: String = ""

    private var productID: String = MembershipStore.defaultProductID
    private var productsByID: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    /// Begin listening for transaction updates and load product + status.
    func start() {
        if updatesTask == nil {
            updatesTask = Task.detached { [weak self] in
                guard let self else { return }
                for await result in Transaction.updates {
                    await self.handle(result)
                }
            }
        }
        Task { await loadProductAndStatus() }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    func loadProductAndStatus() async {
        // Prefer the server-configured Apple product id + plan price.
        if let planResp = try? await KaiXAPIClient.shared.membershipPlan() {
            let remotePlans = planResp.plans ?? planResp.items ?? planResp.plan.map { [$0] } ?? []
            if !remotePlans.isEmpty {
                plans = remotePlans
                if selectedPlanKey.isEmpty {
                    selectedPlanKey = (remotePlans.first(where: { $0.recommended }) ?? remotePlans.first)?.canonicalPlanKey ?? ""
                }
            }
            if let selected = selectedPlan {
                productID = selected.appleProductID
                displayPrice = selected.displayPriceLabel
            } else if let pid = planResp.apple_product_id, !pid.isEmpty {
                productID = pid
            }
        }
        do {
            let ids = Set((plans.map { $0.appleProductID } + [productID]).filter { !$0.isEmpty })
            let products = try await Product.products(for: Array(ids))
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            product = productsByID[productID] ?? products.first
            if let p = product { displayPrice = p.displayPrice }
        } catch {
            // Leave product nil — the UI still shows the plan price and a
            // disabled buy button rather than crashing.
        }
        await refreshMembership()
    }

    var selectedPlan: KaiXMembershipPlanDTO? {
        plans.first { $0.canonicalPlanKey == selectedPlanKey } ?? plans.first
    }

    func selectPlan(_ plan: KaiXMembershipPlanDTO) {
        selectedPlanKey = plan.canonicalPlanKey
        productID = plan.appleProductID
        product = productsByID[productID]
        displayPrice = product?.displayPrice ?? plan.displayPriceLabel
    }

    /// Pull the authoritative membership status from the backend.
    func refreshMembership() async {
        if let me = try? await KaiXAPIClient.shared.membershipMe() {
            membershipActive = me.membership.is_active
            currentPeriodEnd = me.membership.current_period_end ?? ""
        }
    }

    func purchase() async {
        guard let product else { state = .failed("product_unavailable"); return }
        state = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await handle(verification)
            case .pending:
                state = .pending
            case .userCancelled:
                state = .cancelled
            @unknown default:
                state = .failed("unknown")
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Restore purchases: sync with the App Store, then re-verify current
    /// entitlements with the backend. The server remains the source of truth
    /// for active/expired validity periods.
    func restore() async {
        state = .loading
        try? await AppStore.sync()
        for await result in Transaction.currentEntitlements {
            await handle(result, finishTransaction: false)
        }
        await refreshMembership()
        state = membershipActive ? .success : .idle
    }

    // MARK: - private

    private func handle(_ verification: VerificationResult<Transaction>, finishTransaction: Bool = true) async {
        // Send the signed JWS regardless of local verification — the
        // server re-verifies and is the source of truth.
        let transaction: Transaction
        switch verification {
        case .verified(let t): transaction = t
        case .unverified(let t, _): transaction = t
        }
        state = .verifying
        do {
            let resp = try await KaiXAPIClient.shared.verifyAppleTransaction(
                productId: transaction.productID,
                transactionId: String(transaction.id),
                originalTransactionId: String(transaction.originalID),
                signedTransaction: verification.jwsRepresentation,
                environment: transaction.environment.rawValue
            )
            membershipActive = resp.membershipActive
            currentPeriodEnd = resp.currentPeriodEnd ?? ""
            state = resp.membershipActive ? .success : .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
        // Always finish so StoreKit stops re-delivering the transaction,
        // even if our server call failed (it will be retried on next launch
        // via Transaction.currentEntitlements / restore).
        if finishTransaction {
            await transaction.finish()
        }
    }
}
