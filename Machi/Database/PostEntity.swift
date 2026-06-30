import Foundation
import SwiftData

@Model
final class PostEntity {
    @Attribute(.unique) var id: String
    var authorId: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var commentCount: Int
    var repostCount: Int
    var likeCount: Int
    var bookmarkCount: Int
    var viewCount: Int
    var heatScore: Double
    var isLikedByCurrentUser: Bool
    var isBookmarkedByCurrentUser: Bool
    var isRepostedByCurrentUser: Bool
    var statusRaw: String
    var hashtagsRaw: String
    var repostOfPostId: String?
    var remoteId: String?
    var syncStatusRaw: String
    var deletedAt: Date?
    var cursor: String?
    // Phase 1: region. All optional / defaulted so SwiftData
    // lightweight migration handles existing rows without a backfill.
    // `regionCode` is the canonical "country[.province].city" slug
    // and the field most queries should filter on.
    var country: String = ""
    var province: String = ""
    var city: String = ""
    var regionCode: String = ""
    // Phase 2: content type discriminator + typed attributes (JSON
    // string, decoded on demand via `attributes`). Defaults to
    // "dynamic" / "" so legacy posts keep working.
    var contentTypeRaw: String = "dynamic"
    var attributesRaw: String = ""
    // Moderation + commercialization reserves. Defaults keep older
    // local rows valid and let the server roll these out gradually.
    var reportCount: Int = 0
    var isBoosted: Bool = false
    var boostWeight: Double = 0
    var boostedUntil: Date?
    // Phase 3: BCP-47-ish short tag for the post's content language
    // ("zh" / "en" / "ja" / …). Empty string means "language unknown"
    // — feeds treat such rows as universal and de-prioritize them
    // relative to language-matched content.
    var language: String = ""
    // City Seed Bot (城市内容助手). True for official cold-start content
    // (城市助手 / 编辑部); rendered with an official identity + light badge,
    // never as a real user. `seedAuthorType` ∈ {"official_bot","editorial"}.
    var isSeedContent: Bool = false
    var seedAuthorType: String = ""

    init(
        id: String = UUID().uuidString,
        authorId: String,
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        commentCount: Int = 0,
        repostCount: Int = 0,
        likeCount: Int = 0,
        bookmarkCount: Int = 0,
        viewCount: Int = 0,
        heatScore: Double = 0,
        isLikedByCurrentUser: Bool = false,
        isBookmarkedByCurrentUser: Bool = false,
        isRepostedByCurrentUser: Bool = false,
        status: PostStatus = .published,
        hashtags: [String] = [],
        repostOfPostId: String? = nil,
        remoteId: String? = nil,
        syncStatus: SyncStatus = .local,
        deletedAt: Date? = nil,
        cursor: String? = nil,
        country: String = "",
        province: String = "",
        city: String = "",
        regionCode: String = "",
        contentType: ContentType = .dynamic,
        attributesRaw: String = "",
        reportCount: Int = 0,
        isBoosted: Bool = false,
        boostWeight: Double = 0,
        boostedUntil: Date? = nil,
        language: String = "",
        isSeedContent: Bool = false,
        seedAuthorType: String = ""
    ) {
        self.id = id
        self.authorId = authorId
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.commentCount = commentCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.bookmarkCount = bookmarkCount
        self.viewCount = viewCount
        self.heatScore = heatScore
        self.isLikedByCurrentUser = isLikedByCurrentUser
        self.isBookmarkedByCurrentUser = isBookmarkedByCurrentUser
        self.isRepostedByCurrentUser = isRepostedByCurrentUser
        self.statusRaw = status.rawValue
        self.hashtagsRaw = hashtags.normalizedHashtagStorage
        self.repostOfPostId = repostOfPostId
        self.remoteId = remoteId
        self.syncStatusRaw = syncStatus.rawValue
        self.deletedAt = deletedAt
        self.cursor = cursor
        self.country = country
        self.province = province
        self.city = city
        self.regionCode = regionCode
        self.contentTypeRaw = contentType.rawValue
        self.attributesRaw = attributesRaw
        self.reportCount = reportCount
        self.isBoosted = isBoosted
        self.boostWeight = boostWeight
        self.boostedUntil = boostedUntil
        self.language = language
        self.isSeedContent = isSeedContent
        self.seedAuthorType = seedAuthorType
    }
}

extension PostEntity {
    var status: PostStatus {
        get { PostStatus(rawValue: statusRaw) ?? .published }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var hashtags: [String] {
        get { hashtagsRaw.storedHashtags }
        set {
            hashtagsRaw = newValue.normalizedHashtagStorage
            updatedAt = .now
        }
    }

    func matchesTopic(_ topic: String) -> Bool {
        let normalized = topic.normalizedTopicName
        guard !normalized.isEmpty else { return false }
        if hashtags.contains(where: { $0.normalizedTopicName == normalized }) {
            return true
        }
        return content.extractedHashtags.contains(normalized)
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .local }
        set {
            syncStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var previewText: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Discriminator for the local-life content matrix. Computed
    /// against the raw string so legacy posts (missing column on
    /// disk) decode to `.dynamic` instead of crashing.
    var contentType: ContentType {
        get { ContentType(rawValue: contentTypeRaw) ?? .dynamic }
        set { contentTypeRaw = newValue.rawValue }
    }

    /// Typed attributes parsed from the JSON blob. The dictionary
    /// values are `Any` — callers use the typed accessors below
    /// (`stringAttribute(_:)` etc.) so view code never has to
    /// touch `Any`.
    var attributes: [String: Any] {
        guard !attributesRaw.isEmpty,
              let data = attributesRaw.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    func stringAttribute(_ key: String) -> String? {
        attributes[key] as? String
    }

    func doubleAttribute(_ key: String) -> Double? {
        if let n = attributes[key] as? Double { return n }
        if let n = attributes[key] as? Int { return Double(n) }
        if let s = attributes[key] as? String { return Double(s) }
        return nil
    }

    func intAttribute(_ key: String) -> Int? {
        if let n = attributes[key] as? Int { return n }
        if let n = attributes[key] as? Double { return Int(n) }
        if let s = attributes[key] as? String { return Int(s) }
        return nil
    }

    func boolAttribute(_ key: String) -> Bool? {
        if let b = attributes[key] as? Bool { return b }
        if let n = attributes[key] as? Int  { return n != 0 }
        return nil
    }
}
