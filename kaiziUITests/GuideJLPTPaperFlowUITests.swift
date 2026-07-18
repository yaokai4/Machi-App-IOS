import XCTest

/// 分科整卷流转的可视验收:进入 JLPT 全真模考列表 → 点分科父卷 → 整卷概览
/// (intro) → 开始第一科(笔试) → 中间休息 → 聴解(音频播放器)→ 合并成绩。
/// 指向本地已建临时分科卷的后端(test-paper-n5)。
final class GuideJLPTPaperFlowUITests: XCTestCase {

    func testCapturePaperFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-KXAutoGuest", "-KXAllowLocalAPI", "-kaix.api.base", "http://127.0.0.1:8787"]
        app.launch()

        if app.buttons["auth.browseAsGuest"].firstMatch.waitForExistence(timeout: 10) {
            app.buttons["auth.browseAsGuest"].firstMatch.tap()
        }
        let guideTab = app.buttons["tabbar.guide"].firstMatch
        XCTAssertTrue(guideTab.waitForExistence(timeout: 30))
        guideTab.tap()
        Thread.sleep(forTimeInterval: 5)

        // JLPT 卡 → 专区
        let jlptCard = app.buttons["guide.jlpt.card"].firstMatch
        XCTAssertTrue(jlptCard.waitForExistence(timeout: 10), "JLPT 卡缺失")
        jlptCard.tap()
        Thread.sleep(forTimeInterval: 4)

        // 全真模考入口
        let mock = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "全真模考")).firstMatch
        XCTAssertTrue(mock.waitForExistence(timeout: 8), "全真模考入口缺失")
        mock.tap()
        Thread.sleep(forTimeInterval: 5)
        attach(app, name: "20_exam_list")

        // 分科父卷卡(标题含「分科」)
        let paperCard = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "分科")).firstMatch
        XCTAssertTrue(paperCard.waitForExistence(timeout: 8), "分科父卷卡缺失")
        paperCard.tap()
        Thread.sleep(forTimeInterval: 4)
        attach(app, name: "21_paper_intro")

        // 整卷概览应含两科目名
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "聴解")).firstMatch.waitForExistence(timeout: 5),
                      "整卷概览未显示聴解科目")

        // 开始考试 → 第一科(笔试)
        let startBtn = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "开始考试")).firstMatch
        if startBtn.waitForExistence(timeout: 5) {
            startBtn.tap()
            Thread.sleep(forTimeInterval: 5)
            attach(app, name: "22_section1_written")
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
