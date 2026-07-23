import SwiftUI
import SwiftData
import UIKit
#if canImport(Translation)
import Translation
#endif

struct PostCardView: View, Equatable {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var postStore: PostStore
    @State private var isShowingRepostOptions = false
    @State private var isShowingQuoteSheet = false
    @State private var isShowingEditPost = false
    @State private var isShowingDeleteConfirm = false
    @State private var isPostMutationInFlight = false
    @State private var isHiddenAfterDelete = false
    @State private var editPostText = ""
    @State private var cardMessage: String?
    @State private var cardError: String?
    @State private var isTextExpanded = false
    // 「查看全文」按真实截断测量判定:隐藏探针分别量出 4 行钳制高度与
    // 全文高度,两者有差才显示按钮 —— 取代旧的字符数启发式(97~104 字
    // 单段帖「点了没变化」的误报、60~96 字被截却无按钮的漏报都消除)。
    @State private var clampedBodyHeight: CGFloat?
    @State private var fullBodyHeight: CGFloat?
    @State private var isBodyTruncated = false

    let post: PostEntity
    let author: UserEntity?
    let mediaItems: [MediaEntity]
    var currentUser: UserEntity?
    var originalPost: PostEntity?
    var originalAuthor: UserEntity?
    var originalMediaItems: [MediaEntity] = []
    var showsMenu = true
    /// When true (post detail), the body text is never truncated: the detail
    /// page is the ONLY place the full text lives, so it must not depend on
    /// any truncation detection. Feed cards keep `false` (4-line clamp with
    /// a measured "view full text" toggle, tap = open detail).
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
                                    // TimelineView 让相对时间「走起来」:卡片停留时
                                    // 「刚刚」每分钟自然长成「3分钟前」。periodic 只
                                    // 换 context.date,不触发整卡重算(.equatable()
                                    // 缓存不受影响)。
                                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                                        Text(DateFormatterUtils.relativeText(from: contentPost.createdAt, to: timeline.date, language: language))
                                            .font(KXTypography.meta)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
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
                            // 详情页是全文的唯一去处,正文永不截断、不依赖任何截断检测;
                            // 折叠/展开(隐藏探针实测截断)只保留在 Feed 卡片上。
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
                            // 隐藏探针在同一宽度下同时量出「4 行钳制」与「全文」
                            // 高度;background 不参与布局,不撑高卡片。
                            .background { bodyTruncationProbe(for: contentPost.previewText) }
                            if isBodyTruncated || isTextExpanded {
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

                    // 【王牌】日文帖一键翻中(反向 zh→ja、en 互译同理):检测到
                    // 正文语言与界面语言不同时,正文下方出现「翻译」小按钮,点按
                    // 用 Apple Translation framework 就地翻译。iOS 18 以下整体
                    // 优雅隐藏(TranslationSession 是 iOS 18+ API)。
                    #if canImport(Translation)
                    if #available(iOS 18.0, *) {
                        if contentPost.contentType != .question, !contentPost.previewText.isEmpty,
                           let pair = PostTranslationService.shared.translationPair(
                               postId: contentPost.id,
                               text: contentPost.previewText,
                               serverLanguageTag: contentPost.language,
                               uiLanguage: language
                           ) {
                            PostTranslationSection(
                                postId: contentPost.id,
                                sourceText: contentPost.previewText,
                                sourceTag: pair.source,
                                targetTag: pair.target
                            )
                        }
                    }
                    #endif

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
            // 未转发:转发 / 引用 / 取消;已转发:撤销转发 / 引用 / 取消。
            // 点按转发键一律先经此对话框,杜绝「误触即转」。
            if menuTargetPost.isRepostedByCurrentUser {
                Button(L("undoRepost", language), role: .destructive, action: onRepost)
            } else {
                Button(L("repost", language), action: onRepost)
            }
            Button(L("quotePost", language)) {
                isShowingQuoteSheet = true
            }
            Button(L("cancel", language), role: .cancel) {}
        }
        .sheet(isPresented: $isShowingQuoteSheet) {
            QuoteComposerSheet(
                post: menuTargetPost,
                author: quoteTargetAuthor,
                mediaItems: quoteTargetMedia,
                onSubmit: onQuoteRepost
            )
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

    /// Feed 卡片「查看全文」的真实截断探针:两份隐藏 Text 与可见正文完全同
    /// 样式(字号/行距/fixedSize),一份钳制 4 行、一份不限行,在同一宽度下
    /// 各自量出高度 —— 有差即真被截断。替代旧字符数启发式(与真实折行无关,
    /// 误报/漏报皆有)。详情页(expandOnTap)一律不截断,不走此探针。
    @ViewBuilder
    private func bodyTruncationProbe(for text: String) -> some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .kxScaledFont(15, relativeTo: .body, weight: .regular)
                .lineSpacing(2)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    clampedBodyHeight = height
                    updateBodyTruncation()
                }
            Text(text)
                .kxScaledFont(15, relativeTo: .body, weight: .regular)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    fullBodyHeight = height
                    updateBodyTruncation()
                }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func updateBodyTruncation() {
        guard let clamped = clampedBodyHeight, let full = fullBodyHeight else { return }
        let truncated = full - clamped > 0.5
        if truncated != isBodyTruncated {
            isBodyTruncated = truncated
        }
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

    /// 引用弹窗预览用的作者/媒体,与 menuTargetPost 同一套解析:引用转发卡
    /// 的目标是引用帖本身(author/mediaItems),纯转发卡的目标是被转发的
    /// 原帖(originalAuthor/originalMediaItems)。
    private var quoteTargetAuthor: UserEntity? {
        if originalPost != nil && !post.previewText.isEmpty { return author }
        return originalPost != nil ? originalAuthor : author
    }

    private var quoteTargetMedia: [MediaEntity] {
        if originalPost != nil && !post.previewText.isEmpty { return mediaItems }
        return originalPost != nil ? originalMediaItems : mediaItems
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
        // 无论是否已转发都先弹 confirmationDialog(转发 or 撤销转发 / 引用 /
        // 取消)——引用入口不再藏在「先转发一次」之后,误触也不再立即成转。
        // 「是否已转发」的判定必须与交互条展示、onRepost 的作用目标(列表页的
        // targetPost / 详情页的 interactionTarget)取同一个帖子:引用转发卡的
        // 交互条作用于引用帖本身,不是被引用的原帖(menuTargetPost 与 body 的
        // contentPost 是同一解析,对话框内的分支直接复用它)。
        isShowingRepostOptions = true
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
            // 视觉高度保持 30pt(卡片布局不变),命中区只在纵向外扩到 44pt
            // 推荐触达区。不能用 inset(by: -7) 全向外扩:相邻按钮横向紧贴,
            // 横向外扩会在交界处互相抢命中。
            .contentShape(VerticallyExpandedTapShape(expansion: 7))
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

/// 命中区形状:保持原始 frame 参与布局,仅纵向向外扩 `expansion` pt。
private struct VerticallyExpandedTapShape: Shape {
    var expansion: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: 0, dy: -expansion))
    }
}

