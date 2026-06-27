import XCTest

/// End-to-end happy-path coverage for the surfaces touched by the perf /
/// stability pass: the home feed renders, every primary tab opens and stays
/// responsive (the keep-alive + `tab.switch` signpost path), and the feed
/// scrolls (LazyVStack + off-main feed-cache write + image disk cache).
///
/// Uses the same auto-login local-store launch args as the smoke suite so it
/// runs hermetically without touching production accounts.
final class MachiCoreFlowE2EUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-appLanguageCode", "zh",
            "-kaixUITestLocalAuth",
            "-kaixUITestAutoLogin",
            "-kaixUITestEphemeralStore",
        ]
        app.launchEnvironment["KAIX_UI_TEST_LOCAL_AUTH"] = "1"
        app.launchEnvironment["KAIX_UI_TEST_AUTO_LOGIN"] = "1"
        app.launchEnvironment["KAIX_UI_TEST_EPHEMERAL_STORE"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func waitForAnyText(_ texts: [String], in app: XCUIApplication, timeout: TimeInterval = 12) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for text in texts where app.staticTexts[text].exists || app.buttons[text].exists {
                return true
            }
            usleep(200_000)
        }
        return false
    }

    @MainActor
    private func tapTab(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label]
        if button.waitForExistence(timeout: 6) {
            button.tap()
        } else if app.staticTexts[label].exists {
            app.staticTexts[label].tap()
        }
    }

    @MainActor
    func testHomeFeedRendersAndAllTabsOpen() throws {
        let app = launchApp()

        // Home feed chrome — the timeline picker / app name should appear.
        XCTAssertTrue(
            waitForAnyText(["推荐", "热榜", "同城", "Machi"], in: app),
            "Home feed did not render after auto-login"
        )

        // Walk every primary tab. Each should surface something identifiable —
        // this exercises the keep-alive tab swap + tab.switch signpost path.
        let tabChecks: [(tab: String, expect: [String])] = [
            ("发现", ["发现", "搜索", "二手", "租房", "推荐"]),
            ("指南", ["指南", "学校", "公司", "目标", "待办"]),
            ("信息", ["信息", "消息", "暂无", "私信"]),
            ("我的", ["我的", "编辑资料", "设置", "@"]),
            ("首页", ["推荐", "热榜", "同城", "Machi"]),
        ]
        for check in tabChecks {
            tapTab(check.tab, in: app)
            XCTAssertTrue(
                waitForAnyText(check.expect, in: app, timeout: 10),
                "Tab \(check.tab) did not show any of \(check.expect)"
            )
        }

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "e2e-all-tabs"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func openDiscover(in app: XCUIApplication) {
        let discover = app.buttons["tabbar.search"]
        if discover.waitForExistence(timeout: 8) {
            discover.tap()
        } else {
            tapTab("发现", in: app)
        }
        XCTAssertTrue(
            waitForAnyText(["二手", "租房", "推荐", "发现", "搜索"], in: app, timeout: 10),
            "Discover did not render"
        )
    }

    /// The Discover floating compose button must open the COMPOSER — not a post
    /// detail (the audit saw a "帖子不存在或已删除" error page when tapping near
    /// the bottom of Discover). Guards the new `compose.floating` entry point.
    @MainActor
    func testDiscoverFloatingComposeOpensComposer() throws {
        let app = launchApp()
        XCTAssertTrue(
            waitForAnyText(["推荐", "热榜", "同城", "Machi"], in: app),
            "Home feed did not render after auto-login"
        )

        openDiscover(in: app)

        XCTAssertTrue(
            app.buttons["compose.floating"].firstMatch.waitForExistence(timeout: 8),
            "Discover compose FAB (compose.floating) not found"
        )
        // The inactive Home tab keeps a hidden same-id copy; resolve the active,
        // hittable one on Discover.
        let fab = app.buttons.matching(identifier: "compose.floating")
            .allElementsBoundByIndex.first(where: { $0.isHittable })
        XCTAssertNotNil(fab, "Discover compose FAB is not hittable")
        fab?.tap()

        // The composer should appear…
        let composer = app.descendants(matching: .any)["compose.root"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 8), "Tapping the FAB did not open the composer")
        // …and we must NOT have landed on a post-detail error page.
        XCTAssertFalse(
            app.staticTexts["帖子不存在或已删除"].exists,
            "FAB navigated to a (deleted) post detail instead of opening the composer"
        )
    }

    /// All five bottom tabs stay present and hittable while Discover is the
    /// active surface — the floating compose button and Discover's scroll content
    /// must never steal hit-testing from the tab bar.
    @MainActor
    func testBottomTabsRemainHittableOnDiscover() throws {
        let app = launchApp()
        XCTAssertTrue(
            waitForAnyText(["推荐", "热榜", "同城", "Machi"], in: app),
            "Home feed did not render after auto-login"
        )

        openDiscover(in: app)

        let tabIds = ["tabbar.home", "tabbar.search", "tabbar.guide", "tabbar.messages", "tabbar.profile"]
        for id in tabIds {
            let tab = app.buttons[id]
            XCTAssertTrue(tab.waitForExistence(timeout: 6), "\(id) missing on Discover")
            XCTAssertTrue(tab.isHittable, "\(id) not hittable on Discover")
        }

        // Tapping must actually switch tabs (not get swallowed by an overlay).
        app.buttons["tabbar.guide"].tap()
        XCTAssertTrue(
            waitForAnyText(["指南", "学校", "公司", "目标", "待办"], in: app, timeout: 10),
            "Guide tab did not open from Discover"
        )
        app.buttons["tabbar.search"].tap()
        XCTAssertTrue(
            waitForAnyText(["二手", "租房", "推荐", "发现", "搜索"], in: app, timeout: 10),
            "Could not return to Discover via the tab bar"
        )
    }

    @MainActor
    func testHomeFeedScrolls() throws {
        let app = launchApp()
        XCTAssertTrue(
            waitForAnyText(["推荐", "热榜", "同城", "Machi"], in: app),
            "Home feed did not render"
        )

        // Scroll the feed a few times — exercises LazyVStack virtualization,
        // image loading, and the (now off-main) feed-cache write without jank.
        let window = app.windows.firstMatch
        for _ in 0..<3 {
            window.swipeUp(velocity: .fast)
        }
        window.swipeDown(velocity: .fast)

        // App must still be responsive (not crashed / frozen) after scrolling.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
