import SwiftData
import SwiftUI
import UIKit

struct PostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var chrome: AppChromeState
    @EnvironmentObject private var postStore: PostStore
    @EnvironmentObject private var commentStore: CommentStore
    @EnvironmentObject private var router: KXRouter
    @StateObject private var viewModel = PostDetailViewModel()
    @State private var sortMode = CommentSortMode.hot
    @State private var replyingTo: CommentEntity?
    @State private var expandedReplyIds = Set<String>()
    @State private var didApplyInitialFocus = false
    @State private var isShowingDeleteConfirm = false
    @State private var isShowingEditPost = false
    @State private var editPostText = ""
    @State private var localActionMessage: String?
    @State private var isPostMutationInFlight = false
    @FocusState private var isCommentFieldFocused: Bool

    let postId: String
    let currentUser: UserEntity
    let initialFocus: PostDetailInitialFocus

    init(postId: String, currentUser: UserEntity, initialFocus: PostDetailInitialFocus = .none) {
        self.postId = postId
        self.currentUser = currentUser
        self.initialFocus = initialFocus
    }

    private var commentGroups: CommentGroups {
        var roots: [CommentEntity] = []
        var repliesByParent: [String: [CommentEntity]] = [:]
        for comment in viewModel.comments {
            if let parentId = comment.parentCommentId {
                repliesByParent[parentId, default: []].append(comment)
            } else {
                roots.append(comment)
            }
        }

        roots = sorted(roots)
        for key in repliesByParent.keys {
            repliesByParent[key] = sorted(repliesByParent[key] ?? [])
        }
        return CommentGroups(roots: roots, repliesByParent: repliesByParent)
    }

    private func sorted(_ comments: [CommentEntity]) -> [CommentEntity] {
        switch sortMode {
        case .latest:
            comments.sorted { $0.createdAt > $1.createdAt }
        case .hot:
            comments.sorted {
                if $0.likeCount == $1.likeCount {
                    return $0.createdAt > $1.createdAt
                }
                return $0.likeCount > $1.likeCount
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch viewModel.state {
                case .loading, .idle:
                    LoadingView()
                case .error(let message):
                    ErrorStateView(message: message) {
                        Task { await viewModel.load(context: modelContext, postId: postId, currentUser: currentUser, postStore: postStore, commentStore: commentStore) }
                    }
                case .empty:
                    postUnavailableState
                case .loaded:
                    content
                }
            }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.post != nil {
                commentInput
            }
        }
        .task(id: postId) {
            await viewModel.load(context: modelContext, postId: postId, currentUser: currentUser, postStore: postStore, commentStore: commentStore)
        }
        .onChange(of: isCommentFieldFocused) { _, focused in
            chrome.setHidden(focused, reason: .input)
        }
        .onChange(of: viewModel.state) { _, _ in
            didApplyInitialFocus = false
        }
        .onDisappear {
            chrome.setHidden(false, reason: .input)
        }
        .confirmationDialog(L("deletePost", language), isPresented: $isShowingDeleteConfirm, titleVisibility: .visible) {
            Button(L("deletePost", language), role: .destructive) {
                Task { await deleteOwnedPost() }
            }
            Button(L("cancel", language), role: .cancel) {}
        } message: {
            Text(L("deletePostConfirm", language))
        }
        .sheet(isPresented: $isShowingEditPost) {
            editPostSheet
        }
        .alert(L("error", language), isPresented: Binding(
            get: { viewModel.transientPostError != nil },
            set: { if !$0 { viewModel.transientPostError = nil } }
        )) {
            Button(L("ok", language), role: .cancel) {}
        } message: {
            Text(viewModel.transientPostError ?? "")
        }
        .alert(L("ok", language), isPresented: Binding(
            get: { localActionMessage != nil },
            set: { if !$0 { localActionMessage = nil } }
        )) {
            Button(L("ok", language), role: .cancel) {}
        } message: {
            Text(localActionMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
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

            Spacer()

            Text(L("postDetails", language))
                .font(.headline.weight(.semibold))

            Spacer()

            Menu {
                if canModifyPost {
                    Button {
                        editPostText = viewModel.post?.content ?? ""
                        isShowingEditPost = true
                    } label: {
                        Label(L("editPost", language), systemImage: "pencil")
                    }
                    .disabled(isPostMutationInFlight)

                    Button(role: .destructive) {
                        isShowingDeleteConfirm = true
                    } label: {
                        Label(L("deletePost", language), systemImage: "trash")
                    }
                    .disabled(isPostMutationInFlight)
                }

                Button {
                    copyPostLink()
                } label: {
                    Label(L("copyLink", language), systemImage: "link")
                }

                Button {
                    copyPostLink(successMessage: L("shareLinkReady", language))
                } label: {
                    Label(L("sharePost", language), systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    localActionMessage = L("reportRecorded", language)
                } label: {
                    Label(L("reportPost", language), systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.md)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private var canModifyPost: Bool {
        viewModel.post?.authorId == currentUser.id
    }

    private var editPostSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $editPostText)
                    .font(KXTypography.body)
                    .scrollContentBackground(.hidden)
                    .padding(KXSpacing.md)
                    .frame(minHeight: 220)
                    .kxGlassSurface(radius: KXRadius.lg)
                    .padding(KXSpacing.screen)
                Spacer()
            }
            .kxPageBackground()
            .navigationTitle(L("editPost", language))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("cancel", language)) {
                        isShowingEditPost = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("save", language)) {
                        Task { await saveEditedPost() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSaveEdit)
                }
            }
            .overlay(alignment: .bottom) {
                if isPostMutationInFlight {
                    ProgressView()
                        .padding(.bottom, KXSpacing.md)
                }
            }
        }
    }

    private var canSaveEdit: Bool {
        let trimmed = editPostText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPostMutationInFlight, !trimmed.isEmpty else { return false }
        return trimmed != (viewModel.post?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    private func saveEditedPost() async {
        guard !isPostMutationInFlight else { return }
        isPostMutationInFlight = true
        defer { isPostMutationInFlight = false }
        if await viewModel.updatePost(context: modelContext, content: editPostText, postStore: postStore) {
            isShowingEditPost = false
            localActionMessage = L("postUpdated", language)
        }
    }

    private func deleteOwnedPost() async {
        guard !isPostMutationInFlight else { return }
        isPostMutationInFlight = true
        let didDelete = await viewModel.deletePost(context: modelContext, postStore: postStore)
        isPostMutationInFlight = false
        if didDelete {
            localActionMessage = L("postDeletedDone", language)
            dismiss()
        }
    }

    private func copyPostLink(successMessage: String? = nil) {
        guard let post = viewModel.post else {
            router.routeErrorMessage = L("postDeletedHelp", language)
            return
        }
        UIPasteboard.general.string = "machi://post/\(post.id)"
        localActionMessage = successMessage ?? L("linkCopied", language)
    }

    private var postUnavailableState: some View {
        VStack(spacing: KXSpacing.md) {
            EmptyStateView(
                title: L("postDeleted", language),
                subtitle: L("postDeletedHelp", language),
                systemImage: "doc.text.magnifyingglass"
            )
            Button(L("retry", language)) {
                Task { await viewModel.load(context: modelContext, postId: postId, currentUser: currentUser, postStore: postStore, commentStore: commentStore) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, KXSpacing.screen)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: KXSpacing.sm) {
                    if let post = postStore.post(id: postId) ?? viewModel.post {
                        PostCardView(
                            post: post,
                            author: viewModel.author,
                            mediaItems: viewModel.media,
                            currentUser: currentUser,
                            originalPost: viewModel.originalPost,
                            originalAuthor: viewModel.originalAuthor,
                            originalMediaItems: viewModel.originalMedia,
                            showsMenu: false,
                            onOpen: { },
                            onOpenOriginal: { if let originalPost = viewModel.originalPost { router.open(.postDetail(postId: originalPost.id)) } },
                            onAuthor: { router.open(.profile(userId: post.authorId)) },
                            onTag: { router.open(.topic(tag: $0)) },
                            onComment: { focusComments(proxy) },
                            onLike: { Task { await viewModel.toggleLike(context: modelContext, currentUser: currentUser, postStore: postStore) } },
                            onBookmark: { Task { await viewModel.toggleBookmark(context: modelContext, currentUser: currentUser, postStore: postStore) } },
                            onRepost: { Task { await viewModel.repost(context: modelContext, currentUser: currentUser, postStore: postStore) } },
                            onQuoteRepost: { content in
                                Task { await viewModel.quoteRepost(context: modelContext, currentUser: currentUser, content: content, postStore: postStore) }
                            }
                        )
                        .equatable()

                        // Per-type structured field block. Renders only
                        // when the post has typed attributes — e.g. a
                        // secondhand listing shows price / condition /
                        // area; a meetup shows time / location / people
                        // limit. Generic dynamic posts get an EmptyView
                        // and the layout falls through to comments.
                        PostSpecificDetailSection(post: post, currentUser: currentUser)
                    }

                    commentHeader
                        .id(CommentAnchor.header)

                    switch viewModel.commentState {
                    case .idle, .loading:
                        LoadingView()
                            .frame(maxWidth: .infinity)
                    case .failed(let message):
                        if viewModel.comments.isEmpty {
                            ErrorStateView(message: commentErrorText(message)) {
                                Task { await viewModel.reloadComments(context: modelContext, commentStore: commentStore) }
                            }
                        } else {
                            commentFailureBanner(message: commentErrorText(message))
                            commentList
                        }
                    case .empty:
                        EmptyStateView(title: L("noComments", language), subtitle: L("writeComment", language), systemImage: "bubble.left")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    case .loaded:
                        if let transientCommentError = viewModel.transientCommentError {
                            commentFailureBanner(message: transientCommentError)
                        }
                        commentList
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.vertical, KXSpacing.sm)
                .padding(.bottom, KXSpacing.xl)
            }
            .onChange(of: viewModel.commentState) { _, _ in
                applyInitialFocusIfNeeded(proxy)
            }
            .onChange(of: viewModel.comments.count) { _, _ in
                applyInitialFocusIfNeeded(proxy)
            }
        }
    }

    @ViewBuilder
    private var commentList: some View {
        let groups = commentGroups
        ForEach(groups.roots) { comment in
            commentThread(comment, replies: groups.repliesByParent[comment.id] ?? [])
                .id(comment.id)
        }
        if groups.roots.isEmpty && !viewModel.comments.isEmpty {
            ForEach(viewModel.comments) { comment in
                commentThread(comment, replies: [])
                    .id(comment.id)
            }
        }
    }

    private func commentFailureBanner(message: String) -> some View {
        HStack(spacing: KXSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(KXColor.accent.opacity(0.82))
            Text(message)
                .font(KXTypography.metaEmphasis)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button(L("retry", language)) {
                Task { await viewModel.reloadComments(context: modelContext, commentStore: commentStore) }
            }
            .font(KXTypography.metaEmphasis)
            .buttonStyle(.plain)
            .foregroundStyle(KXColor.accent)
        }
        .padding(KXSpacing.md)
        .kxGlassSurface(radius: KXRadius.md)
    }

    private func detailMetrics(_ post: PostEntity) -> some View {
        HStack(spacing: 10) {
            DetailMetric(title: L("comments", language), value: post.commentCount)
            DetailMetric(title: L("repost", language), value: post.repostCount)
            DetailMetric(title: L("like", language), value: post.likeCount)
            DetailMetric(title: L("bookmark", language), value: post.bookmarkCount)
            DetailMetric(title: L("heat", language), value: Int(post.heatScore), tint: KaiXTheme.heat)
        }
        .padding(14)
        .kxGlassSurface(radius: KXRadius.lg)
    }

    private func commentThread(_ comment: CommentEntity, replies: [CommentEntity]) -> some View {
        let isExpanded = expandedReplyIds.contains(comment.id)
        let visibleReplies = isExpanded ? replies : Array(replies.prefix(2))

        return VStack(alignment: .leading, spacing: 8) {
            CommentRowView(
                comment: comment,
                author: viewModel.commentAuthors[comment.authorId],
                currentUser: currentUser,
                onOpenAuthor: { router.open(.profile(userId: comment.authorId)) },
                onLike: { Task { await viewModel.toggleCommentLike(context: modelContext, comment: comment) } },
                onReply: { startReply(to: comment) },
                onReport: { localActionMessage = L("reportRecorded", language) },
                onDelete: {
                    Task { await viewModel.deleteComment(context: modelContext, comment: comment, postStore: postStore, commentStore: commentStore) }
                }
            )

            if !visibleReplies.isEmpty {
                HStack(alignment: .top, spacing: KXSpacing.sm) {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(KXColor.separator)
                        .frame(width: 2)
                        .padding(.vertical, KXSpacing.sm)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleReplies.enumerated()), id: \.element.id) { index, reply in
                            ReplyRowView(
                                comment: reply,
                                author: viewModel.commentAuthors[reply.authorId],
                                onOpenAuthor: { router.open(.profile(userId: reply.authorId)) },
                                onLike: { Task { await viewModel.toggleCommentLike(context: modelContext, comment: reply) } },
                                onReply: { startReply(to: reply) },
                                onReport: { localActionMessage = L("reportRecorded", language) },
                                canDelete: reply.authorId == currentUser.id,
                                onDelete: {
                                    Task { await viewModel.deleteComment(context: modelContext, comment: reply, postStore: postStore, commentStore: commentStore) }
                                }
                            )
                            .id(reply.id)

                            if index < visibleReplies.count - 1 {
                                Divider()
                                    .opacity(0.3)
                                    .padding(.leading, 42)
                            }
                        }

                        if replies.count > 2 {
                            Button {
                                if isExpanded {
                                    expandedReplyIds.remove(comment.id)
                                } else {
                                    expandedReplyIds.insert(comment.id)
                                }
                            } label: {
                                Label(
                                    isExpanded ? L("hideReplies", language) : "\(L("viewMoreReplies", language)) \(replies.count - 2)",
                                    systemImage: isExpanded ? "chevron.up" : "chevron.down"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(KXColor.accent)
                                .frame(minHeight: 34, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 42)
                            .padding(.top, KXSpacing.xs)
                        }
                    }
                    .padding(.horizontal, KXSpacing.sm)
                    .padding(.vertical, KXSpacing.xs)
                    .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                            .stroke(KXColor.separator, lineWidth: 0.6)
                    }
                }
                .padding(.leading, KXAvatarSize.sm + KXSpacing.sm)
            }
        }
    }

    private var commentHeader: some View {
        HStack {
            Text(L("comments", language))
                .font(KXTypography.section)
            Spacer()
            KXSegmentedControl(CommentSortMode.allCases, selection: $sortMode, itemMinWidth: 58, itemHeight: 30) { mode in
                Text(mode.title(language))
            }
            .frame(width: 148)
        }
        .padding(.top, 4)
    }

    private var commentInput: some View {
        let canSendComment = !viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: KXSpacing.sm) {
            if let transientCommentError = viewModel.transientCommentError {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(KXColor.accent.opacity(0.82))
                    Text(transientCommentError)
                        .font(KXTypography.metaEmphasis)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    if viewModel.failedCommentDraft != nil {
                        Button(L("retry", language)) {
                            Task {
                                await viewModel.retryFailedComment(
                                    context: modelContext,
                                    currentUser: currentUser,
                                    postStore: postStore,
                                    commentStore: commentStore
                                )
                            }
                        }
                        .font(KXTypography.metaEmphasis)
                        .buttonStyle(.plain)
                    }
                }
            }

            if let replyingTo {
                HStack {
                    Text("\(L("reply", language)) @\(viewModel.commentAuthors[replyingTo.authorId]?.username ?? L("unknownUser", language))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        self.replyingTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: KXSpacing.sm) {
                AvatarView(user: currentUser, size: KXAvatarSize.sm)
                TextField(L("writeComment", language), text: $viewModel.commentText, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($isCommentFieldFocused)
                    .padding(.horizontal, KXSpacing.md)
                    .padding(.vertical, KXSpacing.sm)
                    .kxGlassSurface(radius: KXRadius.md)

                Button {
                    if currentUser.isGuest { GuestGate.shared.requireLogin(); return }
                    let parentId = replyingTo?.id
                    Task {
                        await viewModel.sendComment(context: modelContext, currentUser: currentUser, postStore: postStore, commentStore: commentStore, parentCommentId: parentId)
                        replyingTo = nil
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.semibold))
                }
                .frame(width: 38, height: 38)
                .foregroundStyle(canSendComment ? KXColor.accent : Color.secondary)
                .background {
                    Circle()
                        .fill(canSendComment ? KXColor.accent.opacity(0.12) : KXColor.glassControlTint)
                }
                .glassEffect((canSendComment ? KXGlass.selected : KXGlass.control).interactive(), in: Circle())
                .clipShape(Circle())
                .overlay(Circle().stroke(KXColor.glassStroke, lineWidth: 0.75))
                .disabled(!canSendComment)
            }
        }
        .padding(.horizontal, KXSpacing.screen)
        .padding(.vertical, KXSpacing.sm)
        .kxGlassBar()
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }

    private func focusComments(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.24)) {
            proxy.scrollTo(CommentAnchor.header, anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            isCommentFieldFocused = true
        }
    }

    private func startReply(to comment: CommentEntity) {
        replyingTo = comment
        isCommentFieldFocused = true
    }

    private func commentErrorText(_ message: String) -> String {
        message == "commentSyncError" ? L("commentSyncError", language) : message
    }

    private func applyInitialFocusIfNeeded(_ proxy: ScrollViewProxy) {
        guard !didApplyInitialFocus else { return }
        guard viewModel.commentState != .idle && viewModel.commentState != .loading else { return }
        didApplyInitialFocus = true
        switch initialFocus {
        case .none:
            break
        case .comments:
            focusComments(proxy)
        case .comment(let commentId):
            if let parentId = viewModel.comments.first(where: { $0.id == commentId })?.parentCommentId {
                expandedReplyIds.insert(parentId)
            }
            DispatchQueue.main.async {
                withAnimation(.snappy(duration: 0.24)) {
                    proxy.scrollTo(commentId, anchor: .center)
                }
            }
        }
    }
}

