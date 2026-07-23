import SwiftData
import SwiftUI

struct HomeTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var toastManager: ToastManager
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var regionStore = RegionStore.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var isShowingSettings = false
    @State private var isShowingRegionPicker = false
    /// Bumped on each follow tap to drive `.sensoryFeedback(.selection)`.
    @State private var followFeedbackTrigger = 0

    // ── 列表级手感状态 ──────────────────────────────────────────────
    /// FAB 随滚动方向收起(下滑)/浮现(上滑),阅读时让出右下角。
    @State private var isFabVisible = true
    /// 是否接近列表顶部,决定刷新增量的呈现形态(轻横幅 vs 回顶胶囊)。
    @State private var isNearTop = true
    /// 滚动偏移/方向追踪器。引用类型:高频回调里写它零 view invalidation。
    @State private var scrollTracker = FeedScrollTracker()
    /// 递增即触发 feed 回顶(再点首页 tab / 新内容胶囊共用一条通道)。
    @State private var scrollToTopToken = 0
    /// 运营位互斥:旅程卡在场时商城 hero 卡让位(同屏最多一张)。
    @State private var isJourneyCardActive = false
    /// 深处刷新出新内容时的「↑ 有新内容」胶囊(带新作者头像堆叠)。
    @State private var newContentPill: HomeViewModel.FeedRefreshDelta?
    /// 顶部刷新完成的「为你更新了 N 条」轻横幅(自动消失)。
    @State private var refreshedBanner: HomeViewModel.FeedRefreshDelta?
    @State private var bannerDismissTask: Task<Void, Never>?
    /// 刷新真的带来新内容时的成功触感。
    @State private var successFeedbackTrigger = 0

    private static let feedTopAnchorID = "home.feed.top"

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
                        // Structured skeleton instead of a lone spinner: the
                        // page keeps its card rhythm while the feed loads,
                        // and the swap to real content doesn't jump.
                        ScrollView {
                            KXFeedSkeleton()
                                .padding(.horizontal, KXSpacing.screen)
                                .padding(.vertical, 7)
                        }
                        .scrollDisabled(true)
                        .transition(.opacity)
                    case .empty:
                        Group {
                            if viewModel.mode == .following {
                                followingEmptyState
                            } else if viewModel.mode == .local && regionStore.current == nil {
                                localPickRegionState
                            } else {
                                // 空态也必须能自助恢复:包进 ScrollView 挂下拉刷新,
                                // 否则服务端瞬时返回空页后这里就是死胡同(无重试按钮,
                                // 用户只能切 tab / 杀 App 才能重载)。
                                ScrollView {
                                    EmptyStateView(title: L("emptyFeed", language), subtitle: L("emptyFeedHelp", language), systemImage: "text.bubble")
                                        .frame(maxWidth: .infinity)
                                        .containerRelativeFrame(.vertical)
                                }
                                .refreshable {
                                    await viewModel.refresh(context: modelContext, currentUser: currentUser, postStore: postStore)
                                }
                            }
                        }
                        .transition(.opacity)
                    case .error(let message):
                        ErrorStateView(message: message) {
                            Task { await viewModel.refresh(context: modelContext, currentUser: currentUser, postStore: postStore) }
                        }
                        .transition(.opacity)
                    case .loaded:
                        // Content settles in with a soft fade + 6pt rise so
                        // the skeleton→feed swap reads as one motion.
                        feed
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.24), value: viewModel.state)
                // 刷新增量的悬浮提示,浮在 header 正下方。
                .overlay(alignment: .top) {
                    feedFloatingNotice
                        .padding(.top, KXSpacing.sm)
                }
            }

            KXFloatingComposeButton {
                isShowingComposer = true
            }
            .accessibilityLabel(L("compose", language))
            .padding(.trailing, KXSpacing.lg)
            .padding(.bottom, chrome.bottomContentPadding + KXSpacing.sm)
            // 下滑收起、上滑浮现:阅读时让出右下角,想发布时一抬手就回来。
            .opacity(isFabVisible ? 1 : 0)
            .scaleEffect(isFabVisible ? 1 : 0.7, anchor: .bottomTrailing)
            .offset(y: isFabVisible ? 0 : 10)
            .allowsHitTesting(isFabVisible)
            .accessibilityHidden(!isFabVisible)
            .animation(.easeInOut(duration: 0.2), value: isFabVisible)
        }
        .sensoryFeedback(.success, trigger: successFeedbackTrigger)
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(for: .kaiXPostRemoved)) { note in
            // 详情页删帖后立即剔除幽灵卡(否则 `?? post` 回退会继续渲染 PostStore
            // 已忘掉、但 viewModel.posts 仍强引用的陈旧实体,点进去报 postDeleted)。
            if let ids = note.userInfo?["ids"] as? [String] { viewModel.removePosts(ids: ids) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kaiXTabReselectedAtRoot)) { note in
            // 已在首页根页再点首页 tab:回顶 + 触发刷新(X/小红书标准手感)。
            guard note.userInfo?["tab"] as? String == AppTab.home.rawValue else { return }
            scrollToTopToken &+= 1
            Task { await viewModel.refresh(context: modelContext, currentUser: currentUser, postStore: postStore) }
        }
        .onChange(of: viewModel.refreshDelta) { _, delta in
            // 刷新真的拉到了新内容:成功触感 + 按所处位置二选一提示 ——
            // 顶部给自动消失的「为你更新了 N 条」,深处给常驻的回顶胶囊。
            guard let delta else { return }
            successFeedbackTrigger &+= 1
            if isNearTop {
                withAnimation(.snappy(duration: 0.25)) {
                    refreshedBanner = delta
                    newContentPill = nil
                }
                bannerDismissTask?.cancel()
                bannerDismissTask = Task {
                    try? await Task.sleep(for: .seconds(2.4))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.3)) { refreshedBanner = nil }
                }
            } else {
                withAnimation(.snappy(duration: 0.25)) { newContentPill = delta }
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            // 离开 loaded(骨架/空态/错误页)时 FAB 必须在场——那些页面没有
            // 滚动手势能把它唤回来。
            if newState != .loaded, !isFabVisible { isFabVisible = true }
        }
        .task {
            await KXPerf.measure("feed.loadInitial") {
                await viewModel.loadInitial(context: modelContext, currentUser: currentUser, postStore: postStore)
            }
        }
        .onChange(of: viewModel.mode) { _, _ in
            // 快照机制下不再 clearExisting:HomeViewModel.mode.didSet 已同步
            // 回填该 tab 的内存快照(零骨架)或清屏,这里只负责触发静默刷新。
            // 悬浮提示属于旧 tab 的语境,随切换一起退场。
            newContentPill = nil
            refreshedBanner = nil
            bannerDismissTask?.cancel()
            Task { await viewModel.loadInitial(context: modelContext, currentUser: currentUser, postStore: postStore) }
        }
        .onChange(of: refreshToken) { _, _ in
            Task { await viewModel.loadInitial(context: modelContext, currentUser: currentUser, postStore: postStore) }
        }
        .navigationDestination(isPresented: $isShowingSettings) {
            SettingsView(currentUser: currentUser, onLogout: onLogout, onSwitchAccount: onSwitchAccount)
        }
        .sheet(isPresented: $isShowingRegionPicker) {
            RegionPickerView(
                initialCountry: regionStore.current?.countryCode ?? (currentUser.country.isEmpty ? "jp" : currentUser.country),
                allowsAnyCountry: false
            ) { region in
                // Only set + persist here. The feed reload is driven by the
                // `onChange(of: regionStore.current?.regionCode)` observer
                // below — calling loadInitial here too fired two concurrent
                // clear-and-reload passes (a doubled network fetch + a feed
                // flash) for every city switch.
                regionStore.setCurrent(region)
                Task { await persistCurrentRegion(region) }
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
        .onChange(of: viewModel.transientError) { _, message in
            // 互动(赞/藏/转/引用/关注)失败走全局 toast,绝不整页替换 feed ——
            // 弱网下一次点赞失败曾让满屏内容瞬间变成错误页并丢滚动位置。
            // 展示后清回 nil,同一条错误连续出现时 onChange 才会再次触发。
            guard let message else { return }
            toastManager.show(.custom(
                title: KXListingCopy.pickText(language, "操作未完成", "操作を完了できませんでした", "Action didn't complete"),
                message: message,
                systemImage: "xmark.octagon",
                tint: .red,
                technicalDetails: nil
            ))
            viewModel.transientError = nil
        }
    }

    private var header: some View {
        HomeHeaderView(
            currentUser: currentUser,
            selection: $viewModel.mode,
            currentRegion: regionStore.current,
            onAvatar: { isShowingSettings = true },
            onRegion: { isShowingRegionPicker = true },
            onCity: {
                if let region = regionStore.current {
                    router.open(.city(regionCode: region.regionCode))
                } else {
                    isShowingRegionPicker = true
                }
            },
            onSearch: { router.open(.search(initialQuery: nil), in: .home) }
        )
    }

    private func persistCurrentRegion(_ region: KaiXRegionDirectory.Region) async {
        currentUser.country = region.countryCode
        currentUser.province = region.provinceCode
        currentUser.city = region.cityCode
        currentUser.currentRegionCode = region.regionCode
        currentUser.recentRegionCodes = regionStore.recent.map(\.regionCode)
        try? modelContext.save()
        // The browse region is pushed to the backend by
        // RegionStore.setCurrent → syncBrowseRegionToBackend, so we don't
        // repeat updateRegionLanguage here — that was a second identical
        // network write on every city switch.
    }

    /// Empty-state for the same-city tab when the user hasn't picked
    /// any region yet. Mirrors the `EmptyStateView` look but with a
    /// dedicated CTA into the picker.
    private var localPickRegionState: some View {
        VStack(spacing: KXSpacing.md) {
            Image(systemName: "mappin.and.ellipse")
                .kxScaledFont(36, weight: .regular)
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
        let feedPosts = visibleFeedPosts
        return ScrollViewReader { proxy in
            ScrollView {
            LazyVStack(spacing: KXSpacing.sm) {
                // "下一步该办什么" Guide-journey hook. Renders nothing when
                // there is no journey hint, and loads independently — it can
                // never delay the feed. Sits above the ForEach so the
                // load-more sentinel (anchored to the trailing cards) is
                // unaffected. 数据晚到时经 withAnimation + .transition 插入,
                // feed 不再被无动画下顶。
                HomeJourneyNextStepCard(currentUser: currentUser) { isActive in
                    guard isJourneyCardActive != isActive else { return }
                    withAnimation(.snappy(duration: 0.3)) { isJourneyCardActive = isActive }
                }

                // I2-1 hero SKU 曝光卡:同一套「自加载、失败静默」模式;
                // 可关闭,7 天内不再出现。运营位互斥:旅程卡在场时让位
                // (同屏最多一张,减轻首屏广告感)。
                HomeStoreHeroCard(isSuppressed: isJourneyCardActive)

                if feedPosts.isEmpty {
                    EmptyStateView(
                        title: KXListingCopy.pickText(language, "这里还没有热榜内容", "まだ急上昇コンテンツがありません", "No hot posts here yet"),
                        subtitle: KXListingCopy.pickText(language, "稍后回来看看新的本地动态。", "あとでもう一度確認してください。", "Check back later for fresh local activity."),
                        systemImage: "flame"
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
                ForEach(feedPosts) { post in
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
                        // 预取哨兵提前 5 张卡:倒数第 5 张上屏即开始拉下一页
                        // (pageSize=15 → 第 10 张触发),配合 loadMoreIfNeeded
                        // 的 isLoadingMore/isLoadingInitial 守卫天然去重;触底
                        // 撞见 spinner 的等待从「每 15 条一次」变成几乎不可见。
                        guard feedPosts.suffix(KaiXConfig.feedLoadMoreLookahead)
                            .contains(where: { $0.id == displayedPost.id }) else { return }
                        await viewModel.loadMoreIfNeeded(context: modelContext, currentUser: currentUser, post: nil, postStore: postStore)
                    }
                }

                if viewModel.isLoadingMore {
                    KXInlineLoader()
                        .transition(.opacity)
                }

                // 到底收尾:明确告诉用户「没有了」而不是静默截止,并给
                // 发现 / 同城两条出路,给无限流一个心理句点。
                if !viewModel.canLoadMore, !viewModel.isLoadingMore, !feedPosts.isEmpty {
                    feedEndFooter
                }
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.vertical, 7)
            .padding(.bottom, chrome.bottomContentPadding + 18)
            .kxReadableWidth()
            .id(Self.feedTopAnchorID)
            // 滚动方向/位置监听:iOS 17 可用的 onGeometryChange(替代 iOS 18
            // 的 onScrollGeometryChange,与 ChatView 同模式),驱动 FAB 的
            // 收起/浮现与「有新内容」胶囊的顶部自愈。
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.frame(in: .scrollView).minY
            } action: { minY in
                handleFeedScroll(minY)
            }
            }
            .refreshable {
                await viewModel.refresh(context: modelContext, currentUser: currentUser, postStore: postStore)
            }
            .onChange(of: scrollToTopToken) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(Self.feedTopAnchorID, anchor: .top)
                }
            }
            .onChange(of: viewModel.mode) { _, _ in
                // 四个 mode 共用同一个 ScrollView:快照回填的新列表不该停在
                // 旧 tab 的滚动深度,内容替换同帧瞬时回顶(无动画)。
                proxy.scrollTo(Self.feedTopAnchorID, anchor: .top)
            }
        }
    }

    /// 到底收尾:三语「已经看完啦」+ 去发现 / 同城两个出口。
    private var feedEndFooter: some View {
        VStack(spacing: KXSpacing.md) {
            HStack(spacing: KXSpacing.sm) {
                Rectangle().fill(.quaternary).frame(width: 28, height: 1)
                Text(KXListingCopy.pickText(language, "已经看完啦", "全部見終わりました", "You're all caught up"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Rectangle().fill(.quaternary).frame(width: 28, height: 1)
            }
            HStack(spacing: KXSpacing.sm) {
                Button {
                    selectedTab = .search
                } label: {
                    Text(KXListingCopy.pickText(language, "去发现逛逛", "発見を見る", "Explore Discover"))
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, KXSpacing.md)
                        .frame(height: 34)
                        .kxGlassCapsule()
                }
                .buttonStyle(.plain)
                Button {
                    if let region = regionStore.current {
                        router.open(.city(regionCode: region.regionCode))
                    } else {
                        isShowingRegionPicker = true
                    }
                } label: {
                    Text(KXListingCopy.pickText(language, "逛逛同城", "同じ街を見る", "Browse your city"))
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, KXSpacing.md)
                        .frame(height: 34)
                        .kxGlassCapsule()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, KXSpacing.lg)
        .padding(.bottom, KXSpacing.md)
        .accessibilityIdentifier("home.feed.endFooter")
    }

    /// 刷新增量的悬浮提示:顶部时是自动消失的「为你更新了 N 条」轻横幅;
    /// 深处时是常驻的「↑ 有新内容」胶囊(前 3 位新作者头像堆叠,点按回顶)。
    @ViewBuilder
    private var feedFloatingNotice: some View {
        if let pill = newContentPill {
            Button {
                scrollToTopToken &+= 1
                withAnimation(.snappy(duration: 0.25)) { newContentPill = nil }
            } label: {
                HStack(spacing: KXSpacing.sm) {
                    if !pill.authors.isEmpty {
                        HStack(spacing: -8) {
                            ForEach(pill.authors) { author in
                                AvatarView(user: author, size: 22)
                                    .overlay(Circle().stroke(KXColor.cardBackground, lineWidth: 1.5))
                            }
                        }
                    }
                    Image(systemName: "arrow.up")
                        .font(.caption.weight(.bold))
                    Text(KXListingCopy.pickText(language, "有新内容", "新着があります", "New posts"))
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(KXColor.accent)
                .padding(.horizontal, KXSpacing.md)
                .frame(height: 36)
                .kxGlassCapsule(isSelected: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KXListingCopy.pickText(language, "有新内容，点按回到顶部", "新着があります。タップして先頭へ", "New posts — tap to scroll to top"))
            .accessibilityIdentifier("home.feed.newContentPill")
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let banner = refreshedBanner {
            Text(KXListingCopy.pickText(
                language,
                "为你更新了 \(banner.count) 条",
                "\(banner.count)件の新着を更新しました",
                banner.count == 1 ? "1 new post for you" : "\(banner.count) new posts for you"
            ))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, KXSpacing.md)
            .frame(height: 32)
            .kxGlassCapsule()
            .accessibilityIdentifier("home.feed.refreshBanner")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// FAB 收起/浮现 + 顶部感知。高频滚动回调只在【派生状态变化】时写
    /// @State,原始偏移存引用类型 tracker,纯滚动零 view invalidation。
    private func handleFeedScroll(_ minY: CGFloat) {
        let delta = minY - scrollTracker.lastOffset
        scrollTracker.lastOffset = minY
        let nearTop = minY > -80
        if nearTop != isNearTop { isNearTop = nearTop }
        if nearTop {
            scrollTracker.accumulated = 0
            if !isFabVisible { isFabVisible = true }
            // 用户自己滚回了顶部:新内容胶囊使命完成,顺手收掉。
            if newContentPill != nil, minY > -40 {
                withAnimation(.snappy(duration: 0.25)) { newContentPill = nil }
            }
            return
        }
        guard abs(delta) > 0.5 else { return }
        // 同方向累计、反向即重置:±16pt 阈值防抖,避免慢滚时 FAB 抖动。
        if (delta < 0) == (scrollTracker.accumulated < 0) {
            scrollTracker.accumulated += delta
        } else {
            scrollTracker.accumulated = delta
        }
        if scrollTracker.accumulated < -16 {
            if isFabVisible { isFabVisible = false }
        } else if scrollTracker.accumulated > 16 {
            if !isFabVisible { isFabVisible = true }
        }
    }

    private var visibleFeedPosts: [PostEntity] {
        viewModel.posts
    }

    private var followingEmptyState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                EmptyStateView(title: L("emptyFollowingFeed", language), subtitle: L("emptyFollowingFeedHelp", language), systemImage: "person.2", illustration: .follow)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)

                ForEach(viewModel.recommendedUsers.prefix(5)) { user in
                    HStack(spacing: KXSpacing.md) {
                        Button {
                            router.open(.profile(userId: user.id))
                        } label: {
                            AvatarView(user: user, size: 50)
                            VStack(alignment: .leading, spacing: KXSpacing.xs) {
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
                            followFeedbackTrigger += 1
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
                        .sensoryFeedback(.selection, trigger: followFeedbackTrigger)
                    }
                    .padding(14)
                    .kxGlassSurface(radius: KXRadius.lg)
                }
            }
            .padding(.horizontal, KXSpacing.screen)
            .padding(.top, KXSpacing.md)
            .padding(.bottom, chrome.bottomContentPadding)
        }
        // 关注空态与正常 feed 同一手势自愈:没有它,推荐加载失败/暂时为空时
        // 这个页面无任何重载途径。
        .refreshable {
            await viewModel.refresh(context: modelContext, currentUser: currentUser, postStore: postStore)
        }
    }
}

/// 滚动偏移/方向追踪器。引用类型:onGeometryChange 每帧写它不触发任何
/// view invalidation,只有派生的 isFabVisible / isNearTop 变化才重渲染。
@MainActor
private final class FeedScrollTracker {
    var lastOffset: CGFloat = 0
    /// 同方向累计位移(带符号),方向反转时重置;±16pt 阈值防抖。
    var accumulated: CGFloat = 0
}

private struct HomeHeaderView: View {
    @Environment(\.appLanguage) private var language
    let currentUser: UserEntity
    @Binding var selection: TimelineMode
    let currentRegion: KaiXRegionDirectory.Region?
    let onAvatar: () -> Void
    let onRegion: () -> Void
    let onCity: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(spacing: KXSpacing.sm) {
                Button(action: onAvatar) {
                    AvatarView(user: currentUser, size: 44)
                        .overlay(Circle().stroke(KXColor.cardBackground, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(currentUser.displayName)

                Text(L("appName", language))
                    .kxScaledFont(34, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                    .lineLimit(1)

                Spacer()

                // Quick jump into full search (posts / people / listings).
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .kxGlassCapsule()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("homeSearchEntry", language))
                .accessibilityIdentifier("home.search")

                // Single region entry — earlier we had both this chip
                // AND a separate `building.2` button that also opened
                // the city channel. Users found the duplication
                // confusing. Long-press the chip (or open Discover) to
                // jump into the city channel.
                RegionPickerButton(region: currentRegion, onTap: onRegion)

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
