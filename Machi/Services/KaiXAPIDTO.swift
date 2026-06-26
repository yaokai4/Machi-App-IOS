import Foundation

/// Swift mirrors of the unified backend's JSON shapes. Field names use
/// `snake_case` for symmetry with `web/app/src/lib/types.ts`. Keep
/// these in sync any time the server adds a column.
///
/// NOTE: We deliberately use plain `Decodable` structs here (not
/// SwiftData entities) so the network layer can be tested without
/// touching a `ModelContext`. `RemoteSyncService` is responsible for
/// converting a DTO into an existing SwiftData entity.

/// Minimal type-erased Codable scalar for `post.attributes`. The
/// values we accept from the server are scalar (string / number /
/// bool); arrays + nested dicts are intentionally NOT supported here
/// because the validators on `web/server.py` strip them. Keeping the
/// shape narrow means JSONDecoder never crashes on an unexpected
/// nested payload from a misbehaving client.
/// Recursive JSON value — used for structured listing attributes that aren't
/// scalars (餐厅菜单 / 团购套餐, which arrive as arrays of objects).
indirect enum KXJSONValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([KXJSONValue])
    case object([String: KXJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self)   { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([KXJSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: KXJSONValue].self) { self = .object(v); return }
        self = .null
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .array(let a):  try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null:          try c.encodeNil()
        }
    }

    /// JSONSerialization-compatible Foundation object (for local persistence).
    var foundationObject: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b):   return b
        case .array(let a):  return a.map { $0.foundationObject }
        case .object(let o): return o.mapValues { $0.foundationObject }
        case .null:          return NSNull()
        }
    }
}

struct KaiXAttributeValue: Codable, Equatable, Hashable {
    enum Kind: Equatable, Hashable {
        case string(String)
        case double(Double)
        case bool(Bool)
        case json(KXJSONValue)   // arrays / nested objects (menu, packages)
        case null
    }
    let kind: Kind

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self.kind = .null; return }
        if let v = try? c.decode(Bool.self)   { self.kind = .bool(v); return }
        if let v = try? c.decode(Int.self)    { self.kind = .double(Double(v)); return }
        if let v = try? c.decode(Double.self) { self.kind = .double(v); return }
        if let v = try? c.decode(String.self) { self.kind = .string(v); return }
        if let v = try? c.decode(KXJSONValue.self) { self.kind = .json(v); return }
        self.kind = .null
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch kind {
        case .string(let s): try c.encode(s)
        case .double(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .json(let j):   try c.encode(j)
        case .null:          try c.encodeNil()
        }
    }

    var stringValue: String? { if case .string(let s) = kind { return s } else { return nil } }
    var doubleValue: Double? { if case .double(let n) = kind { return n } else { return nil } }
    var boolValue:   Bool?   { if case .bool(let b)   = kind { return b } else { return nil } }
    var jsonValue:   KXJSONValue? { if case .json(let j) = kind { return j } else { return nil } }

    /// Decode a structured attribute (e.g. menu / packages array) into a typed
    /// model by round-tripping the captured JSON through the standard decoder.
    func decoded<T: Decodable>(_ type: T.Type) -> T? {
        guard case .json(let j) = kind, let data = try? JSONEncoder().encode(j) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    init(string: String) { self.kind = .string(string) }
    init(double: Double) { self.kind = .double(double) }
    init(bool: Bool)     { self.kind = .bool(bool)     }
}

/// 商家详情结构化数据。后端 attributes.menu / attributes.packages 返回。
struct KXMenuDish: Codable, Equatable, Hashable, Identifiable {
    let name: String?
    let price: String?
    let desc: String?
    var id: String { (name ?? "") + (price ?? "") }
}
struct KXListingPackage: Codable, Equatable, Hashable, Identifiable {
    let title: String?
    let price: String?
    let original_price: String?
    let includes: String?
    let note: String?
    var id: String { (title ?? "") + (price ?? "") }
}

