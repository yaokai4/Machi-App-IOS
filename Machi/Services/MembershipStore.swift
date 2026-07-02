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
        /// StoreKit completed the charge but the server verify call failed
        /// (network / backend down). The transaction is left unfinished and
        /// will be retried; the UI must say "payment received, confirming —
        /// do NOT purchase again", never "purchase failed, retry" (which
        /// invites a double charge).
        case verifyFailedPendingCredit
        case failed(String)
    }

    /// App Store Connect product ids. The backend may override these through
    /// `/api/membership/plan`, but the app keeps these fallbacks so a missing
    /// admin field never leaves the paywall unable to load products.
    static let defaultProductID = "machi_yuedu_18"
    static let yearlyProductID = "machi_1niandu_198"
    static let legacyMonthlyProductID = "machi_verified_monthly_cny_10"
    static let legacyYearlyProductID = "machi_verified_yearly_cny_98"
    static let allKnownProductIDs: Set<String> = [
        defaultProductID,
        yearlyProductID,
        legacyMonthlyProductID,
        legacyYearlyProductID,
    ]

    @Published private(set) var product: Product?
    @Published private(set) var plans: [KaiXMembershipPlanDTO] = []
    @Published private(set) var selectedPlanKey: String = ""
    @Published private(set) var state: PurchaseState = .idle
    @Published private(set) var membershipActive = false
    @Published private(set) var currentPeriodEnd: String = ""
    /// Localized store price (e.g. "¥18.00"); falls back to the server plan.
    @Published private(set) var displayPrice: String = ""
    /// Raw membership status string from the server ("active"/"expired"/…),
    /// mirrored onto the local user by the view.
    @Published private(set) var serverStatus: String = ""
    /// Bumped every time the server confirmed a fresh membership snapshot so
    /// views can write server truth back UNCONDITIONALLY — even when the
    /// active flag didn't change (e.g. local user says member, server says
    /// expired, `membershipActive` stays false → no onChange otherwise).
    @Published private(set) var serverSyncRevision = 0

    private var productID: String = MembershipStore.defaultProductID
    private var productsByID: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    /// Begin listening for transaction updates and load product + status.
    ///
    /// When the app-level IAPTransactionObserver is running it already owns
    /// Transaction.updates (and finishing), so this store skips its own
    /// listener and acts as a page-state mirror only — avoids two listeners
    /// double-verifying/finishing the same transaction.
    func start() {
        if updatesTask == nil && !IAPTransactionObserver.shared.isActive {
            updatesTask = Task.detached { [weak self] in
                guard let self else { return }
                for await result in Transaction.updates {
                    // Machi Points consumables are settled by WalletStore against
                    // a different endpoint — never verify/finish them here.
                    if await self.transaction(from: result).productID.hasPrefix("machi_points_") { continue }
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
            // NO `?? products.first` fallback: buying an arbitrary product
            // that happens to load would charge the wrong plan. Better to
            // show "price unavailable" than to sell the wrong thing.
            product = productsByID[selectedProductID] ?? fallbackProduct(for: selectedPlan)
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
            serverStatus = me.membership.status
            serverSyncRevision += 1
        }
    }

    /// StoreKit-localized price for a plan; the server's price label is only
    /// a fallback, so the paywall never shows two conflicting prices for the
    /// same item.
    func storeDisplayPrice(for plan: KaiXMembershipPlanDTO) -> String {
        productsByID[resolvedProductID(for: plan)]?.displayPrice ?? plan.displayPriceLabel
    }

    static func appAccountToken(for user: UserEntity) -> UUID? {
        if let remote = user.remoteId, let uuid = UUID(uuidString: remote) {
            return uuid
        }
        return UUID(uuidString: user.id)
    }

    func purchase(appAccountToken: UUID? = nil) async {
        guard let product else { state = .failed("product_unavailable"); return }
        state = .purchasing
        do {
            var options: Set<Product.PurchaseOption> = []
            if let appAccountToken {
                options.insert(.appAccountToken(appAccountToken))
            }
            let result = try await product.purchase(options: options)
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
        var verifyFailures = 0
        for await result in Transaction.currentEntitlements {
            let transaction = transaction(from: result)
            guard restorableProductIDs.contains(transaction.productID) else { continue }
            restoredAny = true
            let verified = await handle(result, finishTransaction: false)
            if !verified { verifyFailures += 1 }
        }
        await refreshMembership()
        if membershipActive {
            state = .success
        } else if restoredAny && verifyFailures > 0 {
            // We DID find purchases but couldn't confirm them with the
            // server — say so instead of silently going back to idle.
            state = .failed("restore_verify_failed")
        } else if restoredAny {
            state = .idle
        } else {
            state = .failed("restore_no_purchases")
        }
    }

    /// Manual "confirm again" for a charge the server hasn't credited yet:
    /// re-verify every unfinished membership transaction, then re-pull the
    /// authoritative status. Both are idempotent server-side.
    func reverifyPendingCredit() async {
        state = .verifying
        var anyFailure = false
        for await result in Transaction.unfinished {
            let txn = transaction(from: result)
            guard !WalletStore.isPointsProduct(txn.productID) else { continue }
            let verified = await handle(result)
            if !verified { anyFailure = true }
        }
        await refreshMembership()
        if anyFailure {
            state = .verifyFailedPendingCredit
        } else if membershipActive {
            state = .success
        } else {
            state = .idle
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

    /// Returns whether the SERVER confirmed the transaction.
    @discardableResult
    private func handle(_ verification: VerificationResult<Transaction>, finishTransaction: Bool = true) async -> Bool {
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
            if let s = resp.status, !s.isEmpty { serverStatus = s }
            serverSyncRevision += 1
            state = resp.membershipActive ? .success : .idle
            // Only finish once the SERVER gave a definitive answer. If the verify
            // call THREW (network / server down), do NOT finish — StoreKit then
            // re-delivers the transaction and the app auto-retries verify on the
            // next launch (Transaction.updates / currentEntitlements), so a paid
            // subscription is never stuck "charged but never granted".
            if finishTransaction {
                await transaction.finish()
            }
            return true
        } catch {
            // Apple already completed the charge; only the server confirmation
            // is missing. NEVER report this as "purchase failed, retry" — that
            // invites a double charge. The transaction stays unfinished and is
            // retried by the app-level observer / next launch / the manual
            // "confirm again" button.
            state = .verifyFailedPendingCredit
            return false
        }
    }
}
