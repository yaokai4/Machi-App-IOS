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
        case failed(String)
    }

    /// How a StoreKit product query resolved, so the UI never shows an
    /// indefinite "loading…" when the App Store can't fulfil it.
    enum StoreStatus: Equatable { case ok, unavailable, noProducts }

    @Published private(set) var wallet: KaiXWalletDTO?
    @Published private(set) var topupProducts: [KaiXWalletTopupProductDTO] = []
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
    /// Whether StoreKit returned usable products.
    @Published private(set) var storeStatus: StoreStatus = .ok

    private var productsByID: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    private var appAccountToken: UUID?

    var balancePoints: Int { wallet?.balancePoints ?? 0 }
    var displayBalance: String { wallet?.displayBalance ?? "\(balancePoints) 币" }
    var disclaimer: String { wallet?.disclaimer ?? "" }

    /// Identifies a points consumable so the membership listener can ignore it.
    nonisolated static func isPointsProduct(_ productID: String) -> Bool { productID.hasPrefix("machi_points_") }

    func start(appAccountToken: UUID? = nil) {
        self.appAccountToken = appAccountToken
        if updatesTask == nil {
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
            await retryUnfinished()
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
        do {
            let me = try await KaiXAPIClient.shared.walletMe()
            wallet = me.wallet
            topupProducts = me.topupProducts
            recentEntries = me.recentEntries
            walletUnavailable = false
        } catch {
            // A 404 means the backend predates the wallet (version mismatch) —
            // surface "not available", not an error. Any other failure with no
            // cached balance is a transient error the user can retry.
            if Self.isNotFound(error) {
                walletUnavailable = true
            } else if wallet == nil {
                walletLoadFailed = true
            }
        }
        let ids = Set(topupProducts.map { $0.resolvedAppleProductID }.filter { !$0.isEmpty })
            .union(WalletStore.knownPackProductIDs)
        if walletUnavailable {
            storeStatus = .ok  // don't probe the store for a wallet we can't credit
        } else if !ids.isEmpty {
            do {
                let products = try await Self.productsWithTimeout(ids: Array(ids), seconds: 12)
                productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
                displayPrices = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0.displayPrice) })
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

    private func handle(_ verification: VerificationResult<Transaction>) async {
        let transaction = transaction(from: verification)
        guard WalletStore.isPointsProduct(transaction.productID) else { return }
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
        } catch {
            // Do NOT finish — retried via Transaction.unfinished next launch.
            state = .failed(error.localizedDescription)
        }
    }
}
