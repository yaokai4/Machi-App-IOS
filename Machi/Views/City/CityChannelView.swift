import SwiftData
import SwiftUI

struct CityChannelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var languageManager = LanguageManager.shared
    @EnvironmentObject private var composeStore: ComposeStore
    @StateObject private var viewModel = CityChannelViewModel()
    @State private var primary: CityChannel.Primary = .recommend

    let regionCode: String
    let currentUser: UserEntity
    var initialChannel: CityChannel = .recommend

    var body: some View {
        VStack(spacing: 0) {
            header
            CityPrimaryCategoryTabs(selection: $primary)
            CitySecondaryFilterChips(primary: primary, channel: secondaryBinding)
            channelDescription

            Group {
                switch viewModel.state {
                case .idle, .loading:
                    LoadingView()
                case .empty:
                    ScrollView {
                        ChannelEmptyState(channel: viewModel.channel) {
                            // Pop the global composer with the
                            // channel's primary ContentType
                            // pre-selected. Channel → ContentType
                            // mapping uses the first entry of
                            // channel.contentTypes; falls back to
                            // .dynamic so "推荐 / 热榜" still gets
                            // a usable composer.
                            let type = viewModel.channel.contentTypes?.first ?? .dynamic
                            composeStore.requestCompose(type)
                            dismiss()
                        }
                        .padding(.top, KXSpacing.xl)
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
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(regionCode).\(initialChannel.rawValue)") {
            primary = initialChannel.primary
            viewModel.configure(regionCode: regionCode, channel: initialChannel)
            await viewModel.loadInitial(context: modelContext, currentUser: currentUser, postStore: postStore, clearExisting: true)
        }
        .onChange(of: viewModel.channel) { _, _ in
            Task {
                await viewModel.loadInitial(
                    context: modelContext,
                    currentUser: currentUser,
                    postStore: postStore,
                    clearExisting: true
                )
            }
        }
        .onChange(of: languageManager.preferred) { _, _ in
            Task {
                await viewModel.loadInitial(
                    context: modelContext,
                    currentUser: currentUser,
                    postStore: postStore,
                    clearExisting: true
                )
            }
        }
    }

    /// Two-way binding to the secondary channel that also makes sure
    /// the primary stays in sync (e.g. legacy deep-links open a
    /// sub-channel directly).
    private var secondaryBinding: Binding<CityChannel> {
        Binding {
            // Snap to a default channel of the current primary if the
            // existing viewModel.channel doesn't belong to it.
            primary.channels.contains(viewModel.channel) ? viewModel.channel : (primary.channels.first ?? .recommend)
        } set: { newValue in
            viewModel.channel = newValue
            primary = newValue.primary
        }
    }

    private var header: some View {
        HStack(spacing: KXSpacing.sm) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.region.map { "\($0.countryEmoji) \(KaiXRegionDirectory.localizedMetroName(for: $0, language: language) ?? KaiXRegionDirectory.localizedShortLabel($0, language: language))" } ?? L("selectCity", language))
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(L("cityChannel", language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.md)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private var channelDescription: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: viewModel.channel == .hot ? "flame.fill" : "info.circle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(viewModel.channel == .hot ? KaiXTheme.heat : KXColor.accent)
            Text(viewModel.channel.description(language))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.vertical, 5)
        .background(KXColor.softBackground.opacity(0.72))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.18)
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.posts) { post in
                    let displayedPost = postStore.post(id: post.id) ?? post
                    let originalPost = displayedPost.repostOfPostId.flatMap { postStore.post(id: $0) }
                    let isQuoteRepost = originalPost != nil && !displayedPost.previewText.isEmpty
                    let targetPost = isQuoteRepost ? displayedPost : (originalPost ?? displayedPost)
                    PostCardView(
                        post: displayedPost,
                        author: viewModel.authors[displayedPost.authorId],
                        mediaItems: viewModel.mediaByPostId[displayedPost.id] ?? [],
                        currentUser: currentUser,
                        originalPost: originalPost,
                        originalAuthor: originalPost.flatMap { viewModel.authors[$0.authorId] },
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
                        await viewModel.loadMoreIfNeeded(context: modelContext, currentUser: currentUser, post: displayedPost, postStore: postStore)
                    }
                }

                if viewModel.isLoadingMore {
                    KXInlineLoader()
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.vertical, KXSpacing.sm)
            .padding(.bottom, chrome.bottomContentPadding)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await viewModel.refresh(context: modelContext, currentUser: currentUser, postStore: postStore)
        }
    }
}
