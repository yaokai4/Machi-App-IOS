import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @AppStorage("accountEmail") private var accountEmail = ""
    @AppStorage("blockedUserIds") private var blockedUserIdsRaw = ""
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showLogoutConfirm = false

    let currentUser: UserEntity
    var onLogout: (() -> Void)?
    var onSwitchAccount: ((UserEntity) -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    topBar
                    SettingsAccountCard(
                        user: currentUser,
                        postCount: viewModel.postCount,
                        draftCount: viewModel.draftCount,
                        bookmarkCount: viewModel.bookmarkCount
                    )

                    accountSection
                    preferenceSection
                    securitySection
                    contentSection
                    supportSection

                    Button {
                        showLogoutConfirm = true
                    } label: {
                        Label(L("logout", language), systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .kxGlassSurface(radius: KXRadius.lg)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)

                    Text("Machi 1.0.0")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 42)
            }
            .kxPageBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await viewModel.load(context: modelContext, user: currentUser, postStore: postStore)
        }
        .confirmationDialog(L("logoutConfirm", language), isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button(L("logout", language), role: .destructive) {
                onLogout?()
                dismiss()
            }
            Button(L("cancel", language), role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("account", language))
                    .font(.system(size: 32, weight: .bold))
                    .tracking(0)
                Text(L("accountSettingsSubtitle", language))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private var accountSection: some View {
        SettingsSectionCard(title: L("accountEssentials", language)) {
            SettingsRowLink(
                icon: "checkmark.seal.fill",
                tint: .blue,
                title: L("membershipSettingsTitle", language),
                value: currentUser.isVerifiedMember ? L("membershipStatusActive", language) : nil,
                subtitle: L("membershipSettingsSubtitle", language)
            ) {
                MembershipView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "arrow.triangle.2.circlepath", tint: .purple, title: L("switchAccount", language), subtitle: L("switchAccountSubtitle", language)) {
                AccountSwitcherView(currentUser: currentUser, onSwitch: { user in
                    onSwitchAccount?(user)
                    dismiss()
                })
            }
            SettingsDivider()
            SettingsRowLink(icon: "lock.shield", tint: .indigo, title: L("accountPassword", language), subtitle: L("accountPasswordSubtitle", language)) {
                AccountPasswordSettingsView(user: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "envelope.badge", tint: .mint, title: L("contactInfo", language), value: accountEmail.isEmpty ? nil : accountEmail, subtitle: L("contactSubtitle", language)) {
                ContactSettingsView()
            }
        }
    }

    private var contentSection: some View {
        SettingsSectionCard(title: L("contentManagement", language)) {
            SettingsRowLink(icon: "bookmark.fill", tint: .blue, title: L("bookmarks", language), value: "\(viewModel.bookmarkCount)", subtitle: "\(viewModel.bookmarkCount) \(L("savedItems", language))") {
                BookmarkView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "tray.full", tint: .purple, title: L("drafts", language), value: "\(viewModel.draftCount)", subtitle: L("navigationReady", language)) {
                DraftsSettingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "photo.on.rectangle", tint: .cyan, title: L("mediaLibrary", language), value: "\(viewModel.mediaCount)", subtitle: L("navigationReady", language)) {
                MediaLibraryView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "storefront", tint: .teal, title: L("becomeMerchant", language), value: currentUser.merchantVerified ? L("merchantVerified", language) : (currentUser.isMerchant ? L("merchantPending", language) : ""), subtitle: L("merchantStatusNone", language)) {
                MerchantSettingsView(currentUser: currentUser)
            }
        }
    }

    private var preferenceSection: some View {
        SettingsSectionCard(title: L("preferences", language)) {
            SettingsRowLink(icon: "mappin.and.ellipse", tint: .red, title: L("regionSettings", language), value: regionDisplayLabel, subtitle: L("currentRegion", language)) {
                RegionSettingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "globe", tint: .blue, title: L("language", language), value: AppLanguage.resolved(from: appLanguageCode).title, subtitle: L("currentLanguage", language)) {
                LanguageSettingsView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "character.bubble", tint: .purple, title: L("contentLanguage", language), value: contentLanguageLabel, subtitle: L("contentLanguageSubtitle", language)) {
                ContentLanguageSettingsView(currentUser: currentUser)
            }
            SettingsDivider()
            SettingsRowLink(icon: "circle.lefthalf.filled", tint: .gray, title: L("appearance", language), value: AppAppearance.from(appAppearance).title(language), subtitle: L("appearanceSubtitle", language)) {
                AppearanceSettingsView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "bell.badge", tint: .orange, title: L("notificationSettings", language), value: L("enabled", language), subtitle: L("notificationsHere", language)) {
                NotificationPreferencesView(currentUser: currentUser)
            }
        }
    }

    private var regionDisplayLabel: String {
        if let region = RegionStore.shared.current {
            return "\(region.countryEmoji) \(region.cityName)"
        }
        return L("pickRegion", language)
    }

    private var contentLanguageLabel: String {
        LanguageManager.shared.preferred.title(language)
    }

    private var securitySection: some View {
        SettingsSectionCard(title: L("privacyAndSafety", language)) {
            SettingsRowLink(icon: "hand.raised.fill", tint: .indigo, title: L("privacySettings", language), value: L("public", language), subtitle: L("privacySettingsSubtitle", language)) {
                PrivacySettingsView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "desktopcomputer", tint: .teal, title: L("loginDevices", language), value: "1", subtitle: L("navigationReady", language)) {
                LoginDevicesView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "person.crop.circle.badge.xmark", tint: .red, title: L("blocklist", language), value: "\(blockedUserCount)", subtitle: blocklistSubtitle) {
                BlocklistSettingsView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "trash", tint: .orange, title: L("clearCache", language), subtitle: L("clearCacheSubtitle", language)) {
                CacheSettingsView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "person.crop.circle.badge.minus", tint: .red, title: L("deleteAccount", language), subtitle: L("deleteAccountSubtitle", language)) {
                DeleteAccountView(currentUser: currentUser) {
                    onLogout?()
                }
            }
        }
    }

    private var supportSection: some View {
        SettingsSectionCard(title: L("support", language)) {
            SettingsRowLink(icon: "questionmark.circle", tint: .blue, title: L("helpCenter", language), subtitle: L("navigationReady", language)) {
                HelpCenterView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "bubble.left.and.text.bubble.right", tint: .orange, title: L("feedback", language), subtitle: L("navigationReady", language)) {
                FeedbackView()
            }
            SettingsDivider()
            SettingsRowLink(icon: "info.circle", tint: .gray, title: L("aboutKaiX", language), value: "1.0.0", subtitle: "\(L("version", language)) 1.0.0") {
                AboutKaiXView()
            }
        }
    }

    private var blockedUserCount: Int {
        blockedUserIdsRaw.split(separator: "|").filter { !$0.isEmpty }.count
    }

    private var blocklistSubtitle: String {
        blockedUserCount == 0 ? L("noBlockedUsers", language) : "\(blockedUserCount) \(L("blockedUsers", language))"
    }
}

private struct SettingsAccountCard: View {
    @Environment(\.appLanguage) private var language
    let user: UserEntity
    let postCount: Int
    let draftCount: Int
    let bookmarkCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                AvatarView(user: user, size: 58)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                    .shadow(color: .black.opacity(0.08), radius: 9, x: 0, y: 5)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(user.displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if user.displaysVerifiedBadge {
                            KXVerifiedBadge()
                        }
                    }
                    Text("@\(user.username)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    SettingsRolePill(user: user)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)
            }

            Text(user.bio.isEmpty ? L("defaultBio", language) : user.bio)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                SettingsInlineStat(value: postCount, title: L("posts", language))
                SettingsInlineStat(value: bookmarkCount, title: L("bookmarks", language))
                SettingsInlineStat(value: draftCount, title: L("drafts", language))
            }
            .padding(.top, 1)

            HStack(spacing: 10) {
                NavigationLink {
                    ProfileView(currentUser: user, profileUserId: user.id, showsBackButton: true)
                } label: {
                    Label(L("profile", language), systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(KXColor.softBackground, in: Capsule())
                        .overlay(Capsule().stroke(KXColor.separator.opacity(0.7), lineWidth: 0.6))
                }

                NavigationLink {
                    EditProfileView(user: user)
                } label: {
                    Label(L("editProfile", language), systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(KXColor.softBackground, in: Capsule())
                        .overlay(Capsule().stroke(KXColor.separator.opacity(0.7), lineWidth: 0.6))
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}

private struct SettingsRolePill: View {
    @Environment(\.appLanguage) private var language
    let user: UserEntity

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: user.role == .member ? "person.fill" : "checkmark.seal.fill")
            Text(user.role == .member ? L("member", language) : L("creator", language))
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(user.role == .member ? Color.secondary : KXColor.accent)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background((user.role == .member ? Color.secondary : KXColor.accent).opacity(0.10), in: Capsule())
    }
}

private struct SettingsInlineStat: View {
    let value: Int
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(NumberFormatterUtils.compact(value))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProfileCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @StateObject private var actionModel = ProfileViewModel()
    @State private var selectedDestination: ProfileCollectionDestination?
    let title: String
    let posts: [PostEntity]
    let mediaByPostId: [String: [MediaEntity]]
    let currentUser: UserEntity

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if posts.isEmpty {
                    EmptyStateView(title: title, subtitle: L("noContent", language), systemImage: "tray")
                        .padding(.top, 32)
                } else {
                    ForEach(posts) { post in
                        let displayedPost = postStore.post(id: post.id) ?? post
                        PostCardView(
                            post: displayedPost,
                            author: currentUser,
                            mediaItems: mediaByPostId[displayedPost.id] ?? [],
                            currentUser: currentUser,
                            onOpen: { selectedDestination = .post(postId: displayedPost.id, focusComments: false) },
                            onAuthor: { selectedDestination = .profile(userId: displayedPost.authorId) },
                            onTag: { selectedDestination = .topic(tag: $0) },
                            onComment: { selectedDestination = .post(postId: displayedPost.id, focusComments: true) },
                            onLike: { Task { await actionModel.toggleLike(context: modelContext, post: displayedPost, currentUser: currentUser, profileUser: currentUser, postStore: postStore) } },
                            onBookmark: { Task { await actionModel.toggleBookmark(context: modelContext, post: displayedPost, currentUser: currentUser, profileUser: currentUser, postStore: postStore) } },
                            onRepost: { Task { await actionModel.repost(context: modelContext, post: displayedPost, currentUser: currentUser, profileUser: currentUser, postStore: postStore) } },
                            onQuoteRepost: { content in
                                Task { await actionModel.quoteRepost(context: modelContext, post: displayedPost, currentUser: currentUser, profileUser: currentUser, content: content, postStore: postStore) }
                            }
                        )
                        .equatable()
                    }
                }
            }
            .padding(KaiXTheme.horizontalPadding)
        }
        .kxPageBackground()
        .navigationTitle(title)
        .navigationDestination(item: $selectedDestination) { destination in
            switch destination {
            case .post(let postId, let focusComments):
                KXRoutedPostDetailView(
                    postId: postId,
                    currentUser: currentUser,
                    initialFocus: focusComments ? .comments : .none
                )
            case .profile(let userId):
                ProfileView(currentUser: currentUser, profileUserId: userId, tracksChrome: false, showsBackButton: true)
            case .topic(let tag):
                TopicDetailView(tag: tag, currentUser: currentUser)
            }
        }
    }
}

private enum ProfileCollectionDestination: Identifiable, Hashable {
    case post(postId: String, focusComments: Bool)
    case profile(userId: String)
    case topic(tag: String)

    var id: String {
        switch self {
        case .post(let postId, let focusComments):
            "post:\(postId):\(focusComments)"
        case .profile(let userId):
            "profile:\(userId)"
        case .topic(let tag):
            "topic:\(tag.normalizedTopicName)"
        }
    }
}

private struct LanguageSettingsView: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue

    var body: some View {
        Form {
            Section(L("currentLanguage", language)) {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        appLanguageCode = option.rawValue
                    } label: {
                        HStack {
                            Text(option == .system ? L("systemAppearance", language) : option.title)
                            Spacer()
                            if appLanguageCode == option.rawValue {
                                Image(systemName: "checkmark")
                                    .fontWeight(.bold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(L("language", language))
    }
}
