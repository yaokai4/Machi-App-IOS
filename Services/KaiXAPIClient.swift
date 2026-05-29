import Foundation

extension Notification.Name {
    /// Fired when the backend rejects our session with HTTP 401.
    /// `AppState` should observe this and route to the login screen
    /// (and clear local user state). Posted on the main queue so UI
    /// observers can react without dispatch.
    static let kaiXSessionInvalidated = Notification.Name("KaiXSessionInvalidated")
}

/// HTTP client for the unified KaiX backend.
///
/// This is the Swift mirror of `web/app/src/lib/api.ts`. The two clients are
/// intentionally line-for-line equivalent so behaviour (auth, error shapes,
/// pagination, optimistic-updatable payloads) stays identical across iOS and
/// Web.
///
/// Usage:
///
///     let client = KaiXAPIClient.shared
///     let login = try await client.login(handle: userHandle, password: password)
///     let feed  = try await client.feed(mode: .recommend)
///
/// The client is thread-safe (each call builds its own `URLRequest`) and
/// returns Swift-typed DTOs decoded from JSON. The bearer token is read from
/// `KaiXBackend.token` on every request so that login / logout state can be
/// updated from any actor without re-instantiating the client.
final class KaiXAPIClient {
    static let shared = KaiXAPIClient()

    enum FeedMode: String { case recommend, following, hot, local }
    enum CommentSort: String { case top, new }
    enum ProfileSegment: String { case posts, replies, media, likes, bookmarks }
    enum SearchKind: String { case all, post, user, topic }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - low-level

