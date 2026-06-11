import SwiftData
import SwiftUI

struct MyWorkbenchView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var postStore: PostStore
    @StateObject private var viewModel = ProfileViewModel()

    let currentUser: UserEntity

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
                publishSection
                contentSection
                membershipSection
                serviceSection
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 42)
        }
        .navigationTitle("我的工作台")
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .task {
            await viewModel.load(context: modelContext, user: currentUser, postStore: postStore)
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
                    if currentUser.isVerifiedMember || currentUser.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(KXColor.accent)
                    }
                }
                Text("@\(currentUser.username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    WorkbenchPill("\(viewModel.postCount) \(L("posts", language))")
                    WorkbenchPill(currentUser.isVerifiedMember ? L("membershipStatusActive", language) : "普通成员")
                    WorkbenchPill(currentRegionDisplay)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .kxGlassSurface(radius: 22, elevated: true)
    }

    private var publishSection: some View {
        SettingsSectionCard(title: "发布与交易") {
            SettingsRowLink(icon: "plus.circle.fill", tint: KXColor.accent, title: "发布城市信息", subtitle: "二手、租房、工作、商家与本地服务") {
                CreateCityListingView(listingType: "secondhand", citySlug: currentRegionCode, currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "shippingbox.fill", tint: .teal, title: "我的城市发布", subtitle: "管理二手、租房、工作、商家服务和优惠") {
                MyCityListingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "bubble.left.and.bubble.right.fill", tint: .orange, title: L("inquiriesTitle", language), subtitle: L("inquiriesSubtitle", language)) {
                MyInquiriesView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "doc.text.image.fill", tint: .blue, title: "我的发布", value: "\(viewModel.postCount)", subtitle: "查看已发布内容和互动数据") {
                ProfileCollectionView(
                    title: "我的发布",
                    posts: viewModel.authoredPosts,
                    mediaByPostId: viewModel.mediaByPostId,
                    currentUser: currentUser
                )
            }
            SettingsDivider()
            SettingsRowLink(icon: "tray.full", tint: .purple, title: "我的草稿", value: "\(viewModel.draftCount)", subtitle: L("navigationReady", language)) {
                DraftsSettingsView(currentUser: currentUser)
            }
        }
    }

    private var contentSection: some View {
        SettingsSectionCard(title: L("contentManagement", language)) {
            SettingsRowLink(icon: "bookmark.fill", tint: .blue, title: L("bookmarks", language), value: "\(viewModel.bookmarkCount)", subtitle: "\(viewModel.bookmarkCount) \(L("savedItems", language))") {
                BookmarkView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "photo.on.rectangle", tint: .cyan, title: L("mediaLibrary", language), value: "\(viewModel.mediaCount)", subtitle: L("navigationReady", language)) {
                MediaLibraryView(currentUser: currentUser)
            }
        }
    }

    private var membershipSection: some View {
        SettingsSectionCard(title: "会员与权益") {
            SettingsRowLink(icon: "checkmark.seal.fill", tint: .blue, title: L("membershipSettingsTitle", language), value: currentUser.isVerifiedMember ? L("membershipStatusActive", language) : nil, subtitle: L("membershipSettingsSubtitle", language)) {
                MembershipView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "books.vertical.fill", tint: .orange, title: L("memberLibraryTitle", language), subtitle: L("memberLibrarySubtitle", language)) {
                GuideMemberResourcesView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "doc.plaintext.fill", tint: .green, title: L("ordersTitle", language), subtitle: L("ordersSubtitle", language)) {
                MyOrdersView()
            }
        }
    }

    private var serviceSection: some View {
        SettingsSectionCard(title: "商家服务后台") {
            SettingsRowLink(icon: "storefront", tint: .teal, title: "认证商家服务", value: currentUser.merchantVerified ? L("merchantVerified", language) : (currentUser.isMerchant ? L("merchantPending", language) : ""), subtitle: "申请认证、上传资质、查看经营数据和审核状态") {
                MerchantSettingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "briefcase.fill", tint: .indigo, title: "招聘发布", subtitle: "发布招聘或求职相关信息") {
                CreateCityListingView(listingType: "job", citySlug: currentRegionCode, currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "house.fill", tint: .blue, title: "房源发布", subtitle: "发布合租、整租和短租信息") {
                CreateCityListingView(listingType: "rental", citySlug: currentRegionCode, currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "wrench.and.screwdriver.fill", tint: .brown, title: "商家与本地服务发布", subtitle: "点评、预约、酒店民宿、景点票务、接送机和生活服务") {
                CreateCityListingView(listingType: "local_service", citySlug: currentRegionCode, currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "tag.fill", tint: .pink, title: "优惠发布", subtitle: "发布商家优惠和本地活动") {
                CreateCityListingView(listingType: "discount", citySlug: currentRegionCode, currentUser: currentUser)
            }
        }
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
