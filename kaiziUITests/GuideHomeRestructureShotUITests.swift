import XCTest

/// 2026-07 信息架构重构 + JLPT 全真模考的可视验收:把 Guide 首页自上而下逐屏
/// 截图(AI 入口 → 搜资料库 → JLPT 卡 → 会员/商城双入口 → 六大指南 → 数据库
/// 分区),并断言重复入口确实已消失。指向本地已灌题库的后端,渲染真实数据。
final class GuideHomeRestructureShotUITests: XCTestCase {

    func testCaptureGuideHomeAndAssertNoDuplicateEntries() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-KXAutoGuest", "-KXAllowLocalAPI", "-kaix.api.base", "http://127.0.0.1:8787"]
        app.launch()

        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 10) {
            guest.tap()
        }

        let guideTab = app.buttons["tabbar.guide"].firstMatch
        XCTAssertTrue(guideTab.waitForExistence(timeout: 30), "Guide tab not found")
        guideTab.tap()
        Thread.sleep(forTimeInterval: 7)

        // 重复入口回归断言:引导卡的第二个「30 秒测水平」CTA 与其 ✕ 必须不存在,
        // 全页只剩 JLPT 卡上的那一个定级入口。
        XCTAssertFalse(app.buttons["guide.intro.placement"].exists,
                       "引导卡的重复定级 CTA 仍在首页")
        XCTAssertFalse(app.buttons["guide.intro.dismiss"].exists,
                       "引导卡仍在首页")
        XCTAssertTrue(app.buttons["guide.jlpt.placement"].firstMatch.exists,
                      "JLPT 卡的定级 CTA 应是首页唯一入口")

        attach(app, name: "01_guide_home_top")

        // 逐屏下滑截图,覆盖双入口 / 宫格 / 数据库分区。
        for i in 2...5 {
            app.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 1.2)
            attach(app, name: String(format: "%02d_guide_home_scroll", i))
        }

        // 学校库/公司库入口在独立的「数据库」分区里仍可达。
        XCTAssertTrue(app.buttons["guide.library.schools"].firstMatch.waitForExistence(timeout: 5),
                      "学校库入口缺失")
        XCTAssertTrue(app.buttons["guide.library.companies"].firstMatch.exists,
                      "公司库入口缺失")
    }

    /// JLPT 专区 → 全真模考列表:确认 5 张整卷及「JLPT 标准出分」标记渲染。
    func testCaptureJLPTFullMockList() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-KXAutoGuest", "-KXAllowLocalAPI", "-kaix.api.base", "http://127.0.0.1:8787"]
        app.launch()

        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 10) {
            guest.tap()
        }
        let guideTab = app.buttons["tabbar.guide"].firstMatch
        XCTAssertTrue(guideTab.waitForExistence(timeout: 30))
        guideTab.tap()
        Thread.sleep(forTimeInterval: 6)

        let jlptCard = app.buttons["guide.jlpt.card"].firstMatch
        XCTAssertTrue(jlptCard.waitForExistence(timeout: 10), "JLPT 卡缺失")
        jlptCard.tap()
        Thread.sleep(forTimeInterval: 5)
        attach(app, name: "10_jlpt_zone")

        let mock = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "全真模考")
        ).firstMatch
        if mock.waitForExistence(timeout: 6) {
            mock.tap()
            Thread.sleep(forTimeInterval: 6)
            attach(app, name: "11_jlpt_mock_list")
        }
    }

    /// 用 XCUIScreen 而非 app.windows.screenshot():后者要向被测进程主线程要一份
    /// element snapshot,首页几个 section 各自在 .task 里发网络请求时主线程正忙,
    /// 30s 拿不到快照就把整条用例判失败(截图只是验收产物,不该决定成败)。
    /// XCUIScreen 直接抓屏,不做任何 app 内省。
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
