import SwiftData
import SwiftUI

struct MyWorkbenchView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var postStore: PostStore
    @StateObject private var viewModel = ProfileViewModel()
    @State private var didEnter = false

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
                publishSection
                    .kxWorkbenchEntrance(didEnter, index: 1)
                serviceSection
                    .kxWorkbenchEntrance(didEnter, index: 2)
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

    private var publishSection: some View {
        SettingsSectionCard(title: L("workbenchPublishTrading", language)) {
            SettingsRowLink(icon: "plus.circle.fill", tint: KXColor.accent, title: L("workbenchPublishCity", language), subtitle: L("workbenchPublishCitySubtitle", language), revealsNavBar: false) {
                CreateCityListingView(listingType: "secondhand", citySlug: currentRegionCode, currentUser: currentUser, onPublishedListing: onPublishedListing)
            }
            SettingsDivider()
            SettingsRowLink(icon: "shippingbox.fill", tint: .teal, title: L("workbenchCityListingsTitle", language), subtitle: L("workbenchCityListingsSubtitle", language)) {
                MyCityListingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "bubble.left.and.bubble.right.fill", tint: .orange, title: L("inquiriesTitle", language), subtitle: L("inquiriesSubtitle", language)) {
                MyInquiriesView(currentUser: currentUser)
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
