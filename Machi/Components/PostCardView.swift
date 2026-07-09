import SwiftUI
import SwiftData
import UIKit

struct PostCardView: View, Equatable {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @State private var isShowingRepostOptions = false
    @State private var isShowingQuoteDialog = false
    @State private var isShowingEditPost = false
    @State private var isShowingDeleteConfirm = false
    @State private var isPostMutationInFlight = false
    @State private var isHiddenAfterDelete = false
    @State private var editPostText = ""
    @State private var quoteText = ""
    @State private var cardMessage: String?
    @State private var cardError: String?
    @State private var isTextExpanded = false

    let post: PostEntity
    let author: UserEntity?
    let mediaItems: [MediaEntity]
    var currentUser: UserEntity?
    var originalPost: PostEntity?
    var originalAuthor: UserEntity?
    var originalMediaItems: [MediaEntity] = []
    var showsMenu = true
    /// When true (post detail), the body text is never truncated: the detail
    /// page is the ONLY place the full text lives, and the character-count
    /// heuristic (`shouldShowExpand`) can miss real CJK / large-Dynamic-Type
    /// wrapping — a miss there would leave the clipped tail unreachable.
    /// Feed cards keep `false` (4-line clamp, tap = open detail).
    var expandOnTap = false
    var onOpen: () -> Void = {}
    var onOpenOriginal: () -> Void = {}
    var onAuthor: () -> Void = {}
    var onTag: (String) -> Void = { _ in }
    var onComment: () -> Void = {}
    let onLike: () -> Void
    let onBookmark: () -> Void
    let onRepost: () -> Void
    var onQuoteRepost: (String) -> Void = { _ in }

    static func == (lhs: PostCardView, rhs: PostCardView) -> Bool {
        lhs.post.id == rhs.post.id
        && lhs.post.content == rhs.post.content
        && lhs.post.updatedAt == rhs.post.updatedAt
        && lhs.post.likeCount == rhs.post.likeCount
        && lhs.post.repostCount == rhs.post.repostCount
        && lhs.post.bookmarkCount == rhs.post.bookmarkCount
        && lhs.post.commentCount == rhs.post.commentCount
        && lhs.post.heatScore == rhs.post.heatScore
        && lhs.post.isLikedByCurrentUser == rhs.post.isLikedByCurrentUser
        && lhs.post.isBookmarkedByCurrentUser == rhs.post.isBookmarkedByCurrentUser
        && lhs.post.isRepostedByCurrentUser == rhs.post.isRepostedByCurrentUser
        && lhs.post.country == rhs.post.country
        && lhs.post.province == rhs.post.province
        && lhs.post.city == rhs.post.city
        && lhs.post.regionCode == rhs.post.regionCode
        && lhs.post.contentTypeRaw == rhs.post.contentTypeRaw
        && lhs.post.attributesRaw == rhs.post.attributesRaw
        && lhs.post.language == rhs.post.language
        && lhs.post.isBoosted == rhs.post.isBoosted
        && lhs.author?.id == rhs.author?.id
        && lhs.author?.updatedAt == rhs.author?.updatedAt
        && lhs.mediaItems.elementsEqual(rhs.mediaItems) { $0.id == $1.id }
        && lhs.originalPost?.id == rhs.originalPost?.id
        && lhs.originalPost?.updatedAt == rhs.originalPost?.updatedAt
        && lhs.originalPost?.likeCount == rhs.originalPost?.likeCount
        && lhs.originalPost?.repostCount == rhs.originalPost?.repostCount
        && lhs.originalPost?.bookmarkCount == rhs.originalPost?.bookmarkCount
        && lhs.originalPost?.commentCount == rhs.originalPost?.commentCount
        && lhs.originalPost?.isLikedByCurrentUser == rhs.originalPost?.isLikedByCurrentUser
        && lhs.originalPost?.isBookmarkedByCurrentUser == rhs.originalPost?.isBookmarkedByCurrentUser
        && lhs.originalPost?.isRepostedByCurrentUser == rhs.originalPost?.isRepostedByCurrentUser
        && lhs.originalAuthor?.id == rhs.originalAuthor?.id
        && lhs.originalAuthor?.updatedAt == rhs.originalAuthor?.updatedAt
        && lhs.originalMediaItems.elementsEqual(rhs.originalMediaItems) { $0.id == $1.id }
        && lhs.currentUser?.id == rhs.currentUser?.id
        && lhs.showsMenu == rhs.showsMenu
    }

