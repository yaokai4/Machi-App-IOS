import Foundation

enum CityChannel: String, CaseIterable, Identifiable, Hashable {
    case recommend
    case dynamic
    case news
    case guide
    case secondhand
    case housing
    case jobSeek
    case jobPost
    case meetup
    case dining
    case event
    case question
    case service
    case merchant
    case coupon
    case warning
    case hot

    var id: String { rawValue }

    var contentTypes: [ContentType]? {
        switch self {
        case .recommend, .hot:
            nil
        case .dynamic:
            [.dynamic, .image_post, .long_post, .rant, .anonymous, .poll]
        case .news:
            [.news, .local_info]
        case .guide:
            [.guide]
        case .secondhand:
            [.secondhand]
        case .housing:
            [.housing, .roommate]
        case .jobSeek:
            [.job_seek]
        case .jobPost:
            [.job_post, .referral]
        case .meetup:
            [.meetup]
        case .dining:
            [.dining]
        case .event:
            [.event]
        case .question:
            [.question]
        case .service:
            [.service]
        case .merchant:
            [.merchant]
        case .coupon:
            [.coupon]
        case .warning:
            [.warning]
        }
    }

    var sortsByHeat: Bool {
        self == .recommend || self == .hot
    }

    var limitsToRecentHotWindow: Bool {
        self == .hot
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .recommend: L("forYou", language)
        case .dynamic: L("ct_dynamic", language)
        case .news: L("ct_news", language)
        case .guide: L("ct_guide", language)
        case .secondhand: L("ct_secondhand", language)
        case .housing: L("ct_housing", language)
        case .jobSeek: L("ct_jobseek", language)
        case .jobPost: L("ct_jobpost", language)
        case .meetup: L("ct_meetup", language)
        case .dining: L("ct_dining", language)
        case .event: L("ct_event", language)
        case .question: L("ct_question", language)
        case .service: L("ct_service", language)
        case .merchant: L("ct_merchant", language)
        case .coupon: L("ct_coupon", language)
        case .warning: L("ct_warning", language)
        case .hot: L("hot", language)
        }
    }

    func description(_ language: AppLanguage) -> String {
        switch self {
        case .recommend: L("cityDescRecommend", language)
        case .dynamic: L("cityDescDynamic", language)
        case .news: L("cityDescNews", language)
        case .guide: L("cityDescGuide", language)
        case .secondhand: L("cityDescSecondhand", language)
        case .housing: L("cityDescHousing", language)
        case .jobSeek: L("cityDescJobSeek", language)
        case .jobPost: L("cityDescJobPost", language)
        case .meetup: L("cityDescMeetup", language)
        case .dining: L("cityDescDining", language)
        case .event: L("cityDescEvent", language)
        case .question: L("cityDescQuestion", language)
        case .service: L("cityDescService", language)
        case .merchant: L("cityDescMerchant", language)
        case .coupon: L("cityDescCoupon", language)
        case .warning: L("cityDescWarning", language)
        case .hot: L("cityDescHot", language)
        }
    }

    // MARK: - Primary grouping

    /// Top-level category used by `CityChannelView` to drop the
    /// 17-tab horizontal carousel into 6 broad sections. The user
    /// taps a primary first, then picks a secondary chip below it.
    enum Primary: String, CaseIterable, Identifiable, Hashable {
        case recommend, life, marketplace, work, social, info

        var id: String { rawValue }

        func title(_ language: AppLanguage) -> String {
            switch self {
            case .recommend: return L("cityPrimaryRecommend", language)
            case .life:      return L("cityPrimaryLife", language)
            case .marketplace: return L("cityPrimaryMarketplace", language)
            case .work:      return L("cityPrimaryWork", language)
            case .social:    return L("cityPrimarySocial", language)
            case .info:      return L("cityPrimaryInfo", language)
            }
        }

        var icon: String {
            switch self {
            case .recommend: "star"
            case .life: "leaf"
            case .marketplace: "bag"
            case .work: "briefcase"
            case .social: "person.2"
            case .info: "newspaper"
            }
        }

        /// Channels that should be rendered as secondary chips when this
        /// primary is selected. Order matters — first chip is the
        /// default landing tab.
        var channels: [CityChannel] {
            switch self {
            case .recommend: return [.recommend, .hot, .dynamic]
            case .life:      return [.dynamic, .guide, .question, .warning]
            case .marketplace: return [.secondhand, .housing, .coupon]
            case .work:      return [.jobSeek, .jobPost]
            case .social:    return [.meetup, .dining, .event]
            case .info:      return [.news, .service, .merchant]
            }
        }
    }

    var primary: Primary {
        switch self {
        case .recommend, .hot: return .recommend
        case .dynamic, .guide, .question, .warning: return .life
        case .secondhand, .housing, .coupon: return .marketplace
        case .jobSeek, .jobPost: return .work
        case .meetup, .dining, .event: return .social
        case .news, .service, .merchant: return .info
        }
    }
}
