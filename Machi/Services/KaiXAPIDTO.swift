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

struct KaiXMembershipPlanDTO: Codable, Equatable {
    let plan_key: String
    let name_zh: String?
    let name_en: String?
    let name_ja: String?
    let amount: Double
    let currency: String
    let billing_cycle: String?
}

struct KaiXMembershipMeResponse: Codable {
    let membership: KaiXMembershipStatusDTO
    let plan: KaiXMembershipPlanDTO?
    let user: KaiXUserDTO
}

struct KaiXMembershipPlanResponse: Codable {
    let plan: KaiXMembershipPlanDTO?
    let apple_product_id: String?
}

struct KaiXMembershipBenefitDTO: Codable, Equatable, Identifiable {
    let key: String
    let title: String
    let description: String
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
    let owner_id: String
    let type: String
    let url: String
    let thumb_url: String?
    let mime: String
    let width: Int?
    let height: Int?
    let duration: Double?
    let byte_size: Int?
    let created_at: String
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
    let post_count: Int
}

// MARK: - Local News Desk

struct KaiXEditorialPostDTO: Codable, Equatable, Identifiable {
    let id: String
    let news_item_id: String?
    let author_type: String
    let authorType: String?
    let author_display_name: String
    let authorDisplayName: String?
    let country: String
    let city: String
    let language: String
    let category: String
    let title: String
    let summary: String
    let body: String
    let source_name: String?
    let sourceName: String?
    let source_url: String?
    let sourceUrl: String?
    let original_url: String?
    let originalUrl: String?
    let source_published_at: String?
    let sourcePublishedAt: String?
    let status: String
    let review_status: String
    let reviewed_by_admin_id: String?
    let reviewed_at: String?
    let published_at: String?
    let publishedAt: String?
    let view_count: Int?
    let viewCount: Int?
    let share_count: Int?
    let shareCount: Int?
    let click_source_count: Int?
    let clickSourceCount: Int?
    let risk_level: String?
    let riskLevel: String?
    let official_source_required: Bool?
    let officialSourceRequired: Bool?
    let is_demo: Bool?
    let is_ai_assisted: Bool?
    let isAiAssisted: Bool?
    let ai_model: String?
    let ai_prompt_version: String?
    let created_by_admin_id: String?
    let created_at: String
    let updated_at: String
    let tags: [String]
    let save_count: Int
    let saveCount: Int?
    let comment_count: Int
    let commentCount: Int?
    let saved: Bool
    let is_saved: Bool?
    let isSaved: Bool?
    let can_interact: Bool?
    let canInteract: Bool?
    let source_note: String?
    let sourceNote: String?
    let editorial_disclaimer: String?
    let editorialDisclaimer: String?
}

struct KaiXEditorialCommentDTO: Codable, Equatable, Identifiable {
    let id: String
    let editorial_post_id: String
    let author_id: String
    let content: String
    let created_at: String
    let updated_at: String
    let author: KaiXUserDTO?
}

struct KaiXNewsListResponse: Codable {
    let items: [KaiXEditorialPostDTO]
    let page: Int
    let limit: Int
    let total: Int
}

struct KaiXNewsDetailResponse: Codable {
    let post: KaiXEditorialPostDTO
    let related: [KaiXEditorialPostDTO]
}

struct KaiXNewsCommentsResponse: Codable {
    let items: [KaiXEditorialCommentDTO]
}

struct KaiXPageDTO<Item: Codable>: Codable {
    let items: [Item]
    let next_cursor: String?
}

struct KaiXLoginResponse: Codable {
    let token: String
    let user: KaiXUserDTO
}

struct KaiXAvailabilityResponse: Codable, Equatable {
    let available: Bool
    let message: String
    let code: String?
}

struct KaiXEmailCodeResponse: Codable, Equatable {
    let ok: Bool
    let expires_in: Int
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
