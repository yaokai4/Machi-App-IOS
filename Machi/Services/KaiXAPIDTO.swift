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
struct KaiXAttributeValue: Codable, Equatable, Hashable {
    enum Kind: Equatable, Hashable {
        case string(String)
        case double(Double)
        case bool(Bool)
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
        self.kind = .null
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch kind {
        case .string(let s): try c.encode(s)
        case .double(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .null:          try c.encodeNil()
        }
    }

    var stringValue: String? { if case .string(let s) = kind { return s } else { return nil } }
    var doubleValue: Double? { if case .double(let n) = kind { return n } else { return nil } }
    var boolValue:   Bool?   { if case .bool(let b)   = kind { return b } else { return nil } }

    init(string: String) { self.kind = .string(string) }
    init(double: Double) { self.kind = .double(double) }
    init(bool: Bool)     { self.kind = .bool(bool)     }
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
}

/// One row of /api/my/listing-inquiries — a buyer↔seller contact about a
/// city listing (consult / apply / booking…), with the hydrated listing and
/// counterpart users when the server attaches them.
struct KaiXListingInquiryDTO: Codable, Identifiable, Equatable {
    let id: String
    let listing_id: String?
    let type: String?
    let message: String?
    let status: String?
    let conversation_id: String?
    let created_at: String?
    let listing: KaiXCityListingDTO?
    let from_user: KaiXUserDTO?
    let to_user: KaiXUserDTO?
}

/// One membership payment order (/api/membership/orders).
struct KaiXPaymentOrderDTO: Codable, Identifiable, Equatable {
    let id: String
    let order_no: String
    let plan_key: String?
    let amount: Double?
    let currency: String?
    let status: String?
    let provider: String?
    let created_at: String?
    let paid_at: String?
}

struct KaiXListingsResponse: Codable {
    let items: [KaiXCityListingDTO]
    let next_cursor: String?
    let type: String?
}

struct KaiXListingDetailResponse: Codable {
    let listing: KaiXCityListingDTO
    let safety_tips: [String]?
}

// MARK: - membership + payments

struct KaiXMembershipStatusDTO: Codable, Equatable {
    let user_id: String?
    let userId: String?
    let is_active: Bool
    let isActive: Bool?
    let status: String
    let plan_key: String?
    let planKey: String?
    let current_period_end: String?
    let expires_at: String?
    let expiresAt: String?
    let started_at: String?
    let startedAt: String?
    let source: String?
    let provider: String?
    let price: Double?
    let currency: String?
    let benefits: [String]?
    let verified_badge_type: String?
    let verifiedBadgeType: String?
    let can_post_high_trust_content: Bool?
    let canPostHighTrustContent: Bool?
    let can_access_exclusive_page: Bool?
    let canAccessExclusivePage: Bool?
    let daily_post_limit: Int?
    let dailyPostLimit: Int?
    let priority_review: Bool?
    let priorityReview: Bool?
    let light_boost: Bool?
    let lightBoost: Bool?
    let cancel_at_period_end: Bool?
    let cancelAtPeriodEnd: Bool?
}

enum KaiXPriceFormatter {
    static func format(_ amount: Double, currency: String, billingPeriod: String? = nil) -> String {
        let code = currency.uppercased()
        let base: String
        if code == "CNY" || code == "JPY" {
            base = "¥\(Int(amount.rounded()))"
        } else if code == "USD" {
            base = amount.truncatingRemainder(dividingBy: 1) == 0
                ? "$\(Int(amount))"
                : String(format: "$%.2f", amount)
        } else {
            base = amount.truncatingRemainder(dividingBy: 1) == 0
                ? "\(code) \(Int(amount))"
                : "\(code) \(String(format: "%.2f", amount))"
        }
        if billingPeriod == "monthly" { return "\(base) / 月" }
        if billingPeriod == "yearly" { return "\(base) / 年" }
        return base
    }
}

struct KaiXMembershipPlanDTO: Codable, Equatable {
    let plan_key: String
    let planKey: String?
    let name: String?
    let subtitle: String?
    let description: String?
    let name_zh: String?
    let name_en: String?
    let name_ja: String?
    let amount: Double
    let price: Double?
    let currency: String
    let price_label: String?
    let priceLabel: String?
    let original_price: Double?
    let originalPrice: Double?
    let discount_label: String?
    let discountLabel: String?
    let billing_cycle: String?
    let billingPeriod: String?
    let billing_period: String?
    let intervalCount: Int?
    let interval_count: Int?
    let stripePriceId: String?
    let stripe_price_id: String?
    let iosIapProductId: String?
    let ios_iap_product_id: String?
    let appleProductId: String?
    let apple_product_id: String?
    let isRecommended: Bool?
    let is_recommended: Bool?
    let isDefault: Bool?
    let is_default: Bool?
    let benefits: [KaiXMembershipBenefitDTO]?

