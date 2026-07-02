import SwiftData
import SwiftUI

/// Machi Points wallet (iOS). Tops up points through Apple IAP only — no
/// external/Stripe top-up is ever shown (App Store compliance). The server
/// verifies each transaction and is the source of truth for the balance; this
/// view mirrors it. Points are internal scrip: not cash, not transferable, and
/// they never expire.
struct WalletView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = WalletStore()

    /// Optional: when present we pass its UUID as the StoreKit appAccountToken
    /// (defense-in-depth linking the IAP to this user). The bearer token already
    /// identifies the account server-side, so top-up works without it too.
    var currentUser: UserEntity?

    private var isBusy: Bool {
        store.state == .loading || store.state == .purchasing || store.state == .verifying
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if store.walletNeedsLogin {
                    needsLoginCard
                } else if store.walletUnavailable {
                    unsupportedCard
                } else if store.walletLoadFailed {
                    errorCard
                } else {
                    balanceCard
                    topupSection
                    disclaimerCard
                    ledgerSection
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, KaiXTheme.horizontalPadding)
            .kxTabBarSafeBottomPadding()
        }
        .kxPageBackground()
        .navigationTitle(wl("Machi 币钱包", "Wallet", "Machi コイン"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("done", language)) { dismiss() }
            }
        }
        .task {
            store.start(appAccountToken: currentUser.flatMap { MembershipStore.appAccountToken(for: $0) })
        }
        .onDisappear { store.stop() }
    }

    // MARK: - unsupported / error states

    private var unsupportedCard: some View {
        stateCard(
            icon: "exclamationmark.triangle",
            title: wl("当前版本暂未开放 Machi 币钱包", "Wallet isn't available yet", "ウォレットは未対応です"),
            message: wl("请稍后再试，或更新到最新版本。", "Please try again later or update the app.", "後ほど、またはアプリを更新してお試しください。")
        )
    }

    private var errorCard: some View {
        stateCard(
            icon: "wifi.exclamationmark",
            title: wl("钱包加载失败", "Couldn't load your wallet", "ウォレットを読み込めません"),
            message: wl("网络或服务暂时不可用，请重试。", "Network or service is temporarily unavailable.", "ネットワークまたはサービスが一時的に利用できません。")
        )
    }

    /// 401 from the wallet endpoint: guest / expired session. Guide the user
    /// to sign in instead of failing silently.
    private var needsLoginCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text(wl("登录后可使用 Machi 币钱包", "Sign in to use your wallet", "ログインするとウォレットを利用できます"))
                .font(.headline).multilineTextAlignment(.center)
            Text(wl("登录后即可查看余额、充值和消费记录。", "Sign in to see your balance, top up, and view activity.", "ログインすると残高の確認・チャージ・履歴の表示ができます。"))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                GuestGate.shared.requireLogin()
            } label: {
                Label(wl("去登录", "Sign in", "ログインする"), systemImage: "person.crop.circle")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KXColor.separator, lineWidth: 0.8))
    }

    private func stateCard(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(.secondary)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                Task { await store.reload() }
            } label: {
                Label(wl("重试", "Retry", "再試行"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.state == .loading)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KXColor.separator, lineWidth: 0.8))
    }

    // MARK: - balance

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.orange)
                Text(wl("当前余额", "Balance", "残高")).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(store.displayBalance).font(.system(size: 34, weight: .heavy))
            if store.state == .verifying {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(wl("正在确认到账…", "Confirming…", "確認中…")).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.accentSoft))
    }

    // MARK: - top-up

    private var topupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(wl("充值 Machi 币", "Top up", "チャージ")).font(.headline)
            if !store.hasLoaded {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(wl("加载中…", "Loading…", "読み込み中…")).font(.caption).foregroundStyle(.secondary)
                }
            } else if store.topupProducts.isEmpty {
                Text(wl("暂无可充值套餐，请稍后再试。", "No top-up packs available right now.", "現在チャージできるパックはありません。"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(store.topupProducts) { pack in
                        topupCard(pack)
                    }
                }
                if let notice = storeStatusNotice {
                    HStack(spacing: 6) {
                        Text(notice).font(.caption).foregroundStyle(.secondary)
                        Button(wl("重试", "Retry", "再試行")) { Task { await store.reload() } }
                            .font(.caption).disabled(store.state == .loading)
                    }
                }
            }
            if store.state == .verifyFailedPendingCredit {
                // Honest state: Apple charged, the server hasn't credited
                // yet. NEVER phrased as "purchase failed, retry".
                VStack(alignment: .leading, spacing: 6) {
                    Text(wl("已完成支付，正在确认到账，请勿重复购买。",
                            "Payment received — we're confirming it with the server. Please don't purchase again.",
                            "お支払いは完了しています。入金確認中のため、再度購入しないでください。"))
                        .font(.caption).foregroundStyle(.orange)
                    Button(wl("重新确认", "Confirm again", "再確認する")) {
                        Task { await store.reverifyPendingCredit() }
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(isBusy)
                }
            }
            if case .failed = store.state {
                Text(wl("操作失败，请稍后再试。", "Something went wrong, try again.", "失敗しました。もう一度お試しください。"))
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    /// A retryable notice when StoreKit couldn't price the packs (so prices
    /// fall back to the server label) — never an indefinite spinner.
    private var storeStatusNotice: String? {
        switch store.storeStatus {
        case .ok: return nil
        case .unavailable: return wl("App Store 暂不可用，价格可能不准确。", "App Store is unavailable; prices may be approximate.", "App Store が利用できません。価格は概算です。")
        case .noProducts: return wl("充值套餐尚未在 App Store 上架。", "Top-up packs aren't on the App Store yet.", "チャージパックはまだ App Store に登録されていません。")
        }
    }

    private func topupCard(_ pack: KaiXWalletTopupProductDTO) -> some View {
        let purchasable = pack.purchasable ?? true
        return Button {
            Task { await store.purchaseTopup(pack) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(pack.displayPoints ?? "\(pack.totalPoints) 币").font(.title3.weight(.heavy))
                if let sub = pack.subtitle, !sub.isEmpty {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 2)
                Text(store.storeDisplayPrice(for: pack))
                    .font(.headline)
                    .foregroundStyle(KXColor.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(KXColor.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(KXColor.separator, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        // Also disabled while a paid charge awaits server confirmation —
        // buying again there is exactly the double-charge we must prevent.
        .disabled(!purchasable || isBusy || store.state == .verifyFailedPendingCredit)
        .opacity(purchasable ? 1 : 0.5)
    }

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield").foregroundStyle(KXColor.accent)
            Text(store.disclaimer.isEmpty
                 ? wl("Machi 币仅可用于 Machi 内的数字资料与平台服务，不可提现、不可转让、不可兑换现金，且不会过期。iOS 端充值通过 App Store 完成。",
                       "Machi Coins are for Machi digital materials and platform services only — non-refundable as cash, non-transferable, and never expire. On iOS, top-ups go through the App Store.",
                       "Machi コインは Machi 内のデジタル資料とサービス専用です。現金化・譲渡不可、有効期限なし。iOS ではチャージは App Store 経由です。")
                 : store.disclaimer)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(KXColor.softBackground))
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(wl("最近记录", "Recent activity", "最近の記録")).font(.headline)
            if store.recentEntries.isEmpty {
                Text(wl("暂无记录。", "No activity yet.", "記録はありません。")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(store.recentEntries) { entry in
                    HStack {
                        Text(ledgerLabel(entry.entryType)).font(.subheadline)
                        Spacer()
                        Text(entry.displayDelta ?? "\(entry.pointsDelta)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(entry.pointsDelta >= 0 ? .green : .secondary)
                    }
                    .padding(.vertical, 6)
                    Divider().opacity(0.4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(KXColor.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(KXColor.separator, lineWidth: 0.8))
    }

    private func ledgerLabel(_ entryType: String) -> String {
        switch entryType {
        case "topup": return wl("充值", "Top-up", "チャージ")
        case "bonus": return wl("充值赠送", "Bonus", "ボーナス")
        case "spend": return wl("购买资料", "Purchase", "購入")
        case "refund_credit": return wl("退款返还", "Refund", "返金")
        case "admin_adjustment": return wl("客服调整", "Adjustment", "調整")
        case "membership_bonus": return wl("会员赠币", "Member bonus", "会員ボーナス")
        default: return entryType
        }
    }

    private func wl(_ zh: String, _ en: String, _ ja: String) -> String {
        switch language {
        case .en: return en
        case .ja: return ja
        default: return zh
        }
    }
}
