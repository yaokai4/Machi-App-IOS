import Foundation

// Split out of KaiXAPIDTO.swift for maintainability (reservations · membership · payments · points wallet · login devices).
// Plain Codable mirrors of the backend JSON; see KaiXAPIDTO.swift for the
// shared conventions (snake_case fields, Decodable-only, no SwiftData here).

// MARK: - Reservation calendar (no money)

/// A bookable time slot a merchant/landlord published on a listing.
struct KaiXBookingSlotDTO: Codable, Identifiable, Equatable {
    let id: String
    let listingId: String?
    let startAt: String?
    let endAt: String?
    let capacity: Int?
    let bookedCount: Int?
    let available: Int?
    let isFull: Bool?
    let note: String?
    let status: String?
    let bookedByMe: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case listingId = "listing_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case capacity
        case bookedCount = "booked_count"
        case available
        case isFull = "is_full"
        case note
        case status
        case bookedByMe = "booked_by_me"
    }

    var resolvedAvailable: Int { available ?? max(0, (capacity ?? 1) - (bookedCount ?? 0)) }
    var resolvedIsFull: Bool { isFull ?? (resolvedAvailable <= 0) }
    var resolvedBookedByMe: Bool { bookedByMe ?? false }

    /// Parsed start date (ISO8601, with/without fractional seconds).
    var startDate: Date? { KaiXBookingSlotDTO.parseISO(startAt) }
    var endDate: Date? { KaiXBookingSlotDTO.parseISO(endAt) }

    static func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        // Delegate to the app-wide cached ISO8601 parsers (KXDateParsing):
        // building a fresh ISO8601DateFormatter here did ICU setup on every
        // slot/booking row render. Same fractional→plain fallback order, so
        // parsing results are unchanged.
        if let d = KXDateParsing.isoFractional.date(from: s) { return d }
        return KXDateParsing.iso.date(from: s)
    }
}

struct KaiXBookingSlotsResponse: Decodable {
    let items: [KaiXBookingSlotDTO]
    let isOwner: Bool?
    enum CodingKeys: String, CodingKey { case items; case isOwner = "is_owner" }
}

/// A reservation the current user made (or, owner-side, received).
struct KaiXBookingDTO: Codable, Identifiable, Equatable {
    let id: String
    let slotId: String?
    let listingId: String?
    let status: String?
    let note: String?
    let startAt: String?
    let endAt: String?
    let listingTitle: String?
    let listingType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case slotId = "slot_id"
        case listingId = "listing_id"
        case status
        case note
        case startAt = "start_at"
        case endAt = "end_at"
        case listingTitle = "listing_title"
        case listingType = "listing_type"
    }

    var startDate: Date? { KaiXBookingSlotDTO.parseISO(startAt) }
}

struct KaiXBusinessDocumentDTO: Codable, Identifiable, Equatable {
    let id: String
    let documentId: String?
    let documentType: String?
    let label: String?
    let documentStatus: String?
    let fileType: String?
    let contentType: String?
    let fileSize: Int?
    let purpose: String?
    let entityId: String?
    let status: String?
    let isPrivate: Bool?
    let createdAt: String?
}

struct KaiXBusinessProfileDTO: Codable, Identifiable, Equatable {
    let id: String
    let owner_user_id: String?
    let owner: KaiXUserDTO?
    let business_name: String
    let business_type: String
    let legal_name: String?
    let representative_name: String?
    let registration_number: String?
    let country_code: String?
    let city_slug: String?
    let verification_status: String
    let application_status: String?
    let contact_method: String?
    let phone: String?
    let email: String?
    let website: String?
    let address: String?
    let postal_code: String?
    let description: String?
    let service_categories: [String]?
    let service_cities: [String]?
    let logo_url: String?
    let cover_url: String?
    let application_note: String?
    let review_note: String?
    let submitted_at: String?
    let reviewed_at: String?
    let created_at: String?
    let updated_at: String?
    let documents: [KaiXBusinessDocumentDTO]?
    let document_count: Int?
    let listing_count: Int?
    let published_listing_count: Int?
    let inquiry_count: Int?
}

struct KaiXBusinessProfileResponse: Codable {
    let business: KaiXBusinessProfileDTO?
    let status: String?
}

struct KaiXBusinessSaveResponse: Codable {
    let ok: Bool?
    let business: KaiXBusinessProfileDTO
    let user: KaiXUserDTO?
}

struct KaiXBusinessDashboardDTO: Codable {
    struct Metrics: Codable, Equatable {
        let listings: Int
        let published: Int
        let inquiries: Int
        let new_inquiries: Int
        let favorites: Int
        let views: Int
    }
    let business: KaiXBusinessProfileDTO?
    let metrics: Metrics
    let recent_listings: [KaiXCityListingDTO]
    let recent_inquiries: [KaiXListingInquiryDTO]
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

/// Echo of the applied /api/listings filters. `fallback`/`fallback_label` only
/// appear when the requested area had zero rows and the server widened the
/// scope ("metro_circle" / "country") — clients surface a one-line notice.
struct KaiXListingFiltersDTO: Codable {
    let fallback: String?
    let fallback_label: String?
}

struct KaiXListingsResponse: Codable {
    struct DataPayload: Codable {
        let filters: KaiXListingFiltersDTO?
    }

