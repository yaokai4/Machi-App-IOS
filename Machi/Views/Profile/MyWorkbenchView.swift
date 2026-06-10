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

    private var profileCompletion: Int {
        let checks = [
            !currentUser.avatarURL.isEmpty || !currentUser.avatarSymbol.isEmpty,
            !currentUser.coverURL.isEmpty,
            !currentUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !currentUser.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !(currentUser.currentRegionCode.isEmpty && currentUser.city.isEmpty),
            currentUser.isVerified || currentUser.isVerifiedMember || currentUser.merchantVerified,
        ]
        let done = checks.filter { $0 }.count
        return Int((Double(done) / Double(checks.count)) * 100.0)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 15) {
                hero
                publishSection
                accountSection
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
            SettingsRowLink(icon: "plus.circle.fill", tint: KXColor.accent, title: "发布城市信息", subtitle: "二手、租房、招聘和本地服务") {
                CreateCityListingView(listingType: "secondhand", citySlug: currentRegionCode, currentUser: currentUser)
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

    private var accountSection: some View {
        SettingsSectionCard(title: "资料完整度") {
            SettingsRowLink(icon: "checklist.checked", tint: .green, title: "资料完整度", value: "\(profileCompletion)%", subtitle: "完善头像、封面、简介、城市和认证状态") {
                EditProfileView(user: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "person.crop.circle", tint: .blue, title: L("profile", language), subtitle: L("profileSubtitle", language)) {
                ProfileView(currentUser: currentUser, profileUserId: currentUser.id, showsBackButton: true)
            }
            SettingsDivider()
            SettingsRowLink(icon: "pencil", tint: .indigo, title: L("editProfile", language), subtitle: L("editProfileSubtitle", language)) {
                EditProfileView(user: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "checkmark.seal.fill", tint: .blue, title: L("membershipSettingsTitle", language), value: currentUser.isVerifiedMember ? L("membershipStatusActive", language) : nil, subtitle: L("membershipSettingsSubtitle", language)) {
                MembershipView(currentUser: currentUser)
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
            SettingsRowLink(icon: "sparkles", tint: .orange, title: "Guide 资料", subtitle: "会员资料、模板和本地指南") {
                GuideMemberResourcesView()
            }
        }
    }

    private var serviceSection: some View {
        SettingsSectionCard(title: "商家/发布者") {
            SettingsRowLink(icon: "storefront", tint: .teal, title: L("becomeMerchant", language), value: currentUser.merchantVerified ? L("merchantVerified", language) : (currentUser.isMerchant ? L("merchantPending", language) : ""), subtitle: L("merchantStatusNone", language)) {
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
            SettingsRowLink(icon: "wrench.and.screwdriver.fill", tint: .brown, title: "服务发布", subtitle: "发布翻译、手续、接机和本地服务") {
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
