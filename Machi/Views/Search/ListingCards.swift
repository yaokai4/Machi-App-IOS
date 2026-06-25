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
    let width: CGFloat
    private var inner: CGFloat { max(0, width - 14) }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KXColor.softBackground)
                .frame(width: inner, height: inner)
            KXSkeletonBone(width: 72, height: 15)
            KXSkeletonBone(width: inner - 24, height: 11)
            KXSkeletonBone(width: 96, height: 9)
        }
        .padding(7)
        .padding(.bottom, 2)
        .frame(width: width, alignment: .leading)
        .kxLivingSurface(radius: 18)
        .kxShimmer()
    }
}

struct KXJobSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
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
                    KXSkeletonBone(width: 56, height: 22, radius: 11)
                }
            }
        }
        .padding(14)
        .kxLivingSurface(radius: 20, elevated: true)
        .kxShimmer()
    }
}

struct KXBigPhotoSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(KXColor.softBackground) }
            VStack(alignment: .leading, spacing: 7) {
                KXSkeletonBone(width: 200, height: 13)
                KXSkeletonBone(width: 150, height: 10)
                KXSkeletonBone(width: 110, height: 13)
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .kxLivingSurface(radius: 24, elevated: true)
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
            content.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
        }
    }
}

struct KXSecondhandListingCard: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    var width: CGFloat? = nil
    let onOpen: () -> Void

    private var innerWidth: CGFloat? {
        width.map { max(0, $0 - 14) }
    }

    private var statusBadgeMaxWidth: CGFloat? {
        innerWidth.map { max(70, $0 - 48) }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 9) {
                cover
                    .frame(width: innerWidth)
                Text(KXListingCopy.priceLabel(listing, language))
                    .font(.headline.weight(.black))
                    .foregroundStyle(KXColor.heat)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(width: innerWidth, alignment: .leading)
                Text(KXListingCopy.displayTitle(listing))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(width: innerWidth, alignment: .leading)
                let badges = KXListingCopy.secondhandCardBadges(for: listing, language)
                if !badges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(badges.prefix(2), id: \.self) { badge in
                            Text(badge)
                                .font(.caption2.weight(.black))
                                .foregroundStyle(KXColor.rankTeal)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .padding(.horizontal, 6)
                                .frame(height: 20)
                                .background(KXColor.rankTeal.opacity(0.09), in: Capsule())
                        }
                    }
                    .frame(width: innerWidth, alignment: .leading)
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2.weight(.bold))
                    Text(KXListingCopy.compactMeta(listing, language))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: innerWidth, alignment: .leading)
            }
            .padding(7)
            .padding(.bottom, 2)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
            .kxLivingSurface(radius: 18)
        }
        .frame(maxWidth: width ?? .infinity, alignment: .leading)
        .buttonStyle(.plain)
    }

    private var cover: some View {
        ZStack {
            if let url = listing.coverURL {
                MediaImageView(url: url, targetPixelSize: 720)
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
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                Circle()
                    .fill(KXListingCopy.statusColor(listing.status))
                    .frame(width: 6, height: 6)
                Text(KXListingCopy.formatListingStatus(listing.status, type: listing.type, language))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            .frame(maxWidth: statusBadgeMaxWidth, alignment: .leading)
            .padding(7)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: listing.favorited == true ? "heart.fill" : "heart")
                .font(.caption2.weight(.bold))
                .foregroundStyle(listing.favorited == true ? KXColor.heat : .primary)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                .padding(7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
        }
    }
}

struct ListingMediaPage: View {
    let media: KaiXListingMediaDTO
    let index: Int
    let total: Int

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
            if total > 1 {
                Text("\(index + 1)/\(total)")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
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
                    .font(.system(size: 34, weight: .bold))
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
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 12) {
                    Text(companyInitial.isEmpty ? "M" : companyInitial)
                        .font(.title3.weight(.black))
                        .foregroundStyle(KXColor.livingAccent)
                        .frame(width: 50, height: 50)
                        .background(
                            LinearGradient(
                                colors: [KXColor.livingAccentSoft, KXColor.livingWarm.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
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
                            .font(.subheadline.weight(.black))
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
                        .font(.caption.weight(.black))
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.black))
                }
                .foregroundStyle(KXColor.livingAccent)
            }
            .padding(14)
            .kxLivingSurface(radius: 20, elevated: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(KXPressableStyle(scale: 0.985, dim: 0.9))
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

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    if let url = listing.coverURL {
                        MediaImageView(url: url)
                            .frame(width: 112, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                            .font(.headline.weight(.black))
                            .foregroundStyle(KXColor.heat)
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
            .padding(11)
            .kxGlassSurface(radius: 20, elevated: true)
        }
        .buttonStyle(.plain)
    }
}

struct KXListingAttributeSection: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO

    var body: some View {
        KXListingSection(title: KXListingCopy.pickText(language, "核心字段", "基本情報", "Key details"), icon: KXListingCopy.icon(for: listing.type)) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(KXListingCopy.attributes(for: listing, language), id: \.0) { item in
                    VStack(alignment: .leading, spacing: 4) {
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
                    .background(KXColor.livingSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            Label(KXListingCopy.formText(title, language), systemImage: icon)
                .font(.headline.weight(.bold))
            content
        }
        .padding(KXSpacing.lg)
        .kxLivingSurface(radius: 22)
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
            .padding(.horizontal, 8)
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
