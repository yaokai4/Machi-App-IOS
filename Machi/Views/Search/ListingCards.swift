import SwiftUI
import UIKit

// Listing card + skeleton views (secondhand / job / structured rows,
// media pages, badges) extracted from DiscoverView.swift. Shared by the
// listing channel and detail screens.

struct KXSkeletonBone: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = 5
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(KXColor.softBackground)
            .frame(width: width, height: height)
    }
}

struct KXSecondhandSkeletonCard: View {
    /// nil = 填满所在 grid cell(与真卡的 KXSquareCover(side: nil) 同一路径)。
    var width: CGFloat? = nil
    private var inner: CGFloat? { width.map { max(0, $0 - 14) } }
    var body: some View {
        // 与真卡同构:封面 / 价格 / 两行标题 / chips 行 / meta 行,换入内容不跳版。
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                .fill(KXColor.softBackground)
                .modifier(KXSquareCover(side: inner))
            KXSkeletonBone(width: 84, height: 20)
            KXSkeletonBone(width: nil, height: 11)
            KXSkeletonBone(width: 108, height: 11)
            KXSkeletonBone(width: 64, height: 16, radius: 8)
            KXSkeletonBone(width: 96, height: 9)
        }
        .padding(7)
        .padding(.bottom, KXSpacing.xxs)
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .kxLivingSurface(radius: KXRadius.lg)
        .kxShimmer()
    }
}

struct KXJobSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            HStack(spacing: KXSpacing.md) {
                RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                    .fill(KXColor.softBackground)
                    .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 7) {
                    KXSkeletonBone(width: 190, height: 13)
                    KXSkeletonBone(width: 120, height: 10)
                }
                Spacer(minLength: 0)
            }
            KXSkeletonBone(width: 140, height: 13)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    KXSkeletonBone(width: 56, height: 22, radius: KXRadius.sm)
                }
            }
            // Match the real job row's divider + "查看详情·投递" CTA line.
            Divider().overlay(KXColor.livingInk.opacity(0.06))
            HStack {
                Spacer()
                KXSkeletonBone(width: 96, height: 12)
            }
        }
        .padding(14)
        .kxLivingSurface(radius: KXRadius.card, elevated: true)
        .kxShimmer()
    }
}

struct KXBigPhotoSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay { RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous).fill(KXColor.softBackground) }
            // Mirror the real stay/service card: title+rating row, station,
            // price+CTA row — so the swap to content doesn't shift layout.
            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                HStack {
                    KXSkeletonBone(width: 160, height: 14)
                    Spacer()
                    KXSkeletonBone(width: 46, height: 12)
                }
                KXSkeletonBone(width: 120, height: 10)
                HStack {
                    KXSkeletonBone(width: 90, height: 14)
                    Spacer()
                    KXSkeletonBone(width: 72, height: 28, radius: KXRadius.md)
                }
            }
            .padding(.horizontal, KXSpacing.xxs)
        }
        .padding(KXSpacing.sm)
        .kxLivingSurface(radius: KXRadius.hero, elevated: true)
        .kxShimmer()
    }
}

/// Square cover sizing for listing cards. With a fixed `side` it's an exact
/// square; with `nil` (card filling a flexible grid cell) it fills the cell
/// width and stays 1:1 — fixes the ragged/overlapping grid when no width is
/// passed (e.g. profile → 我的二手).
struct KXSquareCover: ViewModifier {
    let side: CGFloat?
    func body(content: Content) -> some View {
        if let side {
            content.frame(width: side, height: side)
        } else {
            // Color.clear 定出严格 1:1 的版面,内容走 overlay 再裁切——
            // aspectRatio 只影响提案,竖图经 .fill 会汇报超高把卡撑成长方形,
            // 用 overlay 承载才能保证任何原图比例下封面都是正方形。
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .overlay(content)
                .clipped()
                .contentShape(Rectangle())
        }
    }
}