    var canonicalPlanKey: String { planKey ?? plan_key }
    var displayName: String { name ?? name_zh ?? "Machi 认证会员" }
    var displayPriceLabel: String {
        if let label = priceLabel ?? price_label, !label.isEmpty { return label }
        return KaiXPriceFormatter.format(price ?? amount, currency: currency, billingPeriod: billingPeriod ?? billing_period ?? billing_cycle)
    }
    var appleProductID: String {
        appleProductId ?? apple_product_id ?? iosIapProductId ?? ios_iap_product_id ?? canonicalPlanKey
    }
    var recommended: Bool { isRecommended ?? is_recommended ?? false }
}

struct KaiXMembershipMeResponse: Codable {
    let membership: KaiXMembershipStatusDTO
    let plan: KaiXMembershipPlanDTO?
    let user: KaiXUserDTO
}

struct KaiXMembershipPlanResponse: Codable {
    let plan: KaiXMembershipPlanDTO?
    let plans: [KaiXMembershipPlanDTO]?
    let items: [KaiXMembershipPlanDTO]?
    let apple_product_id: String?
}

struct KaiXMembershipBenefitDTO: Codable, Equatable, Identifiable {
    let key: String
    let title: String
    let description: String
    let icon: String?
    let benefit_icon: String?
    let sort_order: Int?
    var id: String { key }
}

struct KaiXMembershipBenefitsResponse: Codable {
    let benefits: [KaiXMembershipBenefitDTO]
    let plan: KaiXMembershipPlanDTO?
    let disclaimer: String?
    let requires_membership_content_types: [String]?
}

struct KaiXAppleVerifyResponse: Codable {
    let membershipActive: Bool
    let currentPeriodEnd: String?
    let status: String?
}

struct KaiXMembershipInsightsTotals: Codable, Equatable {
    let post_count: Int
    let total_views: Int
    let total_likes: Int
    let total_bookmarks: Int
    let total_reposts: Int
    let total_comments: Int
}

struct KaiXMembershipInsightsResponse: Codable {
    let totals: KaiXMembershipInsightsTotals
}

struct KaiXMediaDTO: Codable, Equatable {
    let id: String
    let owner_id: String?
    let ownerId: String?
    let remote_id: String?
    let remoteId: String?
    let type: String?
    let visibility: String?
    let objectKey: String?
    let url: String?
    let cdnUrl: String?
    let publicUrl: String?
    let thumb_url: String?
    let thumbUrl: String?
    let thumbnail_url: String?
    let thumbnailUrl: String?
    let poster_url: String?
    let posterUrl: String?
    let mime: String?
    let content_type: String?
    let contentType: String?
    let width: Int?
    let height: Int?
    let duration: Double?
    let duration_seconds: Double?
    let durationSeconds: Double?
    let byte_size: Int?
    let file_size: Int?
    let fileSize: Int?
    let status: String?
    let processing_status: String?
    let processingStatus: String?
    let created_at: String?
    let createdAt: String?
}

struct KaiXUploadedFileDTO: Codable, Equatable {
    let id: String
    let uploadId: String?
    let objectKey: String?
    let url: String?
    let cdnUrl: String?
    let thumbnailUrl: String?
    let posterUrl: String?
    let contentType: String?
    let fileSize: Int?
    let fileType: String?
    let type: String?
    let visibility: String?
    let purpose: String?
    let entityType: String?
    let entityId: String?
    let status: String?
    let isPrivate: Bool?
    let width: Int?
    let height: Int?
    let duration: Double?
    let durationSeconds: Double?
}

extension KaiXListingMediaDTO {
    var normalizedType: String {
        (type ?? mediaType ?? media_type ?? "image").lowercased()
    }

    var sourceURLString: String {
        cdnUrl ?? publicUrl ?? url
    }

    var thumbnailURLString: String {
        thumbnailUrl ?? thumbnail_url ?? thumbUrl ?? thumb_url ?? ""
    }