    let items: [KaiXCityListingDTO]
    let next_cursor: String?
    /// 满足当前筛选的真实总条数——只在第一页下发(游标页为 nil)。频道头部
    /// 用它展示「311 条结果」,而不是把「已加载 24 条」误标成总数。
    let total: Int?
    let type: String?
    /// Envelope `data` — carries `filters` (empty-result fallback contract).
    let data: DataPayload?
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
    var explicitAppleProductID: String? {
        [appleProductId, apple_product_id, iosIapProductId, ios_iap_product_id]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
    var appleProductID: String {
        explicitAppleProductID ?? canonicalPlanKey
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

// MARK: - Machi Points wallet
// Points are internal scrip — bought via App Store IAP on iOS, spent only on
// Machi digital goods. Never cash: no withdrawal/transfer/expiry. The balance
// is authoritative on the server; iOS only reads it and routes IAP purchases.

struct KaiXWalletDTO: Codable, Equatable {
    let balancePoints: Int
    let status: String?
    let lifetimePurchasedPoints: Int?
    let lifetimeBonusPoints: Int?
    let lifetimeSpentPoints: Int?
    let pointsName: String?
    let displayBalance: String?
    let disclaimer: String?
}

struct KaiXWalletLedgerEntryDTO: Codable, Equatable, Identifiable {
    let id: String
    let entryType: String
    let pointsDelta: Int
    let balanceAfter: Int
    let sourceType: String?
    let productId: String?
    let createdAt: String?
    let displayDelta: String?
}

struct KaiXWalletTopupProductDTO: Codable, Equatable, Identifiable {
    let id: String
    let packKey: String
    let title: String
    let subtitle: String?
    let points: Int
    let bonusPoints: Int
    let totalPoints: Int
    let amountCents: Int
    let currency: String
    let priceLabel: String?
    let displayPoints: String?
    let appleProductId: String?
    let iosIapProductId: String?
    let googleProductId: String?
    let purchasable: Bool?
    let disabledReason: String?

    /// The StoreKit product id iOS should buy for this pack.
    var resolvedAppleProductID: String {
        if let pid = appleProductId, !pid.isEmpty { return pid }
        if let pid = iosIapProductId, !pid.isEmpty { return pid }
        return packKey
    }
}

struct KaiXWalletMeResponse: Codable {
    let wallet: KaiXWalletDTO
    let topupProducts: [KaiXWalletTopupProductDTO]
    let recentEntries: [KaiXWalletLedgerEntryDTO]
    let pointsName: String?
    let disclaimer: String?
}

struct KaiXWalletLedgerResponse: Codable {
    let wallet: KaiXWalletDTO
    let entries: [KaiXWalletLedgerEntryDTO]
    let page: Int?
    let pageSize: Int?
    let hasMore: Bool?
}

struct KaiXWalletTopupProductsResponse: Codable {
    let topupProducts: [KaiXWalletTopupProductDTO]
    let pointsName: String?
    let disclaimer: String?
}

struct KaiXWalletTopupVerifyResponse: Codable {
    let wallet: KaiXWalletDTO
    let grantedPoints: Int?
}

struct KaiXWalletPurchaseResponse: Codable {
    let status: String
    let orderId: String?
    let orderNo: String?
    let message: String?
    let wallet: KaiXWalletDTO?
    let alreadyOwned: Bool?
}

/// POST /api/payments/apple/guide-verify — single-product IAP settlement.
struct KaiXGuideIapVerifyResponse: Codable {
    let status: String?
    let orderNo: String?
    let alreadyOwned: Bool?
}

struct KaiXWalletPointsContextDTO: Codable, Equatable, Hashable {
    let eligible: Bool?
    let requiredPoints: Int?
    let currentBalance: Int?
    let sufficient: Bool?
    let owned: Bool?
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

/// This month's remaining high-trust publish quota for a member. The server may
/// return either an overall `remaining`/`limit`, or a per-group breakdown. All
/// fields optional so a trimmed/older payload still decodes; the client shows
/// whatever it can resolve for the current listing type.
struct KaiXMembershipListingQuotaResponse: Codable {
    let membershipActive: Bool?
    let limit: Int?
    let used: Int?
    let remaining: Int?
    let periodResetAt: String?
    let groups: [KaiXMembershipListingQuotaGroup]?

    /// Remaining count for a specific listing group (e.g. "rental"), falling back
    /// to the overall `remaining`. Returns nil when nothing is resolvable.
    func remaining(forGroup group: String?) -> Int? {
        if let group, let match = groups?.first(where: { $0.matches(group) }) {
            return match.remaining ?? match.derivedRemaining
        }
        return remaining ?? {
            guard let limit else { return nil }
            return max(0, limit - (used ?? 0))
        }()
    }
}

struct KaiXMembershipListingQuotaGroup: Codable {
    let key: String?
    let group: String?
    let type: String?
    let limit: Int?
    let used: Int?
    let remaining: Int?

    var derivedRemaining: Int? {
        guard let limit else { return nil }
        return max(0, limit - (used ?? 0))
    }

    func matches(_ listingType: String) -> Bool {
        let ids = [key, group, type].compactMap { $0?.lowercased() }
        return ids.contains(listingType.lowercased())
    }
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
    let fileName: String?
    let originalFileName: String?
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
        originalUrl ?? original_url ?? largeUrl ?? large_url ?? cdnUrl ?? publicUrl ?? url ?? ""
    }

    var mediumURLString: String {
        mediumUrl ?? medium_url ?? largeUrl ?? large_url ?? sourceURLString
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
    let meetupGoing: Int?
    let meetupJoined: Bool?
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

struct KaiXDraftDTO: Codable, Identifiable, Equatable {
    let id: String
    let content: String
    let media_ids: [String]
    let tags: [String]
    let country: String?
    let province: String?
    let city: String?
    let region_code: String?
    let content_type: String?
    let attributes: [String: KaiXAttributeValue]?
    let language: String?
    let updated_at: String
}

struct KaiXDraftsResponse: Codable {
    let items: [KaiXDraftDTO]
}

struct KaiXSaveDraftResponse: Codable {
    let id: String
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
    let is_accepted: Bool?
}

struct KaiXNotificationDTO: Codable, Equatable {
    let id: String
    let type: String
    let actor_id: String
    let user_id: String
    let target_post_id: String?
    let target_comment_id: String?
    let target_listing_id: String?
    let target_conversation_id: String?
    // Custom title for admin/system broadcasts; empty/absent for typed
    // notifications whose title the client derives from the type.
    let title: String?
    let content: String?
    let is_read: Bool
    let created_at: String
    let actor: KaiXUserDTO?
}

/// One admin push-broadcast task (mirrors the server's serialize_push_campaign).
/// Only the audience + admin-authored copy + aggregate counts — never the
/// recipients' identities.
struct KaiXPushCampaignDTO: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let body: String
    let audience: String
    let audienceUserIds: [String]?
    let audienceUserCount: Int?
    let deepLinkType: String?
    let deepLinkId: String?
    let urgent: Bool
    let status: String
    let recipientCount: Int
    let sentCount: Int
    let failedCount: Int
    let createdAt: String?
    let updatedAt: String?
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
    let object_key: String?
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
    // Private DM video poster: when true, the cover must be fetched via a signed
    // URL (posterViewUrlEndpoint) instead of a public URL. Absent/false on legacy
    // public covers and on older servers, so those keep their direct URL.
    let needsSignedPoster: Bool?
    let posterViewUrlEndpoint: String?
    let thumbnail_purpose: String?
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
    let push_inquiries: Bool?   // optional: tolerates servers that predate this field
    let privacy_protect: Bool
    let privacy_allow_dm: String
    let recommend_following: Bool
    let recommend_topics: Bool
    // Optional for rolling compatibility with servers deployed before the
    // standalone App Store consumption-information consent contract.
    let apple_consumption_consent: Bool?
    let apple_consumption_consent_policy_version: String?
    let apple_consumption_consented_at: String?
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

// MARK: - 邀请裂变 (referral / invite growth loop)
//
// Mirrors `server_referral.referral_summary` (GET /api/referral/me). Unlike the
// snake_case wallet/reservation DTOs above, the referral summary is already
// serialized in camelCase server-side, so these property names map 1:1 with no
// CodingKeys needed. Machi Points earned via referral are a virtual accounting
// liability — never cash.

/// One row in the "最近邀请" list on the invite 战绩页.
struct KaiXReferralInviteeDTO: Codable, Equatable, Identifiable {
    let referralId: String
    let status: String        // pending | qualified | rewarded | rejected
    let handle: String
    let displayName: String
    let avatarUrl: String
    let createdAt: String
    let rewardedAt: String

    var id: String { referralId }

    /// True once the invitee did their first valuable action (both sides paid,
    /// or at least advanced past pending).
    var isQualified: Bool { status == "qualified" || status == "rewarded" }
    var isRewarded: Bool { status == "rewarded" }
}

/// GET /api/referral/me → the invite 战绩页 data model. The stable per-user code
/// is minted lazily server-side on first read, so `code`/`shareUrl` are always
/// present.
struct KaiXReferralSummaryDTO: Codable, Equatable {
    let code: String
    let shareUrl: String
    let invitedCount: Int
    let qualifiedCount: Int
    let pointsEarned: Int
    let inviterReward: Int
    let inviteeReward: Int
    let recentInvitees: [KaiXReferralInviteeDTO]
}

/// Envelope: the server wraps the summary as `{"referral": {…}}`.
struct KaiXReferralMeResponse: Codable {
    let referral: KaiXReferralSummaryDTO
}

/// POST /api/referral/bind → `{bound, reason}`. Used to late-bind an invite for
/// a user who tapped the link *after* they already had an account.
struct KaiXReferralBindResponse: Codable {
    let bound: Bool
    let reason: String?
}
