import Foundation
import SwiftUI

// Listing copy / localization tables and intake catalogs, extracted from
// DiscoverView.swift to shrink that file. Pure data + string helpers — no
// views, no private dependencies on Discover internals.
enum KXListingCopy {
    enum ServiceVertical: String, CaseIterable {
        case foodRestaurant = "food_restaurant"
        case diningBooking = "dining_booking"
        case lodging = "lodging"
        case attractionTicket = "attraction_ticket"
        case dayTour = "day_tour"
        case airportTransfer = "airport_transfer"
        case paperworkTranslation = "paperwork_translation"
        case movingCleaning = "moving_cleaning"
        case lifeSetup = "life_setup"
        case beautyHealth = "beauty_health"
        case petFamily = "pet_family"
    }

    struct ServiceCreateSection: Identifiable {
        let id: String
        let icon: String
        let zh: String
        let ja: String
        let en: String
        let subtitleZh: String
        let subtitleJa: String
        let subtitleEn: String
        let categories: [String]

        func label(_ language: AppLanguage) -> String {
            KXListingCopy.pickText(language, zh, ja, en)
        }

        func subtitle(_ language: AppLanguage) -> String {
            KXListingCopy.pickText(language, subtitleZh, subtitleJa, subtitleEn)
        }
    }

    /// 餐厅：菜系类目（与 web ListingKit FOOD_CATEGORIES 同步）。
    static let foodCategories = ["中华料理", "日本料理", "居酒屋", "烧肉火锅", "拉面", "寿司海鲜", "咖啡甜品", "西餐", "韩国料理"]
    static let legacyFoodCategories = ["餐厅美食", "餐饮预约"]
    static let foodSectionCategories = ["餐厅"] + foodCategories + ["优惠预约"]
    static let foodFilterCategories = foodSectionCategories + legacyFoodCategories
    static let lodgingSectionCategories = ["民宿"]
    static let travelSectionCategories = ["景点门票", "一日游", "本地向导", "体验活动", "包车行程"]
    static let transferSectionCategories = ["机场接送", "车站接送", "包车", "行李协助"]
    static let paperworkSectionCategories = ["材料翻译", "市役所陪同", "银行卡协助", "手机卡协助", "租房申请协助", "签证材料整理"]
    static let movingSectionCategories = ["搬家", "退房清洁", "粗大垃圾协助", "行李搬运", "家具家电配送协助"]
    static let lifeSetupSectionCategories = ["手机卡开通", "网络开通", "水电煤协助", "地址登记协助", "粗大垃圾预约", "生活跑腿", "生活支持"]
    static let beautyHealthSectionCategories = ["美容美发", "美甲", "按摩", "皮肤管理", "体检/牙科预约协助"]
    static let petFamilySectionCategories = ["宠物寄养", "遛狗", "临时照看", "儿童用品租赁", "家庭协助", "宠物服务"]
    static let serviceCreateSections: [ServiceCreateSection] = [
        .init(
            id: "food",
            icon: "fork.knife",
            zh: "餐厅",
            ja: "飲食店",
            en: "Restaurants",
            subtitleZh: "餐厅、居酒屋、咖啡甜品和优惠预约只填写到店、菜单、套餐和取消规则。",
            subtitleJa: "飲食店、居酒屋、カフェ、予約特典は来店予約・メニュー・セット・取消規定を入力します。",
            subtitleEn: "Restaurants, cafes and booking deals use dining, menu, set and cancellation fields.",
            categories: foodSectionCategories
        ),
        // 民宿必须有自己的一级分区:民宿 tab 的「+」路由到本表单,而
        // activeTaxonomyCategories 会过滤掉住宿类目(isStayCategory),没有
        // 这个分区,用户只能在自由文本框逐字输入简体「民宿」才能发布——
        // 日/英用户完全无路可走(serviceCreateSectionKey 的 "lodging" 也曾悬空)。
        .init(
            id: "lodging",
            icon: "bed.double",
            zh: "民宿",
            ja: "民泊・宿泊",
            en: "Stays",
            subtitleZh: "民宿与住宿填写房型、可住人数、入住退房时间、房量与取消规则。",
            subtitleJa: "民泊・宿泊は部屋タイプ、定員、チェックイン・アウト、空室状況、取消規定を入力します。",
            subtitleEn: "Stays use room type, guests, check-in/out, availability and cancellation fields.",
            categories: lodgingSectionCategories
        ),
        .init(
            id: "travel",
            icon: "map",
            zh: "旅行票务",
            ja: "旅行・チケット",
            en: "Travel",
            subtitleZh: "景点门票、一日游、向导和体验活动填写日期、人数、时长、集合地点和包含内容。",
            subtitleJa: "チケット、日帰り、ガイド、体験は日付、人数、所要時間、集合場所、含まれる内容を入力します。",
            subtitleEn: "Tickets, tours and experiences use date, guests, duration, meeting point and inclusion fields.",
            categories: travelSectionCategories
        ),
        .init(
            id: "transfer",
            icon: "car",
            zh: "接送交通",
            ja: "送迎・交通",
            en: "Transfers",
            subtitleZh: "机场、车站、包车和行李协助填写路线、车型、人数、行李、等待与追加费用规则。",
            subtitleJa: "空港・駅送迎、貸切、荷物サポートはルート、車種、人数、荷物、待機・追加料金を入力します。",
            subtitleEn: "Transfers use route, vehicle, passenger, luggage, waiting and surcharge fields.",
            categories: transferSectionCategories
        ),
        .init(
            id: "paperwork",
            icon: "doc.text",
            zh: "翻译手续",
            ja: "翻訳・手続き",
            en: "Paperwork",
            subtitleZh: "材料翻译、市役所、银行卡、手机卡和租房/签证材料整理必须写清材料、流程与不可承诺事项。",
            subtitleJa: "翻訳、役所、銀行、SIM、賃貸・ビザ書類は必要書類、流れ、保証できない事項を明記します。",
            subtitleEn: "Paperwork help must state required materials, workflow and no-result-guarantee boundaries.",
            categories: paperworkSectionCategories
        ),
        .init(
            id: "moving",
            icon: "shippingbox",
            zh: "搬家清洁",
            ja: "引越し・清掃",
            en: "Moving",
            subtitleZh: "搬家、退房清洁、粗大垃圾和配送协助填写面积、物品量、车辆人员、包含内容和追加费用。",
            subtitleJa: "引越し、退去清掃、粗大ごみ、配送補助は広さ、物量、車両人員、含まれる内容、追加料金を入力します。",
            subtitleEn: "Moving and cleaning use size, volume, vehicle/staff, inclusions and surcharge fields.",
            categories: movingSectionCategories
        ),
        .init(
            id: "life",
            icon: "house",
            zh: "生活开通",
            ja: "生活手続き",
            en: "Life setup",
            subtitleZh: "手机卡、网络、水电煤、地址登记、粗大垃圾预约和生活跑腿填写材料、耗时、方式与不可承诺事项。",
            subtitleJa: "SIM、ネット、ライフライン、住所登録、粗大ごみ予約、生活代行は書類、所要時間、方法、保証できない事項を入力します。",
            subtitleEn: "Life setup uses required materials, timeline, method and no-guarantee fields.",
            categories: lifeSetupSectionCategories
        ),
        .init(
            id: "beauty",
            icon: "sparkles",
            zh: "美容健康",
            ja: "美容・健康予約",
            en: "Beauty",
            subtitleZh: "美容美发、美甲、按摩、皮肤管理和体检/牙科预约协助填写项目、时间、价格、注意事项和医疗边界。",
            subtitleJa: "美容、ネイル、マッサージ、肌ケア、健診・歯科予約は項目、時間、料金、注意事項、医療境界を入力します。",
            subtitleEn: "Beauty and health booking uses service, time, price, notes and medical-boundary fields.",
            categories: beautyHealthSectionCategories
        ),
    ]
    static let serviceCreateCategories = uniqueCategories(serviceCreateSections.flatMap(\.categories))
    /// 生活服务只展示第一阶段正式入口；旧伞类目仍在映射中兼容已有数据。
    static let lifeSectionCategories = paperworkSectionCategories + movingSectionCategories + lifeSetupSectionCategories + beautyHealthSectionCategories
    // 「民泊」= 日语用户手输的民宿别名,一并按民宿归档/筛选。
    static let homestayCategories = ["民宿", "民泊"]
    static let hotelCategories = ["酒店", "温泉旅馆", "公寓式酒店", "短住公寓", "酒店民宿"]
    static let stayCategories = homestayCategories + hotelCategories
    static let stayChips = ["全部", "民宿"]

