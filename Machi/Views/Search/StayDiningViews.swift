import SwiftUI

// 租房 · 住宿：长租房源与民宿短住共用的照片主导卡片。
// 与 web 端 ListingKit 的住宿卡同构 —— 大图、心愿收藏、
// 评分内联、价格收尾；home 变体展示户型/面积/敷礼金，stay 变体展示
// 房型/可住人数/每晚价。

struct KXStayListingCard: View {
    enum Variant { case home, stay }

    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    let variant: Variant
    let onOpen: () -> Void

    @State private var favorited: Bool = false
    @State private var favoriteSeeded = false

    private var ratingAvg: Double { listing.rating_avg ?? listing.ratingAvg ?? 0 }
    private var ratingCount: Int { listing.rating_count ?? listing.ratingCount ?? 0 }

    /// DiscoverView 里的同名扩展是 fileprivate，这里按相同口径本地判定。
    private var coverIsVideo: Bool {
        let media = listing.coverMedia ?? listing.cover_media ?? listing.media?.first
        let type = (media?.media_type ?? media?.mediaType ?? media?.type ?? "").lowercased()
        return type.contains("video")
    }

    private var stationOrLocation: String {
        KXListingCopy.attr(listing, "nearest_station")
            ?? KXListingCopy.attr(listing, "near_station")
            ?? (listing.location_text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var subline: String {
        switch variant {
        case .stay:
            let guests = KXListingCopy.attr(listing, "max_guests").flatMap { $0.isEmpty ? nil : "可住 \($0) 人" }
            return [
                KXListingCopy.attr(listing, "room_type") ?? KXListingCopy.categoryLabel(listing.category ?? "", language),
                guests,
                KXListingCopy.boolAttr(listing, "breakfast_included") ? "含早餐" : nil,
            ].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        case .home:
            let area = KXListingCopy.attr(listing, "area_sqm").flatMap { $0.isEmpty ? nil : "\($0)㎡" }
            let moveIn = KXListingCopy.attr(listing, "move_in_date").flatMap { $0.isEmpty ? nil : "\($0) 入住" }
            return [KXListingCopy.attr(listing, "layout"), area, moveIn]
                .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        }
    }

    private var homeTags: [String] {
        guard variant == .home else { return [] }
        var tags: [String] = []
        let deposit = KXListingCopy.attr(listing, "deposit") ?? ""
        let keyMoney = KXListingCopy.attr(listing, "key_money") ?? ""
        if !deposit.isEmpty, deposit == "0" || deposit.contains("无") || deposit.contains("なし") { tags.append("敷金 0") }
        if !keyMoney.isEmpty, keyMoney == "0" || keyMoney.contains("无") || keyMoney.contains("なし") { tags.append("礼金 0") }
        if KXListingCopy.boolAttr(listing, "furnished") { tags.append("家具家电") }
        if KXListingCopy.boolAttr(listing, "short_term_allowed") { tags.append("可短租") }
        if KXListingCopy.boolAttr(listing, "pet_allowed") { tags.append("可养宠") }
        return Array(tags.prefix(3))
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    KXStayCoverArtwork(listing: listing, isStay: variant == .stay)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    if coverIsVideo {
                        Image(systemName: "play.fill")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.55), in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    if listing.verification_status == "verified" {
                        // Solid, bordered pill (was a borderless ultraThinMaterial
                        // that washed out over photos). Brand-green seal + hairline
                        // stroke + soft shadow keeps it legible on any cover.
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(KXColor.accent)
                            Text(variant == .stay ? "认证房东" : "已核验")
                                .foregroundStyle(.primary)
                        }
                        .font(.caption2.weight(.black))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.14), radius: 7, y: 2)
                        .padding(9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    heartButton
                        .padding(9)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(KXListingCopy.displayTitle(listing))
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if ratingCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.caption2.weight(.black))
                                Text(String(format: "%.1f", ratingAvg))
                                    .font(.caption.weight(.black))
                                Text("(\(ratingCount))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                        } else if variant == .stay {
                            Text(L("newlyListed", language))
                                .font(.caption2.weight(.black))
                                .foregroundStyle(KXColor.heat)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(KXColor.heat.opacity(0.1), in: Capsule())
                        }
                    }
                    if !stationOrLocation.isEmpty {
                        Label(stationOrLocation, systemImage: "tram")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !subline.isEmpty {
                        Text(subline)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(KXListingCopy.priceLabel(listing))
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.primary)
                        if variant == .home, let fee = KXListingCopy.attr(listing, "management_fee"), !fee.isEmpty {
                            Text(String(format: L("managementFeeInline", language), fee))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                    if !homeTags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(homeTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(KXColor.livingMuted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(8)
            .kxLivingSurface(radius: 24, elevated: true)
        }
        .buttonStyle(KXPressableStyle())
        .onAppear {
            if !favoriteSeeded {
                favorited = listing.favorited ?? listing.isFavorited ?? false
                favoriteSeeded = true
            }
        }
    }

    /// 右上角爱心：乐观切换，失败回滚。
    private var heartButton: some View {
        Button {
            let next = !favorited
            favorited = next
            Task {
                do {
                    try await KaiXAPIClient.shared.favoriteListing(listing.id, on: next)
                } catch {
                    favorited = !next
                }
            }
        } label: {
            Image(systemName: favorited ? "heart.fill" : "heart")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(favorited ? KXColor.heat : .primary)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 封面图：listing media 第一张，缺图时按住宿/房源给冷色渐变占位。
private struct KXStayCoverArtwork: View {
    let listing: KaiXCityListingDTO
    let isStay: Bool

    private var coverURL: URL? { listing.realCoverURL }

    var body: some View {
        // Reserve a clean 4:3 box first: Color.clear has no intrinsic size, so
        // the aspect ratio is exact and never warped by the photo's own
        // dimensions. The cover then fills it (scaledToFill + clip), so every
        // card lands the identical size regardless of the source image.
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                ZStack {
                    // Placeholder always sits behind the photo: while it decodes
                    // or if the remote image fails (slow 4G), the tasteful
                    // placeholder shows through instead of a blank grey box.
                    stayPlaceholder
                    if let url = coverURL {
                        CachedMediaImageView(url: url, targetPixelSize: 960, failureMode: .transparent)
                    }
                }
            }
            .clipped()
    }

    private var stayPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    KXColor.livingSoft,
                    KXColor.livingAccentSoft.opacity(0.72),
                    Color(.systemBackground).opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(KXColor.livingWarm.opacity(0.10))
                .frame(width: 150, height: 150)
                .offset(x: -86, y: -58)
            Circle()
                .fill(KXColor.livingAccent.opacity(0.10))
                .frame(width: 180, height: 180)
                .offset(x: 118, y: 76)
            VStack(spacing: 9) {
                Image(systemName: isStay ? "bed.double.fill" : "house.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(KXColor.livingAccent.opacity(0.78))
                Text(isStay ? "精选住宿" : "精选房源")
                    .font(.caption.weight(.black))
                    .foregroundStyle(KXColor.livingAccent)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color(.systemBackground).opacity(0.68), in: Capsule())
                Text(KXListingCopy.displayTitle(listing))
                    .font(.footnote.weight(.black))
                    .foregroundStyle(KXColor.livingInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
            }
        }
    }
}
