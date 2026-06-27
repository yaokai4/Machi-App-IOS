import SwiftData
import SwiftUI

struct MyWorkbenchView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var postStore: PostStore
    @StateObject private var viewModel = ProfileViewModel()
    @State private var didEnter = false
    @State private var summary: KaiXWorkbenchSummaryDTO?
    @State private var didLoadSummary = false

    let currentUser: UserEntity
    var onPublishedListing: ((String) -> Void)?

    private var currentRegionCode: String {
        RegionStore.shared.current?.regionCode ?? currentUser.currentRegionCode
    }

    private var currentRegionDisplay: String {
        if let region = RegionStore.shared.current ?? KaiXRegionDirectory.resolve(regionCode: currentUser.currentRegionCode) {
            return "\(region.countryEmoji) \(region.cityName)"
        }
        return currentUser.location.isEmpty ? L("pickRegion", language) : currentUser.location
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 15) {
                hero
                    .kxWorkbenchEntrance(didEnter, index: 0)
                overviewCard
                    .kxWorkbenchEntrance(didEnter, index: 1)
                publishSection
                    .kxWorkbenchEntrance(didEnter, index: 2)
                serviceSection
                    .kxWorkbenchEntrance(didEnter, index: 3)
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 12)
            .kxTabBarSafeBottomPadding()
        }
        .navigationTitle(L("workbenchTitle", language))
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .task {
            await viewModel.load(context: modelContext, user: currentUser, postStore: postStore)
        }
        .task {
            // One-shot summary load (guarded so re-appearing doesn't refetch).
            guard !didLoadSummary, !currentUser.isGuest else { return }
            didLoadSummary = true
            summary = try? await KaiXAPIClient.shared.workbenchSummary()
        }
        .refreshable {
            summary = try? await KaiXAPIClient.shared.workbenchSummary()
        }
        .onAppear {
            withAnimation(.snappy(duration: 0.38)) {
                didEnter = true
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            AvatarView(user: currentUser, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(currentUser.displayName)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    KXUserBadge(user: currentUser)
                }
                Text("@\(currentUser.username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    WorkbenchPill("\(viewModel.postCount) \(L("posts", language))")
                    WorkbenchPill(currentUser.isVerifiedMember ? L("membershipStatusActive", language) : L("workbenchMemberStandard", language))
                    WorkbenchPill(currentRegionDisplay)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .kxGlassSurface(radius: 22, elevated: true)
    }

    /// 经营概览 / 今日待处理 — all counts from /api/my/workbench/summary.
    private var overviewCard: some View {
        let s = summary ?? KaiXWorkbenchSummaryDTO()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KXColor.accent)
                Text(KXListingCopy.pickText(language, "今日待处理", "本日の対応", "To handle"))
                    .font(.subheadline.weight(.bold))
                Spacer()
                if s.pendingTotal > 0 {
                    Text("\(s.pendingTotal)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, 5)
                        .background(KXColor.heat, in: Capsule())
                } else {
                    Text(KXListingCopy.pickText(language, "暂无待处理", "対応待ちなし", "All clear"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if s.pendingTotal > 0 {
                KXFadingHScroll {
                    HStack(spacing: 8) {
                        if s.newConsults > 0 { pendingChip(KXListingCopy.pickText(language, "新咨询", "新規問合せ", "Inquiries"), s.newConsults) }
                        if s.newApplications > 0 { pendingChip(KXListingCopy.pickText(language, "新申请", "新規応募", "Applications"), s.newApplications) }
                        if s.newBookings > 0 { pendingChip(KXListingCopy.pickText(language, "新预约", "新規予約", "Bookings"), s.newBookings) }
                        if s.pendingReview > 0 { pendingChip(KXListingCopy.pickText(language, "审核中", "審査中", "In review"), s.pendingReview) }
                    }
                }
            }
            Divider().opacity(0.5)
            HStack(spacing: 0) {
                statTile(KXListingCopy.pickText(language, "已发布", "公開中", "Live"), s.publishedListings)
                statTile(KXListingCopy.pickText(language, "收到线索", "受信リード", "Leads"), s.receivedInquiries)
                statTile(KXListingCopy.pickText(language, "浏览", "閲覧", "Views"), s.views)
                statTile(L("followers", language), s.followers)
            }
        }
        .padding(16)
        .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(KXColor.separator.opacity(0.5), lineWidth: 0.7))
    }

    private func pendingChip(_ label: String, _ count: Int) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.primary)
            Text("\(count)").font(.caption2.weight(.black)).foregroundStyle(KXColor.heat)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(KXColor.heat.opacity(0.10), in: Capsule())
    }

    private func countValue(_ n: Int) -> String? { n > 0 ? "\(n)" : nil }

    private func statTile(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title3.weight(.black))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var publishSection: some View {
        SettingsSectionCard(title: L("workbenchPublishTrading", language)) {
            SettingsRowLink(icon: "plus.circle.fill", tint: KXColor.accent, title: L("workbenchPublishCity", language), subtitle: L("workbenchPublishCitySubtitle", language)) {
                PublishListingTypeChooserView(citySlug: currentRegionCode, currentUser: currentUser, onPublishedListing: onPublishedListing)
            }
            SettingsDivider()
            SettingsRowLink(icon: "shippingbox.fill", tint: .teal, title: L("workbenchCityListingsTitle", language), value: summary.flatMap { countValue($0.publishedListings) }, subtitle: L("workbenchCityListingsSubtitle", language)) {
                MyCityListingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "bubble.left.and.bubble.right.fill", tint: .orange, title: L("inquiriesTitle", language), value: summary.flatMap { countValue($0.receivedInquiries) }, subtitle: L("inquiriesSubtitle", language)) {
                MyInquiriesView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(
                icon: "calendar.badge.clock", tint: KXColor.accent,
                title: KXListingCopy.pickText(language, "我的预约", "予約", "My reservations"),
                subtitle: KXListingCopy.pickText(language, "看房、到店与服务的预约时段", "内見・来店・サービスの予約", "Your viewing & visit bookings")
            ) {
                MyReservationsView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "doc.text.image.fill", tint: .blue, title: L("workbenchMyPostsTitle", language), value: "\(viewModel.postCount)", subtitle: L("workbenchMyPostsSubtitle", language)) {
                ProfileCollectionView(
                    title: L("workbenchMyPostsTitle", language),
                    posts: viewModel.authoredPosts,
                    mediaByPostId: viewModel.mediaByPostId,
                    currentUser: currentUser
                )
            }
        }
    }

    private var serviceSection: some View {
        SettingsSectionCard(title: L("workbenchMerchantSection", language)) {
            SettingsRowLink(icon: "storefront", tint: .teal, title: L("workbenchMerchantVerifyTitle", language), value: currentUser.merchantVerified ? L("merchantVerified", language) : (currentUser.isMerchant ? L("merchantPending", language) : ""), subtitle: L("workbenchMerchantVerifySubtitle", language)) {
                MerchantSettingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "star.bubble.fill", tint: .orange, title: L("workbenchReviewsTitle", language), subtitle: L("workbenchReviewsSubtitle", language)) {
                MerchantReviewsManageView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "briefcase.fill", tint: .indigo, title: L("workbenchJobPublishTitle", language), subtitle: L("workbenchJobPublishSubtitle", language), revealsNavBar: false) {
                CreateCityListingView(listingType: "job", citySlug: currentRegionCode, currentUser: currentUser, onPublishedListing: onPublishedListing)
            }
            SettingsDivider()
            SettingsRowLink(icon: "house.fill", tint: .blue, title: L("workbenchRentalPublishTitle", language), subtitle: L("workbenchRentalPublishSubtitle", language), revealsNavBar: false) {
                CreateCityListingView(listingType: "rental", citySlug: currentRegionCode, currentUser: currentUser, onPublishedListing: onPublishedListing)
            }
            SettingsDivider()
            SettingsRowLink(icon: "storefront.fill", tint: .brown, title: L("workbenchServicePublishTitle", language), subtitle: L("workbenchServicePublishSubtitle", language), revealsNavBar: false) {
                CreateCityListingView(listingType: "local_service", citySlug: currentRegionCode, currentUser: currentUser, onPublishedListing: onPublishedListing)
            }
            SettingsDivider()
            SettingsRowLink(icon: "tag.fill", tint: .pink, title: L("workbenchDiscountPublishTitle", language), subtitle: L("workbenchDiscountPublishSubtitle", language), revealsNavBar: false) {
                CreateCityListingView(listingType: "discount", citySlug: currentRegionCode, currentUser: currentUser, onPublishedListing: onPublishedListing)
            }
        }
    }
}

private extension View {
    func kxWorkbenchEntrance(_ active: Bool, index: Int) -> some View {
        self
            .opacity(active ? 1 : 0)
            .offset(y: active ? 0 : 10)
            .animation(.snappy(duration: 0.36).delay(Double(index) * 0.035), value: active)
    }
}

private struct WorkbenchPill: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.black))
            .foregroundStyle(KXColor.accent)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(KXColor.accent.opacity(0.10), in: Capsule())
    }
}