    var posterURLString: String {
        let poster = posterUrl ?? poster_url ?? thumbnailURLString
        return normalizedType == "video" && poster == sourceURLString ? "" : poster
    }

    var previewURL: URL? {
        let raw = normalizedType == "video" ? posterURLString : (thumbnailURLString.isEmpty ? sourceURLString : thumbnailURLString)
        return raw.kaixMediaURL
    }

    var sourceURL: URL? {
        sourceURLString.kaixMediaURL
    }
}

extension KaiXMediaDTO {
    var normalizedType: String {
        let declared = (type ?? "").lowercased()
        let mimeType = (contentType ?? content_type ?? mime ?? "").lowercased()
        if declared == "video" || mimeType.hasPrefix("video/") { return "video" }
        if declared == "image" || mimeType.hasPrefix("image/") { return "image" }
        return declared.isEmpty ? "image" : declared
    }

    var sourceURLString: String {
        cdnUrl ?? publicUrl ?? url ?? ""
    }

    var thumbnailURLString: String {
        thumbnailUrl ?? thumbnail_url ?? thumbUrl ?? thumb_url ?? ""
    }

    var posterURLString: String {
        let poster = posterUrl ?? poster_url ?? thumbnailURLString
        return normalizedType == "video" && poster == sourceURLString ? "" : poster
    }

    var previewURL: URL? {
        let raw = normalizedType == "video" ? posterURLString : (thumbnailURLString.isEmpty ? sourceURLString : thumbnailURLString)
        return raw.kaixMediaURL
    }

    var sourceURL: URL? {
        sourceURLString.kaixMediaURL
    }
}

struct KaiXUploadPresignDTO: Codable {
    struct Payload: Codable {
        let uploadId: String
        let uploadUrl: String
        let fileKey: String
        let cdnUrl: String
        let expiresIn: Int
        let headers: [String: String]
        let file: KaiXUploadedFileDTO?
    }
    let ok: Bool
    let data: Payload
}

struct KaiXUploadCompleteDTO: Codable {
    struct Payload: Codable {
        let file: KaiXUploadedFileDTO
        let media: KaiXMediaDTO
    }
    let ok: Bool
    let data: Payload
}

struct KaiXPostDTO: Codable, Equatable {
    let id: String
    let remote_id: String?
    let author_id: String
    let content: String
    let created_at: String
    let createdAt: String?
    let updated_at: String
    let updatedAt: String?
    let deleted_at: String?
    let repost_of_id: String?
    let view_count: Int
    let viewCount: Int?
    let like_count: Int
    let likeCount: Int?
    let repost_count: Int
    let repostCount: Int?
    let bookmark_count: Int
    let bookmarkCount: Int?
    let save_count: Int?
    let saveCount: Int?
    let comment_count: Int
    let commentCount: Int?
    let share_count: Int?
    let shareCount: Int?
    let heat_score: Double
    let heatScore: Double?
    let liked: Bool
    let isLiked: Bool?
    let bookmarked: Bool
    let saved: Bool?
    let isSaved: Bool?
    let reposted: Bool
    let isReposted: Bool?
    let canEdit: Bool?
    let canDelete: Bool?
    let tags: [String]
    let media: [KaiXMediaDTO]
    let images: [String]?
    let videoUrl: String?
    let video_url: String?
    let author: KaiXUserDTO?
    // original_post is a recursive optional — represented as Data when
    // we don't want to decode it eagerly.
    let original_post: OptionalPost?
    let status: String?
    // Phase 1 region — optional so older responses without these
    // fields still decode cleanly.
    let country: String?
    let province: String?
    let city: String?
    let region_code: String?
    let cityPath: String?
    let city_path: String?
    // Phase 2 — content type + typed attributes.
    let content_type: String?
    let contentType: String?
    let category: String?
    let attributes: [String: KaiXAttributeValue]?
    let requiresMembership: Bool?
    let requires_membership: Bool?
    let sourceType: String?
    let source_type: String?
    let report_count: Int?
    let is_boosted: Bool?
    let boost_weight: Double?
    let boosted_until: String?
    // Phase 3 — content language tag ("zh" / "en" / "ja" / …).
    // Optional so responses from older servers still decode.
    let language: String?
    // City Seed Bot (城市内容助手). Optional so older servers decode cleanly.
    let is_seed_content: Bool?
    let seed_author_type: String?

