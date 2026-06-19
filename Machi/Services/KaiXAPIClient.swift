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

    private func request(
        _ method: String,
        _ path: String,
        body: Encodable? = nil,
        queryItems: [URLQueryItem] = [],
        idempotencyKey: String? = nil
    ) async throws -> Data {
        var components = URLComponents(url: KaiXBackend.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        // JSON API calls are small; cap the wait at 25s (vs the 60s default)
        // so a stalled mobile connection surfaces a retry/error quickly
        // instead of spinning for a full minute. Matches the Web client's
        // 20s budget. File uploads use a separate path and are unaffected.
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KaiXBackend.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey, !idempotencyKey.isEmpty {
            req.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        // Transient failures (mobile networks drop, gateways recycle) get a
        // couple of jittered retries — but ONLY for requests safe to replay:
        // idempotent verbs, or anything carrying an Idempotency-Key so the
        // server dedupes. Non-idempotent POSTs are never auto-retried, to
        // avoid double-creating posts / messages / likes.
        let isReplaySafe = ["GET", "HEAD", "DELETE", "PUT"].contains(method)
            || (idempotencyKey?.isEmpty == false)
        let maxAttempts = isReplaySafe ? 4 : 1
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if (200..<300).contains(http.statusCode) {
                    return http.statusCode == 204 ? Data() : data
                }
                // On 401 the session is gone server-side (expired / revoked
                // / rotated). Clear the token now so subsequent calls don't
                // keep replaying a dead bearer, and notify the app so it can
                // route to login. Centralizing this avoids the "stuck on a
                // blank screen" symptom. Never retried.
                if http.statusCode == 401 {
                    KaiXBackend.token = nil
                    NotificationCenter.default.post(name: .kaiXSessionInvalidated, object: nil)
                }
                if http.statusCode == 429,
                   let api = try? JSONDecoder().decode(KaiXAPIError.self, from: data),
                   api.error.code != "rate_limited" {
                    throw api
                }
                // 429/502/503/504 are transient for replay-safe calls. Upload
                // presign/complete carries Idempotency-Key, so backing off here
                // prevents a 9-image publish from failing just because the
                // production upload bucket refills between requests.
                if isReplaySafe, attempt < maxAttempts, Self.isRetryableHTTPStatus(http.statusCode) {
                    try? await Task.sleep(nanoseconds: Self.retryBackoff(attempt, response: http))
                    continue
                }
                if let api = try? JSONDecoder().decode(KaiXAPIError.self, from: data) {
                    throw api
                }
                throw KaiXAPIError(error: .init(code: "http_\(http.statusCode)", message: "HTTP \(http.statusCode)"))
            } catch let urlError as URLError where isReplaySafe
                && attempt < maxAttempts
                && Self.isRetryableURLError(urlError) {
                try? await Task.sleep(nanoseconds: Self.retryBackoff(attempt))
                continue
            }
        }
    }

    private static func isRetryableHTTPStatus(_ status: Int) -> Bool {
        status == 429 || [502, 503, 504].contains(status)
    }

    /// Network-layer errors worth a retry: transient connectivity blips, not
    /// hard "you're offline" or "request cancelled" states.
    private static func isRetryableURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .dnsLookupFailed, .cannotFindHost:
            return true
        default:
            return false
        }
    }

    /// ~0.4s then ~0.8s, with ±25% jitter so a fleet doesn't retry in lockstep.
    private static func retryBackoff(_ attempt: Int, response: HTTPURLResponse? = nil) -> UInt64 {
        if let retryAfter = response?.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(retryAfter.trimmingCharacters(in: .whitespaces)),
           seconds > 0 {
            return UInt64(min(seconds, 30) * 1_000_000_000)
        }
        let base = 0.4 * pow(2.0, Double(attempt - 1))
        let jitter = Double.random(in: 0.75...1.25)
        return UInt64(base * jitter * 1_000_000_000)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - auth

    /// Fetch an image-captcha challenge for `scene` ("login" / "register").
    func fetchCaptcha(scene: String) async throws -> KaiXCaptchaResponse {
        let data = try await request("POST", "/api/auth/captcha", body: ["scene": scene])
        return try decode(data)
    }

    @discardableResult
    func login(handle: String, password: String, captchaId: String? = nil, captchaCode: String? = nil) async throws -> KaiXLoginResponse {
        var body = ["handle": handle, "password": password]
        if let captchaId, !captchaId.isEmpty {
            body["captcha_id"] = captchaId
            body["captcha_code"] = captchaCode ?? ""
        }
        let data = try await request("POST", "/api/auth/login", body: body)
        let response: KaiXLoginResponse = try decode(data)
        KaiXBackend.token = response.token
        return response
    }

    @discardableResult
    func register(handle: String, displayName: String, password: String, email: String? = nil, code: String? = nil, region: KaiXRegionDirectory.Region? = nil, appLanguage: AppLanguage? = nil) async throws -> KaiXLoginResponse {
        var body: [String: String] = ["handle": handle, "display_name": displayName, "password": password]
        if let email { body["email"] = email }
        if let code, !code.isEmpty { body["code"] = code }
        if let appLanguage {
            body["language"] = appLanguage == .zh ? "zh-Hans" : appLanguage.rawValue
        }
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

    /// Native Sign in with Apple: post the identity token (the trust anchor)
    /// plus the raw nonce; the server verifies it and returns the same
    /// {token, user} session shape as password login.
    @discardableResult
    func appleSignIn(identityToken: String, nonce: String, fullName: String? = nil, email: String? = nil) async throws -> KaiXLoginResponse {
        var body = ["identity_token": identityToken, "nonce": nonce]
        if let fullName, !fullName.isEmpty { body["full_name"] = fullName }
        if let email, !email.isEmpty { body["email"] = email }
        let data = try await request("POST", "/api/auth/apple", body: body)
        let response: KaiXLoginResponse = try decode(data)
        KaiXBackend.token = response.token
        return response
    }

    func googleAuthStart(redirect: String = "machi://auth/google", intent: String = "login") async throws -> KaiXGoogleAuthStartResponse {
        let data = try await request("GET", "/api/auth/google/start", queryItems: [
            URLQueryItem(name: "client", value: "ios"),
            URLQueryItem(name: "intent", value: intent),
            URLQueryItem(name: "redirect", value: redirect),
        ])
        return try decode(data)
    }

    /// Unbind Google from the current (logged-in) account; returns the refreshed user.
    @discardableResult
    func googleUnlink() async throws -> KaiXUserDTO {
        struct Wrapper: Codable { let user: KaiXUserDTO }
        let data = try await request("POST", "/api/auth/google/unlink")
        return try decode(data) as Wrapper |> \.user
    }

    func checkUsername(_ username: String) async throws -> KaiXAvailabilityResponse {
        let data = try await request("GET", "/api/auth/check-username",
                                     queryItems: [URLQueryItem(name: "username", value: username)])
        return try decode(data)
    }

    func checkEmail(_ email: String) async throws -> KaiXAvailabilityResponse {
        let data = try await request("GET", "/api/auth/check-email",
                                     queryItems: [URLQueryItem(name: "email", value: email)])
        return try decode(data)
    }

    func sendVerificationCode(email: String, purpose: String = "register", captchaId: String? = nil, captchaCode: String? = nil) async throws -> KaiXEmailCodeResponse {
        var body = ["email": email, "purpose": purpose]
        if let captchaId, !captchaId.isEmpty {
            body["captcha_id"] = captchaId
            body["captcha_code"] = captchaCode ?? ""
        }
        let data = try await request("POST", "/api/auth/send-verification-code", body: body)
        return try decode(data)
    }

    func sendSecurityCode(purpose: String, email: String? = nil) async throws -> KaiXEmailCodeResponse {
        var body = ["purpose": purpose]
        if let email, !email.isEmpty {
            body["email"] = email
            body["new_email"] = email
        }
        let data = try await request("POST", "/api/auth/send-verification-code", body: body)
        return try decode(data)
    }

    func verifyEmailCode(email: String, code: String, purpose: String = "register") async throws -> KaiXVerifyCodeResponse {
        let data = try await request("POST", "/api/auth/verify-code",
                                     body: ["email": email, "code": code, "purpose": purpose])
        return try decode(data)
    }

    func changePassword(oldPassword: String, newPassword: String) async throws {
        _ = try await request("POST", "/api/auth/change-password",
                              body: ["old_password": oldPassword, "new_password": newPassword])
    }

    func verifyPassword(_ password: String) async throws {
        _ = try await request("POST", "/api/account/verify-password", body: ["password": password])
    }

    func changePassword(currentPassword: String? = nil,
                        code: String? = nil,
                        challengeId: String? = nil,
                        newPassword: String) async throws {
        var body = ["new_password": newPassword]
        if let currentPassword, !currentPassword.isEmpty {
            body["current_password"] = currentPassword
        }
        if let code, !code.isEmpty {
            body["code"] = code
        }
        if let challengeId, !challengeId.isEmpty {
            body["challenge_id"] = challengeId
        }
        _ = try await request("POST", "/api/account/change-password", body: body)
    }

    func changeEmail(currentPassword: String? = nil,
                     oldCode: String? = nil,
                     oldChallengeId: String? = nil,
                     newEmail: String,
                     newCode: String,
                     newChallengeId: String? = nil) async throws -> KaiXUserDTO {
        struct Wrapper: Codable { let user: KaiXUserDTO }
        var body: [String: String] = [
            "new_email": newEmail,
            "new_code": newCode,
        ]
        if let currentPassword, !currentPassword.isEmpty {
            body["current_password"] = currentPassword
        }
        if let oldCode, !oldCode.isEmpty {
            body["old_code"] = oldCode
        }
        if let oldChallengeId, !oldChallengeId.isEmpty {
            body["old_challenge_id"] = oldChallengeId
        }
        if let newChallengeId, !newChallengeId.isEmpty {
            body["new_challenge_id"] = newChallengeId
        }
        let data = try await request("POST", "/api/account/change-email", body: body)
        return try decode(data) as Wrapper |> \.user
    }

    func updateRegionLanguage(_ patch: [String: String]) async throws -> KaiXUserDTO {
        struct Wrapper: Codable { let user: KaiXUserDTO }
        let data = try await request("PATCH", "/api/account/region-language", body: patch)
        return try decode(data) as Wrapper |> \.user
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

    // MARK: - membership + payments

    /// Current user's authoritative membership status + the plan.
    func membershipMe() async throws -> KaiXMembershipMeResponse {
        let data = try await request("GET", "/api/membership/me")
        return try decode(data)
    }

    /// Public plan info (price + names + Apple product id).
    func membershipPlan() async throws -> KaiXMembershipPlanResponse {
        let data = try await request("GET", "/api/membership/plan")
        return try decode(data)
    }

    func membershipBenefits() async throws -> KaiXMembershipBenefitsResponse {
        let data = try await request("GET", "/api/membership/benefits")
        return try decode(data)
    }

    /// Member-only basic analytics over the caller's own posts.
    func membershipInsights() async throws -> KaiXMembershipInsightsResponse {
        let data = try await request("GET", "/api/membership/insights")
        return try decode(data)
    }

    /// Verify a StoreKit2 transaction server-side. The server is the only
    /// place a purchase is trusted; it opens/extends membership and is
    /// idempotent on the transaction id (safe to call on restore).
    @discardableResult
    func verifyAppleTransaction(productId: String,
                               transactionId: String,
                               originalTransactionId: String,
                               signedTransaction: String,
                               environment: String) async throws -> KaiXAppleVerifyResponse {
        let body: [String: String] = [
            "productId": productId,
            "transactionId": transactionId,
            "originalTransactionId": originalTransactionId,
            "signedTransaction": signedTransaction,
            "environment": environment,
        ]
        let data = try await request("POST", "/api/payments/apple/verify", body: body)
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

    /// `/api/users/:id/replies` is shared with Web and returns comment rows
    /// with a nested `post`. The iOS profile wants the replied-to posts, so
    /// decode that shape explicitly. The decoder also accepts a direct post
    /// item to stay compatible if the server later normalizes the endpoint.
    func userReplyPosts(_ id: String, cursor: String? = nil) async throws -> KaiXPageDTO<KaiXPostDTO> {
        struct ReplyItem: Codable {
            let post: KaiXPostDTO?

            enum CodingKeys: String, CodingKey {
                case post
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if container.contains(.post) {
                    post = try container.decodeIfPresent(KaiXPostDTO.self, forKey: .post)
                } else {
                    post = try? KaiXPostDTO(from: decoder)
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfPresent(post, forKey: .post)
            }
        }

        struct ReplyPage: Codable {
            let items: [ReplyItem]
            let next_cursor: String?
        }

        var q: [URLQueryItem] = []
        if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
        let data = try await request("GET", "/api/users/\(id.encodedPathSegment)/replies", queryItems: q)
        let page: ReplyPage = try decode(data)
        return KaiXPageDTO(items: page.items.compactMap(\.post), next_cursor: page.next_cursor)
    }

    func setFollow(_ id: String, _ on: Bool) async throws {
        _ = try await request(on ? "POST" : "DELETE", "/api/users/\(id.encodedPathSegment)/follow")
    }

    func setBlock(_ id: String, _ on: Bool) async throws {
        _ = try await request(on ? "POST" : "DELETE", "/api/users/\(id.encodedPathSegment)/block")
    }

    /// Server-side list of users the current account has blocked. Mirrors
    /// web `api.blocks()` (GET /api/blocks); unblock reuses `setBlock`.
    func blockedUsers() async throws -> [KaiXUserDTO] {
        struct Wrapper: Codable { let items: [KaiXUserDTO] }
        let data = try await request("GET", "/api/blocks")
        let wrapper: Wrapper = try decode(data)
        return wrapper.items
    }

    /// Active login devices / sessions. Mirrors web `api.devices()`.
    func loginDevices() async throws -> [KaiXDeviceDTO] {
        struct Wrapper: Codable { let items: [KaiXDeviceDTO] }
        let data = try await request("GET", "/api/devices")
        let wrapper: Wrapper = try decode(data)
        return wrapper.items
    }

    /// Revoke a login device / session. Mirrors web `api.revokeDevice()`.
    func revokeDevice(_ id: String) async throws {
        _ = try await request("DELETE", "/api/devices/\(id.encodedPathSegment)")
    }

    func reportUser(_ id: String, reason: String, note: String? = nil) async throws {
        _ = try await request("POST", "/api/users/\(id.encodedPathSegment)/report", body: ["reason": reason, "note": note ?? ""])
    }

    func user(_ id: String) async throws -> KaiXUserDTO {
        struct Wrapper: Codable { let user: KaiXUserDTO }
        let data = try await request("GET", "/api/users/\(id.encodedPathSegment)")
        return try decode(data) as Wrapper |> \.user
    }

    /// Submit in-app feedback. Mirrors web `POST /api/feedback`; requires auth.
    func submitFeedback(category: String = "general", content: String) async throws {
        _ = try await request("POST", "/api/feedback", body: ["category": category, "content": content])
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
        regionCode: String? = nil,
        country: String? = nil,
        province: String? = nil,
        city: String? = nil,
        contentTypes: [ContentType]? = nil
    ) async throws -> KaiXFeedResponse {
        var q: [URLQueryItem] = [URLQueryItem(name: "mode", value: mode.rawValue)]
        if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
        // Region filter — required for .local, optional everywhere else
        // (server falls back to the viewer's saved home region).
        if let regionCode, !regionCode.isEmpty { q.append(URLQueryItem(name: "region_code", value: regionCode)) }
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
                                                attributes: attributes),
                                     idempotencyKey: "post-create-\(UUID().uuidString)")
        return try decode(data) as Wrapper |> \.post
    }

    func post(_ id: String) async throws -> KaiXPostDTO {
        struct Wrapper: Codable { let post: KaiXPostDTO }
        let data = try await request("GET", "/api/posts/\(id.encodedPathSegment)")
        return try decode(data) as Wrapper |> \.post
    }

    // MARK: - structured city listings

    /// One server page of listings plus the cursor for the next one — the
    /// same keyset protocol the Web client uses, so marketplace channels
    /// scroll through the full inventory instead of the first 24 rows.
    struct ListingsPage {
        let items: [KaiXCityListingDTO]
        let nextCursor: String?
    }

    func listingsPage(
        type: String,
        citySlug: String? = nil,
        regionCode: String? = nil,
        regionCodes: [String] = [],
        countryCode: String? = nil,
        query: String? = nil,
        category: String? = nil,
        categories: [String] = [],
        minPrice: Double? = nil,
        maxPrice: Double? = nil,
        sort: String? = nil,
        attributes: [String: String] = [:],
        sellerId: String? = nil,
        excludeListingId: String? = nil,
        cursor: String? = nil,
        limit: Int? = nil
    ) async throws -> ListingsPage {
        var q: [URLQueryItem] = [
            URLQueryItem(name: "type", value: type),
        ]
        if let citySlug, !citySlug.isEmpty { q.append(URLQueryItem(name: "city_slug", value: citySlug)) }
        if let regionCode, !regionCode.isEmpty { q.append(URLQueryItem(name: "region_code", value: regionCode)) }
        if !regionCodes.isEmpty { q.append(URLQueryItem(name: "region_codes", value: regionCodes.joined(separator: ","))) }
        if let countryCode, !countryCode.isEmpty { q.append(URLQueryItem(name: "country_code", value: countryCode)) }
        if let query, !query.isEmpty { q.append(URLQueryItem(name: "q", value: query)) }
        if let category, !category.isEmpty { q.append(URLQueryItem(name: "category", value: category)) }
        if !categories.isEmpty { q.append(URLQueryItem(name: "categories", value: categories.joined(separator: ","))) }
        if let minPrice { q.append(URLQueryItem(name: "min_price", value: String(minPrice))) }
        if let maxPrice { q.append(URLQueryItem(name: "max_price", value: String(maxPrice))) }
        if let sort, !sort.isEmpty { q.append(URLQueryItem(name: "sort", value: sort)) }
        // 属性级服务端筛选（attr_condition=like_new / attr_gte_max_guests=4）,
        // 与 Web 同一套参数,翻页不漏结果。
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) where !key.isEmpty && !value.isEmpty {
            q.append(URLQueryItem(name: "attr_\(key)", value: value))
        }
        if let sellerId, !sellerId.isEmpty { q.append(URLQueryItem(name: "seller_id", value: sellerId)) }
        if let excludeListingId, !excludeListingId.isEmpty { q.append(URLQueryItem(name: "exclude", value: excludeListingId)) }
        if let cursor, !cursor.isEmpty { q.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let limit { q.append(URLQueryItem(name: "limit", value: String(limit))) }
        let data = try await request("GET", "/api/listings", queryItems: q)
        let response: KaiXListingsResponse = try decode(data)
        return ListingsPage(items: response.items, nextCursor: response.next_cursor)
    }

    /// 详情页相似推荐：服务端按同类目同城→同国→同城逐层补足,不含同卖家。
    func similarListings(_ id: String, limit: Int = 8) async throws -> [KaiXCityListingDTO] {
        struct Wrapper: Decodable { let items: [KaiXCityListingDTO] }
        let data = try await request(
            "GET",
            "/api/listings/\(id.encodedPathSegment)/similar",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
        let response: Wrapper = try decode(data)
        return response.items
    }

    func listings(
        type: String,
        citySlug: String? = nil,
        regionCode: String? = nil,
        regionCodes: [String] = [],
        countryCode: String? = nil,
        query: String? = nil
    ) async throws -> [KaiXCityListingDTO] {
        try await listingsPage(
            type: type,
            citySlug: citySlug,
            regionCode: regionCode,
            regionCodes: regionCodes,
            countryCode: countryCode,
            query: query
        ).items
    }

    /// Bind this device's APNs token to the logged-in account so pushes
    /// reach the user even when the app is killed.
    func registerPushToken(_ token: String, platform: String = "ios") async throws {
        struct Body: Encodable { let token: String; let platform: String }
        _ = try await request("POST", "/api/devices/push-token", body: Body(token: token, platform: platform))
    }

    /// Unbind a device token (logout). Works without a bearer by design —
    /// logout clears the token before this call lands.
    func unregisterPushToken(_ token: String) async throws {
        struct Body: Encodable { let token: String }
        _ = try await request("DELETE", "/api/devices/push-token", body: Body(token: token))
    }

    /// Buyer↔seller contacts about my listings (role=received) or ones I
    /// sent (role=sent). Mirrors the Web workbench inquiries screen.
    func myListingInquiries(role: String) async throws -> [KaiXListingInquiryDTO] {
        struct Response: Decodable { let items: [KaiXListingInquiryDTO] }
        let data = try await request("GET", "/api/my/listing-inquiries", queryItems: [URLQueryItem(name: "role", value: role)])
        let response: Response = try decode(data)
        return response.items
    }

    func businessProfile() async throws -> KaiXBusinessProfileResponse {
        let data = try await request("GET", "/api/business/profile")
        return try decode(data)
    }

    func saveBusinessApplication(_ application: KaiXBusinessApplicationPayload) async throws -> KaiXBusinessSaveResponse {
        let data = try await request(
            "POST",
            "/api/business/application",
            body: application,
            idempotencyKey: "business-application-\(UUID().uuidString)"
        )
        return try decode(data)
    }

    func deleteBusinessDocument(_ documentId: String) async throws -> KaiXBusinessSaveResponse {
        let data = try await request("DELETE", "/api/business/documents/\(documentId.encodedPathSegment)")
        return try decode(data)
    }

    func businessDashboard() async throws -> KaiXBusinessDashboardDTO {
        let data = try await request("GET", "/api/business/dashboard")
        return try decode(data)
    }

    /// My membership payment orders, newest first.
    func membershipOrders() async throws -> [KaiXPaymentOrderDTO] {
        struct Response: Decodable { let items: [KaiXPaymentOrderDTO] }
        let data = try await request("GET", "/api/membership/orders")
        let response: Response = try decode(data)
        return response.items
    }

    /// One server page of the caller's OWN listings of one type, regardless
    /// of city — includes non-published states so sellers can manage
    /// everything they posted.
    func myListingsPage(type: String, cursor: String? = nil, limit: Int = 60) async throws -> ListingsPage {
        var q: [URLQueryItem] = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "mine", value: "1"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let cursor, !cursor.isEmpty {
            q.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let data = try await request("GET", "/api/listings", queryItems: q)
        let response: KaiXListingsResponse = try decode(data)
        return ListingsPage(items: response.items, nextCursor: response.next_cursor)
    }

    /// The caller's complete listing inventory for one type. Keep this
    /// method exhaustive so management screens do not silently show only the
    /// first page once a seller has many active/draft/reviewing listings.
    func myListings(type: String) async throws -> [KaiXCityListingDTO] {
        try await collectListings { cursor in
            try await myListingsPage(type: type, cursor: cursor)
        }
    }

    /// A seller-scoped public inventory used by profile count tags. It walks
    /// the same cursor protocol as marketplace channels so profile shortcuts
    /// never produce a "missing after 50 rows" false empty state.
    func sellerListings(type: String, sellerId: String, limit: Int = 60) async throws -> [KaiXCityListingDTO] {
        try await collectListings { cursor in
            try await listingsPage(type: type, sellerId: sellerId, cursor: cursor, limit: limit)
        }
    }

    private func collectListings(_ pageLoader: (String?) async throws -> ListingsPage) async throws -> [KaiXCityListingDTO] {
        var cursor: String?
        var allItems: [KaiXCityListingDTO] = []
        var seen = Set<String>()
        var pageCount = 0
        repeat {
            let page = try await pageLoader(cursor)
            for item in page.items where seen.insert(item.id).inserted {
                allItems.append(item)
            }
            cursor = page.nextCursor
            pageCount += 1
        } while cursor != nil && pageCount < 20
        return allItems
    }

    func cityListing(_ id: String) async throws -> KaiXCityListingDTO {
        let data = try await request("GET", "/api/listings/\(id.encodedPathSegment)")
        let response: KaiXListingDetailResponse = try decode(data)
        return response.listing
    }

    func createListing(
        type: String,
        countryCode: String = "jp",
        citySlug: String,
        regionCode: String,
        language: String = "zh-CN",
        title: String,
        description: String,
        category: String,
        price: Double?,
        locationText: String,
        mediaIds: [String] = [],
        attributes: [String: KaiXAttributeValue] = [:]
    ) async throws -> KaiXCityListingDTO {
        struct Body: Encodable {
            let type: String
            let country_code: String
            let city_slug: String
            let region_code: String
            let language: String
            let title: String
            let description: String
            let category: String
            let price: Double?
            let currency: String
            let price_type: String
            let location_text: String
            let contact_method: String
            let media_ids: [String]
            let attributes: [String: KaiXAttributeValue]
        }
        struct Wrapper: Codable { let listing: KaiXCityListingDTO }
        let priceType: String = {
            if type == "rental" { return "monthly" }
            if type == "job" || type == "hiring" { return "hourly" }
            if type == "local_service" { return "starting_from" }
            if type == "discount" { return "discount" }
            return "fixed"
        }()
        let data = try await request("POST", "/api/listings", body: Body(
            type: type,
            country_code: countryCode,
            city_slug: citySlug,
            region_code: regionCode,
            language: language,
            title: title,
            description: description,
            category: category,
            price: price,
            currency: "JPY",
            price_type: priceType,
            location_text: locationText,
            contact_method: "app_message",
            media_ids: mediaIds,
            attributes: attributes
        ), idempotencyKey: "listing-create-\(UUID().uuidString)")
        return try decode(data) as Wrapper |> \.listing
    }

    func updateListing(
        _ id: String,
        title: String,
        description: String,
        category: String,
        price: Double?,
        locationText: String,
        mediaIds: [String],
        attributes: [String: KaiXAttributeValue]
    ) async throws -> KaiXCityListingDTO {
        struct Body: Encodable {
            let title: String
            let description: String
            let category: String
            let price: Double?
            let location_text: String
            let media_ids: [String]
            let attributes: [String: KaiXAttributeValue]
        }
        struct Wrapper: Decodable { let listing: KaiXCityListingDTO }
        let data = try await request(
            "PATCH",
            "/api/listings/\(id.encodedPathSegment)",
            body: Body(
                title: title,
                description: description,
                category: category,
                price: price,
                location_text: locationText,
                media_ids: mediaIds,
                attributes: attributes
            )
        )
        let response: Wrapper = try decode(data)
        return response.listing
    }

    func updateListingStatus(_ id: String, status: String) async throws -> KaiXCityListingDTO {
        struct Body: Encodable { let status: String }
        struct Wrapper: Decodable { let listing: KaiXCityListingDTO }
        let data = try await request(
            "PATCH",
            "/api/listings/\(id.encodedPathSegment)",
            body: Body(status: status)
        )
        let response: Wrapper = try decode(data)
        return response.listing
    }

    func deleteListing(_ id: String) async throws {
        _ = try await request("DELETE", "/api/listings/\(id.encodedPathSegment)")
    }

    func favoriteListing(_ id: String, on: Bool) async throws {
        _ = try await request(on ? "POST" : "DELETE", "/api/listings/\(id.encodedPathSegment)/favorite")
    }

    func reportListing(_ id: String, reason: String = "suspicious", note: String = "") async throws {
        _ = try await request("POST", "/api/listings/\(id.encodedPathSegment)/report", body: ["reason": reason, "note": note])
    }

    /// Contacting a listing creates a structured inquiry/booking/application
    /// record and also opens (or reuses) a DM thread for follow-up.
    @discardableResult
    func contactListing(_ id: String, message: String, details: [[String: String]] = [], locale: String? = nil) async throws -> KaiXListingInquiryReceiptDTO {
        struct InquiryBody: Encodable {
            let message: String
            let details: [[String: String]]
            let source_platform: String
            let locale: String?
        }
        let data = try await request(
            "POST",
            "/api/listings/\(id.encodedPathSegment)/inquiry",
            body: InquiryBody(message: message, details: details, source_platform: "ios", locale: locale),
            idempotencyKey: "listing-inquiry-\(UUID().uuidString)"
        )
        struct InquiryResponse: Decodable {
            let conversation_id: String?
            let conversationId: String?
            let inquiry_id: String?
            let inquiryId: String?
            let type: String?
            let status: String?
            let details: [[String: String]]?
            let success_title: String?
            let successTitle: String?
            let data: Nested?

            struct Nested: Decodable {
                let conversation_id: String?
                let conversationId: String?
                let inquiry_id: String?
                let inquiryId: String?
                let type: String?
                let status: String?
                let details: [[String: String]]?
                let success_title: String?
                let successTitle: String?
            }
        }
        let resp: InquiryResponse = try decode(data)
        return KaiXListingInquiryReceiptDTO(
            conversation_id: resp.conversation_id ?? resp.data?.conversation_id,
            conversationId: resp.conversationId ?? resp.data?.conversationId,
            inquiry_id: resp.inquiry_id ?? resp.data?.inquiry_id,
            inquiryId: resp.inquiryId ?? resp.data?.inquiryId,
            type: resp.type ?? resp.data?.type,
            status: resp.status ?? resp.data?.status,
            details: resp.details ?? resp.data?.details,
            success_title: resp.success_title ?? resp.data?.success_title,
            successTitle: resp.successTitle ?? resp.data?.successTitle
        )
    }

    @discardableResult
    func updateListingInquiry(_ id: String, status: String) async throws -> KaiXListingInquiryDTO {
        struct Body: Encodable { let status: String }
        struct Response: Decodable { let inquiry: KaiXListingInquiryDTO }
        let data = try await request(
            "PATCH",
            "/api/listing-inquiries/\(id.encodedPathSegment)",
            body: Body(status: status)
        )
        let response: Response = try decode(data)
        return response.inquiry
    }

    // MARK: - Listing reviews（星级点评）+ 认证商家目录

    func listingReviews(_ listingId: String) async throws -> KaiXListingReviewsResponse {
        let data = try await request("GET", "/api/listings/\(listingId.encodedPathSegment)/reviews")
        return try decode(data)
    }

    @discardableResult
    func submitListingReview(_ listingId: String, rating: Int, content: String, visitDate: String = "") async throws -> KaiXSubmitReviewResponse {
        struct Body: Encodable { let rating: Int; let content: String; let visit_date: String }
        let data = try await request(
            "POST",
            "/api/listings/\(listingId.encodedPathSegment)/reviews",
            body: Body(rating: rating, content: content, visit_date: visitDate),
            idempotencyKey: "listing-review-\(listingId)-\(UUID().uuidString)"
        )
        return try decode(data)
    }

    func deleteListingReview(_ listingId: String, reviewId: String) async throws {
        _ = try await request("DELETE", "/api/listings/\(listingId.encodedPathSegment)/reviews/\(reviewId.encodedPathSegment)")
    }

    @discardableResult
    func replyListingReview(_ listingId: String, reviewId: String, content: String) async throws -> KaiXListingReviewDTO? {
        struct Body: Encodable { let content: String }
        let data = try await request(
            "POST",
            "/api/listings/\(listingId.encodedPathSegment)/reviews/\(reviewId.encodedPathSegment)/reply",
            body: Body(content: content)
        )
        struct Wrapper: Decodable { let review: KaiXListingReviewDTO? }
        return (try? decode(data) as Wrapper)?.review
    }

    func myBusinessReviews() async throws -> KaiXMyBusinessReviewsResponse {
        let data = try await request("GET", "/api/my/business/reviews")
        return try decode(data)
    }

    func businessesDirectory(city: String? = nil, category: String? = nil, query: String? = nil) async throws -> KaiXBusinessDirectoryResponse {
        var items: [URLQueryItem] = []
        if let city, !city.isEmpty { items.append(URLQueryItem(name: "city", value: city)) }
        if let category, !category.isEmpty, category != "全部" { items.append(URLQueryItem(name: "category", value: category)) }
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        let data = try await request("GET", "/api/businesses/directory", queryItems: items)
        return try decode(data)
    }

    func businessPublic(_ businessId: String) async throws -> KaiXBusinessPublicResponse {
        let data = try await request("GET", "/api/businesses/\(businessId.encodedPathSegment)/public")
        return try decode(data)
    }

    // MARK: - Machi Guide / 日本指南

    func guideHome(country: String = "jp", language: String = "zh-CN") async throws -> KaiXGuideHomeResponse {
        let data = try await request("GET", "/api/guide/home", queryItems: [
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "language", value: language),
        ])
        return try decode(data)
    }

    func guideCategories(country: String = "jp") async throws -> KaiXGuideCategoriesResponse {
        let data = try await request("GET", "/api/guide/categories", queryItems: [
            URLQueryItem(name: "country", value: country),
        ])
        return try decode(data)
    }

    func guideArticles(
        country: String = "jp",
        city: String? = nil,
        language: String? = nil,
        categoryKey: String? = nil,
        subCategoryKey: String? = nil,
        contentType: String? = nil,
        keyword: String? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> KaiXGuideListResponse<KaiXGuideArticleDTO> {
        let data = try await request("GET", "/api/guide/articles", queryItems: guideQuery(
            country: country,
            city: city,
            language: language,
            categoryKey: categoryKey,
            subCategoryKey: subCategoryKey,
            contentType: contentType,
            keyword: keyword,
            page: page,
            pageSize: pageSize
        ))
        return try decode(data)
    }

    func guideArticle(_ idOrSlug: String, country: String = "jp") async throws -> KaiXGuideArticleDetailResponse {
        let data = try await request("GET", "/api/guide/articles/\(idOrSlug.encodedPathSegment)", queryItems: [
            URLQueryItem(name: "country", value: country),
        ])
        return try decode(data)
    }

    func guideProducts(
        country: String = "jp",
        categoryKey: String? = nil,
        subCategoryKey: String? = nil,
        productType: String? = nil,
        priceType: String? = nil,
        keyword: String? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> KaiXGuideListResponse<KaiXGuideProductDTO> {
        let data = try await request("GET", "/api/guide/products", queryItems: guideQuery(
            country: country,
            categoryKey: categoryKey,
            subCategoryKey: subCategoryKey,
            productType: productType,
            priceType: priceType,
            keyword: keyword,
            page: page,
            pageSize: pageSize
        ))
        return try decode(data)
    }

    func guideMemberResources(
        country: String = "jp",
        categoryKey: String? = nil,
        keyword: String? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> KaiXGuideListResponse<KaiXGuideProductDTO> {
        let data = try await request("GET", "/api/guide/member-resources", queryItems: guideQuery(
            country: country,
            categoryKey: categoryKey,
            keyword: keyword,
            page: page,
            pageSize: pageSize
        ))
        return try decode(data)
    }

    func guideProduct(_ idOrSlug: String, country: String = "jp") async throws -> KaiXGuideProductDetailResponse {
        let data = try await request("GET", "/api/guide/products/\(idOrSlug.encodedPathSegment)", queryItems: [
            URLQueryItem(name: "country", value: country),
        ])
        return try decode(data)
    }

    func guideSchools(
        country: String = "jp",
        regionGroup: String? = nil,
        prefecture: String? = nil,
        city: String? = nil,
        schoolType: String? = nil,
        field: String? = nil,
        acceptsInternationalStudents: Bool? = nil,
        hasEnglishProgram: Bool? = nil,
        hasJapaneseProgram: Bool? = nil,
        hasScholarship: Bool? = nil,
        hasDormitory: Bool? = nil,
        hasCareerSupport: Bool? = nil,
        hasLanguageSupport: Bool? = nil,
        jlptLevel: String? = nil,
        ejuRequired: Bool? = nil,
        toeflRequired: String? = nil,
        ieltsRequired: String? = nil,
        admissionMonth: String? = nil,
        tuitionMin: Int? = nil,
        tuitionMax: Int? = nil,
        keyword: String? = nil,
        sort: String? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> KaiXGuideListResponse<KaiXGuideSchoolDTO> {
        let data = try await request("GET", "/api/guide/schools", queryItems: guideQuery(
            country: country,
            regionGroup: regionGroup,
            prefecture: prefecture,
            city: city,
            schoolType: schoolType,
            field: field,
            acceptsInternationalStudents: acceptsInternationalStudents,
            hasEnglishProgram: hasEnglishProgram,
            hasJapaneseProgram: hasJapaneseProgram,
            hasScholarship: hasScholarship,
            hasDormitory: hasDormitory,
            hasCareerSupport: hasCareerSupport,
            hasLanguageSupport: hasLanguageSupport,
            jlptLevel: jlptLevel,
            ejuRequired: ejuRequired,
            toeflRequired: toeflRequired,
            ieltsRequired: ieltsRequired,
            admissionMonth: admissionMonth,
            tuitionMin: tuitionMin,
            tuitionMax: tuitionMax,
            keyword: keyword,
            sort: sort,
            page: page,
            pageSize: pageSize
        ))
        return try decode(data)
    }

    func guideSchool(_ idOrSlug: String, country: String = "jp") async throws -> KaiXGuideSchoolDetailResponse {
        let data = try await request("GET", "/api/guide/schools/\(idOrSlug.encodedPathSegment)", queryItems: [
            URLQueryItem(name: "country", value: country)
        ])
        return try decode(data)
    }

    func guideCompanies(
        country: String = "jp",
        regionGroup: String? = nil,
        prefecture: String? = nil,
        city: String? = nil,
        industry: String? = nil,
        subIndustry: String? = nil,
        companySize: String? = nil,
        employmentType: String? = nil,
        supportsWorkVisa: Bool? = nil,
        acceptsForeignApplicants: Bool? = nil,
        hasEnglishPositions: Bool? = nil,
        hasGlobalRoles: Bool? = nil,
        hasForeignEmployees: Bool? = nil,
        japaneseLevel: String? = nil,
        englishLevel: String? = nil,
        interviewLanguage: String? = nil,
        keyword: String? = nil,
        sort: String? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> KaiXGuideListResponse<KaiXGuideCompanyDTO> {
        let data = try await request("GET", "/api/guide/companies", queryItems: guideQuery(
            country: country,
            regionGroup: regionGroup,
            prefecture: prefecture,
            city: city,
            industry: industry,
            subIndustry: subIndustry,
            companySize: companySize,
            employmentType: employmentType,
            supportsWorkVisa: supportsWorkVisa,
            acceptsForeignApplicants: acceptsForeignApplicants,
            hasEnglishPositions: hasEnglishPositions,
            hasGlobalRoles: hasGlobalRoles,
            hasForeignEmployees: hasForeignEmployees,
            japaneseLevel: japaneseLevel,
            englishLevel: englishLevel,
            interviewLanguage: interviewLanguage,
            keyword: keyword,
            sort: sort,
            page: page,
            pageSize: pageSize
        ))
        return try decode(data)
    }

    func guideCompany(_ idOrSlug: String) async throws -> KaiXGuideCompanyDetailResponse {
        let data = try await request("GET", "/api/guide/companies/\(idOrSlug.encodedPathSegment)")
        return try decode(data)
    }

    func guideCompanyReviews(_ idOrSlug: String) async throws -> KaiXGuideCompanyReviewsResponse {
        let data = try await request("GET", "/api/guide/companies/\(idOrSlug.encodedPathSegment)/reviews")
        return try decode(data)
    }

    func guideInterviewReviews(
        country: String = "jp",
        city: String? = nil,
        industry: String? = nil,
        position: String? = nil,
        companyId: String? = nil,
        keyword: String? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> KaiXGuideListResponse<KaiXGuideInterviewReviewDTO> {
        let data = try await request("GET", "/api/guide/interview-reviews", queryItems: guideQuery(
            country: country,
            city: city,
            industry: industry,
            position: position,
            companyId: companyId,
            keyword: keyword,
            page: page,
            pageSize: pageSize
        ))
        return try decode(data)
    }

    func submitGuideCompanyReview(_ payload: KaiXGuideCompanyReviewPayload) async throws -> KaiXGuideSubmitResponse {
        let data = try await request("POST", "/api/guide/company-reviews", body: payload)
        return try decode(data)
    }

    func submitGuideInterviewReview(_ payload: KaiXGuideInterviewReviewPayload) async throws -> KaiXGuideSubmitResponse {
        let data = try await request("POST", "/api/guide/interview-reviews", body: payload)
        return try decode(data)
    }

    func submitGuideServiceRequest(_ payload: KaiXGuideServiceRequestPayload) async throws -> KaiXGuideSubmitResponse {
        let data = try await request("POST", "/api/guide/service-requests", body: payload)
        return try decode(data)
    }

    func submitGuideCorrection(targetType: String, targetId: String, message: String, sourceUrl: String = "") async throws -> KaiXGuideSubmitResponse {
        let data = try await request("POST", "/api/guide/corrections", body: [
            "targetType": targetType,
            "targetId": targetId,
            "message": message,
            "sourceUrl": sourceUrl
        ])
        return try decode(data)
    }

    func saveGuideSchool(_ idOrSlug: String, on: Bool) async throws {
        _ = try await request(on ? "POST" : "DELETE", "/api/guide/schools/\(idOrSlug.encodedPathSegment)/save", body: [String: String]())
    }

    func saveGuideCompany(_ idOrSlug: String, on: Bool) async throws {
        _ = try await request(on ? "POST" : "DELETE", "/api/guide/companies/\(idOrSlug.encodedPathSegment)/save", body: [String: String]())
    }

    func purchaseGuideProduct(_ idOrSlug: String) async throws -> KaiXGuideSubmitResponse {
        let data = try await request("POST", "/api/guide/products/\(idOrSlug.encodedPathSegment)/purchase", body: [String: String]())
        return try decode(data)
    }

    private func guideQuery(
        country: String,
        regionGroup: String? = nil,
        prefecture: String? = nil,
        city: String? = nil,
        language: String? = nil,
        categoryKey: String? = nil,
        subCategoryKey: String? = nil,
        contentType: String? = nil,
        productType: String? = nil,
        priceType: String? = nil,
        industry: String? = nil,
        subIndustry: String? = nil,
        companySize: String? = nil,
        employmentType: String? = nil,
        supportsWorkVisa: Bool? = nil,
        acceptsForeignApplicants: Bool? = nil,
        hasEnglishPositions: Bool? = nil,
        hasGlobalRoles: Bool? = nil,
        hasForeignEmployees: Bool? = nil,
        japaneseLevel: String? = nil,
        englishLevel: String? = nil,
        interviewLanguage: String? = nil,
        position: String? = nil,
        companyId: String? = nil,
        schoolType: String? = nil,
        field: String? = nil,
        acceptsInternationalStudents: Bool? = nil,
        hasEnglishProgram: Bool? = nil,
        hasJapaneseProgram: Bool? = nil,
        hasScholarship: Bool? = nil,
        hasDormitory: Bool? = nil,
        hasCareerSupport: Bool? = nil,
        hasLanguageSupport: Bool? = nil,
        jlptLevel: String? = nil,
        ejuRequired: Bool? = nil,
        toeflRequired: String? = nil,
        ieltsRequired: String? = nil,
        admissionMonth: String? = nil,
        enrollmentMonth: String? = nil,
        tuitionMin: Int? = nil,
        tuitionMax: Int? = nil,
        keyword: String? = nil,
        sort: String? = nil,
        page: Int,
        pageSize: Int
    ) -> [URLQueryItem] {
        var q: [URLQueryItem] = [
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ]
        func append(_ name: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            q.append(URLQueryItem(name: name, value: value))
        }
        func appendBool(_ name: String, _ value: Bool?) {
            guard let value else { return }
            q.append(URLQueryItem(name: name, value: value ? "true" : "false"))
        }
        append("regionGroup", regionGroup)
        append("prefecture", prefecture)
        append("city", city)
        append("language", language)
        append("categoryKey", categoryKey)
        append("subCategoryKey", subCategoryKey)
        append("contentType", contentType)
        append("productType", productType)
        append("priceType", priceType)
        append("industry", industry)
        append("subIndustry", subIndustry)
        append("companySize", companySize)
        append("employmentType", employmentType)
        appendBool("supportsWorkVisa", supportsWorkVisa)
        appendBool("acceptsForeignApplicants", acceptsForeignApplicants)
        appendBool("hasEnglishPositions", hasEnglishPositions)
        appendBool("hasGlobalRoles", hasGlobalRoles)
        appendBool("hasForeignEmployees", hasForeignEmployees)
        append("japaneseLevel", japaneseLevel)
        append("englishLevel", englishLevel)
        append("interviewLanguage", interviewLanguage)
        append("position", position)
        append("companyId", companyId)
        append("schoolType", schoolType)
        append("field", field)
        appendBool("acceptsInternationalStudents", acceptsInternationalStudents)
        appendBool("hasEnglishProgram", hasEnglishProgram)
        appendBool("hasJapaneseProgram", hasJapaneseProgram)
        appendBool("hasScholarship", hasScholarship)
        appendBool("hasDormitory", hasDormitory)
        appendBool("hasCareerSupport", hasCareerSupport)
        appendBool("hasLanguageSupport", hasLanguageSupport)
        append("jlptLevel", jlptLevel)
        appendBool("ejuRequired", ejuRequired)
        append("toeflRequired", toeflRequired)
        append("ieltsRequired", ieltsRequired)
        append("admissionMonth", admissionMonth)
        append("enrollmentMonth", enrollmentMonth)
        if let tuitionMin { append("tuitionMin", String(tuitionMin)) }
        if let tuitionMax { append("tuitionMax", String(tuitionMax)) }
        append("keyword", keyword)
        append("sort", sort)
        return q
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

    private func exploreQueryItems(region: KaiXRegionDirectory.Region?, limit: Int) -> [URLQueryItem] {
        var q: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let region {
            q.append(URLQueryItem(name: "region_code", value: region.regionCode))
            q.append(URLQueryItem(name: "country", value: region.countryCode))
            if !region.provinceCode.isEmpty {
                q.append(URLQueryItem(name: "province", value: region.provinceCode))
            }
            q.append(URLQueryItem(name: "city", value: region.cityCode))
        }
        return q
    }

    func exploreHappening(region: KaiXRegionDirectory.Region?, limit: Int = 30) async throws -> KaiXExplorePostsResponse {
        let data = try await request("GET", "/api/explore/happening", queryItems: exploreQueryItems(region: region, limit: limit))
        return try decode(data)
    }

    func exploreHot(region: KaiXRegionDirectory.Region?, limit: Int = 30) async throws -> KaiXExplorePostsResponse {
        let data = try await request("GET", "/api/explore/hot", queryItems: exploreQueryItems(region: region, limit: limit))
        return try decode(data)
    }

    func exploreTopics(region: KaiXRegionDirectory.Region?, limit: Int = 20) async throws -> KaiXExploreTopicsResponse {
        let data = try await request("GET", "/api/explore/topics", queryItems: exploreQueryItems(region: region, limit: limit))
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

    func mutualMessageFriends(query: String = "", limit: Int = 50) async throws -> [KaiXUserDTO] {
        struct Wrapper: Codable { let items: [KaiXUserDTO] }
        var q: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            q.append(URLQueryItem(name: "q", value: query))
        }
        let data = try await request("GET", "/api/messages/mutual-friends", queryItems: q)
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

    func messages(_ conversationId: String, query: String = "", day: String? = nil) async throws -> [KaiXMessageDTO] {
        var items: [URLQueryItem] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "q", value: trimmed)) }
        if let day, !day.isEmpty { items.append(URLQueryItem(name: "day", value: day)) }
        let data = try await request("GET", "/api/conversations/\(conversationId.encodedPathSegment)/messages", queryItems: items)
        let response: KaiXMessagesResponse = try decode(data)
        return response.items
    }

    func sendMessage(_ conversationId: String, content: String, mediaIds: [String] = [], attachmentIds: [String] = []) async throws -> KaiXMessageDTO {
        struct Body: Encodable { let content: String; let media_ids: [String]; let attachment_ids: [String] }
        struct Wrapper: Codable { let message: KaiXMessageDTO }
        let data = try await request("POST", "/api/conversations/\(conversationId.encodedPathSegment)/messages",
                                     body: Body(content: content, media_ids: mediaIds, attachment_ids: attachmentIds),
                                     idempotencyKey: "message-send-\(UUID().uuidString)")
        return try decode(data) as Wrapper |> \.message
    }

    func messageAttachmentViewUrl(messageId: String, attachmentId: String) async throws -> String {
        struct Payload: Codable {
            let url: String
            let expiresIn: Int?
        }
        struct Wrapper: Codable {
            let ok: Bool?
            let data: Payload?
            let url: String?
            let expiresIn: Int?
        }
        let data = try await request(
            "POST",
            "/api/messages/\(messageId.encodedPathSegment)/attachments/\(attachmentId.encodedPathSegment)/view-url"
        )
        let wrapper: Wrapper = try decode(data)
        if let url = wrapper.data?.url, !url.isEmpty { return url }
        if let url = wrapper.url, !url.isEmpty { return url }
        throw KaiXAPIError(error: .init(code: "attachment_url_missing", message: "Attachment URL missing"))
    }

    func deleteMessage(_ id: String) async throws {
        _ = try await request("DELETE", "/api/messages/\(id.encodedPathSegment)")
    }

    func markConversationRead(_ id: String) async throws {
        _ = try await request("POST", "/api/conversations/\(id.encodedPathSegment)/read")
    }

    // MARK: - media / S3 uploads

    private final class UploadTaskBox: @unchecked Sendable {
        nonisolated(unsafe) var task: URLSessionUploadTask?
        nonisolated(unsafe) var progressObservation: NSKeyValueObservation?
    }

    private func uploadData(
        request: URLRequest,
        data: Data,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> (Data, URLResponse) {
        let box = UploadTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.uploadTask(with: request, from: data) { body, response, error in
                    box.progressObservation?.invalidate()
                    box.progressObservation = nil
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let response else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    continuation.resume(returning: (body ?? Data(), response))
                }
                box.task = task
                if let onProgress {
                    box.progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
                        onProgress(min(max(progress.fractionCompleted, 0), 0.98))
                    }
                }
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    private func uploadPUTWithRetry(
        request: URLRequest,
        data: Data,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> String {
        let maxAttempts = 4
        var attempt = 0
        while true {
            attempt += 1
            do {
                let (body, response) = try await uploadData(request: request, data: data, onProgress: onProgress)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if (200..<300).contains(http.statusCode) {
                    return http.value(forHTTPHeaderField: "ETag")?.replacingOccurrences(of: "\"", with: "") ?? ""
                }
                if let api = try? JSONDecoder().decode(KaiXAPIError.self, from: body),
                   http.statusCode == 409,
                   api.error.code == "invalid_upload_state" {
                    // Mobile networks can lose the PUT response after the
                    // backend has already stored the object in S3. In that
                    // case the retry sees an already-uploaded row; let the
                    // following /complete call verify S3 and finish.
                    return ""
                }
                if attempt < maxAttempts, Self.isRetryableHTTPStatus(http.statusCode) {
                    try? await Task.sleep(nanoseconds: Self.retryBackoff(attempt, response: http))
                    continue
                }
                if let api = try? JSONDecoder().decode(KaiXAPIError.self, from: body) {
                    throw api
                }
                throw KaiXAPIError(error: .init(code: "upload_failed", message: "Upload failed (\(http.statusCode))"))
            } catch let urlError as URLError where attempt < maxAttempts && Self.isRetryableURLError(urlError) {
                try? await Task.sleep(nanoseconds: Self.retryBackoff(attempt))
                continue
            }
        }
    }

    func uploadFile(
        data: Data,
        mime: String,
        fileName: String = "upload",
        purpose: String = "post_image",
        entityType: String = "",
        entityId: String = "",
        threadId: String = "",
        groupId: String = "",
        width: Int = 0,
        height: Int = 0,
        duration: Double = 0,
        metadata: [String: String]? = nil,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> (file: KaiXUploadedFileDTO, media: KaiXMediaDTO) {
        let actionKey = "upload-\(UUID().uuidString)"
        struct PresignBody: Encodable {
            let fileName: String
            let contentType: String
            let fileSize: Int
            let purpose: String
            let entityType: String
            let entityId: String
            let threadId: String
            let groupId: String
            let duration: Double
            let durationSeconds: Double
            let metadata: [String: String]?
            let client: String
            let directS3: Bool
        }
        let presignData = try await request("POST", "/api/uploads/presign", body: PresignBody(
            fileName: fileName,
            contentType: mime,
            fileSize: data.count,
            purpose: purpose,
            entityType: entityType,
            entityId: entityId,
            threadId: threadId,
            groupId: groupId,
            duration: duration,
            durationSeconds: duration,
            metadata: metadata,
            client: "ios",
            directS3: true
        ), idempotencyKey: "\(actionKey)-presign")
        onProgress?(0.03)
        let presign: KaiXUploadPresignDTO = try decode(presignData)
        guard let uploadURL = URL(string: presign.data.uploadUrl, relativeTo: KaiXBackend.baseURL)?.absoluteURL else {
            throw URLError(.badURL)
        }
        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        for (key, value) in presign.data.headers {
            put.setValue(value, forHTTPHeaderField: key)
        }
        let etag = try await uploadPUTWithRetry(request: put, data: data) { progress in
            onProgress?(0.03 + min(max(progress, 0), 0.98) * 0.92)
        }
        onProgress?(0.96)
        struct CompleteBody: Encodable {
            let uploadId: String
            let fileKey: String
            let etag: String
            let width: Int
            let height: Int
            let duration: Double
            let durationSeconds: Double
        }
        let completedData = try await request("POST", "/api/uploads/complete", body: CompleteBody(
            uploadId: presign.data.uploadId,
            fileKey: presign.data.fileKey,
            etag: etag,
            width: width,
            height: height,
            duration: duration,
            durationSeconds: duration
        ), idempotencyKey: "\(actionKey)-complete")
        let completed: KaiXUploadCompleteDTO = try decode(completedData)
        onProgress?(1)
        return (completed.data.file, completed.data.media)
    }

    func uploadMedia(data: Data, mime: String, width: Int = 0, height: Int = 0, duration: Double = 0) async throws -> KaiXMediaDTO {
        let ext: String
        switch mime {
        case "image/png": ext = "png"
        case "image/webp": ext = "webp"
        case "image/heic": ext = "heic"
        case "video/mp4": ext = "mp4"
        case "video/quicktime": ext = "mov"
        case "video/webm": ext = "webm"
        case "application/pdf": ext = "pdf"
        default: ext = "jpg"
        }
        let purpose: String
        if mime == "application/pdf" {
            purpose = "guide_product_file"
        } else if mime.hasPrefix("video/") {
            purpose = "post_video"
        } else {
            purpose = "post_image"
        }
        let uploaded = try await uploadFile(
            data: data,
            mime: mime,
            fileName: "upload.\(ext)",
            purpose: purpose,
            entityType: mime.hasPrefix("video/") || mime.hasPrefix("image/") ? "post" : "",
            width: width,
            height: height,
            duration: duration
        )
        return uploaded.media
    }

    func deleteUploadedFile(_ fileId: String) async throws {
        _ = try await request("DELETE", "/api/uploads/\(fileId.encodedPathSegment)")
    }

    func uploadMediaLegacy(data: Data, mime: String, width: Int = 0, height: Int = 0, duration: Double = 0) async throws -> KaiXMediaDTO {
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

struct KaiXBusinessApplicationPayload: Encodable {
    let business_name: String
    let business_type: String
    let legal_name: String
    let representative_name: String
    let registration_number: String
    let country_code: String
    let city_slug: String
    let phone: String
    let email: String
    let website: String
    let address: String
    let postal_code: String
    let contact_method: String
    let description: String
    let application_note: String
    let service_categories: [String]
    let service_cities: [String]
    let uploadedFileIds: [String]
    let submit: Bool
}

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