enum PostDetailInitialFocus: Hashable {
    case none
    case comments
    case comment(String)
}

private enum CommentAnchor {
    case header
}

private struct CommentGroups {
    let roots: [CommentEntity]
    let repliesByParent: [String: [CommentEntity]]
}

private enum CommentSortMode: String, CaseIterable, Identifiable {
    case hot
    case latest

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .latest: L("latest", language)
        case .hot: L("top", language)
        }
    }
}

private struct DetailMetric: View {
    let title: String
    let value: Int
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 3) {
            Text(NumberFormatterUtils.compact(value))
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CommentRowView: View {
    @Environment(\.appLanguage) private var language
    let comment: CommentEntity
    let author: UserEntity?
    let currentUser: UserEntity
    let onOpenAuthor: () -> Void
    let onLike: () -> Void
    let onReply: () -> Void
    let onReport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.sm) {
            Button(action: onOpenAuthor) {
                AvatarView(user: author, size: KXAvatarSize.sm)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(author?.displayName ?? L("unknownUser", language))

            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Button(action: onOpenAuthor) {
                    HStack(spacing: 5) {
                        Text(author?.displayName ?? L("unknownUser", language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if author?.displaysVerifiedBadge == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        Text(DateFormatterUtils.relativeText(from: comment.createdAt, language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Text(comment.content)
                    .font(KXTypography.body)

                HStack(spacing: KXSpacing.sm) {
                    CommentActionButton(title: L("reply", language), systemImage: "arrowshape.turn.up.left", action: onReply)

                    CommentActionButton(
                        title: NumberFormatterUtils.compact(comment.likeCount),
                        systemImage: comment.isLikedByCurrentUser ? "heart.fill" : "heart",
                        tint: comment.isLikedByCurrentUser ? .pink : .secondary,
                        action: onLike
                    )

                    Spacer(minLength: KXSpacing.sm)

                    Menu {
                        if comment.authorId == currentUser.id {
                            Button(L("delete", language), role: .destructive, action: onDelete)
                        } else {
                            Button(L("reportComment", language), role: .destructive, action: onReport)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(KXColor.softBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(KXSpacing.lg)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}

private struct ReplyRowView: View {
    @Environment(\.appLanguage) private var language
    let comment: CommentEntity
    let author: UserEntity?
    let onOpenAuthor: () -> Void
    let onLike: () -> Void
    let onReply: () -> Void
    let onReport: () -> Void
    var canDelete = false
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.sm) {
            Button(action: onOpenAuthor) {
                AvatarView(user: author, size: KXAvatarSize.xs)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: KXSpacing.xs) {
                Button(action: onOpenAuthor) {
                    HStack(spacing: 5) {
                        Text(author?.displayName ?? L("unknownUser", language))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(DateFormatterUtils.relativeText(from: comment.createdAt, language: language))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Text(comment.content)
                    .font(.subheadline)

                HStack(spacing: KXSpacing.sm) {
                    CommentActionButton(title: L("reply", language), systemImage: "arrowshape.turn.up.left", action: onReply)

                    CommentActionButton(
                        title: NumberFormatterUtils.compact(comment.likeCount),
                        systemImage: comment.isLikedByCurrentUser ? "heart.fill" : "heart",
                        tint: comment.isLikedByCurrentUser ? .pink : .secondary,
                        action: onLike
                    )

                    Spacer(minLength: KXSpacing.sm)

                    Menu {
                        if canDelete {
                            Button(L("delete", language), role: .destructive, action: onDelete)
                        } else {
                            Button(L("reportComment", language), role: .destructive, action: onReport)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(KXColor.cardBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.vertical, KXSpacing.sm)
        .padding(.horizontal, KXSpacing.xs)
    }
}

private struct CommentActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .background(KXColor.softBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
