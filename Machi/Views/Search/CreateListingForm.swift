import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Create / edit city-listing form, extracted from DiscoverView.swift.
// CreateCityListingView is the largest single view in the app; pulling it
// (and its form-field helpers) out keeps DiscoverView navigable.
struct EditCityListingRouteView: View {
    let listingId: String
    let currentUser: UserEntity

    @State private var listing: KaiXCityListingDTO?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let listing {
                CreateCityListingView(
                    listingType: listing.type,
                    citySlug: listing.region_code ?? listing.regionCode ?? listing.city_slug ?? listing.citySlug,
                    currentUser: currentUser,
                    existingListing: listing
                )
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) {
                    Task { await load() }
                }
            } else {
                KXInlineLoader()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .kxPageBackground()
            }
        }
        .task(id: listingId) { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            listing = try await KaiXAPIClient.shared.cityListing(listingId)
        } catch {
            errorMessage = error.kaixUserMessage
        }
    }
}

/// 菜单 / 团购套餐:发布页里「一行一项、| 分隔」<-> 结构化 JSON 字符串。
/// 发布时编码成 JSON(后端 normalize_listing_attributes 解析回数组),
/// 编辑时把已存数组还原成多行文本。
enum KXMerchantInput {
    static func encodeMenu(_ text: String) -> String {
        let dishes: [[String: String]] = text.components(separatedBy: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let p = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = p.first, !name.isEmpty else { return nil }
            var d = ["name": name]
            if p.count > 1, !p[1].isEmpty { d["price"] = p[1] }
            if p.count > 2, !p[2].isEmpty { d["desc"] = p[2] }
            return d
        }
        guard !dishes.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: dishes),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    static func encodePackages(_ text: String) -> String {
        let pkgs: [[String: String]] = text.components(separatedBy: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let p = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let title = p.first, !title.isEmpty else { return nil }
            var d = ["title": title]
            if p.count > 1, !p[1].isEmpty { d["price"] = p[1] }
            if p.count > 2, !p[2].isEmpty { d["original_price"] = p[2] }
            if p.count > 3, !p[3].isEmpty { d["includes"] = p[3] }
            return d
        }
        guard !pkgs.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: pkgs),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    static func menuLines(_ listing: KaiXCityListingDTO) -> String {
        listing.menuDishes.map { [$0.name, $0.price, $0.desc].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " | ") }.joined(separator: "\n")
    }

    static func packageLines(_ listing: KaiXCityListingDTO) -> String {
        listing.groupPackages.map { [$0.title, $0.price, $0.original_price, $0.includes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " | ") }.joined(separator: "\n")
    }
}