    struct OptionalPost: Codable, Equatable {
        let id: String
        let author_id: String
        let content: String
        let created_at: String
        let updated_at: String
        let media: [KaiXMediaDTO]
        let tags: [String]
        let view_count: Int
        let like_count: Int
        let repost_count: Int
        let bookmark_count: Int
        let comment_count: Int
        let heat_score: Double
        let liked: Bool
        let bookmarked: Bool
        let reposted: Bool
        let author: KaiXUserDTO?
    }
}

struct KaiXCommentDTO: Codable, Equatable {
    let id: String
    let post_id: String
    let author_id: String
    let content: String
    let parent_comment_id: String?
    let reply_to_user_id: String?
    let created_at: String
    let updated_at: String
    let deleted_at: String?
    let like_count: Int
    let liked: Bool
    let author: KaiXUserDTO?
}

struct KaiXNotificationDTO: Codable, Equatable {
    let id: String
    let type: String
    let actor_id: String
    let user_id: String
    let target_post_id: String?
    let target_comment_id: String?
    let target_conversation_id: String?
    let content: String?
    let is_read: Bool
    let created_at: String
    let actor: KaiXUserDTO?
}

struct KaiXMessageDTO: Codable, Equatable {
    let id: String
    let conversation_id: String
    let sender_id: String
    let content: String
    let created_at: String
    let is_read: Bool
    let media: [KaiXMediaDTO]?
    let attachments: [KaiXMessageAttachmentDTO]?
}

struct KaiXMessageAttachmentDTO: Codable, Equatable, Identifiable {
    let id: String
    let message_id: String
    let thread_id: String?
    let uploaded_file_id: String
    let type: String
    let visibility: String?
    let objectKey: String?
    let attachment_type: String?
    let url: String?
    let cdnUrl: String?
    let publicUrl: String?
    let thumb_url: String?
    let thumbUrl: String?
    let thumbnail_url: String?
    let thumbnailUrl: String?
    let poster_url: String?
    let posterUrl: String?
    let needsSignedUrl: Bool?
    let viewUrlEndpoint: String?
    let thumbnail_file_id: String?
    let duration: Double?
    let duration_seconds: Double?
    let durationSeconds: Double?
    let width: Int?
    let height: Int?
    let file_name: String?
    let file_size: Int?
    let fileSize: Int?
    let byte_size: Int?
    let content_type: String?
    let contentType: String?
    let mime: String?
    let status: String?
    let created_at: String?
    let createdAt: String?
}

struct KaiXConversationDTO: Codable, Equatable {
    let id: String
    let participant_a: String
    let participant_b: String
    let participants: [String]
    let peer: KaiXUserDTO?
    let last_message: KaiXMessageDTO?
    let unread_count: Int
    let updated_at: String
}

struct KaiXSettingsDTO: Codable, Equatable {
    let user_id: String
    let language: String
    let appearance: String
    let push_likes: Bool
    let push_comments: Bool
    let push_follows: Bool
    let push_messages: Bool
    let privacy_protect: Bool
    let privacy_allow_dm: String
    let recommend_following: Bool
    let recommend_topics: Bool
    let updated_at: String
}

struct KaiXTopicDTO: Codable, Equatable {
    let tag: String
    let post_count: Int?
    let postCount: Int?
    let heat: Double?
    let topic_heat: Double?
    let topicHeat: Double?
}

extension KaiXTopicDTO {
    var normalizedTag: String { tag.normalizedTopicName }
    var postCountValue: Int { post_count ?? postCount ?? 0 }
    var heatScoreValue: Double { topic_heat ?? topicHeat ?? heat ?? Double(postCountValue) }
}

// MARK: - Login devices / sessions (parity with web /settings/devices)

struct KaiXDeviceDTO: Codable, Equatable, Identifiable {
    let id: String
    let token: String?
    let device_name: String?
    let user_agent: String?
    let ip: String?
    let created_at: String?
    let last_seen_at: String?
    let expires_at: String?

