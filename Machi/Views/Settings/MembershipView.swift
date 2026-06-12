import SwiftData
import SwiftUI

/// Machi Verified membership page (iOS). Buys the subscription through
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

    let currentUser: UserEntity

    private let benefitKeys = [
        "membershipBenefitBadge",
        "membershipBenefitPublish",
        "membershipBenefitPriority",
        "membershipBenefitData",
        "membershipBenefitQuota",
        "membershipBenefitReview",
        "membershipBenefitSync",
        "membershipBenefitAudience",
    ]

    private var isActive: Bool { store.membershipActive || currentUser.isVerifiedMember }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                if isActive { activeCard }
                if isActive, let ins = insights { insightsCard(ins) }
                if !store.plans.isEmpty { planCards }
                benefits
                memberLibraryEntry
                if !isActive { purchaseControls }
                subscriptionDisclosure
                safetyNotice
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, KaiXTheme.horizontalPadding)
            .kxTabBarSafeBottomPadding()
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
        .onChange(of: store.membershipActive) { _, active in
            // Persist server truth onto the local user so the badge and
            // compose-gating reflect it across the whole app.
            currentUser.isVerifiedMember = active
            currentUser.membershipStatus = active ? "active" : currentUser.membershipStatus
            currentUser.verifiedMemberUntil = MembershipView.parseDate(store.currentPeriodEnd)
            try? modelContext.save()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.softBackground))
    }

    private var priceText: String {
        if !store.displayPrice.isEmpty { return store.displayPrice }
        return store.selectedPlan?.displayPriceLabel ?? "会员套餐"
    }

    private var planCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(store.plans, id: \.canonicalPlanKey) { plan in
                let selected = plan.canonicalPlanKey == store.selectedPlanKey
                Button {
                    store.selectPlan(plan)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(plan.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()
                            if plan.recommended {
                                Text("推荐")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(KXColor.accent))
                            }
                        }
                        Text(plan.subtitle ?? periodLabel(plan))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(plan.displayPriceLabel)
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(.primary)
                        if let discount = plan.discountLabel ?? plan.discount_label, !discount.isEmpty {
                            Text(discount).font(.caption.weight(.semibold)).foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(selected ? KXColor.accentSoft : KXColor.cardBackground))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? KXColor.accent : KXColor.separator, lineWidth: selected ? 1.2 : 0.7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func periodLabel(_ plan: KaiXMembershipPlanDTO) -> String {
        let period = plan.billingPeriod ?? plan.billing_period ?? plan.billing_cycle
        if period == "yearly" { return "包年订阅" }
        if period == "monthly" { return "按月订阅" }
        return "会员套餐"
    }

    private var activeCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
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
        .background(RoundedRectangle(cornerRadius: 14).fill(KXColor.accentSoft))
    }

    private var untilText: String? {
        let raw = store.currentPeriodEnd.isEmpty
            ? (currentUser.verifiedMemberUntil.map { ISO8601DateFormatter().string(from: $0) } ?? "")
            : store.currentPeriodEnd
        guard let date = MembershipView.parseDate(raw) else { return nil }
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: date)
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
                    VStack(spacing: 2) {
                        Text("\(item.1)").font(.title3.weight(.heavy))
                        Text(L(item.0, language)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(KXColor.softBackground))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KXColor.separator, lineWidth: 0.7))
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("membershipBenefitsTitle", language)).font(.headline)
            if !remoteBenefits.isEmpty {
                ForEach(remoteBenefits) { benefit in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.subheadline)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(benefit.title).font(.subheadline.weight(.semibold))
                            Text(benefit.description).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } else {
                ForEach(benefitKeys, id: \.self) { key in
                    HStack(alignment: .top, spacing: 8) {
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
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(KXColor.separator, lineWidth: 0.7))
    }

    /// Direct door to the member library — the concrete thing the
    /// membership buys, one tap from where it is sold.
    private var memberLibraryEntry: some View {
        NavigationLink {
            GuideMemberResourcesView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.title3)
                    .foregroundStyle(KXColor.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(KXColor.accentSoft))
                VStack(alignment: .leading, spacing: 2) {
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
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(KXColor.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(KXColor.separator, lineWidth: 0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var purchaseControls: some View {
        VStack(spacing: 10) {
            Button {
                if currentUser.isGuest { GuestGate.shared.requireLogin(); return }
                Task { await store.purchase() }
            } label: {
                HStack {
                    if store.state == .purchasing || store.state == .verifying {
                        KXSpinner(size: 18, lineWidth: 2.2)
                    }
                    Text(store.selectedPlan.map { "\($0.displayName) · \($0.displayPriceLabel)" } ?? L("membershipCTA", language))
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(.white)
                .background(Capsule().fill(KXColor.accent))
            }
            .disabled(store.product == nil || store.state == .purchasing || store.state == .verifying)
            .opacity(store.product == nil ? 0.6 : 1)

            Button {
                Task { await store.restore() }
            } label: {
                Text(L("membershipRestore", language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KXColor.accent)
            }

            if store.state == .pending {
                Text(L("membershipPurchasePending", language))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if case .failed = store.state {
                Text(L("membershipPurchaseFailed", language))
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    /// Auto-renewable subscription disclosure required by App Store Review
    /// Guideline 3.1.2: renewal terms, cancel instructions, a manage-subscription
    /// link, and functional Privacy Policy + Terms of Use links on the paywall.
    private var subscriptionDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("membershipRenewalDisclosure", language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("membershipCancelNote", language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if let manage = URL(string: "https://apps.apple.com/account/subscriptions") {
                    Link(L("membershipManage", language), destination: manage)
                }
                Link(L("termsOfService", language), destination: KaiXBackend.termsOfServiceURL)
                Link(L("privacyPolicy", language), destination: KaiXBackend.privacyPolicyURL)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(KXColor.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(KXColor.softBackground))
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
            Text(L("membershipSafetyNotice", language))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(KXColor.softBackground))
    }

    static func parseDate(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }
}
