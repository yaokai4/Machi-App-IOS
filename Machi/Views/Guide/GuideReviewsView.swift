import SwiftUI

// MARK: - Guide product reviews (BE4 / guide_reviews)
//
// Star summary + 5-bucket distribution ladder (native SwiftUI bars, no 3rd party
// chart lib) + paginated review list + a "写评价" sheet for buyers/members.
// All copy is trilingual via `guideText`. Empty/loading states fill their region
// so the header above stays pinned instead of drifting to mid-screen.

/// A row of stars for a rating (supports half-star via fractional fill).
struct GuideStarRow: View {
    let rating: Double
    var size: CGFloat = 14
    var color: Color = KXColor.rankGold

    var body: some View {
        HStack(spacing: KXSpacing.xxs) {
            ForEach(1...5, id: \.self) { i in
                symbol(for: i)
                    .font(.system(size: size))
                    .foregroundStyle(color)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(String(format: "%.1f", rating))
    }

    @ViewBuilder
    private func symbol(for index: Int) -> some View {
        let value = rating - Double(index - 1)
        if value >= 1 {
            Image(systemName: "star.fill")
        } else if value >= 0.5 {
            Image(systemName: "star.leadinghalf.filled")
        } else {
            Image(systemName: "star")
        }
    }
}

/// Interactive 1–5 star picker used inside the write-review sheet.
struct GuideStarPicker: View {
    @Binding var rating: Int
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    rating = i
                } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(i <= rating ? KXColor.rankGold : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i)")
            }
        }
    }
}

// MARK: - Reviews section (embedded in the product detail page)

struct GuideProductReviewsSection: View {
    @Environment(\.appLanguage) private var language

    /// id-or-slug used for all review endpoints (server accepts either).
    let productRef: String

    @State private var summary: KaiXGuideRatingSummaryDTO?
    @State private var items: [KaiXGuideReviewDTO] = []
    @State private var hasMore = false
    @State private var offset = 0
    @State private var isLoading = true
    @State private var isPaging = false
    @State private var errorMessage: String?

    @State private var canReview = false
    @State private var myReview: KaiXGuideReviewDTO?
    @State private var showWriteSheet = false
    @State private var toast: String?

