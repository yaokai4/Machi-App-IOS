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
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
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

        let searchTab = app.buttons["tabbar.search"]
        XCTAssertTrue(searchTab.waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertEqual(app.buttons.matching(identifier: "tabbar.search").count, 1)

        searchTab.tap()

        XCTAssertTrue(app.otherElements["search.root"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertEqual(app.buttons.matching(identifier: "tabbar.search").count, 1)
    }

    @MainActor
    private func ensureAuthenticated(_ app: XCUIApplication) throws {
        if app.buttons["tabbar.search"].waitForExistence(timeout: 4) {
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

        XCTAssertTrue(app.buttons["tabbar.search"].waitForExistence(timeout: 12))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
