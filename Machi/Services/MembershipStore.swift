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

    /// App Store Connect product ids. The backend may override these through
    /// `/api/membership/plan`, but the app keeps these fallbacks so a missing
    /// admin field never leaves the paywall unable to load products.
    static let defaultProductID = "machi_verified_monthly_cny_10"
    static let yearlyProductID = "machi_verified_yearly_cny_98"
    static let allKnownProductIDs: Set<String> = [defaultProductID, yearlyProductID]

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
        state = state == .idle ? .loading : state
        if let planResp = try? await KaiXAPIClient.shared.membershipPlan() {
            let remotePlans = planResp.plans ?? planResp.items ?? planResp.plan.map { [$0] } ?? []
            if !remotePlans.isEmpty {
                plans = remotePlans
                if selectedPlanKey.isEmpty {
                    selectedPlanKey = (remotePlans.first(where: { $0.recommended }) ?? remotePlans.first)?.canonicalPlanKey ?? ""
                }
            }
            if let selected = selectedPlan {
                productID = resolvedProductID(for: selected)
                displayPrice = selected.displayPriceLabel
            } else if let pid = planResp.apple_product_id, !pid.isEmpty {
                productID = pid
            }
        }
        do {
            let ids = Set((plans.map { resolvedProductID(for: $0) } + [productID] + Array(Self.allKnownProductIDs)).filter { !$0.isEmpty })
            let products = try await Product.products(for: Array(ids))
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            let selectedProductID = selectedPlan.map { resolvedProductID(for: $0) } ?? productID
            product = productsByID[selectedProductID] ?? fallbackProduct(for: selectedPlan) ?? products.first
            productID = product?.id ?? selectedProductID
            if let p = product {
                displayPrice = p.displayPrice
                if state == .loading { state = .idle }
            } else if state == .loading {
                state = .failed("product_unavailable")
            }
        } catch {
            // Leave product nil — the UI still shows the plan price and a
            // disabled buy button rather than crashing.
            if state == .loading {
                state = .failed("product_unavailable")
            }
        }
        await refreshMembership()
    }

    var selectedPlan: KaiXMembershipPlanDTO? {
        plans.first { $0.canonicalPlanKey == selectedPlanKey } ?? plans.first
    }

    func selectPlan(_ plan: KaiXMembershipPlanDTO) {
        selectedPlanKey = plan.canonicalPlanKey
        productID = resolvedProductID(for: plan)
        product = productsByID[productID]
        displayPrice = product?.displayPrice ?? plan.displayPriceLabel
        if product == nil {
            state = .failed("product_unavailable")
        } else if case .failed(let code) = state, code == "product_unavailable" {
            state = .idle
        }
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
        do {
            // This is Apple's real restore/authentication surface. Simulator
            // StoreKit testing may show a local test account UI; TestFlight and
            // App Store builds use the user's Apple media account.
            try await AppStore.sync()
        } catch {
            state = .failed("restore_sync_failed")
            return
        }

        let restorableProductIDs = knownProductIDsForRestore()
        var restoredAny = false
        for await result in Transaction.all {
            let transaction = transaction(from: result)
            guard restorableProductIDs.contains(transaction.productID) else { continue }
            restoredAny = true
            await handle(result, finishTransaction: false)
        }
        await refreshMembership()
        if membershipActive {
            state = .success
        } else if restoredAny {
            state = .idle
        } else {
            state = .failed("restore_no_purchases")
        }
    }

    // MARK: - private

    private func resolvedProductID(for plan: KaiXMembershipPlanDTO) -> String {
        if let explicit = plan.explicitAppleProductID {
            return explicit
        }

        let key = plan.canonicalPlanKey.lowercased()
        if key == "machi_verified_yearly" || key == "machi_verified_annual" || key.contains("year") || key.contains("annual") {
            return Self.yearlyProductID
        }
        if key == "machi_verified_monthly" || key.contains("month") {
            return Self.defaultProductID
        }

        let period = (plan.billingPeriod ?? plan.billing_period ?? plan.billing_cycle ?? "").lowercased()
        if period == "yearly" || period == "annual" || plan.intervalCount == 12 || plan.interval_count == 12 {
            return Self.yearlyProductID
        }
        return Self.defaultProductID
    }

    private func fallbackProduct(for plan: KaiXMembershipPlanDTO?) -> Product? {
        guard let plan else { return productsByID[Self.defaultProductID] }
        let fallbackID = resolvedProductID(for: plan)
        return productsByID[fallbackID]
    }

    private func knownProductIDsForRestore() -> Set<String> {
        Set(productsByID.keys)
            .union(Self.allKnownProductIDs)
            .union(plans.map { resolvedProductID(for: $0) })
    }

    private func transaction(from verification: VerificationResult<Transaction>) -> Transaction {
        switch verification {
        case .verified(let transaction), .unverified(let transaction, _):
            return transaction
        }
    }

    private func handle(_ verification: VerificationResult<Transaction>, finishTransaction: Bool = true) async {
        // Send the signed JWS regardless of local verification — the
        // server re-verifies and is the source of truth.
        let transaction = transaction(from: verification)
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