struct KXSecondhandListingCard: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    var width: CGFloat? = nil
    let onOpen: () -> Void

    /// 收藏态实时从 FavoritesStore 推导(观察 items/removedIds 变化),跨页
    /// (详情页/收藏 sheet)取消后回到列表红心即刷新——旧的 favoriteSeeded
    /// 闩锁只播种一次,会留下过期红心。store 没记录时用服务端 DTO 兜底,
    /// 但本会话明确取消过的不再点亮。
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var openTaps = 0

    private var favorited: Bool {
        favorites.contains(listing.id)
            || (!favorites.wasRemoved(listing.id) && (listing.favorited ?? listing.isFavorited ?? false))
    }

    private var innerWidth: CGFloat? {
        width.map { max(0, $0 - 14) }
    }

    private var statusBadgeMaxWidth: CGFloat? {
        innerWidth.map { max(70, $0 - 48) }
    }

    /// 已预约/已售:整卡降权(封面去色 + 状态胶囊 + 卡面微透)。
    private var muted: Bool {
        KXListingCopy.isMutedListingStatus(listing.status)
    }

    var body: some View {
        Button {
            openTaps += 1
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                cover
                    .frame(width: innerWidth)
                // 价格是二手卡的第一信息层级:title3.heavy + 等宽数字,不缩字;
                // 免费送用强调色「免费」胶囊,在满屏价格里一眼可辨。
                Group {
                    if KXListingCopy.isFreeListing(listing) {
                        Text(KXListingCopy.pickText(language, "免费", "無料", "Free"))
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(KXColor.onAccent)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(KXColor.livingAccent, in: Capsule())
                    } else {
                        Text(KXListingCopy.priceLabel(listing, language))
                            .font(.title3.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                .frame(height: 26, alignment: .leading)
                .frame(width: innerWidth, alignment: .leading)
                // 标题退为次级信息,固定两行占位 → 两列卡片天然等高。
                Text(KXListingCopy.displayTitle(listing))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(width: innerWidth, alignment: .leading)
                // chips 行恒占位(空时透明填充),消除行高抖动的锯齿感。
                chipsRow
                    .frame(width: innerWidth, alignment: .leading)
                HStack(spacing: KXSpacing.xs) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2.weight(.bold))
                    Text(KXListingCopy.secondhandCompactMeta(listing, language))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: innerWidth, alignment: .leading)
            }
            .padding(7)
            .padding(.bottom, KXSpacing.xxs)
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
            .kxLivingSurface(radius: KXRadius.lg)
            .opacity(muted ? 0.8 : 1)
        }
        .frame(maxWidth: width ?? .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: openTaps)
        // 无障碍:红心不再嵌在整卡 Button 的 label 里(VoiceOver 会把嵌套的
        // 可交互元素并进卡片焦点、无法单独聚焦),改为卡片 Button 之外的
        // overlay 定位。视觉零变化:44pt 命中框原先贴封面右上角 inset 1pt,
        // 封面距卡缘 7pt,合计 8pt;muted(已售/已预约)时跟随整卡 0.8 降权。
        .overlay(alignment: .topTrailing) {
            heartButton
                .padding(8)
                .opacity(muted ? 0.8 : 1)
        }
    }

    private var chipsRow: some View {
        let badges = KXListingCopy.secondhandCardBadges(for: listing, language)
        return HStack(spacing: KXSpacing.xs) {
            if badges.isEmpty {
                Color.clear
            } else {
                ForEach(badges.prefix(2), id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KXColor.rankTeal)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(KXColor.rankTeal.opacity(0.09), in: Capsule())
                }
            }
        }
        .frame(height: 20)
    }

    /// 右上角爱心：乐观切换，失败回滚;同时写入本地收藏。与住宿/服务卡一致。
    private var favoriteSnapshot: FavoriteSnapshot {
        FavoritesStore.snapshot(from: listing)
    }

    private var heartButton: some View {
        Button {
            guard GuestSession.requireSignedIn(reason: KXListingCopy.pickText(language, "登录后可以收藏喜欢的信息。", "ログインするとお気に入りに保存できます。", "Sign in to save listings you like.")) else { return }
            let next = !favorited
            // 乐观写 store,favorited 即时跟随推导刷新;失败回滚。
            FavoritesStore.shared.set(favoriteSnapshot, on: next)
            Task {
                do { try await KaiXAPIClient.shared.favoriteListing(listing.id, on: next) }
                catch {
                    FavoritesStore.shared.set(favoriteSnapshot, on: !next)
                }
            }
        } label: {
            Image(systemName: favorited ? "heart.fill" : "heart")
                .font(.caption2.weight(.bold))
                .foregroundStyle(favorited ? KXColor.heat : .primary)
                .symbolEffect(.bounce, value: favorited)
                .frame(width: 28, height: 28)
                .kxCoverBadge(in: Circle())
                .frame(width: 44, height: 44)        // 44pt min tap target (HIG)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: favorited)
        .kxFavoriteAccessibility(favorited, language)
    }

    private var cover: some View {
        ZStack {
            if let url = listing.coverURL {
                // ~160pt square cover; 480 = 160pt @3x. Was 720 (≈5x oversample
                // on @2x) — bigger decodes + faster cache eviction for no gain.
                MediaImageView(url: url, targetPixelSize: 480)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                ListingMediaPlaceholder(type: listing.type)
            }
            if listing.coverIsVideo {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.55), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .modifier(KXSquareCover(side: innerWidth))
        // 已预约/已售:封面去色压暗,配居中状态胶囊,浏览时一眼可辨。
        .saturation(muted ? 0 : 1)
        .opacity(muted ? 0.55 : 1)
        .overlay(alignment: .topLeading) {
            // published(默认态)不再常驻「出售中」badge——封面只在异常态
            // (审核中/已下架等)才值得占位;已预约/已售改走居中胶囊。
            if listing.status != "published", !muted {
                HStack(spacing: KXSpacing.xs) {
                    Circle()
                        .fill(KXListingCopy.statusColor(listing.status))
                        .frame(width: 6, height: 6)
                    Text(KXListingCopy.formatListingStatus(listing.status, type: listing.type, language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, KXSpacing.sm)
                .frame(height: 24)
                .kxCoverBadge(in: Capsule())
                .frame(maxWidth: statusBadgeMaxWidth, alignment: .leading)
                .padding(7)
            }
        }
        .overlay(alignment: .center) {
            if muted {
                Text(KXListingCopy.formatListingStatus(listing.status, type: listing.type, language))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, KXSpacing.md)
                    .frame(height: 28)
                    .kxCoverBadge(in: Capsule())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
        }
    }
}

struct ListingMediaPage: View {
    let media: KaiXListingMediaDTO
    let index: Int
    let total: Int
    /// 详情相册自己在 TabView 上叠了不会被圆角裁掉的计数器,故可关掉页内角标。
    var showsCounter: Bool = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if media.normalizedType == "video" {
                MediaVideoView(sourceURL: media.sourceURL, posterURL: media.previewURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url = media.previewURL {
                MediaImageView(url: url, targetPixelSize: 1400)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                ListingMediaPlaceholder(type: media.normalizedType)
            }
            if showsCounter, total > 1 {
                Text("\(index + 1)/\(total)")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, KXSpacing.sm)
                    .frame(height: 24)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(10)
            }
        }
    }
}

struct ListingMediaPlaceholder: View {
    @Environment(\.appLanguage) private var language

    let type: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    KXColor.livingSoft,
                    KXColor.livingAccentSoft.opacity(0.7),
                    Color(.systemBackground).opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(KXColor.livingWarm.opacity(0.10))
                .frame(width: 200, height: 200)
                .offset(x: -120, y: -70)
            Circle()
                .fill(KXColor.livingAccent.opacity(0.10))
                .frame(width: 240, height: 240)
                .offset(x: 150, y: 90)
            VStack(spacing: 11) {
                Image(systemName: type == "video" ? "play.rectangle.fill" : KXListingCopy.icon(for: type))
                    .kxScaledFont(34, weight: .bold)
                    .foregroundStyle(KXColor.livingAccent.opacity(0.8))
                Text(type == "video"
                     ? KXListingCopy.pickText(language, "视频封面生成中", "動画カバーを生成中", "Generating video cover")
                     : KXListingCopy.pickText(language, "暂无图片", "画像はまだありません", "No photos yet"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.livingMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct KXJobListingRow: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    let onOpen: () -> Void
    @State private var openTaps = 0

    private var companyName: String {
        (KXListingCopy.attr(listing, "company_name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var workLocation: String {
        (KXListingCopy.attr(listing, "work_location") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var salaryText: String {
        let s = (KXListingCopy.attr(listing, "salary") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? KXListingCopy.priceLabel(listing, language) : s
    }
    private var companyVerified: Bool {
        KXListingCopy.boolAttr(listing, "company_verified") || listing.verification_status == "verified"
    }
    // Employment type is stored as a ready-to-show label ("全职"/"兼职"…), not a
    // key — read it directly. Falls back to the job_type enum for older rows.
    private var employmentLabel: String? {
        let e = (KXListingCopy.attr(listing, "employment_type") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.isEmpty { return e }
        switch KXListingCopy.attr(listing, "job_type") {
        case "full_time": return L("jt_full_time", language)
        case "part_time": return L("jt_part_time", language)
        case "internship": return L("jt_internship", language)
        case "remote": return L("jt_remote", language)
        default: return nil
        }
    }
    private var japaneseLabel: String? {
        let j = (KXListingCopy.attr(listing, "japanese_level") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLanguagePrefix = j.contains("日语") || j.contains("日本語") || j.localizedCaseInsensitiveContains("Japanese")
        return j.isEmpty ? nil : (hasLanguagePrefix ? j : "\(KXListingCopy.pickText(language, "日语", "日本語", "Japanese")) \(j)")
    }
    private var visaSupport: Bool { KXListingCopy.boolAttr(listing, "visa_support") }
    private var companyInitial: String {
        let source = companyName.isEmpty ? KXListingCopy.displayTitle(listing) : companyName
        return String(source.prefix(1)).uppercased()
    }

    /// Indeed-style fact chips beyond employment + japanese: visa, no-experience,
    /// remote, students, commute, weekly holidays, benefits. Capped so the row
    /// stays tidy.
    private var jobFactChips: [String] {
        var chips: [String] = []
        let visa = (KXListingCopy.attr(listing, "visa_support") ?? "").lowercased()
        if visa == "available" || visa == "support" || visa == "true" {
            chips.append(KXListingCopy.pickText(language, "签证支持", "ビザサポート", "Visa support"))
        } else if visa == "consult" {
            chips.append(KXListingCopy.pickText(language, "签证可咨询", "ビザ相談可", "Visa negotiable"))
        }
        if KXListingCopy.boolAttr(listing, "no_experience_ok") { chips.append(KXListingCopy.pickText(language, "无经验可", "未経験可", "No experience OK")) }
        if KXListingCopy.boolAttr(listing, "remote_ok") { chips.append(KXListingCopy.pickText(language, "可远程", "リモート可", "Remote OK")) }
        if KXListingCopy.boolAttr(listing, "student_ok") { chips.append(KXListingCopy.pickText(language, "留学生可", "留学生可", "Students OK")) }
        if KXListingCopy.boolAttr(listing, "transportation_fee") { chips.append(KXListingCopy.pickText(language, "交通费支给", "交通費支給", "Transport paid")) }
        let holidays = KXListingCopy.attr(listing, "holidays") ?? ""
        if !holidays.isEmpty { chips.append(holidays.count > 6 ? String(holidays.prefix(6)) : holidays) }
        if KXListingCopy.boolAttr(listing, "foreigner_friendly"), chips.count < 5 {
            chips.append(KXListingCopy.pickText(language, "外国人友好", "外国人歓迎", "Foreigner-friendly"))
        }
        return Array(chips.prefix(5))
    }

    var body: some View {
        Button {
            openTaps += 1
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: KXSpacing.md) {
                    Text(companyInitial.isEmpty ? "M" : companyInitial)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                        .frame(width: 50, height: 50)
                        .background(
                            LinearGradient(
                                colors: [KXColor.livingAccentSoft, KXColor.livingWarm.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                                .strokeBorder(KXColor.livingInk.opacity(0.06), lineWidth: 0.8)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(KXListingCopy.displayTitle(listing))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(KXColor.livingInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !companyName.isEmpty {
                            HStack(spacing: 5) {
                                Text(companyName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(KXColor.livingMuted)
                                    .lineLimit(1)
                                if companyVerified {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(KXColor.accent)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

                // Indeed-style key facts: salary + location with leading glyphs.
                HStack(spacing: 14) {
                    if !salaryText.isEmpty {
                        Label(salaryText, systemImage: "yensign.circle.fill")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(KXColor.livingAccent)
                            .lineLimit(1)
                    }
                    if !workLocation.isEmpty {
                        Label(workLocation, systemImage: "mappin.and.ellipse")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KXColor.livingMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                FlowLayout(spacing: 6) {
                    if let employment = employmentLabel {
                        jobChip(employment, filled: true)
                    }
                    if let japanese = japaneseLabel {
                        jobChip(japanese, filled: false)
                    }
                    ForEach(jobFactChips, id: \.self) { chip in
                        jobChip(chip, filled: false)
                    }
                }

                Divider().overlay(KXColor.livingInk.opacity(0.06))

                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    Text(KXListingCopy.pickText(language, "查看详情 · 投递", "詳細を見る・応募", "View details · Apply"))
                        .font(.caption.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(KXColor.livingAccent)
            }
            .padding(14)
            .kxLivingSurface(radius: KXRadius.card, elevated: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(KXPressableStyle(scale: 0.985, dim: 0.9))
        .sensoryFeedback(.impact(weight: .light), trigger: openTaps)
    }

    @ViewBuilder
    private func jobChip(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(filled ? KXColor.livingAccent : KXColor.livingMuted)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(filled ? KXColor.livingAccentSoft : KXColor.livingSoft, in: Capsule())
            .overlay(filled ? Capsule().strokeBorder(KXColor.livingAccent.opacity(0.25), lineWidth: 0.8) : nil)
    }
}

struct KXStructuredListingRow: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    let onOpen: () -> Void
    @State private var openTaps = 0

    var body: some View {
        Button {
            openTaps += 1
            onOpen()
        } label: {
            HStack(alignment: .top, spacing: KXSpacing.md) {
                ZStack(alignment: .bottomLeading) {
                    if let url = listing.coverURL {
                        MediaImageView(url: url)
                            .frame(width: 112, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: KXRadius.tile, style: .continuous)
                            .fill(KXColor.softBackground)
                            .frame(width: 112, height: 104)
                            .overlay {
                                Image(systemName: KXListingCopy.icon(for: listing.type))
                                    .foregroundStyle(.secondary.opacity(0.56))
                            }
                    }
                    if listing.coverIsVideo {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.black.opacity(0.55), in: Circle())
                            .frame(width: 112, height: 104)
                    }
                    KXListingBadge(title: KXListingCopy.formatListingType(listing.type), tint: KXColor.accent)
                        .padding(7)
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        Text(KXListingCopy.priceLabel(listing, language))
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.primary)   // neutral price color (unified across cards)
                            .lineLimit(2)
                        Spacer()
                        KXListingBadge(title: KXListingCopy.statusLabel(listing.status, type: listing.type, language), tint: KXListingCopy.statusColor(listing.status))
                    }
                    Text(KXListingCopy.displayTitle(listing))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(KXListingCopy.structuredMeta(listing, language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    FlowLayout(spacing: 6) {
                        ForEach(KXListingCopy.badges(for: listing, language).prefix(3), id: \.self) { badge in
                            KXListingBadge(title: badge, tint: KXColor.rankTeal)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(KXSpacing.md)
            .kxLivingSurface(radius: KXRadius.card, elevated: true)   // unify: all listing cards share the warm surface
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: openTaps)
    }
}

struct KXListingAttributeSection: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO

    var body: some View {
        KXListingSection(title: KXListingCopy.pickText(language, "核心字段", "基本情報", "Key details"), icon: KXListingCopy.icon(for: listing.type)) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(KXListingCopy.attributes(for: listing, language), id: \.0) { item in
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        Text(KXListingCopy.attributeLabel(item.0, language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(item.1)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KXColor.livingSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
                }
            }
        }
    }
}

struct KXListingSection<Content: View>: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.md) {
            Label(KXListingCopy.formText(title, language), systemImage: icon)
                .font(.headline.weight(.bold))
            content
        }
        .padding(KXSpacing.lg)
        .kxLivingSurface(radius: KXRadius.hero)
    }
}

struct KXListingBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, KXSpacing.sm)
            .frame(height: 24)
            .background(tint.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.18), lineWidth: 0.7)
            }
    }
}

extension KaiXCityListingDTO {
    var primaryCoverMedia: KaiXListingMediaDTO? {
        coverMedia
            ?? cover_media
            ?? card?.coverMedia
            ?? listingCard?.coverMedia
            ?? media?.first(where: { $0.is_cover == true || $0.isCover == true })
            ?? media?.first
    }

    var coverURL: URL? {
        // Skip server-generated placeholder covers — the native placeholder
        // looks far better than the "Generated default cover" card.
        if let cover = primaryCoverMedia,
           !KaiXCityListingDTO.isGeneratedCover(cover.url),
           let url = cover.previewURL {
            return url
        }
        return realCoverURL
    }

    var coverIsVideo: Bool {
        primaryCoverMedia?.normalizedType == "video"
    }
}

extension KaiXAttributeValue {
    var listingDisplayValue: String {
        switch kind {
        case .string(let value):
            return value
        case .double(let value):
            return value.rounded() == value ? "\(Int(value))" : String(format: "%.2f", value)
        case .bool(let value):
            return value ? "是" : "否"
        case .json:
            return ""   // 结构化属性(菜单/团购)由专门的视图渲染,不在通用属性行展示
        case .null:
            return ""
        }
    }
}

/// Identifiable receipt for the post-publish success sheet.