    private func request(_ method: String, _ path: String, body: Encodable? = nil, queryItems: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: KaiXBackend.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KaiXBackend.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if !(200..<300).contains(http.statusCode) {
            // On 401 the session is gone server-side (expired / revoked
            // / rotated). Clear the token now so subsequent calls don't
            // keep replaying a dead bearer, and notify the app so it
            // can route to login. Doing this in one central place
            // avoids the "stuck on a blank screen" symptom that used
            // to happen because RemoteSyncService swallowed every
            // failure.
            if http.statusCode == 401 {
                KaiXBackend.token = nil
                NotificationCenter.default.post(name: .kaiXSessionInvalidated, object: nil)
            }
            if let api = try? JSONDecoder().decode(KaiXAPIError.self, from: data) {
                throw api
            }
            throw KaiXAPIError(error: .init(code: "http_\(http.statusCode)", message: "HTTP \(http.statusCode)"))
        }
        if http.statusCode == 204 { return Data() }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - auth

    @discardableResult
    func login(handle: String, password: String) async throws -> KaiXLoginResponse {
        let body = ["handle": handle, "password": password]
        let data = try await request("POST", "/api/auth/login", body: body)
        let response: KaiXLoginResponse = try decode(data)
        KaiXBackend.token = response.token
        return response
    }

    @discardableResult
    func register(handle: String, displayName: String, password: String, email: String? = nil, region: KaiXRegionDirectory.Region? = nil) async throws -> KaiXLoginResponse {
        var body: [String: String] = ["handle": handle, "display_name": displayName, "password": password]
        if let email { body["email"] = email }
        if let region {
            body["country"] = region.countryCode
            body["province"] = region.provinceCode
            body["city"] = region.cityCode
            body["current_region_code"] = region.regionCode
        }
        let data = try await request("POST", "/api/auth/register", body: body)
        let response: KaiXLoginResponse = try decode(data)
        KaiXBackend.token = response.token
        return response
    }

    func logout() async throws {
        _ = try await request("POST", "/api/auth/logout")
        KaiXBackend.token = nil
    }

    func me() async throws -> KaiXUserDTO {
        struct Wrapper: Codable { let user: KaiXUserDTO }
        let data = try await request("GET", "/api/auth/me")
        return try decode(data) as Wrapper |> \.user
    }

    func updateMe(_ patch: [String: String]) async throws -> KaiXUserDTO {
        struct Wrapper: Codable { let user: KaiXUserDTO }
        let data = try await request("PATCH", "/api/auth/me", body: patch)
        return try decode(data) as Wrapper |> \.user
    }

    func deleteMe() async throws {
        _ = try await request("DELETE", "/api/auth/me")
        KaiXBackend.token = nil
    }

    // MARK: - bootstrap

    func bootstrap() async throws -> KaiXBootstrapResponse {
        let data = try await request("GET", "/api/bootstrap")
        return try decode(data)
    }

    // MARK: - regions

    func countries() async throws -> [KaiXCountryDTO] {
        let data = try await request("GET", "/api/regions/countries")
        let response: KaiXCountriesResponse = try decode(data)
        return response.items
    }

    func provinces(country: String) async throws -> KaiXProvincesResponse {
        let data = try await request("GET", "/api/regions/provinces",
                                     queryItems: [URLQueryItem(name: "country", value: country)])
        return try decode(data)
    }

    func cities(country: String, province: String? = nil) async throws -> KaiXCitiesResponse {
        var q: [URLQueryItem] = [URLQueryItem(name: "country", value: country)]
        if let province, !province.isEmpty { q.append(URLQueryItem(name: "province", value: province)) }
        let data = try await request("GET", "/api/regions/cities", queryItems: q)
        return try decode(data)
    }

    func popularRegions() async throws -> [KaiXRegionDTO] {
        let data = try await request("GET", "/api/regions/popular")
        let response: KaiXPopularRegionsResponse = try decode(data)
        return response.items
    }

    func resolveRegion(code: String) async throws -> KaiXRegionDTO {
        let data = try await request("GET", "/api/regions/resolve",
                                     queryItems: [URLQueryItem(name: "code", value: code)])
        return try decode(data)
    }

    // MARK: - users

    func userDetail(_ id: String) async throws -> KaiXUserDTO {
        struct Wrapper: Codable { let user: KaiXUserDTO }
        let data = try await request("GET", "/api/users/\(id.encodedPathSegment)")
        return try decode(data) as Wrapper |> \.user
    }

    func userPosts(_ id: String, segment: ProfileSegment = .posts, cursor: String? = nil) async throws -> KaiXPageDTO<KaiXPostDTO> {
        var q: [URLQueryItem] = []
        if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
        let data = try await request("GET", "/api/users/\(id.encodedPathSegment)/\(segment.rawValue)", queryItems: q)
        return try decode(data)
    }

    func setFollow(_ id: String, _ on: Bool) async throws {
        _ = try await request(on ? "POST" : "DELETE", "/api/users/\(id.encodedPathSegment)/follow")
    }

    func setBlock(_ id: String, _ on: Bool) async throws {
        _ = try await request(on ? "POST" : "DELETE", "/api/users/\(id.encodedPathSegment)/block")
    }

    func reportUser(_ id: String, reason: String, note: String? = nil) async throws {
        _ = try await request("POST", "/api/users/\(id.encodedPathSegment)/report", body: ["reason": reason, "note": note ?? ""])
    }

    func followers(_ id: String) async throws -> [KaiXUserDTO] {
        struct Wrapper: Codable { let items: [KaiXUserDTO] }
        let data = try await request("GET", "/api/users/\(id.encodedPathSegment)/followers")
        return try decode(data) as Wrapper |> \.items
    }

    func following(_ id: String) async throws -> [KaiXUserDTO] {
        struct Wrapper: Codable { let items: [KaiXUserDTO] }
        let data = try await request("GET", "/api/users/\(id.encodedPathSegment)/following")
        return try decode(data) as Wrapper |> \.items
    }

    // MARK: - feed & posts

    func feed(
        mode: FeedMode = .recommend,
        cursor: String? = nil,
        country: String? = nil,
        province: String? = nil,
        city: String? = nil,
        contentTypes: [ContentType]? = nil
    ) async throws -> KaiXFeedResponse {
        var q: [URLQueryItem] = [URLQueryItem(name: "mode", value: mode.rawValue)]
        if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
        // Region filter — required for .local, optional everywhere else
        // (server falls back to the viewer's saved home region).
        if let country, !country.isEmpty { q.append(URLQueryItem(name: "country", value: country)) }
        if let province, !province.isEmpty { q.append(URLQueryItem(name: "province", value: province)) }
        if let city, !city.isEmpty { q.append(URLQueryItem(name: "city", value: city)) }
        if let contentTypes, !contentTypes.isEmpty {
            q.append(URLQueryItem(name: "content_type", value: contentTypes.map(\.rawValue).joined(separator: ",")))
        }
        let data = try await request("GET", "/api/feed", queryItems: q)
        return try decode(data)
    }

    func createPost(
        content: String,
        mediaIds: [String] = [],
        tags: [String] = [],
        repostOf: String? = nil,
        country: String? = nil,
        province: String? = nil,
        city: String? = nil,
        regionCode: String? = nil,
        contentType: String? = nil,
        attributes: [String: KaiXAttributeValue]? = nil
    ) async throws -> KaiXPostDTO {
        struct Body: Encodable {
            let content: String
            let media_ids: [String]
            let tags: [String]
            let repost_of_id: String?
            let country: String?
            let province: String?
            let city: String?
            let region_code: String?
            let content_type: String?
            let attributes: [String: KaiXAttributeValue]?
        }
        struct Wrapper: Codable { let post: KaiXPostDTO }
        let data = try await request("POST", "/api/posts",
                                     body: Body(content: content,
                                                media_ids: mediaIds,
                                                tags: tags,
                                                repost_of_id: repostOf,
                                                country: country,
                                                province: province,
                                                city: city,
                                                region_code: regionCode,
                                                content_type: contentType,
                                                attributes: attributes))
        return try decode(data) as Wrapper |> \.post
    }

    func post(_ id: String) async throws -> KaiXPostDTO {
        struct Wrapper: Codable { let post: KaiXPostDTO }
        let data = try await request("GET", "/api/posts/\(id.encodedPathSegment)")
        return try decode(data) as Wrapper |> \.post
    }

    func editPost(_ id: String, content: String) async throws -> KaiXPostDTO {
        struct Wrapper: Codable { let post: KaiXPostDTO }
        let data = try await request("PATCH", "/api/posts/\(id.encodedPathSegment)", body: ["content": content])
        return try decode(data) as Wrapper |> \.post
    }

    func deletePost(_ id: String) async throws {
        _ = try await request("DELETE", "/api/posts/\(id.encodedPathSegment)")
    }

    func setLike(_ id: String, _ on: Bool) async throws -> KaiXPostDTO {
        struct Wrapper: Codable { let post: KaiXPostDTO }
        let data = try await request(on ? "POST" : "DELETE", "/api/posts/\(id.encodedPathSegment)/like")
        return try decode(data) as Wrapper |> \.post
    }

    func setBookmark(_ id: String, _ on: Bool) async throws -> KaiXPostDTO {
        struct Wrapper: Codable { let post: KaiXPostDTO }
        let data = try await request(on ? "POST" : "DELETE", "/api/posts/\(id.encodedPathSegment)/bookmark")
        return try decode(data) as Wrapper |> \.post
    }

    func setRepost(_ id: String, _ on: Bool) async throws -> KaiXPostDTO {
        struct Wrapper: Codable { let post: KaiXPostDTO }
        let data = try await request(on ? "POST" : "DELETE", "/api/posts/\(id.encodedPathSegment)/repost")
        return try decode(data) as Wrapper |> \.post
    }

    func quoteRepost(_ id: String, content: String) async throws -> KaiXPostDTO {
        try await createPost(content: content, repostOf: id)
    }

    func viewPost(_ id: String) async throws {
        _ = try await request("POST", "/api/posts/\(id.encodedPathSegment)/view")
    }

    func reportPost(_ id: String, reason: String, note: String? = nil) async throws {
        _ = try await request("POST", "/api/posts/\(id.encodedPathSegment)/report", body: ["reason": reason, "note": note ?? ""])
    }

    // MARK: - comments

    func comments(postId: String, sort: CommentSort = .top) async throws -> [KaiXCommentDTO] {
        struct Wrapper: Codable { let items: [KaiXCommentDTO] }
        let data = try await request("GET", "/api/posts/\(postId.encodedPathSegment)/comments",
                                     queryItems: [URLQueryItem(name: "sort", value: sort.rawValue)])
        return try decode(data) as Wrapper |> \.items
    }

    func createComment(postId: String, content: String, parentId: String? = nil, replyToUserId: String? = nil) async throws -> KaiXCommentDTO {
        struct Body: Encodable { let content: String; let parent_comment_id: String?; let reply_to_user_id: String? }
        struct Wrapper: Codable { let comment: KaiXCommentDTO }
        let data = try await request("POST", "/api/posts/\(postId.encodedPathSegment)/comments",
                                     body: Body(content: content, parent_comment_id: parentId, reply_to_user_id: replyToUserId))
        return try decode(data) as Wrapper |> \.comment
    }

    func deleteComment(_ id: String) async throws {
        _ = try await request("DELETE", "/api/comments/\(id.encodedPathSegment)")
    }

    func setCommentLike(_ id: String, _ on: Bool) async throws {
        _ = try await request(on ? "POST" : "DELETE", "/api/comments/\(id.encodedPathSegment)/like")
    }

    // MARK: - search & topics

    func search(_ q: String, kind: SearchKind = .all) async throws -> KaiXSearchResponse {
        let data = try await request("GET", "/api/search",
                                     queryItems: [URLQueryItem(name: "q", value: q),
                                                  URLQueryItem(name: "kind", value: kind.rawValue)])
        return try decode(data)
    }

    func trending() async throws -> KaiXTrendingResponse {
        let data = try await request("GET", "/api/trending")
        return try decode(data)
    }

    func topic(_ tag: String) async throws -> [KaiXPostDTO] {
        struct Wrapper: Codable { let tag: String; let items: [KaiXPostDTO] }
        let trimmed = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
        let data = try await request("GET", "/api/topics/\(trimmed.encodedPathSegment)")
        return try decode(data) as Wrapper |> \.items
    }

    // MARK: - notifications

    func notifications(kind: String = "all") async throws -> KaiXNotificationsResponse {
        let data = try await request("GET", "/api/notifications",
                                     queryItems: [URLQueryItem(name: "kind", value: kind)])
        return try decode(data)
    }

    func markNotificationsRead(ids: [String]? = nil, all: Bool = false) async throws {
        struct Body: Encodable { let ids: [String]?; let all: Bool }
        _ = try await request("POST", "/api/notifications/read", body: Body(ids: ids, all: all))
    }

    func deleteNotification(_ id: String) async throws {
        _ = try await request("DELETE", "/api/notifications/\(id.encodedPathSegment)")
    }

    // MARK: - conversations & messages

    func conversations() async throws -> [KaiXConversationDTO] {
        struct Wrapper: Codable { let items: [KaiXConversationDTO] }
        let data = try await request("GET", "/api/conversations")
        return try decode(data) as Wrapper |> \.items
    }

    func openConversation(with peerId: String) async throws -> KaiXConversationDTO {
        struct Wrapper: Codable { let conversation: KaiXConversationDTO }
        let data = try await request("POST", "/api/conversations", body: ["peer_id": peerId])
        return try decode(data) as Wrapper |> \.conversation
    }

    func deleteConversation(_ id: String) async throws {
        _ = try await request("DELETE", "/api/conversations/\(id.encodedPathSegment)")
    }

    func messages(_ conversationId: String) async throws -> [KaiXMessageDTO] {
        let data = try await request("GET", "/api/conversations/\(conversationId.encodedPathSegment)/messages")
        let response: KaiXMessagesResponse = try decode(data)
        return response.items
    }

    func sendMessage(_ conversationId: String, content: String, mediaIds: [String] = []) async throws -> KaiXMessageDTO {
        struct Body: Encodable { let content: String; let media_ids: [String] }
        struct Wrapper: Codable { let message: KaiXMessageDTO }
        let data = try await request("POST", "/api/conversations/\(conversationId.encodedPathSegment)/messages",
                                     body: Body(content: content, media_ids: mediaIds))
        return try decode(data) as Wrapper |> \.message
    }

    func deleteMessage(_ id: String) async throws {
        _ = try await request("DELETE", "/api/messages/\(id.encodedPathSegment)")
    }

    func markConversationRead(_ id: String) async throws {
        _ = try await request("POST", "/api/conversations/\(id.encodedPathSegment)/read")
    }

    // MARK: - media (base64 upload for simplicity & parity with Web)

    func uploadMedia(data: Data, mime: String, width: Int = 0, height: Int = 0, duration: Double = 0) async throws -> KaiXMediaDTO {
        struct Body: Encodable {
            let data: String
            let mime: String
            let width: Int
            let height: Int
            let duration: Double
        }
        struct Wrapper: Codable { let media: KaiXMediaDTO }
        let dataURL = "data:\(mime);base64," + data.base64EncodedString()
        let payload = Body(data: dataURL, mime: mime, width: width, height: height, duration: duration)
        let response = try await request("POST", "/api/media/upload", body: payload)
        return try decode(response) as Wrapper |> \.media
    }

    // MARK: - settings

    func settings() async throws -> KaiXSettingsDTO {
        struct Wrapper: Codable { let settings: KaiXSettingsDTO }
        let data = try await request("GET", "/api/settings")
        return try decode(data) as Wrapper |> \.settings
    }

    func updateSettings(_ patch: [String: AnyEncodable]) async throws -> KaiXSettingsDTO {
        struct Wrapper: Codable { let settings: KaiXSettingsDTO }
        let data = try await request("PATCH", "/api/settings", body: patch)
        return try decode(data) as Wrapper |> \.settings
    }
}

// MARK: - tiny encoder helpers

/// `AnyEncodable` lets us forward heterogeneous dictionaries (`[String: Any]`)
/// to JSONEncoder without forcing the caller to declare a full struct.
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        self._encode = value.encode
    }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

// Tiny pipe operator. Reads as "decoded value, get this key".
infix operator |>: AdditionPrecedence
@inlinable func |> <Root, Value>(value: Root, kp: KeyPath<Root, Value>) -> Value {
    value[keyPath: kp]
}

private extension String {
    /// Percent-encode for safe inclusion as a URL path segment.
    var encodedPathSegment: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