    var displayName: String {
        let name = (device_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let ua = (user_agent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ua.isEmpty ? "未知设备" : String(ua.prefix(40))
    }
}

// MARK: - Machi Guide / 日本指南

struct KaiXGuideHeroDTO: Codable, Equatable {
    let title: String
    let subtitle: String
    let note: String
    let searchPlaceholder: String
    let quickTags: [String]
}

struct KaiXGuideEmptyStateDTO: Codable, Equatable {
    let title: String
    let body: String
    let action: String
    let actionCountry: String
}

struct KaiXGuideCategoryDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let key: String
    let parentKey: String
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let color: String
    let country: String
    let sortOrder: Int
    let subCategories: [KaiXGuideCategoryDTO]?
}

struct KaiXGuideGoalEntryDTO: Codable, Equatable, Identifiable {
    let targetKey: String
    let title: String
    let categoryKey: String
    let subCategoryKey: String
    var id: String { targetKey }
}

struct KaiXGuideResourceEntryDTO: Codable, Equatable, Identifiable, Hashable {
    let key: String
    let title: String
    let description: String
    let icon: String
    let href: String
    var id: String { key }
}

struct KaiXGuideGoalsDTO: Codable, Equatable {
    let title: String
    let entries: [KaiXGuideGoalEntryDTO]
}

struct KaiXGuideArticleDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String
    let summary: String
    let body: String?
    let categoryKey: String
    let subCategoryKey: String
    let contentType: String
    let country: String
    let city: String
    let language: String
    let coverImage: String
    let tags: [String]
    let authorType: String
    let authorName: String
    let isFeatured: Bool
    let isFree: Bool
    let isPaid: Bool
    let status: String
    let viewCount: Int
    let saveCount: Int
    let publishedAt: String?
    let updatedAt: String?
}

struct KaiXGuideProductDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let title: String
    let slug: String
    let subtitle: String
    let description: String
    let categoryKey: String
    let subCategoryKey: String
    let productType: String
    let price: Int
    let currency: String
    let priceLabel: String
    let originalPrice: Int?
    let discountLabel: String?
    let memberPriceLabel: String?
    let isPriceHidden: Bool?
    let isAppointmentOnly: Bool?
    let billingType: String?
    let billingPeriod: String?
    let servicePriceType: String?
    let startingPrice: Int?
    let memberDiscountPercent: Int?
    let serviceDurationMinutes: Int?
    let depositRequired: Bool?
    let depositAmount: Int?
    let cancellationPolicy: String?
    let canView: Bool?
    let canPurchase: Bool?
    let ctaLabel: String?
    let coverImage: String
    let tags: [String]
    let targetAudience: String
    let deliveryMethod: String
    let country: String
    let language: String
    let isDigital: Bool
    let isService: Bool
    let isFree: Bool
    let isPaid: Bool
    let isComingSoon: Bool
    let status: String
    let purchaseCount: Int
    let rating: Double
    let publishedAt: String?
    let fileCount: Int?
    // Member / payment / gating fields from the unified Guide API. All optional so
    // older payloads still decode. `purchaseContent`/`fileUrl` appear only for an
    // entitled viewer (owned order or active member). iOS shows digital purchases as
    // 即将开放 (no external Stripe button) until Apple IAP is wired.
    let previewContent: String?
    let hasPurchaseContent: Bool?
    let hasFile: Bool?
    let isMemberIncluded: Bool?
    let isMemberDiscount: Bool?
    let memberPrice: Int?
    let memberEffectivePrice: Int?
    let isFeatured: Bool?
    let refundPolicy: String?
    let notes: String?
    let sortOrder: Int?
    let iosIapProductId: String?
    let appleProductId: String?
    let stripeAvailable: Bool?
    let purchaseContent: String?
    let fileUrl: String?
    let access: KaiXGuideProductAccess?
}

struct KaiXGuideProductAccess: Codable, Equatable, Hashable {
    let owned: Bool?
    let memberUnlocked: Bool?
    let canAccess: Bool?
    let signedIn: Bool?
}

struct KaiXGuideCompanyScoresDTO: Codable, Equatable, Hashable {
    let foreignerFriendly: Double
    let visaSupport: Double?
    let interviewDifficulty: Double
    let overtime: Double
    let salaryBenefit: Double
    let workLifeBalance: Double
    let careerGrowth: Double?
}

