import Foundation
import XCTest

/// App Store preflight smoke coverage for every major native surface.
///
/// These tests intentionally open DEBUG-only direct routes so we can verify
/// deep screens without polluting production accounts or relying on fragile
/// multi-minute tap paths. Release builds do not include the routes.
final class MachiFullFeatureSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAccountSettingsWorkbenchAndGuideScreensOpen() throws {
        let screens: [SmokeScreen] = [
            .init("settings", ["账号", "账号与安全"]),
            .init("security", ["账号与安全", "Google 账号"]),
            .init("region-language", ["地区与语言", "语言"]),
            .init("notification-preferences", ["通知设置", "点赞通知"]),
            .init("notifications", ["通知", "暂无通知"]),
            .init("privacy", ["隐私设置", "屏蔽"]),
            .init("membership", ["Machi 认证会员", "会员资料库"]),
            .init("bookmarks", ["收藏", "收藏过的帖子"]),
            .init("drafts", ["暂无草稿", "草稿箱"]),
            .init("media-library", ["媒体库", "图片"]),
            .init("help", ["帮助中心"]),
            .init("feedback", ["反馈问题"]),
            .init("about", ["关于 Machi"]),
            .init("orders", ["我的订单"]),
            .init("inquiries", ["咨询管理"]),
            .init("workbench", ["我的工作台", "发布与交易"]),
            .init("my-listings", ["本地发布"]),
            .init("merchant", ["认证商家服务"]),
            .init("merchant-reviews", ["点评管理"]),
            .init("business-directory", ["认证商家", "搜索商家名称"]),
            .init("guide-services", ["商城", "资料包、模板、清单、课程与人工辅导服务"]),
            .init("guide-member", ["会员专属资料", "搜索会员资料"]),
            .init("guide-schools", ["学校", "学校库"]),
            .init("guide-companies", ["公司", "公司库"]),
            .init("guide-interviews", ["面试", "面经"]),
            .init("search-screen", ["tokyo", "帖子", "话题", "用户", "没有找到内容"]),
            .init("profile-self", ["UI Test", "@ui_test_runner"]),
            .init("city", ["城市频道", "推荐"]),
        ]

