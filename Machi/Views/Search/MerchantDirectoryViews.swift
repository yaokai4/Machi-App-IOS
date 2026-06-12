import SwiftUI

// 商家与本地服务：星级点评、认证商家目录、
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

    private var ratingAvg: Double { listing.rating_avg ?? listing.ratingAvg ?? 0 }
    private var ratingCount: Int { listing.rating_count ?? listing.ratingCount ?? 0 }
    private var category: String { listing.category ?? "" }

    private var ctaTitle: String {
        if KXListingCopy.isStayCategory(category) { return "查房价" }
        if KXListingCopy.isFoodCategory(category) { return "在线订座" }
        switch category {
        case "景点门票", "一日游": return "订门票"
        default: return "预约"
        }
    }

    private var priceText: String {
        if let range = listing.attributes?["price_range"]?.stringValue, !range.isEmpty { return range }
        return KXListingCopy.priceLabel(listing)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ListingCoverArtwork(listing: listing)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipped()
                    HStack {
                        if !category.isEmpty {
                            Text(KXListingCopy.categoryLabel(category, language))
                                .font(.caption2.weight(.black))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        Spacer()
                        if listing.verification_status == "verified" {
                            Label("认证", systemImage: "checkmark.seal.fill")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.92), in: Capsule())
                        }
                    }
                    .padding(8)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(KXListingCopy.displayTitle(listing))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack {
                        if ratingCount > 0 {
                            KXRatingStarsView(value: ratingAvg, count: ratingCount)
                        } else {
                            Text("暂无点评 · 期待你的体验")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(priceText)
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2.weight(.bold))
                        Text(listing.location_text?.isEmpty == false ? listing.location_text! : (listing.city_slug ?? ""))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(ctaTitle)
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(Color.orange, in: Capsule())
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .background(KXColor.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KXColor.glassStroke.opacity(0.7), lineWidth: 0.8))
            .shadow(color: KXColor.glassShadow.opacity(0.4), radius: 6, y: 2)
        }
        .buttonStyle(KXPressableStyle())
    }
}

/// 封面图：listing media 第一张，缺图时按类型渐变占位。
private struct ListingCoverArtwork: View {
    let listing: KaiXCityListingDTO

    private var coverURLString: String {
        listing.card?.coverUrl
            ?? listing.coverUrl
            ?? listing.cover_url
            ?? listing.media?.first?.thumbnailUrl
            ?? listing.media?.first?.url
            ?? ""
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orange.opacity(0.14), Color.pink.opacity(0.08), KXColor.softBackground],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "storefront")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.55))
            if let url = coverURLString.kaixMediaURL {
                CachedMediaImageView(url: url, targetPixelSize: 720, failureMode: .transparent)
            }
        }
    }
}

// MARK: - 认证商家横滑条（服务频道内）

struct MerchantDirectoryStripView: View {
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
                        Label("认证商家", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            router.open(.businessDirectory(citySlug: citySlug))
                        } label: {
                            HStack(spacing: 3) {
                                Text("全部商家")
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
    let business: KaiXBusinessPublicDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                MerchantLogoView(business: business, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Text(business.business_name ?? "商家")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.green)
                    }
                    Text(business.business_type ?? business.service_categories?.first ?? "本地商家")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack {
                if (business.rating_count ?? 0) > 0 {
                    KXRatingStarsView(value: business.rating_avg ?? 0, count: business.rating_count, starSize: 10)
                } else {
                    Text("暂无点评")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(business.published_listing_count ?? 0) 服务")
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
    @EnvironmentObject private var router: AppRouter
    let citySlug: String
    let currentUser: UserEntity

    @State private var items: [KaiXBusinessPublicDTO] = []
    @State private var category = "全部"
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let categories = ["全部", "餐厅美食", "在线订座", "优惠团购", "民宿", "酒店", "景点门票", "一日游", "接送机", "翻译手续", "搬家清洁", "维修安装", "本地向导"]

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
                            title: "暂无认证商家",
                            subtitle: "商家可以在「工作台 → 商家服务后台」提交认证申请，审核通过后展示在这里。",
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
                .padding(.bottom, 36)
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
                    Text("\(cityName) · 认证商家")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text("资质审核通过的本地商家与服务方")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.green)
                TextField("搜索商家名称、服务类型…", text: $query)
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
                        Text(item)
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
    let business: KaiXBusinessPublicDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MerchantLogoView(business: business, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(business.business_name ?? "商家")
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Color.green)
                    }
                    Text(business.business_type ?? "本地商家")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if (business.rating_count ?? 0) > 0 {
                        KXRatingStarsView(value: business.rating_avg ?? 0, starSize: 11)
                    }
                    Text("\(business.published_listing_count ?? 0) 个在线服务")
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
                    Text(response?.business.business_name ?? "商家主页")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text("认证商家")
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
                    EmptyStateView(title: "商家不存在", subtitle: "它可能未通过认证或已下线。", systemImage: "storefront")
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
                                Text(business.business_name ?? "商家")
                                    .font(.title3.weight(.black))
                                    .lineLimit(1)
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Color.green)
                            }
                            if (business.rating_count ?? 0) > 0 {
                                KXRatingStarsView(value: business.rating_avg ?? 0, count: business.rating_count, starSize: 13)
                            } else {
                                Text("暂无点评")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(business.published_listing_count ?? 0) 个在线服务")
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
                    Text("在线服务 (\(listings.count))")
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
                    Text("最新点评")
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
            .padding(.bottom, 36)
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
                    Label("商家回复", systemImage: "storefront")
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
                KXListingSection(title: "用户点评", icon: "star.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryHeader
                        if let items = response?.items, !items.isEmpty {
                            ForEach(items.prefix(10)) { review in
                                KXReviewRow(review: review)
                            }
                        } else if response != nil {
                            Text("还没有人点评，体验过的话写下第一条点评帮助大家做决定。")
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
                        Text(["很差", "较差", "一般", "不错", "超赞"][max(0, min(4, draftRating - 1))])
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(.orange)
                    }
                }
                Section("点评内容") {
                    TextField("服务体验、环境、价格、是否推荐…", text: $draftContent, axis: .vertical)
                        .lineLimit(4...8)
                }
                Section {
                    Button(isSubmitting ? "发布中…" : "发布点评") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("写点评")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { writeOpen = false }
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
            message = "点评已发布，感谢分享体验！"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - 工作台 · 点评管理

struct MerchantReviewsManageView: View {
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
                            Text("综合评分")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Divider().frame(height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(summary.count ?? 0) 条点评")
                                .font(.subheadline.weight(.black))
                            Text("\(summary.unreplied ?? 0) 条待回复 — 认真回复能显著提升转化")
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
                        title: "还没有收到点评",
                        subtitle: "服务成交后引导用户在详情页留下体验点评。",
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
                                    Label("回复点评", systemImage: "arrowshape.turn.up.left")
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
            .padding(.bottom, 36)
        }
        .navigationTitle("点评管理")
        .navigationBarTitleDisplayMode(.inline)
        .kxPageBackground()
        .task { await load() }
        .refreshable { await load() }
        .alert("回复点评", isPresented: Binding(get: { replyTarget != nil }, set: { if !$0 { replyTarget = nil } })) {
            TextField("感谢点评 / 说明改进…", text: $replyText)
            Button(isReplying ? "回复中…" : "回复") {
                Task { await submitReply() }
            }
            .disabled(isReplying)
            Button("取消", role: .cancel) { replyTarget = nil }
        } message: {
            Text("回复会公开展示在点评下方，用户会收到通知。")
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
