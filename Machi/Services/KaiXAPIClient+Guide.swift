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
}