        for screen in screens {
            try open(screen)
        }
    }

    @MainActor
    func testComposeFormsOpenForEveryPublishedPostType() throws {
        let screens: [SmokeScreen] = [
            .init("compose:dynamic", ["发布"], requiredTexts: ["动态"]),
            .init("compose:image_post", ["发布"], requiredTexts: ["图文"]),
            .init("compose:question", ["发布"], requiredTexts: ["提问"]),
            .init("compose:rant", ["发布"], requiredTexts: ["吐槽"]),
            .init("compose:meetup", ["发布"], requiredTexts: ["约局"]),
            .init("compose:dining", ["发布"], requiredTexts: ["美食"]),
            .init("compose:event", ["发布"], requiredTexts: ["活动"]),
            .init("compose:guide", ["发布"], requiredTexts: ["攻略"]),
            .init("compose:warning", ["发布"], requiredTexts: ["避坑"]),
            .init("compose:news", ["发布"], requiredTexts: ["新闻"]),
            .init("compose:local_info", ["发布"], requiredTexts: ["本地告示"]),
            .init("compose:poll", ["发布"], requiredTexts: ["投票"]),
            .init("compose:long_post", ["发布"], requiredTexts: ["长文"]),
            .init("compose:anonymous", ["发布"], requiredTexts: ["树洞"]),
            .init("compose:referral", ["发布"], requiredTexts: ["内推"]),
        ]

        for screen in screens {
            try open(screen)
        }
    }

    @MainActor
    func testCityListingChannelsAndPublishFormsOpen() throws {
        let screens: [SmokeScreen] = [
            .init("listing:secondhand", ["二手市场", "筛选"]),
            .init("listing:rental", ["租房 · 住宿", "长租房源"]),
            .init("listing:stays", ["租房 · 住宿", "民宿"]),
            .init("listing:work", ["工作", "职位库"]),
            .init("listing:local_service", ["商家与服务", "餐厅"]),
            .init("listing:discount", ["优惠", "本地商家优惠"]),
            .init("create:secondhand", ["发布二手", "图片与视频"]),
            .init("create:rental", ["发布房源", "图片与视频"]),
            .init("create:job", ["发布求职信息", "图片与视频"]),
            .init("create:hiring", ["发布招聘", "图片与视频"]),
            .init("create:local_service", ["发布商家与服务", "图片与视频"]),
            .init("create:discount", ["发布优惠", "图片与视频"]),
        ]

        for screen in screens {
            try open(screen)
        }
    }

    @MainActor
    func testProductionBackedDetailScreensOpen() throws {
        let targets = try ProductionSmokeTargets.fetch()
        var screens: [SmokeScreen] = []

        if let listing = targets.listing {
            screens.append(.init("listing-detail:\(listing.id)", [listing.title, "详情与联系"]))
        }
        if let post = targets.post {
            screens.append(.init("post-detail:\(post.id)", [post.title, "评论"]))
        }
        if let article = targets.article {
            screens.append(.init("guide-article:\(article.id)", [article.title, "指南"]))
        }
        if let product = targets.product {
            screens.append(.init("guide-product:\(product.id)", [product.title, "商城"]))
        }
        if let school = targets.schoolId {
            screens.append(.init("guide-school:\(school)", ["学校详情"]))
        }
        if let company = targets.companyId {
            screens.append(.init("guide-company:\(company)", ["公司详情"]))
            screens.append(.init("guide-company-reviews:\(company)", ["评论"]))
        }

        guard !screens.isEmpty else {
            throw XCTSkip("Production smoke targets were unavailable.")
        }

        for screen in screens {
            try open(screen, timeout: 18)
        }
    }

    @MainActor
    private func open(_ screen: SmokeScreen, timeout: TimeInterval = 10) throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-appLanguageCode", "zh",
            "-kaixUITestLocalAuth",
            "-kaixUITestAutoLogin",
            "-kaixUITestEphemeralStore",
            "-KXDebugPush", screen.name,
        ]
        app.launchEnvironment["KAIX_UI_TEST_LOCAL_AUTH"] = "1"
        app.launchEnvironment["KAIX_UI_TEST_AUTO_LOGIN"] = "1"
        app.launchEnvironment["KAIX_UI_TEST_EPHEMERAL_STORE"] = "1"
        app.launch()

        XCTAssertTrue(
            waitForAnyText(screen.expectedTexts, in: app, timeout: timeout),
            "Expected one of \(screen.expectedTexts) on \(screen.name)"
        )
        for requiredText in screen.requiredTexts {
            XCTAssertTrue(
                waitForAnyText([requiredText], in: app, timeout: 3),
                "Expected required text \(requiredText) on \(screen.name)"
            )
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "full-smoke-\(screen.name.replacingOccurrences(of: ":", with: "-"))"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }

    @MainActor
    private func waitForAnyText(_ texts: [String], in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for text in texts where !text.isEmpty {
                if app.staticTexts[text].exists || app.buttons[text].exists || app.textFields[text].exists {
                    return true
                }
                let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
                let valuePredicate = NSPredicate(format: "value CONTAINS[c] %@", text)
                if app.staticTexts.matching(predicate).firstMatch.exists ||
                    app.buttons.matching(predicate).firstMatch.exists ||
                    app.textFields.matching(predicate).firstMatch.exists ||
                    app.textFields.matching(valuePredicate).firstMatch.exists ||
                    app.otherElements.matching(predicate).firstMatch.exists {
                    return true
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
        }
        return false
    }
}

private struct SmokeScreen {
    let name: String
    let expectedTexts: [String]
    let requiredTexts: [String]

