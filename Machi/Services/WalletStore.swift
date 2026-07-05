import Combine
import Foundation
import StoreKit

/// StoreKit 2 driver for Machi Points top-ups (consumable IAP).
///
/// Points are NEVER trusted on-device: after StoreKit returns a transaction we
/// send its signed JWS to the backend (`/api/wallet/topups/apple/verify`),
/// which is the only place points are credited. The server is idempotent on
/// the transaction id, so a retry never double-credits. Per App Store rules
/// the app buys points ONLY through IAP and never shows an external/Stripe
/// top-up. Consumables are not "restored"; the balance is recovered from the
/// server (`walletMe`) after login on any device.
@MainActor
final class WalletStore: ObservableObject {
    enum PurchaseState: Equatable {
        case idle, loading, purchasing, verifying, success, pending, cancelled
        /// StoreKit completed the charge but the server verify call failed.
        /// The transaction stays unfinished and is retried; the UI must say
        /// "payment received, confirming — don't purchase again", never
        /// "failed, try again" (which invites a double charge).
        case verifyFailedPendingCredit
        case failed(String)
    }

    /// How a StoreKit product query resolved, so the UI never shows an
    /// indefinite "loading…" when the App Store can't fulfil it.
    enum StoreStatus: Equatable { case ok, unavailable, noProducts }

    @Published private(set) var wallet: KaiXWalletDTO?
    @Published private(set) var topupProducts: [KaiXWalletTopupProductDTO] = []
    /// StoreKit-only fallback packs built directly from the App Store products
    /// (independent of the server wallet endpoint), so the consumable IAPs are
    /// visible/locatable even to a signed-out user or when the server is down —
    /// App Review must be able to find them. The Buy action still gates on login.
    @Published private(set) var storeFallbackPacks: [KaiXWalletTopupProductDTO] = []
    @Published private(set) var recentEntries: [KaiXWalletLedgerEntryDTO] = []
    @Published private(set) var state: PurchaseState = .idle
    /// StoreKit-localized prices keyed by Apple product id (e.g. "¥6.00").
    @Published private(set) var displayPrices: [String: String] = [:]
    /// True once a load attempt has finished (success OR failure) — lets the UI
    /// stop showing a spinner that would otherwise hang forever.
    @Published private(set) var hasLoaded = false
    /// The backend has no wallet routes (404): a version mismatch, not an error.
    @Published private(set) var walletUnavailable = false
    /// A non-404 wallet load failed and there's no cached balance to fall back on.
    @Published private(set) var walletLoadFailed = false
    /// The wallet endpoint said 401: the viewer isn't signed in (guest /
    /// expired session). Surface a login prompt, never a silent blank page.
    @Published private(set) var walletNeedsLogin = false
    /// Whether StoreKit returned usable products.
    @Published private(set) var storeStatus: StoreStatus = .ok

    private var productsByID: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    private var appAccountToken: UUID?

    var balancePoints: Int { wallet?.balancePoints ?? 0 }
    var displayBalance: String { wallet?.displayBalance ?? "\(balancePoints) 币" }
    var disclaimer: String { wallet?.disclaimer ?? "" }

    /// What the top-up grid renders: the server's packs when available, else the
    /// StoreKit-only fallback so the 9 consumables always show (guest / offline /
    /// server-down) and reviewers can locate them.
    var visibleTopupPacks: [KaiXWalletTopupProductDTO] {
        topupProducts.isEmpty ? storeFallbackPacks : topupProducts
    }

    /// Identifies a points consumable so the membership listener can ignore it.
    nonisolated static func isPointsProduct(_ productID: String) -> Bool { productID.hasPrefix("machi_points_") }

