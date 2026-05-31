import SwiftData
import SwiftUI

struct HomeTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var regionStore = RegionStore.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var isShowingSettings = false
    @State private var isShowingRegionPicker = false
    @State private var hotScope: HotScope = .city

    let currentUser: UserEntity
    @Binding var selectedTab: AppTab
    @Binding var isShowingComposer: Bool
    let refreshToken: UUID
    var onLogout: (() -> Void)?
    var onSwitchAccount: ((UserEntity) -> Void)?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                header

                Group {
                    switch viewModel.state {
                    case .loading, .idle:
                        LoadingView()
                    case .empty:
                        if viewModel.mode == .following {
                            followingEmptyState
                        } else if viewModel.mode == .local && regionStore.current == nil {
                            localPickRegionState
                        } else {
                            EmptyStateView(title: L("emptyFeed", language), subtitle: L("emptyFeedHelp", language), systemImage: "text.bubble")
                        }
                    case .error(let message):
                        ErrorStateView(message: message) {
                            Task { await viewModel.refresh(context: modelContext, currentUser: currentUser, postStore: postStore) }
                        }
                    case .loaded:
                        feed
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            KXFloatingComposeButton {
                isShowingComposer = true
            }
            .accessibilityLabel(L("compose", language))
            .padding(.trailing, KXSpacing.lg)
            .padding(.bottom, chrome.bottomContentPadding + KXSpacing.sm)
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadInitial(context: modelContext, currentUser: currentUser, postStore: postStore)
        }
        .onChange(of: viewModel.mode) { _, _ in
            Task { await viewModel.loadInitial(context: modelContext, currentUser: currentUser, postStore: postStore, clearExisting: true) }
        }
        .onChange(of: refreshToken) { _, _ in
            Task { await viewModel.loadInitial(context: modelContext, currentUser: currentUser, postStore: postStore) }
        }
        .fullScreenCover(isPresented: $isShowingSettings) {
            SettingsView(currentUser: currentUser, onLogout: onLogout, onSwitchAccount: onSwitchAccount)
        }
        .sheet(isPresented: $isShowingRegionPicker) {
            RegionPickerView(
                initialCountry: currentUser.country.isEmpty ? regionStore.current?.countryCode : currentUser.country,
                allowsAnyCountry: currentUser.country.isEmpty
            ) { region in
                regionStore.setCurrent(region)
                Task {
                    await persistCurrentRegion(region)
                    await viewModel.loadInitial(
                        context: modelContext,
                        currentUser: currentUser,
                        postStore: postStore,
                        clearExisting: true,
                    )
                }
            }
        }
        .onChange(of: regionStore.current?.regionCode) { _, _ in
            Task {
                await viewModel.loadInitial(
                    context: modelContext,
                    currentUser: currentUser,
                    postStore: postStore,
                    clearExisting: true,
                )
            }
        }
        .onChange(of: languageManager.preferred) { _, _ in
            // Content-language change → wipe the existing feed and
            // re-rank from scratch. The repository's predicate now
            // factors in the resolved primary tag via
            // `FeedQueryBuilder.context`.
            Task {
                await viewModel.loadInitial(
                    context: modelContext,
                    currentUser: currentUser,
                    postStore: postStore,
                    clearExisting: true,
                )
            }
        }
    }

    /// Scope chip shown above the "热榜" tab. Lets the user pivot
    /// the hot-list between current city / country / global without
    /// losing position. The actual filtering hooks into the existing
    /// HomeViewModel via `viewModel.mode == .hot` plus this state.
    private enum HotScope: String, CaseIterable, Identifiable {
        case city, country, all
        var id: String { rawValue }
        func title(_ language: AppLanguage) -> String {
            switch self {
            case .all:     return L("hotScopeAll", language)
            case .country: return L("hotScopeCountry", language)
            case .city:    return L("hotScopeCity", language)
            }
        }
    }

    private var header: some View {
        HomeHeaderView(
            currentUser: currentUser,
            selection: $viewModel.mode,
            currentRegion: regionStore.current,
            onAvatar: { isShowingSettings = true },
            onBell: { selectedTab = .notifications },
            onRegion: { isShowingRegionPicker = true },
            onCity: {
                if let region = regionStore.current {
                    router.open(.city(regionCode: region.regionCode))
                } else {
                    isShowingRegionPicker = true
                }
            }
        )
    }

    private func persistCurrentRegion(_ region: KaiXRegionDirectory.Region) async {
        currentUser.country = region.countryCode
        currentUser.province = region.provinceCode
        currentUser.city = region.cityCode
        currentUser.currentRegionCode = region.regionCode
        currentUser.recentRegionCodes = regionStore.recent.map(\.regionCode)
        try? modelContext.save()

        guard KaiXBackend.token != nil else { return }
        _ = try? await KaiXAPIClient.shared.updateMe([
            "country": region.countryCode,
            "province": region.provinceCode,
            "city": region.cityCode,
            "current_region_code": region.regionCode,
        ])
    }

    /// Empty-state for the same-city tab when the user hasn't picked
    /// any region yet. Mirrors the `EmptyStateView` look but with a
    /// dedicated CTA into the picker.
    private var localPickRegionState: some View {
        VStack(spacing: KXSpacing.md) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(KXColor.accent)
            Text(L("pickRegion", language))
                .font(.headline.weight(.semibold))
            Text(L("pickRegionPrompt", language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                isShowingRegionPicker = true
            } label: {
                Text(L("selectCity", language))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .kxGlassCapsule(isSelected: true)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.horizontal, KXSpacing.xl)
        .padding(.vertical, KXSpacing.xl)
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                LocalNewsDeskStripView(
                    country: regionStore.current?.countryCode ?? currentUser.country,
                    city: regionStore.current?.cityCode ?? currentUser.city,
                    title: "本地资讯台",
                    variant: .home
                )
                if viewModel.mode == .hot {
                    hotScopePicker
                }
                ForEach(viewModel.posts) { post in
                    let displayedPost = postStore.post(id: post.id) ?? post
                    let originalPost = displayedPost.repostOfPostId.flatMap { postStore.post(id: $0) }
                    let isQuoteRepost = originalPost != nil && !displayedPost.previewText.isEmpty
                    let targetPost = isQuoteRepost ? displayedPost : (originalPost ?? displayedPost)
                    let author = viewModel.authors[displayedPost.authorId]
                    let originalAuthor = originalPost.flatMap { viewModel.authors[$0.authorId] }
                    PostCardView(
                        post: displayedPost,
                        author: author,
                        mediaItems: viewModel.mediaByPostId[displayedPost.id] ?? [],
                        currentUser: currentUser,
                        originalPost: originalPost,
                        originalAuthor: originalAuthor,
                        originalMediaItems: originalPost == nil ? [] : (viewModel.mediaByPostId[originalPost?.id ?? ""] ?? []),
                        onOpen: { router.open(.postDetail(postId: targetPost.id)) },
                        onOpenOriginal: { if let originalPost { router.open(.postDetail(postId: originalPost.id)) } },
                        onAuthor: { router.open(.profile(userId: targetPost.authorId)) },
                        onTag: { router.open(.topic(tag: $0)) },
                        onComment: { router.open(.postDetailComment(postId: targetPost.id, commentId: nil)) },
                        onLike: { Task { await viewModel.toggleLike(context: modelContext, post: targetPost, currentUser: currentUser, postStore: postStore) } },
                        onBookmark: { Task { await viewModel.toggleBookmark(context: modelContext, post: targetPost, currentUser: currentUser, postStore: postStore) } },
                        onRepost: { Task { await viewModel.repost(context: modelContext, post: targetPost, currentUser: currentUser, postStore: postStore) } },
                        onQuoteRepost: { content in
                            Task { await viewModel.quoteRepost(context: modelContext, post: targetPost, currentUser: currentUser, content: content, postStore: postStore) }
                        }
                    )
                    .equatable()
                    .task(id: displayedPost.id) {
                        guard displayedPost.id == viewModel.posts.last?.id else { return }
                        await viewModel.loadMoreIfNeeded(context: modelContext, currentUser: currentUser, post: displayedPost, postStore: postStore)
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding()
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.vertical, KXSpacing.sm)
            .padding(.bottom, chrome.bottomContentPadding)
        }
        .refreshable {
            await viewModel.refresh(context: modelContext, currentUser: currentUser, postStore: postStore)
        }
    }

    /// Pivot chip row that lets the user switch the hot-list between
    /// city / country / global. Posts that don't match the chosen
    /// scope are filtered in-memory so the existing repository call
    /// stays untouched.
    private var hotScopePicker: some View {
        HStack(spacing: 8) {
            ForEach(HotScope.allCases) { scope in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        hotScope = scope
                    }
                } label: {
                    Text(scope.title(language))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .kxGlassCapsule(isSelected: hotScope == scope)
                }
                .buttonStyle(.plain)
                .foregroundStyle(hotScope == scope ? KXColor.accent : .primary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var followingEmptyState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                EmptyStateView(title: L("emptyFollowingFeed", language), subtitle: L("emptyFollowingFeedHelp", language), systemImage: "person.2")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)

                ForEach(viewModel.recommendedUsers.prefix(5)) { user in
                    HStack(spacing: 12) {
                        Button {
                            router.open(.profile(userId: user.id))
                        } label: {
                            AvatarView(user: user, size: 50)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline.weight(.semibold))
                                Text("@\(user.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            Task { await viewModel.follow(context: modelContext, currentUser: currentUser, target: user, postStore: postStore, userStore: userStore) }
                        } label: {
                            Text(L("follow", language))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(KXColor.accent)
                                .padding(.horizontal, 15)
                                .frame(height: 36)
                                .kxGlassCapsule(isSelected: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .kxGlassSurface(radius: KXRadius.lg)
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, chrome.bottomContentPadding)
        }
    }
}

private struct HomeHeaderView: View {
    @Environment(\.appLanguage) private var language
    let currentUser: UserEntity
    @Binding var selection: TimelineMode
    let currentRegion: KaiXRegionDirectory.Region?
    let onAvatar: () -> Void
    let onBell: () -> Void
    let onRegion: () -> Void
    let onCity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(spacing: KXSpacing.sm) {
                Button(action: onAvatar) {
                    AvatarView(user: currentUser, size: 44)
                        .overlay(Circle().stroke(KXColor.cardBackground, lineWidth: 2))
                }
                .buttonStyle(.plain)

                Text(L("appName", language))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Spacer()

                // Single region entry — earlier we had both this chip
                // AND a separate `building.2` button that also opened
                // the city channel. Users found the duplication
                // confusing. Long-press the chip (or open Discover) to
                // jump into the city channel.
                RegionPickerButton(region: currentRegion, onTap: onRegion)

                Button(action: onBell) {
                    Image(systemName: "bell")
                        .font(.system(size: KXIconSize.md, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .kxGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("notifications", language))
            }

            TimelinePicker(selection: $selection)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }
}

private struct TimelinePicker: View {
    @Environment(\.appLanguage) private var language
    @Binding var selection: TimelineMode

    var body: some View {
        KXSegmentedControl(TimelineMode.allCases, selection: $selection) { mode in
            Text(mode.title(language))
        }
    }
}
