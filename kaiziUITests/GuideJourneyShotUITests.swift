import XCTest

/// Captures the new Guide journey surfaces (home grid + detail timeline) as
/// screenshot attachments. Points the Debug app at a local seeded backend via
/// the `kaix.api.base` UserDefaults override so real journey data renders.
final class GuideJourneyShotUITests: XCTestCase {

    func testCaptureGuideJourneys() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-KXAutoGuest", "-kaix.api.base", "http://127.0.0.1:8787"]
        app.launch()

        // Enter as guest if the auth wall is shown.
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 10) {
            guest.tap()
        }

        // Open the Guide tab.
        let guideTab = app.buttons["tabbar.guide"].firstMatch
        XCTAssertTrue(guideTab.waitForExistence(timeout: 30), "Guide tab not found")
        guideTab.tap()

        // Let the guide home load from the local backend.
        Thread.sleep(forTimeInterval: 6)
        attach(app, name: "guide_home_journeys")

        // Best-effort: open the 日本就职 journey card -> timeline detail.
        let jobButton = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "日本就职")
        ).firstMatch
        if jobButton.waitForExistence(timeout: 6) {
            jobButton.tap()
            Thread.sleep(forTimeInterval: 5)
            attach(app, name: "guide_journey_detail")
        } else {
            let jobText = app.staticTexts["日本就职"].firstMatch
            if jobText.waitForExistence(timeout: 3) {
                jobText.tap()
                Thread.sleep(forTimeInterval: 5)
                attach(app, name: "guide_journey_detail")
            }
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
