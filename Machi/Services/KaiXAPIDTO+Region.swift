import Foundation

// Split out of KaiXAPIDTO.swift for maintainability (region directory · discover hot board).
// Plain Codable mirrors of the backend JSON; see KaiXAPIDTO.swift for the
// shared conventions (snake_case fields, Decodable-only, no SwiftData here).

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

/// Workbench overview counts (GET /api/my/workbench/summary). Every field
/// defaults so a missing/null key never breaks decoding.
struct KaiXWorkbenchSummaryDTO: Decodable {
    var posts = 0
    var followers = 0
    var following = 0
    var publishedListings = 0
    var pendingReview = 0
    var offlineListings = 0
    var receivedInquiries = 0
    var newInquiries = 0
    var sentInquiries = 0
    var applications = 0
    var newApplications = 0
    var bookings = 0
    var newBookings = 0
    var consults = 0
    var newConsults = 0
    var orders = 0
    var views = 0
    var newLeads = 0
    var membershipActive = false
    var merchantVerified = false

    enum CodingKeys: String, CodingKey {
        case posts, followers, following, publishedListings, pendingReview, offlineListings
        case receivedInquiries, newInquiries, sentInquiries, applications, newApplications
        case bookings, newBookings, consults, newConsults, orders, views, newLeads
        case membershipActive, merchantVerified
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func i(_ k: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: k)) ?? 0 }
        func b(_ k: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? false }
        posts = i(.posts); followers = i(.followers); following = i(.following)
        publishedListings = i(.publishedListings); pendingReview = i(.pendingReview); offlineListings = i(.offlineListings)
        receivedInquiries = i(.receivedInquiries); newInquiries = i(.newInquiries); sentInquiries = i(.sentInquiries)
        applications = i(.applications); newApplications = i(.newApplications)
        bookings = i(.bookings); newBookings = i(.newBookings)
        consults = i(.consults); newConsults = i(.newConsults)
        orders = i(.orders); views = i(.views); newLeads = i(.newLeads)
        membershipActive = b(.membershipActive); merchantVerified = b(.merchantVerified)
    }

    /// Total items needing attention today (drives the 今日待处理 banner).
    var pendingTotal: Int { newInquiries + newApplications + newBookings + pendingReview }
}

// MARK: - Discover hot board (热榜)

/// One ranked topic on the local trend board. The server owns the ranking and
/// the explainable `reason`; iOS only renders. Decoding is fully defensive so a
/// server that adds/renames fields can never crash the Discover tab.
struct KaiXDiscoverHotItemDTO: Decodable, Identifiable {
    let id: String
    var kind: String
    var title: String
    var subtitle: String
    var reason: String
    var scope: String
    var scopeLabel: String
    var timeWindow: String
    var rank: Int
    var rankDelta: Int
    var trend: String          // "up" | "down" | "flat"
    var heatScore: Int
    var relatedPosts: Int
    var routeType: String
    var routeID: String

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle, reason, scope, scopeLabel
        case timeWindow, rank, rankDelta, trend, heatScore, relatedPosts, route
    }
    private enum RouteKeys: String, CodingKey { case type, id }

    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        id = (try? c?.decodeIfPresent(String.self, forKey: .id) ?? nil) ?? UUID().uuidString
        kind = (try? c?.decodeIfPresent(String.self, forKey: .kind) ?? nil) ?? "topic"
        title = (try? c?.decodeIfPresent(String.self, forKey: .title) ?? nil) ?? ""
        subtitle = (try? c?.decodeIfPresent(String.self, forKey: .subtitle) ?? nil) ?? ""
        reason = (try? c?.decodeIfPresent(String.self, forKey: .reason) ?? nil) ?? ""
        scope = (try? c?.decodeIfPresent(String.self, forKey: .scope) ?? nil) ?? "city"
        scopeLabel = (try? c?.decodeIfPresent(String.self, forKey: .scopeLabel) ?? nil) ?? ""
        timeWindow = (try? c?.decodeIfPresent(String.self, forKey: .timeWindow) ?? nil) ?? "24h"
        rank = (try? c?.decodeIfPresent(Int.self, forKey: .rank) ?? nil) ?? 0
        rankDelta = (try? c?.decodeIfPresent(Int.self, forKey: .rankDelta) ?? nil) ?? 0
        trend = (try? c?.decodeIfPresent(String.self, forKey: .trend) ?? nil) ?? "flat"
        heatScore = (try? c?.decodeIfPresent(Int.self, forKey: .heatScore) ?? nil) ?? 0
        relatedPosts = (try? c?.decodeIfPresent(Int.self, forKey: .relatedPosts) ?? nil) ?? 0
        let route = try? c?.nestedContainer(keyedBy: RouteKeys.self, forKey: .route)
        routeType = (try? route?.decodeIfPresent(String.self, forKey: .type) ?? nil) ?? ""
        routeID = (try? route?.decodeIfPresent(String.self, forKey: .id) ?? nil) ?? ""
    }
}

struct KaiXDiscoverHotResponse: Decodable {
    var items: [KaiXDiscoverHotItemDTO]
    var scope: String
    var timeWindow: String

    private enum CodingKeys: String, CodingKey { case items, scope, timeWindow }
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        items = (try? c?.decodeIfPresent([KaiXDiscoverHotItemDTO].self, forKey: .items) ?? nil) ?? []
        scope = (try? c?.decodeIfPresent(String.self, forKey: .scope) ?? nil) ?? "city"
        timeWindow = (try? c?.decodeIfPresent(String.self, forKey: .timeWindow) ?? nil) ?? "24h"
    }
}
