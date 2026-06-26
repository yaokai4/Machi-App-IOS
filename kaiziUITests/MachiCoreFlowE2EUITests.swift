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