    var body: some View {
        let isQuoteRepost = originalPost != nil && !post.previewText.isEmpty
        let contentPost = isQuoteRepost ? post : (originalPost ?? post)
        let contentAuthor = isQuoteRepost ? author : (originalAuthor ?? author)
        let contentMedia = isQuoteRepost ? mediaItems : (originalPost == nil ? mediaItems : originalMediaItems)
        let visibleHashtags = visibleHashtags(for: contentPost)
        let authorPresentation = officialAuthorPresentation(for: contentPost, author: contentAuthor)

        return Group {
            if isHiddenAfterDelete {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: KXSpacing.sm) {
                    if post.repostOfPostId != nil {
                        Button(action: onAuthor) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.2.squarepath")
                                    .font(.caption2.weight(.bold))
                                KXAvatar(user: author, size: 18)
                                Text("\(author?.displayName ?? L("unknownUser", language)) \(isQuoteRepost ? L("quotePost", language) : L("repostedBy", language))")
                                    .font(KXTypography.metaEmphasis)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.leading, KXSpacing.xxs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(alignment: .top, spacing: KXSpacing.sm) {
                        Button(action: onAuthor) {
                            // Seed/curated posts are attributed to a synthetic
                            // editorial persona with no real account, so they
                            // keep the Machi "M" brand mark. A genuine official
                            // account (e.g. admin) shows its own uploaded avatar —
                            // KXAvatar/AvatarView still falls back to the "M" mark
                            // when that account hasn't set a custom avatar.
                            if authorPresentation.isOfficial && contentPost.isSeedContent {
                                MachiOfficialAvatarView(size: 38)
                            } else {
                                KXAvatar(user: contentAuthor, size: 38)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(authorPresentation.displayName)

                        Button(action: onAuthor) {
                            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                                HStack(spacing: KXSpacing.xs) {
                                    Text(authorPresentation.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                    if authorPresentation.isOfficial {
                                        KXOfficialBadge()
                                    } else if contentAuthor?.displaysVerifiedBadge == true {
                                        KXVerifiedBadge()
                                    }
                                    if let label = authorPresentation.label {
                                        OfficialSourceChip(title: label)
                                    }
                                }
                                HStack(spacing: 5) {
                                    Text("@\(authorPresentation.username)")
                                        .font(KXTypography.meta)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text("·")
                                        .font(KXTypography.meta)
                                        .foregroundStyle(.tertiary)
                                    Text(DateFormatterUtils.relativeText(from: contentPost.createdAt, language: language))
                                        .font(KXTypography.meta)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if let region = postRegion(contentPost) {
                                        Text("·")
                                            .font(KXTypography.meta)
                                            .foregroundStyle(.tertiary)
                                        Text(KaiXRegionDirectory.localizedHeaderLabel(region, language: language))
                                            .font(KXTypography.meta)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .layoutPriority(1)

                        Spacer(minLength: KXSpacing.xs)

                        if showsMenu {
                            postMenuButton
                        }
                    }

                    metadataRow(for: contentPost)

                    if contentPost.contentType == .question {
                        // 提问帖不用等打开详情:问题本身在卡片上就是主角,
                        // 附带回答数 / 作答 CTA,让人一眼认出「这是一个提问」。
                        questionPanel(for: contentPost)
                    } else if !contentPost.previewText.isEmpty {
                        if expandOnTap {
                            // 详情页是全文的唯一去处:shouldShowExpand 的字符数启发式与真实
                            // 折行无关(CJK 每行仅 20 余字、动态大字号下更少),约 60–96 字的
                            // 多段帖会被截在 4 行却不出现「查看全文」,后面的内容彻底不可达。
                            // 所以详情页正文永不截断;折叠/展开只保留在 Feed 卡片上。
                            Text(contentPost.previewText)
                                .kxScaledFont(15, relativeTo: .body, weight: .regular)
                                .foregroundStyle(.primary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Button(action: onOpen) {
                                Text(contentPost.previewText)
                                    .kxScaledFont(15, relativeTo: .body, weight: .regular)
                                    .foregroundStyle(.primary)
                                    .lineSpacing(2)
                                    .lineLimit(isTextExpanded ? nil : 4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            if shouldShowExpand(for: contentPost.previewText) {
                                Button {
                                    withAnimation(.snappy(duration: 0.18)) {
                                        isTextExpanded.toggle()
                                    }
                                } label: {
                                    Text(isTextExpanded ? L("collapseText", language) : L("viewFullText", language))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(KXColor.accent)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, -2)
                            }
                        }
                    }

                    if !visibleHashtags.isEmpty {
                        TagWrapView(tags: visibleHashtags, onTap: onTag)
                    }

                    if !contentMedia.isEmpty {
                        MediaGridView(mediaItems: contentMedia)
                    }

                    if isQuoteRepost, let originalPost {
                        QuotedPostPreview(
                            post: originalPost,
                            author: originalAuthor,
                            mediaItems: originalMediaItems,
                            onOpen: onOpenOriginal
                        )
                    }

                    KXInteractionBar(
                        post: contentPost,
                        onComment: onComment,
                        onRepost: guestGated(handleRepostTap),
                        onLike: guestGated(onLike),
                        onBookmark: guestGated(onBookmark)
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .kxGlassSurface(radius: KXRadius.lg)
                .contentShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
                .gesture(TapGesture().onEnded {
                    // 详情页(expandOnTap)正文已永不截断,整卡点按不再承担
                    // 「展开」职责;保留手势本身吞掉点按,避免误触穿透。
                    if !expandOnTap { onOpen() }
                }, including: .gesture)
            }
        }
        .confirmationDialog(L("repost", language), isPresented: $isShowingRepostOptions, titleVisibility: .visible) {
            Button(L("undoRepost", language), role: .destructive, action: onRepost)
            Button(L("quotePost", language)) {
                quoteText = ""
                isShowingQuoteDialog = true
            }
            Button(L("cancel", language), role: .cancel) {}
        }
        .alert(L("quotePost", language), isPresented: $isShowingQuoteDialog) {
            TextField(L("quotePlaceholder", language), text: $quoteText)
            Button(L("publish", language)) {
                let trimmed = quoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onQuoteRepost(trimmed)
                quoteText = ""
            }
            Button(L("cancel", language), role: .cancel) {
                quoteText = ""
            }
        }
        .confirmationDialog(L("deletePost", language), isPresented: $isShowingDeleteConfirm, titleVisibility: .visible) {
            Button(L("deletePost", language), role: .destructive) {
                Task { await deleteMenuTargetPost() }
            }
            Button(L("cancel", language), role: .cancel) {}
        } message: {
            Text(L("deletePostConfirm", language))
        }
        .sheet(isPresented: $isShowingEditPost) {
            editPostSheet
        }
        .alert(L("ok", language), isPresented: Binding(
            get: { cardMessage != nil },
            set: { if !$0 { cardMessage = nil } }
        )) {
            Button(L("ok", language), role: .cancel) {}
        } message: {
            Text(cardMessage ?? "")
        }
        .alert(L("error", language), isPresented: Binding(
            get: { cardError != nil },
            set: { if !$0 { cardError = nil } }
        )) {
            Button(L("ok", language), role: .cancel) {}
        } message: {
            Text(cardError ?? "")
        }
    }

    /// Resolve a post's region into a hydrated chip-ready object.
    /// Tries the canonical `regionCode` first, then falls back to
    /// stitching together (country, province, city) for posts created
    /// before the Phase-1 region pivot.
    private func postRegion(_ post: PostEntity) -> KaiXRegionDirectory.Region? {
        if !post.regionCode.isEmpty {
            return KaiXRegionDirectory.resolve(regionCode: post.regionCode)
        }
        guard !post.country.isEmpty, !post.city.isEmpty else { return nil }
        let province = post.province.isEmpty ? nil : post.province
        return KaiXRegionDirectory.make(country: post.country, province: province, city: post.city)
    }

    private func officialAuthorPresentation(for post: PostEntity, author: UserEntity?) -> PostAuthorPresentation {
        let authorIsOfficial = author?.isMachiOfficialAccount == true
        // The editorial / assistant persona override is ONLY for actual seed
        // content authored by an official seed-bot account. Two cases must keep
        // their own identity instead:
        //   • Real "city user" persona seed posts (not official) → their own name.
        //   • Genuine posts a real official account wrote by hand — e.g. the
        //     @admin "Machi 官方" account — must NOT be relabelled to 城市助手/编辑部.
        // A previous fix keyed off isMachiOfficialAccount alone and dropped the
        // isSeedContent check, so every admin/official post rendered as the
        // assistant desk with a swapped @handle. Require BOTH conditions.
        guard post.isSeedContent, authorIsOfficial else {
            return PostAuthorPresentation(
                displayName: author?.displayName ?? L("unknownUser", language),
                username: author?.username ?? L("unknownUser", language),
                isOfficial: authorIsOfficial,
                label: authorIsOfficial ? L("machiOfficial", language) : nil
            )
        }

        let region = postRegion(post)
        let isTokyo = region?.countryCode == "jp" && region?.cityCode == "tokyo"
        let account: (name: String, username: String, label: String)
        switch post.contentType {
        case .question:
            account = ("Machi 城市助手", "machi_assistant_zh", L("cityAssistant", language))
        case .event, .news, .local_info:
            account = isTokyo
                ? ("Machi 东京编辑部", "machi_tokyo_editorial", L("editorialCurated", language))
                : ("Machi 日本生活编辑部", "machi_japan_life_editorial", L("editorialCurated", language))
        case .service, .merchant, .coupon:
            account = ("Machi 本地生活编辑部", "machi_local_life_editorial", L("localLifeDesk", language))
        case .guide, .housing, .roommate, .job_seek, .job_post, .referral, .warning:
            account = ("Machi 日本生活编辑部", "machi_japan_life_editorial", L("editorialCurated", language))
        default:
            if post.seedAuthorType == "editorial" {
                account = isTokyo
                    ? ("Machi 东京编辑部", "machi_tokyo_editorial", L("editorialCurated", language))
                    : ("Machi 日本生活编辑部", "machi_japan_life_editorial", L("editorialCurated", language))
            } else {
                account = ("Machi 城市助手", "machi_assistant_zh", L("cityAssistant", language))
            }
        }
        return PostAuthorPresentation(
            displayName: account.name,
            username: account.username,
            isOfficial: true,
            label: account.label
        )
    }

    /// Feed 卡片「查看全文」入口的启发式。注意它与真实折行行数无关(只看字符
    /// 数/段落数),所以只允许用在 Feed 上 —— Feed 漏判时点开详情仍能读到全文;
    /// 详情页(expandOnTap)一律不截断,绝不能依赖这个启发式。
    private func shouldShowExpand(for text: String) -> Bool {
        text.count > 96 || text.components(separatedBy: .newlines).count > 4
    }

    /// 提问帖的卡片主体:问题面板(问号徽章 + 问题原文 + 补充说明摘要 +
    /// 回答数/作答 CTA)。问题优先取 attributes.question(老帖),否则取正文
    /// 首行;剩余正文作为补充背景淡化展示。
    private func questionPanel(for post: PostEntity) -> some View {
        let preview = post.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attrQuestion = (post.stringAttribute(PostAttributeKeys.question) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = preview.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let question = attrQuestion.isEmpty ? (firstLine.isEmpty ? preview : firstLine) : attrQuestion
        // 正文以问题行开头时,剩余部分作为背景补充;完全相同则不重复展示。
        var body = ""
        if !preview.isEmpty, preview != question {
            if preview.hasPrefix(question) {
                body = String(preview.dropFirst(question.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                body = preview
            }
        }
        let tint = ContentType.question.spec.tint
        return Button {
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                HStack(alignment: .top, spacing: KXSpacing.sm) {
                    Image(systemName: "questionmark.circle.fill")
                        .kxScaledFont(17, weight: .bold)
                        .foregroundStyle(tint)
                        .padding(.top, 1)
                    Text(question)
                        .kxScaledFont(16, relativeTo: .body, weight: .semibold)
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        // 与正文同理:详情页是问题全文的唯一去处(结构化区块对
                        // question 只展示分类),永不截断;Feed 卡片保留行数上限。
                        .lineLimit(expandOnTap ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !body.isEmpty {
                    Text(body)
                        .kxScaledFont(14, relativeTo: .subheadline, weight: .regular)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .lineLimit(expandOnTap ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: KXSpacing.sm) {
                    if post.commentCount > 0 {
                        Label(String(format: L("questionAnswersFmt", language), post.commentCount), systemImage: "text.bubble.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                    } else {
                        Label(L("questionAwaiting", language), systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        Text(L("questionAnswerCTA", language))
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(KXSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(L("ct_question", language))：\(question)")
    }

    private func metadataRow(for post: PostEntity) -> some View {
        FlowLayout(spacing: 6) {
            let spec = post.contentType.spec
            CategoryChip(
                title: L(spec.titleKey, language),
                icon: post.contentType == .warning ? nil : spec.icon,
                tint: calmerTint(for: post.contentType)
            )
        }
    }

    private func visibleHashtags(for post: PostEntity) -> [String] {
        let redundantTags = redundantContentTags(for: post)
        return post.hashtags.filter { tag in
            let normalized = tag.normalizedTopicName
            return !redundantTags.contains(normalized)
        }
    }

    private func redundantContentTags(for post: PostEntity) -> Set<String> {
        var values = [L(post.contentType.spec.titleKey, language)]
        if post.contentType == .warning {
            values.append(contentsOf: ["避坑", "注意喚起", "warning", "avoid scams"])
        }
        return Set(values.map(\.normalizedTopicName).filter { !$0.isEmpty })
    }

    private func calmerTint(for type: ContentType) -> Color {
        switch type {
        case .warning:
            return KXColor.heat
        case .meetup, .dining:
            return Color.orange.opacity(0.86)
        default:
            return type.spec.tint
        }
    }

    private var menuTargetPost: PostEntity {
        if originalPost != nil && !post.previewText.isEmpty {
            return post
        }
        return originalPost ?? post
    }

    private var canModifyMenuTarget: Bool {
        currentUser?.id == menuTargetPost.authorId
    }

    private var canSaveEdit: Bool {
        let trimmed = editPostText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPostMutationInFlight, !trimmed.isEmpty else { return false }
        return trimmed != menuTargetPost.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var postMenuButton: some View {
        Menu {
            if canModifyMenuTarget {
                Button {
                    editPostText = menuTargetPost.content
                    isShowingEditPost = true
                } label: {
                    Label(L("editPost", language), systemImage: "pencil")
                }
                .disabled(isPostMutationInFlight)

                Button {
                    cardMessage = L("promoBackendOnlyMessage", language)
                } label: {
                    Label(L("promoBackendOnly", language), systemImage: "flame")
                }
                .disabled(true)

                Button(role: .destructive) {
                    isShowingDeleteConfirm = true
                } label: {
                    Label(L("deletePost", language), systemImage: "trash")
                }
                .disabled(isPostMutationInFlight)

                Divider()
            }

            ShareLink(
                item: postShareURL,
                subject: Text(postShareTitle),
                preview: SharePreview(postShareTitle)
            ) {
                Label(L("sharePost", language), systemImage: "square.and.arrow.up")
            }

            Button {
                copyPostLink()
            } label: {
                Label(L("copyLink", language), systemImage: "link")
            }

            Button(role: .destructive) {
                let reportedPostId = post.id
                Task {
                    do {
                        try await KaiXAPIClient.shared.reportPost(reportedPostId, reason: "other")
                        cardMessage = L("reportRecorded", language)
                    } catch {
                        cardMessage = error.kaixUserMessage
                    }
                }
            } label: {
                Label(L("reportPost", language), systemImage: "flag")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                // 不用 kxGlassCircle:它在 iOS<26 回退为 .ultraThinMaterial 实时
                // 模糊,且 .shadow 打在合成结果上(离屏 pass)——每张可见卡片都
                // 多付一次,×N 逐帧累加,与卡片主阴影的 120 Hz 优化(kxGlassSurface
                // 从不透明形状投射阴影)背道而驰。改为不透明圆 + 由该不透明形状
                // 直接投射同参数阴影:外观几乎一致,零模糊、零离屏合成。
                .background {
                    Circle()
                        .fill(KXColor.softBackground)
                        .shadow(color: KXColor.glassShadow.opacity(0.22), radius: 3, y: 1)
                }
                .overlay(Circle().stroke(KXColor.glassStroke, lineWidth: 0.75))
        }
        .disabled(isPostMutationInFlight)
        .accessibilityLabel(L("postActions", language))
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
                        Task { await saveMenuTargetPost() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSaveEdit)
                }
            }
            .overlay(alignment: .bottom) {
                if isPostMutationInFlight {
                    KXSpinner(size: 24, lineWidth: 2.6)
                        .padding(.bottom, KXSpacing.md)
                }
            }
        }
    }

    private func saveMenuTargetPost() async {
        guard !isPostMutationInFlight else { return }
        let target = menuTargetPost
        isPostMutationInFlight = true
        defer { isPostMutationInFlight = false }
        do {
            postStore.register(target)
            try await postStore.updatePost(context: modelContext, postId: target.id, content: editPostText)
            isShowingEditPost = false
            cardMessage = L("postUpdated", language)
        } catch {
            cardError = error.kaixUserMessage
        }
    }

    private func deleteMenuTargetPost() async {
        guard !isPostMutationInFlight else { return }
        let target = menuTargetPost
        isPostMutationInFlight = true
        defer { isPostMutationInFlight = false }
        do {
            postStore.register(target)
            try await postStore.deletePost(context: modelContext, postId: target.id)
            isHiddenAfterDelete = true
            cardMessage = L("postDeletedDone", language)
        } catch {
            cardError = error.kaixUserMessage
        }
    }

    private func copyPostLink(successMessage: String? = nil) {
        UIPasteboard.general.string = "machi://post/\(menuTargetPost.id)"
        cardMessage = successMessage ?? L("linkCopied", language)
    }

    /// Public web URL used by the system share sheet (a real link a recipient can
    /// open in any browser and that resolves back into the app via Universal
    /// Links). Falls back to the machicity.com root if the id is somehow empty.
    private var postShareURL: URL {
        URL(string: "https://machicity.com/p/\(menuTargetPost.id)") ?? URL(string: "https://machicity.com")!
    }

    /// Short human title for the share preview — the first line of the post,
    /// clipped, with a Machi-branded fallback for media-only posts.
    private var postShareTitle: String {
        let text = menuTargetPost.previewText
        if text.isEmpty { return "Machi" }
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
    }

    private func handleRepostTap() {
        // 「是否已转发」的判定必须与交互条展示、onRepost 的作用目标(列表页的
        // targetPost / 详情页的 interactionTarget)取同一个帖子:引用转发卡的
        // 交互条作用于引用帖本身,不是被引用的原帖。此前这里取 (originalPost
        // ?? post),引用卡拿到的是【原帖】状态 —— 用户转发过原帖 A 再看引用帖
        // Q 时,按钮未激活却弹「撤销转发」,选撤销反而对 Q 新建一条转发。
        // menuTargetPost 与 body 的 contentPost 是同一解析,直接复用。
        if menuTargetPost.isRepostedByCurrentUser {
            isShowingRepostOptions = true
        } else {
            onRepost()
        }
    }

    /// Wrap a write action so a guest gets a login prompt instead. Reading /
    /// navigation actions (open comments, open profile) are NOT wrapped. The
    /// prompt carries a reason so the auth sheet explains why it appeared.
    private func guestGated(_ action: @escaping () -> Void) -> () -> Void {
        {
            if currentUser?.isGuest == true {
                GuestGate.shared.requireLogin(L("guestReasonLike", language))
            } else {
                action()
            }
        }
    }
}

private struct PostAuthorPresentation {
    let displayName: String
    let username: String
    let isOfficial: Bool
    let label: String?
}

private struct OfficialSourceChip: View {
    let title: String

    var body: some View {
        Text(title)
            .kxScaledFont(9, weight: .bold)
            .foregroundStyle(KXColor.official)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(KXColor.official.opacity(0.10), in: Capsule())
    }
}

private struct CategoryChip: View {
    let title: String
    let icon: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
            }
            Text(title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, KXSpacing.sm)
        .frame(height: 22)
        .background(tint.opacity(0.095), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.14), lineWidth: 0.6))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct QuotedPostPreview: View {
    @Environment(\.appLanguage) private var language
    let post: PostEntity
    let author: UserEntity?
    let mediaItems: [MediaEntity]
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: KXSpacing.xs) {
                    HStack(spacing: KXSpacing.xs) {
                        KXAvatar(user: author, size: KXAvatarSize.xs)
                        Text(author?.displayName ?? L("unknownUser", language))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        KXUserBadge(user: author)
                        Text("@\(author?.username ?? L("unknownUser", language))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if !post.previewText.isEmpty {
                        Text(post.previewText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .buttonStyle(.plain)

            if !mediaItems.isEmpty {
                MediaGridView(mediaItems: mediaItems)
            }
        }
        .padding(KXSpacing.md)
        .background(KXColor.softBackground, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .stroke(KXColor.separator, lineWidth: 0.6)
        }
    }
}

struct KXInteractionBar: View {
    @Environment(\.appLanguage) private var language
    let post: PostEntity
    let onComment: () -> Void
    let onRepost: () -> Void
    let onLike: () -> Void
    let onBookmark: () -> Void

    var body: some View {
        // activeStateText: VoiceOver 需要「已转发/已点赞/已收藏」的开关状态 ——
        // heart→heart.fill 的视觉变化对旁白不可见。词表无现成 L(key),按约定
        // 用内联三语(pickText);评论按钮无开关语义,不传。
        HStack(spacing: KXSpacing.xxs) {
            MetricButton(icon: "bubble.left", value: post.commentCount, isActive: false, label: L("comments", language), tint: .teal, action: onComment)
            MetricButton(icon: "arrow.2.squarepath", value: post.repostCount, isActive: post.isRepostedByCurrentUser, label: L("repost", language), activeStateText: KXListingCopy.pickText(language, "已转发", "リポスト済み", "Reposted"), tint: .green, action: onRepost)
            MetricButton(icon: post.isLikedByCurrentUser ? "heart.fill" : "heart", value: post.likeCount, isActive: post.isLikedByCurrentUser, label: L("like", language), activeStateText: KXListingCopy.pickText(language, "已点赞", "いいね済み", "Liked"), tint: .pink, action: onLike)
            MetricButton(icon: post.isBookmarkedByCurrentUser ? "bookmark.fill" : "bookmark", value: post.bookmarkCount, isActive: post.isBookmarkedByCurrentUser, label: L("bookmark", language), activeStateText: KXListingCopy.pickText(language, "已收藏", "保存済み", "Bookmarked"), tint: .blue, action: onBookmark)
        }
        .padding(.top, KXSpacing.xs)
    }
}

private struct MetricButton: View {
    let icon: String
    let value: Int
    let isActive: Bool
    let label: String
    /// 选中态的 VoiceOver 文案(已点赞/已转发/已收藏)。图标 fill/变色只对
    /// 明眼人可见;不补这个状态,旁白用户无法判断再点一下是点赞还是取消。
    /// nil(评论按钮)表示该按钮没有开关语义。
    var activeStateText: String? = nil
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .kxScaledFont(15, weight: .regular)
                    .symbolRenderingMode(.hierarchical)
                    // Smoothly cross-fade the heart/bookmark glyph
                    // when the user toggles it instead of snapping.
                    .contentTransition(.symbolEffect(.replace.downUp))
                    // Celebratory bounce when the state flips (like /
                    // repost / bookmark) — matches the platform-native
                    // "it worked" cue users know from system apps.
                    .symbolEffect(.bounce, options: .speed(1.5), value: isActive)
                    .frame(width: 17, height: 17)
                Text(NumberFormatterUtils.compact(value))
                    .kxScaledFont(12, relativeTo: .caption, weight: .medium)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(isActive ? tint.opacity(0.92) : .secondary)
            .animation(.snappy(duration: 0.18), value: isActive)
            .frame(maxWidth: .infinity)
            .frame(height: 30, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(KXPressableStyle(scale: 0.90, dim: 0.8))
        .sensoryFeedback(.selection, trigger: isActive)
        .accessibilityLabel("\(label) \(value)")
        // 已选中状态进入可访问性属性:value 播报应用语言的「已点赞」等文案,
        // .isSelected 让系统再补一句本地化的「已选定」,双保险。
        .accessibilityValue(isActive ? (activeStateText ?? "") : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct TagWrapView: View {
    let tags: [String]
    var onTap: (String) -> Void = { _ in }

    private var displayTags: [String] {
        Array(tags.normalizedDisplayHashtags.prefix(5))
    }

    private var overflowCount: Int {
        max(0, tags.normalizedDisplayHashtags.count - displayTags.count)
    }

    var body: some View {
        // Refined soft-accent pill chips: a tinted capsule + hairline rim
        // reads more polished than flat inline text, while the low-opacity
        // fill keeps the card calm even with several tags.
        FlowLayout(spacing: KXSpacing.sm) {
            ForEach(displayTags, id: \.self) { tag in
                Button {
                    onTap(tag)
                } label: {
                    Text("#\(tag)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.accent)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(KXColor.accent.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(KXColor.accent.opacity(0.18), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
            }
        }
    }
}
