import SwiftUI

// 商家与服务：星级点评、认证商家目录、
// 商家公开主页和点评管理。Web 端 BusinessDirectory.tsx / ListingKit 的同构实现。

// MARK: - 星级

struct KXRatingStarsView: View {
    let value: Double
    var count: Int? = nil
    var showsValue: Bool = true
    var starSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            HStack(spacing: 1.5) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: "star.fill")
                        .font(.system(size: starSize, weight: .bold))
                        .foregroundStyle(star <= Int(value.rounded()) ? Color.orange : Color.secondary.opacity(0.24))
                }
            }
            if showsValue, value > 0 {
                Text(String(format: "%.1f", value))
                    .font(.system(size: starSize + 1, weight: .black))
                    .foregroundStyle(.orange)
            }
            if let count, count > 0 {
                Text("(\(count))")
                    .font(.system(size: starSize, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 服务频道卡片

struct KXServiceListingCard: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    let onOpen: () -> Void

    @State private var favorited: Bool = false
    @State private var favoriteSeeded = false

    private var ratingAvg: Double { listing.rating_avg ?? listing.ratingAvg ?? 0 }
    private var ratingCount: Int { listing.rating_count ?? listing.ratingCount ?? 0 }
    private var category: String { listing.category ?? "" }

    private var ctaTitle: String {
        if KXListingCopy.isStayCategory(category) { return KXListingCopy.pickText(language, "查房价", "料金を見る", "View price") }
        if KXListingCopy.isFoodCategory(category) { return KXListingCopy.pickText(language, "在线订座", "予約する", "Book table") }
        switch category {
        case "景点门票", "一日游": return KXListingCopy.pickText(language, "订门票", "チケット予約", "Book tickets")
        default: return KXListingCopy.pickText(language, "预约", "予約", "Book")
        }
    }

    private var priceText: String {
        if let range = listing.attributes?["price_range"]?.stringValue, !range.isEmpty { return range }
        return KXListingCopy.priceLabel(listing)
    }

    private var openHours: String {
        KXListingCopy.attr(listing, "open_hours") ?? KXListingCopy.attr(listing, "availability") ?? ""
    }

    // Mirrors KXStayListingCard exactly: inset 4:3 cover with rounded corners,
    // save heart top-right, bordered verified pill top-left — so merchant
    // cards read as photo-led Airbnb listings, not boxy rectangles.
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    ListingCoverArtwork(listing: listing)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    HStack(spacing: 6) {
                        if !category.isEmpty {
                            Text(KXListingCopy.categoryLabel(category, language))
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.regularMaterial, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
                                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        }
                        if listing.verification_status == "verified" {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(KXColor.accent)
                                Text(L("verifiedMerchant", language)).foregroundStyle(.primary)
                            }
                            .font(.caption2.weight(.black))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
                            .shadow(color: .black.opacity(0.14), radius: 7, y: 2)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                                Image(systemName: "star.fill").font(.caption2.weight(.black)).foregroundStyle(.orange)
                                Text(String(format: "%.1f", ratingAvg)).font(.caption.weight(.black)).foregroundStyle(.primary)
                                Text("(\(ratingCount))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(L("noReviews", language))
                                .font(.caption2.weight(.black))
                                .foregroundStyle(KXColor.livingWarm)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(KXColor.livingWarm.opacity(0.1), in: Capsule())
                        }
                    }
                    Label(listing.location_text?.isEmpty == false ? listing.location_text! : (listing.city_slug ?? ""), systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !openHours.isEmpty {
                        Label(openHours, systemImage: "clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(priceText)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(KXColor.livingWarm)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(ctaTitle)
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .frame(height: 28)
                            .background(KXColor.livingAccent, in: Capsule())
                    }
                    .padding(.top, 2)
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

    private var heartButton: some View {
        Button {
            let next = !favorited
            favorited = next
            Task {
                do { try await KaiXAPIClient.shared.favoriteListing(listing.id, on: next) }
                catch { favorited = !next }
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

/// 封面图：listing media 第一张，缺图时按类型渐变占位。
private struct ListingCoverArtwork: View {
    let listing: KaiXCityListingDTO

    private var coverURL: URL? { listing.realCoverURL }

    private var category: String { listing.category ?? "" }

    var body: some View {
        // Reserve an exact 4:3 box with a zero-intrinsic-size Color.clear so a
        // tall/odd source photo can never stretch the card (this was the bug:
        // applying .aspectRatio to a ZStack that already carried the image's
        // own intrinsic size did nothing). The cover then fills + clips into
        // the box, identical to KXStayCoverArtwork.
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                ZStack {
                    // Placeholder behind the photo so failed/slow loads degrade
                    // to a tasteful tile instead of a blank grey rectangle.
                    servicePlaceholder
                    if let url = coverURL {
                        CachedMediaImageView(url: url, targetPixelSize: 720, failureMode: .transparent)
                    }
                }
            }
            .clipped()
    }

    private var servicePlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    KXColor.livingSoft,
                    KXColor.livingWarm.opacity(0.12),
                    Color(.systemBackground).opacity(0.94),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(KXColor.livingWarm.opacity(0.11))
                .frame(width: 140, height: 140)
                .offset(x: -80, y: -46)
            Circle()
                .fill(KXColor.livingAccent.opacity(0.09))
                .frame(width: 160, height: 160)
                .offset(x: 110, y: 56)
            VStack(spacing: 8) {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(KXColor.livingWarm.opacity(0.78))
                Text(category.isEmpty ? "本地精选" : KXListingCopy.categoryLabel(category, .zh))
                    .font(.caption.weight(.black))
                    .foregroundStyle(KXColor.livingWarm)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color(.systemBackground).opacity(0.68), in: Capsule())
            }
        }
    }

    private var placeholderIcon: String {
        if KXListingCopy.isFoodCategory(category) { return "fork.knife" }
        switch category {
        case "民宿", "酒店", "温泉旅馆", "公寓式酒店", "短住公寓": return "bed.double.fill"
        case "景点门票", "一日游", "本地向导", "体验活动", "包车行程": return "ticket.fill"
        case "接送机", "机场接送", "车站接送", "包车", "行李协助": return "car.fill"
        case "材料翻译", "市役所陪同", "银行卡协助", "手机卡协助", "租房申请协助", "签证材料整理", "翻译", "翻译手续", "签证/手续协助": return "character.bubble.fill"
        case "搬家", "退房清洁", "粗大垃圾协助", "行李搬运", "家具家电配送协助", "搬家清洁", "清洁": return "sparkles"
        case "手机卡开通", "网络开通", "水电煤协助", "地址登记协助", "粗大垃圾预约", "生活跑腿": return "house.fill"
        case "美容美发", "美甲", "按摩", "皮肤管理", "体检/牙科预约协助": return "scissors"
        case "宠物寄养", "遛狗", "临时照看", "儿童用品租赁", "家庭协助", "宠物服务": return "heart.fill"
        default: return "storefront.fill"
        }
    }
}

// MARK: - 认证商家横滑条（服务频道内）

struct MerchantDirectoryStripView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let citySlug: String

    @State private var items: [KaiXBusinessPublicDTO] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(L("verifiedMerchant", language), systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            router.open(.businessDirectory(citySlug: citySlug))
                        } label: {
                            HStack(spacing: 3) {
                                Text(L("allMerchants", language))
                                Image(systemName: "chevron.right")
                            }
                            .font(.caption.weight(.black))
                            .foregroundStyle(Color.green)
                        }
                        .buttonStyle(.plain)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(items.prefix(12)) { business in
                                Button {
                                    router.open(.businessProfile(businessId: business.id))
                                } label: {
                                    MerchantStripCard(business: business)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(KXSpacing.md)
                .kxGlassSurface(radius: KXRadius.lg, elevated: true)
            }
        }
        .task(id: citySlug) {
            guard !loaded else { return }
            loaded = true
            if let response = try? await KaiXAPIClient.shared.businessesDirectory(city: citySlug) {
                items = response.items
            }
        }
    }
}

private struct MerchantStripCard: View {
    @Environment(\.appLanguage) private var language
    let business: KaiXBusinessPublicDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MerchantLogoView(business: business, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Text(business.business_name ?? L("merchantFallbackName", language))
                            .font(.caption.weight(.black))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.green)
                    }
                    Text(business.business_type ?? business.service_categories?.first ?? L("localMerchant", language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack {
                if (business.rating_count ?? 0) > 0 {
                    KXRatingStarsView(value: business.rating_avg ?? 0, count: business.rating_count, starSize: 10)
                } else {
                    Text(L("noReviews", language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: L("servicesCount", language), business.published_listing_count ?? 0))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: 196, alignment: .leading)
        .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(KXColor.glassStroke.opacity(0.7), lineWidth: 0.7))
    }
}

private struct MerchantLogoView: View {
    let business: KaiXBusinessPublicDTO
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Color.green.opacity(0.12))
            Image(systemName: "storefront")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.green)
            if let url = (business.logo_url ?? "").kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: size * 3, failureMode: .transparent)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 认证商家目录（全屏）

