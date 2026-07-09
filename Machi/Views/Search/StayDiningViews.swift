import SwiftUI

// 租房 · 住宿：长租房源与民宿短住共用的照片主导卡片。
// 与 web 端 ListingKit 的住宿卡同构 —— 大图、心愿收藏、
// 评分内联、价格收尾；home 变体展示户型/面积/敷礼金，stay 变体展示
// 房型/可住人数/每晚价。

struct KXStayListingCard: View {
    enum Variant { case home, stay, forsale }

    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    let variant: Variant
    let onOpen: () -> Void

    /// 收藏态实时从 FavoritesStore 推导(观察 items/removedIds),跨页取消后
    /// 回到列表红心即刷新——旧的 favoriteSeeded 闩锁会留下过期红心。
    /// store 没记录时用服务端 DTO 兜底,本会话明确取消过的不再点亮。
    @ObservedObject private var favorites = FavoritesStore.shared
    @State private var openTaps = 0

    private var favorited: Bool {
        favorites.contains(listing.id)
            || (!favorites.wasRemoved(listing.id) && (listing.favorited ?? listing.isFavorited ?? false))
    }

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
            let guests = KXListingCopy.attr(listing, "max_guests").flatMap { $0.isEmpty ? nil : KXListingCopy.pickText(language, "可住 \($0) 人", "定員\($0)名", "Sleeps \($0)") }
            return [
                KXListingCopy.attr(listing, "room_type") ?? KXListingCopy.categoryLabel(listing.category ?? "", language),
                guests,
                KXListingCopy.boolAttr(listing, "breakfast_included") ? KXListingCopy.pickText(language, "含早餐", "朝食付き", "Breakfast included") : nil,
            ].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        case .home:
            let area = KXListingCopy.attr(listing, "area_sqm").flatMap { $0.isEmpty ? nil : "\($0)㎡" }
            let moveIn = KXListingCopy.attr(listing, "move_in_date").flatMap { $0.isEmpty ? nil : KXListingCopy.pickText(language, "\($0) 入住", "\($0) 入居可", "Move in \($0)") }
            return [KXListingCopy.attr(listing, "layout"), area, moveIn]
                .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        case .forsale:
            let area = KXListingCopy.attr(listing, "area_sqm").flatMap { $0.isEmpty ? nil : "\($0)㎡" }
            let age = KXListingCopy.attr(listing, "building_age").flatMap { $0.isEmpty ? nil : "築\($0)" }
            return [KXListingCopy.attr(listing, "layout"), area, age, KXListingCopy.attr(listing, "structure")]
                .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        }
    }

    /// 买房卡的标签：利回り / 土地面积 / 投资·出售意图。
    private var forsaleTags: [String] {
        guard variant == .forsale else { return [] }
        var tags: [String] = []
        if let yield = KXListingCopy.attr(listing, "yield_rate"), !yield.isEmpty {
            tags.append(KXListingCopy.pickText(language, "利回り \(yield)%", "利回り \(yield)%", "Yield \(yield)%"))
        }
        if let land = KXListingCopy.attr(listing, "land_area"), !land.isEmpty {
            tags.append(KXListingCopy.pickText(language, "土地 \(land)㎡", "土地 \(land)㎡", "Land \(land)㎡"))
        }
        let intent = KXListingCopy.attr(listing, "listing_intent") ?? ""
        if intent == "investment" {
            tags.append(KXListingCopy.pickText(language, "投资", "投資向け", "Investment"))
        } else if !intent.isEmpty {
            tags.append(KXListingCopy.pickText(language, "出售", "売買", "For sale"))
        }
        return Array(tags.prefix(3))
    }

    private var homeTags: [String] {
        guard variant == .home else { return [] }
        var tags: [String] = []
        let deposit = KXListingCopy.attr(listing, "deposit") ?? ""
        let keyMoney = KXListingCopy.attr(listing, "key_money") ?? ""
        if !deposit.isEmpty, deposit == "0" || deposit.contains("无") || deposit.contains("なし") { tags.append(KXListingCopy.pickText(language, "敷金 0", "敷金 0", "No deposit")) }
        if !keyMoney.isEmpty, keyMoney == "0" || keyMoney.contains("无") || keyMoney.contains("なし") { tags.append(KXListingCopy.pickText(language, "礼金 0", "礼金 0", "No key money")) }
        if KXListingCopy.boolAttr(listing, "furnished") { tags.append(KXListingCopy.pickText(language, "家具家电", "家具家電付き", "Furnished")) }
        if KXListingCopy.boolAttr(listing, "short_term_allowed") { tags.append(KXListingCopy.pickText(language, "可短租", "短期可", "Short-term OK")) }
        if KXListingCopy.boolAttr(listing, "pet_allowed") { tags.append(KXListingCopy.pickText(language, "可养宠", "ペット可", "Pets OK")) }
        return Array(tags.prefix(3))
    }

    /// 变体对应的灰色标签行（民宿暂无）。
    private var variantTags: [String] {
        switch variant {
        case .home: return homeTags
        case .forsale: return forsaleTags
        case .stay: return []
        }
    }

    var body: some View {
        Button {
            openTaps += 1
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    KXStayCoverArtwork(listing: listing, isStay: variant == .stay)
                        .clipShape(RoundedRectangle(cornerRadius: KXRadius.lg, style: .continuous))
                    if coverIsVideo {
                        Image(systemName: "play.fill")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.55), in: Circle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    // 封面左上角徽章：Machi 推荐金徽章叠在认证徽章之上，二者可同时出现。
                    VStack(alignment: .leading, spacing: 6) {
                        if listing.isMachiRecommended {
                            HStack(spacing: KXSpacing.xs) {
                                Image(systemName: "sparkles")
                                Text(KXListingCopy.pickText(language, "Machi推荐", "Machiおすすめ", "Machi Pick"))
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(KXColor.onTint(KXColor.rankGold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(KXColor.rankGold, in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 0.7))
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        }
                        if listing.verification_status == "verified" {
                            // Solid, bordered pill (was a borderless ultraThinMaterial
                            // that washed out over photos). Brand-green seal + hairline
                            // stroke + soft shadow keeps it legible on any cover.
                            HStack(spacing: KXSpacing.xs) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(KXColor.accent)
                                Text(variant == .stay
                                     ? KXListingCopy.pickText(language, "认证房东", "認証ホスト", "Verified host")
                                     : KXListingCopy.pickText(language, "已核验", "確認済み", "Verified"))
                                    .foregroundStyle(.primary)
                            }
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .kxCoverBadge(in: Capsule())
                        }
                    }
                    .padding(KXSpacing.sm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    heartButton
                        .padding(3)   // 44pt frame absorbs the rest of the inset
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: KXSpacing.sm) {
                        Text(KXListingCopy.displayTitle(listing))
                            .kxScaledFont(16, relativeTo: .subheadline, weight: .semibold)   // mid-size title, not 19pt — no longer top-heavy
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
                        Text(KXListingCopy.priceLabel(listing, language))
                            .kxScaledFont(17, relativeTo: .headline, weight: .bold)   // price = the one accent: a touch bigger + warm
                            .foregroundStyle(KXColor.livingWarm)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if variant == .home || variant == .forsale, let fee = KXListingCopy.attr(listing, "management_fee"), !fee.isEmpty {
                            Text(String(format: L("managementFeeInline", language), fee))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, KXSpacing.xs)
                    if !variantTags.isEmpty || !listing.machiBadgeList.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(variantTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(KXColor.livingMuted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, KXSpacing.xs)
                                    .background(KXColor.livingSoft, in: RoundedRectangle(cornerRadius: KXRadius.xs, style: .continuous))
                            }
                            // 闪耀标签：星域 partner 自定义标签，金色描边小药丸。
                            ForEach(Array(listing.machiBadgeList.prefix(3)), id: \.self) { badge in
                                Text(badge)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(KXColor.rankGold)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, KXSpacing.xs)
                                    .background(KXColor.rankGold.opacity(0.14), in: RoundedRectangle(cornerRadius: KXRadius.xs, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: KXRadius.xs, style: .continuous).stroke(KXColor.rankGold.opacity(0.35), lineWidth: 0.7))
                            }
                        }
                        .padding(.top, KXSpacing.xxs)
                    }
                }
                .padding(.horizontal, KXSpacing.xs)
            }
            .padding(10)
            .kxLivingSurface(radius: KXRadius.hero, elevated: true)
        }
        .buttonStyle(KXPressableStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: openTaps)
    }

    private var favoriteSnapshot: FavoriteSnapshot {
        // 统一走 snapshot(from:) 以带上原始价格数据(收藏页按当前语言现算),
        // 只覆写更贴近卡片语境的位置文案。
        var snapshot = FavoritesStore.snapshot(from: listing)
        if !stationOrLocation.isEmpty { snapshot.locationText = stationOrLocation }
        return snapshot
    }

    /// 右上角爱心：乐观切换，失败回滚；同时写入本地收藏。游客先弹登录。
    private var heartButton: some View {
        Button {
            guard GuestSession.requireSignedIn(reason: KXListingCopy.pickText(language, "登录后可以收藏喜欢的信息。", "ログインするとお気に入りに保存できます。", "Sign in to save listings you like.")) else { return }
            let next = !favorited
            // 乐观写 store,favorited 即时跟随推导刷新;失败回滚。
            FavoritesStore.shared.set(favoriteSnapshot, on: next)
            Task {
                do {
                    try await KaiXAPIClient.shared.favoriteListing(listing.id, on: next)
                } catch {
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
    @Environment(\.appLanguage) private var language
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
                    .kxScaledFont(30, weight: .semibold)
                    .foregroundStyle(KXColor.livingAccent.opacity(0.78))
                Text(isStay
                     ? KXListingCopy.pickText(language, "精选住宿", "おすすめの宿", "Featured stay")
                     : KXListingCopy.pickText(language, "精选房源", "おすすめ物件", "Featured home"))
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