struct KaiXGuideCompanyDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let corporateNumber: String?
    let companyName: String
    let companyNameJp: String
    let companyNameEn: String?
    let slug: String
    let industry: String
    let subIndustry: String?
    let country: String
    let prefecture: String?
    let city: String
    let ward: String?
    let address: String?
    let postalCode: String?
    let latitude: Double?
    let longitude: Double?
    let website: String
    let careerUrl: String?
    let newGraduateUrl: String?
    let midCareerUrl: String?
    let globalCareerUrl: String?
    let size: String
    let companySize: String?
    let foundedYear: Int
    let description: String
    let shortDescription: String?
    let isForeignerFriendly: Bool?
    let acceptsForeignApplicants: Bool?
    let supportsWorkVisa: Bool?
    let supportsNewGraduate: Bool?
    let supportsMidCareer: Bool?
    let hasEnglishPositions: Bool?
    let hasGlobalRoles: Bool?
    let hasForeignEmployees: Bool?
    let requiredJapaneseLevel: String?
    let requiredEnglishLevel: String?
    let employmentTypes: [String]?
    let averageSalaryMin: Int?
    let averageSalaryMax: Int?
    let currency: String?
    let scores: KaiXGuideCompanyScoresDTO?
    let reviewCount: Int
    let interviewReviewCount: Int?
    let saveCount: Int?
    let sourceType: String?
    let sourceName: String?
    let sourceUrl: String?
    let sourceLastCheckedAt: String?
    let verificationStatus: String?
    let dataQualityScore: Int?
    let isFeatured: Bool?
    let status: String
}

struct KaiXGuideSchoolDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let slug: String
    let schoolName: String
    let schoolNameJp: String
    let schoolNameEn: String
    let schoolType: String
    let country: String
    let prefecture: String
    let city: String
    let ward: String?
    let address: String?
    let postalCode: String?
    let latitude: Double?
    let longitude: Double?
    let website: String
    let admissionUrl: String?
    let internationalAdmissionUrl: String
    let applicationUrl: String?
    let scholarshipUrl: String?
    let careerSupportUrl: String?
    let languageSupportUrl: String?
    let dormitoryUrl: String?
    let description: String
    let shortDescription: String
    let isAcceptingInternationalStudents: Bool?
    let hasEnglishProgram: Bool?
    let hasJapaneseProgram: Bool?
    let hasScholarship: Bool?
    let hasDormitory: Bool?
    let hasCareerSupport: Bool?
    let hasLanguageSupport: Bool?
    let tuitionMin: Int
    let tuitionMax: Int
    let currency: String
    let applicationPeriods: [String]?
    let admissionMonths: [String]
    let requiredJapaneseLevel: String
    let requiredEnglishLevel: String
    let ejuRequired: String?
    let jlptRequired: String?
    let toeflRequired: String?
    let ieltsRequired: String?
    let fieldsOfStudy: [String]
    let departments: [String]?
    let faculties: [String]?
    let graduateSchools: [String]?
    let tags: [String]?
    let sourceType: String?
    let sourceName: String?
    let sourceUrl: String
    let sourceLastCheckedAt: String?
    let verificationStatus: String
    let dataQualityScore: Int?
    let isFeatured: Bool
    let viewCount: Int?
    let saveCount: Int
    let savedByMe: Bool?
    let status: String
}

struct KaiXGuideSchoolProgramDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let schoolId: String
    let programName: String
    let programNameJp: String
    let programNameEn: String
    let degreeLevel: String
    let programType: String
    let field: String
    let subField: String?
    let facultyName: String?
    let departmentName: String?
    let graduateSchoolName: String?
    let languageOfInstruction: String
    let durationMonths: Int
    let admissionMonths: [String]
    let applicationPeriod: String
    let tuition: Int
    let currency: String
    let description: String
    let applicationUrl: String
    let sourceUrl: String?
    let verificationStatus: String?
    let status: String
}

struct KaiXGuideSchoolAdmissionDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let schoolId: String
    let programId: String
    let admissionType: String
    let enrollmentMonth: String
    let requiredDocuments: [String]
    let selectionMethod: String
    let scholarshipInfo: String
    let notes: String
    let sourceUrl: String
    let verificationStatus: String?
    let status: String
}

struct KaiXGuideCompanyPositionDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let companyId: String
    let positionTitle: String
    let positionTitleJp: String
    let positionCategory: String
    let employmentType: String
    let city: String
    let remoteType: String
    let salaryMin: Int
    let salaryMax: Int
    let currency: String
    let requiredJapaneseLevel: String
    let requiredEnglishLevel: String
    let visaSupport: String
    let description: String
    let requirements: String
    let sourceUrl: String
    let verificationStatus: String?
    let status: String
}

struct KaiXGuideCompanyReviewDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let companyId: String
    let anonymous: Bool
    let position: String
    let employmentType: String
    let pros: String
    let cons: String
    let overtimeLevel: String
    let foreignerSupport: String
    let salaryBenefits: String
    let careerGrowth: String
    let recommendationScore: Double
    let createdAt: String
}

struct KaiXGuideInterviewReviewDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let companyId: String
    let companyName: String?
    let companySlug: String?
    let anonymous: Bool
    let position: String
    let employmentType: String
    let interviewRounds: Int
    let interviewLanguage: String
    let difficulty: String
    let questions: String
    let processDescription: String
    let result: String
    let interviewYear: Int
    let city: String
    let createdAt: String
}

struct KaiXGuideFaqDTO: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let question: String
    let answer: String
    let categoryKey: String
}

struct KaiXGuideHomeResponse: Codable {
    let status: String
    let country: String
    let language: String?
    let hero: KaiXGuideHeroDTO
    let emptyState: KaiXGuideEmptyStateDTO?
    let categories: [KaiXGuideCategoryDTO]
    let goals: KaiXGuideGoalsDTO?
    let goalEntries: [KaiXGuideGoalEntryDTO]
    let resourceEntries: [KaiXGuideResourceEntryDTO]?
    let featuredArticles: [KaiXGuideArticleDTO]
    let featuredProducts: [KaiXGuideProductDTO]
    let featuredServices: [KaiXGuideProductDTO]
    let featuredSchools: [KaiXGuideSchoolDTO]?
    let companyHighlights: [KaiXGuideCompanyDTO]
    let latestArticles: [KaiXGuideArticleDTO]
    let faq: [KaiXGuideFaqDTO]
    let reviewDisclaimer: String?
    let schoolDisclaimer: String?
    let companyDisclaimer: String?
}

struct KaiXGuideCategoriesResponse: Codable {
    let status: String
    let country: String
    let categories: [KaiXGuideCategoryDTO]
    let emptyState: KaiXGuideEmptyStateDTO?
}

struct KaiXGuideListResponse<Item: Codable>: Codable {
    let status: String
    let country: String
    let items: [Item]
    let page: Int
    let pageSize: Int
    let total: Int
    let emptyState: KaiXGuideEmptyStateDTO?
    let disclaimer: String?
    let membershipActive: Bool?
}

struct KaiXGuideArticleDetailResponse: Codable {
    let status: String
    let article: KaiXGuideArticleDTO
    let related: [KaiXGuideArticleDTO]
}

struct KaiXGuideProductDetailResponse: Codable {
    let status: String
    let product: KaiXGuideProductDTO
}

struct KaiXGuideCompanyDetailResponse: Codable {
    let status: String
    let company: KaiXGuideCompanyDTO
    let interviewReviewCount: Int
    let workReviewCount: Int
    let positions: [KaiXGuideCompanyPositionDTO]?
    let relatedArticles: [KaiXGuideArticleDTO]?
    let disclaimer: String
}

struct KaiXGuideSchoolDetailResponse: Codable {
    let status: String
    let school: KaiXGuideSchoolDTO
    let programs: [KaiXGuideSchoolProgramDTO]
    let admissions: [KaiXGuideSchoolAdmissionDTO]
    let relatedArticles: [KaiXGuideArticleDTO]
    let relatedProducts: [KaiXGuideProductDTO]
    let disclaimer: String
}

struct KaiXGuideCompanyReviewsResponse: Codable {
    let status: String
    let companyId: String
    let workReviews: [KaiXGuideCompanyReviewDTO]
    let interviewReviews: [KaiXGuideInterviewReviewDTO]
    let disclaimer: String
}

struct KaiXGuideSubmitResponse: Codable {
    let status: String
    let id: String?
    let message: String
    let orderId: String?
}

struct KaiXGuideCompanyReviewPayload: Encodable {
    let companyId: String
    let position: String
    let employmentType: String
    let pros: String
    let cons: String
    let overtimeLevel: String
    let foreignerSupport: String
    let salaryBenefits: String
    let careerGrowth: String
    let recommendationScore: Double
    let anonymous: Bool
}

struct KaiXGuideInterviewReviewPayload: Encodable {
    let companyId: String
    let position: String
    let employmentType: String
    let interviewRounds: Int
    let interviewLanguage: String
    let difficulty: String
    let questions: String
    let processDescription: String
    let result: String
    let interviewYear: Int
    let city: String
    let anonymous: Bool
}

struct KaiXGuideServiceRequestPayload: Encodable {
    let productId: String
    let serviceType: String
    let contactMethod: String
    let message: String
}

