import Foundation

enum UserRole: String, CaseIterable, Identifiable {
    case member
    case creator
    case admin

    var id: String { rawValue }
}

enum PostStatus: String, CaseIterable, Identifiable {
    case draft
    case uploading
    case published
    case active
    case hidden
    case deleted
    case under_review
    case failed

    var id: String { rawValue }

    var isPubliclyVisible: Bool {
        self == .published || self == .active
    }
}

enum MediaType: String, CaseIterable, Identifiable {
    case image
    case video

    var id: String { rawValue }
}

enum UploadState: String, CaseIterable, Identifiable {
    case waiting
    case compressing
    case local
    case uploading
    case uploaded
    case failed

    var id: String { rawValue }
}

enum MessageStatus: String, CaseIterable, Identifiable {
    case sending
    case sent
    case failed

    var id: String { rawValue }
}

enum MessageContentType: String, CaseIterable, Identifiable {
    case text
    case image
    case video
    case mixed
    case system

    var id: String { rawValue }
}

enum NotificationType: String, CaseIterable, Identifiable {
    case like
    case repost
    case comment
    case reply
    case follow
    case mention
    case bookmark
    // A new DM arrived (server inserts at most one unread row per
    // conversation). Raw values mirror the backend `notifications.type`.
    case message
    // Someone contacted the user about one of their listings.
    case listingInquiry = "listing_inquiry"
    // A new listing matched one of the user's saved searches.
    case savedSearch = "saved_search"
    // A favorited listing dropped its price. Deep-links to the listing.
    case favoritePriceDrop = "favorite_price_drop"
    // A favorited listing was taken down / closed. Deep-links to the listing.
    case favoriteClosed = "favorite_closed"
    // A batched follow summary ("X and 3 others followed you"). Opens the actor.
    case followDigest = "follow_digest"
    // A periodic city activity roundup. Lands on the home/discover tab.
    case cityDigest = "city_digest"
    case system

    var id: String { rawValue }
}

enum SyncStatus: String, CaseIterable, Identifiable {
    case local
    case syncing
    case synced
    case failed
    case deleted

    var id: String { rawValue }
}

/// Discriminator for KaiX's local-life content matrix. Mirrors
/// `CONTENT_TYPES` in `web/server.py` — keep them in sync.
///
/// `dynamic` is the implicit default for "just type and post" usage
/// and for any post created before content_type existed.
enum ContentType: String, CaseIterable, Identifiable, Hashable {
    case dynamic
    case image_post
    case long_post
    case news
    case local_info
    case guide
    case question
    case rant
    case secondhand
    case housing
    case roommate
    case job_seek
    case job_post
    case referral
    case meetup
    case dining
    case event
    case service
    case merchant
    case coupon
    case warning
    case poll
    case anonymous

    var id: String { rawValue }
}

enum TimelineMode: String, CaseIterable, Identifiable {
    case recommend
    case hot
    case local
    case following

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .recommend: L("forYou", language)
        case .hot:       L("hot", language)
        case .local:     L("local", language)
        case .following: L("following", language)
        }
    }
}

enum ProfileSegment: String, CaseIterable, Identifiable {
    case posts
    case replies
    case media
    case likes
    case bookmarks

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .posts: L("posts", language)
        case .replies: L("replies", language)
        case .media: L("media", language)
        case .likes: L("likes", language)
        case .bookmarks: L("bookmarks", language)
        }
    }
}