struct MerchantDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let citySlug: String
    let currentUser: UserEntity

    @State private var items: [KaiXBusinessPublicDTO] = []
    @State private var category = "全部"
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let categories = ["全部"] + KXListingCopy.serviceCreateCategories

    private var cityName: String {
        KaiXRegionDirectory.resolve(regionCode: citySlug)?.cityName ?? citySlug
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    categoryChips
                    if isLoading {
                        KXInlineLoader()
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if let errorMessage {
                        ErrorStateView(message: errorMessage) { Task { await load() } }
                    } else if items.isEmpty {
                        EmptyStateView(
                            title: KXListingCopy.pickText(language, "暂无认证商家", "認証済み店舗はまだありません", "No verified merchants yet"),
                            subtitle: KXListingCopy.pickText(language, "商家可以在「工作台 → 商家服务后台」提交认证申请，审核通过后展示在这里。", "店舗は「ワークベンチ → 店舗サービス管理」から認証申請できます。審査後ここに表示されます。", "Merchants can apply in Workbench → Merchant service console. Approved profiles appear here."),
                            systemImage: "storefront"
                        )
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        ForEach(items) { business in
                            Button {
                                router.open(.businessProfile(businessId: business.id))
                            } label: {
                                MerchantDirectoryRow(business: business)
                            }
                            .buttonStyle(KXPressableStyle())
                        }
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 12)
                .kxTabBarSafeBottomPadding()
            }
            .refreshable { await load() }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: KXSpacing.sm) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .kxGlassCircle()
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(cityName) · \(L("verifiedMerchant", language))")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(L("verifiedMerchantSubtitle", language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.green)
                TextField(KXListingCopy.pickText(language, "搜索商家名称、服务类型…", "店舗名・サービス種類を検索…", "Search merchant name or service type..."), text: $query)
                    .font(.subheadline.weight(.semibold))
                    .submitLabel(.search)
                    .onSubmit { Task { await load() } }
            }
            .padding(.horizontal, KXSpacing.lg)
            .frame(height: 44)
            .background(KXColor.softBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { item in
                    Button {
                        category = item
                        Task { await load() }
                    } label: {
                        Text(KXListingCopy.categoryLabel(item, language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(category == item ? Color.white : .primary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(category == item ? Color.green : KXColor.softBackground.opacity(0.88), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await KaiXAPIClient.shared.businessesDirectory(
                city: citySlug,
                category: category,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            items = response.items
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

private struct MerchantDirectoryRow: View {
    @Environment(\.appLanguage) private var language
    let business: KaiXBusinessPublicDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MerchantLogoView(business: business, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(business.business_name ?? L("merchantFallbackName", language))
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Color.green)
                    }
                    Text(business.business_type ?? L("localMerchant", language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if (business.rating_count ?? 0) > 0 {
                        KXRatingStarsView(value: business.rating_avg ?? 0, starSize: 11)
                    }
                    Text(String(format: L("onlineServicesCount", language), business.published_listing_count ?? 0))
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.secondary)
                }
            }
            if let description = business.description, !description.isEmpty {
                Text(description)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let categories = business.service_categories, !categories.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(categories.prefix(5), id: \.self) { item in
                        Text(item)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .padding(KXSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg, elevated: true)
    }
}

// MARK: - 商家公开主页

struct BusinessPublicProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    let businessId: String
    let currentUser: UserEntity

    @State private var response: KaiXBusinessPublicResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KXSpacing.sm) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .kxGlassCircle()
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(response?.business.business_name ?? L("merchantProfileTitle", language))
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(L("verifiedMerchant", language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .kxGlassBar(ignoresTopSafeArea: true)
            .overlay(alignment: .bottom) { Divider().opacity(0.18) }

            Group {
                if isLoading {
                    LoadingView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load() } }
                } else if let response {
                    content(response)
                } else {
                    EmptyStateView(title: L("merchantNotFoundTitle", language), subtitle: L("merchantNotFoundHelp", language), systemImage: "storefront")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: businessId) { await load() }
    }

    private func content(_ response: KaiXBusinessPublicResponse) -> some View {
        let business = response.business
        let listings = response.listings ?? []
        let reviews = response.reviews ?? []
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                // 店铺名片
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        MerchantLogoView(business: business, size: 60)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Text(business.business_name ?? L("merchantFallbackName", language))
                                    .font(.title3.weight(.black))
                                    .lineLimit(1)
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Color.green)
                            }
                            if (business.rating_count ?? 0) > 0 {
                                KXRatingStarsView(value: business.rating_avg ?? 0, count: business.rating_count, starSize: 13)
                            } else {
                                Text(L("noReviews", language))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(String(format: L("onlineServicesCount", language), business.published_listing_count ?? 0))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if let description = business.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let categories = business.service_categories, !categories.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(categories, id: \.self) { item in
                                Text(item)
                                    .font(.caption2.weight(.black))
                                    .foregroundStyle(Color.green)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if let address = business.address, !address.isEmpty {
                            Label(address, systemImage: "mappin.and.ellipse")
                        }
                        if let contact = business.contact_method, !contact.isEmpty {
                            Label(contact, systemImage: "phone")
                        }
                        if let website = business.website, !website.isEmpty {
                            Label(website, systemImage: "globe")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(KXSpacing.lg)
                .kxGlassSurface(radius: KXRadius.lg, elevated: true)

                // 在线服务
                if !listings.isEmpty {
                    Text(KXListingCopy.pickText(language, "在线服务 (\(listings.count))", "公開サービス (\(listings.count))", "Online services (\(listings.count))"))
                        .font(.headline.weight(.black))
                        .padding(.horizontal, 2)
                    LazyVStack(spacing: 12) {
                        ForEach(listings) { listing in
                            KXServiceListingCard(listing: listing) {
                                router.open(.cityListingDetail(listingId: listing.id))
                            }
                        }
                    }
                }

                // 最新点评
                if !reviews.isEmpty {
                    Text(L("latestReviews", language))
                        .font(.headline.weight(.black))
                        .padding(.horizontal, 2)
                    LazyVStack(spacing: 10) {
                        ForEach(reviews) { review in
                            KXReviewRow(review: review, showsListingTitle: true)
                        }
                    }
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 14)
            .kxTabBarSafeBottomPadding()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            response = try await KaiXAPIClient.shared.businessPublic(businessId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - 点评行

struct KXReviewRow: View {
    @Environment(\.appLanguage) private var language
    let review: KaiXListingReviewDTO
    var showsListingTitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                ReviewAuthorAvatar(author: review.author, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.author?.display_name ?? "Machi 用户")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        KXRatingStarsView(value: Double(review.rating), showsValue: false, starSize: 10)
                        Text(String((review.created_at ?? "").prefix(10)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if showsListingTitle, let title = review.listing_title, !title.isEmpty {
                Text(title)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(KXColor.accent)
                    .lineLimit(1)
            }
            if let content = review.content, !content.isEmpty {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reply = review.owner_reply, !reply.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L("merchantReply", language), systemImage: "storefront")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(reply)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KXColor.softBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(KXSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kxGlassSurface(radius: KXRadius.lg)
    }
}

private struct ReviewAuthorAvatar: View {
    let author: KaiXUserDTO?
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(KXColor.accent.opacity(0.14))
            Text(String((author?.display_name ?? "M").prefix(1)))
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(KXColor.accent)
            if let url = (author?.avatar_url ?? "").kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: size * 3, failureMode: .transparent)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 详情页点评区

struct ListingReviewsSectionView: View {
    @Environment(\.appLanguage) private var language
    let listing: KaiXCityListingDTO
    let currentUser: UserEntity

    @State private var response: KaiXListingReviewsResponse?
    @State private var writeOpen = false
    @State private var draftRating = 5
    @State private var draftContent = ""
    @State private var isSubmitting = false
    @State private var message: String?

    private static let reviewableTypes: Set<String> = ["local_service", "discount", "event"]

    private var isOwn: Bool {
        let sellerId = listing.seller_user_id ?? listing.sellerUserId ?? ""
        return !sellerId.isEmpty && (sellerId == currentUser.remoteId || sellerId == currentUser.id)
    }

    var body: some View {
        Group {
            if Self.reviewableTypes.contains(listing.type) {
                KXListingSection(title: L("userReviews", language), icon: "star.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryHeader
                        if let items = response?.items, !items.isEmpty {
                            ForEach(items.prefix(10)) { review in
                                KXReviewRow(review: review)
                            }
                        } else if response != nil {
                            Text(L("noReviewPrompt", language))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if let message {
                            Text(message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(KXColor.accent)
                        }
                    }
                }
                .task(id: listing.id) { await load() }
                .sheet(isPresented: $writeOpen) {
                    writeSheet
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            } else {
                EmptyView()
            }
        }
    }

    private var summaryHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            let avg = response?.summary?.rating_avg ?? listing.rating_avg ?? 0
            let count = response?.summary?.rating_count ?? listing.rating_count ?? 0
            if count > 0 {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", avg))
                        .font(.title.weight(.black))
                        .foregroundStyle(.orange)
                    KXRatingStarsView(value: avg, showsValue: false, starSize: 10)
                    Text("\(count) 条点评")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Spacer()
            if !isOwn {
                Button {
                    if let mine = response?.my_review {
                        draftRating = mine.rating
                        draftContent = mine.content ?? ""
                    }
                    writeOpen = true
                } label: {
                    Label(response?.my_review == nil ? "写点评" : "修改点评", systemImage: "square.and.pencil")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(Color.orange, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var writeSheet: some View {
        NavigationStack {
            Form {
                Section("评分") {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                draftRating = star
                            } label: {
                                Image(systemName: "star.fill")
                                    .font(.title2)
                                    .foregroundStyle(star <= draftRating ? Color.orange : Color.secondary.opacity(0.25))
                            }
                            .buttonStyle(.plain)
                        }
                        Text([L("poorRating", language), L("lowRating", language), L("averageRating", language), L("goodRating", language), L("excellentRating", language)][max(0, min(4, draftRating - 1))])
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.orange)
                    }
                }
                Section(L("reviewContent", language)) {
                    TextField(L("reviewPlaceholder", language), text: $draftContent, axis: .vertical)
                        .lineLimit(4...8)
                }
                Section {
                    Button(isSubmitting ? L("publishingReview", language) : L("publishReview", language)) {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle(L("writeReviewTitle", language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel", language)) { writeOpen = false }
                }
            }
        }
    }

    private func load() async {
        response = try? await KaiXAPIClient.shared.listingReviews(listing.id)
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KaiXAPIClient.shared.submitListingReview(
                listing.id,
                rating: draftRating,
                content: draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            writeOpen = false
            message = L("reviewPublishedMessage", language)
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - 工作台 · 点评管理

struct MerchantReviewsManageView: View {
    @Environment(\.appLanguage) private var language
    let currentUser: UserEntity

    @State private var response: KaiXMyBusinessReviewsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var replyTarget: KaiXListingReviewDTO?
    @State private var replyText = ""
    @State private var isReplying = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let summary = response?.summary, (summary.count ?? 0) > 0 {
                    HStack(spacing: 14) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1f", summary.rating_avg ?? 0))
                                .font(.title.weight(.black))
                                .foregroundStyle(.orange)
                            Text(KXListingCopy.pickText(language, "综合评分", "総合評価", "Overall rating"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Divider().frame(height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(KXListingCopy.pickText(language, "\(summary.count ?? 0) 条点评", "\(summary.count ?? 0)件のレビュー", "\(summary.count ?? 0) reviews"))
                                .font(.subheadline.weight(.black))
                            Text(KXListingCopy.pickText(language, "\(summary.unreplied ?? 0) 条待回复 - 认真回复能显著提升转化", "\(summary.unreplied ?? 0)件が未返信 - 丁寧な返信は予約率を高めます", "\(summary.unreplied ?? 0) waiting for reply - thoughtful replies improve conversion"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(KXSpacing.md)
                    .kxGlassSurface(radius: KXRadius.lg, elevated: true)
                }
                if isLoading {
                    KXInlineLoader()
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load() } }
                } else if (response?.items ?? []).isEmpty {
                    EmptyStateView(
                        title: KXListingCopy.pickText(language, "还没有收到点评", "レビューはまだありません", "No reviews yet"),
                        subtitle: KXListingCopy.pickText(language, "服务完成后，引导用户在详情页留下真实体验。", "サービス完了後、詳細ページから体験レビューを書いてもらいましょう。", "After a service is completed, invite customers to leave a real review on the detail page."),
                        systemImage: "star.bubble"
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ForEach(response?.items ?? []) { review in
                        VStack(alignment: .leading, spacing: 8) {
                            KXReviewRow(review: review, showsListingTitle: true)
                            if (review.owner_reply ?? "").isEmpty {
                                Button {
                                    replyTarget = review
                                    replyText = ""
                                } label: {
                                    Label(KXListingCopy.pickText(language, "回复点评", "レビューに返信", "Reply to review"), systemImage: "arrowshape.turn.up.left")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(KXColor.accent)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 4)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 12)
            .kxTabBarSafeBottomPadding()
        }
        .navigationTitle(KXListingCopy.pickText(language, "点评管理", "レビュー管理", "Review management"))
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .task { await load() }
        .refreshable { await load() }
        .alert(KXListingCopy.pickText(language, "回复点评", "レビューに返信", "Reply to review"), isPresented: Binding(get: { replyTarget != nil }, set: { if !$0 { replyTarget = nil } })) {
            TextField(KXListingCopy.pickText(language, "感谢点评 / 说明改进...", "レビューへのお礼 / 改善点...", "Thanks or improvement notes..."), text: $replyText)
            Button(isReplying ? KXListingCopy.pickText(language, "回复中...", "返信中...", "Replying...") : KXListingCopy.pickText(language, "回复", "返信", "Reply")) {
                Task { await submitReply() }
            }
            .disabled(isReplying)
            Button(L("cancel", language), role: .cancel) { replyTarget = nil }
        } message: {
            Text(KXListingCopy.pickText(language, "回复会公开展示在点评下方，用户会收到通知。", "返信はレビューの下に公開表示され、ユーザーに通知されます。", "Your reply appears publicly below the review and notifies the customer."))
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            response = try await KaiXAPIClient.shared.myBusinessReviews()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func submitReply() async {
        guard let target = replyTarget, !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isReplying = true
        defer { isReplying = false }
        _ = try? await KaiXAPIClient.shared.replyListingReview(
            target.listing_id ?? "",
            reviewId: target.id,
            content: replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        replyTarget = nil
        await load()
    }
}
