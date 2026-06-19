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
        && lhs.mediaItems.map(\.id) == rhs.mediaItems.map(\.id)
        && lhs.originalPost?.id == rhs.originalPost?.id
        && lhs.originalPost?.updatedAt == rhs.originalPost?.updatedAt
        && lhs.originalPost?.likeCount == rhs.originalPost?.likeCount
        && lhs.originalPost?.repostCount == rhs.originalPost?.repostCount
        && lhs.originalPost?.commentCount == rhs.originalPost?.commentCount
        && lhs.originalAuthor?.id == rhs.originalAuthor?.id
        && lhs.originalAuthor?.updatedAt == rhs.originalAuthor?.updatedAt
        && lhs.originalMediaItems.map(\.id) == rhs.originalMediaItems.map(\.id)
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
                        Label("\(author?.displayName ?? L("unknownUser", language)) \(isQuoteRepost ? L("quotePost", language) : L("repostedBy", language))", systemImage: "arrow.2.squarepath")
                            .font(KXTypography.metaEmphasis)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.leading, 2)
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
                                HStack(spacing: 4) {
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

                        if contentPost.isBoosted && (contentPost.boostedUntil ?? .distantFuture) > .now {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 9, weight: .black))
                                Text(L("boostedBadge", language))
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(KXColor.heat, in: Capsule())
                        }

                        if showsMenu {
                            postMenuButton
                        }
                    }

                    metadataRow(for: contentPost)

                    if !contentPost.previewText.isEmpty {
                        Button(action: onOpen) {
                            Text(contentPost.previewText)
                                .font(.system(size: 15, weight: .regular))
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
                .gesture(TapGesture().onEnded { onOpen() }, including: .gesture)
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
        guard post.isSeedContent else {
            return PostAuthorPresentation(
                displayName: author?.displayName ?? L("unknownUser", language),
                username: author?.username ?? L("unknownUser", language),
                isOfficial: author?.isMachiOfficialAccount == true,
                label: author?.isMachiOfficialAccount == true ? L("machiOfficial", language) : nil
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

    private func shouldShowExpand(for text: String) -> Bool {
        text.count > 96 || text.components(separatedBy: .newlines).count > 4
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

    private func attributeSummary(for post: PostEntity, visibleHashtags: [String]) -> String? {
        func s(_ key: String) -> String? {
            post.stringAttribute(key)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        func money(_ numberKey: String) -> String? {
            guard let value = post.doubleAttribute(numberKey) else { return nil }
            let currency = s(PostAttributeKeys.currency) ?? ""
            let amount = value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.2f", value)
            return currency.isEmpty ? amount : "\(currency) \(amount)"
        }
        func joined(_ parts: [String?]) -> String? {
            let values = parts.compactMap { $0?.nilIfBlank }
            return values.isEmpty ? nil : values.joined(separator: " · ")
        }
        func status(_ raw: String?) -> String? {
            guard let raw else { return nil }
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "active":
                return nil
            case "under_review":
                return L("status_under_review", language)
            default:
                return raw
            }
        }

        switch post.contentType {
        case .image_post, .long_post:
            return joined([s(PostAttributeKeys.title), s(PostAttributeKeys.summary)])
        case .question:
            return joined([s(PostAttributeKeys.question), s(PostAttributeKeys.category)])
        case .rant:
            return joined([s(PostAttributeKeys.title), s(PostAttributeKeys.category)])
        case .secondhand:
            return joined([money(PostAttributeKeys.price), s(PostAttributeKeys.condition), s(PostAttributeKeys.tradeMethod), s(PostAttributeKeys.status)])
        case .housing:
            return joined([money(PostAttributeKeys.rent), s(PostAttributeKeys.roomType), s(PostAttributeKeys.area), s(PostAttributeKeys.nearestStation)])
        case .roommate:
            return joined([s(PostAttributeKeys.rentRange), s(PostAttributeKeys.area), s(PostAttributeKeys.moveInDate)])
        case .job_seek:
            return joined([s(PostAttributeKeys.desiredJob), s(PostAttributeKeys.expectedSalary), s(PostAttributeKeys.visaStatus)])
        case .job_post:
            return joined([s(PostAttributeKeys.salary), s(PostAttributeKeys.companyName), s(PostAttributeKeys.workLocation)])
        case .referral:
            return joined([s(PostAttributeKeys.companyName), s(PostAttributeKeys.jobTitle), s(PostAttributeKeys.contactMethod)])
        case .meetup:
            return joined([s(PostAttributeKeys.meetupTime), s(PostAttributeKeys.location), post.intAttribute(PostAttributeKeys.peopleLimit).map { "\($0)人" }])
        case .dining:
            return joined([s(PostAttributeKeys.restaurantOrArea), s(PostAttributeKeys.meetupTime), s(PostAttributeKeys.budget)])
        case .event:
            return joined([s(PostAttributeKeys.eventTime), s(PostAttributeKeys.location), s(PostAttributeKeys.fee)])
        case .guide:
            return s(PostAttributeKeys.summary)
        case .news, .local_info:
            return joined([s(PostAttributeKeys.source), s(PostAttributeKeys.summary)])
        case .service:
            return joined([s(PostAttributeKeys.serviceType), s(PostAttributeKeys.priceRange), s(PostAttributeKeys.contactMethod)])
        case .merchant:
            let rating = post.doubleAttribute(PostAttributeKeys.rating).map { String(format: "%.1f★", $0) }
            return joined([rating, s(PostAttributeKeys.address), s(PostAttributeKeys.merchantType)])
        case .coupon:
            return joined([s(PostAttributeKeys.discountInfo), s(PostAttributeKeys.validUntil)])
        case .warning:
            let category = s(PostAttributeKeys.category)
            let normalizedCategory = category?.normalizedTopicName
            let categoryAlreadyVisible = normalizedCategory.map { normalized in
                visibleHashtags.contains { $0.normalizedTopicName == normalized }
            } ?? false
            return joined([
                categoryAlreadyVisible ? nil : category,
                status(s(PostAttributeKeys.reviewStatus))
            ])
        case .poll:
            return joined([s(PostAttributeKeys.question), s(PostAttributeKeys.expiresAt)])
        case .anonymous:
            return joined([s(PostAttributeKeys.title), s(PostAttributeKeys.description)])
        default:
            return nil
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
                cardMessage = L("reportRecorded", language)
            } label: {
                Label(L("reportPost", language), systemImage: "flag")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .kxGlassCircle()
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

    private func handleRepostTap() {
        if (originalPost ?? post).isRepostedByCurrentUser {
            isShowingRepostOptions = true
        } else {
            onRepost()
        }
    }

    /// Wrap a write action so a guest gets a login prompt instead. Reading /
    /// navigation actions (open comments, open profile) are NOT wrapped.
    private func guestGated(_ action: @escaping () -> Void) -> () -> Void {
        { if currentUser?.isGuest == true { GuestGate.shared.requireLogin() } else { action() } }
    }
}

private struct TypedSummaryView: View {
    let summary: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(summary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.045), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous)
                .stroke(tint.opacity(0.09), lineWidth: 0.6)
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
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.45))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(Color(red: 0.05, green: 0.48, blue: 0.45).opacity(0.10), in: Capsule())
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
        .padding(.horizontal, 8)
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
        HStack(spacing: 2) {
            MetricButton(icon: "bubble.left", value: post.commentCount, isActive: false, label: L("comments", language), tint: .teal, action: onComment)
            MetricButton(icon: "arrow.2.squarepath", value: post.repostCount, isActive: post.isRepostedByCurrentUser, label: L("repost", language), tint: .green, action: onRepost)
            MetricButton(icon: post.isLikedByCurrentUser ? "heart.fill" : "heart", value: post.likeCount, isActive: post.isLikedByCurrentUser, label: L("like", language), tint: .pink, action: onLike)
            MetricButton(icon: post.isBookmarkedByCurrentUser ? "bookmark.fill" : "bookmark", value: post.bookmarkCount, isActive: post.isBookmarkedByCurrentUser, label: L("bookmark", language), tint: .blue, action: onBookmark)
        }
        .padding(.top, 4)
    }
}

private struct MetricButton: View {
    let icon: String
    let value: Int
    let isActive: Bool
    let label: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
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
                    .font(.system(size: 12, weight: .medium))
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
    }
}

private struct MetricLabel: View {
    let icon: String
    let value: Int
    let label: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .frame(width: 17, height: 17)
            Text(NumberFormatterUtils.compact(value))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 30, alignment: .center)
            .accessibilityLabel("\(label) \(value)")
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
        FlowLayout(spacing: 8) {
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