    private static func uniqueCategories(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }
    }

    static func isStayCategory(_ category: String?) -> Bool {
        stayCategories.contains(category ?? "")
    }

    static func isHomestayCategory(_ category: String?) -> Bool {
        homestayCategories.contains(category ?? "")
    }

    static func isFoodCategory(_ category: String?) -> Bool {
        foodFilterCategories.contains(category ?? "")
    }

    private static let serviceVerticalByCategory: [String: ServiceVertical] = [
        "餐厅": .foodRestaurant,
        "餐厅美食": .foodRestaurant,
        "餐饮预约": .foodRestaurant,
        "中华料理": .foodRestaurant,
        "日本料理": .foodRestaurant,
        "居酒屋": .foodRestaurant,
        "烧肉火锅": .foodRestaurant,
        "拉面": .foodRestaurant,
        "寿司海鲜": .foodRestaurant,
        "咖啡甜品": .foodRestaurant,
        "西餐": .foodRestaurant,
        "韩国料理": .foodRestaurant,
        "餐饮点评": .diningBooking,
        "优惠预约": .diningBooking,
        "民宿": .lodging,
        "民泊": .lodging,
        "酒店": .lodging,
        "温泉旅馆": .lodging,
        "公寓式酒店": .lodging,
        "短住公寓": .lodging,
        "酒店民宿": .lodging,
        "景点门票": .attractionTicket,
        "一日游": .dayTour,
        "本地向导": .dayTour,
        "体验活动": .dayTour,
        "包车行程": .dayTour,
        "接送机": .airportTransfer,
        "机场接送": .airportTransfer,
        "车站接送": .airportTransfer,
        "包车": .airportTransfer,
        "行李协助": .airportTransfer,
        "材料翻译": .paperworkTranslation,
        "市役所陪同": .paperworkTranslation,
        "银行卡协助": .paperworkTranslation,
        "手机卡协助": .paperworkTranslation,
        "签证材料整理": .paperworkTranslation,
        "翻译手续": .paperworkTranslation,
        "签证/手续协助": .paperworkTranslation,
        "翻译": .paperworkTranslation,
        "租房申请协助": .paperworkTranslation,
        "认证服务": .paperworkTranslation,
        "退房清洁": .movingCleaning,
        "粗大垃圾协助": .movingCleaning,
        "行李搬运": .movingCleaning,
        "家具家电配送协助": .movingCleaning,
        "搬家清洁": .movingCleaning,
        "搬家": .movingCleaning,
        "清洁": .movingCleaning,
        "手机卡开通": .lifeSetup,
        "网络开通": .lifeSetup,
        "水电煤协助": .lifeSetup,
        "地址登记协助": .lifeSetup,
        "粗大垃圾预约": .lifeSetup,
        "生活跑腿": .lifeSetup,
        "生活支持": .lifeSetup,
        "美容美发": .beautyHealth,
        "美甲": .beautyHealth,
        "按摩": .beautyHealth,
        "皮肤管理": .beautyHealth,
        "体检/牙科预约协助": .beautyHealth,
        "宠物寄养": .petFamily,
        "遛狗": .petFamily,
        "临时照看": .petFamily,
        "儿童用品租赁": .petFamily,
        "家庭协助": .petFamily,
        "宠物服务": .petFamily,
    ]

    static func serviceVertical(category: String?, serviceType: String?) -> ServiceVertical? {
        let categoryKey = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let serviceKey = serviceType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let vertical = serviceVerticalByCategory[categoryKey] { return vertical }
        if let vertical = serviceVerticalByCategory[serviceKey] { return vertical }
        if let vertical = ServiceVertical(rawValue: serviceKey) { return vertical }
        return nil
    }

    static func serviceCreateSection(for category: String?) -> ServiceCreateSection? {
        guard let key = serviceCreateSectionKey(for: category) else { return nil }
        return serviceCreateSections.first { $0.id == key }
    }

    static func serviceCreateSectionKey(for category: String?) -> String? {
        let value = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty { return nil }
        if let section = serviceCreateSections.first(where: { $0.categories.contains(value) }) {
            return section.id
        }
        switch serviceVertical(category: value, serviceType: value) {
        case .foodRestaurant, .diningBooking:
            return "food"
        case .lodging:
            return "lodging"
        case .attractionTicket, .dayTour:
            return "travel"
        case .airportTransfer:
            return "transfer"
        case .paperworkTranslation:
            return "paperwork"
        case .movingCleaning:
            return "moving"
        case .lifeSetup:
            return "life"
        case .beautyHealth:
            return "beauty"
        case .petFamily:
            return nil
        case .none:
            return nil
        }
    }

    static func serviceVertical(for listing: KaiXCityListingDTO) -> ServiceVertical? {
        let serviceType = listing.attributes?["service_type"]?.listingDisplayValue
        if let vertical = serviceVertical(category: listing.category, serviceType: serviceType) { return vertical }
        let explicit = listing.attributes?["service_vertical"]?.listingDisplayValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let vertical = ServiceVertical(rawValue: explicit) { return vertical }
        let attrs = listing.attributes ?? [:]
        if attrs["menu"] != nil || attrs["packages"] != nil { return .foodRestaurant }
        if attrs["room_type"] != nil || attrs["max_guests"] != nil { return .lodging }
        if attrs["airport_route"] != nil || attrs["flight_info_note"] != nil { return .airportTransfer }
        if attrs["document_type"] != nil || attrs["required_materials"] != nil { return .paperworkTranslation }
        if attrs["property_size"] != nil || attrs["vehicle_staff"] != nil { return .movingCleaning }
        if attrs["setup_type"] != nil || attrs["cannot_guarantee"] != nil { return .lifeSetup }
        if attrs["beauty_service"] != nil || attrs["medical_disclaimer"] != nil { return .beautyHealth }
        if attrs["service_target"] != nil { return .petFamily }
        if attrs["ticket_type"] != nil {
            if attrs["pickup_service"] != nil { return .dayTour }
            return .attractionTicket
        }
        return nil
    }

    static func serviceVerticalLabel(_ vertical: ServiceVertical, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch vertical {
        case .foodRestaurant: (zh, ja, en) = ("餐厅字段", "飲食店フィールド", "Restaurant fields")
        case .diningBooking: (zh, ja, en) = ("餐厅优惠字段", "飲食店特典フィールド", "Restaurant deal fields")
        case .lodging: (zh, ja, en) = ("住宿字段", "宿泊フィールド", "Stay fields")
        case .attractionTicket: (zh, ja, en) = ("景点门票字段", "観光チケットフィールド", "Attraction ticket fields")
        case .dayTour: (zh, ja, en) = ("一日游字段", "日帰りツアーフィールド", "Day tour fields")
        case .airportTransfer: (zh, ja, en) = ("接送与交通字段", "送迎・交通フィールド", "Transfer fields")
        case .paperworkTranslation: (zh, ja, en) = ("翻译 / 手续字段", "翻訳・手続きフィールド", "Paperwork fields")
        case .movingCleaning: (zh, ja, en) = ("搬家 / 清洁字段", "引越し・清掃フィールド", "Moving & cleaning fields")
        case .lifeSetup: (zh, ja, en) = ("生活开通 / 住后支持字段", "生活手続きフィールド", "Life setup fields")
        case .beautyHealth: (zh, ja, en) = ("美容健康预约字段", "美容・健康予約フィールド", "Beauty & health fields")
        case .petFamily: (zh, ja, en) = ("宠物与家庭支持字段", "ペット・家庭サポートフィールド", "Pet & family fields")
        }
        return pickText(language, zh, ja, en)
    }

    static func serviceTypeOptions(for vertical: ServiceVertical) -> [String] {
        switch vertical {
        case .foodRestaurant:
            return ["餐厅"] + foodCategories
        case .diningBooking:
            return ["优惠预约"]
        case .lodging:
            return lodgingSectionCategories
        case .attractionTicket:
            return ["景点门票"]
        case .dayTour:
            return ["一日游", "本地向导", "体验活动", "包车行程"]
        case .airportTransfer:
            return transferSectionCategories
        case .paperworkTranslation:
            return paperworkSectionCategories
        case .movingCleaning:
            return movingSectionCategories
        case .lifeSetup:
            return lifeSetupSectionCategories
        case .beautyHealth:
            return beautyHealthSectionCategories
        case .petFamily:
            return petFamilySectionCategories
        }
    }

    /// Header copy in the viewer's app language. zh remains the source of
    /// truth; ja/en mirror web ListingKit's CHANNEL_TEXT so both clients
    /// read the same.
    static func title(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental", "stays", "hotels": (zh, ja, en) = ("租房 · 住宿", "賃貸・宿泊", "Homes & Stays")
        case "for_sale":      (zh, ja, en) = ("买房 · 物件", "物件購入", "Properties for sale")
        case "work":          (zh, ja, en) = ("工作", "求人", "Jobs")
        case "job":           (zh, ja, en) = ("找工作", "仕事を探す", "Find work")
        case "hiring":        (zh, ja, en) = ("招聘", "採用", "Hiring")
        case "local_service": (zh, ja, en) = ("商家与服务", "店舗・地域サービス", "Businesses & local services")
        case "discount":      (zh, ja, en) = ("优惠", "クーポン", "Deals")
        case "event":         (zh, ja, en) = ("活动", "イベント", "Events")
        default:              (zh, ja, en) = ("二手市场", "フリマ", "Marketplace")
        }
        return pickText(language, zh, ja, en)
    }

    static func subtitle(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental", "stays", "hotels":
            (zh, ja, en) = ("长租房源与民宿", "賃貸・民泊をまとめて探せる", "Long-term rentals and homestays")
        case "for_sale":
            (zh, ja, en) = ("精选在售物件、户型、面积与利回り", "厳選された販売物件・間取り・面積・利回り", "Curated properties for sale, layout, area and yield")
        case "work", "job", "hiring":
            (zh, ja, en) = ("职位库、薪资、日语要求和签证支持", "求人・給与・日本語レベル・ビザサポート", "Jobs, salary, Japanese level, visa support")
        case "local_service":
            (zh, ja, en) = ("餐厅、点评订座、景点玩乐和生活支持", "飲食店・口コミ予約・観光体験・生活サポート", "Restaurants, reviews & booking, attractions and local support")
        case "discount":
            (zh, ja, en) = ("本地商家优惠与精选活动", "地元店舗の特典と注目イベント", "Local merchant deals and featured events")
        default:
            (zh, ja, en) = ("图片、价格、地点和交易状态", "写真・価格・場所・取引状況", "Photos, price, location and deal status")
        }
        return pickText(language, zh, ja, en)
    }

    /// Inline trilingual pick — file-wide helper for one-off UI strings.
    static func pickText(_ language: AppLanguage, _ zh: String, _ ja: String, _ en: String) -> String {
        switch language {
        case .ja: ja
        case .en: en
        default:  zh
        }
    }

    /// Detail-row titles, keyed by the canonical zh label used when the
    /// rows are built. Mirrors DETAIL_FIELD_LABELS in web listingFormat.ts
    /// so both clients read identically. Unknown labels pass through.
    private static let attributeLabels: [String: (ja: String, en: String)] = [
        "地区": ("エリア", "Area"),
        "最近车站": ("最寄り駅", "Nearest station"),
        "车站距离": ("駅からの距離", "To station"),
        "户型": ("間取り", "Layout"),
        "面积": ("面積", "Size"),
        "押金": ("敷金", "Deposit"),
        "礼金": ("礼金", "Key money"),
        "管理费": ("管理費", "Management fee"),
        "初期费用说明": ("初期費用について", "Initial costs"),
        "入住时间": ("入居可能日", "Move-in date"),
        "租期": ("契約期間", "Lease term"),
        "短租": ("短期", "Short-term"),
        "合租": ("ルームシェア", "Roomshare"),
        "家具家电": ("家具家電", "Furnished"),
        "宠物": ("ペット", "Pets"),
        "公司/店铺": ("会社・店舗", "Company"),
        "地点": ("場所", "Location"),
        "雇佣形式": ("雇用形態", "Employment type"),
        "薪资": ("給与", "Salary"),
        "薪资类型": ("給与形態", "Salary type"),
        "日语要求": ("日本語レベル", "Japanese level"),
        "签证支持": ("ビザサポート", "Visa support"),
        "签证支持说明": ("ビザサポート", "Visa support"),
        "工作时间": ("勤務時間", "Working hours"),
        "交通费": ("交通費", "Transport fee"),
        "外国人友好": ("外国人歓迎", "Foreigner friendly"),
        "无经验可": ("未経験OK", "No experience OK"),
        "留学生可": ("留学生OK", "Students OK"),
        "服务类型": ("サービス種別", "Service type"),
        "服务方": ("提供者", "Provider"),
        "服务范围": ("対応範囲", "Service scope"),
        "可服务城市": ("対応エリア", "Service area"),
        "价格": ("価格", "Price"),
        "起步价格": ("開始価格", "Starting price"),
        "价格单位": ("料金単位", "Price unit"),
        "可预约时间": ("予約可能時間", "Availability"),
        "营业时间": ("営業時間", "Business hours"),
        "价格区间": ("価格帯", "Price range"),
        "到店电话": ("店舗電話", "Store phone"),
        "预约制": ("予約制", "Reservation required"),
        "预约说明": ("予約について", "Reservation notes"),
        "服务语言": ("対応言語", "Service languages"),
        "认证服务方": ("認証済み提供者", "Verified provider"),
        "房型": ("客室タイプ", "Room type"),
        "可住人数": ("定員", "Guests"),
        "入住办理": ("チェックイン", "Check-in"),
        "退房时间": ("チェックアウト", "Check-out"),
        "最少入住": ("最低宿泊数", "Minimum stay"),
        "设施服务": ("設備・サービス", "Amenities"),
        "房量与日期": ("空室・日程", "Availability notes"),
        "含早餐": ("朝食付き", "Breakfast included"),
        "即时确认": ("即時確定", "Instant confirmation"),
        "资质/许可说明": ("資格・許認可", "License notes"),
        "票种": ("チケット種別", "Ticket type"),
        "日期/有效期": ("日付・有効期限", "Date / validity"),
        "时长": ("所要時間", "Duration"),
        "集合地点": ("集合場所", "Meeting point"),
        "包含内容": ("含まれるもの", "Included"),
        "不包含内容": ("含まれないもの", "Not included"),
        "含酒店接送": ("ホテル送迎付き", "Hotel pickup"),
        "机场/路线": ("空港・ルート", "Airport / route"),
        "车型": ("車種", "Vehicle type"),
        "人数": ("人数", "Passengers"),
        "行李数": ("荷物数", "Luggage"),
        "航班号说明": ("便名について", "Flight info"),
        "等待规则": ("待機ルール", "Waiting rule"),
        "夜间/追加费用": ("深夜・追加料金", "Surcharges"),
        "文件/手续类型": ("書類・手続き種別", "Document / procedure type"),
        "所需材料": ("必要書類", "Required materials"),
        "交付时间": ("納期", "Delivery time"),
        "结果说明": ("結果について", "Result note"),
        "房型/面积": ("間取り・面積", "Room / size"),
        "物品量": ("荷物量", "Item volume"),
        "车辆/人员": ("車両・スタッフ", "Vehicle / staff"),
        "追加费用": ("追加料金", "Extra fees"),
        "设备/项目类型": ("設備・作業種別", "Device / project"),
        "品牌/型号": ("ブランド・型番", "Brand / model"),
        "上门区域": ("出張エリア", "On-site area"),
        "上门费": ("出張費", "On-site fee"),
        "配件费": ("部品代", "Parts fee"),
        "保修说明": ("保証について", "Warranty"),
        "不可服务范围": ("対応不可範囲", "Unavailable scope"),
        "服务流程": ("サービスの流れ", "Process"),
        "用户需准备": ("ご準備いただくもの", "You prepare"),
        "取消规则": ("キャンセル規定", "Cancellation"),
        "审核状态": ("審査状況", "Review status"),
        "商家": ("店舗", "Merchant"),
        "优惠": ("特典", "Deal"),
        "优惠内容": ("特典内容", "Deal details"),
        "有效期": ("有効期限", "Valid until"),
        "使用规则": ("利用条件", "Usage rules"),
        "商家认证": ("店舗認証", "Merchant verification"),
        "状态": ("ステータス", "Status"),
        "发布类型": ("出品タイプ", "Listing type"),
        "分类": ("カテゴリ", "Category"),
        "新旧程度": ("状態", "Condition"),
        "原价/参考价": ("元値・参考価格", "Original/reference price"),
        "价格可议": ("価格相談", "Negotiable"),
        "购买时间": ("購入時期", "Purchase time"),
        "配件/包装": ("付属品・箱", "Accessories/box"),
        "瑕疵说明": ("傷・不具合", "Defects note"),
        "交易地点": ("受け渡し場所", "Meetup location"),
        "交易方式": ("受け渡し方法", "Delivery method"),
        "品牌": ("ブランド", "Brand"),
        "可交易时间": ("受け渡し可能時間", "Available time"),
        "取货说明": ("受け渡しメモ", "Pickup note"),
    ]

    static func attributeLabel(_ zhLabel: String, _ language: AppLanguage) -> String {
        guard let entry = attributeLabels[zhLabel.trimmingCharacters(in: .whitespaces)] else { return zhLabel }
        switch language {
        case .ja: return entry.ja
        case .en: return entry.en
        default:  return zhLabel
        }
    }

    /// Display-only localization for the city-listing compose form. The
    /// stored payload values remain the canonical zh strings where the API
    /// expects them; only the visible label/placeholder/chip text changes.
    static func formText(_ value: String, _ language: AppLanguage) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return value }
        if let entry = formTexts[normalized] {
            return pickText(language, normalized, entry.ja, entry.en)
        }
        let category = categoryLabel(normalized, language)
        if category != normalized { return category }
        let attribute = attributeLabel(normalized, language)
        if attribute != normalized { return attribute }
        // 频道筛选表与发布表单共用同一批中文枚举(新旧程度/发布类型/可宠物…)。
        // 兜底链缺了它,选项行会中外混排——如「全新/几乎全新/良好/有使用痕迹」
        // 留中文而同行的「可用」显示 Fair。ListingFilterLocalizer 自身继续兜底
        // 到 ListingIntakeLocalizer,链条完整,无递归。
        let filter = ListingFilterLocalizer.text(normalized, language)
        if filter != normalized { return filter }
        return value
    }

    private static let formTexts: [String: (ja: String, en: String)] = [
        "房源信息": ("物件情報", "Home details"),
        "职位信息": ("求人情報", "Job details"),
        "选择服务细分类": ("サービス細分類を選択", "Choose service subcategory"),
        "商家优惠字段": ("店舗特典の項目", "Deal details"),
        "交易字段": ("取引項目", "Marketplace details"),
        "交易细节（可选）": ("取引の詳細（任意）", "Trade details (optional)"),
        "以下全部选填。写清新旧程度、瑕疵与配件能减少来回确认;交易地点私聊约定即可。": (
            "以下はすべて任意です。状態・傷・付属品を書いておくとやり取りがスムーズです。受け渡し場所はメッセージで相談しましょう。",
            "Everything below is optional. Condition, flaws and accessories save back-and-forth; arrange the meetup spot in chat."
        ),
        "例如 可面交，邮寄需买家承担运费": ("例：手渡し可、郵送は買い手が送料負担", "e.g. meetup OK, buyer pays shipping"),
        "如有划痕、缺件、维修史请提前说明": ("傷・欠品・修理歴があれば事前に記載してください", "Note any scratches, missing parts or repairs"),
        "服务方名称": ("提供者名", "Provider name"),
        "细分类 / 服务类型": ("細分類 / サービス種別", "Subcategory / service type"),
        "公司 / 店铺名": ("会社 / 店舗名", "Company / store name"),
        "商家名称": ("店舗名", "Merchant name"),
        "商家已认证": ("店舗認証済み", "Merchant verified"),
        "认证商家": ("認証済み店舗", "Verified merchant"),
        "仅限预约制": ("予約制のみ", "Reservation only"),
        "取消/退款规则": ("キャンセル / 返金規定", "Cancellation / refund rules"),
        "人均 / 价位": ("一人あたり / 価格帯", "Per person / price range"),
        "每晚/起步价格": ("1泊 / 開始価格", "Nightly / starting price"),
        "日期 / 有效期": ("日付 / 有効期限", "Date / validity"),
        "服务区域 / 店铺位置": ("対応エリア / 店舗所在地", "Service area / store location"),
        "安全/资质说明": ("安全 / 資格説明", "Safety / credentials"),
        "医疗免责声明": ("医療免責事項", "Medical disclaimer"),
        "不可承诺事项": ("保証できない事項", "What cannot be guaranteed"),
        "价格说明": ("料金説明", "Price notes"),
        "预计耗时": ("目安時間", "Estimated time"),
        "服务方式": ("サービス方法", "Service method"),
        "服务区域": ("対応エリア", "Service area"),
        "服务对象": ("対象", "Service target"),
        "菜单（每行：菜名 | 价格 | 备注）": ("メニュー（1行：料理名 | 価格 | メモ）", "Menu (one line: item | price | note)"),
        "团购套餐（每行：套餐名 | 现价 | 原价 | 包含）": ("セット（1行：名称 | 現価格 | 通常価格 | 内容）", "Packages (one line: name | deal price | original | includes)"),
        "品牌 / 型号": ("ブランド / 型番", "Brand / model"),
        "原价 / 参考价": ("元値 / 参考価格", "Original / reference price"),
        "配件 / 包装": ("付属品 / 箱", "Accessories / packaging"),
        "瑕疵 / 使用痕迹": ("傷 / 使用感", "Defects / wear"),
        "取货 / 邮寄说明": ("受け渡し / 配送メモ", "Pickup / shipping notes"),
        "自取 / 面交": ("引き取り / 対面", "Pickup / meetup"),
        "可邮寄": ("配送可", "Shipping OK"),
        "价格可商量": ("価格相談可", "Negotiable"),
        "可合租": ("シェア可", "Share OK"),
        "可短租": ("短期可", "Short-term OK"),
        "休日休假": ("休日・休暇", "Holidays"),
        "完全周休二日 / 轮班制": ("完全週休2日 / シフト制", "Two days off / shift schedule"),
        "社保完备、员工餐、交通费支给": ("社会保険完備、まかない、交通費支給", "Insurance, staff meals, transport covered"),
        "留学生可": ("留学生OK", "Students OK"),
        "可远程": ("リモート可", "Remote OK"),
        "发布类型": ("出品タイプ", "Listing mode"),
        "免费送": ("無料譲渡", "Free giveaway"),
        "可用": ("使用可", "Fair"),
        "可选，例如 28000": ("任意：例 28000", "Optional, e.g. 28000"),
        "可选，例如 2025 年春": ("任意：例 2025年春", "Optional, e.g. spring 2025"),
        "个人 / 店铺 / 公司名称": ("個人 / 店舗 / 会社名", "Individual / store / company name"),
        "店铺 / 品牌 / 公司名称": ("店舗 / ブランド / 会社名", "Store / brand / company name"),
        "东京 23 区 / 店内用餐 / 外带自取": ("東京23区 / 店内飲食 / テイクアウト", "Tokyo 23 wards / dine-in / pickup"),
        "东京 23 区 / 线上预约 / 到店点评": ("東京23区 / オンライン予約 / 来店レビュー", "Tokyo 23 wards / online booking / visit review"),
        "东京 23 区 / 横滨 / 线上协助": ("東京23区 / 横浜 / オンライン対応", "Tokyo 23 wards / Yokohama / online help"),
        "东京 23 区 / 横滨 / 清洁可线上估价": ("東京23区 / 横浜 / 清掃はオンライン見積可", "Tokyo 23 wards / Yokohama / online cleaning quote"),
        "东京 23 区 / 到店 / 上门": ("東京23区 / 来店 / 出張", "Tokyo 23 wards / in-store / home visit"),
        "新宿站东口步行 5 分钟": ("新宿駅東口から徒歩5分", "5 min walk from Shinjuku East Exit"),
        "如何预约、可预约时段、几人起订、是否需要定金": ("予約方法、可能時間、最低人数、予約金の有無", "How to book, times, minimum party, deposit"),
        "麻婆豆腐 | ¥980\n口水鸡 | ¥1,080 | 微辣": ("麻婆豆腐 | ¥980\nよだれ鶏 | ¥1,080 | ピリ辛", "Mapo tofu | ¥980\nSpicy chicken | ¥1,080 | mild spicy"),
        "双人套餐 | ¥3,980 | ¥5,200 | 4菜1汤+2饮料": ("2名セット | ¥3,980 | ¥5,200 | 4品1スープ+2ドリンク", "Set for 2 | ¥3,980 | ¥5,200 | 4 dishes + soup + 2 drinks"),
        "中文 / 日文 / 英文": ("中国語 / 日本語 / 英語", "Chinese / Japanese / English"),
        "中日 / 中英 / 日英 / 多语言": ("中日 / 中英 / 日英 / 多言語", "CN-JP / CN-EN / JP-EN / multilingual"),
        "预约确认、到店、点评或优惠使用流程": ("予約確認、来店、レビューまたは特典利用の流れ", "Booking confirmation, visit, review or deal flow"),
        "例如 前一天可取消，定金不可退请写清": ("例：前日キャンセル可、予約金返金不可など", "e.g. cancel by previous day; note non-refundable deposits"),
        "大床房 / 双床房 / 整套民宿": ("ダブル / ツイン / 一棟貸し", "Double / twin / entire stay"),
        "每晚 / 每人 / 预约咨询": ("1泊 / 1名 / 予約相談", "Per night / per person / inquire"),
        "1 晚 / 2 晚起": ("1泊 / 2泊から", "1 night / 2 nights minimum"),
        "Wi-Fi、厨房、洗衣机、停车场、温泉、行李寄存": ("Wi-Fi、キッチン、洗濯機、駐車場、温泉、荷物預かり", "Wi-Fi, kitchen, washer, parking, onsen, luggage storage"),
        "可订日期、剩余房量、旺季限制、儿童入住规则": ("予約可能日、残室、繁忙期制限、子ども利用条件", "Available dates, rooms left, peak limits, child policy"),
        "入住前几天可取消、旺季不可退等": ("宿泊何日前まで取消可、繁忙期返金不可など", "Cancellation window, peak non-refundable rules"),
        "旅馆业许可 / 民泊备案 / 可接待范围": ("旅館業許可 / 民泊届出 / 受入範囲", "Hotel license / minpaku registration / guest scope"),
        "成人 / 儿童 / 私人团 / 拼团": ("大人 / 子ども / プライベート / 混載", "Adult / child / private / shared"),
        "成人票 / 儿童票 / 套票 / 电子票": ("大人券 / 子ども券 / セット券 / 電子券", "Adult / child / bundle / e-ticket"),
        "指定日期 / 购买后 30 天有效 / 每周六出发": ("指定日 / 購入後30日有効 / 毎週土曜出発", "Fixed date / valid 30 days / Saturdays"),
        "约 8 小时": ("約8時間", "About 8 hours"),
        "约 2 小时 / 当日有效": ("約2時間 / 当日有効", "About 2 hours / same-day valid"),
        "新宿站西口 / 景区入口 / 酒店接送范围": ("新宿駅西口 / 施設入口 / ホテル送迎範囲", "Shinjuku West Exit / attraction entrance / hotel pickup area"),
        "门票、导览、交通、餐食等": ("チケット、ガイド、交通、食事など", "Tickets, guide, transport, meals"),
        "个人消费、餐饮、保险等": ("個人消費、食事、保険など", "Personal spending, meals, insurance"),
        "护照、证件、舒适鞋、雨具等": ("パスポート、身分証、歩きやすい靴、雨具など", "Passport, ID, comfortable shoes, rain gear"),
        "票务不可退 / 出发前 3 天可取消": ("チケット返金不可 / 出発3日前まで取消可", "Tickets non-refundable / cancel 3 days before"),
        "票务来源、旅行资质、保险或导游说明": ("チケット入手元、旅行資格、保険またはガイド説明", "Ticket source, travel credentials, insurance or guide notes"),
        "成田机场 - 东京 23 区 / 羽田 - 横滨": ("成田空港 - 東京23区 / 羽田 - 横浜", "Narita - Tokyo 23 wards / Haneda - Yokohama"),
        "可接送区域、是否支持跨县、夜间范围": ("送迎エリア、県外対応、深夜対応範囲", "Pickup area, cross-prefecture, night scope"),
        "轿车 / Alphard / Hiace": ("セダン / アルファード / ハイエース", "Sedan / Alphard / Hiace"),
        "2 个 28 寸 + 2 个随身": ("28インチ2個 + 手荷物2個", "Two 28-inch bags + two carry-ons"),
        "是否需要航班号、延误如何处理": ("便名の要否、遅延時の対応", "Flight number needed, delay handling"),
        "免费等待 60 分钟，超时每 30 分钟加收": ("60分無料待機、以降30分ごとに追加料金", "60 min free waiting, extra per 30 min"),
        "夜间、儿童座椅、大件行李、高速费说明": ("深夜、チャイルドシート、大型荷物、高速料金", "Night, child seat, large luggage, toll notes"),
        "出发前多久可取消，临时取消费用": ("出発何日前まで取消可、直前取消料", "Cancellation window and late fees"),
        "住民票翻译 / 签证材料 / 租房申请 / 电话代沟通": ("住民票翻訳 / ビザ書類 / 賃貸申込 / 電話代行", "Residence record translation / visa docs / rental application / phone help"),
        "护照、在留卡、原文件、申请表等": ("パスポート、在留カード、原本、申請書など", "Passport, residence card, originals, forms"),
        "最快当天 / 2-3 个工作日 / 加急另议": ("最短当日 / 2-3営業日 / 特急相談", "Same day / 2-3 business days / rush on request"),
        "资料确认、报价、翻译/代办、交付方式": ("資料確認、見積、翻訳/代行、納品方法", "Document check, quote, translation/help, delivery"),
        "需本人确认、签字、原件邮寄或线上提交的信息": ("本人確認、署名、原本郵送、オンライン提出情報", "Identity check, signature, originals by mail, online info"),
        "行政书士、翻译资质、合作机构或免责声明": ("行政書士、翻訳資格、提携先または免責事項", "Scrivener, translation credentials, partners or disclaimer"),
        "开始处理后是否可退、材料错误如何处理": ("着手後の返金可否、資料不備時の対応", "Refund after work starts, document error handling"),
        "1K / 45 平 / 店铺 20 平": ("1K / 45平米 / 店舗20平米", "1K / 45 sqm / 20 sqm store"),
        "纸箱 20 个 / 大件 3 件": ("段ボール20箱 / 大型3点", "20 boxes / 3 large items"),
        "2 吨车 + 2 人 / 1 人上门": ("2t車 + 2名 / 1名出張", "2-ton truck + 2 staff / 1 staff visit"),
        "搬运、拆装、基础清洁、垃圾袋等": ("運搬、分解組立、簡易清掃、ごみ袋など", "Moving, assembly, basic cleaning, trash bags"),
        "空调拆装、粗大垃圾处理、停车费等": ("エアコン脱着、粗大ごみ処理、駐車料金など", "AC removal/install, oversized trash, parking"),
        "提前打包、预约电梯、停车位、垃圾券等": ("事前梱包、エレベーター予約、駐車場所、ごみ券など", "Pack ahead, reserve elevator, parking, disposal tickets"),
        "楼梯、大件、远距离、夜间、停车费说明": ("階段、大型物、長距離、深夜、駐車料金", "Stairs, large items, distance, night, parking"),
        "预约前一天取消费、雨天改期等": ("前日キャンセル料、雨天変更など", "Previous-day cancellation fee, weather reschedule"),
        "手机卡 / 网络 / 水电煤 / 地址登记": ("SIM / ネット / ライフライン / 住所登録", "SIM / internet / utilities / address registration"),
        "在留卡、护照、地址、银行卡、本人到场要求": ("在留カード、パスポート、住所、銀行カード、本人来店要否", "Residence card, passport, address, bank card, in-person requirement"),
        "当天 / 1-3 个工作日 / 需预约窗口": ("当日 / 1-3営業日 / 窓口予約必要", "Same day / 1-3 business days / appointment needed"),
        "线上确认材料、预约窗口、陪同办理或远程协助": ("オンライン資料確認、窓口予約、同行または遠隔サポート", "Online document check, appointment, accompaniment or remote help"),
        "证件原件、印章、现金、可接电话时间等": ("原本書類、印鑑、現金、電話可能時間など", "Original IDs, seal, cash, reachable times"),
        "不能保证运营商审核、开户结果、政府窗口受理或第三方时效": ("キャリア審査、口座開設結果、役所受付、第三者の所要時間は保証不可", "Cannot guarantee carrier review, account approval, government acceptance, or third-party timing"),
        "预约咨询 / ¥3,000 起 / 按事项报价": ("予約相談 / ¥3,000から / 内容別見積", "Inquire / from ¥3,000 / by request"),
        "材料确认后、预约日前后取消与改期规则": ("資料確認後、予約日前後の取消・変更規定", "Cancellation/reschedule rules after document check or booking"),
        "新宿 / 原宿 / 线上预约协助": ("新宿 / 原宿 / オンライン予約支援", "Shinjuku / Harajuku / online booking help"),
        "剪发 / 美甲 / 按摩 / 体检预约协助": ("ヘアカット / ネイル / マッサージ / 健診予約支援", "Haircut / nails / massage / checkup booking"),
        "平日晚间 / 周末 / 需提前 2 天": ("平日夜 / 週末 / 2日前まで", "Weekday evenings / weekends / 2 days ahead"),
        "¥4,000 起 / 按项目报价": ("¥4,000から / メニュー別", "From ¥4,000 / by service"),
        "45 分钟 / 90 分钟": ("45分 / 90分", "45 min / 90 min"),
        "迟到规则、过敏史、禁忌提醒、预约前准备": ("遅刻規定、アレルギー、禁忌、事前準備", "Late rules, allergies, contraindications, prep"),
        "医疗相关仅做预约协助，不提供诊断、治疗承诺或医疗建议": ("医療関連は予約支援のみで、診断・治療保証・医療助言は提供しません", "Medical items are booking help only, not diagnosis, treatment promise, or medical advice"),
        "24 小时内取消、迟到、改期等规则": ("24時間以内の取消、遅刻、変更規定", "Rules for cancellation within 24h, lateness, rescheduling"),
        "小型犬 / 猫 / 儿童用品 / 家庭协助": ("小型犬 / 猫 / 子ども用品 / 家庭支援", "Small dogs / cats / kids items / family help"),
        "平日晚上 / 周末 / 假期": ("平日夜 / 週末 / 祝日", "Weekday evenings / weekends / holidays"),
        "按小时 / 按天 / 预约咨询": ("時間単位 / 日単位 / 予約相談", "Hourly / daily / inquire"),
        "宠物性格、疫苗、用品、紧急联系人、家庭规则": ("性格、ワクチン、用品、緊急連絡先、家庭ルール", "Temperament, vaccines, supplies, emergency contact, home rules"),
        "经验、保险、照看范围、不可服务边界": ("経験、保険、ケア範囲、対応不可範囲", "Experience, insurance, care scope, exclusions"),
        "预约前取消、临时变更、超时费用等": ("予約前取消、直前変更、延長料金など", "Cancellation, last-minute changes, overtime fees"),
        "例如 学生出示证件 9 折，套餐减 500 日元": ("例：学生証提示で10%オフ、セット500円引き", "e.g. 10% off with student ID, ¥500 off set"),
        "适用门店、不可叠加、预约说明等": ("対象店舗、併用不可、予約説明など", "Eligible stores, no stacking, booking notes"),
        "可选，例如 日文配列键盘 / 白色书桌 / 13 寸笔记本": ("任意：例 日本語配列キーボード / 白い机 / 13インチノートPC", "Optional, e.g. Japanese keyboard / white desk / 13-inch laptop"),
        "例如 原盒、充电器、说明书、保修卡": ("例：箱、充電器、説明書、保証書", "e.g. box, charger, manual, warranty card"),
        "如有划痕、缺件、维修史请提前说明；没有可写“无明显瑕疵”": ("傷、欠品、修理歴があれば記載。なければ「目立つ傷なし」", "Note scratches, missing parts, repairs; otherwise write no obvious defects"),
        "例如 平日 19:00 后 / 周末下午": ("例：平日19:00以降 / 週末午後", "e.g. weekdays after 19:00 / weekend afternoons"),
        "例如 新宿站面交，邮寄需买家承担运费": ("例：新宿駅で手渡し、配送は購入者送料負担", "e.g. meetup at Shinjuku Station, buyer pays shipping"),
        "完整填写车站、面积和入住时间，能明显减少重复私信询问。": ("駅、面積、入居時期を具体的に書くと、重複問い合わせを減らせます。", "Clear station, size, and move-in timing reduce repeated messages."),
        "请先在基本信息里选择一个标准服务分类，例如 餐厅、景点门票、一日游、机场接送、翻译手续、搬家清洁、生活开通或美容健康。": ("まず基本情報で標準サービス分類を選んでください。例：飲食店、観光チケット、日帰り、空港送迎、翻訳手続き、引越し清掃、生活セットアップ、美容健康。", "Choose a standard service category in Basic info first, such as restaurants, tickets, day tours, airport transfer, paperwork, moving/cleaning, life setup, or beauty/health."),
        "建议写清购买时间、瑕疵、配件、是否含包装和交易地点，减少来回确认。": ("購入時期、傷、付属品、箱の有無、受け渡し場所を書くと確認の往復が減ります。", "Add purchase time, defects, accessories, packaging, and handoff location to reduce back-and-forth."),
        // —— 分类专属字段此前对日/英用户回落为中文的标题/选项/占位 —— //
        "福利待遇": ("福利厚生", "Benefits"),
        "服务时长": ("施術時間", "Service duration"),
        "最少入住晚数": ("最低宿泊数", "Minimum nights"),
        "房量与日期说明": ("空室・日程について", "Availability & dates"),
        "不保证结果": ("結果保証なし", "No result guarantee"),
        "例如 池袋站 步行 8 分钟": ("例：池袋駅 徒歩8分", "e.g. 8 min walk from Ikebukuro Stn"),
        "例如 7 月上旬 / 即可入住": ("例：7月上旬 / 即入居可", "e.g. early July / available now"),
        "例如 新宿咖啡店 / 株式会社...": ("例：新宿のカフェ / 株式会社...", "e.g. Shinjuku cafe / Co., Ltd. ..."),
        "例如 周末 10:00-18:00": ("例：週末 10:00-18:00", "e.g. weekends 10:00-18:00"),
        "11:00-22:00 / 周一休": ("11:00-22:00 / 月曜定休", "11:00-22:00 / closed Mondays"),
        "人均 ¥2,500-3,500": ("一人あたり ¥2,500-3,500", "¥2,500-3,500 per person"),
        "平日晚上 / 周末 / 需提前 2 天": ("平日夜 / 週末 / 2日前まで", "Weekday evenings / weekends / 2 days ahead"),
        "例如 2026-08-31": ("例：2026-08-31", "e.g. 2026-08-31")
    ]

    static func icon(for type: String) -> String {
        switch type {
        case "rental": "house"
        case "for_sale": "building.2"
        case "work", "job", "hiring": "briefcase"
        case "local_service": "storefront"
        case "discount": "tag"
        case "event": "calendar"
        default: "bag"
        }
    }

    /// 类目 → SF Symbol，用于发现页频道的图标类目滑栏（爱彼迎式）。
    static func categoryIcon(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "全部": return "square.grid.2x2"
        // 二手
        case "家具": return "sofa.fill"
        case "家电": return "washer.fill"
        case "手机数码": return "iphone"
        case "电脑办公": return "laptopcomputer"
        case "电子产品": return "headphones"
        case "教材", "书籍教材": return "books.vertical.fill"
        case "衣物": return "tshirt.fill"
        case "生活用品": return "house.fill"
        case "母婴儿童": return "figure.and.child.holdinghands"
        case "运动户外": return "figure.outdoor.cycle"
        case "票券卡券": return "ticket.fill"
        case "搬家出清": return "shippingbox.fill"
        case "免费送": return "gift.fill"
        case "求购": return "magnifyingglass"
        // 租房
        case "单人": return "person.fill"
        case "合租": return "person.2.fill"
        case "整租": return "house.fill"
        case "家具家电": return "sofa.fill"
        case "近车站": return "tram.fill"
        case "可宠物": return "pawprint.fill"
        case "短租": return "calendar.badge.clock"
        // 民宿
        case "民宿", "酒店", "温泉旅馆", "公寓式酒店", "短住公寓", "整套房": return "bed.double.fill"
        // 工作
        case "兼职": return "clock.fill"
        case "全职": return "briefcase.fill"
        case "派遣": return "person.badge.clock.fill"
        case "实习": return "graduationcap.fill"
        case "时给": return "yensign.circle.fill"
        case "月给": return "calendar"
        case "N3 可", "N3可": return "character.bubble.fill"
        case "签证支持": return "checkmark.seal.fill"
        case "无经验可": return "sparkles"
        case "留学生可": return "graduationcap.fill"
        default: return "tag.fill"
        }
    }

    /// 服务频道一级分区 → SF Symbol。
    static func serviceSectionIcon(_ key: String) -> String {
        switch key {
        case "all": return "square.grid.2x2"
        case "food": return "fork.knife"
        case "travel": return "airplane"
        case "transfer": return "car.fill"
        case "paperwork": return "doc.text.fill"
        case "moving": return "shippingbox.fill"
        case "life": return "house.fill"
        case "beauty": return "scissors"
        default: return "storefront.fill"
        }
    }

    static func searchPlaceholder(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental":
            (zh, ja, en) = ("搜索地区、车站、学校、房源关键词", "エリア・駅・学校・物件キーワードを検索", "Search area, station, school, keywords")
        case "stays":
            (zh, ja, en) = ("搜索民宿、整套房、地区关键词", "民泊・一棟貸し・エリアを検索", "Search homestays and whole-place stays")
        case "hotels":
            (zh, ja, en) = ("搜索民宿、整套房、地区关键词", "民泊・一棟貸し・エリアを検索", "Search homestays and whole-place stays")
        case "for_sale":
            (zh, ja, en) = ("搜索地区、车站、户型、物件关键词", "エリア・駅・間取り・物件を検索", "Search area, station, layout, property")
        case "work", "job", "hiring":
            (zh, ja, en) = ("搜索职位、公司、地点、日语要求", "職種・会社・場所・日本語レベルを検索", "Search roles, companies, locations")
        case "local_service":
            (zh, ja, en) = ("搜索餐厅、旅行票务、机场接送、翻译手续、生活服务", "飲食店、旅行チケット、空港送迎、翻訳・手続き、生活サポートを検索", "Search restaurants, travel tickets, transfers, paperwork and local support")
        case "discount":
            (zh, ja, en) = ("搜索优惠、商家、地区", "特典・店舗・エリアを検索", "Search deals, merchants, areas")
        default:
            (zh, ja, en) = ("搜索家具、家电、教材、搬家出清", "家具・家電・教材・引越し処分を検索", "Search furniture, appliances, textbooks")
        }
        return pickText(language, zh, ja, en)
    }

    static func categories(for type: String) -> [String] {
        switch type {
        case "rental": ["全部", "单人", "合租", "整租", "家具家电", "近车站"]
        case "for_sale": ["全部", "公寓", "一户建", "投资物件", "一棟", "土地"]
        case "stays": stayChips
        case "hotels": stayChips
        case "work", "job", "hiring": ["全部", "兼职", "全职", "时给", "月给", "N3 可", "签证支持", "无经验可"]
        case "local_service": ["全部"] + serviceCreateCategories
        case "discount": ["全部", "餐饮", "学校", "服务", "购物", "限时"]
        // 「免费送/求购」不是真实 category(发布端写 listing_mode attr),已移到
        // facetChips(for: "secondhand") 走 attr 通道;「教材/书籍教材」近重复,
        // 合并保留语义更宽的「书籍教材」。
        default: ["全部", "家具", "家电", "手机数码", "电脑办公", "电子产品", "书籍教材", "衣物", "生活用品", "母婴儿童", "运动户外", "票券卡券", "搬家出清"]
        }
    }

    /// 频道类目滑栏里的「属性 facet」型 chip（租房长租 / 工作频道）：点一下写入一个
    /// `attr_<key>=value` 服务端筛选（与筛选面板同一套参数）。长租与工作的滑栏项
    /// 本质是属性（家具/合租/薪资形态/日语等级/签证/无经验…）而非真实 `category`
    /// 值——旧实现把它们塞进 `categories(for:)` 当 category：服务端精确匹配
    /// `category` 列匹配不到、客户端 `category.contains` 也匹配不到，于是选中即清空
    /// 列表，而头部计数仍按未筛选全集显示（虚高）、翻页拉的也是未筛选流。改成
    /// facet 后由服务端精确筛选并计入 total，翻页也带上同一条件。key 取自
    /// `server_config.LISTING_ATTRIBUTE_KEYS`（该类型白名单内），值与筛选面板一致。
    struct ListingFacetChip: Identifiable {
        /// `attr_<key>` 的 key（须在服务端该类型白名单内）。
        let key: String
        /// attr 值（布尔用 "true"；签证兼容老数据用 "available,true"）。
        let value: String
        /// 显示/图标用的中文枚举（走 ListingFilterLocalizer + categoryIcon）。
        let labelKey: String
        var id: String { "\(key)=\(value)" }
    }

    static func facetChips(for type: String) -> [ListingFacetChip] {
        switch type {
        case "rental":
            // 长租快捷筛选：家具家电 / 合租 / 可宠物 / 短租——均为 rental 白名单内
            // 的布尔属性，与筛选面板 toggle 同一 key，滑栏与面板选中态互通。
            return [
                .init(key: "furnished", value: "true", labelKey: "家具家电"),
                .init(key: "share_allowed", value: "true", labelKey: "合租"),
                .init(key: "pet_allowed", value: "true", labelKey: "可宠物"),
                .init(key: "short_term_allowed", value: "true", labelKey: "短租"),
            ]
        case "work", "job", "hiring":
            // 工作快捷筛选：雇佣形态 / 薪资形态 / 日语等级 / 签证 / 无经验。同 key
            // 多值互斥（兼职⇄全职、时给⇄月给）天然由字典同 key 覆盖实现。工作频道
            // 同时查 job+hiring 两流，facet 会同时应用到两流（旧 category=兼职 会把
            // category=招聘 的 hiring 全部误排除，且 total 仍按两流未筛选之和虚高）。
            return [
                .init(key: "employment_type", value: "part_time", labelKey: "兼职"),
                .init(key: "employment_type", value: "full_time", labelKey: "全职"),
                .init(key: "salary_type", value: "hourly", labelKey: "时给"),
                .init(key: "salary_type", value: "monthly", labelKey: "月给"),
                .init(key: "japanese_level", value: "N3", labelKey: "N3 可"),
                // 与筛选面板「签证支持」选项同值："available,true" 兼容早期布尔存法。
                .init(key: "visa_support", value: "available,true", labelKey: "签证支持"),
                .init(key: "no_experience_ok", value: "true", labelKey: "无经验可"),
            ]
        case "secondhand":
            // 免费送/求购:发布端落库为 listing_mode attr,旧实现把它们当 category
            // 精确下发,只命中 category 恰为「免费送」的极少数老条目,attr 为 free
            // 的商品全部漏掉。改走 attr 通道后与筛选面板「发布类型」同 key 互通。
            return [
                .init(key: "listing_mode", value: "free", labelKey: "免费送"),
                .init(key: "listing_mode", value: "wanted", labelKey: "求购"),
            ]
        default:
            return []
        }
    }

    /// Display-only ja/en labels for category values. The zh string is the
    /// CANONICAL wire/storage format (listings store and filter by it —
    /// mirrors `CATEGORY_LABELS` in web ListingKit.tsx), so only the label
    /// localizes; the value sent to the API never changes. Unknown
    /// (user-typed) categories fall back to the raw value.
    private static let categoryLabels: [String: (ja: String, en: String)] = [
        "全部": ("すべて", "All"),
        "家具": ("家具", "Furniture"),
        "家电": ("家電", "Appliances"),
        "手机数码": ("スマホ・デジタル", "Phones & gadgets"),
        "电脑办公": ("PC・オフィス", "Computers & office"),
        "电子产品": ("電子機器", "Electronics"),
        "教材": ("教材", "Textbooks"),
        "书籍教材": ("本・教材", "Books & textbooks"),
        "衣物": ("衣類", "Clothing"),
        "生活用品": ("生活用品", "Daily goods"),
        "母婴儿童": ("ベビー・キッズ", "Baby & kids"),
        "运动户外": ("スポーツ・アウトドア", "Sports & outdoors"),
        "票券卡券": ("チケット・ギフト券", "Tickets & gift cards"),
        "搬家出清": ("引越し処分", "Moving sale"),
        "免费送": ("無料譲渡", "Free giveaway"),
        "求购": ("買います", "Wanted"),
        "单人": ("一人暮らし", "Single"),
        "合租": ("ルームシェア", "Roomshare"),
        "短租": ("短期", "Short-term"),
        "整租": ("まるごと賃貸", "Entire place"),
        "家具家电": ("家具家電付き", "Furnished"),
        "近车站": ("駅近", "Near station"),
        "兼职": ("アルバイト", "Part-time"),
        "全职": ("正社員", "Full-time"),
        "派遣": ("派遣", "Temp agency"),
        "实习": ("インターン", "Internship"),
        "时给": ("時給", "Hourly pay"),
        "月给": ("月給", "Monthly pay"),
        "N3 可": ("N3可", "N3 OK"),
        "无经验可": ("未経験OK", "No experience"),
        "留学生可": ("留学生OK", "Students OK"),
        "签证支持": ("ビザサポート", "Visa support"),
        "周末": ("週末", "Weekend"),
        "搬家": ("引越し", "Moving"),
        "签证": ("ビザ", "Visa"),
        "维修": ("修理", "Repair"),
        "翻译": ("翻訳", "Translation"),
        "接送": ("送迎", "Pickup"),
        "清洁": ("清掃", "Cleaning"),
        "美容美发": ("美容・ヘア", "Beauty & hair"),
        "宠物服务": ("ペットサービス", "Pet care"),
        "生活支持": ("生活サポート", "Life support"),
        "签证/手续协助": ("ビザ・手続きサポート", "Visa & paperwork"),
        "租房申请协助": ("賃貸申込サポート", "Rental application help"),
        "餐厅": ("飲食店", "Restaurants"),
        "餐厅美食": ("飲食店", "Restaurants"),
        "餐饮预约": ("飲食店", "Restaurants"),
        "餐饮点评": ("飲食口コミ", "Dining reviews"),
        "优惠预约": ("予約特典", "Deals & booking"),
        "中华料理": ("中華料理", "Chinese"),
        "日本料理": ("日本料理", "Japanese"),
        "居酒屋": ("居酒屋", "Izakaya"),
        "烧肉火锅": ("焼肉・鍋", "BBQ & hot pot"),
        "拉面": ("ラーメン", "Ramen"),
        "寿司海鲜": ("寿司・海鮮", "Sushi & seafood"),
        "咖啡甜品": ("カフェ・スイーツ", "Café & desserts"),
        "西餐": ("洋食", "Western"),
        "韩国料理": ("韓国料理", "Korean"),
        "酒店民宿": ("ホテル・民泊", "Hotels & stays"),
        "民宿": ("民泊", "Guesthouse"),
        "民泊": ("民泊", "Guesthouse"),
        "酒店": ("ホテル", "Hotel"),
        "温泉旅馆": ("温泉旅館", "Onsen ryokan"),
        "公寓式酒店": ("アパートホテル", "Aparthotel"),
        "短住公寓": ("短期アパート", "Short-stay apartment"),
        "景点门票": ("観光チケット", "Attraction tickets"),
        "一日游": ("日帰りツアー", "Day trips"),
        "本地向导": ("ローカルガイド", "Local guide"),
        "体验活动": ("体験アクティビティ", "Experiences"),
        "包车行程": ("貸切ツアー", "Chartered tour"),
        "接送机": ("空港送迎", "Airport transfer"),
        "机场接送": ("空港送迎", "Airport transfer"),
        "车站接送": ("駅送迎", "Station transfer"),
        "包车": ("貸切車", "Private car"),
        "行李协助": ("荷物サポート", "Luggage help"),
        "翻译手续": ("翻訳・手続き", "Translation & paperwork"),
        "材料翻译": ("書類翻訳", "Document translation"),
        "市役所陪同": ("役所同行", "City-office accompaniment"),
        "银行卡协助": ("銀行口座サポート", "Bank account help"),
        "手机卡协助": ("SIMサポート", "SIM card help"),
        "签证材料整理": ("ビザ書類整理", "Visa document prep"),
        "搬家清洁": ("引越し・清掃", "Moving & cleaning"),
        "退房清洁": ("退去清掃", "Move-out cleaning"),
        "粗大垃圾协助": ("粗大ごみサポート", "Oversized trash help"),
        "行李搬运": ("荷物運搬", "Luggage moving"),
        "家具家电配送协助": ("家具家電配送サポート", "Furniture delivery help"),
        "手机卡开通": ("SIM開通", "SIM setup"),
        "网络开通": ("ネット開通", "Internet setup"),
        "水电煤协助": ("ライフライン手続き", "Utilities setup"),
        "地址登记协助": ("住所登録サポート", "Address registration help"),
        "粗大垃圾预约": ("粗大ごみ予約", "Oversized trash booking"),
        "生活跑腿": ("生活代行", "Local errands"),
        "美甲": ("ネイル", "Nails"),
        "按摩": ("マッサージ", "Massage"),
        "皮肤管理": ("肌ケア", "Skin care"),
        "体检/牙科预约协助": ("健診・歯科予約サポート", "Checkup/dental booking help"),
        "宠物寄养": ("ペット預かり", "Pet boarding"),
        "遛狗": ("犬の散歩", "Dog walking"),
        "临时照看": ("一時見守り", "Temporary care"),
        "儿童用品租赁": ("子ども用品レンタル", "Kids item rental"),
        "家庭协助": ("家庭サポート", "Family support"),
        "认证服务": ("認定サービス", "Verified services"),
        "餐饮": ("飲食", "Dining"),
        "学校": ("学校", "Schools"),
        "服务": ("サービス", "Services"),
        "购物": ("ショッピング", "Shopping"),
        "限时": ("期間限定", "Limited-time"),
        "生活": ("生活", "Living"),
        "学习": ("学習", "Study"),
        "今天": ("今日", "Today"),
        "本周": ("今週", "This week"),
        "免费": ("無料", "Free"),
    ]

    static func categoryLabel(_ value: String, _ language: AppLanguage) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if language == .zh {
            switch trimmed {
            case "餐饮预约", "餐厅美食":
                return "餐厅"
            default:
                return value
            }
        }
        guard let entry = categoryLabels[trimmed] else { return value }
        switch language {
        case .ja: return entry.ja
        case .en: return entry.en
        default:  return value
        }
    }

    static func emptyTitle(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental":               (zh, ja, en) = ("这里还没有房源", "まだ物件がありません", "No rentals yet")
        case "for_sale":             (zh, ja, en) = ("这里还没有在售物件", "まだ販売物件がありません", "No properties for sale yet")
        case "stays":                (zh, ja, en) = ("这里还没有民宿", "まだ民泊がありません", "No homestays yet")
        case "hotels":               (zh, ja, en) = ("这里还没有民宿", "まだ民泊がありません", "No homestays yet")
        case "work", "job", "hiring": (zh, ja, en) = ("这里还没有工作信息", "まだ求人がありません", "No jobs yet")
        case "local_service":        (zh, ja, en) = ("这里还没有商家与服务", "まだ店舗・地域サービスがありません", "No business or local services yet")
        case "discount":             (zh, ja, en) = ("这里还没有优惠", "まだ特典がありません", "No deals yet")
        default:                     (zh, ja, en) = ("这里还没有二手商品", "まだ出品がありません", "No items yet")
        }
        return pickText(language, zh, ja, en)
    }

    static func emptySubtitle(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental":
            (zh, ja, en) = ("发布房源或稍后查看新的租房信息。", "物件を掲載するか、また後で見に来てください。", "Post a rental or check back soon.")
        case "for_sale":
            (zh, ja, en) = ("精选在售物件审核后会展示在这里，稍后再来看看。", "厳選された販売物件が審査後に表示されます。また後で見に来てください。", "Curated properties for sale appear here after review. Check back soon.")
        case "stays":
            (zh, ja, en) = ("认证服务方可以发布民宿，审核通过后展示给同城旅客。", "認証ホストの民泊が審査後に表示されます。", "Verified homestays appear here after review.")
        case "hotels":
            (zh, ja, en) = ("认证服务方可以发布民宿，审核通过后展示。", "認証ホストの民泊が審査後に表示されます。", "Verified homestays appear here after review.")
        case "work", "job", "hiring":
            (zh, ja, en) = ("稍后查看新的同城工作机会。", "新しい求人をまた後でチェックしてください。", "Check back soon for new local jobs.")
        case "local_service":
            (zh, ja, en) = ("认证商家的餐厅、旅行票务、接送交通、翻译手续、搬家清洁和生活服务审核后会展示在这里。", "認証店舗の飲食店、旅行チケット、送迎、翻訳・手続き、引越し清掃、生活サポートが審査後に表示されます。", "Verified restaurants, travel, transfers, paperwork, moving and local support appear here after review.")
        case "discount":
            (zh, ja, en) = ("商家优惠审核后会展示在这里。", "店舗特典が審査後にここに表示されます。", "Merchant deals appear here after review.")
        default:
            (zh, ja, en) = ("发布第一个闲置，让同城的人看到它。", "最初の出品をして、近くの人に届けよう。", "List the first item for your city to see.")
        }
        return pickText(language, zh, ja, en)
    }

    static func createTitle(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental": (zh, ja, en) = ("发布房源", "物件を投稿", "Post rental")
        case "job": (zh, ja, en) = ("发布求职信息", "求職情報を投稿", "Post job-seeking profile")
        case "work", "hiring": (zh, ja, en) = ("发布招聘", "求人を投稿", "Post job")
        case "local_service": (zh, ja, en) = ("发布商家与服务", "店舗・サービスを投稿", "Post business/service")
        case "discount": (zh, ja, en) = ("发布优惠", "特典を投稿", "Post deal")
        default: (zh, ja, en) = ("发布二手", "出品する", "List item")
        }
        return pickText(language, zh, ja, en)
    }

    static func createGuidance(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental":
            (zh, ja, en) = ("把租金、车站、户型、面积和入住时间写清楚，房源会更容易被认真咨询。", "家賃、駅、間取り、面積、入居時期を明確にすると、質の高い問い合わせが増えます。", "Clear rent, station, layout, size, and move-in timing bring better inquiries.")
        case "work", "job", "hiring":
            (zh, ja, en) = ("岗位、工作时间、日语要求和签证说明越清楚，越能减少无效沟通。", "職種、勤務時間、日本語レベル、ビザ条件を明確にすると無駄なやり取りを減らせます。", "Clear role, hours, Japanese level, and visa notes reduce unqualified messages.")
        case "local_service":
            (zh, ja, en) = ("先选择一级服务，再选细分类。系统只展示该服务真正需要的字段，资质、价格、服务边界和取消规则会直接影响审核与用户信任。", "大カテゴリから細分類を選ぶと、そのサービスに必要な項目だけ表示されます。資格、料金、範囲、取消規定は審査と信頼に直結します。", "Choose a primary service, then a subcategory. Only relevant fields appear; credentials, pricing, boundaries, and cancellation rules affect review and trust.")
        case "discount":
            (zh, ja, en) = ("优惠内容、有效期和使用规则需要明确，避免用户到店后产生误解。", "特典内容、有効期限、利用条件を明確にして、来店時の誤解を防ぎましょう。", "Make deal details, validity, and usage rules clear to avoid confusion in-store.")
        default:
            (zh, ja, en) = ("只需标题、分类、价格和描述就能发布；照片清楚会卖得更快，交易地点私聊再约。", "タイトル・カテゴリ・価格・説明だけで出品OK。写真がきれいだと早く売れます。受け渡し場所はメッセージで相談を。", "Just a title, category, price and description to list. Clear photos sell faster; arrange the meetup in chat.")
        }
        return pickText(language, zh, ja, en)
    }

    static func createType(for type: String) -> String {
        type == "work" ? "hiring" : type
    }

    static func submitLabel(for type: String, _ language: AppLanguage = .zh) -> String {
        type == "secondhand"
            ? pickText(language, "发布", "投稿", "Post")
            : pickText(language, "提交审核", "審査に送信", "Submit for review")
    }

    static func categoryPlaceholder(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental": (zh, ja, en) = ("类型，例如 单人 / 合租 / 整租", "種類：一人暮らし / ルームシェア / 一棟賃貸", "Type, e.g. single / share / entire place")
        case "work", "job", "hiring": (zh, ja, en) = ("行业或岗位分类", "業種または職種カテゴリ", "Industry or role category")
        case "local_service": (zh, ja, en) = ("服务分类，例如 日本料理 / 民宿 / 景点门票 / 机场接送", "サービス分類：日本料理 / 民泊 / 観光チケット / 空港送迎", "Service category, e.g. Japanese dining / stay / tickets / airport transfer")
        case "discount": (zh, ja, en) = ("优惠分类", "特典カテゴリ", "Deal category")
        default: (zh, ja, en) = ("分类，例如 家具 / 家电 / 教材", "カテゴリ：家具 / 家電 / 教材", "Category, e.g. furniture / appliances / textbooks")
        }
        return pickText(language, zh, ja, en)
    }

    static func titlePlaceholder(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental": (zh, ja, en) = ("例如 池袋 1K 公寓，可预约看房", "例：池袋 1K、内見予約可", "e.g. Ikebukuro 1K, viewing available")
        case "work", "job", "hiring": (zh, ja, en) = ("例如 新宿咖啡店周末兼职", "例：新宿カフェの週末アルバイト", "e.g. Weekend cafe shift in Shinjuku")
        case "local_service": (zh, ja, en) = ("例如 东京周末一日游 / 机场接送 / 材料翻译协助", "例：東京週末ツアー / 空港送迎 / 書類翻訳サポート", "e.g. Tokyo day tour / airport transfer / document translation")
        case "discount": (zh, ja, en) = ("例如 留学生套餐 9 折", "例：留学生セット 10% オフ", "e.g. 10% off student set")
        default: (zh, ja, en) = ("例如 日文配列键盘 / 搬家出清书桌", "例：日本語配列キーボード / 引越し処分デスク", "e.g. Japanese keyboard / moving-sale desk")
        }
        return pickText(language, zh, ja, en)
    }

    static func pricePlaceholder(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental": (zh, ja, en) = ("月租，例如 58000", "月額家賃：例 58000", "Monthly rent, e.g. 58000")
        case "work", "job", "hiring": (zh, ja, en) = ("薪资，例如 1200", "給与：例 1200", "Pay, e.g. 1200")
        default: (zh, ja, en) = ("价格，例如 8000", "価格：例 8000", "Price, e.g. 8000")
        }
        return pickText(language, zh, ja, en)
    }

    static func descriptionPlaceholder(for type: String, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch type {
        case "rental":
            (zh, ja, en) = ("写清房间状态、费用包含项、初期费用、可入住时间、看房方式。", "部屋の状態、費用に含まれるもの、初期費用、入居可能時期、内見方法を書いてください。", "Describe room condition, included costs, initial fees, move-in timing, and viewing method.")
        case "work", "job", "hiring":
            (zh, ja, en) = ("写清工作内容、薪资、排班、试用期、交通费和需要准备的材料。", "仕事内容、給与、シフト、試用期間、交通費、必要書類を書いてください。", "Describe duties, pay, schedule, probation, transport fee, and required materials.")
        case "local_service":
            (zh, ja, en) = ("写清适合谁、服务包含/不包含什么、预约规则、旅行/景点说明、取消退款规则，以及预约前需要准备的信息。", "対象者、含まれる内容・含まれない内容、予約規則、旅行/観光説明、取消・返金規定、事前準備を書いてください。", "Explain who it suits, what is included/excluded, booking rules, travel or attraction notes, cancellation/refund rules, and what users should prepare.")
        case "discount":
            (zh, ja, en) = ("写清适用门店、适用人群、不可叠加条件和使用方式。", "対象店舗、対象者、併用不可条件、利用方法を書いてください。", "Describe eligible stores, audience, non-stackable conditions, and how to use it.")
        default:
            (zh, ja, en) = ("写清购买时间、使用情况、瑕疵、配件、交易地点和是否可议价。", "購入時期、使用状況、傷、付属品、受け渡し場所、価格相談可否を書いてください。", "Describe purchase time, usage, defects, accessories, meetup location, and negotiability.")
        }
        return pickText(language, zh, ja, en)
    }

    static func defaultCategory(for type: String) -> String {
        switch type {
        case "rental": "房源"
        case "work", "job", "hiring": "职位"
        case "local_service": "商家与服务"
        case "discount": "优惠"
        default: "二手"
        }
    }

    static func formatListingType(_ type: String) -> String {
        title(for: type)
    }

    static func formatListingStatus(_ status: String, type: String? = nil, _ language: AppLanguage = .zh) -> String {
        let zh: String
        let ja: String
        let en: String
        switch normalized(status) {
        case "draft": (zh, ja, en) = ("草稿", "下書き", "Draft")
        case "pending_review": (zh, ja, en) = ("审核中", "審査中", "In review")
        case "reserved": (zh, ja, en) = ("已预约", "予約済み", "Reserved")
        case "sold": (zh, ja, en) = ("已售出", "売約済み", "Sold")
        case "rented": (zh, ja, en) = ("已租出", "成約済み", "Rented")
        case "closed": (zh, ja, en) = ("已关闭", "終了", "Closed")
        case "expired": (zh, ja, en) = ("已过期", "期限切れ", "Expired")
        case "rejected": (zh, ja, en) = ("已拒绝", "却下", "Rejected")
        case "hidden": (zh, ja, en) = ("已下架", "非公開", "Hidden")
        case "published":
            switch type {
            case "rental": (zh, ja, en) = ("可咨询", "問い合わせ可", "Open")
            case "job", "hiring": (zh, ja, en) = ("招聘中", "募集中", "Hiring")
            case "local_service": (zh, ja, en) = ("可预约", "予約可", "Bookable")
            case "discount": (zh, ja, en) = ("有效中", "有効", "Active")
            case "event": (zh, ja, en) = ("开放报名", "受付中", "Open")
            default: (zh, ja, en) = ("出售中", "販売中", "Available")
            }
        default: (zh, ja, en) = ("待补充", "未設定", "Pending")
        }
        return pickText(language, zh, ja, en)
    }

    static func formatVerificationStatus(_ status: String, _ language: AppLanguage = .zh) -> String {
        switch normalized(status) {
        case "verified": pickText(language, "认证", "認証済み", "Verified")
        case "pending": pickText(language, "待核验", "確認待ち", "Pending verification")
        case "needs_review": pickText(language, "需复核", "再確認が必要", "Needs review")
        case "rejected": pickText(language, "认证拒绝", "認証却下", "Verification rejected")
        case "unverified": pickText(language, "未认证", "未認証", "Unverified")
        default: pickText(language, "未认证", "未認証", "Unverified")
        }
    }

    static func formatEmploymentType(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        return switch normalized(value) {
        case "full_time", "full-time": "全职"
        case "part_time", "part-time": "兼职"
        case "dispatch": "派遣"
        case "contract": "契约"
        case "internship": "实习"
        case "freelance": "自由职业"
        case "temporary": "短期"
        default: value
        }
    }

    static func employmentTypeKey(_ value: String) -> String {
        switch normalized(value) {
        case "全职", "full_time", "full-time": "full_time"
        case "派遣", "dispatch": "dispatch"
        case "契约", "contract": "contract"
        case "实习", "internship": "internship"
        case "自由职业", "freelance": "freelance"
        case "短期", "temporary": "temporary"
        default: "part_time"
        }
    }

    static func employmentTypeLabel(_ value: String) -> String {
        let label = formatEmploymentType(value)
        return label.isEmpty ? "兼职" : label
    }

    static func conditionKey(_ value: String) -> String {
        switch normalized(value) {
        case "全新", "brand_new", "new": "brand_new"
        case "几乎全新", "like_new": "like_new"
        case "有使用痕迹", "used": "used"
        case "可用", "fair": "fair"
        default: "good"
        }
    }

    static func conditionLabel(_ value: String) -> String {
        switch normalized(value) {
        case "brand_new", "new", "全新": "全新"
        case "like_new", "几乎全新": "几乎全新"
        case "used", "有使用痕迹": "有使用痕迹"
        case "fair", "可用": "可用"
        default: "良好"
        }
    }

    static func listingModeKey(_ value: String) -> String {
        switch normalized(value) {
        case "免费送", "free", "giveaway": "free"
        case "求购", "wanted", "buy": "wanted"
        default: "sale"
        }
    }

    static func listingModeLabel(_ value: String) -> String {
        switch normalized(value) {
        case "free", "giveaway", "免费送": "免费送"
        case "wanted", "buy", "求购": "求购"
        default: "出售"
        }
    }

    static func formatSalaryType(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        return switch normalized(value) {
        case "hourly", "hour": "时给"
        case "daily": "日给"
        case "weekly": "周给"
        case "monthly", "month": "月给"
        case "annual", "yearly": "年薪"
        case "fixed": "固定价"
        case "negotiable": "可商量"
        default: value
        }
    }

    static func formatCurrency(_ currency: String?) -> String {
        switch normalized(currency ?? "JPY").uppercased() {
        case "JPY": "日元"
        case "CNY": "人民币"
        case "USD": "美元"
        case "EUR": "欧元"
        case "KRW": "韩元"
        default: cleanText(currency) ?? "日元"
        }
    }

    static func formatPrice(_ listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> String {
        formatPrice(
            price: listing.price,
            currency: listing.currency,
            priceType: listing.price_type ?? listing.priceType,
            type: listing.type,
            listingMode: listing.attributes?["listing_mode"]?.listingDisplayValue,
            language
        )
    }

    /// 原始数据版价格标签:收藏快照等没有完整 DTO 的场景也能用当前语言现算。
    /// listingMode 传 attributes["listing_mode"] 原值——发布端 price_type 恒按
    /// 类型写死(二手=fixed),按表单指引「免费送可填 0」发布的商品若只看
    /// price>0 会掉进「价格咨询」,与卡上「免费送」徽章直接矛盾。
    static func formatPrice(price: Double?, currency: String?, priceType rawPriceType: String?, type: String, listingMode: String? = nil, _ language: AppLanguage = .zh) -> String {
        let priceType = normalized(rawPriceType ?? "")
        if priceType == "free" { return pickText(language, "免费", "無料", "Free") }
        if let mode = listingMode.map(normalized), mode == "free" || mode == "giveaway" || mode == "免费送" {
            return pickText(language, "免费", "無料", "Free")
        }
        if ["appointment_only", "quote_required", "consultation", "negotiable"].contains(priceType) {
            return fallbackPriceLabel(for: type, language)
        }
        guard let price, price.isFinite, price > 0 else {
            return fallbackPriceLabel(for: type, language)
        }
        let amount = price.rounded() == price
            ? NumberFormatter.localizedString(from: NSNumber(value: Int(price)), number: .decimal)
            : String(format: "%.2f", price)
        let code = (currency ?? "JPY").uppercased()
        let prefix: String = {
            switch code {
            case "JPY", "CNY": return "¥"
            case "USD": return "$"
            case "EUR": return "€"
            case "KRW": return "₩"
            default: return "\(code) "
            }
        }()
        let rendered = "\(prefix)\(amount)"
        switch priceType {
        case "monthly", "month": return "\(rendered)\(pickText(language, "/月", "/月", "/mo"))"
        case "hourly", "hour": return "\(rendered)\(pickText(language, "/小时", "/時", "/hr"))"
        case "per_night", "nightly": return "\(rendered)\(pickText(language, "/晚", "/泊", "/night"))"
        case "daily": return "\(rendered)\(pickText(language, "/日", "/日", "/day"))"
        case "weekly": return "\(rendered)\(pickText(language, "/周", "/週", "/wk"))"
        case "yearly", "annual": return "\(rendered)\(pickText(language, "/年", "/年", "/yr"))"
        case "starting_from": return "\(rendered) \(pickText(language, "起", "から", "and up"))"
        default:
            if type == "rental" { return "\(rendered)\(pickText(language, "/月", "/月", "/mo"))" }
            if type == "job" || type == "hiring" { return "\(rendered)\(pickText(language, "/小时", "/時", "/hr"))" }
            return rendered
        }
    }

    /// 卡片用紧凑面积:数据里可能自带单位(「30.1 m²」),剥掉再统一补 ㎡,
    /// 避免渲染出「30.1 m²㎡」双单位。
    static func compactArea(_ value: String?) -> String? {
        guard var text = cleanText(value) else { return nil }
        for unit in ["m²", "㎡", "平方米", "平米", "m2"] {
            if text.lowercased().hasSuffix(unit.lowercased()) {
                text = String(text.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard !text.isEmpty else { return nil }
        return "\(text)㎡"
    }

    static func formatArea(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        if let number = Double(value), number.isFinite, number > 0 {
            let text = number.rounded() == number ? "\(Int(number))" : String(format: "%.1f", number)
            return "\(text) m²"
        }
        return value
    }

    static func formatStationDistance(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        if let number = Double(value), number.isFinite, number > 0 {
            return "步行 \(Int(number.rounded())) 分钟"
        }
        return value
    }

    static func formatDate(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return value
    }

    static func formatJapaneseLevel(_ value: String?) -> String {
        guard let value = cleanText(value) else { return "" }
        switch normalized(value) {
        case "not_required", "none", "no_requirement":
            return "不限"
        case "native":
            return "母语级"
        case "business":
            return "商务日语"
        case "daily":
            return "日常会话"
        default:
            let upper = value.uppercased()
            return ["N1", "N2", "N3", "N4", "N5"].contains(upper) ? upper : value
        }
    }

    static func priceLabel(_ listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> String {
        formatPrice(listing, language)
    }

    static func displayTitle(_ listing: KaiXCityListingDTO) -> String {
        guard listing.type == "rental" else { return listing.title }
        return listing.title
            .replacingOccurrences(of: "，外国人可咨询", with: "，可预约看房")
            .replacingOccurrences(of: "外国人可咨询", with: "可预约看房")
            .replacingOccurrences(of: "，外国人可", with: "")
            .replacingOccurrences(of: "外国人可", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compactMeta(_ listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> String {
        [cleanText(listing.location_text), attr(listing, "condition"), attr(listing, "available_time"), statusLabel(listing.status, type: listing.type, language)]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    static func structuredMeta(_ listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> String {
        switch listing.type {
        case "rental":
            return [cleanText(listing.location_text), attr(listing, "nearest_station"), attr(listing, "layout"), attr(listing, "area_sqm")]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        case "job", "hiring":
            let level = attr(listing, "japanese_level") ?? pickText(language, "未注明", "未記入", "Not specified")
            return [attr(listing, "company_name"), cleanText(listing.location_text), attr(listing, "employment_type"), "\(pickText(language, "日语", "日本語", "Japanese")) \(level)"]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        case "local_service":
            return [attr(listing, "service_type"), attr(listing, "service_area"), attr(listing, "price_unit"), attr(listing, "availability")]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        case "discount":
            return [attr(listing, "merchant_name"), cleanText(listing.location_text), attr(listing, "valid_until").map { "\(pickText(language, "有效至", "有効期限", "Valid until")) \($0)" }]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " · ")
        default:
            return compactMeta(listing, language)
        }
    }

    static func badges(for listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> [String] {
        var result: [String] = []
        if listing.verification_status == "pending" { result.append(formatVerificationStatus(listing.verification_status, language)) }
        if listing.verification_status == "verified" { result.append(formatVerificationStatus(listing.verification_status, language)) }
        switch listing.type {
        case "rental":
            if boolAttr(listing, "short_term_allowed") { result.append(pickText(language, "短租", "短期可", "Short-term")) }
            if boolAttr(listing, "share_allowed") { result.append(pickText(language, "合租", "シェア可", "Shared OK")) }
            if boolAttr(listing, "furnished") { result.append(pickText(language, "家具家电", "家具家電付き", "Furnished")) }
        case "job", "hiring":
            if boolAttr(listing, "visa_support") { result.append(pickText(language, "签证支持", "ビザサポート", "Visa support")) }
            if let level = attr(listing, "japanese_level") { result.append("\(pickText(language, "日语", "日本語", "Japanese")) \(level)") }
            if let employment = attr(listing, "employment_type") { result.append(employment) }
        case "local_service":
            if let service = attr(listing, "service_type") { result.append(service) }
            if boolAttr(listing, "certified_provider") || listing.verification_status == "verified" { result.append(pickText(language, "认证服务方", "認証済みサービス", "Verified provider")) }
            if let area = attr(listing, "service_area") { result.append(area) }
        case "discount":
            if let merchant = attr(listing, "merchant_name") { result.append(merchant) }
            if let validUntil = attr(listing, "valid_until") { result.append("\(pickText(language, "有效至", "有効期限", "Valid until")) \(validUntil)") }
            if boolAttr(listing, "merchant_verified") || listing.verification_status == "verified" { result.append(pickText(language, "认证商家", "認証済み店舗", "Verified merchant")) }
        default:
            if let condition = attr(listing, "condition") { result.append(condition) }
            if boolAttr(listing, "pickup_available") { result.append(pickText(language, "可自取", "手渡し可", "Pickup OK")) }
            if boolAttr(listing, "shipping_available") { result.append(pickText(language, "可邮寄", "配送可", "Shipping OK")) }
            if let time = attr(listing, "available_time") { result.append(time) }
        }
        return result
    }

    static func secondhandCardBadges(for listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> [String] {
        guard listing.type == "secondhand" else { return [] }
        var result: [String] = []
        // 「出售」是默认态不占 chip;只有免费送/求购是真正的差异信息。
        let mode = rawAttribute(listing, "listing_mode")
        if !mode.isEmpty {
            switch listingModeKey(mode) {
            case "free": result.append(pickText(language, "免费送", "無料譲渡", "Free giveaway"))
            case "wanted": result.append(pickText(language, "求购", "買います", "Wanted"))
            default: break
            }
        }
        // 新旧程度最有信息量,排最前(旧序排最后,永远被 prefix(2) 挤掉)。
        if let condition = attr(listing, "condition") { result.append(condition) }
        if boolAttr(listing, "price_negotiable") { result.append(pickText(language, "可议价", "価格相談可", "Negotiable")) }
        if boolAttr(listing, "pickup_available") { result.append(pickText(language, "可自取", "手渡し可", "Pickup OK")) }
        if boolAttr(listing, "shipping_available") { result.append(pickText(language, "可邮寄", "配送可", "Shipping OK")) }
        return result
    }

    /// 二手卡底部 meta:「地点 · 相对时间」。condition / status 已由 chips 与
    /// 封面 badge 承担,不再重复(compactMeta 仍服务其他频道的兜底行)。
    static func secondhandCompactMeta(_ listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> String {
        let published = listing.published_at ?? listing.publishedAt ?? listing.created_at ?? listing.createdAt
        let relative = KXDateParsing.parse(published).map { DateFormatterUtils.relativeText(from: $0, language: language) }
        return [cleanText(listing.location_text), relative]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    /// 免费送判定(价格胶囊/徽章用),与 formatPrice 的免费分支同一套口径。
    static func isFreeListing(_ listing: KaiXCityListingDTO) -> Bool {
        if normalized(listing.price_type ?? listing.priceType ?? "") == "free" { return true }
        let mode = rawAttribute(listing, "listing_mode")
        return !mode.isEmpty && listingModeKey(mode) == "free"
    }

    /// 已预约/已售出等「不可再买」状态:列表沉底 + 卡面置灰。
    static func isMutedListingStatus(_ status: String) -> Bool {
        ["reserved", "sold", "rented"].contains(normalized(status))
    }

    static func attributes(for listing: KaiXCityListingDTO, _ language: AppLanguage = .zh) -> [(String, String)] {
        let base: [(String, String?)]
        switch listing.type {
        case "rental":
            base = [
                ("月租", priceLabel(listing, language)),
                ("地区", cleanText(listing.location_text)),
                ("最近车站", attr(listing, "nearest_station")),
                ("沿线", attr(listing, "nearest_lines")),
                ("户型", attr(listing, "layout")),
                ("面积", attr(listing, "area_sqm")),
                ("物件类型", attr(listing, "building_type")),
                ("所在楼层", attr(listing, "room_no")),
                ("总层数", attr(listing, "total_floors")),
                ("築年", attr(listing, "building_age")),
                ("入住时间", attr(listing, "move_in_date")),
                ("合租", boolAttr(listing, "share_allowed") ? "可" : "未注明"),
                ("短租", boolAttr(listing, "short_term_allowed") ? "可" : "未注明"),
                ("家具家电", boolAttr(listing, "furnished") ? "有" : "未注明"),
                ("设备设施", attr(listing, "amenities")),
                ("周边设施", attr(listing, "nearby_facilities")),
                ("物件番号", attr(listing, "property_no")),
                ("状态", attr(listing, "availability_status")),
                ("最新确认", attr(listing, "confirmed_at")),
                ("原始链接", attr(listing, "source_url")),
            ]
        case "for_sale":
            base = [
                ("販売価格", priceLabel(listing, language)),
                ("首付", attr(listing, "down_payment")),
                ("利回り", attr(listing, "yield_rate")),
                ("地区", cleanText(listing.location_text)),
                ("物件类型", attr(listing, "building_type")),
                ("户型", attr(listing, "layout")),
                ("面积", attr(listing, "area_sqm")),
                ("土地面积", attr(listing, "land_area")),
                ("所在楼层", attr(listing, "room_no")),
                ("楼层", attr(listing, "floor")),
                ("总层数", attr(listing, "total_floors")),
                ("築年", attr(listing, "building_age")),
                ("構造", attr(listing, "structure")),
                ("最寄駅", attr(listing, "nearest_station")),
                ("徒歩分", attr(listing, "station_distance_minutes")),
                ("沿线", attr(listing, "nearest_lines")),
                ("管理费", attr(listing, "management_fee")),
                ("设备设施", attr(listing, "amenities")),
                ("周边设施", attr(listing, "nearby_facilities")),
                ("物件番号", attr(listing, "property_no")),
                ("需要改造", attr(listing, "needs_renovation")),
                ("状态", attr(listing, "availability_status")),
                ("最新确认", attr(listing, "confirmed_at")),
                ("原始链接", attr(listing, "source_url")),
            ]
        case "job", "hiring":
            // visa_support 历史上存过布尔（true/false），现统一为枚举
            // none/consult/available——两种 wire 值都要能读。
            let visaRaw = rawAttribute(listing, "visa_support")
            let visaLabel: String? = switch visaRaw {
            case "available", "true", "1", "yes": "支持"
            case "consult": "可咨询"
            case "none", "false": "无"
            default: nil
            }
            base = [
                ("薪资", priceLabel(listing, language)),
                ("公司/店铺", attr(listing, "company_name")),
                ("地点", cleanText(listing.location_text)),
                ("雇佣形式", attr(listing, "employment_type")),
                ("日语要求", attr(listing, "japanese_level")),
                ("签证支持", visaLabel ?? "未注明"),
                ("工作时间", attr(listing, "working_hours")),
                ("休日休假", attr(listing, "holidays")),
                ("试用期", attr(listing, "trial_period")),
                ("福利待遇", attr(listing, "benefits")),
                ("无经验可", boolAttr(listing, "no_experience_ok") ? "可" : nil),
                ("留学生可", boolAttr(listing, "student_ok") ? "可" : nil),
                ("可远程", boolAttr(listing, "remote_ok") ? "可" : nil),
                ("审核状态", verificationLabel(listing.verification_status, language)),
            ]
        case "local_service":
            switch serviceVertical(for: listing) {
            case .foodRestaurant?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("营业时间", attr(listing, "open_hours")),
                    ("价格区间", attr(listing, "price_range")),
                    ("最近车站", attr(listing, "near_station")),
                    ("到店电话", attr(listing, "store_phone")),
                    ("预约制", boolAttr(listing, "reservation_required") ? "需要预约" : nil),
                    ("预约说明", attr(listing, "reservation_note")),
                    ("服务语言", attr(listing, "languages")),
                    ("认证服务方", boolAttr(listing, "certified_provider") || listing.verification_status == "verified" ? "已认证" : nil),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .diningBooking?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("营业时间", attr(listing, "open_hours")),
                    ("价格区间", attr(listing, "price_range")),
                    ("最近车站", attr(listing, "near_station")),
                    ("到店电话", attr(listing, "store_phone")),
                    ("可预约时间", attr(listing, "availability")),
                    ("预约制", boolAttr(listing, "booking_required") || boolAttr(listing, "reservation_required") ? "需要预约" : nil),
                    ("预约说明", attr(listing, "reservation_note")),
                    ("服务流程", attr(listing, "service_process")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("服务语言", attr(listing, "languages")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .lodging?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("房型", attr(listing, "room_type")),
                    ("可住人数", attr(listing, "max_guests")),
                    ("价格单位", attr(listing, "price_unit")),
                    ("入住办理", attr(listing, "check_in_time")),
                    ("退房时间", attr(listing, "check_out_time")),
                    ("最少入住", attr(listing, "minimum_stay")),
                    ("设施服务", attr(listing, "amenities")),
                    ("房量与日期", attr(listing, "inventory_note")),
                    ("含早餐", boolAttr(listing, "breakfast_included") ? "包含" : nil),
                    ("即时确认", boolAttr(listing, "instant_confirmation") ? "支持" : nil),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("资质/许可说明", attr(listing, "license_note")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .attractionTicket?, .dayTour?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("票种", attr(listing, "ticket_type")),
                    ("日期/有效期", attr(listing, "availability")),
                    ("时长", attr(listing, "duration")),
                    ("集合地点", attr(listing, "meeting_point")),
                    ("包含内容", attr(listing, "included_items")),
                    ("不包含内容", attr(listing, "not_included")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("含酒店接送", boolAttr(listing, "pickup_service") ? "包含" : nil),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("资质/许可说明", attr(listing, "license_note")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .airportTransfer?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("机场/路线", attr(listing, "airport_route")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("车型", attr(listing, "vehicle_type")),
                    ("人数", attr(listing, "passenger_count")),
                    ("行李数", attr(listing, "luggage_count")),
                    ("航班号说明", attr(listing, "flight_info_note")),
                    ("等待规则", attr(listing, "waiting_rule")),
                    ("夜间/追加费用", attr(listing, "surcharge_note")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .paperworkTranslation?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务语言", attr(listing, "languages")),
                    ("文件/手续类型", attr(listing, "document_type")),
                    ("所需材料", attr(listing, "required_materials")),
                    ("交付时间", attr(listing, "delivery_time")),
                    ("服务流程", attr(listing, "service_process")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("结果说明", boolAttr(listing, "no_result_guarantee") ? "不保证结果" : nil),
                    ("资质/许可说明", attr(listing, "license_note")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .movingCleaning?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("房型/面积", attr(listing, "property_size")),
                    ("物品量", attr(listing, "item_volume")),
                    ("车辆/人员", attr(listing, "vehicle_staff")),
                    ("包含内容", attr(listing, "included_items")),
                    ("不包含内容", attr(listing, "not_included")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("追加费用", attr(listing, "surcharge_note")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .lifeSetup?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("办理类型", attr(listing, "setup_type")),
                    ("所需材料", attr(listing, "required_materials")),
                    ("交付时间", attr(listing, "delivery_time")),
                    ("服务流程", attr(listing, "service_process")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("结果说明", attr(listing, "cannot_guarantee")),
                    ("价格区间", attr(listing, "price_range")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .beautyHealth?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("服务项目", attr(listing, "beauty_service")),
                    ("可预约时间", attr(listing, "availability")),
                    ("价格区间", attr(listing, "price_range")),
                    ("服务时长", attr(listing, "duration")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("安全说明", attr(listing, "medical_disclaimer")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .petFamily?:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("服务对象", attr(listing, "service_target")),
                    ("可预约时间", attr(listing, "availability")),
                    ("价格区间", attr(listing, "price_range")),
                    ("用户需准备", attr(listing, "user_prepare")),
                    ("资质/许可说明", attr(listing, "license_note")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            case .none:
                base = [
                    ("起步价格", priceLabel(listing, language)),
                    ("服务方", attr(listing, "business_name")),
                    ("服务类型", attr(listing, "service_type")),
                    ("服务范围", attr(listing, "service_area") ?? cleanText(listing.location_text)),
                    ("价格单位", attr(listing, "price_unit")),
                    ("可预约时间", attr(listing, "availability")),
                    ("服务流程", attr(listing, "service_process")),
                    ("取消规则", attr(listing, "cancellation_rule")),
                    ("审核状态", verificationLabel(listing.verification_status, language)),
                ]
            }
        case "discount":
            base = [
                ("优惠", priceLabel(listing, language)),
                ("商家", attr(listing, "merchant_name")),
                ("地点", cleanText(listing.location_text)),
                ("优惠内容", attr(listing, "discount_info")),
                ("有效期", attr(listing, "valid_until")),
                ("使用规则", attr(listing, "usage_rules")),
                ("商家认证", boolAttr(listing, "merchant_verified") || listing.verification_status == "verified" ? "已认证" : "待核验"),
            ]
        default:
            base = [
                ("价格", priceLabel(listing, language)),
                ("地点", cleanText(listing.location_text)),
                ("分类", cleanText(listing.category)),
                ("发布类型", attr(listing, "listing_mode")),
                ("品牌", attr(listing, "brand")),
                ("新旧程度", attr(listing, "condition")),
                ("原价/参考价", attr(listing, "original_price")),
                ("价格可议", boolAttr(listing, "price_negotiable") ? "可商量" : nil),
                ("购买时间", attr(listing, "purchase_time")),
                ("配件/包装", attr(listing, "accessories")),
                ("瑕疵说明", attr(listing, "defect_note")),
                ("可交易时间", attr(listing, "available_time")),
                ("交易方式", attr(listing, "delivery_method")),
                ("取货说明", attr(listing, "pickup_note")),
                ("状态", statusLabel(listing.status, type: listing.type, language)),
            ]
        }
        return base.compactMap { key, value in
            guard let value, !value.isEmpty else { return nil }
            return (localizedAttributeLabel(key, language), localizedAttributeValue(value, language))
        }
    }

    private static func localizedAttributeLabel(_ key: String, _ language: AppLanguage) -> String {
        switch key {
        case "月租": pickText(language, "月租", "月額家賃", "Monthly rent")
        case "地区": pickText(language, "地区", "エリア", "Area")
        case "最近车站": pickText(language, "最近车站", "最寄り駅", "Nearest station")
        case "户型": pickText(language, "户型", "間取り", "Layout")
        case "面积": pickText(language, "面积", "面積", "Area size")
        case "入住时间": pickText(language, "入住时间", "入居時期", "Move-in")
        case "合租": pickText(language, "合租", "シェア", "Shared")
        case "短租": pickText(language, "短租", "短期", "Short-term")
        case "家具家电": pickText(language, "家具家电", "家具家電", "Furnished")
        case "薪资": pickText(language, "薪资", "給与", "Pay")
        case "公司/店铺": pickText(language, "公司/店铺", "会社・店舗", "Company/store")
        case "地点": pickText(language, "地点", "場所", "Location")
        case "雇佣形式": pickText(language, "雇佣形式", "雇用形態", "Employment type")
        case "日语要求": pickText(language, "日语要求", "日本語要件", "Japanese level")
        case "签证支持": pickText(language, "签证支持", "ビザサポート", "Visa support")
        case "工作时间": pickText(language, "工作时间", "勤務時間", "Working hours")
        case "休日休假": pickText(language, "休日休假", "休日・休暇", "Holidays")
        case "试用期": pickText(language, "试用期", "試用期間", "Trial period")
        case "福利待遇": pickText(language, "福利待遇", "福利厚生", "Benefits")
        case "无经验可": pickText(language, "无经验可", "未経験可", "No experience OK")
        case "留学生可": pickText(language, "留学生可", "留学生可", "Students OK")
        case "可远程": pickText(language, "可远程", "リモート可", "Remote OK")
        case "审核状态": pickText(language, "审核状态", "審査状態", "Review status")
        case "起步价格": pickText(language, "起步价格", "開始価格", "Starting price")
        case "服务方": pickText(language, "服务方", "提供者", "Provider")
        case "服务类型": pickText(language, "服务类型", "サービス種別", "Service type")
        case "服务范围": pickText(language, "服务范围", "対応範囲", "Service area")
        case "营业时间": pickText(language, "营业时间", "営業時間", "Hours")
        case "价格区间": pickText(language, "价格区间", "価格帯", "Price range")
        case "到店电话": pickText(language, "到店电话", "店舗電話", "Phone")
        case "预约制": pickText(language, "预约制", "予約制", "Reservation")
        case "预约说明": pickText(language, "预约说明", "予約説明", "Booking notes")
        case "服务语言": pickText(language, "服务语言", "対応言語", "Languages")
        case "认证服务方": pickText(language, "认证服务方", "認証済み提供者", "Verified provider")
        case "可预约时间": pickText(language, "可预约时间", "予約可能時間", "Available times")
        case "服务流程": pickText(language, "服务流程", "サービス手順", "Service flow")
        case "取消规则": pickText(language, "取消规则", "キャンセル規定", "Cancellation")
        case "房型": pickText(language, "房型", "部屋タイプ", "Room type")
        case "可住人数": pickText(language, "可住人数", "定員", "Guests")
        case "价格单位": pickText(language, "价格单位", "価格単位", "Price unit")
        case "入住办理": pickText(language, "入住办理", "チェックイン", "Check-in")
        case "退房时间": pickText(language, "退房时间", "チェックアウト", "Check-out")
        case "最少入住": pickText(language, "最少入住", "最低宿泊", "Minimum stay")
        case "设施服务": pickText(language, "设施服务", "設備", "Amenities")
        case "房量与日期": pickText(language, "房量与日期", "空室・日程", "Availability")
        case "含早餐": pickText(language, "含早餐", "朝食付き", "Breakfast")
        case "即时确认": pickText(language, "即时确认", "即時確認", "Instant confirmation")
        case "资质/许可说明": pickText(language, "资质/许可说明", "資格・許可", "License notes")
        case "票种": pickText(language, "票种", "チケット種別", "Ticket type")
        case "日期/有效期": pickText(language, "日期/有效期", "日付・有効期限", "Date/validity")
        case "时长": pickText(language, "时长", "所要時間", "Duration")
        case "集合地点": pickText(language, "集合地点", "集合場所", "Meeting point")
        case "包含内容": pickText(language, "包含内容", "含まれるもの", "Included")
        case "不包含内容": pickText(language, "不包含内容", "含まれないもの", "Not included")
        case "用户需准备": pickText(language, "用户需准备", "利用者の準備", "User preparation")
        case "含酒店接送": pickText(language, "含酒店接送", "ホテル送迎", "Hotel pickup")
        case "机场/路线": pickText(language, "机场/路线", "空港・ルート", "Airport/route")
        case "车型": pickText(language, "车型", "車種", "Vehicle")
        case "人数": pickText(language, "人数", "人数", "Passengers")
        case "行李数": pickText(language, "行李数", "荷物数", "Luggage")
        case "航班号说明": pickText(language, "航班号说明", "便名メモ", "Flight notes")
        case "等待规则": pickText(language, "等待规则", "待機ルール", "Waiting rules")
        case "夜间/追加费用": pickText(language, "夜间/追加费用", "夜間・追加料金", "Surcharges")
        case "文件/手续类型": pickText(language, "文件/手续类型", "書類・手続き種別", "Document type")
        case "所需材料": pickText(language, "所需材料", "必要書類", "Required materials")
        case "交付时间": pickText(language, "交付时间", "納期", "Delivery time")
        case "结果说明": pickText(language, "结果说明", "結果の説明", "Result notes")
        case "房型/面积": pickText(language, "房型/面积", "部屋・面積", "Property size")
        case "物品量": pickText(language, "物品量", "荷物量", "Item volume")
        case "车辆/人员": pickText(language, "车辆/人员", "車両・人員", "Vehicle/staff")
        case "办理类型": pickText(language, "办理类型", "手続き種別", "Setup type")
        case "服务项目": pickText(language, "服务项目", "サービス項目", "Service items")
        case "服务时长": pickText(language, "服务时长", "施術時間", "Service duration")
        case "安全说明": pickText(language, "安全说明", "安全説明", "Safety notes")
        case "服务对象": pickText(language, "服务对象", "対象", "Service target")
        case "优惠": pickText(language, "优惠", "特典", "Deal")
        case "商家": pickText(language, "商家", "店舗", "Merchant")
        case "优惠内容": pickText(language, "优惠内容", "特典内容", "Deal details")
        case "有效期": pickText(language, "有效期", "有効期限", "Valid until")
        case "使用规则": pickText(language, "使用规则", "利用条件", "Usage rules")
        case "商家认证": pickText(language, "商家认证", "店舗認証", "Merchant verification")
        case "价格": pickText(language, "价格", "価格", "Price")
        case "分类": pickText(language, "分类", "カテゴリ", "Category")
        case "发布类型": pickText(language, "发布类型", "投稿種別", "Listing mode")
        case "品牌": pickText(language, "品牌", "ブランド", "Brand")
        case "新旧程度": pickText(language, "新旧程度", "状態", "Condition")
        case "原价/参考价": pickText(language, "原价/参考价", "元値・参考価格", "Original/reference")
        case "价格可议": pickText(language, "价格可议", "価格相談", "Negotiable")
        case "购买时间": pickText(language, "购买时间", "購入時期", "Purchase time")
        case "配件/包装": pickText(language, "配件/包装", "付属品・箱", "Accessories/box")
        case "瑕疵说明": pickText(language, "瑕疵说明", "傷・不具合", "Defects")
        case "可交易时间": pickText(language, "可交易时间", "取引可能時間", "Available time")
        case "交易方式": pickText(language, "交易方式", "取引方法", "Handoff")
        case "取货说明": pickText(language, "取货说明", "受け渡しメモ", "Pickup notes")
        case "状态": pickText(language, "状态", "状態", "Status")
        case "物件类型": pickText(language, "物件类型", "物件種別", "Property type")
        case "土地面积": pickText(language, "土地面积", "土地面積", "Land area")
        case "楼层": pickText(language, "楼层", "所在階", "Floor")
        case "築年": pickText(language, "築年", "築年数", "Building age")
        case "構造": pickText(language, "構造", "構造", "Structure")
        case "最寄駅": pickText(language, "最寄駅", "最寄り駅", "Nearest station")
        case "徒歩分": pickText(language, "徒歩分", "駅徒歩", "Walk to station")
        case "沿线": pickText(language, "沿线", "沿線", "Train lines")
        case "管理费": pickText(language, "管理费", "管理費", "Management fee")
        case "利回り": pickText(language, "利回り", "利回り", "Yield")
        case "販売価格": pickText(language, "販売价格", "販売価格", "Sale price")
        case "原始链接": pickText(language, "原始链接", "元リンク", "Source link")
        case "所在楼层": pickText(language, "所在楼层", "所在階", "Floor")
        case "总层数": pickText(language, "总层数", "総階数", "Total floors")
        case "设备设施": pickText(language, "设备设施", "設備・共用施設", "Amenities")
        case "周边设施": pickText(language, "周边设施", "周辺施設", "Nearby")
        case "物件番号": pickText(language, "物件番号", "物件番号", "Property no.")
        case "最新确认": pickText(language, "最新确认", "最新確認日", "Last confirmed")
        case "首付": pickText(language, "首付", "頭金", "Down payment")
        case "需要改造": pickText(language, "需要改造", "リフォーム要否", "Renovation")
        default: key
        }
    }

    private static func localizedAttributeValue(_ value: String, _ language: AppLanguage) -> String {
        switch value {
        case "可": pickText(language, "可", "可", "Yes")
        case "有": pickText(language, "有", "あり", "Yes")
        case "无": pickText(language, "无", "なし", "No")
        case "未注明": pickText(language, "未注明", "未記入", "Not specified")
        case "支持": pickText(language, "支持", "対応", "Supported")
        case "可咨询": pickText(language, "可咨询", "相談可", "Consultable")
        case "需要预约": pickText(language, "需要预约", "予約が必要", "Reservation required")
        case "已认证": pickText(language, "已认证", "認証済み", "Verified")
        case "待核验": pickText(language, "待核验", "確認待ち", "Pending verification")
        case "包含": pickText(language, "包含", "含む", "Included")
        case "不保证结果": pickText(language, "不保证结果", "結果保証なし", "No result guarantee")
        case "可商量": pickText(language, "可商量", "相談可", "Negotiable")
        default: value
        }
    }

    /// Listing types that warrant extra-prominent (high-risk) safety framing.
    static func isHighRisk(_ type: String) -> Bool {
        ["rental", "work", "job", "hiring", "local_service", "discount"].contains(type)
    }

    static func safetyTips(for type: String, _ language: AppLanguage = .zh) -> [String] {
        baseSafetyTips(for: type, language) + [
            pickText(language,
                     "谨防站外交易：不点陌生链接、不私下加站外好友打款，沟通与交易尽量留在 Machi 内，遇到可疑行为立即举报",
                     "プラットフォーム外取引に注意：不審なリンクを開かず、外部で個別送金せず、やり取りと取引は Machi 内で行い、不審な行為はすぐ通報してください",
                     "Beware off-platform deals: don't open unknown links or pay outside the app; keep chat and trades on Machi and report anything suspicious")
        ]
    }

    private static func baseSafetyTips(for type: String, _ language: AppLanguage = .zh) -> [String] {
        if type == "rental" {
            return [
                pickText(language, "Machi 不代收押金、订金或房租", "Machi は敷金・申込金・家賃を預かりません", "Machi does not hold deposits, reservation fees, or rent"),
                pickText(language, "不要提前转账，先核实房源和发布者身份", "事前送金は避け、物件と投稿者の本人確認をしてください", "Do not transfer money upfront; verify the listing and poster first"),
                pickText(language, "避免暴露完整住址，线下看房注意安全", "詳細住所の公開は避け、内見時は安全に注意してください", "Avoid exposing the full address and stay safe during viewings"),
                pickText(language, "遇到虚假地址、假照片或可疑收费立即举报", "偽住所、偽写真、不審な請求はすぐ通報してください", "Report fake addresses, fake photos, or suspicious fees immediately")
            ]
        }
        if type == "work" || type == "job" || type == "hiring" {
            return [
                pickText(language, "招聘不允许押金、保证金或培训费骗局", "求人で敷金・保証金・研修費を請求する詐欺は禁止です", "Jobs must not require deposits, guarantees, or training-fee scams"),
                pickText(language, "核实招聘方身份、工作地点和签证支持说明", "採用側の身元、勤務地、ビザサポート条件を確認してください", "Verify the employer, work location, and visa-support details"),
                pickText(language, "警惕虚假高薪、违法兼职和灰产招聘", "不自然な高収入、違法バイト、グレーな求人に注意してください", "Watch for fake high pay, illegal gigs, or gray-market jobs"),
                pickText(language, "遇到可疑内容立即举报", "不審な内容はすぐ通報してください", "Report suspicious content immediately")
            ]
        }
        if type == "local_service" {
            return [
                pickText(language, "商家与服务默认进入审核，服务方认证状态会展示", "店舗・サービスは原則審査され、提供者の認証状態が表示されます", "Business and service posts are reviewed, and provider verification is shown"),
                pickText(language, "餐饮、住宿、票务、旅行、接送交通和手续协助需写清资质、包含/不包含内容和取消规则", "飲食、宿泊、チケット、旅行、送迎、手続き支援は資格、含まれる/含まれない内容、取消規定を明記してください", "Dining, stays, tickets, travel, transfers, and paperwork help must state credentials, inclusions/exclusions, and cancellation rules"),
                pickText(language, "暂不开放外卖配送、维修安装、学习咨询；禁止成人服务、高风险线下服务和违法服务", "デリバリー、修理設置、学習相談は現在対象外です。成人向け、高リスク対面、違法サービスは禁止です", "Delivery, repair/installation, and study consulting are not supported yet. Adult, high-risk offline, and illegal services are prohibited"),
                pickText(language, "不要提前转账给未核验服务方，预约前确认服务范围、取消规则和所需材料", "未確認の提供者へ事前送金せず、予約前に範囲、取消規定、必要書類を確認してください", "Do not prepay unverified providers; confirm scope, cancellation rules, and required materials before booking")
            ]
        }
        if type == "discount" {
            return [
                pickText(language, "确认优惠有效期、适用门店和使用规则", "特典の有効期限、対象店舗、利用条件を確認してください", "Confirm the deal validity, eligible stores, and usage rules"),
                pickText(language, "不要把个人敏感信息发给未核验商家", "未確認の店舗へ個人情報を送らないでください", "Do not send sensitive personal information to unverified merchants"),
                pickText(language, "遇到虚假折扣、诱导转账或强制消费立即举报", "虚偽割引、送金誘導、強制消費はすぐ通報してください", "Report fake discounts, payment pressure, or forced purchases immediately")
            ]
        }
        return [
            pickText(language, "Machi 不代收二手交易款", "Machi はフリマ代金を預かりません", "Machi does not hold marketplace payments"),
            pickText(language, "不要提前转账，交易建议选择公共场所", "事前送金は避け、受け渡しは公共の場所がおすすめです", "Avoid paying upfront; meet in a public place"),
            pickText(language, "核实对方身份，谨慎提供个人信息", "相手を確認し、個人情報の共有は慎重にしてください", "Verify the other person and be careful with personal information"),
            pickText(language, "遇到可疑内容立即举报", "不審な内容はすぐ通報してください", "Report suspicious content immediately")
        ]
    }

    static func sortForDisplay(_ lhs: KaiXCityListingDTO, _ rhs: KaiXCityListingDTO) -> Bool {
        let left = lhs.published_at ?? lhs.updated_at ?? lhs.created_at ?? ""
        let right = rhs.published_at ?? rhs.updated_at ?? rhs.created_at ?? ""
        return left > right
    }

    static func statusLabel(_ status: String, type: String? = nil, _ language: AppLanguage = .zh) -> String {
        formatListingStatus(status, type: type, language)
    }

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "published": KXColor.accent
        case "pending_review": KXColor.heat
        default: .secondary
        }
    }

    static func verificationLabel(_ status: String, _ language: AppLanguage = .zh) -> String {
        formatVerificationStatus(status, language)
    }

    static func attr(_ listing: KaiXCityListingDTO, _ key: String) -> String? {
        guard let raw = listing.attributes?[key]?.listingDisplayValue else { return nil }
        return formatAttribute(key: key, value: raw)
    }

    static func boolAttr(_ listing: KaiXCityListingDTO, _ key: String) -> Bool {
        listing.attributes?[key]?.boolValue ?? false
    }

    static func rawAttribute(_ listing: KaiXCityListingDTO, _ key: String) -> String {
        listing.attributes?[key]?.listingDisplayValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func fallbackPriceLabel(for type: String, _ language: AppLanguage = .zh) -> String {
        switch type {
        case "rental": pickText(language, "租金咨询", "家賃相談", "Rent on request")
        case "for_sale": pickText(language, "价格咨询", "価格相談", "Price on request")
        case "job", "hiring": pickText(language, "薪资面议", "給与応相談", "Pay negotiable")
        case "local_service": pickText(language, "预约咨询", "予約相談", "Booking inquiry")
        case "discount": pickText(language, "查看优惠", "特典を見る", "View deal")
        default: pickText(language, "价格咨询", "価格相談", "Price on request")
        }
    }

    private static func formatAttribute(key: String, value: String) -> String? {
        guard let value = cleanText(value) else { return nil }
        switch normalized(key) {
        case "employment_type", "job_type":
            return cleanText(formatEmploymentType(value))
        case "salary_type", "price_unit":
            return cleanText(formatSalaryType(value))
        case "japanese_level", "required_japanese_level":
            return cleanText(formatJapaneseLevel(value))
        case "area_sqm", "area", "size_sqm":
            return cleanText(formatArea(value))
        case "station_distance", "station_distance_minutes":
            return cleanText(formatStationDistance(value))
        case "move_in_date", "valid_until", "expires_at":
            return cleanText(formatDate(value))
        case "condition":
            switch normalized(value) {
            case "brand_new", "new": return "全新"
            case "like_new": return "几乎全新"
            case "good": return "良好"
            case "used": return "有使用痕迹"
            case "fair": return "可用"
            default: return value
            }
        case "listing_mode":
            switch normalized(value) {
            case "sale", "sell": return "出售"
            case "free", "giveaway": return "免费送"
            case "wanted", "buy": return "求购"
            default: return value
            }
        case "delivery_method":
            switch normalized(value) {
            case "pickup": return "自取"
            case "meetup": return "面交"
            case "shipping": return "邮寄"
            case "pickup_or_shipping": return "自取或邮寄"
            case "negotiable": return "可商量"
            default: return value
            }
        case "visa_support":
            if isPositive(value) { return "支持" }
            if isNegative(value) { return "不支持" }
            return value
        default:
            return value
        }
    }

    private static func cleanText(_ value: String?) -> String? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let bad = ["unknown", "undefined", "null", "nan", "n/a", "na", "none", "tbd", "未知", "不明"]
        return bad.contains(text.lowercased()) ? nil : text
    }

    // 纯字符串归一化，不碰任何 UI 状态。工程默认 SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor，
    // 不显式标 nonisolated 的话，从 nonisolated 上下文（如 map 闭包）调用会报隔离告警。
    nonisolated private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_")
    }

    private static func isPositive(_ value: String) -> Bool {
        ["true", "1", "yes", "是", "可", "有", "支持", "available", "allowed"].contains(normalized(value))
    }

    private static func isNegative(_ value: String) -> Bool {
        ["false", "0", "no", "否", "不可", "无", "不支持", "none", "unavailable"].contains(normalized(value))
    }
}
