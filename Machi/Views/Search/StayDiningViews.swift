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
    @State private var openTaps = 0

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
        Button {
            openTaps += 1
            onOpen()
        } label: {
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
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .kxCoverBadge(in: Capsule())
                        .padding(9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    heartButton
                        .padding(3)   // 44pt frame absorbs the rest of the inset
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(KXListingCopy.displayTitle(listing))
                            .font(.system(size: 16, weight: .semibold))   // mid-size title, not 19pt — no longer top-heavy
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if ratingCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.caption2.weight(.semibold))
                                Text(String(format: "%.1f", ratingAvg))
                                    .font(.caption.weight(.semibold))
                                Text("(\(ratingCount))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                        } else if variant == .stay {
                            Text(L("newlyListed", language))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(KXColor.heat)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(KXColor.heat.opacity(0.1), in: Capsule())
                        }
                    }
                    if !stationOrLocation.isEmpty {
                        Label(stationOrLocation, systemImage: "tram")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !subline.isEmpty {
                        Text(subline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(KXListingCopy.priceLabel(listing))
                            .font(.system(size: 17, weight: .bold))   // price = the one accent: a touch bigger + warm
                            .foregroundStyle(KXColor.livingWarm)
                        if variant == .home, let fee = KXListingCopy.attr(listing, "management_fee"), !fee.isEmpty {
                            Text(String(format: L("managementFeeInline", language), fee))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                    if !homeTags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(homeTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(KXColor.livingMuted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
            .kxLivingSurface(radius: 24, elevated: true)
        }
        .buttonStyle(KXPressableStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: openTaps)
        .onAppear {
            if !favoriteSeeded {
                favorited = FavoritesStore.shared.contains(listing.id) || (listing.favorited ?? listing.isFavorited ?? false)
                favoriteSeeded = true
            }
        }
    }

    private var favoriteSnapshot: FavoriteSnapshot {
        FavoriteSnapshot(
            id: listing.id,
            title: KXListingCopy.displayTitle(listing),
            priceLabel: KXListingCopy.priceLabel(listing),
            coverURLString: listing.realCoverURL?.absoluteString,
            type: listing.type,
            locationText: stationOrLocation.isEmpty ? listing.location_text : stationOrLocation,
            savedAt: Date()
        )
    }

    /// 右上角爱心：乐观切换，失败回滚；同时写入本地收藏。
    private var heartButton: some View {
        Button {
            let next = !favorited
            favorited = next
            FavoritesStore.shared.set(favoriteSnapshot, on: next)
            Task {
                do {
                    try await KaiXAPIClient.shared.favoriteListing(listing.id, on: next)
                } catch {
                    favorited = !next
                    FavoritesStore.shared.set(favoriteSnapshot, on: !next)
                }
            }
        } label: {
            Image(systemName: favorited ? "heart.fill" : "heart")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(favorited ? KXColor.heat : .primary)
                .symbolEffect(.bounce, value: favorited)
                .frame(width: 32, height: 32)
                .kxCoverBadge(in: Circle())
                .frame(width: 44, height: 44)        // 44pt min tap target (HIG)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .kxFavoriteAccessibility(favorited, language)
    }
}

/// 封面图：listing media 第一张，缺图时按住宿/房源给冷色渐变占位。
private struct KXStayCoverArtwork: View {
    let listing: KaiXCityListingDTO
    let isStay: Bool

    /// All real listing photos (generated covers dropped) so the cover can
    /// swipe between them; falls back to the single resolved cover.
    private var coverURLs: [URL] {
        let media = (listing.media ?? []).filter { !KaiXCityListingDTO.isGeneratedCover($0.url) }
        let urls = media.compactMap { $0.previewURL }
        if !urls.isEmpty { return urls }
        return listing.realCoverURL.map { [$0] } ?? []
    }

    var body: some View {
        // Photo-led cover: swipes between photos (with dots) when there are
        // several, else a single fill — placeholder always behind so slow/
        // failed loads degrade to a tasteful tile instead of a grey box.
        KXCoverCarousel(urls: coverURLs, aspectRatio: 4.0 / 3.0, targetPixelSize: 960) {
            stayPlaceholder
        }
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
