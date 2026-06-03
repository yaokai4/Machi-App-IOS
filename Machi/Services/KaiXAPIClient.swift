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
    func register(handle: String, displayName: String, password: String, email: String? = nil, code: String? = nil, region: KaiXRegionDirectory.Region? = nil) async throws -> KaiXLoginResponse {
        var body: [String: String] = ["handle": handle, "display_name": displayName, "password": password]
        if let email { body["email"] = email }
        if let code, !code.isEmpty { body["code"] = code }
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

    func sendVerificationCode(email: String, purpose: String = "register") async throws -> KaiXEmailCodeResponse {
        let data = try await request("POST", "/api/auth/send-verification-code",
                                     body: ["email": email, "purpose": purpose])
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