    func start(appAccountToken: UUID? = nil) {
        self.appAccountToken = appAccountToken
        // When the app-level IAPTransactionObserver is running it already
        // owns Transaction.updates/unfinished (and finishing) for points
        // products too — this store then acts as a page-state mirror only,
        // so the same transaction is never double-verified/finished.
        let observerOwnsTransactions = IAPTransactionObserver.shared.isActive
        if updatesTask == nil && !observerOwnsTransactions {
            updatesTask = Task.detached { [weak self] in
                guard let self else { return }
                for await result in Transaction.updates {
                    let txn = self.transaction(from: result)
                    guard WalletStore.isPointsProduct(txn.productID) else { continue }
                    await self.handle(result)
                }
            }
        }
        Task {
            await loadWalletAndProducts()
            if !observerOwnsTransactions {
                await retryUnfinished()
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    func setAppAccountToken(_ token: UUID?) { appAccountToken = token }

    /// Re-run a full load (for a user-tapped "retry").
    func reload() async {
        state = .loading
        await loadWalletAndProducts()
    }

    func loadWalletAndProducts() async {
        state = state == .idle ? .loading : state
        walletLoadFailed = false
        walletNeedsLogin = false
        do {
            let me = try await KaiXAPIClient.shared.walletMe()
            wallet = me.wallet
            topupProducts = me.topupProducts
            recentEntries = me.recentEntries
            walletUnavailable = false
        } catch {
            // A 404 means the backend predates the wallet (version mismatch) —
            // surface "not available", not an error. A 401 means the viewer
            // isn't signed in — show a login prompt, never a silent failure.
            // Any other failure with no cached balance is a transient error
            // the user can retry.
            if Self.isNotFound(error) {
                walletUnavailable = true
            } else if Self.isUnauthorized(error) {
                walletNeedsLogin = true
            } else if wallet == nil {
                walletLoadFailed = true
            }
        }
        let ids = Set(topupProducts.map { $0.resolvedAppleProductID }.filter { !$0.isEmpty })
            .union(WalletStore.knownPackProductIDs)
        // Always probe StoreKit for the pack products — even when the server
        // wallet is unavailable (404) or the viewer is a guest (401) — so the
        // consumables are visible/locatable for the user and App Review. The
        // Buy action gates on login separately; showing the catalog does not.
        if !ids.isEmpty {
            do {
                let products = try await Self.productsWithTimeout(ids: Array(ids), seconds: 12)
                productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
                displayPrices = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0.displayPrice) })
                storeFallbackPacks = products
                    .filter { WalletStore.isPointsProduct($0.id) }
                    .map { Self.fallbackPack(from: $0) }
                    .sorted { $0.totalPoints < $1.totalPoints }
                storeStatus = products.isEmpty ? .noProducts : .ok
            } catch {
                // Network/timeout/StoreKit unavailable — show a retryable notice
                // instead of an indefinite "loading…".
                storeStatus = .unavailable
            }
        }
        hasLoaded = true
        if state == .loading { state = .idle }
    }

    private static func isNotFound(_ error: Error) -> Bool {
        (error as? KaiXAPIError)?.error.code == "http_404"
    }

    private static func isUnauthorized(_ error: Error) -> Bool {
        (error as? KaiXAPIError)?.error.code == "http_401"
    }

