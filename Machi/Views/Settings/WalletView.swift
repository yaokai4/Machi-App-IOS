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
                balanceCard
                topupSection
                disclaimerCard
                ledgerSection
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, KaiXTheme.horizontalPadding)
            .kxTabBarSafeBottomPadding()
        }
        .kxPageBackground()
        .navigationTitle(wl("点数钱包", "Wallet", "ポイント"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("done", language)) { dismiss() }
            }
        }
        .task {
            store.start(appAccountToken: currentUser.flatMap { MembershipStore.appAccountToken(for: $0) })
        }
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
            Text(wl("充值点数", "Top up", "チャージ")).font(.headline)
            if store.topupProducts.isEmpty {
                Text(wl("加载中…", "Loading…", "読み込み中…")).font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(store.topupProducts) { pack in
                        topupCard(pack)
                    }
                }
            }
            if case .failed = store.state {
                Text(wl("操作失败，请稍后再试。", "Something went wrong, try again.", "失敗しました。もう一度お試しください。"))
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func topupCard(_ pack: KaiXWalletTopupProductDTO) -> some View {
        let purchasable = pack.purchasable ?? true
        return Button {
            Task { await store.purchaseTopup(pack) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(pack.displayPoints ?? "\(pack.totalPoints) 点").font(.title3.weight(.heavy))
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
        .disabled(!purchasable || isBusy)
        .opacity(purchasable ? 1 : 0.5)
    }

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield").foregroundStyle(KXColor.accent)
            Text(store.disclaimer.isEmpty
                 ? wl("Machi 点数仅可用于 Machi 内的数字资料与平台服务，不可提现、不可转让、不可兑换现金，且不会过期。iOS 端点数充值通过 App Store 完成。",
                       "Machi Points are for Machi digital materials and platform services only — non-refundable as cash, non-transferable, and never expire. On iOS, top-ups go through the App Store.",
                       "Machi ポイントは Machi 内のデジタル資料とサービス専用です。現金化・譲渡不可、有効期限なし。iOS ではチャージは App Store 経由です。")
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
        case "membership_bonus": return wl("会员赠点", "Member bonus", "会員ボーナス")
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