    init(_ name: String, _ expectedTexts: [String], requiredTexts: [String] = []) {
        self.name = name
        self.expectedTexts = expectedTexts
        self.requiredTexts = requiredTexts
    }
}

private struct ProductionSmokeTargets {
    struct Target {
        let id: String
        let title: String
    }

    var listing: Target?
    var post: Target?
    var article: Target?
    var product: Target?
    var schoolId: String?
    var companyId: String?

    static func fetch() throws -> ProductionSmokeTargets {
        try asyncFetch { completion in
            Task {
                do {
                    async let listing = fetchListing()
                    async let post = fetchPost()
                    async let guide = fetchGuideHome()
                    let guideResult = try await guide
                    completion(.success(ProductionSmokeTargets(
                        listing: try await listing,
                        post: try await post,
                        article: guideResult.article,
                        product: guideResult.product,
                        schoolId: guideResult.schoolId,
                        companyId: guideResult.companyId
                    )))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private static func asyncFetch<T>(_ body: (@escaping (Result<T, Error>) -> Void) -> Void) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        body {
            result = $0
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 12) == .success else {
            throw URLError(.timedOut)
        }
        return try result!.get()
    }

    private static func fetchJSON(_ urlString: String) async throws -> [String: Any] {
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private static func fetchListing() async throws -> Target? {
        let json = try await fetchJSON("https://machicity.com/api/listings?region_code=jp.tokyo.tokyo&type=secondhand&page_size=5")
        let items = (json["items"] as? [[String: Any]]) ?? ((json["data"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
        return items.compactMap { item -> Target? in
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Target(id: id, title: title)
        }.first
    }

    private static func fetchPost() async throws -> Target? {
        let json = try await fetchJSON("https://machicity.com/api/feed?mode=recommend&page_size=10")
        let items = (json["items"] as? [[String: Any]]) ?? (json["posts"] as? [[String: Any]]) ?? ((json["data"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
        return items.compactMap { item -> Target? in
            guard let id = item["id"] as? String else { return nil }
            let rawTitle = (item["title"] as? String) ?? (item["content"] as? String) ?? ""
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return Target(id: id, title: String(title.prefix(16)))
        }.first
    }

    private static func fetchGuideHome() async throws -> (article: Target?, product: Target?, schoolId: String?, companyId: String?) {
        let json = try await fetchJSON("https://machicity.com/api/guide/home?country=jp")
        let home = (json["home"] as? [String: Any])
            ?? ((json["data"] as? [String: Any])?["home"] as? [String: Any])
            ?? json
        let articles = (home["featuredArticles"] as? [[String: Any]]) ?? (home["featured_articles"] as? [[String: Any]]) ?? []
        let products = ((home["featuredProducts"] as? [[String: Any]]) ?? (home["featured_products"] as? [[String: Any]]) ?? [])
            + ((home["featuredServices"] as? [[String: Any]]) ?? (home["featured_services"] as? [[String: Any]]) ?? [])
        let schools = (home["featuredSchools"] as? [[String: Any]]) ?? (home["featured_schools"] as? [[String: Any]]) ?? []
        let companies = (home["companyHighlights"] as? [[String: Any]]) ?? (home["company_highlights"] as? [[String: Any]]) ?? []

        let article = articles.compactMap { item -> Target? in
            guard let slug = item["slug"] as? String, let title = item["title"] as? String else { return nil }
            return Target(id: slug, title: title)
        }.first
        let product = products.compactMap { item -> Target? in
            guard let slug = item["slug"] as? String, let title = item["title"] as? String else { return nil }
            return Target(id: slug, title: title)
        }.first
        let schoolId = schools.compactMap { ($0["id"] as? String) ?? ($0["slug"] as? String) }.first
        let companyId = companies.compactMap { ($0["id"] as? String) ?? ($0["slug"] as? String) }.first
        return (article, product, schoolId, companyId)
    }
}