/// Type chooser for "发布城市信息" — so the main publish entry covers every
/// marketplace channel (二手 / 租房 / 招聘 / 本地服务 / 优惠), not just secondhand.
/// Membership-gated types are still enforced inside CreateCityListingView.
struct PublishListingTypeChooserView: View {
    @Environment(\.appLanguage) private var language
    let citySlug: String
    let currentUser: UserEntity
    var onPublishedListing: ((String) -> Void)?

    private struct Option: Identifiable {
        let type: String
        let icon: String
        let tint: Color
        var id: String { type }
    }

    private let options: [Option] = [
        .init(type: "secondhand", icon: "shippingbox.fill", tint: .teal),
        .init(type: "rental", icon: "house.fill", tint: .blue),
        .init(type: "job", icon: "briefcase.fill", tint: .indigo),
        .init(type: "local_service", icon: "storefront.fill", tint: .brown),
        .init(type: "discount", icon: "tag.fill", tint: .pink),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                SettingsSectionCard(title: L("workbenchPublishCity", language)) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { SettingsDivider() }
                        SettingsRowLink(
                            icon: option.icon,
                            tint: option.tint,
                            title: KXListingCopy.createTitle(for: option.type, language),
                            subtitle: publishSubtitle(option.type),
                            revealsNavBar: false
                        ) {
                            CreateCityListingView(listingType: option.type, citySlug: citySlug, currentUser: currentUser, onPublishedListing: onPublishedListing)
                        }
                    }
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 12)
            .kxTabBarSafeBottomPadding()
        }
        .navigationTitle(L("workbenchPublishCity", language))
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
    }

    private func publishSubtitle(_ type: String) -> String {
        switch type {
        case "secondhand": return KXListingCopy.pickText(language, "出售、求购、免费送", "売る・買う・譲る", "Sell, buy, give away")
        case "rental": return KXListingCopy.pickText(language, "整租、合租与转租房源", "賃貸・シェア・転貸", "Rentals, shares, sublets")
        case "job": return KXListingCopy.pickText(language, "招聘与兼职职位", "求人・アルバイト", "Jobs & part-time roles")
        case "local_service": return KXListingCopy.pickText(language, "本地商家与上门服务", "ローカル店舗・出張サービス", "Local shops & services")
        case "discount": return KXListingCopy.pickText(language, "优惠券与团购套餐", "クーポン・割引", "Deals & coupons")
        default: return ""
        }
    }
}
