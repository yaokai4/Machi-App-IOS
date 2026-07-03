import Foundation

// Machi Guide (日本指南) API methods, split out of KaiXAPIClient.swift for
// maintainability. Shares the internal request/decode/guideQuery helpers on
// the client. No behaviour change — same methods, same call sites.
extension KaiXAPIClient {
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

    // MARK: - guide journeys (situation -> action path)

    func guideJourneys(country: String = "jp", language: String = "zh-CN") async throws -> KaiXGuideJourneysResponse {
        let data = try await request("GET", "/api/guide/journeys", queryItems: [
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "language", value: language),
        ])
        return try decode(data)
    }

    func guideJourney(_ key: String, country: String = "jp", language: String = "zh-CN") async throws -> KaiXGuideJourneyDetailResponse {
        let data = try await request("GET", "/api/guide/journeys/\(key.encodedPathSegment)", queryItems: [
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "language", value: language),
        ])
        return try decode(data)
    }

    /// Unified Guide search — articles + schools + companies + products + faq +
    /// journeys, grouped. Same endpoint the Web client uses, so search is
    /// consistent across platforms.
    func guideSearch(country: String = "jp", language: String = "zh-CN", keyword: String, scope: String = "all") async throws -> KaiXGuideSearchResponse {
        let data = try await request("GET", "/api/guide/search", queryItems: [
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "q", value: keyword),
            URLQueryItem(name: "scope", value: scope),
        ])
        return try decode(data)
    }

    func guideProgress() async throws -> KaiXGuideProgressResponse {
        let data = try await request("GET", "/api/guide/progress")
        return try decode(data)
    }

    @discardableResult
    func updateGuideProgress(
        journeyKey: String,
        stepKey: String,
        status: String,
        reminderAt: String? = nil,
        plannedDate: String? = nil,
        dueAt: String? = nil,
        priority: String? = nil,
        notifyEnabled: Bool? = nil,
        calendarNote: String? = nil,
        notes: String? = nil
    ) async throws -> KaiXGuideProgressResponse {
        let body = KaiXGuideProgressUpdatePayload(
            journeyKey: journeyKey,
            stepKey: stepKey,
            status: status,
            reminderAt: reminderAt,
            plannedDate: plannedDate,
            dueAt: dueAt,
            priority: priority,
            notifyEnabled: notifyEnabled,
            calendarNote: calendarNote,
            notes: notes
        )
        let data = try await request("PATCH", "/api/guide/progress", body: body)
        return try decode(data)
    }

    func guideProfile() async throws -> KaiXGuideProfileResponse {
        let data = try await request("GET", "/api/guide/profile")
        return try decode(data)
    }

    @discardableResult
    func updateGuideProfile(_ payload: KaiXGuideProfileUpdatePayload) async throws -> KaiXGuideProfileResponse {
        let data = try await request("PATCH", "/api/guide/profile", body: payload)
        return try decode(data)
    }

    func guidePlans() async throws -> KaiXGuidePlanListResponse {
        let data = try await request("GET", "/api/guide/plans")
        return try decode(data)
    }

    func guideActivePlan(language: String = "zh-CN") async throws -> KaiXGuideActivePlanResponse {
        let data = try await request("GET", "/api/guide/plans/active", queryItems: [
            URLQueryItem(name: "language", value: language),
        ])
        return try decode(data)
    }

    @discardableResult
    func startGuidePlan(journeyKey: String, planType: String? = nil, targetDate: String? = nil) async throws -> KaiXGuidePlanStartResponse {
        struct Body: Encodable {
            let journeyKey: String
            let planType: String?
            let targetDate: String?
        }
        let data = try await request("POST", "/api/guide/plans/start", body: Body(journeyKey: journeyKey, planType: planType, targetDate: targetDate))
        return try decode(data)
    }

    func createCustomGuidePlan(title: String, targetDate: String? = nil) async throws -> KaiXGuidePlanStartResponse {
        struct Body: Encodable {
            let planType: String
            let title: String
            let subtitle: String
            let targetDate: String?
        }
        let data = try await request(
            "POST",
            "/api/guide/plans/start",
            body: Body(planType: "custom", title: title, subtitle: "自定义目标", targetDate: targetDate)
        )
        return try decode(data)
    }

    /// Spec P0.2: generate a JLPT/日语 study plan of recurring habit todos
    /// (每日词汇 / 每周语法 / 周末模考) + registration & sprint milestones.
    @discardableResult
    func generateStudyPlan(targetLevel: String, examDate: String, dailyMinutes: Int) async throws -> KaiXGuideStudyPlanResponse {
        struct Body: Encodable {
            let targetLevel: String
            let examDate: String
            let dailyMinutes: Int
        }
        let data = try await request("POST", "/api/guide/study-plan", body: Body(targetLevel: targetLevel, examDate: examDate, dailyMinutes: dailyMinutes))
        return try decode(data)
    }

    @discardableResult
    func updateGuidePlan(id: String, title: String? = nil, subtitle: String? = nil, status: String? = nil, targetDate: String? = nil) async throws -> KaiXGuidePlanResponse {
        struct Body: Encodable {
            let title: String?
            let subtitle: String?
            let status: String?
            let targetDate: String?
        }
        let data = try await request("PATCH", "/api/guide/plans/\(id.encodedPathSegment)", body: Body(title: title, subtitle: subtitle, status: status, targetDate: targetDate))
        return try decode(data)
    }

    @discardableResult
    func resetGuidePlan(id: String) async throws -> KaiXGuidePlanResponse {
        let data = try await request("POST", "/api/guide/plans/\(id.encodedPathSegment)/reset", body: [String: String]())
        return try decode(data)
    }

    func guideTodos(status: String? = nil, type: String? = nil, from: String? = nil, to: String? = nil, planId: String? = nil, limit: Int = 50) async throws -> KaiXGuideTodoListResponse {
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let status, !status.isEmpty { query.append(URLQueryItem(name: "status", value: status)) }
        if let type, !type.isEmpty { query.append(URLQueryItem(name: "type", value: type)) }
        if let from, !from.isEmpty { query.append(URLQueryItem(name: "from", value: from)) }
        if let to, !to.isEmpty { query.append(URLQueryItem(name: "to", value: to)) }
        if let planId, !planId.isEmpty { query.append(URLQueryItem(name: "planId", value: planId)) }
        let data = try await request("GET", "/api/guide/todos", queryItems: query)
        return try decode(data)
    }

    @discardableResult
    func updateGuideTodo(id: String, payload: KaiXGuideTodoUpdatePayload) async throws -> KaiXGuideTodoResponse {
        let data = try await request("PATCH", "/api/guide/todos/\(id.encodedPathSegment)", body: payload)
        return try decode(data)
    }

    @discardableResult
    func createGuideTodo(_ payload: KaiXGuideTodoCreatePayload) async throws -> KaiXGuideTodoResponse {
        let data = try await request("POST", "/api/guide/todos", body: payload)
        return try decode(data)
    }

    @discardableResult
    func completeGuideTodo(id: String) async throws -> KaiXGuideTodoResponse {
        let data = try await request("POST", "/api/guide/todos/\(id.encodedPathSegment)/complete", body: [String: String]())
        return try decode(data)
    }

    func deleteGuideTodo(id: String) async throws {
        _ = try await request("DELETE", "/api/guide/todos/\(id.encodedPathSegment)")
    }

    /// Set/clear a todo's reminder time; server-side reminderAt is the source of
    /// truth (APNs is the primary channel, local notifications a supplement).
    @discardableResult
    func setGuideTodoReminder(id: String, reminderAt: String) async throws -> KaiXGuideTodoResponse {
        let data = try await request("POST", "/api/guide/todos/\(id.encodedPathSegment)/reminder", body: ["reminderAt": reminderAt])
        return try decode(data)
    }

    func guideCalendar(from: String? = nil, to: String? = nil, limit: Int = 200) async throws -> KaiXGuideCalendarResponse {
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let from, !from.isEmpty { query.append(URLQueryItem(name: "from", value: from)) }
        if let to, !to.isEmpty { query.append(URLQueryItem(name: "to", value: to)) }
        let data = try await request("GET", "/api/guide/calendar", queryItems: query)
        return try decode(data)
    }

    @discardableResult
    func createGuideCalendarEvent(_ payload: KaiXGuideCalendarEventPayload) async throws -> KaiXGuideCalendarEventResponse {
        let data = try await request("POST", "/api/guide/calendar/events", body: payload)
        return try decode(data)
    }

    @discardableResult
    func updateGuideCalendarEvent(id: String, payload: KaiXGuideCalendarEventPayload) async throws -> KaiXGuideCalendarEventResponse {
        let data = try await request("PATCH", "/api/guide/calendar/events/\(id.encodedPathSegment)", body: payload)
        return try decode(data)
    }

    func deleteGuideCalendarEvent(id: String) async throws {
        _ = try await request("DELETE", "/api/guide/calendar/events/\(id.encodedPathSegment)")
    }

    func guideApplications() async throws -> KaiXGuideApplicationsResponse {
        let data = try await request("GET", "/api/guide/applications")
        return try decode(data)
    }

    @discardableResult
    func createGuideApplication(_ payload: KaiXGuideApplicationPayload) async throws -> KaiXGuideApplicationResponse {
        let data = try await request("POST", "/api/guide/applications", body: payload)
        return try decode(data)
    }

    @discardableResult
    func updateGuideApplication(id: String, payload: KaiXGuideApplicationPayload) async throws -> KaiXGuideApplicationResponse {
        let data = try await request("PATCH", "/api/guide/applications/\(id.encodedPathSegment)", body: payload)
        return try decode(data)
    }

    func deleteGuideApplication(id: String) async throws {
        _ = try await request("DELETE", "/api/guide/applications/\(id.encodedPathSegment)")
    }

    func guideLifeItems() async throws -> KaiXGuideLifeItemsResponse {
        let data = try await request("GET", "/api/guide/life-items")
        return try decode(data)
    }

    func guideLifePayments(itemId: String) async throws -> KaiXGuideLifePaymentsResponse {
        let data = try await request("GET", "/api/guide/life-items/\(itemId.encodedPathSegment)/payments")
        return try decode(data)
    }

    func createGuideLifePayment(itemId: String, payload: KaiXGuideLifePaymentPayload) async throws -> KaiXGuideLifePaymentResponse {
        let data = try await request("POST", "/api/guide/life-items/\(itemId.encodedPathSegment)/payments", body: payload)
        return try decode(data)
    }

    /// Public catalog of life-bill presets with smart defaults (spec P1).
    func guideLifePresets(language: String = "zh-CN") async throws -> KaiXGuideLifePresetsResponse {
        let data = try await request("GET", "/api/guide/life-presets", queryItems: [URLQueryItem(name: "language", value: language)])
        return try decode(data)
    }

    /// Materials + services that help finish a given todo / plan stage. A single
    /// recommendation query failing never breaks Guide — the server returns an
    /// empty list rather than 500.
    func guideRecommendations(todoId: String? = nil, planType: String? = nil, todoType: String? = nil,
                              country: String = "jp", language: String = "zh-CN") async throws -> KaiXGuideRecommendationsResponse {
        var query: [URLQueryItem] = [URLQueryItem(name: "country", value: country), URLQueryItem(name: "language", value: language)]
        if let todoId, !todoId.isEmpty { query.append(URLQueryItem(name: "todoId", value: todoId)) }
        if let planType, !planType.isEmpty { query.append(URLQueryItem(name: "planType", value: planType)) }
        if let todoType, !todoType.isEmpty { query.append(URLQueryItem(name: "todoType", value: todoType)) }
        let data = try await request("GET", "/api/guide/recommendations", queryItems: query)
        return try decode(data)
    }

    @discardableResult
    func createGuideLifeItem(_ payload: KaiXGuideLifeItemPayload) async throws -> KaiXGuideLifeItemResponse {
        let data = try await request("POST", "/api/guide/life-items", body: payload)
        return try decode(data)
    }

    @discardableResult
    func updateGuideLifeItem(id: String, payload: KaiXGuideLifeItemPayload) async throws -> KaiXGuideLifeItemResponse {
        let data = try await request("PATCH", "/api/guide/life-items/\(id.encodedPathSegment)", body: payload)
        return try decode(data)
    }

    func deleteGuideLifeItem(id: String) async throws {
        _ = try await request("DELETE", "/api/guide/life-items/\(id.encodedPathSegment)")
    }

    // MARK: Finance (manual ledger + budgets + summary)

    func guideFinanceCategories() async throws -> KaiXGuideFinanceCategoriesResponse {
        let data = try await request("GET", "/api/guide/finance/categories")
        return try decode(data)
    }

    func guideFinanceSummary(month: String? = nil) async throws -> KaiXGuideFinanceSummaryDTO {
        var query: [URLQueryItem] = []
        if let month, !month.isEmpty { query.append(URLQueryItem(name: "month", value: month)) }
        let data = try await request("GET", "/api/guide/finance/summary", queryItems: query)
        return try decode(data)
    }

    func guideTransactions(month: String? = nil, limit: Int = 200) async throws -> KaiXGuideTransactionsResponse {
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let month, !month.isEmpty { query.append(URLQueryItem(name: "month", value: month)) }
        let data = try await request("GET", "/api/guide/transactions", queryItems: query)
        return try decode(data)
    }

    @discardableResult
    func createGuideTransaction(_ payload: KaiXGuideTransactionPayload) async throws -> KaiXGuideTransactionDTO {
        let data = try await request("POST", "/api/guide/transactions", body: payload)
        let resp: KaiXGuideTransactionResponse = try decode(data)
        return resp.transaction
    }

    func deleteGuideTransaction(id: String) async throws {
        _ = try await request("DELETE", "/api/guide/transactions/\(id.encodedPathSegment)")
    }

    func guideDigest(days: Int = 14) async throws -> KaiXGuideDigestDTO {
        let data = try await request("GET", "/api/guide/digest", queryItems: [URLQueryItem(name: "days", value: String(days))])
        return try decode(data)
    }

    @discardableResult
    func guideQuickSetup(profile: String) async throws -> KaiXGuideQuickSetupResponse {
        let data = try await request("POST", "/api/guide/quick-setup", body: KaiXGuideQuickSetupPayload(profile: profile))
        return try decode(data)
    }

    func guideFinanceTrend(months: Int = 6, month: String? = nil) async throws -> KaiXGuideFinanceTrendResponse {
        var query: [URLQueryItem] = [URLQueryItem(name: "months", value: String(months))]
        if let month, !month.isEmpty { query.append(URLQueryItem(name: "month", value: month)) }
        let data = try await request("GET", "/api/guide/finance/trend", queryItems: query)
        return try decode(data)
    }

    @discardableResult
    func postGuideFixedCosts(month: String? = nil) async throws -> KaiXGuidePostFixedResponse {
        let data = try await request("POST", "/api/guide/finance/post-fixed", body: KaiXGuidePostFixedPayload(month: month))
        return try decode(data)
    }

    func guideBudgets() async throws -> KaiXGuideBudgetsResponse {
        let data = try await request("GET", "/api/guide/budgets")
        return try decode(data)
    }

    @discardableResult
    func setGuideBudget(category: String, monthlyLimit: Int) async throws -> KaiXGuideBudgetsResponse {
        let data = try await request("POST", "/api/guide/budgets", body: KaiXGuideBudgetSetPayload(category: category, monthlyLimit: monthlyLimit))
        return try decode(data)
    }

    func guideContracts() async throws -> KaiXGuideContractsResponse {
        let data = try await request("GET", "/api/guide/contracts")
        return try decode(data)
    }

    @discardableResult
    func createGuideContract(_ payload: KaiXGuideContractPayload) async throws -> KaiXGuideContractResponse {
        let data = try await request("POST", "/api/guide/contracts", body: payload)
        return try decode(data)
    }

    @discardableResult
    func updateGuideContract(id: String, payload: KaiXGuideContractPayload) async throws -> KaiXGuideContractResponse {
        let data = try await request("PATCH", "/api/guide/contracts/\(id.encodedPathSegment)", body: payload)
        return try decode(data)
    }

    func deleteGuideContract(id: String) async throws {
        _ = try await request("DELETE", "/api/guide/contracts/\(id.encodedPathSegment)")
    }

    func guideDocuments() async throws -> KaiXGuideDocumentsResponse {
        let data = try await request("GET", "/api/guide/documents")
        return try decode(data)
    }

    @discardableResult
    func createGuideDocument(_ payload: KaiXGuideDocumentPayload) async throws -> KaiXGuideDocumentResponse {
        let data = try await request("POST", "/api/guide/documents", body: payload)
        return try decode(data)
    }

    @discardableResult
    func updateGuideDocument(id: String, payload: KaiXGuideDocumentPayload) async throws -> KaiXGuideDocumentResponse {
        let data = try await request("PATCH", "/api/guide/documents/\(id.encodedPathSegment)", body: payload)
        return try decode(data)
    }

    func deleteGuideDocument(id: String) async throws {
        _ = try await request("DELETE", "/api/guide/documents/\(id.encodedPathSegment)")
    }

    func guideAttachments(entityType: String, entityId: String) async throws -> KaiXGuideAttachmentsResponse {
        let data = try await request("GET", "/api/guide/attachments", queryItems: [
            URLQueryItem(name: "entityType", value: entityType),
            URLQueryItem(name: "entityId", value: entityId),
        ])
        return try decode(data)
    }

    func guideSavedItems() async throws -> KaiXGuideSavedResponse {
        let data = try await request("GET", "/api/guide/saved")
        return try decode(data)
    }

    func setGuideSaved(itemType: String, itemId: String, on: Bool) async throws {
        _ = try await request(on ? "POST" : "DELETE", "/api/guide/saved", body: ["itemType": itemType, "itemId": itemId])
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

    func updateGuideArticleProgress(_ idOrSlug: String, country: String = "jp", progressPercent: Int) async throws -> KaiXGuideArticleProgressResponse {
        let clamped = max(0, min(100, progressPercent))
        let data = try await request("PATCH", "/api/guide/articles/\(idOrSlug.encodedPathSegment)/progress", body: [
            "country": country,
            "progressPercent": String(clamped),
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

    // MARK: - Guide product reviews (BE4 / guide_reviews)

    /// Public paginated list of PUBLISHED reviews + the 5-bucket distribution.
    /// `idOrSlug` matches the product detail route (server accepts id OR slug).
    func guideProductReviews(_ idOrSlug: String, limit: Int = 20, offset: Int = 0) async throws -> KaiXGuideReviewsResponse {
        let data = try await request("GET", "/api/guide/products/\(idOrSlug.encodedPathSegment)/reviews", queryItems: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return try decode(data)
    }

    /// The caller's own review (any status) + whether they're allowed to write one.
    func guideProductMyReview(_ idOrSlug: String) async throws -> KaiXGuideReviewMeResponse {
        let data = try await request("GET", "/api/guide/products/\(idOrSlug.encodedPathSegment)/reviews/me")
        return try decode(data)
    }

    /// Create or update the caller's review. Buy-gated + one per (user, product).
    /// A re-submit returns the row to pending for re-moderation.
    @discardableResult
    func submitGuideProductReview(_ idOrSlug: String, rating: Int, body reviewBody: String, anonymous: Bool = false) async throws -> KaiXGuideReviewSubmitResponse {
        struct Body: Encodable { let rating: Int; let body: String; let anonymous: Bool }
        let data = try await request("POST", "/api/guide/products/\(idOrSlug.encodedPathSegment)/reviews",
                                     body: Body(rating: rating, body: reviewBody, anonymous: anonymous))
        return try decode(data)
    }

    /// Author withdraws their own review.
    func deleteMyGuideReview(_ reviewId: String) async throws {
        _ = try await request("DELETE", "/api/guide/reviews/\(reviewId.encodedPathSegment)")
    }

    /// Idempotent "有帮助" vote toggle. `on == false` removes the vote.
    @discardableResult
    func voteGuideReviewHelpful(_ reviewId: String, on: Bool) async throws -> KaiXGuideReviewHelpfulResponse {
        let data = try await request(on ? "POST" : "DELETE", "/api/guide/reviews/\(reviewId.encodedPathSegment)/helpful")
        return try decode(data)
    }

    /// Report a review. Deduped server-side (one report per user per target).
    func reportGuideReview(_ reviewId: String, reason: String = "other", note: String = "") async throws {
        _ = try await request("POST", "/api/guide/reviews/\(reviewId.encodedPathSegment)/report",
                              body: ["reason": reason, "note": note])
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

    /// Purchased + member-unlocked materials, the user's service requests, and a
    /// merged order history. Read-only aggregation; requires a logged-in user.
    func guideMyLibrary(language: String = "zh-CN") async throws -> KaiXGuideLibraryResponse {
        let data = try await request("GET", "/api/guide/my-library", queryItems: [
            URLQueryItem(name: "language", value: language)
        ])
        return try decode(data)
    }

    // MARK: - Machi AI (原创 in-app assistant)

    /// `guestId` (signed-out callers only) rides the `X-Machi-Guest-Id` header
    /// so the server can compute the guest taster quota; pass nil when logged in.
    func guideAIBootstrap(country: String = "jp", language: String = "zh-CN",
                          guestId: String? = nil) async throws -> KaiXGuideAIBootstrapResponse {
        var headers: [String: String] = [:]
        if let guestId, !guestId.isEmpty { headers["X-Machi-Guest-Id"] = guestId }
        let data = try await request("GET", "/api/guide/ai/bootstrap", queryItems: [
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "language", value: language),
        ], extraHeaders: headers)
        return try decode(data)
    }

    func guideJLPTZone(country: String = "jp", language: String = "zh-CN") async throws -> KaiXGuideJLPTZoneResponse {
        let data = try await request("GET", "/api/guide/jlpt", queryItems: [
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "language", value: language),
        ])
        return try decode(data)
    }

    func guideAIConversations(limit: Int = 30) async throws -> KaiXGuideAIConversationsResponse {
        let data = try await request("GET", "/api/guide/ai/conversations", queryItems: [
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        return try decode(data)
    }

    func guideAIMessages(conversationId: String) async throws -> KaiXGuideAIMessagesResponse {
        let id = try requirePathIdentifier(conversationId)
        let data = try await request("GET", "/api/guide/ai/conversations/\(id.encodedPathSegment)/messages")
        return try decode(data)
    }

    /// Send one turn to Machi AI. A nil `conversationId` starts a new thread.
    /// Longer timeout than the default JSON budget because answering takes a
    /// few seconds; the 429 `AI_QUOTA_EXCEEDED` surfaces as a `KaiXAPIError`.
    /// `guestId` (signed-out callers only) carries the stable client UUID in
    /// `X-Machi-Guest-Id` for the server-enforced guest taster quota.
    func sendGuideAIMessage(conversationId: String?, message: String, country: String = "jp",
                            language: String = "zh-CN", category: String? = nil,
                            ability: String? = nil, guestId: String? = nil) async throws -> KaiXGuideAIChatResponse {
        struct Body: Encodable {
            let conversationId: String?
            let message: String
            let country: String
            let language: String
            let category: String?
            let ability: String?
        }
        var headers: [String: String] = [:]
        if let guestId, !guestId.isEmpty { headers["X-Machi-Guest-Id"] = guestId }
        let data = try await request(
            "POST", "/api/guide/ai/chat",
            body: Body(conversationId: conversationId, message: message, country: country,
                       language: language, category: category, ability: ability),
            extraHeaders: headers,
            timeoutInterval: 40
        )
        return try decode(data)
    }

    func deleteGuideAIConversation(id: String) async throws {
        let cid = try requirePathIdentifier(id)
        _ = try await request("DELETE", "/api/guide/ai/conversations/\(cid.encodedPathSegment)")
    }

    func sendGuideAIFeedback(messageId: String, rating: String, reason: String? = nil) async throws -> KaiXGuideAIFeedbackResponse {
        struct Body: Encodable {
            let rating: String
            let reason: String?
        }
        let mid = try requirePathIdentifier(messageId)
        let data = try await request("POST", "/api/guide/ai/messages/\(mid.encodedPathSegment)/feedback",
                                     body: Body(rating: rating, reason: reason))
        return try decode(data)
    }

    // MARK: - JLPT 备考核心 (BE6 / iOS-3): 题库 / 定级 / 打卡 / 单词 / 在线考试 / 日历

    /// Sample practice questions. Signed-out callers get free questions only;
    /// members additionally see member-only questions (server-enforced).
    func jlptPractice(level: String, section: String? = nil, count: Int? = nil) async throws -> KaiXJLPTPracticeResponse {
        var q = [URLQueryItem(name: "level", value: level)]
        if let section, !section.isEmpty { q.append(URLQueryItem(name: "section", value: section)) }
        if let count { q.append(URLQueryItem(name: "count", value: String(count))) }
        let data = try await request("GET", "/api/guide/jlpt/practice", queryItems: q)
        return try decode(data)
    }

    /// Grade + record one answer. Requires auth.
    func jlptAttempt(questionId: String, selectedIndex: Int, sessionId: String? = nil,
                     sourceKind: String = "practice") async throws -> KaiXJLPTAttemptResult {
        struct Body: Encodable {
            let questionId: String
            let selectedIndex: Int
            let sessionId: String?
            let sourceKind: String
        }
        let data = try await request("POST", "/api/guide/jlpt/attempt",
                                     body: Body(questionId: questionId, selectedIndex: selectedIndex,
                                                sessionId: sessionId, sourceKind: sourceKind))
        return try decode(data)
    }

    /// 错题本 — questions whose latest attempt was wrong (answers revealed).
    func jlptReview(level: String? = nil, count: Int? = nil) async throws -> KaiXJLPTReviewResponse {
        var q: [URLQueryItem] = []
        if let level, !level.isEmpty { q.append(URLQueryItem(name: "level", value: level)) }
        if let count { q.append(URLQueryItem(name: "count", value: String(count))) }
        let data = try await request("GET", "/api/guide/jlpt/review", queryItems: q)
        return try decode(data)
    }

    func jlptStats(level: String? = nil) async throws -> KaiXJLPTStatsResponse {
        var q: [URLQueryItem] = []
        if let level, !level.isEmpty { q.append(URLQueryItem(name: "level", value: level)) }
        let data = try await request("GET", "/api/guide/jlpt/stats", queryItems: q)
        return try decode(data)
    }

    func jlptStreak() async throws -> KaiXJLPTStreakResponse {
        let data = try await request("GET", "/api/guide/jlpt/streak")
        return try decode(data)
    }

    func jlptExamDates(region: String = "jp") async throws -> KaiXJLPTExamDatesResponse {
        let data = try await request("GET", "/api/guide/jlpt/exam-dates",
                                     queryItems: [URLQueryItem(name: "region", value: region)])
        return try decode(data)
    }

    /// Member-only per-question AI explanation (Machi AI Pro). Free callers spend
    /// their normal Machi AI daily quota (or 403 when exhausted). Longer timeout
    /// since generation takes a few seconds.
    func jlptExplain(questionId: String, language: String = "zh-CN") async throws -> KaiXJLPTExplainResponse {
        struct Body: Encodable {
            let questionId: String
            let language: String
        }
        let data = try await request("POST", "/api/guide/jlpt/explain",
                                     body: Body(questionId: questionId, language: language),
                                     timeoutInterval: 40)
        return try decode(data)
    }

    // ── placement (定级) ────────────────────────────────────────────────────
    func jlptPlacementStart() async throws -> KaiXJLPTPlacementStartResponse {
        let data = try await request("GET", "/api/guide/jlpt/placement/start")
        return try decode(data)
    }

    func jlptPlacementSubmit(answers: [KaiXJLPTPlacementAnswer]) async throws -> KaiXJLPTPlacementResult {
        struct Body: Encodable { let answers: [KaiXJLPTPlacementAnswer] }
        let data = try await request("POST", "/api/guide/jlpt/placement/submit", body: Body(answers: answers))
        return try decode(data)
    }

    // ── vocab (单词) ────────────────────────────────────────────────────────
    func jlptVocabDecks(level: String? = nil) async throws -> KaiXJLPTVocabDecksResponse {
        var q: [URLQueryItem] = []
        if let level, !level.isEmpty { q.append(URLQueryItem(name: "level", value: level)) }
        let data = try await request("GET", "/api/guide/jlpt/vocab/decks", queryItems: q)
        return try decode(data)
    }

    /// Deck detail. Member-only decks 403 (`MEMBER_REQUIRED`) for free users.
    func jlptVocabDeck(deckId: String) async throws -> KaiXJLPTVocabDeckResponse {
        let id = try requirePathIdentifier(deckId)
        let data = try await request("GET", "/api/guide/jlpt/vocab/deck/\(id.encodedPathSegment)")
        return try decode(data)
    }

    @discardableResult
    func jlptVocabMark(wordId: String, state: String) async throws -> KaiXJLPTVocabMarkResponse {
        struct Body: Encodable { let wordId: String; let state: String }
        let data = try await request("POST", "/api/guide/jlpt/vocab/mark",
                                     body: Body(wordId: wordId, state: state))
        return try decode(data)
    }

    func jlptVocabProgress(level: String? = nil) async throws -> KaiXJLPTVocabProgress {
        var q: [URLQueryItem] = []
        if let level, !level.isEmpty { q.append(URLQueryItem(name: "level", value: level)) }
        let data = try await request("GET", "/api/guide/jlpt/vocab/progress", queryItems: q)
        return try decode(data)
    }

    /// 考单词 — generates an MCQ quiz from the word bank (kind='vocab' session).
    func jlptVocabQuizStart(level: String, deckId: String? = nil, count: Int? = nil) async throws -> KaiXJLPTVocabQuizStartResponse {
        var q = [URLQueryItem(name: "level", value: level)]
        if let deckId, !deckId.isEmpty { q.append(URLQueryItem(name: "deckId", value: deckId)) }
        if let count { q.append(URLQueryItem(name: "count", value: String(count))) }
        let data = try await request("GET", "/api/guide/jlpt/vocab/quiz/start", queryItems: q)
        return try decode(data)
    }

    /// Submit a vocab quiz. `answers` is index-aligned to the quiz questions.
    func jlptVocabQuizSubmit(sessionId: String, answers: [Int]) async throws -> KaiXJLPTVocabQuizSubmitResponse {
        struct Body: Encodable { let sessionId: String; let answers: [Int] }
        let data = try await request("POST", "/api/guide/jlpt/vocab/quiz/submit",
                                     body: Body(sessionId: sessionId, answers: answers))
        return try decode(data)
    }

    // ── online exams (在线考试) ─────────────────────────────────────────────
    func jlptExams(level: String? = nil) async throws -> KaiXJLPTExamsResponse {
        var q: [URLQueryItem] = []
        if let level, !level.isEmpty { q.append(URLQueryItem(name: "level", value: level)) }
        let data = try await request("GET", "/api/guide/jlpt/exams", queryItems: q)
        return try decode(data)
    }

    /// Start an exam session. Member-only exams 403 (`MEMBER_REQUIRED`) for free
    /// users; empty banks return 409 (`no_questions`).
    func jlptExamStart(examId: String) async throws -> KaiXJLPTExamStartResponse {
        struct Body: Encodable { let examId: String }
        let data = try await request("POST", "/api/guide/jlpt/exam/start", body: Body(examId: examId))
        return try decode(data)
    }

    @discardableResult
    func jlptExamAnswer(sessionId: String, questionId: String, selectedIndex: Int) async throws -> KaiXJLPTExamAnswerResponse {
        struct Body: Encodable { let sessionId: String; let questionId: String; let selectedIndex: Int }
        let data = try await request("POST", "/api/guide/jlpt/exam/answer",
                                     body: Body(sessionId: sessionId, questionId: questionId, selectedIndex: selectedIndex))
        return try decode(data)
    }

    func jlptExamSubmit(sessionId: String) async throws -> KaiXJLPTExamResult {
        struct Body: Encodable { let sessionId: String }
        let data = try await request("POST", "/api/guide/jlpt/exam/submit", body: Body(sessionId: sessionId))
        return try decode(data)
    }

    func jlptExamHistory(level: String? = nil) async throws -> KaiXJLPTExamHistoryResponse {
        var q: [URLQueryItem] = []
        if let level, !level.isEmpty { q.append(URLQueryItem(name: "level", value: level)) }
        let data = try await request("GET", "/api/guide/jlpt/exam/history", queryItems: q)
        return try decode(data)
    }

    func jlptExamSession(sessionId: String) async throws -> KaiXJLPTExamResult {
        let id = try requirePathIdentifier(sessionId)
        let data = try await request("GET", "/api/guide/jlpt/exam/session/\(id.encodedPathSegment)")
        return try decode(data)
    }
}
