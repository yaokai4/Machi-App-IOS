import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// City listing channel (search/filter/sort list of listings for a region)
// + a user's own listings view, extracted from DiscoverView.swift. Reached
// via KXRoute.cityListings / KXRoute.userListings.

private enum ListingSortMode: String, CaseIterable, Identifiable {
    case newest
    case priceLow
    case priceHigh
    case rating

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .newest: KXListingCopy.pickText(language, "最新", "新着順", "Newest")
        case .priceLow: KXListingCopy.pickText(language, "价格低", "安い順", "Price low")
        case .priceHigh: KXListingCopy.pickText(language, "价格高", "高い順", "Price high")
        case .rating: KXListingCopy.pickText(language, "评分高", "評価順", "Top rated")
        }
    }

    func sortsBefore(_ lhs: KaiXCityListingDTO, _ rhs: KaiXCityListingDTO) -> Bool {
        switch self {
        case .newest:
            return KXListingCopy.sortForDisplay(lhs, rhs)
        case .priceLow:
            return (lhs.price ?? Double.greatestFiniteMagnitude) < (rhs.price ?? Double.greatestFiniteMagnitude)
        case .priceHigh:
            return (lhs.price ?? -Double.greatestFiniteMagnitude) > (rhs.price ?? -Double.greatestFiniteMagnitude)
        case .rating:
            let lhsCount = lhs.rating_count ?? lhs.ratingCount ?? 0
            let rhsCount = rhs.rating_count ?? rhs.ratingCount ?? 0
            // 无评分的沉底；有评分的按分数、再按评价数。
            if (lhsCount > 0) != (rhsCount > 0) { return lhsCount > 0 }
            let lhsAvg = lhs.rating_avg ?? lhs.ratingAvg ?? 0
            let rhsAvg = rhs.rating_avg ?? rhs.ratingAvg ?? 0
            if lhsAvg != rhsAvg { return lhsAvg > rhsAvg }
            return lhsCount > rhsCount
        }
    }
}

private enum ListingScopeMode: String, Identifiable {
    case city
    case country
    case area
    case province
    case selectedCity

    var id: String { rawValue }
}

private struct ListingScopeArea: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let regionCodes: [String]

    func localizedTitle(_ language: AppLanguage) -> String {
        switch id {
        case "kanto": KXListingCopy.pickText(language, "关东圈", "関東圏", "Greater Kanto")
        case "kansai": KXListingCopy.pickText(language, "关西圈", "関西圏", "Greater Kansai")
        case "popular": KXListingCopy.pickText(language, "其他热门", "その他の人気都市", "Other popular")
        default: title
        }
    }

    func localizedSubtitle(_ language: AppLanguage) -> String {
        switch id {
        case "kanto": KXListingCopy.pickText(language, "东京、横滨、川崎、埼玉、千叶", "東京・横浜・川崎・埼玉・千葉", "Tokyo, Yokohama, Kawasaki, Saitama, Chiba")
        case "kansai": KXListingCopy.pickText(language, "大阪、京都、神户、奈良、大津", "大阪・京都・神戸・奈良・大津", "Osaka, Kyoto, Kobe, Nara, Otsu")
        case "popular": KXListingCopy.pickText(language, "名古屋、福冈、仙台", "名古屋・福岡・仙台", "Nagoya, Fukuoka, Sendai")
        default: subtitle
        }
    }
}

private let listingScopeAreas: [ListingScopeArea] = [
    .init(
        id: "kanto",
        title: "关东圈",
        subtitle: "东京、横滨、川崎、埼玉、千叶",
        regionCodes: ["jp.tokyo.tokyo", "jp.kanagawa.yokohama", "jp.kanagawa.kawasaki", "jp.saitama.saitama", "jp.chiba.chiba"]
    ),
    .init(
        id: "kansai",
        title: "关西圈",
        subtitle: "大阪、京都、神户、奈良、大津",
        regionCodes: ["jp.osaka.osaka", "jp.kyoto.kyoto", "jp.hyogo.kobe", "jp.nara.nara", "jp.shiga.otsu"]
    ),
    .init(
        id: "popular",
        title: "其他热门",
        subtitle: "名古屋、福冈、仙台",
        regionCodes: ["jp.aichi.nagoya", "jp.fukuoka.fukuoka", "jp.miyagi.sendai"]
    ),
]

private let listingScopeHotCityCodes = [
    "jp.tokyo.tokyo", "jp.kanagawa.yokohama", "jp.kanagawa.kawasaki", "jp.saitama.saitama", "jp.chiba.chiba",
    "jp.osaka.osaka", "jp.kyoto.kyoto", "jp.hyogo.kobe", "jp.nara.nara", "jp.shiga.otsu",
    "jp.aichi.nagoya", "jp.fukuoka.fukuoka", "jp.miyagi.sendai",
]