#if canImport(Translation)
/// 卡片正文下的就地翻译区:「翻译」小按钮 + 淡入的译文块(标「AI 翻译」)。
/// 再点收起;结果缓存在 PostTranslationService(内存 per postId×目标语言),
/// 收起再展开、滚出滚回都不重跑模型。语言包未下载时由系统 sheet 引导下载
/// (translationTask 自动弹出);语言对不支持时按钮整体隐藏。
@available(iOS 18.0, *)
private struct PostTranslationSection: View {
    @Environment(\.appLanguage) private var language

    let postId: String
    let sourceText: String
    /// 短标签("ja"/"zh"/"en"),Locale 映射见 PostTranslationService。
    let sourceTag: String
    let targetTag: String

    @State private var translatedText: String?
    @State private var isShowingTranslation = false
    @State private var isTranslating = false
    @State private var didFail = false
    @State private var configuration: TranslationSession.Configuration?
    @State private var isPairSupported = true

    private var sourceLanguage: Locale.Language {
        Locale.Language(identifier: PostTranslationService.localeIdentifier(forTag: sourceTag))
    }

    private var targetLanguage: Locale.Language {
        Locale.Language(identifier: PostTranslationService.localeIdentifier(forTag: targetTag))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.xs) {
            if isPairSupported {
                Button(action: handleTap) {
                    HStack(spacing: 5) {
                        if isTranslating {
                            KXSpinner(size: 12, lineWidth: 1.6)
                        } else {
                            Image(systemName: "translate")
                                .font(.caption2.weight(.bold))
                        }
                        Text(buttonTitle)
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(KXColor.accent)
                    .contentShape(VerticallyExpandedTapShape(expansion: 8))
                }
                .buttonStyle(.plain)
                .disabled(isTranslating)
                .accessibilityIdentifier("post_translate_button")

                if didFail && !isShowingTranslation {
                    Text(KXListingCopy.pickText(language, "翻译暂时不可用，点按重试", "翻訳を利用できません。タップして再試行", "Translation unavailable — tap to retry"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if isShowingTranslation, let translatedText {
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2.weight(.semibold))
                            Text(KXListingCopy.pickText(language, "AI 翻译", "AI翻訳", "AI translation"))
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(.secondary)
                        Text(translatedText)
                            .kxScaledFont(15, relativeTo: .body, weight: .regular)
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(KXSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KXColor.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                            .stroke(KXColor.accent.opacity(0.12), lineWidth: 0.6)
                    )
                    .transition(.opacity)
                }
            }
        }
        .task(id: "\(sourceTag)->\(targetTag)") {
            // 首次上屏或语言对变化(例如用户切换界面语言):丢弃旧配置,
            // 用新目标语言回填缓存里的既有译文(无则收起旧展示),再查
            // 该语言对的可用性。
            configuration = nil
            isTranslating = false
            let cached = PostTranslationService.shared.cachedTranslation(postId: postId, targetTag: targetTag)
            translatedText = cached
            if cached == nil {
                isShowingTranslation = false
            }
            await refreshPairSupport()
        }
        .translationTask(configuration) { session in
            do {
                let response = try await session.translate(sourceText)
                PostTranslationService.shared.storeTranslation(response.targetText, postId: postId, targetTag: targetTag)
                withAnimation(.easeInOut(duration: 0.22)) {
                    translatedText = response.targetText
                    isShowingTranslation = true
                }
            } catch {
                didFail = true
            }
            isTranslating = false
        }
    }

    private var buttonTitle: String {
        if isTranslating {
            return KXListingCopy.pickText(language, "翻译中…", "翻訳中…", "Translating…")
        }
        if isShowingTranslation {
            return KXListingCopy.pickText(language, "收起翻译", "翻訳を閉じる", "Hide translation")
        }
        return KXListingCopy.pickText(language, "翻译", "翻訳", "Translate")
    }

    private func handleTap() {
        didFail = false
        if isShowingTranslation {
            withAnimation(.easeInOut(duration: 0.18)) {
                isShowingTranslation = false
            }
            return
        }
        if let cached = translatedText
            ?? PostTranslationService.shared.cachedTranslation(postId: postId, targetTag: targetTag) {
            translatedText = cached
            withAnimation(.easeInOut(duration: 0.22)) {
                isShowingTranslation = true
            }
            return
        }
        isTranslating = true
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
        } else {
            // 失败后重试:invalidate 让 translationTask 以同一配置重跑。
            configuration?.invalidate()
        }
    }

    /// 语言对完全不支持(设备/系统不含该翻译方向)时隐藏整个入口;
    /// 「支持但语言包未下载」保留按钮,点按时系统会引导下载。
    private func refreshPairSupport() async {
        let status = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
        switch status {
        case .unsupported:
            isPairSupported = false
        case .installed, .supported:
            isPairSupported = true
        @unknown default:
            isPairSupported = true
        }
    }
}
#endif

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