    private let pageSize = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isLoading && items.isEmpty && summary == nil {
                LoadingView()
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            } else if let errorMessage, items.isEmpty && summary == nil {
                ErrorStateView(message: errorMessage) { Task { await reload() } }
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            } else {
                if let summary { summaryCard(summary) }
                writeAffordance
                if items.isEmpty {
                    EmptyStateView(
                        title: guideText(language, "还没有评价", "レビューはまだありません", "No reviews yet"),
                        subtitle: guideText(language, "购买或解锁后，成为第一个分享体验的人。", "購入・解除後、最初の体験を共有しましょう。", "Buy or unlock, then be the first to share your experience."),
                        systemImage: "star.bubble"
                    )
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
                } else {
                    VStack(spacing: KXSpacing.md) {
                        ForEach(items) { review in
                            GuideReviewCard(
                                review: review,
                                language: language,
                                onHelpful: { await toggleHelpful(review) },
                                onReport: { await report(review) },
                                onWithdraw: { await withdraw(review) }
                            )
                        }
                    }
                    if hasMore {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            HStack(spacing: 6) {
                                if isPaging { ProgressView().controlSize(.small) }
                                Text(guideText(language, "查看更多评价", "さらにレビューを見る", "See more reviews"))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(KXColor.accentSoft, in: Capsule())
                            .foregroundStyle(KXColor.accent)
                        }
                        .buttonStyle(.fullArea)
                        .contentShape(Rectangle())
                        .disabled(isPaging)
                    }
                }
            }
        }
        .task(id: productRef) { await reload() }
        .sheet(isPresented: $showWriteSheet, onDismiss: { Task { await refreshMineAndSummary() } }) {
            GuideWriteReviewSheet(
                productRef: productRef,
                existing: myReview,
                onSubmitted: { message in
                    toast = message
                    Task { await refreshMineAndSummary() }
                }
            )
        }
        .alert("Machi Guide", isPresented: Binding(get: { toast != nil }, set: { if !$0 { toast = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(toast ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(guideText(language, "用户评价", "ユーザーレビュー", "Reviews"))
                .font(.title3.weight(.bold))
            if let count = summary?.ratingCount, count > 0 {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func summaryCard(_ summary: KaiXGuideRatingSummaryDTO) -> some View {
        KXCard(padding: 18, radius: 22) {
            HStack(alignment: .center, spacing: 18) {
                VStack(spacing: KXSpacing.xs) {
                    Text(summary.ratingCount > 0 ? String(format: "%.1f", summary.ratingAvg) : "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    GuideStarRow(rating: summary.ratingAvg, size: 13)
                    Text(guideText(language, "\(summary.ratingCount) 条评价", "\(summary.ratingCount) 件", "\(summary.ratingCount) reviews"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 84)

                VStack(spacing: 6) {
                    ForEach(summary.fullDistribution) { bucket in
                        distributionBar(star: bucket.star, count: bucket.count, total: summary.ratingCount)
                    }
                }
            }
        }
    }

    private func distributionBar(star: Int, count: Int, total: Int) -> some View {
        let fraction = total > 0 ? Double(count) / Double(total) : 0
        return HStack(spacing: KXSpacing.sm) {
            Text("\(star)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10, alignment: .trailing)
            Image(systemName: "star.fill")
                .font(.system(size: 9))
                .foregroundStyle(KXColor.rankGold)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(KXColor.rankGold)
                        .frame(width: max(fraction > 0 ? 6 : 0, geo.size.width * fraction))
                }
            }
            .frame(height: 7)
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var writeAffordance: some View {
        if canReview {
            Button {
                showWriteSheet = true
            } label: {
                HStack(spacing: KXSpacing.sm) {
                    Image(systemName: myReview == nil ? "square.and.pencil" : "pencil")
                    Text(writeButtonLabel)
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(KXColor.accent, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.fullArea)
            .contentShape(Rectangle())
            if let mine = myReview, mine.status != "published" {
                Text(myReviewStatusHint(mine.status))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var writeButtonLabel: String {
        myReview == nil
            ? guideText(language, "写评价", "レビューを書く", "Write a review")
            : guideText(language, "编辑我的评价", "レビューを編集", "Edit my review")
    }

    private func myReviewStatusHint(_ status: String) -> String {
        switch status {
        case "pending":
            return guideText(language, "你的评价正在审核中，通过后展示。", "レビューは審査中です。承認後に表示されます。", "Your review is under review and will appear once approved.")
        case "rejected":
            return guideText(language, "你的评价未通过审核，可修改后重新提交。", "レビューは承認されませんでした。修正して再提出できます。", "Your review was not approved. Edit and resubmit.")
        case "hidden":
            return guideText(language, "你的评价已被隐藏，等待复核。", "レビューは非表示です。再確認待ちです。", "Your review is hidden pending re-review.")
        case "withdrawn":
            return guideText(language, "你已撤回评价，可重新发布。", "レビューを取り下げました。再投稿できます。", "You withdrew your review. You can post again.")
        default:
            return ""
        }
    }

    // MARK: - data

    private func reload() async {
        isLoading = true
        errorMessage = nil
        offset = 0
        defer { isLoading = false }
        do {
            let resp = try await KaiXAPIClient.shared.guideProductReviews(productRef, limit: pageSize, offset: 0)
            summary = resp.summary
            items = resp.items
            hasMore = resp.hasMore
            offset = resp.items.count
        } catch {
            errorMessage = error.localizedDescription
        }
        await refreshMine()
    }

    private func loadMore() async {
        guard hasMore, !isPaging else { return }
        isPaging = true
        defer { isPaging = false }
        do {
            let resp = try await KaiXAPIClient.shared.guideProductReviews(productRef, limit: pageSize, offset: offset)
            // Dedupe defensively against a shifting window.
            let known = Set(items.map(\.id))
            items.append(contentsOf: resp.items.filter { !known.contains($0.id) })
            hasMore = resp.hasMore
            offset += resp.items.count
        } catch {
            toast = error.localizedDescription
        }
    }

    /// Only signed-in users can have a "me" review / write affordance.
    private func refreshMine() async {
        guard KaiXBackend.token != nil else {
            canReview = false
            myReview = nil
            return
        }
        do {
            let resp = try await KaiXAPIClient.shared.guideProductMyReview(productRef)
            canReview = resp.canReview
            myReview = resp.review
        } catch {
            // Non-fatal: the list still renders without the write affordance.
            canReview = false
            myReview = nil
        }
    }

    private func refreshMineAndSummary() async {
        await refreshMine()
        // A submit/withdraw may change the aggregate + list ordering.
        do {
            let resp = try await KaiXAPIClient.shared.guideProductReviews(productRef, limit: pageSize, offset: 0)
            summary = resp.summary
            items = resp.items
            hasMore = resp.hasMore
            offset = resp.items.count
        } catch {
            // Keep current data on a refresh failure.
        }
    }

    private func toggleHelpful(_ review: KaiXGuideReviewDTO) async {
        guard KaiXBackend.token != nil else {
            toast = guideText(language, "请登录后再投票。", "ログインして投票してください。", "Please log in to vote.")
            return
        }
        let target = !review.viewerVoted
        do {
            let resp = try await KaiXAPIClient.shared.voteGuideReviewHelpful(review.id, on: target)
            if let idx = items.firstIndex(where: { $0.id == review.id }) {
                items[idx] = replacing(items[idx], helpfulCount: resp.helpfulCount, viewerVoted: resp.viewerVoted)
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    private func report(_ review: KaiXGuideReviewDTO) async {
        guard KaiXBackend.token != nil else {
            toast = guideText(language, "请登录后再举报。", "ログインして報告してください。", "Please log in to report.")
            return
        }
        do {
            try await KaiXAPIClient.shared.reportGuideReview(review.id)
            toast = guideText(language, "已举报，我们会尽快审核。", "報告しました。確認します。", "Reported. We'll review it shortly.")
        } catch {
            toast = error.localizedDescription
        }
    }

    private func withdraw(_ review: KaiXGuideReviewDTO) async {
        do {
            try await KaiXAPIClient.shared.deleteMyGuideReview(review.id)
            toast = guideText(language, "已撤回评价。", "レビューを取り下げました。", "Review withdrawn.")
            await refreshMineAndSummary()
        } catch {
            toast = error.localizedDescription
        }
    }

    /// Build a copy of a review with an updated helpful state (DTO is immutable).
    private func replacing(_ r: KaiXGuideReviewDTO, helpfulCount: Int, viewerVoted: Bool) -> KaiXGuideReviewDTO {
        KaiXGuideReviewDTO(
            id: r.id, productId: r.productId, rating: r.rating, body: r.body, status: r.status,
            helpfulCount: helpfulCount, reportCount: r.reportCount, anonymous: r.anonymous,
            createdAt: r.createdAt, updatedAt: r.updatedAt, isMine: r.isMine,
            viewerVoted: viewerVoted, author: r.author
        )
    }
}

// MARK: - Single review card

struct GuideReviewCard: View {
    let review: KaiXGuideReviewDTO
    let language: AppLanguage
    let onHelpful: () async -> Void
    let onReport: () async -> Void
    let onWithdraw: () async -> Void

    @State private var busy = false

    var body: some View {
        KXCard(padding: 16, radius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    GuideReviewAvatar(author: review.author, anonymous: review.anonymous)
                    VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                        Text(displayName)
                            .font(.subheadline.weight(.semibold))
                        GuideStarRow(rating: Double(review.rating), size: 12)
                    }
                    Spacer(minLength: 0)
                    if let date = relativeDate {
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !review.body.isEmpty {
                    Text(review.body)
                        .font(.callout)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 14) {
                    Button {
                        guard !busy else { return }
                        busy = true
                        Task { await onHelpful(); busy = false }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: review.viewerVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                            Text(helpfulLabel)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(review.viewerVoted ? KXColor.accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || review.isMine)

                    Spacer(minLength: 0)

                    if review.isMine {
                        Button {
                            guard !busy else { return }
                            busy = true
                            Task { await onWithdraw(); busy = false }
                        } label: {
                            Text(guideText(language, "撤回", "取り下げ", "Withdraw"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.red.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    } else {
                        Button {
                            guard !busy else { return }
                            busy = true
                            Task { await onReport(); busy = false }
                        } label: {
                            Text(guideText(language, "举报", "報告", "Report"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }
                }
            }
        }
    }

    private var displayName: String {
        if review.anonymous || review.author == nil {
            return guideText(language, "匿名用户", "匿名ユーザー", "Anonymous")
        }
        let a = review.author
        return a?.displayName?.isEmpty == false ? (a?.displayName ?? "") : (a?.handle ?? guideText(language, "用户", "ユーザー", "User"))
    }

    private var helpfulLabel: String {
        let n = review.helpfulCount
        if n > 0 {
            return guideText(language, "有帮助 \(n)", "役立った \(n)", "Helpful \(n)")
        }
        return guideText(language, "有帮助", "役立った", "Helpful")
    }

    private var relativeDate: String? {
        guard let created = review.createdAt else { return nil }
        return GuideReviewDateFormatter.shared.relative(created, language: language)
    }
}

/// Avatar for a review author — a plain URL string (not a UserEntity), so we
/// render the cached image with an initial fallback.
struct GuideReviewAvatar: View {
    let author: KaiXGuideReviewAuthorDTO?
    let anonymous: Bool
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.18))
            if anonymous || author == nil {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary)
            } else if let urlString = author?.avatarUrl, let url = urlString.kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: size * 3, failureMode: .transparent)
                    .clipShape(Circle())
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: String {
        let name = author?.displayName?.isEmpty == false ? (author?.displayName ?? "") : (author?.handle ?? "?")
        return String(name.prefix(1)).uppercased()
    }
}

// MARK: - Write review sheet

struct GuideWriteReviewSheet: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    let productRef: String
    let existing: KaiXGuideReviewDTO?
    let onSubmitted: (String) -> Void

    @State private var rating: Int
    @State private var text: String
    @State private var anonymous: Bool
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(productRef: String, existing: KaiXGuideReviewDTO?, onSubmitted: @escaping (String) -> Void) {
        self.productRef = productRef
        self.existing = existing
        self.onSubmitted = onSubmitted
        _rating = State(initialValue: existing?.rating ?? 5)
        _text = State(initialValue: existing?.body ?? "")
        _anonymous = State(initialValue: existing?.anonymous ?? false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(guideText(language, "你的评分", "評価", "Your rating"))
                            .font(.subheadline.weight(.semibold))
                        GuideStarPicker(rating: $rating)
                    }

                    VStack(alignment: .leading, spacing: KXSpacing.sm) {
                        Text(guideText(language, "评价内容（可选）", "レビュー本文（任意）", "Your review (optional)"))
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $text)
                            .frame(minHeight: 130)
                            .padding(KXSpacing.sm)
                            .kxGlassSurface(radius: KXRadius.card)
                            .overlay(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text(guideText(language, "分享你的真实体验，帮助其他人做决定。请勿发布隐私或未经证实的指控。", "実際の体験を共有して、他の人の判断に役立ててください。個人情報や未確認の主張は避けてください。", "Share your honest experience to help others decide. Avoid private info or unverified accusations."))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, KXSpacing.lg)
                                        .allowsHitTesting(false)
                                }
                            }
                        Text("\(text.count)/2000")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    Toggle(isOn: $anonymous) {
                        Text(guideText(language, "匿名发布", "匿名で投稿", "Post anonymously"))
                            .font(.subheadline)
                    }

                    Text(guideText(language, "评价提交后需经审核，通过后才会展示。", "レビューは審査後に表示されます。", "Reviews are shown after moderation approval."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(KXSpacing.screen)
            }
            .navigationTitle(existing == nil
                ? guideText(language, "写评价", "レビューを書く", "Write a review")
                : guideText(language, "编辑评价", "レビューを編集", "Edit review"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(guideText(language, "取消", "キャンセル", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(guideText(language, "提交", "送信", "Submit")).bold()
                        }
                    }
                    .disabled(isSubmitting || rating < 1)
                }
            }
        }
    }

    private func submit() async {
        guard rating >= 1, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let trimmed = String(text.prefix(2000))
        do {
            let resp = try await KaiXAPIClient.shared.submitGuideProductReview(
                productRef, rating: rating, body: trimmed, anonymous: anonymous)
            let message = resp.message ?? guideText(language, "评价已提交，审核通过后展示。", "レビューを送信しました。承認後に表示されます。", "Review submitted. It will appear after approval.")
            onSubmitted(message)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - relative date formatting (cached; DateFormatter is expensive to build)

final class GuideReviewDateFormatter {
    static let shared = GuideReviewDateFormatter()
    private let iso = ISO8601DateFormatter()
    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// A compact "3天前 / 3 days ago" relative string. Falls back to a short
    /// absolute date beyond a month.
    func relative(_ isoString: String, language: AppLanguage) -> String? {
        let date = iso.date(from: isoString) ?? isoFractional.date(from: isoString)
        guard let date else { return nil }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 {
            return guideText(language, "刚刚", "たった今", "just now")
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return guideText(language, "\(minutes)分钟前", "\(minutes)分前", "\(minutes)m ago")
        }
        let hours = minutes / 60
        if hours < 24 {
            return guideText(language, "\(hours)小时前", "\(hours)時間前", "\(hours)h ago")
        }
        let days = hours / 24
        if days < 30 {
            return guideText(language, "\(days)天前", "\(days)日前", "\(days)d ago")
        }
        let df = DateFormatter()
        df.dateStyle = .short
        return df.string(from: date)
    }
}