struct CityListingChannelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState

    let regionCode: String
    let listingType: String
    let currentUser: UserEntity
    /// Shared with CityListingDetailView (via the router) for the card→detail
    /// zoom transition. nil outside the router path → plain push.
    var zoomNamespace: Namespace.ID? = nil

    @State private var items: [KaiXCityListingDTO] = []
    /// Signature of the last successfully loaded (region, type, tab). `.task(id:)`
    /// re-fires on every pop-back from a detail even though the id is unchanged —
    /// this lets that re-fire become a no-op so the list, scroll position and
    /// keyset pagination survive returning, instead of flashing a skeleton.
    @State private var loadedSignature = ""
    @State private var query = ""
    @State private var selectedCategory = "全部"
    @State private var serviceSection = "all"
    @State private var sortMode: ListingSortMode = .newest
    @State private var filtersOpen = false
    /// 默认「全国」不做地域预筛——进频道先看到全部内容(尤其合作商同步的房源),
    /// 再由用户主动收窄到都市圈/都道府县/本市。曾经一进来自动扩到关东圈(且只认
    /// 5 个城市 region_code),导致大量内容被静默隐藏。
    @State private var scopeMode: ListingScopeMode = .country
    @State private var selectedScopeArea = ""
    @State private var selectedScopeRegionCode = ""
    /// 选中的都道府县(省/州)code,scopeMode == .province 时生效。
    @State private var selectedProvinceCode = ""
    @State private var minimumPrice = ""
    @State private var maximumPrice = ""
    /// 属性级筛选（key → 值，布尔用 "true"，人数下限用 gte_ 前缀），
    /// 与 Web 同一套 attr_<key> 协议，全部交给服务端过滤。
    @State private var attrFilters: [String: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// True once the listings scroll past the top — condenses the pinned
    /// header (drops the rental tabs + result summary, keeps search + rail).
    @State private var headerCollapsed = false
    /// Local 收藏 sheet.
    @State private var wishlistOpen = false
    /// Map vs list presentation of the current results.
    @State private var mapMode = false
    // Server-side keyset pagination ("work" merges two listing types, so it
    // carries one cursor per stream). nil = that stream is exhausted.
    @State private var nextCursor: String?
    @State private var nextHiringCursor: String?
    @State private var isLoadingMore = false
    /// True while a `quiet` reload (filter/sort change) is in flight — drives a
    /// small "updating…" indicator so a silent reload never reads as "frozen".
    @State private var isReloading = false
    /// data.filters.fallback_label from the last load: the server found the
    /// requested area empty and widened the scope (metro_circle / country) —
    /// surfaces a "该地区暂无,已为你展示{label}的内容" notice so the widened
    /// results aren't silently confusing. nil = no fallback happened.
    @State private var fallbackNoticeLabel: String?
    /// 「保存此搜索」按钮态,与 SearchView.subscribeSearchButton 同一套
    /// saving/done 模式;筛选条件一变 done 复位,可再次订阅新条件。
    @State private var savedSearchSaving = false
    @State private var savedSearchDone = false
    /// Bumped on every load. A request that finishes after a newer one started
    /// (rapid filter/sort tapping on a slow network) discards its result instead
    /// of clobbering the newer list — "last issued wins", not "last returned".
    @State private var loadGeneration = 0
    /// Debounce for the price fields: each keystroke fires `onChange`, but only
    /// the value that survives ~400ms of silence actually hits the server.
    @State private var priceDebounceTask: Task<Void, Never>?

    private var hasMoreListings: Bool {
        nextCursor != nil || nextHiringCursor != nil
    }

    /// Shared login-prompt copy for the publish entry points ("+", empty-state CTA).
    private var publishLoginReason: String {
        KXListingCopy.pickText(language, "登录后可以发布信息。", "ログインすると投稿できます。", "Sign in to publish a listing.")
    }

    private var marketplaceGridSpacing: CGFloat { 12 }

    private var marketplaceCardWidth: CGFloat {
        let contentWidth = screenWidth - (KaiXTheme.horizontalPadding * 2)
        return max(142, floor((contentWidth - marketplaceGridSpacing) / 2))
    }

    /// Cached once in `.onAppear` (see `currentScreenWidth`). Was a computed
    /// property that walked `UIApplication.connectedScenes` on EVERY access —
    /// i.e. once per card width during layout and scroll. Reading a stored
    /// value is free; the screen width doesn't change mid-scroll anyway.
    // Seed from the real screen width at init (not a hardcoded 393) so the
    // two-column grid lays out correctly on the FIRST frame — no SE/iPad/Split
    // View width jump after onAppear.
    @State private var screenWidth: CGFloat = CityListingChannelView.resolveScreenWidth()

    private static func resolveScreenWidth() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState != .unattached }?
            .screen.bounds.width ?? 393
    }

    private var secondhandRows: [[KaiXCityListingDTO]] {
        stride(from: 0, to: visibleItems.count, by: 2).map { start in
            Array(visibleItems[start..<min(start + 2, visibleItems.count)])
        }
    }

    private var region: KaiXRegionDirectory.Region? {
        KaiXRegionDirectory.resolve(regionCode: regionCode)
    }

    /// 服务频道分区与发布页第一阶段正式类目保持一致。
    /// 住宿类目已整体搬去租房页「民宿」，这里不再展示。
    static let serviceSections: [(key: String, title: String, categories: [String])] = [
        ("all", "全部", []),
        ("food", "餐厅", KXListingCopy.foodSectionCategories),
        ("travel", "旅行票务", KXListingCopy.travelSectionCategories),
        ("transfer", "接送交通", KXListingCopy.transferSectionCategories),
        ("paperwork", "翻译手续", KXListingCopy.paperworkSectionCategories),
        ("moving", "搬家清洁", KXListingCopy.movingSectionCategories),
        ("life", "生活开通", KXListingCopy.lifeSetupSectionCategories),
        ("beauty", "美容健康", KXListingCopy.beautyHealthSectionCategories),
    ]

    /// 「stays / hotels」是住房频道伪类型；旧 hotels 深链统一归并到民宿。
    /// 工作频道兼容 work/job/hiring 三种入口，避免外部深链只展示半条招聘流。
    private var baseType: String {
        let raw = listingType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "stays", "hotels":
            return "rental"
        case "work", "job", "jobs", "hiring":
            return "work"
        case "service", "services", "local_services":
            return "local_service"
        default:
            return raw
        }
    }
    private var isWorkChannel: Bool { baseType == "work" }

    private var staysActive: Bool { baseType == "rental" && activeRentalTab == .stays }
    private var lodgingActive: Bool { staysActive }
    /// 买房分区：房源频道内的独立垂类（与长租/民宿并列）。
    private var forsaleActive: Bool { baseType == "rental" && activeRentalTab == .forsale }

    /// 真正发给 API 的 listing type。买房走 for_sale，民宿走 local_service。
    private var queryType: String {
        forsaleActive ? "for_sale" : (lodgingActive ? "local_service" : baseType)
    }

    /// 文案/类目/空状态用的有效类型（买房=for_sale，民宿=stays，其余=baseType）。
    private var copyType: String {
        forsaleActive ? "for_sale" : (staysActive ? "stays" : baseType)
    }

    enum RentalTab: String { case homes, forsale, stays }
    @State private var rentalTab: RentalTab?

    private var activeRentalTab: RentalTab {
        rentalTab ?? (listingType == "hotels" || listingType == "stays" ? .stays : .homes)
    }

    /// Materialised filtered+sorted list. Recomputed only when data or filters
    /// change (`recomputeVisibleItems`) — not on every `body` evaluation, the way
    /// a computed property was. A filter change updates it immediately for
    /// instant client-side feedback, before the server reload returns.
    @State private var visibleItems: [KaiXCityListingDTO] = []

    /// Signature of every input that affects `visibleItems`; a change drives an
    /// immediate local recompute via `.onChange` in `body`.
    private var visibleFilterSignature: String {
        "\(serviceSection)|\(selectedCategory)|\(query)|\(minimumPrice)|\(maximumPrice)|\(sortMode)|\(staysActive)|\(forsaleActive)|\(baseType)"
    }

    private func recomputeVisibleItems() {
        let sectionCategories = Self.serviceSections.first { $0.key == serviceSection }?.categories ?? []
        let filtered = items.filter { item in
            // 买房分区只展示 for_sale；长租/民宿分区排除 for_sale。
            if forsaleActive {
                guard item.type == "for_sale" else { return false }
            } else if item.type == "for_sale" {
                return false
            } else if staysActive {
                // 住宿新入口只展示民宿；服务频道隐藏全部住宿历史类目。
                guard KXListingCopy.isHomestayCategory(item.category) else { return false }
            } else if baseType == "local_service", KXListingCopy.isStayCategory(item.category) {
                return false
            }
            let categoryOK = selectedCategory == "全部" || (item.category ?? "").localizedCaseInsensitiveContains(selectedCategory)
            // 分区只在「全部」类目下生效，选中具体类目时以类目为准
            let sectionOK = baseType != "local_service"
                || selectedCategory != "全部"
                || sectionCategories.isEmpty
                || sectionCategories.contains(item.category ?? "")
            let queryOK = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || item.title.localizedCaseInsensitiveContains(query)
                || (item.description ?? "").localizedCaseInsensitiveContains(query)
                || (item.location_text ?? "").localizedCaseInsensitiveContains(query)
            let priceOK = (Double(minimumPrice).map { (item.price ?? 0) >= $0 } ?? true)
                && (Double(maximumPrice).map { (item.price ?? .greatestFiniteMagnitude) <= $0 } ?? true)
            // 属性筛选由服务端完成（attrFilters → attr_<key>），客户端不再
            // 重复判断——gte 这类语义客户端复刻不了，重复判断只会误隐藏。
            return categoryOK && sectionOK && queryOK && priceOK
        }
        visibleItems = filtered.sorted(by: sortMode.sortsBefore)
    }

    private var selectedArea: ListingScopeArea? {
        listingScopeAreas.first { $0.id == selectedScopeArea }
    }

    private var selectedScopeRegion: KaiXRegionDirectory.Region? {
        KaiXRegionDirectory.resolve(regionCode: selectedScopeRegionCode)
    }

    private var activeScopeLabel: String {
        switch scopeMode {
        case .city:
            return region.map { KaiXRegionDirectory.localizedShortLabel($0, language: language) } ?? L("currentRegion", language)
        case .country:
            // 默认范围:直呼「全国」,比国家名(日本)更贴合「看全部」的语义。
            return KXListingCopy.pickText(language, "全国", "全国", "Nationwide")
        case .area:
            return selectedArea?.localizedTitle(language) ?? KXListingCopy.pickText(language, "城市圈", "都市圏", "Metro area")
        case .province:
            return selectedProvinceLabel
        case .selectedCity:
            return selectedScopeRegion.map { KaiXRegionDirectory.localizedShortLabel($0, language: language) } ?? ListingFilterLocalizer.text("热门城市", language)
        }
    }

    /// 选中都道府县的本地化名(找不到时回退到通用「都道府县」)。
    private var selectedProvinceLabel: String {
        let country = region?.countryCode ?? "jp"
        guard let province = KaiXRegionDirectory.provinces(for: country).first(where: { $0.code == selectedProvinceCode }) else {
            return KXListingCopy.pickText(language, "都道府县", "都道府県", "Prefecture")
        }
        return KaiXRegionDirectory.localizedProvinceName(countryCode: country, province: province, language: language)
    }

    private var activeFilterCount: Int {
        var count = 0
        if selectedCategory != "全部" { count += 1 }
        // 默认范围是「全国」;任何收窄(本市/都市圈/都道府县/热门城市)才算用户筛选。
        if scopeMode != .country { count += 1 }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !minimumPrice.isEmpty { count += 1 }
        if !maximumPrice.isEmpty { count += 1 }
        count += attrFilters.values.filter { !$0.isEmpty }.count
        return count
    }

    private var serverSort: String {
        switch sortMode {
        case .newest: "latest"
        case .priceLow: "price_asc"
        case .priceHigh: "price_desc"
        case .rating: "rating"
        }
    }

    /// 评分排序只对有点评体系的内容开放（服务频道与住宿分区）。
    private var availableSortModes: [ListingSortMode] {
        baseType == "local_service" || lodgingActive
            ? ListingSortMode.allCases
            : ListingSortMode.allCases.filter { $0 != .rating }
    }

    /// 选择/开关筛选即静默重载——保留旧列表避免闪白，结果回来再替换。
    private func attrChoiceBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { attrFilters[key] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    attrFilters.removeValue(forKey: key)
                } else {
                    attrFilters[key] = newValue
                }
                Task { await load(quiet: true) }
            }
        )
    }

    private func attrToggleBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { attrFilters[key] == "true" },
            set: { isOn in
                if isOn {
                    attrFilters[key] = "true"
                } else {
                    attrFilters.removeValue(forKey: key)
                }
                Task { await load(quiet: true) }
            }
        )
    }

    private var lodgingCategories: [String] {
        if staysActive { return KXListingCopy.homestayCategories }
        return []
    }

    private var serverLodgingCategory: String? {
        lodgingActive && selectedCategory != "全部" ? selectedCategory : nil
    }

    private var serverCategory: String? {
        if lodgingActive { return serverLodgingCategory }
        if baseType == "local_service", selectedCategory != "全部" { return selectedCategory }
        return nil
    }

    private var serverCategories: [String] {
        if lodgingActive {
            return serverLodgingCategory == nil ? lodgingCategories : []
        }
        if baseType == "local_service", selectedCategory == "全部" {
            return Self.serviceSections.first { $0.key == serviceSection }?.categories ?? []
        }
        return []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // Pinned search-first chrome: search pill + icon rail stay reachable
            // while listings scroll under; secondary rows condense on scroll.
            listingControls
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 10)
            if mapMode {
                ListingMapView(listings: visibleItems) { id in
                    router.open(.cityListingDetail(listingId: id))
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let fallbackNoticeLabel, !visibleItems.isEmpty {
                            fallbackNotice(fallbackNoticeLabel)
                        }
                        if baseType == "local_service" {
                            MerchantDirectoryStripView(citySlug: regionCode)
                        }
                        stateContent
                        if !isLoading, errorMessage == nil, hasMoreListings {
                            // Sentinel row: scrolling it into view pulls the next
                            // server page. Re-armed whenever items grow OR a cursor
                            // advances — dedup can leave count unchanged while a
                            // fresh page cursor still needs to be consumed.
                            KXInlineLoader()
                                .task(id: "\(items.count)|\(nextCursor ?? "")|\(nextHiringCursor ?? "")") { await loadMore() }
                        } else if !isLoading, errorMessage == nil, !visibleItems.isEmpty {
                            // Clear end-of-list boundary instead of just stopping.
                            Text(KXListingCopy.pickText(language, "已显示全部", "すべて表示しました", "You've reached the end"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }
                    }
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
                    .padding(.top, 6)
                    .padding(.bottom, chrome.bottomContentPadding + 28)
                    .kxReadableWidth(820)
                }
                .refreshable { await load() }
                .kxScrollCollapse($headerCollapsed)
                .overlay(alignment: .top) {
                    if isReloading {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text(KXListingCopy.pickText(language, "更新中", "更新中", "Updating"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(KXColor.cardBackground.opacity(0.96), in: Capsule())
                        .overlay(Capsule().stroke(KXColor.glassStroke.opacity(0.6), lineWidth: 0.7))
                        .shadow(color: KXColor.glassShadow.opacity(0.3), radius: 8, y: 3)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(KXMotion.reveal, value: isReloading)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLoading, errorMessage == nil, !visibleItems.isEmpty {
                mapToggle
                    .padding(.bottom, 24)
            }
        }
        .kxPageBackground()
        // Deliberately NOT a zoom destination: this screen hosts the per-card
        // zoom sources into the listing detail, and being a zoom destination at
        // the same time (nested matchedTransitionSource) makes iOS 18/26 render
        // the whole list blank after popping back from the detail.
        .sheet(isPresented: $filtersOpen) { filterSheet }
        .sheet(isPresented: $wishlistOpen) {
            WishlistView { id in openFromWishlist(id) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(regionCode)-\(listingType)-\(activeRentalTab.rawValue)") {
            let signature = "\(regionCode)-\(listingType)-\(activeRentalTab.rawValue)"
            // Unchanged id + data already on screen = a pop-back re-fire, not a
            // real context switch — keep the list instead of reloading it.
            guard signature != loadedSignature || items.isEmpty else { return }
            await load()
            if errorMessage == nil { loadedSignature = signature }
        }
        .onChange(of: minimumPrice) { _, _ in schedulePriceReload() }
        .onChange(of: maximumPrice) { _, _ in schedulePriceReload() }
        // Instant client-side re-filter the moment any filter changes — the
        // server reload that follows refreshes it again with fresh data. A
        // changed filter is a new search, so the saved-search done state resets.
        .onChange(of: visibleFilterSignature) { _, _ in
            recomputeVisibleItems()
            savedSearchDone = false
        }
        .onAppear { screenWidth = Self.resolveScreenWidth() }
    }

    /// 服务端空结果回退提示：请求范围没有内容,已自动展示更大范围
    /// (data.filters.fallback / fallback_label 契约)。纯信息行,不可点。
    private func fallbackNotice(_ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(KXColor.livingAccent)
            Text(KXListingCopy.pickText(language,
                                        "该地区暂无相关内容,已为你展示\(label)的内容",
                                        "この地域にはまだ投稿がないため、\(label)の内容を表示しています",
                                        "Nothing here yet — showing listings from \(label) instead"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(KXColor.livingAccentSoft, in: RoundedRectangle(cornerRadius: KXRadius.md, style: .continuous))
        .transition(.opacity)
    }

    private var header: some View {
        HStack(spacing: KXSpacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KXListingCopy.pickText(language, "返回", "戻る", "Back"))

            VStack(alignment: .leading, spacing: 2) {
                Text("\(region.map { KaiXRegionDirectory.localizedShortLabel($0, language: language) } ?? L("currentRegion", language)) · \(KXListingCopy.title(for: baseType, language))")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(KXListingCopy.subtitle(for: baseType, language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { wishlistOpen = true } label: {
                Image(systemName: "heart")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KXListingCopy.pickText(language, "我的收藏", "お気に入り", "Saved"))
            Button {
                guard GuestSession.requireSignedIn(currentUser, reason: publishLoginReason) else { return }
                router.open(.createCityListing(type: KXListingCopy.createType(for: lodgingActive ? "local_service" : baseType), citySlug: regionCode))
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(KXColor.livingAccent, in: Circle())
                    .shadow(color: KXColor.livingAccent.opacity(0.18), radius: 9, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("compose", language))
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    /// Dismiss the wishlist sheet, then push the chosen listing's detail on the
    /// host stack (same deferred pattern as the inquiry receipt sheet).
    private func openFromWishlist(_ id: String) {
        wishlistOpen = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            router.open(.cityListingDetail(listingId: id))
        }
    }

    /// Floating list ⇄ map switch (Airbnb-style), centred above the safe area.
    private var mapToggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { mapMode.toggle() }
        } label: {
            Label(
                mapMode ? KXListingCopy.pickText(language, "列表", "リスト", "List") : KXListingCopy.pickText(language, "地图", "地図", "Map"),
                systemImage: mapMode ? "list.bullet" : "map.fill"
            )
            .font(.subheadline.weight(.black))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 46)
            .background(KXColor.livingInk, in: Capsule())
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(KXPressableStyle(scale: 0.95))
    }

    /// 住房频道三标签：长租 / 买房 / 民宿。
    private var rentalTabSwitcher: some View {
        HStack(spacing: 4) {
            rentalTabButton(.homes, title: KXListingCopy.pickText(language, "长租", "長期賃貸", "Rentals"), icon: "house")
            rentalTabButton(.forsale, title: KXListingCopy.pickText(language, "买房", "物件購入", "Buy"), icon: "building.2")
            rentalTabButton(.stays, title: KXListingCopy.pickText(language, "民宿", "民泊", "Homestays"), icon: "bed.double")
        }
        .padding(4)
        .background(KXColor.softBackground.opacity(0.82), in: Capsule())
        .overlay(Capsule().stroke(KXColor.separator.opacity(0.6), lineWidth: 0.7))
        .frame(maxWidth: .infinity)
    }

    private func rentalTabButton(_ tab: RentalTab, title: String, icon: String) -> some View {
        Button {
            guard activeRentalTab != tab else { return }
            rentalTab = tab
            selectedCategory = "全部"
            // 三个分区的筛选维度不同（长租=户型/家具，住宿=人数/早餐），
            // 残留上一分区的条件会变成隐形过滤；评分排序仅住宿分区可用。
            attrFilters = [:]
            // 价格量纲也不同（长租=月租、买房=总价、民宿=每晚）——残留旧区间
            // 会把新分区隐形过滤成空列表。onChange 仅在值真变时触发。
            minimumPrice = ""
            maximumPrice = ""
            if sortMode == .rating, tab == .homes { sortMode = .newest }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.black))
                .foregroundStyle(activeRentalTab == tab ? Color.white : KXColor.livingInk)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .frame(maxWidth: .infinity)
                .background(activeRentalTab == tab ? KXColor.livingAccent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var listingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if baseType == "rental", !headerCollapsed {
                rentalTabSwitcher
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            heroSearchBar
            categoryIconRail
            serviceSubCategoryRail
            if !headerCollapsed {
                resultSummaryRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Web-parity second-level menu for 商家与服务: once a primary section
    /// (餐厅 / 旅行票务 …) is chosen, its sub-categories appear as a chip row so
    /// users can drill in (e.g. 餐厅 → 中餐 / 日料 / 火锅). Driven by the existing
    /// serviceSections taxonomy + selectedCategory state.
    @ViewBuilder private var serviceSubCategoryRail: some View {
        if baseType == "local_service", serviceSection != "all" {
            let subs = Self.serviceSections.first { $0.key == serviceSection }?.categories ?? []
            if !subs.isEmpty {
                KXFadingHScroll {
                    HStack(spacing: 8) {
                        serviceSubChip(ListingFilterLocalizer.text("全部", language), value: "全部")
                        ForEach(subs, id: \.self) { cat in
                            serviceSubChip(ListingFilterLocalizer.text(cat, language), value: cat)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func serviceSubChip(_ title: String, value: String) -> some View {
        let selected = selectedCategory == value
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                selectedCategory = value
                Task { await load(quiet: true) }
            }
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? Color.white : KXColor.livingInk)
                .padding(.horizontal, 13)
                .frame(height: 32)
                .background(selected ? KXColor.livingAccent : KXColor.softBackground.opacity(0.88), in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : KXColor.separator.opacity(0.6), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    /// 爱彼迎式搜索条：左端城市/范围菜单 + 内联搜索框，合成一颗悬浮胶囊。
    private var heroSearchBar: some View {
        HStack(spacing: 0) {
            scopeMenu
            Rectangle()
                .fill(KXColor.livingInk.opacity(0.10))
                .frame(width: 1, height: 26)
                .padding(.horizontal, 10)
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(KXColor.livingAccent)
            TextField(KXListingCopy.searchPlaceholder(for: copyType, language), text: $query)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 8)
                .onSubmit { Task { await load(quiet: true) } }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    query = ""
                    Task { await load(quiet: true) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("clear", language))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(height: 56)
        .background(KXColor.livingSurface, in: Capsule())
        .overlay(Capsule().stroke(KXColor.livingInk.opacity(0.09), lineWidth: 0.8))
        .shadow(color: KXColor.glassShadow.opacity(0.6), radius: 12, y: 5)
    }

    /// 范围菜单：城市 / 全国 / 都市圈，收进搜索胶囊左端（热门城市仍在筛选面板）。
    private var scopeMenu: some View {
        Menu {
            Button {
                selectScope(.city)
            } label: {
                Label(region.map { KaiXRegionDirectory.localizedShortLabel($0, language: language) } ?? KXListingCopy.pickText(language, "本市", "現在の都市", "This city"), systemImage: scopeMode == .city ? "checkmark" : "building.2")
            }
            Button {
                selectScope(.country)
            } label: {
                Label(KXListingCopy.pickText(language, "全国", "全国", "Nationwide"), systemImage: scopeMode == .country ? "checkmark" : "globe.asia.australia")
            }
            Section(KXListingCopy.pickText(language, "都市圈", "都市圏", "Metro areas")) {
                ForEach(listingScopeAreas) { area in
                    Button {
                        selectScope(.area, area: area.id)
                    } label: {
                        Label(area.localizedTitle(language), systemImage: scopeMode == .area && selectedScopeArea == area.id ? "checkmark" : "map")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(KXColor.livingAccent)
                Text(activeScopeLabel)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(KXColor.livingInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: 150)
            .frame(height: 40)
            .background(KXColor.livingSoft.opacity(0.9), in: Capsule())
        }
    }

    private func selectScope(_ mode: ListingScopeMode, area: String = "", cityCode: String = "", provinceCode: String = "") {
        scopeMode = mode
        selectedScopeArea = area
        selectedScopeRegionCode = cityCode
        selectedProvinceCode = provinceCode
        // 换范围 = 新搜索:旧的回退提示与「已订阅」态都不再成立。
        fallbackNoticeLabel = nil
        savedSearchDone = false
        Task { await load() }
    }

    /// 爱彼迎标志性的图标类目滑栏 + 末端固定的排序 / 筛选按钮。
    private var categoryIconRail: some View {
        HStack(spacing: 8) {
            KXFadingHScroll {
                HStack(spacing: 2) {
                    if baseType == "local_service" {
                        ForEach(Self.serviceSections, id: \.key) { section in
                            categoryIconItem(
                                title: ListingFilterLocalizer.text(section.title, language),
                                icon: KXListingCopy.serviceSectionIcon(section.key),
                                selected: serviceSection == section.key && selectedCategory == "全部"
                            ) {
                                serviceSection = section.key
                                selectedCategory = "全部"
                                Task { await load(quiet: true) }
                            }
                        }
                    } else {
                        ForEach(visibleCategoryChips, id: \.self) { category in
                            categoryIconItem(
                                title: KXListingCopy.categoryLabel(category, language),
                                icon: KXListingCopy.categoryIcon(category),
                                selected: selectedCategory == category
                            ) {
                                selectedCategory = category
                                Task { await load(quiet: true) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            sortButton
            filtersButton
        }
    }

    private func categoryIconItem(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 22)
                Text(title)
                    .font(.caption2.weight(selected ? .heavy : .semibold))
                    .lineLimit(1)
                    .fixedSize()
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(selected ? KXColor.livingInk : Color.clear)
                    .frame(width: 18, height: 2.5)
            }
            .foregroundStyle(selected ? KXColor.livingInk : KXColor.livingMuted)
            .padding(.horizontal, 9)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sortButton: some View {
        Menu {
            ForEach(availableSortModes) { mode in
                Button {
                    sortMode = mode
                    Task { await load(quiet: true) }
                } label: {
                    if sortMode == mode {
                        Label(mode.title(language), systemImage: "checkmark")
                    } else {
                        Text(mode.title(language))
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(KXColor.livingInk)
                .frame(width: 44, height: 44)
                .background(KXColor.livingSoft.opacity(0.9), in: Circle())
                .overlay(Circle().stroke(KXColor.livingInk.opacity(0.08), lineWidth: 0.8))
        }
        .accessibilityLabel(KXListingCopy.pickText(language, "排序", "並び替え", "Sort"))
    }

    private var filtersButton: some View {
        Button {
            filtersOpen = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(sheetFilterCount > 0 ? Color.white : KXColor.livingInk)
                    .frame(width: 44, height: 44)
                    .background(sheetFilterCount > 0 ? KXColor.livingAccent : KXColor.livingSoft.opacity(0.9), in: Circle())
                    .overlay(Circle().stroke(sheetFilterCount > 0 ? Color.clear : KXColor.livingInk.opacity(0.08), lineWidth: 0.8))
                if sheetFilterCount > 0 {
                    Text("\(sheetFilterCount)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(KXColor.livingAccent)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().stroke(KXColor.livingAccent, lineWidth: 1.2))
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KXListingCopy.pickText(language, "筛选", "絞り込み", "Filters"))
    }

    /// 轻量结果摘要行：结果数 + 当前范围/类目 + 清空。
    private var resultSummaryRow: some View {
        HStack(spacing: 6) {
            Text(resultCountText(visibleItems.count))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
            Text("\(activeScopeLabel) · \(ListingFilterLocalizer.text(selectedCategory, language))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            saveSearchButton
            if activeFilterCount > 0 {
                Button {
                    clearAllFilters()
                } label: {
                    Label(KXListingCopy.pickText(language, "清空筛选", "絞り込みをクリア", "Clear filters"), systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KXColor.livingAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    /// 「保存此搜索」——把当前频道条件订阅成 saved search(新匹配上架时通知),
    /// 与 SearchView.subscribeSearchButton 同一套 saving/done 状态模式。
    private var saveSearchButton: some View {
        Button {
            guard !savedSearchSaving, !savedSearchDone else { return }
            guard GuestSession.requireSignedIn(currentUser, reason: KXListingCopy.pickText(language, "登录后可以订阅搜索。", "ログインすると検索を保存できます。", "Sign in to save this search.")) else { return }
            savedSearchSaving = true
            Task {
                defer { savedSearchSaving = false }
                do {
                    // 用订阅专用的 scope 映射(savedSearchScope),不能复用列表
                    // 查询的 listingScopeQuery——后者在都市圈/都道府县/全国档把
                    // 位置放进 provinceCodes/countryCode,直接塞给 createSavedSearch
                    // 会落库一条位置全空、匹配全世界的订阅。
                    let scope = region.map { savedSearchScope(for: $0) }
                    let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = try await KaiXAPIClient.shared.createSavedSearch(
                        // 服务端 vertical 只认真实 listing type:买房/民宿分区走
                        // queryType(for_sale/local_service);工作频道订阅招聘流。
                        vertical: isWorkChannel ? "hiring" : queryType,
                        keyword: keyword.isEmpty ? nil : keyword,
                        category: selectedCategory == "全部" ? nil : selectedCategory,
                        citySlug: scope?.citySlug,
                        regionCode: scope?.regionCode,
                        countryCode: scope?.countryCode
                    )
                    savedSearchDone = true
                } catch {
                    savedSearchDone = false
                }
            }
        } label: {
            Label(
                savedSearchDone ? KXListingCopy.pickText(language, "已订阅", "保存済み", "Saved") : KXListingCopy.pickText(language, "保存此搜索", "この検索を保存", "Save search"),
                systemImage: savedSearchDone ? "bell.fill" : "bell.badge"
            )
            .font(.caption.weight(.bold))
            .foregroundStyle(KXColor.livingAccent)
        }
        .buttonStyle(.plain)
        .disabled(savedSearchSaving || savedSearchDone)
        .accessibilityIdentifier("channel.saveSearch")
    }

    private func clearAllFilters() {
        query = ""
        selectedCategory = "全部"
        scopeMode = .country
        selectedScopeArea = ""
        selectedScopeRegionCode = ""
        selectedProvinceCode = ""
        minimumPrice = ""
        maximumPrice = ""
        attrFilters = [:]
        Task { await load() }
    }

    /// 筛选面板内的条件计数（类目在滑栏、城市/全国在菜单，不计入角标）。
    private var sheetFilterCount: Int {
        var count = 0
        if !minimumPrice.isEmpty { count += 1 }
        if !maximumPrice.isEmpty { count += 1 }
        if scopeMode == .area || scopeMode == .province || scopeMode == .selectedCity { count += 1 }
        if baseType == "local_service", selectedCategory != "全部" { count += 1 }
        count += attrFilters.values.filter { !$0.isEmpty }.count
        return count
    }

    private var visibleCategoryChips: [String] {
        if baseType == "local_service" {
            let quick: [String]
            switch serviceSection {
            case "food":
                quick = ["全部", "中华料理", "日本料理", "居酒屋", "烧肉火锅", "咖啡甜品"]
            case "travel":
                quick = ["全部", "景点门票", "一日游", "本地向导", "体验活动", "包车行程"]
            case "transfer":
                quick = ["全部", "机场接送", "车站接送", "包车", "行李协助"]
            case "paperwork":
                quick = ["全部", "材料翻译", "市役所陪同", "银行卡协助", "手机卡协助", "租房申请协助"]
            case "moving":
                quick = ["全部", "搬家", "退房清洁", "粗大垃圾协助", "行李搬运", "家具家电配送协助"]
            case "life":
                quick = ["全部", "手机卡开通", "网络开通", "水电煤协助", "地址登记协助", "粗大垃圾预约"]
            case "beauty":
                quick = ["全部", "美容美发", "美甲", "按摩", "皮肤管理", "体检/牙科预约协助"]
            default:
                quick = ["全部", "中华料理", "日本料理", "景点门票", "机场接送", "材料翻译", "搬家", "美容美发"]
            }
            return selectedCategory == "全部" || quick.contains(selectedCategory) ? quick : quick + [selectedCategory]
        }
        return KXListingCopy.categories(for: copyType)
    }

    /// 全部细筛收进底部弹出面板，带「查看 N 个结果」固定底栏（爱彼迎式）。
    private var filterSheet: some View {
        NavigationStack {
            ScrollView {
                scopeFilterPanel
                    .padding(.horizontal, KaiXTheme.horizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
            }
            .background(KXColor.pageBackground.ignoresSafeArea())
            .navigationTitle(KXListingCopy.pickText(language, "筛选", "絞り込み", "Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if activeFilterCount > 0 {
                        Button(KXListingCopy.pickText(language, "清空", "クリア", "Clear")) {
                            clearAllFilters()
                        }
                        .foregroundStyle(KXColor.livingAccent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        filtersOpen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(L("close", language))
                }
            }
            .safeAreaInset(edge: .bottom) {
                filterSheetBottomBar
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var filterSheetBottomBar: some View {
        Button {
            filtersOpen = false
        } label: {
            Text(KXListingCopy.pickText(language, "查看 \(visibleItems.count) 个结果", "\(visibleItems.count) 件を見る", "Show \(visibleItems.count) results"))
                .kxGlassButton(prominent: true)
        }
        .buttonStyle(KXPressableStyle(scale: 0.97))
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.4) }
    }

    private var scopeFilterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ListingFilterLocalizer.text(baseType == "rental" ? (lodgingActive ? "每晚价格" : "月租范围") : isWorkChannel ? "薪资范围" : "价格范围", language))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    filterPriceField(title: ListingFilterLocalizer.text("最低", language), text: $minimumPrice)
                    Text("—")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    filterPriceField(title: ListingFilterLocalizer.text("最高", language), text: $maximumPrice)
                }
            }

            if baseType == "secondhand" {
                filterChoiceSection(
                    title: "发布类型",
                    options: [("", "全部"), ("sale", "出售"), ("free", "免费送"), ("wanted", "求购")],
                    selection: attrChoiceBinding("listing_mode")
                )
                filterChoiceSection(
                    title: "新旧程度",
                    options: [("", "不限"), ("brand_new", "全新"), ("like_new", "几乎全新"), ("good", "良好"), ("used", "有使用痕迹"), ("fair", "可用")],
                    selection: attrChoiceBinding("condition")
                )
                filterChoiceSection(
                    title: "交易方式",
                    options: [("", "不限"), ("meetup", "面交"), ("pickup", "自取"), ("shipping", "邮寄"), ("negotiable", "可商量")],
                    selection: attrChoiceBinding("delivery_method")
                )
                filterToggleSection(title: "交易偏好", toggles: [
                    ("price_negotiable", "价格可议"),
                    ("pickup_available", "可自取"),
                    ("shipping_available", "可邮寄"),
                ])
            } else if lodgingActive {
                filterChoiceSection(
                    title: "可住人数",
                    options: [("", "不限"), ("2", "2 人及以上"), ("3", "3 人及以上"), ("4", "4 人及以上"), ("6", "6 人及以上")],
                    selection: attrChoiceBinding("gte_max_guests")
                )
                filterToggleSection(title: "住宿条件", toggles: [
                    ("breakfast_included", "含早餐"),
                    ("instant_confirmation", "即时确认"),
                    ("certified_provider", "认证商家"),
                ])
            } else if baseType == "rental" {
                filterChoiceSection(
                    title: "户型",
                    options: [("", "不限"), ("1R", "1R"), ("1K", "1K"), ("1DK", "1DK"), ("1LDK", "1LDK"), ("2K", "2K"), ("2LDK", "2LDK"), ("合租", "合租")],
                    selection: attrChoiceBinding("layout")
                )
                filterToggleSection(title: "条件", toggles: [
                    ("furnished", "家具家电"),
                    ("pet_allowed", "可宠物"),
                    ("share_allowed", "可合租"),
                ])
            } else if isWorkChannel {
                filterChoiceSection(
                    title: "雇佣形式",
                    options: [("", "不限"), ("part_time", "兼职"), ("full_time", "全职"), ("dispatch", "派遣"), ("internship", "实习")],
                    selection: attrChoiceBinding("employment_type")
                )
                filterChoiceSection(
                    title: "日语要求",
                    options: [("", "不限"), ("not_required", "日语不限"), ("N5", "N5"), ("N4", "N4"), ("N3", "N3"), ("N2", "N2"), ("N1", "N1")],
                    selection: attrChoiceBinding("japanese_level")
                )
                filterChoiceSection(
                    title: "签证支持",
                    // "available,true" 兼容老数据：早期版本把 visa_support 存成了布尔。
                    options: [("", "不限"), ("available,true", "有"), ("consult", "可咨询")],
                    selection: attrChoiceBinding("visa_support")
                )
                filterToggleSection(title: "条件", toggles: [
                    ("no_experience_ok", "无经验可"),
                    ("student_ok", "留学生可"),
                    ("remote_ok", "可远程"),
                ])
            } else if baseType == "local_service" {
                filterChoiceSection(
                    title: "服务细分类",
                    options: serviceCategoryFilterOptions,
                    selection: Binding(
                        get: { selectedCategory },
                        set: { newValue in
                            selectedCategory = newValue
                            Task { await load(quiet: true) }
                        }
                    )
                )
                filterToggleSection(title: "商家条件", toggles: [
                    ("booking_required", "需要预约"),
                    ("certified_provider", "认证商家"),
                ])
            }

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 7) {
                Text(ListingFilterLocalizer.text("城市范围", language))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                scopeAreaRow(
                    title: KXListingCopy.pickText(language, "全国", "全国", "Nationwide"),
                    subtitle: KXListingCopy.pickText(language, "不限地区,查看全部", "地域を限定せず全件", "No area filter — everything"),
                    selected: scopeMode == .country
                ) { selectScope(.country) }
                ForEach(listingScopeAreas) { area in
                    scopeAreaRow(
                        title: area.localizedTitle(language),
                        subtitle: area.localizedSubtitle(language),
                        selected: scopeMode == .area && selectedScopeArea == area.id
                    ) { selectScope(.area, area: area.id) }
                }
            }

            prefecturePickerSection

            VStack(alignment: .leading, spacing: 7) {
                Text(ListingFilterLocalizer.text("热门城市", language))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(listingScopeHotCityCodes, id: \.self) { code in
                        if let city = KaiXRegionDirectory.resolve(regionCode: code) {
                            Button {
                                selectScope(.selectedCity, cityCode: city.regionCode)
                            } label: {
                                Text(KaiXRegionDirectory.localizedShortLabel(city, language: language))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(scopeMode == .selectedCity && selectedScopeRegionCode == city.regionCode ? Color.white : .primary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .background(scopeMode == .selectedCity && selectedScopeRegionCode == city.regionCode ? KXColor.accent : KXColor.softBackground.opacity(0.88), in: Capsule())
                                    .overlay(Capsule().stroke(KXColor.separator.opacity(0.55), lineWidth: 0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

        }
        .padding(12)
        .background(KXColor.softBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// 「城市范围」单行选项(全国 / 都市圈),统一视觉。
    private func scopeAreaRow(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(selected ? KXColor.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(KXColor.softBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// 47 都道府县选择:按都市圈分组(关东/关西/中部…),点一个县 = 看该县全部城市
    /// (服务端按 region_code 前缀匹配,覆盖客户端城市表之外的城市)。
    private var prefecturePickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(KXListingCopy.pickText(language, "都道府县", "都道府県", "Prefecture"))
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            ForEach(KaiXRegionDirectory.jpMetroCircles) { circle in
                VStack(alignment: .leading, spacing: 6) {
                    Text(metroCircleTitle(circle.code))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                    FlowLayout(spacing: 8) {
                        ForEach(circle.provinceCodes, id: \.self) { pc in
                            if let prov = KaiXRegionDirectory.provinces(for: "jp").first(where: { $0.code == pc }) {
                                provinceChip(prov)
                            }
                        }
                    }
                }
            }
        }
    }

    private func provinceChip(_ province: KaiXRegionDirectory.Province) -> some View {
        let selected = scopeMode == .province && selectedProvinceCode == province.code
        return Button {
            selectScope(.province, provinceCode: province.code)
        } label: {
            Text(KaiXRegionDirectory.localizedProvinceName(countryCode: "jp", province: province, language: language))
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? Color.white : .primary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(selected ? KXColor.accent : KXColor.softBackground.opacity(0.88), in: Capsule())
                .overlay(Capsule().stroke(KXColor.separator.opacity(0.55), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private func metroCircleTitle(_ code: String) -> String {
        switch code {
        case "hokkaido_tohoku": return KXListingCopy.pickText(language, "北海道・东北", "北海道・東北", "Hokkaido & Tohoku")
        case "kanto":           return KXListingCopy.pickText(language, "关东", "関東", "Kanto")
        case "chubu":           return KXListingCopy.pickText(language, "中部", "中部", "Chubu")
        case "kansai":          return KXListingCopy.pickText(language, "关西", "関西", "Kansai")
        case "chugoku":         return KXListingCopy.pickText(language, "中国地区", "中国地方", "Chugoku")
        case "shikoku":         return KXListingCopy.pickText(language, "四国", "四国", "Shikoku")
        case "kyushu_okinawa":  return KXListingCopy.pickText(language, "九州・冲绳", "九州・沖縄", "Kyushu & Okinawa")
        default:                return code
        }
    }

    private var serviceCategoryFilterOptions: [(value: String, label: String)] {
        let categories: [String]
        switch serviceSection {
        case "food":
            categories = KXListingCopy.foodSectionCategories
        case "travel":
            categories = KXListingCopy.travelSectionCategories
        case "transfer":
            categories = KXListingCopy.transferSectionCategories
        case "paperwork":
            categories = KXListingCopy.paperworkSectionCategories
        case "moving":
            categories = KXListingCopy.movingSectionCategories
        case "life":
            categories = KXListingCopy.lifeSetupSectionCategories
        case "beauty":
            categories = KXListingCopy.beautyHealthSectionCategories
        default:
            categories = KXListingCopy.foodSectionCategories + KXListingCopy.travelSectionCategories + KXListingCopy.transferSectionCategories + KXListingCopy.lifeSectionCategories
        }
        let unique = categories.reduce(into: [String]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }
        return [("全部", "全部")] + unique.map { ($0, KXListingCopy.categoryLabel($0, language)) }
    }

    private func filterPriceField(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text("¥")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .keyboardType(.numberPad)
                .font(.subheadline.weight(.bold))
                .onSubmit { Task { await load(quiet: true) } }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(KXColor.separator.opacity(0.7), lineWidth: 0.7))
    }

    private func filterChoiceSection(
        title: String,
        options: [(value: String, label: String)],
        selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ListingFilterLocalizer.text(title, language))
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    Button {
                        selection.wrappedValue = option.value
                    } label: {
                        Text(ListingFilterLocalizer.text(option.label, language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selection.wrappedValue == option.value ? Color.white : .primary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(selection.wrappedValue == option.value ? KXColor.accent : Color(.systemBackground), in: Capsule())
                            .overlay(Capsule().stroke(selection.wrappedValue == option.value ? Color.clear : KXColor.separator.opacity(0.65), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func filterToggleSection(title: String, toggles: [(key: String, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ListingFilterLocalizer.text(title, language))
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                ForEach(toggles, id: \.key) { item in
                    filterToggle(title: ListingFilterLocalizer.text(item.label, language), isOn: attrToggleBinding(item.key))
                }
            }
        }
    }

    private func filterToggle(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.bold))
                .foregroundStyle(isOn.wrappedValue ? KXColor.accent : .primary)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(Color(.systemBackground), in: Capsule())
                .overlay(Capsule().stroke(isOn.wrappedValue ? KXColor.accent.opacity(0.45) : KXColor.separator.opacity(0.65), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var stateContent: some View {
        if isLoading {
            loadingSkeleton
        } else if let errorMessage {
            ErrorStateView(message: errorMessage) { Task { await load() } }
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if visibleItems.isEmpty {
            VStack(spacing: 18) {
                if activeFilterCount > 0 {
                    // Empty because the filters are too narrow → lead with
                    // "clear filters", not an unrelated "go publish".
                    EmptyStateView(
                        title: KXListingCopy.pickText(language, "没有符合条件的结果", "条件に合う結果がありません", "No matches for these filters"),
                        subtitle: KXListingCopy.pickText(language, "试试放宽筛选或扩大范围", "条件を緩めるか範囲を広げてみてください", "Try relaxing your filters or widening the area"),
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    Button {
                        clearAllFilters()
                    } label: {
                        Label(KXListingCopy.pickText(language, "清空筛选", "条件をクリア", "Clear filters"), systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 48)
                            .background(KXColor.livingAccent, in: Capsule())
                            .shadow(color: KXColor.livingAccent.opacity(0.25), radius: 12, y: 5)
                    }
                    .buttonStyle(KXPressableStyle())
                    Button {
                        guard GuestSession.requireSignedIn(currentUser, reason: publishLoginReason) else { return }
                        router.open(.createCityListing(type: KXListingCopy.createType(for: lodgingActive ? "local_service" : baseType), citySlug: regionCode))
                    } label: {
                        Text(KXListingCopy.createTitle(for: lodgingActive ? "local_service" : baseType, language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KXColor.livingAccent)
                    }
                    .buttonStyle(.plain)
                } else {
                    EmptyStateView(
                        title: KXListingCopy.emptyTitle(for: copyType, language),
                        subtitle: KXListingCopy.emptySubtitle(for: copyType, language),
                        systemImage: KXListingCopy.icon(for: baseType)
                    )
                    Button {
                        guard GuestSession.requireSignedIn(currentUser, reason: publishLoginReason) else { return }
                        router.open(.createCityListing(type: KXListingCopy.createType(for: lodgingActive ? "local_service" : baseType), citySlug: regionCode))
                    } label: {
                        Label(KXListingCopy.createTitle(for: lodgingActive ? "local_service" : baseType, language), systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .frame(height: 48)
                            .background(KXColor.livingAccent, in: Capsule())
                            .shadow(color: KXColor.livingAccent.opacity(0.25), radius: 12, y: 5)
                    }
                    .buttonStyle(KXPressableStyle())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if isWorkChannel {
            // Indeed-style job cards, Airbnb layout: each role is its own
            // elevated card with breathing room — no outer surface (which
            // would nest card-in-card with KXJobListingRow's own surface).
            LazyVStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    KXJobListingRow(listing: item) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                    .kxListingZoomSource("listing-\(item.id)", zoomNamespace)
                }
            }
        } else if baseType == "secondhand" {
            // Two-column photo grid: square covers, price first, quick scan.
            LazyVStack(spacing: 14) {
                // Stable id (first item's id) instead of row index, so paging
                // loadMore / re-filter inserts rows incrementally instead of
                // forcing SwiftUI to rebuild every row.
                ForEach(secondhandRows, id: \.first?.id) { row in
                    HStack(alignment: .top, spacing: marketplaceGridSpacing) {
                        ForEach(row) { item in
                            KXSecondhandListingCard(listing: item, width: marketplaceCardWidth) {
                                router.open(.cityListingDetail(listingId: item.id))
                            }
                            .kxListingZoomSource("listing-\(item.id)", zoomNamespace)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if row.count == 1 {
                            Spacer(minLength: 0)
                                .frame(width: marketplaceCardWidth)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
        } else if baseType == "rental" {
            // 照片主导卡：长租与民宿共用同一套视觉语言。
            LazyVStack(spacing: 18) {
                ForEach(visibleItems) { item in
                    KXStayListingCard(listing: item, variant: forsaleActive ? .forsale : (staysActive ? .stay : .home)) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                    .kxListingZoomSource("listing-\(item.id)", zoomNamespace)
                }
            }
        } else if baseType == "local_service" {
            // 服务卡片：评分、类目、价位、预约 CTA。
            LazyVStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    KXServiceListingCard(listing: item) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                    .kxListingZoomSource("listing-\(item.id)", zoomNamespace)
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    KXStructuredListingRow(listing: item) {
                        router.open(.cityListingDetail(listingId: item.id))
                    }
                    .kxListingZoomSource("listing-\(item.id)", zoomNamespace)
                }
            }
        }
    }

    /// 按频道形态给出对应骨架占位。Extracted to `ChannelLoadingSkeleton` (a
    /// separate value-typed View) to keep this already-large struct's body
    /// lighter — the first step of breaking the channel screen into pieces.
    private var loadingSkeleton: some View {
        ChannelLoadingSkeleton(
            isWorkChannel: isWorkChannel,
            baseType: baseType,
            cardWidth: marketplaceCardWidth,
            gridSpacing: marketplaceGridSpacing
        )
    }

    /// quiet = 筛选/排序微调时静默重载：保留旧列表直到新结果回来，避免闪白。
    /// Price edits reload only after ~400ms of silence — typing "12000" must
    /// send one request, not five. Cancelling the previous task keeps exactly
    /// one pending reload; `loadGeneration` already defuses any stragglers.
    private func schedulePriceReload() {
        priceDebounceTask?.cancel()
        priceDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await load(quiet: true)
        }
    }

    private func load(quiet: Bool = false) async {
        guard let region else {
            errorMessage = "城市无法识别，请重新选择城市。"
            isLoading = false
            return
        }
        if !quiet { isLoading = true }
        if quiet { isReloading = true }
        loadGeneration += 1
        let generation = loadGeneration
        defer { if generation == loadGeneration { isReloading = false } }
        errorMessage = nil
        do {
            let scope = listingScopeQuery(for: region)
            if isWorkChannel {
                async let jobs = KaiXAPIClient.shared.listingsPage(type: "job", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, provinceCodes: scope.provinceCodes, countryCode: scope.countryCode, query: query, minPrice: Double(minimumPrice), maxPrice: Double(maximumPrice), sort: serverSort, attributes: attrFilters)
                async let hiring = KaiXAPIClient.shared.listingsPage(type: "hiring", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, provinceCodes: scope.provinceCodes, countryCode: scope.countryCode, query: query, minPrice: Double(minimumPrice), maxPrice: Double(maximumPrice), sort: serverSort, attributes: attrFilters)
                let jobPage = try await jobs
                let hiringPage = try await hiring
                guard generation == loadGeneration else { return }   // superseded by a newer load
                // 服务端空结果回退按每个请求独立触发:job 在本地有结果而 hiring
                // 单独回退到都市圈/全国时,不能把两种地理范围的条目混排,更不能
                // 在本地结果就摆在屏上时挂「该地区暂无内容」横幅。规则:
                // ① 两流都回退 → 全部展示 + 横幅;② 单流回退且另一流也为空 →
                // 展示回退结果 + 横幅;③ 单流回退但另一流有本地结果 → 丢弃回退
                // 流的异地条目(连同其游标,防止 loadMore 继续拉异地页),无横幅。
                var jobItems = jobPage.items
                var hiringItems = hiringPage.items
                var jobCursor = jobPage.nextCursor
                var hiringCursor = hiringPage.nextCursor
                var fbLabel: String?
                switch (jobPage.fallback != nil, hiringPage.fallback != nil) {
                case (true, true):
                    fbLabel = jobPage.fallbackLabel ?? hiringPage.fallbackLabel
                case (true, false):
                    if hiringItems.isEmpty {
                        fbLabel = jobPage.fallbackLabel
                    } else {
                        jobItems = []
                        jobCursor = nil
                    }
                case (false, true):
                    if jobItems.isEmpty {
                        fbLabel = hiringPage.fallbackLabel
                    } else {
                        hiringItems = []
                        hiringCursor = nil
                    }
                case (false, false):
                    fbLabel = nil
                }
                items = (jobItems + hiringItems).sorted(by: KXListingCopy.sortForDisplay)
                nextCursor = jobCursor
                nextHiringCursor = hiringCursor
                fallbackNoticeLabel = (fbLabel?.isEmpty == false) ? fbLabel : nil
            } else {
                let page = try await KaiXAPIClient.shared.listingsPage(
                    type: queryType,
                    citySlug: scope.citySlug,
                    regionCode: scope.regionCode,
                    regionCodes: scope.regionCodes,
                    provinceCodes: scope.provinceCodes,
                    countryCode: scope.countryCode,
                    query: query,
                    category: serverCategory,
                    categories: serverCategories,
                    minPrice: Double(minimumPrice),
                    maxPrice: Double(maximumPrice),
                    sort: serverSort,
                    attributes: attrFilters
                )
                guard generation == loadGeneration else { return }   // superseded by a newer load
                items = page.items
                nextCursor = page.nextCursor
                nextHiringCursor = nil
                fallbackNoticeLabel = (page.fallback != nil && page.fallbackLabel?.isEmpty == false) ? page.fallbackLabel : nil
            }
            isLoading = false
            recomputeVisibleItems()
        } catch {
            guard generation == loadGeneration else { return }
            // A load cancelled by navigation (task torn down mid-flight) is not
            // an error the user can act on — never surface "已取消" as a retry
            // screen. Whatever list was on screen stays; the .task guard reloads
            // on the next appearance only if the list is actually empty.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                isLoading = false
                return
            }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// Pull the next server page(s) and append, deduplicating by id so a
    /// row that moved between keyset windows can never show twice.
    private func loadMore() async {
        guard !isLoadingMore, !isLoading, hasMoreListings, let region else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = loadGeneration
        let scope = listingScopeQuery(for: region)
        do {
            var fetched: [KaiXCityListingDTO] = []
            // Cursor advances land in locals first: a stale page (superseded by
            // a reload mid-flight) must never overwrite the fresh load's cursors.
            var advancedCursor = nextCursor
            var advancedHiringCursor = nextHiringCursor
            if isWorkChannel {
                if let cursor = nextCursor {
                    let page = try await KaiXAPIClient.shared.listingsPage(type: "job", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, provinceCodes: scope.provinceCodes, countryCode: scope.countryCode, query: query, minPrice: Double(minimumPrice), maxPrice: Double(maximumPrice), sort: serverSort, attributes: attrFilters, cursor: cursor)
                    fetched += page.items
                    advancedCursor = page.nextCursor
                }
                if let cursor = nextHiringCursor {
                    let page = try await KaiXAPIClient.shared.listingsPage(type: "hiring", citySlug: scope.citySlug, regionCode: scope.regionCode, regionCodes: scope.regionCodes, provinceCodes: scope.provinceCodes, countryCode: scope.countryCode, query: query, minPrice: Double(minimumPrice), maxPrice: Double(maximumPrice), sort: serverSort, attributes: attrFilters, cursor: cursor)
                    fetched += page.items
                    advancedHiringCursor = page.nextCursor
                }
            } else if let cursor = nextCursor {
                let page = try await KaiXAPIClient.shared.listingsPage(
                    type: queryType,
                    citySlug: scope.citySlug,
                    regionCode: scope.regionCode,
                    regionCodes: scope.regionCodes,
                    provinceCodes: scope.provinceCodes,
                    countryCode: scope.countryCode,
                    query: query,
                    category: serverCategory,
                    categories: serverCategories,
                    minPrice: Double(minimumPrice),
                    maxPrice: Double(maximumPrice),
                    sort: serverSort,
                    attributes: attrFilters,
                    cursor: cursor
                )
                fetched = page.items
                advancedCursor = page.nextCursor
            }
            guard generation == loadGeneration else { return }   // a reload replaced the list mid-page
            nextCursor = advancedCursor
            nextHiringCursor = advancedHiringCursor
            let existing = Set(items.map(\.id))
            items += fetched.filter { !existing.contains($0.id) }
            recomputeVisibleItems()
        } catch {
            // Quietly stop paging on error; pull-to-refresh recovers. A stale
            // page's failure must not kill the cursors a newer load just set.
            guard generation == loadGeneration else { return }
            nextCursor = nil
            nextHiringCursor = nil
        }
    }

    private func listingScopeQuery(for region: KaiXRegionDirectory.Region) -> (citySlug: String?, regionCode: String?, regionCodes: [String], provinceCodes: [String], countryCode: String?) {
        switch scopeMode {
        case .city:
            return (region.cityCode, region.regionCode, [], [], nil)
        case .country:
            return (nil, nil, [], [], region.countryCode)
        case .area:
            // 都市圈按整组都道府县全覆盖(关东圈=7 县所有城市),交给服务端按
            // region_code 前缀匹配——不再依赖那份只有 5 个城市的旧硬编码列表。
            let provinces = KaiXRegionDirectory.jpMetroCircles
                .first { $0.code == selectedScopeArea }?.provinceCodes ?? []
            return (nil, nil, [], provinces, region.countryCode)
        case .province:
            return (nil, nil, [], selectedProvinceCode.isEmpty ? [] : [selectedProvinceCode], region.countryCode)
        case .selectedCity:
            let selected = selectedScopeRegion ?? region
            return (selected.cityCode, selected.regionCode, [], [], nil)
        }
    }

    /// saved_searches 落库只有 city_slug / region_code / country_code 三级位置
    /// 列(没有都道府县/都市圈列),而服务端匹配会把 region_code 按整个都市圈
    /// 扩展(metro_circle_region_codes)。据此把各档 scopeMode 映射成可匹配的
    /// 订阅条件:都市圈/都道府县档取圈内(县内)一个代表城市的 region_code 表达
    /// 「整圈」(都道府县档因此比所选县略宽——是当前列结构下最小的超集),全国
    /// 档传 country_code。绝不能三者全空落库,否则订阅会匹配全世界的新信息。
    private func savedSearchScope(for region: KaiXRegionDirectory.Region) -> (citySlug: String?, regionCode: String?, countryCode: String?) {
        switch scopeMode {
        case .city:
            return (region.cityCode, region.regionCode, nil)
        case .selectedCity:
            let selected = selectedScopeRegion ?? region
            return (selected.cityCode, selected.regionCode, nil)
        case .area:
            let circle = KaiXRegionDirectory.jpMetroCircles.first { $0.code == selectedScopeArea }
            let representative: KaiXRegionDirectory.Region? =
                (circle?.provinceCodes.contains(region.provinceCode) == true)
                ? region
                : KaiXRegionDirectory.regionsForMetroCircle(selectedScopeArea).first?.region
            return (nil, representative?.regionCode, region.countryCode)
        case .province:
            if !selectedProvinceCode.isEmpty,
               let circle = KaiXRegionDirectory.jpMetroCircles.first(where: { $0.provinceCodes.contains(selectedProvinceCode) }),
               let representative = KaiXRegionDirectory.regionsForMetroCircle(circle.code)
                   .first(where: { $0.province.code == selectedProvinceCode })?.region {
                return (nil, representative.regionCode, region.countryCode)
            }
            return (nil, nil, region.countryCode)
        case .country:
            return (nil, nil, region.countryCode)
        }
    }

    private func resultCountText(_ count: Int) -> String {
        KXListingCopy.pickText(language, "\(count) 条结果", "\(count)件の結果", "\(count) results")
    }
}

/// One user's published listings of a single type — opened from a tappable
/// count tag on their profile ("出售二手 5" → their secondhand items). Reuses
/// the channel cards but is seller-scoped across all cities (no region filter).
struct UserListingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState
    let userId: String
    let listingType: String
    let title: String
    let currentUser: UserEntity

    @State private var items: [KaiXCityListingDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var baseType: String {
        listingType == "hiring" ? "job" : listingType
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if isLoading {
                    LoadingView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load() } }
                } else if items.isEmpty {
                    KXEmptyState(
                        title: KXListingCopy.pickText(language, "暂无发布", "まだ投稿がありません", "No listings yet"),
                        subtitle: KXListingCopy.pickText(language, "TA 还没有发布该类型的内容。", "この種類の投稿はまだありません。", "This person has not published this type of listing yet."),
                        systemImage: "tray"
                    )
                } else {
                    resultsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(userId)-\(listingType)") { await load() }
    }

    private var header: some View {
        HStack(spacing: KXSpacing.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(KXColor.livingInk)
                    .frame(width: 42, height: 42)
                    .kxGlassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(KXListingCopy.pickText(language, "返回", "戻る", "Back"))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(KXColor.livingInk)
                Text(KXListingCopy.pickText(language, "\(items.count) 条发布", "\(items.count)件の投稿", "\(items.count) listings"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KXColor.livingMuted)
            }
            Spacer()
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(KXColor.livingBackground.opacity(0.94))
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    @ViewBuilder
    private var resultsList: some View {
        ScrollView {
            Group {
                if baseType == "secondhand" {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                        ForEach(items) { item in
                            KXSecondhandListingCard(listing: item) { router.open(.cityListingDetail(listingId: item.id)) }
                        }
                    }
                } else if baseType == "rental" {
                    LazyVStack(spacing: 18) {
                        ForEach(items) { item in
                            KXStayListingCard(listing: item, variant: KXListingCopy.isStayCategory(item.category) ? .stay : .home) {
                                router.open(.cityListingDetail(listingId: item.id))
                            }
                        }
                    }
                } else if baseType == "job" {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            KXJobListingRow(listing: item) { router.open(.cityListingDetail(listingId: item.id)) }
                        }
                    }
                } else if baseType == "local_service" {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            KXServiceListingCard(listing: item) { router.open(.cityListingDetail(listingId: item.id)) }
                        }
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            KXStructuredListingRow(listing: item) { router.open(.cityListingDetail(listingId: item.id)) }
                        }
                    }
                }
            }
            .padding(.horizontal, KaiXTheme.horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, chrome.bottomContentPadding + 24)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            // job tag covers both job + hiring; fetch both and merge.
            if listingType == "job" {
                async let jobs = KaiXAPIClient.shared.sellerListings(type: "job", sellerId: userId)
                async let hiring = KaiXAPIClient.shared.sellerListings(type: "hiring", sellerId: userId)
                items = sortListings((try await jobs) + (try await hiring))
            } else {
                items = sortListings(try await KaiXAPIClient.shared.sellerListings(type: listingType, sellerId: userId))
            }
            isLoading = false
        } catch {
            errorMessage = error.kaixUserMessage
            isLoading = false
        }
    }

    private func sortListings(_ listings: [KaiXCityListingDTO]) -> [KaiXCityListingDTO] {
        var seen = Set<String>()
        return listings
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.updated_at ?? $0.updatedAt ?? "") > ($1.updated_at ?? $1.updatedAt ?? "") }
    }
}

/// Per-channel first-load skeleton, split out of `CityListingChannelView` so the
/// channel's own body stays smaller (faster to type-check / diff). Value-only
/// inputs — no shared state — so the extraction is purely mechanical.
private struct ChannelLoadingSkeleton: View {
    let isWorkChannel: Bool
    let baseType: String
    let cardWidth: CGFloat
    let gridSpacing: CGFloat

    var body: some View {
        // Fewer skeleton cards: only the first-screen count needs to render on
        // the push frame; the rest arrive with real data.
        if isWorkChannel {
            LazyVStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in KXJobSkeletonRow() }
            }
        } else if baseType == "secondhand" {
            LazyVStack(spacing: 14) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(alignment: .top, spacing: gridSpacing) {
                        KXSecondhandSkeletonCard(width: cardWidth)
                        KXSecondhandSkeletonCard(width: cardWidth)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if baseType == "rental" {
            LazyVStack(spacing: 18) {
                ForEach(0..<2, id: \.self) { _ in KXBigPhotoSkeletonCard() }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in KXBigPhotoSkeletonCard() }
            }
        }
    }
}
