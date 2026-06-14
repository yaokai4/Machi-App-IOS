import Foundation
import SwiftData

@Model
final class UserEntity {
    @Attribute(.unique) var id: String
    @Attribute(.unique) var username: String
    var displayName: String
    var email: String = ""
    var avatarURL: String
    var coverURL: String
    var bio: String
    var location: String
    var joinDate: Date
    var isVerified: Bool
    var roleRaw: String
    var followerCount: Int
    var followingCount: Int
    var createdAt: Date
    var updatedAt: Date
    var passwordHash: String
    var avatarSymbol: String
    var avatarColorName: String
    var remoteId: String?
    var syncStatusRaw: String
    var deletedAt: Date?
    var cursor: String?
    // Phase 1: declared home + currently-browsing region. Persisted
    // here so the data survives even if the user clears their
    // app-side caches; `currentRegionCode` may differ from
    // `country/province/city` while travelling.
    var country: String = ""
    var province: String = ""
    var city: String = ""
    var currentRegionCode: String = ""
    var recentRegionCodesRaw: String = ""
    var membershipLevel: String = "free"
    var totalHeat: Double = 0
    var creatorBadge: String = ""
    // Admin-assigned custom tags, stored "|"-joined (SwiftData-safe default).
    var customTagsRaw: String = ""
    // Published listing counts per type as JSON {type:count}; only populated by
    // the profile-detail endpoint, powering tappable count tags.
    var listingCountsRaw: String = ""
    var isMerchant: Bool = false
    var merchantVerified: Bool = false
    var profileViewCount: Int = 0
    // Machi Verified membership cache (authoritative truth lives on the
    // server in user_memberships; these mirror /api/auth/me so the badge
    // and publish-gating work offline). Added with defaults so SwiftData
    // lightweight-migrates existing local stores with no data loss.
    var isVerifiedMember: Bool = false
    var verifiedMemberUntil: Date? = nil
    var membershipStatus: String = "inactive"
    var membershipPlanKey: String = ""
    // Phase 3: explicit App / content language preferences. Stored
    // alongside the user so they survive a logout-relogin and so the
    // server can mirror them for cross-device parity. `appLanguage`
    // mirrors the `AppLanguage` rawValue; `contentLanguagePreference`
    // mirrors `ContentLanguage.rawValue`. Empty defaults preserve
    // the "no explicit choice → follow system / follow app" behavior.
    var appLanguage: String = ""
    var contentLanguagePreference: String = ""
    var preferredContentLanguagesRaw: String = ""
    // Server-enforced DM privacy ('everyone' | 'following' | 'none'),
    // mirrored from /api/auth/me so Settings shows the truth offline.
    // Default keeps SwiftData lightweight migration safe.
    var dmPrivacy: String = "everyone"

    init(
        id: String = UUID().uuidString,
        username: String,
        displayName: String,
        email: String = "",
        avatarURL: String = "",
        coverURL: String = "",
        bio: String = "",
        location: String = "",
        joinDate: Date = .now,
        isVerified: Bool = false,
        role: UserRole = .member,
        followerCount: Int = 0,
        followingCount: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        passwordHash: String = "",
        avatarSymbol: String = "person.fill",
        avatarColorName: String = "blue",
        remoteId: String? = nil,
        syncStatus: SyncStatus = .local,
        deletedAt: Date? = nil,
        cursor: String? = nil,
        country: String = "",
        province: String = "",
        city: String = "",
        currentRegionCode: String = "",
        recentRegionCodesRaw: String = "",
        membershipLevel: String = "free",
        totalHeat: Double = 0,
        creatorBadge: String = "",
        customTagsRaw: String = "",
        listingCountsRaw: String = "",
        isMerchant: Bool = false,
        merchantVerified: Bool = false,
        profileViewCount: Int = 0,
        isVerifiedMember: Bool = false,
        verifiedMemberUntil: Date? = nil,
        membershipStatus: String = "inactive",
        membershipPlanKey: String = "",
        appLanguage: String = "",
        contentLanguagePreference: String = "",
        preferredContentLanguagesRaw: String = ""
    ) {
        self.id = id
        self.username = username.normalizedUsername
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
        self.coverURL = coverURL
        self.bio = bio
        self.location = location
        self.joinDate = joinDate
        self.isVerified = isVerified
        self.roleRaw = role.rawValue
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.passwordHash = passwordHash
        self.avatarSymbol = avatarSymbol
        self.avatarColorName = avatarColorName
        self.remoteId = remoteId
        self.syncStatusRaw = syncStatus.rawValue
        self.deletedAt = deletedAt
        self.cursor = cursor
        self.country = country
        self.province = province
        self.city = city
        self.currentRegionCode = currentRegionCode
        self.recentRegionCodesRaw = recentRegionCodesRaw
        self.membershipLevel = membershipLevel
        self.totalHeat = totalHeat
        self.creatorBadge = creatorBadge
        self.customTagsRaw = customTagsRaw
        self.listingCountsRaw = listingCountsRaw
        self.isMerchant = isMerchant
        self.merchantVerified = merchantVerified
        self.profileViewCount = profileViewCount
        self.isVerifiedMember = isVerifiedMember
        self.verifiedMemberUntil = verifiedMemberUntil
        self.membershipStatus = membershipStatus
        self.membershipPlanKey = membershipPlanKey
        self.appLanguage = appLanguage
        self.contentLanguagePreference = contentLanguagePreference
        self.preferredContentLanguagesRaw = preferredContentLanguagesRaw
    }
}

extension UserEntity {
    /// Whether to show the blue Machi Verified badge. True for active
    /// verified members AND legacy/admin-verified accounts, so the
    /// existing badge behaviour is preserved while membership lights it up.
    var displaysVerifiedBadge: Bool { isVerified || isVerifiedMember }

    /// Admin-assigned tags shown as bordered chips on the profile.
    var customTags: [String] {
        customTagsRaw.split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    /// Published listing counts per type (二手/租房/招聘/服务…) for tappable tags.
    var listingCounts: [String: Int] {
        guard let data = listingCountsRaw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return dict
    }

    var role: UserRole {
        get { UserRole(rawValue: roleRaw) ?? .member }
        set {
            roleRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .local }
        set {
            syncStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var recentRegionCodes: [String] {
        get { recentRegionCodesRaw.storedHashtags }
        set {
            recentRegionCodesRaw = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
                .removingDuplicates()
                .joined(separator: "|")
            updatedAt = .now
        }
    }

    /// Pipe-delimited list of preferred content-language tags
    /// ("zh|en|ja"). Empty string defaults to "no extras configured".
    var preferredContentLanguages: [String] {
        get { preferredContentLanguagesRaw.storedHashtags }
        set {
            preferredContentLanguagesRaw = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
                .removingDuplicates()
                .joined(separator: "|")
            updatedAt = .now
        }
    }
}