struct CreateCityListingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var chrome: AppChromeState
    let listingType: String
    let citySlug: String?
    let currentUser: UserEntity
    let existingListing: KaiXCityListingDTO?
    let onPublishedListing: ((String) -> Void)?

    init(
        listingType: String,
        citySlug: String?,
        currentUser: UserEntity,
        existingListing: KaiXCityListingDTO? = nil,
        onPublishedListing: ((String) -> Void)? = nil
    ) {
        self.listingType = listingType
        self.citySlug = citySlug
        self.currentUser = currentUser
        self.existingListing = existingListing
        self.onPublishedListing = onPublishedListing
    }

    @State private var title = ""
    @State private var category = ""
    @State private var price = ""
    @State private var location = ""
    @State private var description = ""
    @State private var listingMode = "出售"
    @State private var condition = "良好"
    @State private var brandModel = ""
    @State private var originalPrice = ""
    @State private var purchaseTime = ""
    @State private var accessories = ""
    @State private var defectNote = ""
    @State private var secondhandAvailableTime = ""
    @State private var secondhandPickupNotes = ""
    @State private var pickupAvailable = true
    @State private var secondhandShippingAvailable = false
    @State private var priceNegotiable = false
    @State private var layout = "1K"
    @State private var area = ""
    @State private var station = ""
    @State private var moveIn = ""
    @State private var employmentType = "兼职"
    @State private var japaneseLevel = "N3"
    @State private var workingHours = ""
    @State private var companyName = ""
    @State private var shareAllowed = false
    @State private var shortTermAllowed = false
    @State private var furnished = false
    @State private var visaSupport = false
    @State private var noExperienceOK = false
    @State private var studentOK = false
    @State private var remoteOK = false
    @State private var jobHolidays = ""
    @State private var jobBenefits = ""
    @State private var serviceBusinessName = ""
    @State private var serviceType = ""
    @State private var serviceCategorySection = KXListingCopy.serviceCreateSections.first?.id ?? "food"
    @State private var serviceArea = ""
    @State private var priceUnit = "预约咨询"
    @State private var availability = ""
    @State private var certifiedProvider = false
    @State private var serviceProcess = ""
    @State private var cancellationRule = ""
    @State private var openHours = ""
    @State private var priceRange = ""
    @State private var nearStation = ""
    @State private var storePhone = ""
    @State private var reservationRequired = false
    @State private var reservationNote = ""
    @State private var menuText = ""
    @State private var packagesText = ""
    @State private var languages = ""
    @State private var roomType = ""
    @State private var maxGuests = ""
    @State private var checkInTime = "15:00"
    @State private var checkOutTime = "10:00"
    @State private var minimumStay = "1 晚"
    @State private var amenities = ""
    @State private var inventoryNote = ""
    @State private var breakfastIncluded = false
    @State private var instantConfirmation = false
    @State private var ticketType = ""
    @State private var duration = ""
    @State private var meetingPoint = ""
    @State private var pickupService = false
    @State private var includedItems = ""
    @State private var notIncluded = ""
    @State private var userPrepare = ""
    @State private var licenseNote = ""
    @State private var airportRoute = ""
    @State private var vehicleType = ""
    @State private var passengerCount = ""
    @State private var luggageCount = ""
    @State private var flightInfoNote = ""
    @State private var waitingRule = ""
    @State private var surchargeNote = ""
    @State private var documentType = ""
    @State private var requiredMaterials = ""
    @State private var deliveryTime = ""
    @State private var noResultGuarantee = false
    @State private var propertySize = ""
    @State private var itemVolume = ""
    @State private var vehicleStaff = ""
    @State private var setupType = ""
    @State private var cannotGuarantee = ""
    @State private var beautyService = ""
    @State private var medicalDisclaimer = ""
    @State private var serviceTarget = ""
    @State private var merchantName = ""
    @State private var discountInfo = ""
    @State private var validUntil = ""
    @State private var usageRules = ""
    @State private var merchantVerified = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var mediaDrafts: [MediaDraft] = []
    @State private var mediaUploadPhases: [String: ListingMediaUploadPhase] = [:]
    @State private var uploadedMedia: [String: KaiXMediaDTO] = [:]
    @State private var existingMedia: [KaiXListingMediaDTO] = []
    @State private var didHydrateExisting = false
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var listingTaxonomyCategories: [KaiXListingTaxonomyCategoryDTO] = []
    // 发布地区 = the structured region the listing is filed under (drives the
    // top region filter + city channel). Distinct from `location` (展示位置),
    // which is the free-text business location the user types. Seeded from the
    // passed citySlug / current browsing region, then user-changeable.
    @State private var selectedRegion: KaiXRegionDirectory.Region?
    @State private var isShowingRegionPicker = false
    @State private var publishedReceipt: ListingPublishReceipt?
    @State private var showMembershipSheet = false
    @State private var showMembershipGate = false
    @State private var showQuotaExhausted = false
    @State private var quotaExhaustedMessage: String?
    // #6: this month's remaining high-trust publish quota for a member on a gated
    // type. nil = unknown / not loaded / endpoint unavailable (row stays hidden).
    @State private var listingQuotaRemaining: Int?

    /// Listing types gated behind Machi membership (mirrors the server's
    /// LISTING_TYPES_REQUIRING_MEMBERSHIP). Used to prompt *before* the user
    /// fills out the whole form and again when they tap publish, instead of
    /// only surfacing the server's 403 as a bottom error.
    private static let membershipGatedTypes: Set<String> = ["rental", "job", "hiring", "local_service", "discount"]

    private var needsMembership: Bool {
        Self.membershipGatedTypes.contains(listingType) && !currentUser.isVerifiedMember && !isEditing
    }

    /// A member publishing a gated type is the only case the monthly quota row is
    /// relevant to.
    private var showsListingQuota: Bool {
        Self.membershipGatedTypes.contains(listingType) && currentUser.isVerifiedMember && !isEditing
    }

    /// Load the member's remaining monthly high-trust publish quota. Silent on any
    /// failure (404 on an older server, network) — the row simply stays hidden.
    private func loadListingQuota() async {
        guard showsListingQuota else {
            listingQuotaRemaining = nil
            return
        }
        guard let resp = try? await KaiXAPIClient.shared.membershipListingQuota() else {
            listingQuotaRemaining = nil
            return
        }
        listingQuotaRemaining = resp.remaining(forGroup: listingType)
    }

    private var region: KaiXRegionDirectory.Region? {
        if let selectedRegion { return selectedRegion }
        if let citySlug,
           let region = KaiXRegionDirectory.resolve(regionCode: citySlug) {
            return region
        }
        return RegionStore.shared.current ?? KaiXRegionDirectory.resolve(regionCode: "jp.tokyo.tokyo")
    }

    /// Channel-specific label for the free-text 展示位置 field (the business
    /// location), kept separate from the structured 发布地区 above.
    private var locationFieldTitle: String {
        switch listingType {
        case "secondhand": return KXListingCopy.pickText(language, "交易地点 / 最近车站", "受け渡し場所 / 最寄り駅", "Meetup / nearest station")
        case "rental": return KXListingCopy.pickText(language, "房源位置", "物件の場所", "Property location")
        case "job", "hiring": return KXListingCopy.pickText(language, "工作地点", "勤務地", "Work location")
        case "jobseeker": return KXListingCopy.pickText(language, "希望工作地区", "希望勤務エリア", "Preferred work area")
        case "local_service", "discount": return KXListingCopy.pickText(language, "店铺地址 / 服务范围", "店舗住所 / 対応エリア", "Address / service area")
        default: return KXListingCopy.pickText(language, "展示位置", "表示する場所", "Display location")
        }
    }

    private var locationFieldPlaceholder: String {
        switch listingType {
        case "secondhand": return KXListingCopy.pickText(language, "例如 川崎站东口 / 武藏小杉 / 可邮寄", "例：川崎駅東口 / 武蔵小杉 / 郵送可", "e.g. Kawasaki Stn east / Musashi-Kosugi / shippable")
        case "rental": return KXListingCopy.pickText(language, "例如 中野站步行 8 分钟", "例：中野駅 徒歩8分", "e.g. 8 min walk from Nakano Stn")
        case "job", "hiring": return KXListingCopy.pickText(language, "例如 新宿店 / 最近车站 / 可远程", "例：新宿店 / 最寄り駅 / リモート可", "e.g. Shinjuku branch / nearest stn / remote ok")
        case "jobseeker": return KXListingCopy.pickText(language, "例如 23 区内 / 可通勤 1 小时 / 可远程", "例：23区内 / 通勤1時間可 / リモート可", "e.g. within 23 wards / 1h commute / remote ok")
        case "local_service", "discount": return KXListingCopy.pickText(language, "例如 涩谷店 / 上门范围 / 线上预约", "例：渋谷店 / 出張範囲 / オンライン予約", "e.g. Shibuya store / on-site area / online")
        default: return KXListingCopy.pickText(language, "填写具体位置或服务范围", "具体的な場所や対応範囲", "Specific place or service area")
        }
    }

    private var isEditing: Bool { existingListing != nil }

    private var taxonomyRequestType: String {
        KXListingCopy.createType(for: listingType)
    }

    private var activeTaxonomyCategories: [KaiXListingTaxonomyCategoryDTO] {
        var items = listingTaxonomyCategories
        if listingType == "local_service" {
            items = items.filter { item in
                let key = item.resolvedKey
                return !KXListingCopy.isStayCategory(key) || key == category
            }
        }
        var seen = Set<String>()
        return items.filter { item in
            let key = item.resolvedKey
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    private var fallbackCategoryValues: [String] {
        KXListingCopy.categories(for: listingType).filter { $0 != "全部" }
    }

    private var publishCategoryValues: [String] {
        let serverValues = activeTaxonomyCategories.map(\.resolvedKey)
        let values = serverValues.isEmpty ? fallbackCategoryValues : serverValues
        var seen = Set<String>()
        return values.filter { value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean != "全部" else { return false }
            return seen.insert(clean).inserted
        }
    }

    private func taxonomyCategoryLabel(_ key: String) -> String {
        if let item = activeTaxonomyCategories.first(where: { $0.resolvedKey == key }) {
            switch language {
            case .ja:
                return item.resolvedLabelJa
            case .en:
                return item.resolvedLabelEn
            default:
                return item.resolvedLabel
            }
        }
        return KXListingCopy.categoryLabel(key, language)
    }

    private func serviceCategories(for section: KXListingCopy.ServiceCreateSection) -> [String] {
        let serverValues = activeTaxonomyCategories.compactMap { item -> String? in
            let key = item.resolvedKey
            guard !key.isEmpty else { return nil }
            if !item.resolvedSectionKey.isEmpty {
                return item.resolvedSectionKey == section.id ? key : nil
            }
            return KXListingCopy.serviceCreateSectionKey(for: key) == section.id ? key : nil
        }
        guard !serverValues.isEmpty else { return section.categories }
        var seen = Set<String>()
        return serverValues.filter { seen.insert($0).inserted }
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && region != nil
            && typeRequiredFieldsReady
            && !hasBlockingMediaUpload
            && !isSubmitting
    }

    private var hasBlockingMediaUpload: Bool {
        mediaUploadPhases.values.contains { phase in
            if case .failed = phase { return true }
            return false
        }
    }

    private var imageLimit: Int {
        if listingType == "rental" { return 20 }
        if listingType == "work" || listingType == "job" || listingType == "hiring" || listingType == "discount" { return 5 }
        return 10
    }

    private var typeRequiredFieldsReady: Bool {
        let filled: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if listingType == "rental" {
            return filled(layout) && filled(area) && filled(station) && filled(moveIn)
        }
        if listingType == "work" || listingType == "job" || listingType == "hiring" {
            return filled(companyName) && filled(workingHours)
        }
        if listingType == "local_service" {
            guard let vertical = serviceVertical, filled(category) else { return false }
            switch vertical {
            case .foodRestaurant, .diningBooking:
                return filled(serviceBusinessName) && filled(serviceArea)
            case .lodging:
                return filled(serviceBusinessName) && filled(roomType) && filled(maxGuests)
            case .attractionTicket, .dayTour:
                return filled(serviceBusinessName) && filled(ticketType) && filled(availability)
            case .airportTransfer:
                return filled(serviceBusinessName) && filled(airportRoute) && filled(serviceArea)
            case .paperworkTranslation:
                return filled(serviceBusinessName) && filled(languages) && filled(documentType)
            case .movingCleaning:
                return filled(serviceBusinessName) && filled(serviceArea)
            case .lifeSetup:
                return filled(serviceBusinessName) && filled(serviceArea) && filled(setupType)
            case .beautyHealth:
                return filled(serviceBusinessName) && filled(serviceArea) && filled(beautyService)
            case .petFamily:
                return filled(serviceBusinessName) && filled(serviceArea)
            }
        }
        if listingType == "discount" {
            return filled(merchantName) && filled(discountInfo) && filled(validUntil)
        }
        if listingType == "secondhand" {
            return filled(category) && filled(price) && filled(condition)
        }
        return true
    }

    private var isStayService: Bool {
        serviceVertical == .lodging
    }

    private var serviceVertical: KXListingCopy.ServiceVertical? {
        guard listingType == "local_service" else { return nil }
        return KXListingCopy.serviceVertical(category: category, serviceType: serviceType)
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { category },
            set: { nextValue in
                if listingType == "local_service" {
                    applyServiceCategory(nextValue)
                } else {
                    category = nextValue
                }
            }
        )
    }

    private func applyServiceCategory(_ nextCategory: String) {
        let previousVertical = serviceVertical
        let cleanCategory = nextCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanCategory.isEmpty {
            category = ""
            serviceType = ""
            return
        }
        let nextVertical = KXListingCopy.serviceVertical(category: cleanCategory, serviceType: cleanCategory)
        serviceCategorySection = KXListingCopy.serviceCreateSectionKey(for: cleanCategory) ?? serviceCategorySection
        category = cleanCategory
        serviceType = cleanCategory
        if previousVertical != nextVertical {
            clearServiceSpecificFields()
        }
    }

    private func applyServiceType(_ nextType: String) {
        let previousVertical = serviceVertical
        let nextVertical = KXListingCopy.serviceVertical(category: nextType, serviceType: nextType)
        serviceCategorySection = KXListingCopy.serviceCreateSectionKey(for: nextType) ?? serviceCategorySection
        serviceType = nextType
        category = nextType
        if previousVertical != nextVertical {
            clearServiceSpecificFields()
        }
    }

    private var activeServiceCreateSection: KXListingCopy.ServiceCreateSection {
        if let taxonomyCategory = activeTaxonomyCategories.first(where: { $0.resolvedKey == category }),
           !taxonomyCategory.resolvedSectionKey.isEmpty,
           let section = KXListingCopy.serviceCreateSections.first(where: { $0.id == taxonomyCategory.resolvedSectionKey }) {
            return section
        }
        if let fromCategory = KXListingCopy.serviceCreateSection(for: category) {
            return fromCategory
        }
        if let fromState = KXListingCopy.serviceCreateSections.first(where: { $0.id == serviceCategorySection }) {
            return fromState
        }
        return KXListingCopy.serviceCreateSections[0]
    }

    private func selectServiceCreateSection(_ section: KXListingCopy.ServiceCreateSection) {
        serviceCategorySection = section.id
        let sectionCategories = serviceCategories(for: section)
        guard !sectionCategories.contains(category), let first = sectionCategories.first else { return }
        applyServiceCategory(first)
    }

    @MainActor
    private func loadListingTaxonomy() async {
        do {
            let payload = try await KaiXAPIClient.shared.listingTaxonomy(type: taxonomyRequestType)
            listingTaxonomyCategories = payload.resolvedCategories
        } catch {
            listingTaxonomyCategories = []
        }
    }

    private func clearServiceSpecificFields() {
        serviceArea = ""
        priceUnit = "预约咨询"
        availability = ""
        serviceProcess = ""
        cancellationRule = ""
        openHours = ""
        priceRange = ""
        nearStation = ""
        storePhone = ""
        reservationRequired = false
        reservationNote = ""
        menuText = ""
        packagesText = ""
        languages = ""
        roomType = ""
        maxGuests = ""
        checkInTime = "15:00"
        checkOutTime = "10:00"
        minimumStay = "1 晚"
        amenities = ""
        inventoryNote = ""
        breakfastIncluded = false
        instantConfirmation = false
        ticketType = ""
        duration = ""
        meetingPoint = ""
        pickupService = false
        includedItems = ""
        notIncluded = ""
        userPrepare = ""
        licenseNote = ""
        airportRoute = ""
        vehicleType = ""
        passengerCount = ""
        luggageCount = ""
        flightInfoNote = ""
        waitingRule = ""
        surchargeNote = ""
        documentType = ""
        requiredMaterials = ""
        deliveryTime = ""
        noResultGuarantee = false
        propertySize = ""
        itemVolume = ""
        vehicleStaff = ""
        setupType = ""
        cannotGuarantee = ""
        beautyService = ""
        medicalDisclaimer = ""
        serviceTarget = ""
    }

    private var typeAccent: Color {
        switch listingType {
        case "rental":
            return KXColor.accent
        case "work", "job", "hiring":
            return KXColor.rankViolet
        case "local_service":
            return KXColor.heat
        case "discount":
            return KXColor.rankCoral
        default:
            return KXColor.rankTeal
        }
    }

    private func messageIsPositive(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return text.contains("成功")
            || text.contains("提交")
            || text.contains("保存")
            || text.contains("送信")
            || text.contains("保存")
            || lowercased.contains("success")
            || lowercased.contains("submitted")
            || lowercased.contains("saved")
    }

    private var requiredProgress: (done: Int, total: Int) {
        let filled: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var values = [filled(title), filled(location)]
        if listingType == "rental" {
            values += [filled(layout), filled(area), filled(station), filled(moveIn)]
        } else if listingType == "work" || listingType == "job" || listingType == "hiring" {
            values += [filled(companyName), filled(workingHours)]
        } else if listingType == "local_service" {
            values += [filled(category)]
            if let vertical = serviceVertical {
                switch vertical {
                case .foodRestaurant, .diningBooking:
                    values += [filled(serviceBusinessName), filled(serviceArea)]
                case .lodging:
                    values += [filled(serviceBusinessName), filled(roomType), filled(maxGuests)]
                case .attractionTicket, .dayTour:
                    values += [filled(serviceBusinessName), filled(ticketType), filled(availability)]
                case .airportTransfer:
                    values += [filled(serviceBusinessName), filled(airportRoute), filled(serviceArea)]
                case .paperworkTranslation:
                    values += [filled(serviceBusinessName), filled(languages), filled(documentType)]
                case .movingCleaning, .petFamily:
                    values += [filled(serviceBusinessName), filled(serviceArea)]
                case .lifeSetup:
                    values += [filled(serviceBusinessName), filled(serviceArea), filled(setupType)]
                case .beautyHealth:
                    values += [filled(serviceBusinessName), filled(serviceArea), filled(beautyService)]
                }
            } else {
                values += [false]
            }
        } else if listingType == "discount" {
            values += [filled(merchantName), filled(discountInfo), filled(validUntil)]
        } else if listingType == "secondhand" {
            values += [filled(category), filled(price), filled(condition)]
        }
        return (values.filter { $0 }.count, values.count)
    }

    private var missingRequiredCopy: String {
        let filled: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !filled(title) { return KXListingCopy.pickText(language, "请先补充标题", "タイトルを入力してください", "Add a title first") }
        if !filled(location) { return KXListingCopy.pickText(language, "请补充地区、车站或交易地点", "エリア、駅、または受け渡し場所を入力してください", "Add an area, station, or meetup location") }
        if region == nil { return KXListingCopy.pickText(language, "请先选择可发布的城市", "投稿先の都市を選んでください", "Choose a city before posting") }
        if listingType == "rental" && !typeRequiredFieldsReady { return KXListingCopy.pickText(language, "请补充户型、面积、最近车站和入住时间", "間取り、面積、最寄り駅、入居時期を入力してください", "Add layout, size, nearest station, and move-in date") }
        if (listingType == "work" || listingType == "job" || listingType == "hiring") && !typeRequiredFieldsReady { return KXListingCopy.pickText(language, "请补充公司/店铺名和工作时间", "会社・店舗名と勤務時間を入力してください", "Add company/store name and working hours") }
        if listingType == "local_service" && serviceVertical == nil { return KXListingCopy.pickText(language, "请先选择商家与服务细分类", "店舗・サービスの細分類を選んでください", "Choose a business/service subcategory") }
        if listingType == "local_service" && !typeRequiredFieldsReady { return KXListingCopy.pickText(language, "请补齐当前服务分类的必填字段", "現在のサービス分類の必須項目を入力してください", "Complete the required fields for this service type") }
        if listingType == "discount" && !typeRequiredFieldsReady { return KXListingCopy.pickText(language, "请补充商家、优惠内容和有效期", "店舗、特典内容、有効期限を入力してください", "Add merchant, deal details, and validity") }
        if listingType == "secondhand" && !typeRequiredFieldsReady { return KXListingCopy.pickText(language, "请补充分类、价格和新旧程度，免费送可填 0", "カテゴリ、価格、状態を入力してください。無料譲渡は 0 で登録できます", "Add category, price, and condition. Use 0 for free items") }
        return KXListingCopy.pickText(language, "信息完整后即可提交", "情報がそろうと送信できます", "You can submit once the details are complete")
    }

    var body: some View {
        VStack(spacing: 0) {
            createHeader
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.lg) {
                    createHero
                    if needsMembership { membershipBanner }
                    if showsListingQuota, let remaining = listingQuotaRemaining { listingQuotaBanner(remaining) }
                    publishRegionCard
                    photoSection
                    basicInfoSection
                    typeFields
                    validationInlineHint
                    safetySection
                    if let message {
                        Text(message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(messageIsPositive(message) ? KXColor.accent : KXColor.heat)
                            .padding(KXSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background((messageIsPositive(message) ? KXColor.accent : KXColor.heat).opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, KaiXTheme.horizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, canSubmit || isSubmitting ? 22 : chrome.bottomContentPadding + 22)
            }
            if canSubmit || isSubmitting {
                submitBar
            }
        }
        .kxPageBackground()
        .toolbar(.hidden, for: .navigationBar)
        // 工作台等入口用 NavigationLink 直推本页(不走 router 的
        // requiresHiddenTabBar),不收起悬浮 TabBar 会压住底部提交栏。
        .kxHidesTabBar(reason: .custom("focus-form"))
        .onChange(of: pickerItems) { _, newItems in
            Task { await loadImages(newItems) }
        }
        .task(id: existingListing?.id) {
            hydrateExistingListingIfNeeded()
        }
        .task(id: taxonomyRequestType) {
            await loadListingTaxonomy()
        }
        .task(id: listingType) {
            await loadListingQuota()
        }
        .onAppear {
            // Seed 发布地区 from the editing listing, the passed citySlug, or the
            // current browsing region — so the card always shows a concrete region.
            if selectedRegion == nil {
                if let existingListing,
                   let r = KaiXRegionDirectory.resolve(regionCode: existingListing.region_code ?? existingListing.regionCode ?? "") {
                    selectedRegion = r
                } else if let citySlug, let r = KaiXRegionDirectory.resolve(regionCode: citySlug) {
                    selectedRegion = r
                } else {
                    selectedRegion = RegionStore.shared.current
                }
            }
        }
        .sheet(isPresented: $isShowingRegionPicker) {
            RegionSelectorView(
                initialCountry: region?.countryCode ?? RegionStore.shared.current?.countryCode ?? "jp",
                allowsAnyCountry: false
            ) { picked in
                selectedRegion = picked
            }
        }
        .sheet(item: $publishedReceipt) { receipt in
            ListingPublishSuccessSheet(
                receipt: receipt,
                language: language,
                onViewListing: {
                    let id = receipt.listingId
                    publishedReceipt = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        openPublishedListing(id)
                    }
                },
                onContinuePublishing: {
                    publishedReceipt = nil
                    resetFormForAnother()
                },
                onClose: {
                    publishedReceipt = nil
                    dismiss()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMembershipSheet) {
            NavigationStack { MembershipView(currentUser: currentUser) }
        }
        .confirmationDialog(
            membershipGateTitle,
            isPresented: $showMembershipGate,
            titleVisibility: .visible
        ) {
            Button(KXListingCopy.pickText(language, "开通会员", "メンバー登録", "Get membership")) {
                showMembershipSheet = true
            }
            Button(KXListingCopy.pickText(language, "了解权益", "特典を見る", "See benefits")) {
                showMembershipSheet = true
            }
            Button(KXListingCopy.pickText(language, "取消", "キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(membershipGateMessage)
        }
        .confirmationDialog(
            KXListingCopy.pickText(language, "本月免费发布已用完", "今月の無料投稿枠を使い切りました", "Monthly free listings used up"),
            isPresented: $showQuotaExhausted,
            titleVisibility: .visible
        ) {
            Button(KXListingCopy.pickText(language, "知道了", "OK", "Got it"), role: .cancel) {}
        } message: {
            Text(quotaExhaustedMessage ?? KXListingCopy.pickText(
                language,
                "你本月的免费发布次数已用完，下月 1 日自动重置。",
                "今月の無料投稿枠を使い切りました。翌月1日に自動でリセットされます。",
                "You've used this month's free listings. Your quota resets on the 1st of next month."
            ))
        }
    }

    private var membershipGateTitle: String {
        switch listingType {
        case "rental": return KXListingCopy.pickText(language, "发布房源需要 Machi 会员", "物件掲載には Machi メンバーが必要", "Listing rentals needs Machi membership")
        case "job", "hiring": return KXListingCopy.pickText(language, "发布招聘需要 Machi 会员", "求人掲載には Machi メンバーが必要", "Posting jobs needs Machi membership")
        case "local_service": return KXListingCopy.pickText(language, "发布服务需要 Machi 会员", "サービス掲載には Machi メンバーが必要", "Listing services needs Machi membership")
        case "discount": return KXListingCopy.pickText(language, "发布优惠需要 Machi 会员", "クーポン掲載には Machi メンバーが必要", "Posting deals needs Machi membership")
        default: return KXListingCopy.pickText(language, "发布该信息需要 Machi 会员", "掲載には Machi メンバーが必要", "This listing needs Machi membership")
        }
    }

    private var membershipGateMessage: String {
        KXListingCopy.pickText(
            language,
            "认证会员可获得高信任发布权限与认证标识。开通后即可发布。",
            "認証メンバーになると、高信頼の掲載権限と認証バッジが付与されます。",
            "Verified members get high-trust posting and a verified badge. Upgrade to publish."
        )
    }

    /// Prominent, tappable notice shown at the top of the form for a non-member
    /// on a gated type — so they learn the requirement before filling it all in.
    private var membershipBanner: some View {
        Button { showMembershipGate = true } label: {
            HStack(spacing: KXSpacing.md) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(KXColor.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(membershipGateTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(KXListingCopy.pickText(language, "开通认证会员即可发布本类型，并获得认证标识", "メンバー登録でこのカテゴリを投稿でき、認証バッジも付きます", "Become a verified member to post in this channel"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(KXColor.accent.opacity(0.3), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    /// #6: shown to a member on a gated type — this month's remaining high-trust
    /// publish allowance for the current group. A depleted count reads as a clear
    /// "used up, resets next month" instead of a silent failure at submit.
    private func listingQuotaBanner(_ remaining: Int) -> some View {
        let depleted = remaining <= 0
        return HStack(spacing: 10) {
            Image(systemName: depleted ? "calendar.badge.exclamationmark" : "checkmark.seal.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(depleted ? KXColor.heat : KXColor.accent)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(depleted
                     ? KXListingCopy.pickText(language, "本月该类型发布额度已用完", "今月のこのカテゴリの投稿枠を使い切りました", "This month's quota for this type is used up")
                     : KXListingCopy.pickText(language, "本月还可发布 \(remaining) 条", "今月はあと \(remaining) 件投稿できます", "\(remaining) posts left this month"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(KXListingCopy.pickText(language, "高信任发布额度每组每月 3 条，次月 1 日重置。", "高信頼投稿枠は各カテゴリ月3件、翌月1日にリセットされます。", "High-trust posting is 3 per group each month, resetting on the 1st."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((depleted ? KXColor.heat : KXColor.accent).opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke((depleted ? KXColor.heat : KXColor.accent).opacity(0.25), lineWidth: 0.8))
    }

    /// Clears the per-listing fields so the user can immediately publish another
    /// in the same region (keeps 发布地区 + media-less form).
    private func resetFormForAnother() {
        title = ""; price = ""; location = ""; description = ""
        category = ""; station = ""; area = ""; serviceArea = ""
        mediaDrafts = []; uploadedMedia = [:]; existingMedia = []
        mediaUploadPhases = [:]; pickerItems = []
        message = nil
    }

    /// 发布地区 card — the structured region this listing files under. Shows the
    /// flag + 都道府县 · 市区町村, explains it drives the top region filter / city
    /// channel, and lets the user keep the current location or change cities.
    /// Deliberately distinct from the free-text 展示位置 field below (车站/地址…).
    private var publishRegionCard: some View {
        KXListingSection(title: KXListingCopy.pickText(language, "发布地区", "公開エリア", "Publish area"), icon: "mappin.circle.fill") {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                HStack(spacing: KXSpacing.md) {
                    Text(region?.countryEmoji ?? "🌐")
                        .font(.system(size: 30))
                        .frame(width: 46, height: 46)
                        .background(KXColor.softBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(region.map { KaiXRegionDirectory.localizedHeaderLabel($0, language: language) }
                             ?? KXListingCopy.pickText(language, "尚未选择城市", "都市が未選択", "No city selected"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(KXListingCopy.pickText(language,
                                                    "发布后会进入该城市频道，并可被顶部地区筛选命中。",
                                                    "投稿後はこの都市チャンネルに入り、上部のエリア絞り込みに表示されます。",
                                                    "Files into this city channel and shows up in the top region filter."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    Button {
                        selectedRegion = RegionStore.shared.current ?? selectedRegion
                    } label: {
                        Label(KXListingCopy.pickText(language, "使用当前位置", "現在地を使う", "Use current"), systemImage: "location.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(KXColor.accent)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .frame(maxWidth: .infinity)
                            .background(KXColor.accent.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        isShowingRegionPicker = true
                    } label: {
                        Label(KXListingCopy.pickText(language, "更换城市", "都市を変更", "Change city"), systemImage: "arrow.left.arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .frame(maxWidth: .infinity)
                            .background(KXColor.softBackground.opacity(0.9), in: Capsule())
                            .overlay(Capsule().stroke(KXColor.separator.opacity(0.6), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var createHeader: some View {
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
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(isEditing ? KXListingCopy.pickText(language, "编辑发布", "投稿を編集", "Edit listing") : KXListingCopy.createTitle(for: listingType, language))
                    .font(.headline.weight(.semibold))
                Text(region.map { KaiXRegionDirectory.localizedHeaderLabel($0, language: language) } ?? KXListingCopy.pickText(language, "选择城市后发布", "都市を選んで投稿", "Choose a city to post"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, KXSpacing.sm)
        .padding(.bottom, KXSpacing.md)
        .kxGlassBar(ignoresTopSafeArea: true)
        .overlay(alignment: .bottom) { Divider().opacity(0.18) }
    }

    private var createHero: some View {
        let progress = requiredProgress
        return HStack(alignment: .top, spacing: KXSpacing.md) {
            Image(systemName: KXListingCopy.icon(for: listingType))
                .font(.title3.weight(.bold))
                .foregroundStyle(typeAccent)
                .frame(width: 52, height: 52)
                .background(typeAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: KXSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(isEditing ? KXListingCopy.pickText(language, "完善并保存修改", "内容を整えて保存", "Review and save changes") : KXListingCopy.createTitle(for: listingType, language))
                        .font(.title3.weight(.black))
                    Spacer()
                    Text("\(progress.done)/\(progress.total)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(typeAccent)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(typeAccent.opacity(0.10), in: Capsule())
                }
                Text(KXListingCopy.createGuidance(for: listingType, language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .tint(typeAccent)
            }
        }
        .padding(KXSpacing.lg)
        .kxGlassSurface(radius: KXRadius.hero, elevated: true)
    }

    private var photoSection: some View {
        KXListingSection(title: KXListingCopy.pickText(language, "图片与视频", "写真・動画", "Photos & video"), icon: "photo.on.rectangle") {
            VStack(alignment: .leading, spacing: KXSpacing.md) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: imageLimit, matching: .any(of: [.images, .videos])) {
                    HStack(spacing: KXSpacing.md) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(typeAccent)
                            .frame(width: 42, height: 42)
                            .background(typeAccent.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: KXSpacing.xs) {
                            Text(mediaDrafts.isEmpty ? KXListingCopy.pickText(language, "添加图片或视频", "写真または動画を追加", "Add photos or video") : KXListingCopy.pickText(language, "继续添加媒体", "メディアを追加", "Add more media"))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(KXListingCopy.pickText(language, "最多 \(imageLimit) 个媒体，其中最多 1 个视频，第一项作为封面。避免包含身份证、护照等敏感信息。", "最大 \(imageLimit) 件まで、動画は 1 件まで。最初のメディアがカバーになります。身分証やパスポートなどの個人情報は入れないでください。", "Up to \(imageLimit) media files, including at most 1 video. The first item becomes the cover. Avoid IDs, passports, or sensitive information."))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(KXSpacing.md)
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                    .background(KXColor.softBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(typeAccent.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    }
                }
                .buttonStyle(.plain)

                if !existingMedia.isEmpty || !mediaDrafts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(existingMedia.enumerated()), id: \.element.id) { index, item in
                                ZStack {
                                    MediaImageView(url: URL(string: item.thumbnail_url ?? item.thumbnailUrl ?? item.url))
                                    if (item.media_type ?? item.mediaType ?? item.type) == "video" {
                                        Image(systemName: "play.fill")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 38, height: 38)
                                            .background(.black.opacity(0.58), in: Circle())
                                    }
                                }
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .overlay(alignment: .topLeading) {
                                    Text(index == 0 ? KXListingCopy.pickText(language, "封面", "カバー", "Cover") : "\(index + 1)")
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .frame(height: 20)
                                        .background(.black.opacity(0.52), in: Capsule())
                                        .padding(7)
                                }
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            existingMedia.removeAll { $0.id == item.id }
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(.primary)
                                            .frame(width: 28, height: 28)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L("delete", language))
                                    .padding(6)
                                }
                            }
                            ForEach(Array(mediaDrafts.enumerated()), id: \.element.id) { index, draft in
                                ZStack {
                                    if let image = UIImage(contentsOfFile: draft.thumbnailURL.path) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Color.secondary.opacity(0.12)
                                    }
                                    if draft.type == .video {
                                        Image(systemName: "play.fill")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 38, height: 38)
                                            .background(.black.opacity(0.58), in: Circle())
                                    }
                                }
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .overlay(alignment: .topLeading) {
                                    Text(existingMedia.isEmpty && index == 0 ? KXListingCopy.pickText(language, "封面", "カバー", "Cover") : "\(existingMedia.count + index + 1)")
                                        .font(.caption2.weight(.black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .frame(height: 20)
                                        .background(.black.opacity(0.52), in: Capsule())
                                        .padding(7)
                                }
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            mediaDrafts.removeAll { $0.id == draft.id }
                                            mediaUploadPhases.removeValue(forKey: draft.id)
                                            uploadedMedia.removeValue(forKey: draft.id)
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.black))
                                            .foregroundStyle(.primary)
                                            .frame(width: 28, height: 28)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L("delete", language))
                                    .padding(6)
                                }
                                .overlay(alignment: .bottom) {
                                    if let phase = mediaUploadPhases[draft.id], phase != .idle {
                                        Text(phase.label(language))
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(phase.isFailure ? KXColor.heat : .white)
                                            .lineLimit(1)
                                            .padding(.horizontal, 7)
                                            .frame(height: 22)
                                            .frame(maxWidth: .infinity)
                                            .background(.black.opacity(0.58))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var basicInfoSection: some View {
        KXListingSection(title: KXListingCopy.pickText(language, "基本信息", "基本情報", "Basic info"), icon: "square.and.pencil") {
            VStack(spacing: KXSpacing.md) {
                KXListingFormField(title: KXListingCopy.pickText(language, "标题", "タイトル", "Title"), placeholder: KXListingCopy.titlePlaceholder(for: listingType, language), icon: "text.cursor", text: $title)
                KXListingFormField(title: KXListingCopy.pickText(language, "分类", "カテゴリ", "Category"), placeholder: KXListingCopy.categoryPlaceholder(for: listingType, language), icon: "square.grid.2x2", text: categoryBinding)
                listingCategorySelector
                KXListingFormField(title: listingType == "rental" ? KXListingCopy.pickText(language, "租金", "家賃", "Rent") : KXListingCopy.pickText(language, "价格", "価格", "Price"), placeholder: KXListingCopy.pricePlaceholder(for: listingType, language), icon: "yensign.circle", text: $price, keyboard: .decimalPad)
                // 展示位置 (business location, free text) — NOT the publish region.
                // Channel-specific label so it reads as a real-world spot, not an
                // area filter. The structured region lives in the 发布地区 card above.
                KXListingFormField(title: locationFieldTitle, placeholder: locationFieldPlaceholder, icon: "mappin.and.ellipse", text: $location)
                KXListingFormField(title: KXListingCopy.pickText(language, "描述", "説明", "Description"), placeholder: KXListingCopy.descriptionPlaceholder(for: listingType, language), icon: "text.alignleft", text: $description, lineLimit: 4...8)
            }
        }
    }

    @ViewBuilder
    private var listingCategorySelector: some View {
        if listingType == "local_service" {
            serviceCreateCategorySelector
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(publishCategoryValues, id: \.self) { chip in
                        Button {
                            category = chip
                        } label: {
                            Text(taxonomyCategoryLabel(chip))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(category == chip ? Color.white : .primary)
                                .padding(.horizontal, 11)
                                .frame(height: 28)
                                .background(category == chip ? KXColor.accent : KXColor.softBackground.opacity(0.88), in: Capsule())
                                .overlay(Capsule().stroke(category == chip ? Color.clear : KXColor.separator.opacity(0.6), lineWidth: 0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var serviceCreateCategorySelector: some View {
        let activeSection = activeServiceCreateSection
        return VStack(alignment: .leading, spacing: 10) {
            Label(KXListingCopy.pickText(language, "一级分类", "大カテゴリ", "Primary category"), systemImage: "square.grid.3x3")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KXSpacing.sm) {
                    ForEach(KXListingCopy.serviceCreateSections) { section in
                        let isSelected = activeSection.id == section.id
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                selectServiceCreateSection(section)
                            }
                        } label: {
                            HStack(spacing: KXSpacing.sm) {
                                Image(systemName: section.icon)
                                    .font(.caption.weight(.black))
                                Text(section.label(language))
                                    .font(.caption.weight(.black))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSelected ? Color.white : KXColor.livingInk)
                            .padding(.horizontal, 13)
                            .frame(height: 38)
                            .background(isSelected ? KXColor.livingInk : KXColor.softBackground.opacity(0.88), in: Capsule())
                            .overlay(Capsule().stroke(isSelected ? Color.clear : KXColor.separator.opacity(0.65), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(alignment: .top, spacing: KXSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(typeAccent)
                    .frame(width: 18, height: 18)
                Text(activeSection.subtitle(language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(typeAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Label(KXListingCopy.pickText(language, "二级分类", "サブカテゴリ", "Subcategory"), systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: KXSpacing.sm) {
                ForEach(serviceCategories(for: activeSection), id: \.self) { chip in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            applyServiceCategory(chip)
                        }
                    } label: {
                        Text(taxonomyCategoryLabel(chip))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(category == chip ? Color.white : .primary)
                            .padding(.horizontal, KXSpacing.md)
                            .frame(height: 34)
                            .background(category == chip ? typeAccent : KXColor.softBackground.opacity(0.82), in: Capsule())
                            .overlay(Capsule().stroke(category == chip ? Color.clear : KXColor.separator.opacity(0.58), lineWidth: 0.65))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var safetySection: some View {
        KXListingSection(title: KXListingCopy.pickText(language, "安全确认", "安全確認", "Safety check"), icon: "shield.checkered") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(KXListingCopy.safetyTips(for: listingType, language), id: \.self) { tip in
                    KXListingHintRow(text: tip, icon: "checkmark.circle.fill", tint: KXColor.accent)
                }
                KXListingHintRow(
                    text: KXListingCopy.pickText(language, "Machi 只做信息发布、联系、收藏、举报和审核，不代收交易款、押金或保证金。", "Machi は情報掲載、連絡、保存、通報、審査のみを行い、取引代金・敷金・保証金は預かりません。", "Machi only supports listing, contact, saving, reporting, and review. It does not hold payments, deposits, or guarantees."),
                    icon: "exclamationmark.triangle.fill",
                    tint: KXColor.heat
                )
            }
        }
    }

    @ViewBuilder
    private var validationInlineHint: some View {
        if !canSubmit {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: hasBlockingMediaUpload ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(hasBlockingMediaUpload ? KXColor.heat : typeAccent)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(KXListingCopy.pickText(language, "还差一步", "あと一歩", "One more step"))
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.primary)
                    Text(hasBlockingMediaUpload ? KXListingCopy.pickText(language, "有媒体上传失败，请删除后重新选择。", "アップロードに失敗したメディアがあります。削除して選び直してください。", "Some media failed to upload. Remove it and choose again.") : missingRequiredCopy)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(KXSpacing.md)
            .background(typeAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(typeAccent.opacity(0.16), lineWidth: 0.8)
            }
        }
    }

    private var submitBar: some View {
        VStack(spacing: KXSpacing.sm) {
            if !canSubmit {
                Text(hasBlockingMediaUpload ? KXListingCopy.pickText(language, "有媒体上传失败，请删除后重新选择。", "アップロードに失敗したメディアがあります。削除して選び直してください。", "Some media failed to upload. Remove it and choose again.") : missingRequiredCopy)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                // Always ATTEMPT the publish: new accounts get a free first listing
                // of each gated type (server decides), so we must not pre-block.
                // If the server returns MEMBERSHIP_REQUIRED, submit() surfaces the
                // upgrade gate.
                Task { await submit() }
            } label: {
                HStack(spacing: KXSpacing.sm) {
                    if isSubmitting { KXSpinner(size: 18, lineWidth: 2.2, tint: .white) }
                    Text(isSubmitting ? KXListingCopy.pickText(language, "提交中", "送信中", "Submitting") : isEditing ? KXListingCopy.pickText(language, "保存修改", "変更を保存", "Save changes") : KXListingCopy.submitLabel(for: listingType, language))
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSubmit ? typeAccent : Color.secondary.opacity(0.18), in: Capsule())
                .foregroundStyle(canSubmit ? Color.white : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, KaiXTheme.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(KXColor.pageBackground.opacity(0.98))
        .overlay(alignment: .top) { Divider().opacity(0.16) }
    }

    @ViewBuilder
    private var typeFields: some View {
        if listingType == "rental" {
            KXListingSection(title: "房源信息", icon: "house") {
                VStack(spacing: KXSpacing.md) {
                    HStack(spacing: 10) {
                        KXListingFormField(title: "户型", placeholder: "1K / 2LDK", icon: "square.split.2x2", text: $layout)
                        KXListingFormField(title: "面积", placeholder: "24", icon: "ruler", text: $area, keyboard: .decimalPad)
                    }
                    KXListingFormField(title: "最近车站", placeholder: "例如 池袋站 步行 8 分钟", icon: "tram", text: $station)
                    KXListingFormField(title: "入住时间", placeholder: "例如 7 月上旬 / 即可入住", icon: "calendar", text: $moveIn)
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "可合租", icon: "person.2", isOn: $shareAllowed, tint: typeAccent)
                    }
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "家具家电", icon: "bed.double", isOn: $furnished, tint: typeAccent)
                    }
                    KXListingHintRow(text: "完整填写车站、面积和入住时间，能明显减少重复私信询问。", icon: "sparkles", tint: typeAccent)
                }
            }
        } else if listingType == "work" || listingType == "job" || listingType == "hiring" {
            KXListingSection(title: "职位信息", icon: "briefcase") {
                VStack(spacing: KXSpacing.md) {
                    KXListingFormField(title: "公司 / 店铺名", placeholder: "例如 新宿咖啡店 / 株式会社...", icon: "building.2", text: $companyName)
                    KXListingFormField(title: "工作时间", placeholder: "例如 周末 10:00-18:00", icon: "clock", text: $workingHours)
                    KXListingFormField(title: "休日休假", placeholder: "完全周休二日 / 轮班制", icon: "calendar", text: $jobHolidays)
                    KXListingFormField(title: "福利待遇", placeholder: "社保完备、员工餐、交通费支给", icon: "gift", text: $jobBenefits)
                    KXListingChoiceRow(title: "雇佣形式", icon: "person.text.rectangle", options: ["兼职", "全职", "派遣", "实习"], selection: $employmentType, tint: typeAccent)
                    KXListingChoiceRow(title: "日语要求", icon: "character.bubble", options: ["不限", "N5", "N4", "N3", "N2", "N1"], selection: $japaneseLevel, tint: typeAccent)
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "签证支持", icon: "checkmark.shield", isOn: $visaSupport, tint: typeAccent)
                        KXListingToggleChip(title: "无经验可", icon: "figure.wave", isOn: $noExperienceOK, tint: typeAccent)
                    }
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "留学生可", icon: "graduationcap", isOn: $studentOK, tint: typeAccent)
                        KXListingToggleChip(title: "可远程", icon: "laptopcomputer.and.iphone", isOn: $remoteOK, tint: typeAccent)
                    }
                }
            }
        } else if listingType == "local_service" {
            if let vertical = serviceVertical {
                KXListingSection(title: KXListingCopy.serviceVerticalLabel(vertical, language), icon: "calendar.badge.clock") {
                    VStack(spacing: KXSpacing.md) {
                        KXListingFormField(title: "服务方名称", placeholder: "个人 / 店铺 / 公司名称", icon: "person.crop.square", text: $serviceBusinessName)
                        KXListingChoiceRow(
                            title: "细分类 / 服务类型",
                            icon: "line.3.horizontal.decrease.circle",
                            options: KXListingCopy.serviceTypeOptions(for: vertical),
                            selection: Binding(get: { serviceType }, set: { applyServiceType($0) }),
                            tint: typeAccent
                        )

                        switch vertical {
                        case .foodRestaurant:
                            KXListingFormField(title: "服务范围", placeholder: "东京 23 区 / 店内用餐 / 外带自取", icon: "map", text: $serviceArea)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "营业时间", placeholder: "11:00-22:00 / 周一休", icon: "clock", text: $openHours)
                                KXListingFormField(title: "人均 / 价位", placeholder: "人均 ¥2,500-3,500", icon: "yensign.circle", text: $priceRange)
                            }
                            KXListingFormField(title: "最近车站", placeholder: "新宿站东口步行 5 分钟", icon: "tram", text: $nearStation)
                            KXListingFormField(title: "到店电话", placeholder: "03-1234-5678", icon: "phone", text: $storePhone)
                            KXListingToggleChip(title: "仅限预约制", icon: "calendar.badge.clock", isOn: $reservationRequired, tint: typeAccent)
                            KXListingFormField(title: "预约说明", placeholder: "如何预约、可预约时段、几人起订、是否需要定金", icon: "text.bubble", text: $reservationNote, lineLimit: 2...4)
                            KXListingFormField(title: "菜单（每行：菜名 | 价格 | 备注）", placeholder: "麻婆豆腐 | ¥980\n口水鸡 | ¥1,080 | 微辣", icon: "fork.knife", text: $menuText, lineLimit: 3...10)
                            KXListingFormField(title: "团购套餐（每行：套餐名 | 现价 | 原价 | 包含）", placeholder: "双人套餐 | ¥3,980 | ¥5,200 | 4菜1汤+2饮料", icon: "ticket", text: $packagesText, lineLimit: 3...8)
                            KXListingFormField(title: "服务语言", placeholder: "中文 / 日文 / 英文", icon: "character.bubble", text: $languages)
                            KXListingToggleChip(title: "认证商家", icon: "checkmark.seal", isOn: $certifiedProvider, tint: typeAccent)

                        case .diningBooking:
                            KXListingFormField(title: "服务范围", placeholder: "东京 23 区 / 线上预约 / 到店点评", icon: "map", text: $serviceArea)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "营业时间", placeholder: "11:00-22:00 / 周一休", icon: "clock", text: $openHours)
                                KXListingFormField(title: "价格区间", placeholder: "人均 ¥2,500-3,500", icon: "yensign.circle", text: $priceRange)
                            }
                            KXListingFormField(title: "最近车站", placeholder: "新宿站东口步行 5 分钟", icon: "tram", text: $nearStation)
                            KXListingFormField(title: "到店电话", placeholder: "03-1234-5678", icon: "phone", text: $storePhone)
                            KXListingFormField(title: "可预约时间", placeholder: "平日晚上 / 周末 / 需提前 2 天", icon: "calendar.badge.clock", text: $availability)
                            KXListingToggleChip(title: "仅限预约制", icon: "calendar.badge.clock", isOn: $reservationRequired, tint: typeAccent)
                            KXListingFormField(title: "预约说明", placeholder: "如何预约、可预约时段、几人起订、是否需要定金", icon: "text.bubble", text: $reservationNote, lineLimit: 2...4)
                            KXListingFormField(title: "服务流程", placeholder: "预约确认、到店、点评或优惠使用流程", icon: "list.bullet.clipboard", text: $serviceProcess, lineLimit: 3...6)
                            KXListingFormField(title: "取消/退款规则", placeholder: "例如 前一天可取消，定金不可退请写清", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)
                            KXListingFormField(title: "服务语言", placeholder: "中文 / 日文 / 英文", icon: "character.bubble", text: $languages)
                            KXListingToggleChip(title: "认证服务方", icon: "checkmark.seal", isOn: $certifiedProvider, tint: typeAccent)

                        case .lodging:
                            HStack(spacing: 10) {
                                KXListingFormField(title: "房型", placeholder: "大床房 / 双床房 / 整套民宿", icon: "bed.double", text: $roomType)
                                KXListingFormField(title: "可住人数", placeholder: "2", icon: "person.2", text: $maxGuests, keyboard: .numberPad)
                            }
                            KXListingFormField(title: "每晚/起步价格", placeholder: "每晚 / 每人 / 预约咨询", icon: "yensign.circle", text: $priceUnit)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "入住时间", placeholder: "15:00", icon: "arrow.right.to.line", text: $checkInTime)
                                KXListingFormField(title: "退房时间", placeholder: "10:00", icon: "arrow.left.to.line", text: $checkOutTime)
                            }
                            KXListingFormField(title: "最少入住晚数", placeholder: "1 晚 / 2 晚起", icon: "moon.stars", text: $minimumStay)
                            KXListingFormField(title: "设施服务", placeholder: "Wi-Fi、厨房、洗衣机、停车场、温泉、行李寄存", icon: "sparkles", text: $amenities, lineLimit: 2...4)
                            KXListingFormField(title: "房量与日期说明", placeholder: "可订日期、剩余房量、旺季限制、儿童入住规则", icon: "calendar", text: $inventoryNote, lineLimit: 2...5)
                            HStack(spacing: 10) {
                                KXListingToggleChip(title: "含早餐", icon: "cup.and.saucer", isOn: $breakfastIncluded, tint: typeAccent)
                                KXListingToggleChip(title: "即时确认", icon: "bolt", isOn: $instantConfirmation, tint: typeAccent)
                            }
                            KXListingFormField(title: "取消规则", placeholder: "入住前几天可取消、旺季不可退等", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)
                            KXListingFormField(title: "资质/许可说明", placeholder: "旅馆业许可 / 民泊备案 / 可接待范围", icon: "checkmark.shield", text: $licenseNote, lineLimit: 2...4)

                        case .attractionTicket, .dayTour:
                            KXListingFormField(title: "票种", placeholder: vertical == .dayTour ? "成人 / 儿童 / 私人团 / 拼团" : "成人票 / 儿童票 / 套票 / 电子票", icon: "ticket", text: $ticketType)
                            KXListingFormField(title: "日期 / 有效期", placeholder: "指定日期 / 购买后 30 天有效 / 每周六出发", icon: "calendar.badge.clock", text: $availability)
                            KXListingFormField(title: "时长", placeholder: vertical == .dayTour ? "约 8 小时" : "约 2 小时 / 当日有效", icon: "clock", text: $duration)
                            KXListingFormField(title: "集合地点", placeholder: "新宿站西口 / 景区入口 / 酒店接送范围", icon: "mappin.and.ellipse", text: $meetingPoint)
                            KXListingFormField(title: "包含内容", placeholder: "门票、导览、交通、餐食等", icon: "checklist", text: $includedItems, lineLimit: 2...5)
                            KXListingFormField(title: "不包含内容", placeholder: "个人消费、餐饮、保险等", icon: "minus.circle", text: $notIncluded, lineLimit: 2...5)
                            KXListingFormField(title: "用户需准备", placeholder: "护照、证件、舒适鞋、雨具等", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            if vertical == .dayTour {
                                KXListingToggleChip(title: "含酒店接送", icon: "bus", isOn: $pickupService, tint: typeAccent)
                            }
                            KXListingFormField(title: "取消规则", placeholder: "票务不可退 / 出发前 3 天可取消", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)
                            KXListingFormField(title: "资质/许可说明", placeholder: "票务来源、旅行资质、保险或导游说明", icon: "checkmark.shield", text: $licenseNote, lineLimit: 2...4)

                        case .airportTransfer:
                            KXListingFormField(title: "机场/路线", placeholder: "成田机场 - 东京 23 区 / 羽田 - 横滨", icon: "airplane", text: $airportRoute)
                            KXListingFormField(title: "服务范围", placeholder: "可接送区域、是否支持跨县、夜间范围", icon: "map", text: $serviceArea)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "车型", placeholder: "轿车 / Alphard / Hiace", icon: "car", text: $vehicleType)
                                KXListingFormField(title: "人数", placeholder: "4", icon: "person.2", text: $passengerCount, keyboard: .numberPad)
                            }
                            KXListingFormField(title: "行李数", placeholder: "2 个 28 寸 + 2 个随身", icon: "suitcase", text: $luggageCount)
                            KXListingFormField(title: "航班号说明", placeholder: "是否需要航班号、延误如何处理", icon: "airplane.arrival", text: $flightInfoNote, lineLimit: 2...4)
                            KXListingFormField(title: "等待规则", placeholder: "免费等待 60 分钟，超时每 30 分钟加收", icon: "timer", text: $waitingRule, lineLimit: 2...4)
                            KXListingFormField(title: "夜间/追加费用", placeholder: "夜间、儿童座椅、大件行李、高速费说明", icon: "moon.stars", text: $surchargeNote, lineLimit: 2...4)
                            KXListingFormField(title: "取消规则", placeholder: "出发前多久可取消，临时取消费用", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)

                        case .paperworkTranslation:
                            KXListingFormField(title: "服务语言", placeholder: "中日 / 中英 / 日英 / 多语言", icon: "character.bubble", text: $languages)
                            KXListingFormField(title: "文件/手续类型", placeholder: "住民票翻译 / 签证材料 / 租房申请 / 电话代沟通", icon: "doc.text", text: $documentType)
                            KXListingFormField(title: "所需材料", placeholder: "护照、在留卡、原文件、申请表等", icon: "folder.badge.plus", text: $requiredMaterials, lineLimit: 2...5)
                            KXListingFormField(title: "交付时间", placeholder: "最快当天 / 2-3 个工作日 / 加急另议", icon: "clock.badge.checkmark", text: $deliveryTime)
                            KXListingFormField(title: "服务流程", placeholder: "资料确认、报价、翻译/代办、交付方式", icon: "list.bullet.clipboard", text: $serviceProcess, lineLimit: 3...6)
                            KXListingFormField(title: "用户需准备", placeholder: "需本人确认、签字、原件邮寄或线上提交的信息", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            KXListingToggleChip(title: "不保证结果", icon: "exclamationmark.shield", isOn: $noResultGuarantee, tint: typeAccent)
                            KXListingFormField(title: "资质/许可说明", placeholder: "行政书士、翻译资质、合作机构或免责声明", icon: "checkmark.shield", text: $licenseNote, lineLimit: 2...4)
                            KXListingFormField(title: "取消规则", placeholder: "开始处理后是否可退、材料错误如何处理", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)

                        case .movingCleaning:
                            KXListingFormField(title: "服务范围", placeholder: "东京 23 区 / 横滨 / 清洁可线上估价", icon: "map", text: $serviceArea)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "房型/面积", placeholder: "1K / 45 平 / 店铺 20 平", icon: "square.split.2x2", text: $propertySize)
                                KXListingFormField(title: "物品量", placeholder: "纸箱 20 个 / 大件 3 件", icon: "shippingbox", text: $itemVolume)
                            }
                            KXListingFormField(title: "车辆/人员", placeholder: "2 吨车 + 2 人 / 1 人上门", icon: "truck.box", text: $vehicleStaff)
                            KXListingFormField(title: "包含内容", placeholder: "搬运、拆装、基础清洁、垃圾袋等", icon: "checklist", text: $includedItems, lineLimit: 2...5)
                            KXListingFormField(title: "不包含内容", placeholder: "空调拆装、粗大垃圾处理、停车费等", icon: "minus.circle", text: $notIncluded, lineLimit: 2...5)
                            KXListingFormField(title: "用户需准备", placeholder: "提前打包、预约电梯、停车位、垃圾券等", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            KXListingFormField(title: "追加费用", placeholder: "楼梯、大件、远距离、夜间、停车费说明", icon: "plus.circle", text: $surchargeNote, lineLimit: 2...4)
                            KXListingFormField(title: "取消规则", placeholder: "预约前一天取消费、雨天改期等", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)

                        case .lifeSetup:
                            KXListingFormField(title: "服务区域", placeholder: "东京 23 区 / 横滨 / 线上协助", icon: "map", text: $serviceArea)
                            KXListingFormField(title: "服务类型", placeholder: "手机卡 / 网络 / 水电煤 / 地址登记", icon: "slider.horizontal.3", text: $setupType)
                            KXListingFormField(title: "所需材料", placeholder: "在留卡、护照、地址、银行卡、本人到场要求", icon: "folder.badge.plus", text: $requiredMaterials, lineLimit: 2...5)
                            KXListingFormField(title: "预计耗时", placeholder: "当天 / 1-3 个工作日 / 需预约窗口", icon: "clock.badge.checkmark", text: $deliveryTime)
                            KXListingFormField(title: "服务方式", placeholder: "线上确认材料、预约窗口、陪同办理或远程协助", icon: "list.bullet.clipboard", text: $serviceProcess, lineLimit: 3...6)
                            KXListingFormField(title: "用户需准备", placeholder: "证件原件、印章、现金、可接电话时间等", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            KXListingFormField(title: "不可承诺事项", placeholder: "不能保证运营商审核、开户结果、政府窗口受理或第三方时效", icon: "exclamationmark.shield", text: $cannotGuarantee, lineLimit: 2...5)
                            KXListingFormField(title: "价格说明", placeholder: "预约咨询 / ¥3,000 起 / 按事项报价", icon: "yensign.circle", text: $priceRange)
                            KXListingFormField(title: "取消规则", placeholder: "材料确认后、预约日前后取消与改期规则", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)

                        case .beautyHealth:
                            KXListingFormField(title: "服务区域 / 店铺位置", placeholder: "新宿 / 原宿 / 线上预约协助", icon: "map", text: $serviceArea)
                            KXListingFormField(title: "服务项目", placeholder: "剪发 / 美甲 / 按摩 / 体检预约协助", icon: "sparkles", text: $beautyService)
                            KXListingFormField(title: "可预约时间", placeholder: "平日晚间 / 周末 / 需提前 2 天", icon: "calendar.badge.clock", text: $availability)
                            HStack(spacing: 10) {
                                KXListingFormField(title: "价格区间", placeholder: "¥4,000 起 / 按项目报价", icon: "yensign.circle", text: $priceRange)
                                KXListingFormField(title: "服务时长", placeholder: "45 分钟 / 90 分钟", icon: "clock", text: $duration)
                            }
                            KXListingFormField(title: "注意事项", placeholder: "迟到规则、过敏史、禁忌提醒、预约前准备", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            KXListingFormField(title: "医疗免责声明", placeholder: "医疗相关仅做预约协助，不提供诊断、治疗承诺或医疗建议", icon: "cross.case", text: $medicalDisclaimer, lineLimit: 2...5)
                            KXListingFormField(title: "取消规则", placeholder: "24 小时内取消、迟到、改期等规则", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)

                        case .petFamily:
                            KXListingFormField(title: "服务区域", placeholder: "东京 23 区 / 到店 / 上门", icon: "map", text: $serviceArea)
                            KXListingFormField(title: "服务对象", placeholder: "小型犬 / 猫 / 儿童用品 / 家庭协助", icon: "person.2", text: $serviceTarget)
                            KXListingFormField(title: "可预约时间", placeholder: "平日晚上 / 周末 / 假期", icon: "calendar.badge.clock", text: $availability)
                            KXListingFormField(title: "价格说明", placeholder: "按小时 / 按天 / 预约咨询", icon: "yensign.circle", text: $priceRange)
                            KXListingFormField(title: "注意事项", placeholder: "宠物性格、疫苗、用品、紧急联系人、家庭规则", icon: "person.crop.circle.badge.questionmark", text: $userPrepare, lineLimit: 2...5)
                            KXListingFormField(title: "安全/资质说明", placeholder: "经验、保险、照看范围、不可服务边界", icon: "checkmark.shield", text: $licenseNote, lineLimit: 2...4)
                            KXListingFormField(title: "取消规则", placeholder: "预约前取消、临时变更、超时费用等", icon: "arrow.uturn.left.circle", text: $cancellationRule, lineLimit: 2...5)
                        }
                    }
                }
            } else {
                KXListingSection(title: "选择服务细分类", icon: "square.grid.2x2") {
                    KXListingHintRow(
                        text: "请先在基本信息里选择一个标准服务分类，例如 餐厅、景点门票、一日游、机场接送、翻译手续、搬家清洁、生活开通或美容健康。",
                        icon: "hand.tap",
                        tint: typeAccent
                    )
                }
            }
        } else if listingType == "discount" {
            KXListingSection(title: "商家优惠字段", icon: "tag") {
                VStack(spacing: KXSpacing.md) {
                    KXListingFormField(title: "商家名称", placeholder: "店铺 / 品牌 / 公司名称", icon: "storefront", text: $merchantName)
                    KXListingFormField(title: "优惠内容", placeholder: "例如 学生出示证件 9 折，套餐减 500 日元", icon: "tag", text: $discountInfo, lineLimit: 3...6)
                    KXListingFormField(title: "有效期", placeholder: "例如 2026-08-31", icon: "calendar", text: $validUntil)
                    KXListingFormField(title: "使用规则", placeholder: "适用门店、不可叠加、预约说明等", icon: "doc.text", text: $usageRules, lineLimit: 2...5)
                    KXListingToggleChip(title: "商家已认证", icon: "checkmark.seal", isOn: $merchantVerified, tint: typeAccent)
                }
            }
        } else {
            KXListingSection(title: "交易字段", icon: "shippingbox") {
                VStack(spacing: KXSpacing.md) {
                    KXListingChoiceRow(title: "发布类型", icon: "arrow.left.arrow.right.circle", options: ["出售", "免费送", "求购"], selection: $listingMode, tint: typeAccent)
                    KXListingFormField(title: "品牌 / 型号", placeholder: "可选，例如 日文配列键盘 / 白色书桌 / 13 寸笔记本", icon: "tag", text: $brandModel)
                    KXListingChoiceRow(title: "新旧程度", icon: "sparkles", options: ["全新", "几乎全新", "良好", "有使用痕迹", "可用"], selection: $condition, tint: typeAccent)
                    HStack(spacing: 10) {
                        KXListingFormField(title: "原价 / 参考价", placeholder: "可选，例如 28000", icon: "chart.line.uptrend.xyaxis", text: $originalPrice, keyboard: .decimalPad)
                        KXListingFormField(title: "购买时间", placeholder: "可选，例如 2025 年春", icon: "calendar", text: $purchaseTime)
                    }
                    KXListingFormField(title: "配件 / 包装", placeholder: "例如 原盒、充电器、说明书、保修卡", icon: "shippingbox.and.arrow.backward", text: $accessories)
                    KXListingFormField(title: "瑕疵 / 使用痕迹", placeholder: "如有划痕、缺件、维修史请提前说明；没有可写“无明显瑕疵”", icon: "exclamationmark.circle", text: $defectNote, lineLimit: 2...4)
                    KXListingFormField(title: "可交易时间", placeholder: "例如 平日 19:00 后 / 周末下午", icon: "calendar.badge.clock", text: $secondhandAvailableTime)
                    KXListingFormField(title: "取货 / 邮寄说明", placeholder: "例如 新宿站面交，邮寄需买家承担运费", icon: "shippingbox", text: $secondhandPickupNotes, lineLimit: 2...4)
                    HStack(spacing: 10) {
                        KXListingToggleChip(title: "自取 / 面交", icon: "person.2", isOn: $pickupAvailable, tint: typeAccent)
                        KXListingToggleChip(title: "可邮寄", icon: "shippingbox", isOn: $secondhandShippingAvailable, tint: typeAccent)
                    }
                    KXListingToggleChip(title: "价格可商量", icon: "arrow.left.arrow.right", isOn: $priceNegotiable, tint: typeAccent)
                    KXListingHintRow(text: "建议写清购买时间、瑕疵、配件、是否含包装和交易地点，减少来回确认。", icon: "lightbulb", tint: typeAccent)
                }
            }
        }
    }

    private func hydrateExistingListingIfNeeded() {
        guard !didHydrateExisting, let listing = existingListing else { return }
        didHydrateExisting = true
        title = listing.title
        category = listing.category ?? ""
        price = listing.price.map { String(format: $0.rounded() == $0 ? "%.0f" : "%.2f", $0) } ?? ""
        location = listing.location_text ?? listing.locationText ?? ""
        description = listing.description ?? ""
        existingMedia = listing.media ?? []

        let raw: (String) -> String = { key in
            listing.attributes?[key]?.listingDisplayValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let bool: (String) -> Bool = { key in
            if let value = listing.attributes?[key]?.boolValue { return value }
            return ["true", "1", "yes", "是", "可", "有", "available"].contains(raw(key).lowercased())
        }

        switch listing.type {
        case "rental":
            layout = raw("layout").isEmpty ? layout : raw("layout")
            area = raw("area_sqm")
            station = raw("nearest_station")
            moveIn = raw("move_in_date")
            shareAllowed = bool("share_allowed")
            shortTermAllowed = bool("short_term_allowed")
            furnished = bool("furnished")
        case "job", "hiring":
            companyName = raw("company_name")
            workingHours = raw("working_hours")
            employmentType = KXListingCopy.employmentTypeLabel(raw("employment_type"))
            japaneseLevel = raw("japanese_level").isEmpty ? japaneseLevel : raw("japanese_level")
            visaSupport = bool("visa_support")
            noExperienceOK = bool("no_experience_ok")
            studentOK = bool("student_ok")
            remoteOK = bool("remote_ok")
            jobHolidays = raw("holidays")
            jobBenefits = raw("benefits")
        case "local_service":
            serviceBusinessName = raw("business_name")
            serviceType = raw("service_type").isEmpty ? (listing.category ?? "") : raw("service_type")
            if category.isEmpty { category = serviceType }
            serviceArea = raw("service_area")
            priceUnit = raw("price_unit").isEmpty ? priceUnit : raw("price_unit")
            availability = raw("availability")
            certifiedProvider = bool("certified_provider")
            serviceProcess = raw("service_process")
            cancellationRule = raw("cancellation_rule")
            openHours = raw("open_hours")
            priceRange = raw("price_range")
            nearStation = raw("near_station")
            storePhone = raw("store_phone")
            reservationRequired = bool("reservation_required")
            reservationNote = raw("reservation_note")
            menuText = KXMerchantInput.menuLines(listing)
            packagesText = KXMerchantInput.packageLines(listing)
            languages = raw("languages")
            roomType = raw("room_type")
            maxGuests = raw("max_guests")
            checkInTime = raw("check_in_time").isEmpty ? checkInTime : raw("check_in_time")
            checkOutTime = raw("check_out_time").isEmpty ? checkOutTime : raw("check_out_time")
            minimumStay = raw("minimum_stay").isEmpty ? minimumStay : raw("minimum_stay")
            amenities = raw("amenities")
            inventoryNote = raw("inventory_note")
            breakfastIncluded = bool("breakfast_included")
            instantConfirmation = bool("instant_confirmation")
            ticketType = raw("ticket_type")
            duration = raw("duration")
            meetingPoint = raw("meeting_point")
            pickupService = bool("pickup_service")
            includedItems = raw("included_items")
            notIncluded = raw("not_included")
            userPrepare = raw("user_prepare")
            licenseNote = raw("license_note")
            airportRoute = raw("airport_route")
            vehicleType = raw("vehicle_type")
            passengerCount = raw("passenger_count")
            luggageCount = raw("luggage_count")
            flightInfoNote = raw("flight_info_note")
            waitingRule = raw("waiting_rule")
            surchargeNote = raw("surcharge_note")
            documentType = raw("document_type")
            requiredMaterials = raw("required_materials")
            deliveryTime = raw("delivery_time")
            noResultGuarantee = bool("no_result_guarantee")
            propertySize = raw("property_size")
            itemVolume = raw("item_volume")
            vehicleStaff = raw("vehicle_staff")
            setupType = raw("setup_type")
            cannotGuarantee = raw("cannot_guarantee")
            beautyService = raw("beauty_service")
            medicalDisclaimer = raw("medical_disclaimer")
            serviceTarget = raw("service_target")
        case "discount":
            merchantName = raw("merchant_name")
            discountInfo = raw("discount_info")
            validUntil = raw("valid_until")
            usageRules = raw("usage_rules")
            merchantVerified = bool("merchant_verified")
        default:
            listingMode = KXListingCopy.listingModeLabel(raw("listing_mode"))
            condition = KXListingCopy.conditionLabel(raw("condition"))
            brandModel = [raw("brand"), raw("model")].filter { !$0.isEmpty }.joined(separator: " / ")
            originalPrice = raw("original_price")
            priceNegotiable = bool("price_negotiable")
            purchaseTime = raw("purchase_time")
            accessories = raw("accessories")
            defectNote = raw("defect_note")
            secondhandAvailableTime = raw("available_time")
            secondhandPickupNotes = raw("pickup_note")
            pickupAvailable = bool("pickup_available")
            secondhandShippingAvailable = bool("shipping_available")
        }
    }

    private func loadImages(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var next = mediaDrafts
        var videoCount = mediaDrafts.filter { $0.type == .video }.count
        var imageCount = mediaDrafts.filter { $0.type == .image }.count
        var mediaCount = mediaDrafts.count
        var warning: String?
        for item in items.prefix(imageLimit) {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            do {
                guard mediaCount < imageLimit else {
                    warning = "媒体最多上传 \(imageLimit) 个，其中最多 1 个视频。"
                    continue
                }
                if isVideo {
                    guard videoCount < 1 else {
                        warning = "每条信息最多上传 1 个视频。"
                        continue
                    }
                    guard let picked = try? await item.loadTransferable(type: PickedVideoFile.self) else {
                        warning = "无法读取所选媒体，请重新选择。"
                        continue
                    }
                    guard fileByteCount(at: picked.url) <= (listingType == "rental" ? 300 * 1024 * 1024 : KaiXConfig.maxPostVideoSourceBytes) else {
                        warning = "视频文件过大，请压缩后重试。"
                        continue
                    }
                    let draft = try await UploadService.shared.prepareVideo(fileURL: picked.url, contentType: item.supportedContentTypes.first { $0.conforms(to: .movie) })
                    guard draft.duration <= (listingType == "rental" ? 600 : 300) else {
                        warning = listingType == "rental" ? "房源视频最长 10 分钟。" : "视频最长 5 分钟。"
                        continue
                    }
                    next.append(draft)
                    videoCount += 1
                    mediaCount += 1
                } else {
                    guard imageCount < imageLimit else {
                        warning = "图片最多上传 \(imageLimit) 张。"
                        continue
                    }
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        warning = "无法读取所选媒体，请重新选择。"
                        continue
                    }
                    let draft = try await UploadService.shared.prepareImage(data: data)
                    next.append(draft)
                    imageCount += 1
                    mediaCount += 1
                }
            } catch {
                warning = "媒体处理失败，请重新选择。"
            }
        }
        mediaDrafts = next
        mediaUploadPhases = Dictionary(uniqueKeysWithValues: next.map { ($0.id, uploadedMedia[$0.id] == nil ? .idle : .ready) })
        pickerItems = []
        if let warning { message = warning }
    }

    private func fileByteCount(at url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? Int.max
    }

    private func submit() async {
        guard let region else { return }
        isSubmitting = true
        message = nil
        do {
            var mediaIds = existingMedia.compactMap { $0.uploaded_file_id ?? $0.uploadedFileId }
            for draft in mediaDrafts {
                if let cached = uploadedMedia[draft.id] {
                    mediaIds.append(cached.id)
                    continue
                }
                mediaUploadPhases[draft.id] = .preparing
                let isVideo = draft.type == .video
                withAnimation(.easeInOut(duration: 0.2)) {
                    mediaUploadPhases[draft.id] = .uploading(0.45)
                }
                let media = try await UploadManager.shared.upload(
                    draft: draft,
                    purpose: listingUploadPurpose(isVideo: isVideo),
                    entityType: "listing"
                )
                mediaUploadPhases[draft.id] = .completing
                uploadedMedia[draft.id] = media
                withAnimation(.easeOut(duration: 0.2)) {
                    mediaUploadPhases[draft.id] = .ready
                }
                mediaIds.append(media.id)
            }
            let result: KaiXCityListingDTO
            if let existingListing {
                result = try await KaiXAPIClient.shared.updateListing(
                    existingListing.id,
                    title: title,
                    description: description,
                    category: category.isEmpty ? KXListingCopy.defaultCategory(for: listingType) : category,
                    price: Double(price),
                    locationText: location,
                    mediaIds: mediaIds,
                    attributes: attributes
                )
            } else {
                result = try await KaiXAPIClient.shared.createListing(
                    type: KXListingCopy.createType(for: listingType),
                    countryCode: region.countryCode,
                    citySlug: region.cityCode,
                    regionCode: region.regionCode,
                    language: language == .zh ? "zh-CN" : language.rawValue,
                    title: title,
                    description: description,
                    category: category.isEmpty ? KXListingCopy.defaultCategory(for: listingType) : category,
                    price: Double(price),
                    locationText: location,
                    mediaIds: mediaIds,
                    attributes: attributes
                )
            }
            let published = result.status == "published" || result.status == "active"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSubmitting = false
            message = nil
            // Proper success feedback instead of a 0.42s flash → jump. The sheet
            // surfaces type / title / 发布地区 / 展示位置 / status / time + actions.
            publishedReceipt = ListingPublishReceipt(
                listingId: result.id,
                isEditing: isEditing,
                published: published,
                typeLabel: KXListingCopy.createTitle(for: listingType, language),
                title: title.isEmpty ? KXListingCopy.displayTitle(result) : title,
                regionLabel: KaiXRegionDirectory.localizedHeaderLabel(region, language: language),
                locationText: location
            )
        } catch {
            if let api = error as? KaiXAPIError {
                // Non-member (or free first-listing allowance used up) → show the
                // membership upsell instead of a bottom error.
                if api.error.code == "MEMBERSHIP_REQUIRED" {
                    isSubmitting = false
                    showMembershipGate = true
                    return
                }
                // An ALREADY-paying member who exhausted this month's free quota.
                // Do NOT show the "Get membership" gate (they already have it) —
                // surface an informational notice that the quota resets next month.
                if api.error.code == "MEMBERSHIP_LISTING_QUOTA_EXCEEDED" {
                    isSubmitting = false
                    quotaExhaustedMessage = error.kaixUserMessage
                    showQuotaExhausted = true
                    return
                }
            }
            if let failed = mediaDrafts.first(where: {
                if case .uploading = mediaUploadPhases[$0.id] { return true }
                if case .completing = mediaUploadPhases[$0.id] { return true }
                if case .preparing = mediaUploadPhases[$0.id] { return true }
                return false
            }) {
                mediaUploadPhases[failed.id] = .failed(error.kaixUserMessage)
            }
            message = error.kaixUserMessage
            isSubmitting = false
        }
    }

    @MainActor
    private func openPublishedListing(_ listingId: String) {
        if let onPublishedListing {
            onPublishedListing(listingId)
            return
        }
        let targetTab = router.activeTab
        let detailRoute = KXRoute.cityListingDetail(listingId: listingId)
        if router.replaceTop(with: detailRoute, in: targetTab) {
            return
        }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            router.open(detailRoute, in: targetTab)
        }
    }

    private func listingUploadPurpose(isVideo: Bool) -> String {
        switch KXListingCopy.createType(for: listingType) {
        case "rental": return isVideo ? "rental_video" : "rental_image"
        case "job", "hiring": return isVideo ? "job_video" : "job_image"
        case "local_service": return isVideo ? "service_video" : "service_image"
        case "discount", "event": return isVideo ? "discount_video" : "discount_image"
        default: return isVideo ? "secondhand_video" : "secondhand_image"
        }
    }

    private var attributes: [String: KaiXAttributeValue] {
        if listingType == "rental" {
            return [
                "rent": .init(double: Double(price) ?? 0),
                "layout": .init(string: layout),
                "area_sqm": .init(double: Double(area) ?? 0),
                "nearest_station": .init(string: station),
                "move_in_date": .init(string: moveIn),
                "share_allowed": .init(bool: shareAllowed),
                "furnished": .init(bool: furnished),
            ]
        }
        if listingType == "work" || listingType == "job" || listingType == "hiring" {
            return [
                "salary_min": .init(double: Double(price) ?? 0),
                "salary_type": .init(string: "hourly"),
                "employment_type": .init(string: KXListingCopy.employmentTypeKey(employmentType)),
                "japanese_level": .init(string: japaneseLevel),
                // visa_support 是三态枚举（none/consult/available），与 Web 同一
                // 套 wire 值——存布尔会让 Web 端「签证支持」筛选永远匹配不到。
                "visa_support": .init(string: visaSupport ? "available" : "none"),
                "working_hours": .init(string: workingHours),
                "company_name": .init(string: companyName),
                "holidays": .init(string: jobHolidays),
                "benefits": .init(string: jobBenefits),
                "no_experience_ok": .init(bool: noExperienceOK),
                "student_ok": .init(bool: studentOK),
                "remote_ok": .init(bool: remoteOK),
            ]
        }
        if listingType == "local_service" {
            var result: [String: KaiXAttributeValue] = [
                "business_name": .init(string: serviceBusinessName),
                "service_type": .init(string: serviceType.isEmpty ? category : serviceType),
                "certified_provider": .init(bool: certifiedProvider),
            ]
            guard let vertical = serviceVertical else { return result }
            result["service_vertical"] = .init(string: vertical.rawValue)

            switch vertical {
            case .foodRestaurant:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["open_hours"] = .init(string: openHours)
                result["price_range"] = .init(string: priceRange)
                result["near_station"] = .init(string: nearStation)
                result["store_phone"] = .init(string: storePhone)
                result["reservation_required"] = .init(bool: reservationRequired)
                result["reservation_note"] = .init(string: reservationNote)
                result["languages"] = .init(string: languages)
                result["menu"] = .init(string: KXMerchantInput.encodeMenu(menuText))
                result["packages"] = .init(string: KXMerchantInput.encodePackages(packagesText))
            case .diningBooking:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["open_hours"] = .init(string: openHours)
                result["price_range"] = .init(string: priceRange)
                result["near_station"] = .init(string: nearStation)
                result["store_phone"] = .init(string: storePhone)
                result["availability"] = .init(string: availability)
                result["booking_required"] = .init(bool: reservationRequired)
                result["reservation_required"] = .init(bool: reservationRequired)
                result["reservation_note"] = .init(string: reservationNote)
                result["service_process"] = .init(string: serviceProcess)
                result["cancellation_rule"] = .init(string: cancellationRule)
                result["languages"] = .init(string: languages)
            case .lodging:
                result["room_type"] = .init(string: roomType)
                result["max_guests"] = .init(string: maxGuests)
                result["price_unit"] = .init(string: priceUnit)
                result["check_in_time"] = .init(string: checkInTime)
                result["check_out_time"] = .init(string: checkOutTime)
                result["minimum_stay"] = .init(string: minimumStay)
                result["amenities"] = .init(string: amenities)
                result["inventory_note"] = .init(string: inventoryNote)
                result["breakfast_included"] = .init(bool: breakfastIncluded)
                result["instant_confirmation"] = .init(bool: instantConfirmation)
                result["cancellation_rule"] = .init(string: cancellationRule)
                result["license_note"] = .init(string: licenseNote)
            case .attractionTicket:
                result["ticket_type"] = .init(string: ticketType)
                result["availability"] = .init(string: availability)
                result["duration"] = .init(string: duration)
                result["meeting_point"] = .init(string: meetingPoint)
                result["included_items"] = .init(string: includedItems)
                result["not_included"] = .init(string: notIncluded)
                result["user_prepare"] = .init(string: userPrepare)
                result["cancellation_rule"] = .init(string: cancellationRule)
                result["license_note"] = .init(string: licenseNote)
            case .dayTour:
                result["ticket_type"] = .init(string: ticketType)
                result["availability"] = .init(string: availability)
                result["duration"] = .init(string: duration)
                result["meeting_point"] = .init(string: meetingPoint)
                result["included_items"] = .init(string: includedItems)
                result["not_included"] = .init(string: notIncluded)
                result["user_prepare"] = .init(string: userPrepare)
                result["pickup_service"] = .init(bool: pickupService)
                result["cancellation_rule"] = .init(string: cancellationRule)
                result["license_note"] = .init(string: licenseNote)
            case .airportTransfer:
                result["airport_route"] = .init(string: airportRoute)
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["vehicle_type"] = .init(string: vehicleType)
                result["passenger_count"] = .init(string: passengerCount)
                result["luggage_count"] = .init(string: luggageCount)
                result["flight_info_note"] = .init(string: flightInfoNote)
                result["waiting_rule"] = .init(string: waitingRule)
                result["surcharge_note"] = .init(string: surchargeNote)
                result["cancellation_rule"] = .init(string: cancellationRule)
            case .paperworkTranslation:
                result["languages"] = .init(string: languages)
                result["document_type"] = .init(string: documentType)
                result["required_materials"] = .init(string: requiredMaterials)
                result["delivery_time"] = .init(string: deliveryTime)
                result["service_process"] = .init(string: serviceProcess)
                result["user_prepare"] = .init(string: userPrepare)
                result["no_result_guarantee"] = .init(bool: noResultGuarantee)
                result["license_note"] = .init(string: licenseNote)
                result["cancellation_rule"] = .init(string: cancellationRule)
            case .movingCleaning:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["property_size"] = .init(string: propertySize)
                result["item_volume"] = .init(string: itemVolume)
                result["vehicle_staff"] = .init(string: vehicleStaff)
                result["included_items"] = .init(string: includedItems)
                result["not_included"] = .init(string: notIncluded)
                result["user_prepare"] = .init(string: userPrepare)
                result["surcharge_note"] = .init(string: surchargeNote)
                result["cancellation_rule"] = .init(string: cancellationRule)
            case .lifeSetup:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["setup_type"] = .init(string: setupType)
                result["required_materials"] = .init(string: requiredMaterials)
                result["delivery_time"] = .init(string: deliveryTime)
                result["service_process"] = .init(string: serviceProcess)
                result["user_prepare"] = .init(string: userPrepare)
                result["cannot_guarantee"] = .init(string: cannotGuarantee)
                result["price_range"] = .init(string: priceRange)
                result["cancellation_rule"] = .init(string: cancellationRule)
            case .beautyHealth:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["beauty_service"] = .init(string: beautyService)
                result["price_range"] = .init(string: priceRange)
                result["availability"] = .init(string: availability)
                result["duration"] = .init(string: duration)
                result["user_prepare"] = .init(string: userPrepare)
                result["medical_disclaimer"] = .init(string: medicalDisclaimer)
                result["cancellation_rule"] = .init(string: cancellationRule)
            case .petFamily:
                result["service_area"] = .init(string: serviceArea.isEmpty ? location : serviceArea)
                result["service_target"] = .init(string: serviceTarget)
                result["availability"] = .init(string: availability)
                result["price_range"] = .init(string: priceRange)
                result["user_prepare"] = .init(string: userPrepare)
                result["cancellation_rule"] = .init(string: cancellationRule)
                result["license_note"] = .init(string: licenseNote)
            }
            return result
        }
        if listingType == "discount" {
            return [
                "merchant_name": .init(string: merchantName),
                "discount_info": .init(string: discountInfo),
                "valid_until": .init(string: validUntil),
                "usage_rules": .init(string: usageRules),
                "merchant_verified": .init(bool: merchantVerified),
            ]
        }
        return [
            "listing_mode": .init(string: KXListingCopy.listingModeKey(listingMode)),
            "brand": .init(string: brandModel),
            "condition": .init(string: KXListingCopy.conditionKey(condition)),
            "original_price": .init(string: originalPrice),
            "price_negotiable": .init(bool: priceNegotiable),
            "purchase_time": .init(string: purchaseTime),
            "accessories": .init(string: accessories),
            "defect_note": .init(string: defectNote),
            "available_time": .init(string: secondhandAvailableTime),
            "pickup_note": .init(string: secondhandPickupNotes),
            "delivery_method": .init(string: pickupAvailable ? (secondhandShippingAvailable ? "pickup_or_shipping" : "pickup") : (secondhandShippingAvailable ? "shipping" : "negotiable")),
            "pickup_available": .init(bool: pickupAvailable),
            "shipping_available": .init(bool: secondhandShippingAvailable),
        ]
    }
}

private struct KXListingFormField: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let placeholder: String
    let icon: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var lineLimit: ClosedRange<Int>?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(KXListingCopy.formText(title, language), systemImage: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            Group {
                if let lineLimit {
                    TextField(KXListingCopy.formText(placeholder, language), text: $text, axis: .vertical)
                        .lineLimit(lineLimit)
                } else {
                    TextField(KXListingCopy.formText(placeholder, language), text: $text)
                        .keyboardType(keyboard)
                }
            }
            .font(.subheadline.weight(.semibold))
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .padding(.horizontal, KXSpacing.md)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KXColor.softBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(KXColor.separator.opacity(0.58), lineWidth: 0.65)
            }
        }
    }
}

private struct KXListingChoiceRow: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let icon: String
    let options: [String]
    @Binding var selection: String
    var tint: Color = KXColor.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(KXListingCopy.formText(title, language), systemImage: icon)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            FlowLayout(spacing: KXSpacing.sm) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(KXListingCopy.formText(option, language))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selection == option ? Color.white : .primary)
                            .padding(.horizontal, KXSpacing.md)
                            .frame(height: 34)
                            .background(selection == option ? tint : KXColor.softBackground.opacity(0.82), in: Capsule())
                            .overlay(Capsule().stroke(selection == option ? Color.clear : KXColor.separator.opacity(0.58), lineWidth: 0.65))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KXListingToggleChip: View {
    @Environment(\.appLanguage) private var language
    let title: String
    let icon: String
    @Binding var isOn: Bool
    var tint: Color = KXColor.accent

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: KXSpacing.sm) {
                Image(systemName: isOn ? "checkmark.circle.fill" : icon)
                    .font(.subheadline.weight(.bold))
                Text(KXListingCopy.formText(title, language))
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isOn ? tint : .secondary)
            .padding(.horizontal, KXSpacing.md)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isOn ? tint.opacity(0.11) : KXColor.softBackground.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isOn ? tint.opacity(0.32) : KXColor.separator.opacity(0.58), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct KXListingHintRow: View {
    @Environment(\.appLanguage) private var language
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.sm) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
            Text(KXListingCopy.formText(text, language))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

