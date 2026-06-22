import XCTest
@testable import Machi

/// Offline, deterministic tests for the Guide Journey / Guide OS system:
/// DTO decoding, unified-search grouping, and server-first progress payloads.
/// No backend required — these stay green in CI without a running server.
@MainActor
final class GuideJourneyTests: XCTestCase {

    private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - DTO decoding

    func testJourneysListDecoding() throws {
        let json = """
        {"status":"ok","country":"jp","language":"zh-CN","journeys":[
          {"id":"j1","key":"job_hunting","country":"jp","language":"zh-CN","title":"日本就职",
           "subtitle":"从自我分析到内定","audience":"job_seeker","icon":"briefcase","color":"#147067",
           "heroTitle":"在日本找到工作","heroSubtitle":"一步步走完","estimatedDays":180,
           "sortOrder":6,"status":"published","stepCount":7}
        ]}
        """
        let response = try decode(json, as: KaiXGuideJourneysResponse.self)
        XCTAssertEqual(response.journeys.count, 1)
        let journey = try XCTUnwrap(response.journeys.first)
        XCTAssertEqual(journey.key, "job_hunting")
        XCTAssertEqual(journey.estimatedDays, 180)
        XCTAssertEqual(journey.stepCount, 7)
    }

    func testJourneyDetailDecodingWithProgressMap() throws {
        let json = """
        {"status":"ok","country":"jp","language":"zh-CN",
         "journey":{"id":"j1","key":"job_hunting","title":"日本就职","subtitle":"...","audience":"job_seeker",
           "icon":"briefcase","color":"#147067","heroTitle":"在日本找到工作","heroSubtitle":"...",
           "estimatedDays":180,"sortOrder":6,"status":"published"},
         "steps":[
           {"id":"s1","journeyKey":"job_hunting","stepKey":"resume","title":"履历书 / 职务经歴书","summary":"按日式格式写",
            "actionLabel":"","actionType":"product","actionTarget":"","categoryKey":"career_japan",
            "articleSlugs":[],"productSlugs":[],"required":true,"estimatedMinutes":180,"deadlineHint":"投递前完成",
            "sortOrder":3,"status":"published","relatedArticles":null,"relatedProducts":null}
         ],
         "progress":{"resume":{"status":"done","completedAt":"2026-06-21T00:00:00Z"}},
         "disclaimer":"仅供参考"}
        """
        let response = try decode(json, as: KaiXGuideJourneyDetailResponse.self)
        XCTAssertEqual(response.journey.key, "job_hunting")
        XCTAssertEqual(response.steps.count, 1)
        let step = try XCTUnwrap(response.steps.first)
        XCTAssertEqual(step.stepKey, "resume")
        XCTAssertTrue(step.required)
        XCTAssertEqual(step.deadlineHint, "投递前完成")
        XCTAssertEqual(response.progress?["resume"]?.status, "done")
    }

    func testProgressResponseDecoding() throws {
        let json = """
        {"status":"ok",
         "items":[{"id":"p1","journeyKey":"job_hunting","stepKey":"resume","status":"done",
                   "completedAt":"2026-06-21T00:00:00Z","reminderAt":null,"notes":"","updatedAt":"2026-06-21T00:00:00Z"}],
         "summary":[{"journeyKey":"job_hunting","done":1,"total":7,"percent":14}]}
        """
        let response = try decode(json, as: KaiXGuideProgressResponse.self)
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.summary.first?.percent, 14)
        XCTAssertEqual(response.summary.first?.total, 7)
    }

    // MARK: - Unified search grouping

    func testSearchResponseGrouping() throws {
        let json = """
        {"status":"ok","query":"履历",
         "scopes":[{"key":"all","label":"全部"},{"key":"journeys","label":"路径"}],
         "groups":{"journeys":[
           {"id":"j1","key":"job_hunting","title":"日本就职","subtitle":"...","audience":"","icon":"briefcase",
            "color":"#147067","heroTitle":"","heroSubtitle":"","estimatedDays":180,"sortOrder":6,"status":"published"}
         ]}}
        """
        let response = try decode(json, as: KaiXGuideSearchResponse.self)
        XCTAssertEqual(response.query, "履历")
        XCTAssertEqual(response.scopes.count, 2)
        XCTAssertEqual(response.groups.journeys?.count, 1)
        // Absent groups decode as nil rather than failing the whole payload.
        XCTAssertNil(response.groups.articles)
        XCTAssertNil(response.groups.schools)
    }

    // MARK: - Server-first Guide OS payloads

    func testActivePlanDecodingIncludesContextualRecommendations() throws {
        let json = """
        {"status":"ok","profile":null,"plan":null,
         "todayTodos":[],"upcomingTodos":[],"openTodos":[],
         "recommendedProducts":[],"recommendedServices":[]}
        """
        let response = try decode(json, as: KaiXGuideActivePlanResponse.self)
        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.recommendedProducts?.count, 0)
        XCTAssertEqual(response.recommendedServices?.count, 0)
    }

    func testProgressMapDecodingUsesServerDatesAndReminderState() throws {
        let json = """
        {"status":"ok","country":"jp","language":"zh-CN",
         "journey":{"id":"j1","key":"arrival","title":"刚到日本","subtitle":"...","audience":"life",
           "icon":"plane","color":"#147067","heroTitle":"刚到日本一周计划","heroSubtitle":"...",
           "estimatedDays":7,"sortOrder":1,"status":"published"},
         "steps":[],
         "progress":{"resident_registration":{"status":"done","completedAt":"2026-06-21T00:00:00Z",
           "plannedDate":"2026-06-22","dueAt":"2026-06-30","priority":"high","notifyEnabled":true,
           "calendarNote":"带在留卡和护照"}},
         "disclaimer":"仅供参考"}
        """
        let response = try decode(json, as: KaiXGuideJourneyDetailResponse.self)
        let progress = try XCTUnwrap(response.progress?["resident_registration"])
        XCTAssertEqual(progress.status, "done")
        XCTAssertEqual(progress.plannedDate, "2026-06-22")
        XCTAssertEqual(progress.dueAt, "2026-06-30")
        XCTAssertEqual(progress.priority, "high")
        XCTAssertEqual(progress.notifyEnabled, true)
        XCTAssertEqual(progress.calendarNote, "带在留卡和护照")
    }

    // MARK: - Category -> journey mapping (article "next step")

    func testCategoryToJourneyMapping() {
        XCTAssertEqual(guideJourneyKey(forCategory: "career_japan"), "job_hunting")
        XCTAssertEqual(guideJourneyKey(forCategory: "jlpt"), "jlpt")
        XCTAssertNil(guideJourneyKey(forCategory: "unknown_category"))
    }
}