    /// Race a StoreKit product query against a timeout so a hung App Store
    /// connection can't leave the top-up section spinning forever.
    private static func productsWithTimeout(ids: [String], seconds: Double) async throws -> [Product] {
        try await withThrowingTaskGroup(of: [Product].self) { group in
            group.addTask { try await Product.products(for: ids) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            defer { group.cancelAll() }
            return try await group.next() ?? []
        }
    }

    /// Refresh just the balance + ledger (after a purchase settles).
    func refreshWallet() async {
        if let me = try? await KaiXAPIClient.shared.walletMe() {
            wallet = me.wallet
            topupProducts = me.topupProducts
            recentEntries = me.recentEntries
        }
    }

    func storeDisplayPrice(for pack: KaiXWalletTopupProductDTO) -> String {
        displayPrices[pack.resolvedAppleProductID] ?? pack.priceLabel ?? ""
    }

    func purchaseTopup(_ pack: KaiXWalletTopupProductDTO) async {
        let pid = pack.resolvedAppleProductID
        guard let product = productsByID[pid] else { state = .failed("product_unavailable"); return }
        state = .purchasing
        do {
            var options: Set<Product.PurchaseOption> = []
            if let appAccountToken { options.insert(.appAccountToken(appAccountToken)) }
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

    // MARK: - private

    private static let knownPackProductIDs: Set<String> = [
        "machi_points_600", "machi_points_1800", "machi_points_3000", "machi_points_6800",
        "machi_points_9800", "machi_points_12800", "machi_points_19800", "machi_points_32800",
        "machi_points_64800",
    ]

    /// Build a display-only top-up pack straight from a StoreKit product, for
    /// when the server pack list is empty (guest / offline / server-down). Coin
    /// amount is parsed from the `machi_points_<n>` id; price is StoreKit's
    /// localized `displayPrice`.
    private static func fallbackPack(from product: Product) -> KaiXWalletTopupProductDTO {
        let coins = Int(product.id.replacingOccurrences(of: "machi_points_", with: "")) ?? 0
        return KaiXWalletTopupProductDTO(
            id: product.id,
            packKey: product.id,
            title: product.displayName,
            subtitle: nil,
            points: coins,
            bonusPoints: 0,
            totalPoints: coins,
            amountCents: 0,
            currency: "",
            priceLabel: product.displayPrice,
            displayPoints: "\(coins) 币",
            appleProductId: product.id,
            iosIapProductId: product.id,
            googleProductId: nil,
            purchasable: true,
            disabledReason: nil
        )
    }

    nonisolated private func transaction(from verification: VerificationResult<Transaction>) -> Transaction {
        switch verification {
        case .verified(let transaction), .unverified(let transaction, _):
            return transaction
        }
    }

    /// On launch, re-verify any points transaction StoreKit still has open
    /// (e.g. the app was killed between purchase and our server verify). The
    /// server is idempotent, so this is always safe.
    private func retryUnfinished() async {
        for await result in Transaction.unfinished {
            let txn = transaction(from: result)
            guard WalletStore.isPointsProduct(txn.productID) else { continue }
            await handle(result)
        }
    }

    /// Returns whether the SERVER credited the transaction.
    @discardableResult
    private func handle(_ verification: VerificationResult<Transaction>) async -> Bool {
        let transaction = transaction(from: verification)
        guard WalletStore.isPointsProduct(transaction.productID) else { return true }
        state = .verifying
        do {
            let resp = try await KaiXAPIClient.shared.verifyAppleWalletTopup(
                productId: transaction.productID,
                transactionId: String(transaction.id),
                originalTransactionId: String(transaction.originalID),
                signedTransaction: verification.jwsRepresentation,
                environment: transaction.environment.rawValue
            )
            wallet = resp.wallet
            await refreshWallet()
            state = .success
            // Only finish AFTER the server credited the points, so a failed
            // verify keeps the transaction for a retry on next launch.
            await transaction.finish()
            return true
        } catch {
            // Do NOT finish — retried via Transaction.unfinished next launch.
            // Apple already charged; only the server credit is missing, so
            // never surface this as a retryable "purchase failed".
            state = .verifyFailedPendingCredit
            return false
        }
    }

    /// Manual "confirm again" for a charge the server hasn't credited yet.
    /// Idempotent server-side; safe to tap repeatedly.
    func reverifyPendingCredit() async {
        state = .verifying
        var anyFailure = false
        for await result in Transaction.unfinished {
            let txn = transaction(from: result)
            guard WalletStore.isPointsProduct(txn.productID) else { continue }
            let credited = await handle(result)
            if !credited { anyFailure = true }
        }
        await refreshWallet()
        state = anyFailure ? .verifyFailedPendingCredit : .idle
    }
}