extension KaiXCityListingDTO {
    var menuDishes: [KXMenuDish] {
        (attributes?["menu"]?.decoded([KXMenuDish].self) ?? []).filter { !($0.name ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }
    var groupPackages: [KXListingPackage] {
        (attributes?["packages"]?.decoded([KXListingPackage].self) ?? []).filter { !($0.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

struct KaiXAPIError: Codable, Error, LocalizedError {
    struct Body: Codable { let code: String; let message: String }
    let error: Body
    var errorDescription: String? { error.message }
}

struct KaiXUserDTO: Codable, Equatable {
    let id: String
    let remote_id: String?
    let handle: String
    let display_name: String
    let displayName: String?
    let email: String?
    let bio: String?
    let location: String?
    let avatar_symbol: String?
    let avatar_color: String?
    let avatar_url: String?
    let avatarUrl: String?
    let cover_url: String?
    let membership_tier: String?
    let is_verified: Bool?
    let role: String?
    let isOfficial: Bool?
    let is_official: Bool?
    let officialRole: String?
    let official_role: String?
    let joined_at: String?
    let created_at: String?
    let createdAt: String?
    let updated_at: String?
    let updatedAt: String?
    let follower_count: Int?
    let followerCount: Int?
    let following_count: Int?
    let followingCount: Int?
    let post_count: Int?
    let postCount: Int?
    let is_following: Bool?
    let isFollowing: Bool?
    let is_blocked: Bool?
    let can_message: Bool?
    let canMessage: Bool?
    // Phase 1: region. All optional so old responses still decode.
    let country: String?
    let province: String?
    let city: String?
    let current_region_code: String?
    let recent_region_codes: [String]?
    let dm_privacy: String?
    let total_heat: Double?
    let creator_badge: String?
    let custom_tags: [String]?
    let listing_counts: [String: Int]?
    let is_merchant: Bool?
    let merchant_verified: Bool?
    let profile_view_count: Int?
    // Phase 3 — language preferences.
    let app_language: String?
    let content_language_preference: String?
    let preferred_content_languages: String?
    // Machi Verified membership cache (all optional so older responses
    // still decode). is_verified_member drives the blue badge.
    let is_verified_member: Bool?
    let isVerifiedMember: Bool?
    let verified_member_until: String?
    let verifiedMemberUntil: String?
    let membership_status: String?
    let membershipStatus: String?
    let membership_plan_key: String?
    let membershipPlanKey: String?
    let verified_badge_type: String?
    let verifiedBadgeType: String?
    // Google account binding (mirrors serialize_user in server.py). All
    // optional so older responses keep decoding.
    let email_verified: Bool?
    let auth_provider: String?
    let has_google: Bool?
    let can_unlink_google: Bool?
    // Apple account binding (mirrors serialize_user in server.py). Optional so
    // older responses and accounts without Apple linked keep decoding.
    let has_apple: Bool?
    let can_unlink_apple: Bool?
}

struct KaiXListingMediaDTO: Codable, Equatable, Hashable {
    let id: String
    let listing_id: String?
    let listingId: String?
    let uploaded_file_id: String?
    let uploadedFileId: String?
    let media_type: String?
    let mediaType: String?
    let type: String?
    let visibility: String?
    let objectKey: String?
    let url: String
    let cdnUrl: String?
    let publicUrl: String?
    let original_url: String?
    let originalUrl: String?
    let medium_url: String?
    let mediumUrl: String?
    let large_url: String?
    let largeUrl: String?
    let thumb_url: String?
    let thumbUrl: String?
    let thumbnail_url: String?
    let thumbnailUrl: String?
    let poster_url: String?
    let posterUrl: String?
    let content_type: String?
    let contentType: String?
    let mime: String?
    let width: Int?
    let height: Int?
    let duration: Double?
    let duration_seconds: Double?
    let durationSeconds: Double?
    let file_size: Int?
    let fileSize: Int?
    let byte_size: Int?
    let status: String?
    let processing_status: String?
    let processingStatus: String?
    let sort_order: Int?
    let sortOrder: Int?
    let is_cover: Bool?
    let isCover: Bool?
}

struct KaiXListingCardDTO: Codable, Equatable {
    let id: String?
    let type: String?
    let title: String?
    let priceLabel: String?
    let primaryMeta: String?
    let secondaryMeta: String?
    let status: String?
    let statusLabel: String?
    let verificationStatus: String?
    let isVerified: Bool?
    let isFavorited: Bool?
    let isPromoted: Bool?
    let citySlug: String?
    let cityLabel: String?
    let coverUrl: String?
    let coverMedia: KaiXListingMediaDTO?
    let createdAt: String?
    let publishedAt: String?
}

struct KaiXCityListingDTO: Codable, Identifiable, Equatable {
    let id: String
    let country_code: String?
    let countryCode: String?
    let city_id: String?
    let cityId: String?
    let city_slug: String?
    let citySlug: String?
    let region_code: String?
    let regionCode: String?
    let language: String?
    let type: String
    let category: String?
    let title: String
    let description: String?
    let price: Double?
    let currency: String?
    let price_type: String?
    let priceType: String?
    let location_text: String?
    let locationText: String?
    let status: String
    let verification_status: String
    let verificationStatus: String?
    let seller_user_id: String?
    let sellerUserId: String?
    let business_id: String?
    let businessId: String?
    let contact_method: String?
    let contactMethod: String?
    let view_count: Int?
    let viewCount: Int?
    let inquiry_count: Int?
    let inquiryCount: Int?
    let favorite_count: Int?
    let favoriteCount: Int?
    let report_count: Int?
    let reportCount: Int?
    let published_at: String?
    let publishedAt: String?
    let expires_at: String?
    let expiresAt: String?
    let created_at: String?
    let createdAt: String?
    let updated_at: String?
    let updatedAt: String?
    let media: [KaiXListingMediaDTO]?
    let coverMedia: KaiXListingMediaDTO?
    let cover_media: KaiXListingMediaDTO?
    let cover_url: String?
    let coverUrl: String?
    let card: KaiXListingCardDTO?
    let listingCard: KaiXListingCardDTO?
    let attributes: [String: KaiXAttributeValue]?
    let seller: KaiXUserDTO?
    let favorited: Bool?
    let isFavorited: Bool?
    let can_manage: Bool?
    let canManage: Bool?
    let rating_avg: Double?
    let ratingAvg: Double?
    let rating_count: Int?
    let ratingCount: Int?
}

extension KaiXCityListingDTO {
    /// A server-generated placeholder cover (e.g. `/api/generated/listing-card.png`)
    /// is NOT a real photo — rendering it shows the ugly "Generated default cover"
    /// card. We detect these so views fall back to a tasteful native placeholder.
    static func isGeneratedCover(_ raw: String?) -> Bool {
        guard let raw, !raw.isEmpty else { return true }
        return raw.contains("/api/generated/listing-card") || raw.contains("listing-card.svg")
    }

    /// Best *real* uploaded/seeded cover URL string, or nil when only a generated
    /// placeholder exists. Views should render their own placeholder for nil.
    var realCoverURLString: String? {
        let candidates: [String?] = [
            card?.coverUrl, listingCard?.coverUrl,
            coverMedia?.thumbnailUrl, coverMedia?.url,
            cover_media?.thumbnailUrl, cover_media?.url,
            coverUrl, cover_url,
            media?.first?.thumbnailUrl, media?.first?.url,
        ]
        for candidate in candidates {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty, !Self.isGeneratedCover(value) {
                return value
            }
        }
        return nil
    }

    /// Resolved URL for `realCoverURLString`, honouring relative `/uploads` paths.
    var realCoverURL: URL? {
        guard let raw = realCoverURLString else { return nil }
        if raw.hasPrefix("/") {
            return URL(string: raw, relativeTo: KaiXBackend.baseURL)?.absoluteURL
        }
        return raw.kaixMediaURL
    }
}

// ── listing taxonomy（后台可配置发布分类/字段）──────────────────────────────

struct KaiXListingTaxonomyCategoryDTO: Codable, Equatable {
    let id: String?
    let listing_type: String?
    let listingType: String?
    let category_key: String?
    let categoryKey: String?
    let label: String?
    let label_ja: String?
    let labelJa: String?
    let label_en: String?
    let labelEn: String?
    let section_key: String?
    let sectionKey: String?
    let description: String?
    let is_active: Bool?
    let isActive: Bool?
    let sort_order: Int?
    let sortOrder: Int?

    private func clean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedKey: String {
        let key = clean(category_key ?? categoryKey)
        return key.isEmpty ? clean(label) : key
    }

    var resolvedLabel: String {
        let name = clean(label)
        return name.isEmpty ? resolvedKey : name
    }

    var resolvedLabelJa: String {
        let name = clean(label_ja ?? labelJa)
        return name.isEmpty ? resolvedLabel : name
    }

    var resolvedLabelEn: String {
        let name = clean(label_en ?? labelEn)
        return name.isEmpty ? resolvedLabel : name
    }

    var resolvedSectionKey: String {
        clean(section_key ?? sectionKey)
    }

    var isVisible: Bool {
        is_active ?? isActive ?? true
    }

    var resolvedSortOrder: Int {
        sort_order ?? sortOrder ?? 0
    }
}

struct KaiXListingTaxonomyFieldDTO: Codable, Equatable {
    let id: String?
    let listing_type: String?
    let listingType: String?
    let category_key: String?
    let categoryKey: String?
    let field_key: String?
    let fieldKey: String?
    let label: String?
    let label_ja: String?
    let labelJa: String?
    let label_en: String?
    let labelEn: String?
    let kind: String?
    let field_kind: String?
    let fieldKind: String?
    let placeholder: String?
    let required: Bool?
    let is_active: Bool?
    let isActive: Bool?
    let sort_order: Int?
    let sortOrder: Int?
}

struct KaiXListingTaxonomyDTO: Codable, Equatable {
    let listing_type: String?
    let listingType: String?
    let categories: [KaiXListingTaxonomyCategoryDTO]?
    let fields: [KaiXListingTaxonomyFieldDTO]?
    let data: Nested?

    struct Nested: Codable, Equatable {
        let listing_type: String?
        let listingType: String?
        let categories: [KaiXListingTaxonomyCategoryDTO]?
        let fields: [KaiXListingTaxonomyFieldDTO]?
    }

    var resolvedCategories: [KaiXListingTaxonomyCategoryDTO] {
        (categories ?? data?.categories ?? [])
            .filter(\.isVisible)
            .sorted {
                if $0.resolvedSortOrder != $1.resolvedSortOrder {
                    return $0.resolvedSortOrder < $1.resolvedSortOrder
                }
                return $0.resolvedLabel.localizedCompare($1.resolvedLabel) == .orderedAscending
            }
    }
}

// ── listing reviews（星级点评）────────────────────────────────────────────

struct KaiXListingReviewDTO: Codable, Identifiable, Equatable {
    let id: String
    let listing_id: String?
    let business_id: String?
    let user_id: String?
    let rating: Int
    let content: String?
    let visit_date: String?
    let status: String?
    let owner_reply: String?
    let owner_reply_at: String?
    let helpful_count: Int?
    let created_at: String?
    let updated_at: String?
    let author: KaiXUserDTO?
    let listing_title: String?
    let listing_type: String?
}

struct KaiXListingReviewSummaryDTO: Codable, Equatable {
    let rating_avg: Double?
    let rating_count: Int?
    let histogram: [String: Int]?
    let reviewable: Bool?
}

struct KaiXListingReviewsResponse: Codable {
    let items: [KaiXListingReviewDTO]
    let summary: KaiXListingReviewSummaryDTO?
    let my_review: KaiXListingReviewDTO?
}

struct KaiXSubmitReviewResponse: Codable {
    let review: KaiXListingReviewDTO?
    let rating_avg: Double?
    let rating_count: Int?
}

struct KaiXMyBusinessReviewsSummaryDTO: Codable, Equatable {
    let count: Int?
    let rating_avg: Double?
    let unreplied: Int?
}

struct KaiXMyBusinessReviewsResponse: Codable {
    let items: [KaiXListingReviewDTO]
    let summary: KaiXMyBusinessReviewsSummaryDTO?
}

// ── public merchant directory（认证商家目录与公开主页）──────────────────────

struct KaiXBusinessPublicDTO: Codable, Identifiable, Equatable {
    let id: String
    let business_name: String?
    let business_type: String?
    let country_code: String?
    let city_slug: String?
    let address: String?
    let website: String?
    let contact_method: String?
    let description: String?
    let service_categories: [String]?
    let service_cities: [String]?
    let opening_hours: [String: String]?
    let logo_url: String?
    let cover_url: String?
    let verification_status: String?
    let is_verified: Bool?
    let owner: KaiXUserDTO?
    let published_listing_count: Int?
    let rating_avg: Double?
    let rating_count: Int?
    let created_at: String?
}

struct KaiXBusinessDirectoryResponse: Codable {
    let items: [KaiXBusinessPublicDTO]
    let total: Int?
}

struct KaiXBusinessPublicResponse: Codable {
    let business: KaiXBusinessPublicDTO
    let listings: [KaiXCityListingDTO]?
    let reviews: [KaiXListingReviewDTO]?
}

/// One row of /api/my/listing-inquiries — a buyer↔seller contact about a
/// city listing (consult / apply / booking…), with the hydrated listing and
/// counterpart users when the server attaches them.
struct KaiXListingInquiryDTO: Codable, Identifiable, Equatable {
    let id: String
    let listing_id: String?
    let listingId: String?
    let type: String?
    let message: String?
    let status: String?
    let conversation_id: String?
    let conversationId: String?
    let details: [[String: String]]?
    let metadata: [String: KaiXAttributeValue]?
    let created_at: String?
    let createdAt: String?
    let updated_at: String?
    let updatedAt: String?
    let listing: KaiXCityListingDTO?
    let from_user: KaiXUserDTO?
    let fromUser: KaiXUserDTO?
    let to_user: KaiXUserDTO?
    let toUser: KaiXUserDTO?

    var resolvedListingId: String {
        listing_id ?? listingId ?? ""
    }

    var resolvedConversationId: String {
        conversation_id ?? conversationId ?? ""
    }

    var resolvedCreatedAt: String {
        created_at ?? createdAt ?? ""
    }

    var resolvedUpdatedAt: String {
        updated_at ?? updatedAt ?? ""
    }

    var resolvedFromUser: KaiXUserDTO? {
        from_user ?? fromUser
    }

    var resolvedToUser: KaiXUserDTO? {
        to_user ?? toUser
    }
}

struct KaiXListingInquiryReceiptDTO: Codable, Equatable {
    let conversation_id: String?
    let conversationId: String?
    let inquiry_id: String?
    let inquiryId: String?
    let type: String?
    let status: String?
    let details: [[String: String]]?
    let success_title: String?
    let successTitle: String?

    var resolvedConversationId: String {
        conversation_id ?? conversationId ?? ""
    }

    var resolvedInquiryId: String {
        inquiry_id ?? inquiryId ?? ""
    }

    var resolvedSuccessTitle: String {
        success_title ?? successTitle ?? "已提交"
    }
}

