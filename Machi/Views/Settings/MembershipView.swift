import StoreKit
import SwiftData
import SwiftUI

/// Machi Verified membership page (iOS). Buys membership access through
/// Apple IAP only (no external payment shown — App Store compliance). The
/// server verifies the transaction and is the source of truth; this view
/// mirrors that status and persists it onto the local user so the blue
/// badge + publish-gating update everywhere immediately.
struct MembershipView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var store = MembershipStore()
    @State private var insights: KaiXMembershipInsightsTotals?
    @State private var remoteBenefits: [KaiXMembershipBenefitDTO] = []
    @State private var scrollProxy: ScrollViewProxy?

    static let purchaseAnchor = "membership-purchase-controls"

    let currentUser: UserEntity

    // Fallback benefit list (shown only when the server benefits endpoint is
    // unavailable). Kept honest and aligned with what membership actually grants:
    // priority/quota/review were dropped (over-promised), Machi AI's higher daily
    // limit + Pro model leads.
    private let benefitKeys = [
        "membershipBenefitAI",
        "membershipBenefitBadge",
        "membershipBenefitPublish",
        "membershipBenefitData",
        "membershipBenefitSync",
        "membershipBenefitAudience",
    ]

    private var isActive: Bool { store.membershipActive || currentUser.isVerifiedMember }
    private var isPaymentBusy: Bool {
        store.state == .loading || store.state == .purchasing || store.state == .verifying
    }

    /// Best-known validity end: server truth first, local mirror as fallback.
    private var expiryDate: Date? {
        if let d = MembershipView.parseDate(store.currentPeriodEnd) { return d }
        return currentUser.verifiedMemberUntil
    }

    /// Had a membership that has since lapsed (shows "expired" + repurchase).
    private var isExpired: Bool {
        guard !isActive, let end = expiryDate else { return false }
        return end < Date()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if isActive { activeCard }
                    if isExpired { expiredCard }
                    if isActive, let ins = insights { insightsCard(ins) }
                    if !isActive { lockedInsightsPreview }
                    if !store.plans.isEmpty {
                        planCards
                    } else {
                        // Server returned no plans (guest / offline) — still show
                        // both tiers from StoreKit so title/duration/price stay
                        // visible + locatable for the user and App Review.
                        storeFallbackPlanCards
                    }
                    benefits
                    memberLibraryEntry
                    // Always shown: active members can renew/extend (the server
                    // simply extends the validity period), expired members can
                    // buy again. Membership is a one-time pass, not auto-renew,
                    // so hiding the buy button from active members was a dead end.
                    purchaseControls
                        .id(MembershipView.purchaseAnchor)
                    purchaseDisclosure
                    safetyNotice
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, KaiXTheme.horizontalPadding)
                .kxTabBarSafeBottomPadding()
            }
            .onAppear { scrollProxy = proxy }
        }
        .kxPageBackground()
        .navigationTitle(L("membershipTitle", language))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("done", language)) { dismiss() }
            }
        }
        .task {
            store.start()
            if let response = try? await KaiXAPIClient.shared.membershipBenefits() {
                remoteBenefits = response.benefits
            }
        }
        .task(id: isActive) {
            if isActive {
                insights = try? await KaiXAPIClient.shared.membershipInsights().totals
            }
        }
        .onDisappear {
            // Stop the page-level Transaction.updates listener — without this
            // every visit leaked a permanently-resident listener. The
            // app-level IAPTransactionObserver keeps handling transactions.
            store.stop()
        }
        .onChange(of: store.serverSyncRevision) { _, _ in
            // Persist server truth onto the local user UNCONDITIONALLY (not
            // only when the active flag flips) so an expiry the server
            // reports is mirrored even when the local user still says
            // "member" — badge and compose-gating then update everywhere.
            currentUser.isVerifiedMember = store.membershipActive
            if !store.serverStatus.isEmpty {
                currentUser.membershipStatus = store.serverStatus
            } else if store.membershipActive {
                currentUser.membershipStatus = "active"
            }
            currentUser.verifiedMemberUntil = MembershipView.parseDate(store.currentPeriodEnd)
            try? modelContext.save()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: KXSpacing.sm) {
            HStack(spacing: 6) {
                Text(L("membershipTitle", language)).font(.title2.weight(.bold))
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
            }
            Text(L("membershipSubtitle", language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(priceText).font(.title.weight(.heavy))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KXSpacing.lg)
        .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.softBackground))
    }

    private var priceText: String {
        // StoreKit's localized price is authoritative for what Apple will
        // actually charge; the server label is only a fallback.
        if !store.displayPrice.isEmpty { return store.displayPrice }
        if store.state == .loading {
            return ml("正在获取价格…", "Fetching price…", "価格を取得中…")
        }
        return store.selectedPlan?.displayPriceLabel ?? L("membershipPlanFallback", language)
    }

    private var planCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(store.plans, id: \.canonicalPlanKey) { plan in
                let selected = plan.canonicalPlanKey == store.selectedPlanKey
                Button {
                    store.selectPlan(plan)
                } label: {
                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        HStack(alignment: .top) {
                            Text(plan.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()
                            if plan.recommended {
                                Text(L("recommendedBadge", language))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, KXSpacing.xxs)
                                    .background(Capsule().fill(KXColor.accent))
                            }
                        }
                        Text(plan.subtitle ?? periodLabel(plan))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(store.storeDisplayPrice(for: plan))
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(.primary)
                        if let discount = plan.discountLabel ?? plan.discount_label, !discount.isEmpty {
                            Text(discount).font(.caption.weight(.semibold)).foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: KXRadius.md).fill(selected ? KXColor.accentSoft : KXColor.cardBackground))
                    .overlay(RoundedRectangle(cornerRadius: KXRadius.md).stroke(selected ? KXColor.accent : KXColor.separator, lineWidth: selected ? 1.2 : 0.7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Fallback tier cards built straight from StoreKit when the server returned
    /// no plans (guest / offline), so both tiers (title + duration + price) stay
    /// visible + locatable and selectable.
    @ViewBuilder
    private var storeFallbackPlanCards: some View {
        let tiers: [(product: Product, isYear: Bool)] = {
            var out: [(Product, Bool)] = []
            if let m = store.storeMonthlyProduct { out.append((m, false)) }
            if let y = store.storeYearlyProduct { out.append((y, true)) }
            return out.map { (product: $0.0, isYear: $0.1) }
        }()
        if !tiers.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(tiers, id: \.product.id) { tier in
                    let selected = store.product?.id == tier.product.id
                    Button {
                        store.selectStoreProduct(tier.product)
                    } label: {
                        VStack(alignment: .leading, spacing: KXSpacing.sm) {
                            Text(tier.isYear ? ml("年度会员", "Yearly", "年間メンバー") : ml("月度会员", "Monthly", "月間メンバー"))
                                .font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(2)
                            Text(tier.isYear
                                 ? ml("365 天会员（一次性购买，非自动续费）", "365-day pass · one-time, no auto-renew", "365日パス（一回購入・自動更新なし）")
                                 : ml("30 天会员（一次性购买，非自动续费）", "30-day pass · one-time, no auto-renew", "30日パス（一回購入・自動更新なし）"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(tier.product.displayPrice)
                                .font(.title3.weight(.heavy)).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: KXRadius.md).fill(selected ? KXColor.accentSoft : KXColor.cardBackground))
                        .overlay(RoundedRectangle(cornerRadius: KXRadius.md).stroke(selected ? KXColor.accent : KXColor.separator, lineWidth: selected ? 1.2 : 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func periodLabel(_ plan: KaiXMembershipPlanDTO) -> String {
        // Membership is a NON-renewing one-time pass — never frame it as
        // monthly/yearly subscription billing (that implied auto-renew). Show the
        // access duration as a one-time pass instead.
        let period = plan.billingPeriod ?? plan.billing_period ?? plan.billing_cycle
        let days = period == "yearly" ? 365 : 30
        switch language {
        case .ja: return "\(days)日パス（一回購入・自動更新なし）"
        case .en: return "\(days)-day pass · one-time, no auto-renew"
        default: return "\(days) 天会员（一次性购买，非自动续费）"
        }
    }

    private var activeCard: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(L("membershipActiveTitle", language)).font(.subheadline.weight(.semibold))
                if let until = untilText {
                    Text("\(L("membershipActiveUntil", language)) \(until)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: KXRadius.md).fill(KXColor.accentSoft))
    }

    private var untilText: String? {
        guard let date = expiryDate else { return nil }
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: date)
    }

    /// Shown to previously-paid users whose pass has lapsed: an honest
    /// "expired" state with the purchase entry restored right below.
    private var expiredCard: some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(ml("会员已过期", "Membership expired", "メンバーシップの有効期限が切れています"))
                    .font(.subheadline.weight(.semibold))
                if let until = untilText {
                    Text(ml("有效期至 \(until)，购买后可继续使用会员权益。",
                            "Expired on \(until). Purchase again to keep your member benefits.",
                            "\(until) に期限切れになりました。再購入すると会員特典を継続できます。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: KXRadius.md).fill(KXColor.softBackground))
    }

    private func insightsCard(_ totals: KaiXMembershipInsightsTotals) -> some View {
        let items: [(String, Int)] = [
            ("membershipInsightsViews", totals.total_views),
            ("membershipInsightsLikes", totals.total_likes),
            ("membershipInsightsComments", totals.total_comments),
            ("membershipInsightsBookmarks", totals.total_bookmarks),
            ("membershipInsightsPosts", totals.post_count),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("membershipInsightsTitle", language)).font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(items, id: \.0) { item in
                    VStack(spacing: KXSpacing.xxs) {
                        Text("\(item.1)").font(.title3.weight(.heavy))
                        Text(L(item.0, language)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, KXSpacing.sm)
                    .background(RoundedRectangle(cornerRadius: KXRadius.sm).fill(KXColor.softBackground))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KXSpacing.lg)
        .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KXColor.separator, lineWidth: 0.7))
    }

    /// #3: a locked "content stats" teaser for non-members. Shows blurred sample
    /// numbers behind a lock so the value of the member-only insights is visible
    /// before purchase; tapping scrolls down to the purchase controls.
    private var lockedInsightsPreview: some View {
        let sampleItems: [(String, String)] = [
            ("membershipInsightsViews", "1,280"),
            ("membershipInsightsLikes", "342"),
            ("membershipInsightsComments", "56"),
            ("membershipInsightsBookmarks", "88"),
            ("membershipInsightsPosts", "24"),
        ]
        return Button {
            withAnimation(.easeInOut(duration: 0.35)) {
                scrollProxy?.scrollTo(MembershipView.purchaseAnchor, anchor: .center)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(L("membershipInsightsTitle", language)).font(.headline).foregroundStyle(.primary)
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(ml("会员专属", "Members only", "会員限定"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                        .padding(.horizontal, KXSpacing.sm)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(KXColor.accentSoft))
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(sampleItems, id: \.0) { item in
                        VStack(spacing: KXSpacing.xxs) {
                            Text(item.1)
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(.primary)
                                .blur(radius: 5)
                            Text(L(item.0, language)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, KXSpacing.sm)
                        .background(RoundedRectangle(cornerRadius: KXRadius.sm).fill(KXColor.softBackground))
                    }
                }
                Text(ml("开通会员后可查看你发布内容的浏览、点赞、评论和收藏数据。",
                        "Membership unlocks views, likes, comments and saves on your posts.",
                        "会員になると、あなたの投稿の閲覧・いいね・コメント・保存の統計を見られます。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(KXSpacing.lg)
            .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(KXColor.separator, lineWidth: 0.7))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("membershipBenefitsTitle", language)).font(.headline)
            if !remoteBenefits.isEmpty {
                ForEach(remoteBenefits) { benefit in
                    HStack(alignment: .top, spacing: KXSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                            Text(benefit.title).font(.subheadline.weight(.semibold))
                            Text(benefit.description).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
                ForEach(benefitKeys, id: \.self) { key in
                    HStack(alignment: .top, spacing: KXSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.subheadline)
                        Text(L(key, language)).font(.subheadline)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KXSpacing.lg)
        .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KXColor.separator, lineWidth: 0.7))
    }

    /// Direct door to the member library — the concrete thing the
    /// membership buys, one tap from where it is sold.
    private var memberLibraryEntry: some View {
        NavigationLink {
            GuideMemberResourcesView()
        } label: {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: "books.vertical.fill")
                    .font(.title3)
                    .foregroundStyle(KXColor.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(KXColor.accentSoft))
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(L("memberLibraryTitle", language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(L("memberLibrarySubtitle", language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(KXSpacing.lg)
            .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(KXColor.separator, lineWidth: 0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Buy-button label. Active members see an explicit "renew" framing —
    /// the server simply extends the current validity period.
    private var purchaseCTALabel: String {
        guard let plan = store.selectedPlan else { return L("membershipCTA", language) }
        let base = "\(plan.displayName) · \(store.storeDisplayPrice(for: plan))"
        guard isActive else { return base }
        return "\(ml("续期", "Renew", "延長")) · \(base)"
    }

    @ViewBuilder
    private var purchaseControls: some View {
        VStack(spacing: 10) {
            Button {
                if currentUser.isGuest { GuestGate.shared.requireLogin(L("guestReasonMembership", language)); return }
                Task {
                    await store.purchase(appAccountToken: MembershipStore.appAccountToken(for: currentUser))
                }
            } label: {
                HStack {
                    if store.state == .purchasing || store.state == .verifying {
                        KXSpinner(size: 18, lineWidth: 2.2)
                    }
                    Text(purchaseCTALabel)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(.white)
                .background(Capsule().fill(KXColor.accent))
            }
            // Also disabled while a paid charge awaits server confirmation —
            // buying again there is exactly the double-charge we must prevent.
            .disabled(store.product == nil || isPaymentBusy || store.state == .verifyFailedPendingCredit)
            .opacity(store.product == nil ? 0.6 : 1)

            Button {
                Task { await store.restore() }
            } label: {
                HStack(spacing: 6) {
                    if store.state == .loading {
                        KXSpinner(size: 14, lineWidth: 1.8)
                    }
                    Text(L("membershipRestore", language))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(KXColor.accent)
            }
            .disabled(isPaymentBusy || store.state == .verifyFailedPendingCredit)

            if store.state == .pending {
                Text(L("membershipPurchasePending", language))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.state == .verifyFailedPendingCredit {
                // Honest state: Apple charged, the server hasn't confirmed
                // yet. NEVER phrased as "purchase failed, retry".
                VStack(spacing: KXSpacing.sm) {
                    Text(ml("已完成支付，正在确认到账，请勿重复购买。",
                            "Payment received — we're confirming it with the server. Please don't purchase again.",
                            "お支払いは完了しています。入金確認中のため、再度購入しないでください。"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await store.reverifyPendingCredit() }
                    } label: {
                        Text(ml("重新确认", "Confirm again", "再確認する"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KXColor.accent)
                    }
                }
            }
            if let failure = paymentFailureMessage {
                Text(failure)
                    .font(.caption).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else if store.product == nil {
                Text(store.state == .loading
                     ? ml("正在获取价格…", "Fetching price…", "価格を取得中…")
                     : productUnavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// User-facing wording (no App Store Connect jargon).
    private var productUnavailableMessage: String {
        ml("暂时无法从 App Store 获取该商品，请稍后再试。",
           "This item isn't available from the App Store right now. Please try again later.",
           "現在 App Store からこの商品を取得できません。しばらくしてからもう一度お試しください。")
    }

    private var paymentFailureMessage: String? {
        guard case .failed(let code) = store.state else { return nil }
        switch code {
        case "product_unavailable":
            return productUnavailableMessage
        case "restore_sync_failed":
            return L("membershipRestoreFailed", language)
        case "restore_no_purchases":
            return L("membershipRestoreNoPurchases", language)
        case "restore_verify_failed":
            return ml("找到购买记录，但与服务器确认失败，请稍后重试。",
                      "We found your purchase but couldn't confirm it with the server. Please try again later.",
                      "購入記録は見つかりましたが、サーバーでの確認に失敗しました。しばらくしてからもう一度お試しください。")
        default:
            return L("membershipPurchaseFailed", language)
        }
    }

    /// Local three-language helper for copy not yet in LocalizationService
    /// (same pattern as WalletView.wl / guideText).
    private func ml(_ zh: String, _ en: String, _ ja: String) -> String {
        switch language {
        case .en: return en
        case .ja: return ja
        default: return zh
        }
    }

    /// Non-renewing purchase disclosure: clear validity rules plus functional
    /// Privacy Policy + Terms of Use links on the paywall.
    private var purchaseDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("membershipPurchaseDisclosure", language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("membershipPurchaseNote", language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: KXSpacing.lg) {
                Link(L("termsOfService", language), destination: KaiXBackend.termsOfServiceURL)
                Link(L("privacyPolicy", language), destination: KaiXBackend.privacyPolicyURL)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(KXColor.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: KXRadius.md).fill(KXColor.softBackground))
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: KXSpacing.sm) {
            Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
            Text(L("membershipSafetyNotice", language))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: KXRadius.md).fill(KXColor.softBackground))
    }

    // Delegate to the cached KXDateParsing formatters instead of allocating a
    // fresh ISO8601DateFormatter on each call.
    static func parseDate(_ s: String) -> Date? { KXDateParsing.parse(s) }
}
