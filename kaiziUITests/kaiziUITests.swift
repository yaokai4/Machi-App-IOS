//
//  kaiziUITests.swift
//  kaiziUITests
//
//  Created by 姚凯 on 2026/5/21.
//

import XCTest

final class kaiziUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguageCode", "zh", "-kaixUITestLocalAuth", "-kaixUITestAutoLogin", "-kaixUITestEphemeralStore"]
        app.launchEnvironment["KAIX_UI_TEST_LOCAL_AUTH"] = "1"
        app.launchEnvironment["KAIX_UI_TEST_AUTO_LOGIN"] = "1"
        app.launchEnvironment["KAIX_UI_TEST_EPHEMERAL_STORE"] = "1"
        app.launch()

        try ensureAuthenticated(app)

        XCTAssertTrue(
            app.buttons["tabbar.home"].waitForExistence(timeout: 12) ||
                app.staticTexts["Machi"].waitForExistence(timeout: 2),
            "The app should reach the authenticated home surface."
        )
    }

    @MainActor
    func testBottomNavigationDoesNotDuplicateAndSearchOpens() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguageCode", "zh", "-kaixUITestLocalAuth", "-kaixUITestAutoLogin", "-kaixUITestEphemeralStore"]
        app.launchEnvironment["KAIX_UI_TEST_LOCAL_AUTH"] = "1"
        app.launchEnvironment["KAIX_UI_TEST_AUTO_LOGIN"] = "1"
        app.launchEnvironment["KAIX_UI_TEST_EPHEMERAL_STORE"] = "1"
        app.launch()

        try ensureAuthenticated(app)

        XCTAssertEqual(app.tabBars.count, 0)

        tapBottomTab(.search, in: app)

        XCTAssertTrue(waitForDiscoverRoot(in: app, timeout: 8))
        XCTAssertEqual(app.tabBars.count, 0)
    }

    @MainActor
    private func ensureAuthenticated(_ app: XCUIApplication) throws {
        if !app.buttons["auth.mode.register"].waitForExistence(timeout: 2) {
            settleForUITest(2_000)
            return
        }

        let registerButton = app.buttons["auth.mode.register"]
        XCTAssertTrue(registerButton.waitForExistence(timeout: 6))
        registerButton.tap()

        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
            .lowercased()
        let username = app.textFields["auth.username"]
        let displayName = app.textFields["auth.displayName"]
        let password = app.secureTextFields["auth.password"]

        XCTAssertTrue(username.waitForExistence(timeout: 4))
        username.tap()
        username.typeText("ui_\(suffix)")

        XCTAssertTrue(displayName.waitForExistence(timeout: 4))
        displayName.tap()
        displayName.typeText("UI Test")

        XCTAssertTrue(password.waitForExistence(timeout: 4))
        password.tap()
        password.typeText("secret123")

        let submitButton = app.buttons["auth.submit"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 4))
        XCTAssertTrue(submitButton.isEnabled)
        submitButton.tap()

        settleForUITest(2_500)
    }

    @MainActor
    private func tapBottomTab(_ tab: AppTabIndex, in app: XCUIApplication) {
        let totalTabs: CGFloat = 5
        let x = (CGFloat(tab.rawValue) + 0.5) / totalTabs
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.94)).tap()
        settleForUITest(1_200)
    }

    @MainActor
    private func settleForUITest(_ ms: UInt32) {
        usleep(ms * 1000)
    }

    private enum AppTabIndex: Int {
        case home = 0
        case search = 1
        case guide = 2
        case messages = 3
        case profile = 4
    }

    @MainActor
    private func waitForDiscoverRoot(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        if app.otherElements["discover.root"].waitForExistence(timeout: timeout) {
            return true
        }
        return app.staticTexts["城市入口"].waitForExistence(timeout: 2)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// Drives the app through every primary surface and captures a screenshot of
    /// each, so the full UI can be visually reviewed from the test bundle.
    /// Run: xcodebuild test -only-testing:kaiziUITests/kaiziUITests/testVisualSweep
    @MainActor
    func testVisualSweep() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        // Authenticated test session (tab navigation is reliable here, matching
        // the passing nav test). Data is an ephemeral store, so this verifies
        // every page's LAYOUT / empty-state / premium polish; real-content
        // rendering is verified separately on the production build.
        app.launchArguments += ["-appLanguageCode", "zh", "-kaixUITestLocalAuth", "-kaixUITestAutoLogin", "-kaixUITestEphemeralStore"]
        app.launchEnvironment["KAIX_UI_TEST_LOCAL_AUTH"] = "1"
        app.launchEnvironment["KAIX_UI_TEST_AUTO_LOGIN"] = "1"
        app.launchEnvironment["KAIX_UI_TEST_EPHEMERAL_STORE"] = "1"
        app.launch()

        func snap(_ name: String) {
            let a = XCTAttachment(screenshot: app.screenshot())
            a.name = name
            a.lifetime = .keepAlways
            add(a)
        }
        func settle(_ ms: UInt32 = 2_000) { usleep(ms * 1000) }
        @discardableResult
        func switchTab(_ id: String) -> Bool {
            let index: AppTabIndex
            switch id {
            case "home": index = .home
            case "search": index = .search
            case "guide": index = .guide
            case "messages": index = .messages
            case "profile": index = .profile
            default: return false
            }
            tapBottomTab(index, in: app)
            settle()
            return true
        }
        func goBack() {
            let back = app.navigationBars.buttons.firstMatch
            if back.exists && back.isHittable { back.tap(); settle(1_100) }
        }

        let guest = app.buttons["auth.browseAsGuest"]
        if guest.waitForExistence(timeout: 6) { guest.tap(); settle(2_500) }
        _ = app.buttons["tabbar.search"].waitForExistence(timeout: 25)
        settle(2_500)
        snap("00-home")

        // Tabs FIRST (before any segment/sheet interaction, which is what broke
        // subsequent tab taps in earlier runs).
        switchTab("search"); settle(2_200); snap("02-discover")
        for ch in ["二手市场", "租房", "找工作", "本地服务"] {
            let card = app.staticTexts[ch].firstMatch
            guard card.waitForExistence(timeout: 3) else { continue }
            card.tap(); settle(2_600); snap("03-channel-\(ch)")
            let cell = app.scrollViews.firstMatch.buttons.element(boundBy: 0)
            if cell.waitForExistence(timeout: 3), cell.isHittable { cell.tap(); settle(2_600); snap("04-detail-\(ch)"); goBack() }
            goBack(); switchTab("search")
        }
        switchTab("guide"); settle(2_200); snap("05-guide")
        switchTab("messages"); settle(2_000); snap("06-messages")
        switchTab("profile"); settle(2_200); snap("07-profile-workbench")
        // Settings entry from profile/workbench
        let settingsEntry = app.staticTexts["设置"].firstMatch
        if settingsEntry.waitForExistence(timeout: 3) { settingsEntry.tap(); settle(2_000); snap("08-settings"); goBack() }

        // Home segments + compose LAST
        switchTab("home"); settle(1_500)
        for seg in ["同城", "热榜"] {
            let s = app.buttons[seg].firstMatch
            if s.waitForExistence(timeout: 2) { s.tap(); settle(2_000); snap("01-home-\(seg)") }
        }
        let fab = app.buttons.matching(NSPredicate(format: "label CONTAINS '投稿' OR label CONTAINS '发布' OR label CONTAINS '+'")).firstMatch
        if fab.waitForExistence(timeout: 2) { fab.tap(); settle(2_200); snap("09-compose") }
    }
}