struct KaiXPageDTO<Item: Codable>: Codable {
    let items: [Item]
    let next_cursor: String?
}

struct KaiXLoginResponse: Codable {
    let token: String
    let user: KaiXUserDTO
}

struct KaiXGoogleAuthStartResponse: Codable {
    let authorization_url: String
    let url: String?
    let state: String
    let expires_in: Int
}

struct KaiXAvailabilityResponse: Codable, Equatable {
    let available: Bool
    let message: String
    let code: String?
}

struct KaiXEmailCodeResponse: Codable, Equatable {
    let ok: Bool
    let challenge_id: String?
    let email_hint: String?
    let expires_in: Int
}

/// Image-captcha challenge gating the anonymous auth endpoints. When the
/// server has enforcement off for the requested scene, `enabled` is false
/// and the UI hides the captcha row entirely.
struct KaiXCaptchaResponse: Codable, Equatable {
    let enabled: Bool
    let captcha_id: String?
    /// `data:image/png;base64,…`
    let image: String?
    let expires_in: Int?

    var pngData: Data? {
        guard let image, let comma = image.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(image[image.index(after: comma)...]))
    }
}

struct KaiXVerifyCodeResponse: Codable, Equatable {
    let ok: Bool?
    let success: Bool?
    let message: String?
}

struct KaiXFeedResponse: Codable {
    let items: [KaiXPostDTO]
    let next_cursor: String?
    let mode: String
}

struct KaiXTrendingResponse: Codable {
    let posts: [KaiXPostDTO]
    let topics: [KaiXTopicDTO]
    let users: [KaiXUserDTO]
}

struct KaiXExplorePostsResponse: Codable {
    let items: [KaiXPostDTO]?
    let posts: [KaiXPostDTO]?
    let days: Int?
    let fallbackUsed: Bool?

    var orderedPosts: [KaiXPostDTO] { items ?? posts ?? [] }
}

struct KaiXExploreTopicsResponse: Codable {
    let topics: [KaiXTopicDTO]?
    let items: [KaiXTopicDTO]?
    let days: Int?
    let fallbackUsed: Bool?

    var orderedTopics: [KaiXTopicDTO] { topics ?? items ?? [] }
}

struct KaiXSearchResponse: Codable {
    let posts: [KaiXPostDTO]
    let users: [KaiXUserDTO]
    let topics: [KaiXTopicDTO]
}

struct KaiXNotificationsResponse: Codable {
    let items: [KaiXNotificationDTO]
    let unread_count: Int
}

struct KaiXMessagesResponse: Codable {
    let items: [KaiXMessageDTO]
}

struct KaiXBootstrapResponse: Codable {
    let user: KaiXUserDTO
    let feed: [KaiXPostDTO]
    let unread_notifications: Int
    let server_time: String
}

// MARK: - Region (phase 1)

/// One country in `/api/regions/countries`. `has_provinces` tells the
/// picker whether to descend through a province step (CN/JP/US) or go
/// straight to cities (UK/SG/JP overseas …).
struct KaiXCountryDTO: Codable, Equatable, Hashable {
    let code: String
    let name: String
    let emoji: String
    let tier: Int
    let has_provinces: Bool
}

/// Province / state / prefecture under a country.
struct KaiXProvinceDTO: Codable, Equatable, Hashable {
    let code: String
    let name: String
}

/// City under either a province (hierarchical countries) or directly
/// under a country (flat countries).
struct KaiXCityDTO: Codable, Equatable, Hashable {
    let code: String
    let name: String
}

/// Hydrated region object — what `/api/regions/popular` and
/// `/api/regions/resolve` return so the UI can render a chip without
/// re-walking the directory.
struct KaiXRegionDTO: Codable, Equatable, Hashable, Identifiable {
    let region_code: String
    let country_code: String
    let country_name: String
    let country_emoji: String
    let province_code: String
    let province_name: String
    let city_code: String
    let city_name: String

    var id: String { region_code }
}

struct KaiXCountriesResponse: Codable {
    let items: [KaiXCountryDTO]
}

struct KaiXProvincesResponse: Codable {
    let country: String
    let has_provinces: Bool
    let items: [KaiXProvinceDTO]
}

struct KaiXCitiesResponse: Codable {
    let country: String
    let province: String
    let items: [KaiXCityDTO]
}

struct KaiXPopularRegionsResponse: Codable {
    let items: [KaiXRegionDTO]
}
