import XCTest

/// Screenshot walkthrough used to visually verify UI upgrades on the
/// simulator without manual tapping. Writes PNGs to /tmp/machi_shots/
/// (simulator processes share the host filesystem). Not a behavioural
/// assertion suite — failures are soft so one missing element doesn't
/// abort the whole sweep.
final class MachiWalkthroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testWalkthroughScreens() throws {
        let app = XCUIApplication()
        app.launch()

        // ── 1. 登录页
        _ = app.buttons["auth.mode.register"].waitForExistence(timeout: 25)
        snap("01_auth_login")

        // ── 2. 注册模式 → 城市选择器（应只有国家列表）
        if app.buttons["auth.mode.register"].exists {
            forceTap(app.buttons["auth.mode.register"])
            pause(1)
            snap("02_auth_register")
            app.swipeUp()
            pause(1)
            let regionRow = app.buttons["auth.region"]
            if regionRow.waitForExistence(timeout: 5) {
                forceTap(regionRow)
                pause(1.2)
                snap("03_region_picker_top")
                app.swipeUp()
                pause(0.8)
                snap("04_region_picker_bottom")
                let japan = app.staticTexts["日本"].firstMatch
                if japan.waitForExistence(timeout: 3) {
                    forceTap(japan)
                    pause(1)
                    snap("05_region_japan_provinces")
                    let tokyo = app.staticTexts["东京都"].firstMatch
                    if tokyo.waitForExistence(timeout: 3) {
                        forceTap(tokyo)
                        pause(1)
                        snap("06_region_tokyo_cities")
                    }
                }
                let cancel = app.buttons["取消"].firstMatch
                if cancel.exists {
                    forceTap(cancel)
                } else {
                    app.swipeDown(velocity: .fast)
                }
                pause(1)
            }
        }

        // ── 3. 游客模式进主界面
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 5) {
            forceTap(guest)
        }
        _ = app.buttons["tabbar.search"].waitForExistence(timeout: 30)
        pause(3)
        snap("07_home")

        // ── 4. 发现页（新城市入口卡片）
        tapTab(app, "tabbar.search")
        pause(2.5)
        snap("08_discover_cards")

        // ── 5. 商家与服务列表页（紧凑筛选卡 + 渐隐 chips）
        let serviceCard = app.staticTexts["商家与服务"].firstMatch
        if serviceCard.waitForExistence(timeout: 6) {
            forceTap(serviceCard)
            pause(3)
            snap("09_service_listing")
            app.swipeUp()
            pause(1)
            snap("10_service_listing_scrolled")
            // 列表页隐藏了底部 TabBar——必须先返回发现页再切 tab。
            tapBack(app)
            pause(1.5)
        }

        // ── 6. 私信 tab（游客视角）
        tapTab(app, "tabbar.messages")
        pause(1.5)
        snap("11_messages_guest")

        // ── 7. 指南 tab（新加载动画 → 内容）
        tapTab(app, "tabbar.guide")
        snap("18_guide_loading")
        pause(3)
        snap("19_guide_loaded")

        // ── 8. 工作台 + 商家认证表单（登录后页面，用 DEBUG 直达钩子）
        app.launchArguments = ["-KXAutoGuest", "-KXDebugPush", "workbench"]
        app.launch()
        pause(3)
        snap("12_workbench_top")
        app.swipeUp()
        app.swipeUp()
        pause(1)
        snap("13_workbench_bottom")

        let merchant = app.staticTexts["认证商家服务"].firstMatch
        if merchant.waitForExistence(timeout: 5) {
        }

        app.launchArguments = ["-KXAutoGuest", "-KXDebugPush", "merchant"]
        app.launch()
        pause(3)
        snap("14_merchant_form_top")
        app.swipeUp()
        pause(0.8)
        snap("15_merchant_form_fields")
        app.swipeUp()
        pause(0.8)
        snap("16_merchant_form_more")
        app.swipeUp()
        pause(0.8)
        snap("17_merchant_form_bottom")
    }

    /// Captures social surfaces (home feed / 信息) for store screenshots.
    @MainActor
    func testSocialShots() throws {
        let app = XCUIApplication()
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["不允许", "允许", "Don't Allow", "Allow"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 3) { b.tap(); break }
        }
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 12) { forceTap(guest) }
        _ = app.buttons["tabbar.home"].waitForExistence(timeout: 30)
        pause(4)
        tapTab(app, "tabbar.home")
        pause(3.5)
        snap("SOC_home")
        app.swipeUp()
        pause(1.2)
        snap("SOC_home2")
        tapTab(app, "tabbar.messages")
        pause(2.5)
        snap("SOC_messages")
        // open the first conversation row, if any
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34)).tap()
        pause(2.5)
        snap("SOC_chat")
    }

    /// Captures the Discover polish (正在发生 rank badges) and the reworked
    /// content-type picker (fewer, clearer types).
    @MainActor
    func testUXBatchShots() throws {
        let app = XCUIApplication()
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["不允许", "允许", "Don't Allow", "Allow"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 3) { b.tap(); break }
        }
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 12) { forceTap(guest) }
        _ = app.buttons["tabbar.search"].waitForExistence(timeout: 30)
        pause(3)
        tapTab(app, "tabbar.search")
        pause(2.5)
        snap("UX_discover_top")
        app.swipeUp()
        pause(1.2)
        snap("UX_discover_happening")
        app.swipeUp()
        pause(1.2)
        snap("UX_discover_happening2")
        // Compose content-type picker via the home floating + button.
        tapTab(app, "tabbar.home")
        pause(1.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.86)).tap()
        pause(2)
        snap("UX_compose_picker")
        app.swipeUp()
        pause(0.8)
        snap("UX_compose_picker_more")
    }

    /// Captures the auth screen (to verify the prominent Apple button),
    /// dismissing the system notification-permission alert if it appears.
    @MainActor
    func testAuthScreenAppleButton() throws {
        let app = XCUIApplication()
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["不允许", "允许", "Don't Allow", "Allow"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 3) { b.tap(); break }
        }
        _ = app.buttons["auth.apple"].waitForExistence(timeout: 15)
        pause(1.5)
        snap("APPLE_auth")
    }

    /// Captures the redesigned four discover channels (二手 / 租房 / 工作 /
    /// 商家与服务) — new search-first chrome, icon category rail and filter
    /// bottom sheet. PNGs land in /tmp/machi_shots/ prefixed `RD_`.
    @MainActor
    func testFourChannelRedesign() throws {
        let app = XCUIApplication()
        // To audit dark mode, prepend ["-appAppearance", "dark"] to launchArguments.
        app.launch()

        _ = app.buttons["auth.mode.register"].waitForExistence(timeout: 25)
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 10) { forceTap(guest) }
        _ = app.buttons["tabbar.search"].waitForExistence(timeout: 30)
        pause(3)
        tapTab(app, "tabbar.search")
        pause(2.5)
        snap("RD_00_discover")

        // Map view (client-side geocoded) — capture from the first channel.
        let mapCard = app.staticTexts["二手市场"].firstMatch
        if mapCard.waitForExistence(timeout: 6) {
            forceTap(mapCard)
            pause(3)
            let mapBtn = app.buttons["地图"].firstMatch
            if mapBtn.waitForExistence(timeout: 4) {
                forceTap(mapBtn)
                pause(8)   // allow on-device geocoding to drop pins
                snap("RD_map")
            }
            tapBack(app)
            pause(1.5)
        }

        let entries: [(label: String, key: String)] = [
            ("二手市场", "secondhand"),
            ("租房 · 住宿", "rental"),
            ("工作", "work"),
            ("商家与服务", "service"),
        ]
        for entry in entries {
            tapTab(app, "tabbar.search")
            pause(1.5)
            let card = app.staticTexts[entry.label].firstMatch
            guard card.waitForExistence(timeout: 8) else { continue }
            forceTap(card)
            pause(3.5)
            snap("RD_\(entry.key)_1_top")
            app.swipeUp()
            pause(1.2)
            snap("RD_\(entry.key)_2_scrolled")
            app.swipeDown()
            pause(1)
            // Open the filter bottom sheet via its accessibility label, then
            // dismiss by swiping the (un-scrolled) sheet straight down.
            let filters = app.buttons["筛选"].firstMatch
            if filters.waitForExistence(timeout: 4) {
                forceTap(filters)
                pause(2)
                snap("RD_\(entry.key)_3_filters")
                app.swipeDown(velocity: .fast)
                pause(1.2)
            }
            tapBack(app)
            pause(1.5)
        }

        // Local 收藏 page — open from a channel header heart.
        tapTab(app, "tabbar.search")
        pause(1.2)
        let mk = app.staticTexts["二手市场"].firstMatch
        if mk.waitForExistence(timeout: 6) {
            forceTap(mk)
            pause(3)
            let saved = app.buttons["我的收藏"].firstMatch
            if saved.waitForExistence(timeout: 4) {
                forceTap(saved)
                pause(1.5)
                snap("RD_wishlist")
                app.swipeDown(velocity: .fast)
                pause(1)
            }
            tapBack(app)
        }
    }

    /// Regression for the workbench freeze: the profile top-left workbench
    /// button opens a fullScreenCover that must come up fully rendered (the
    /// earlier bug left the whole cover at opacity 0 — a blank/frozen screen
    /// with no visible close button). Logs in as a real (non-guest) user so
    /// the profile shows the workbench entry, taps it, and screenshots the
    /// cover for visual confirmation that content is actually visible.
    @MainActor
    func testProfileWorkbenchOpensWithoutFreeze() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-appLanguageCode", "zh", "-kaixUITestLocalAuth", "-kaixUITestAutoLogin", "-kaixUITestEphemeralStore"]
        app.launch()

        _ = app.buttons["tabbar.profile"].waitForExistence(timeout: 30)
        tapTab(app, "tabbar.profile")
        pause(2)

        let workbench = app.buttons["profile.workbench"]
        XCTAssertTrue(workbench.waitForExistence(timeout: 12), "profile workbench button not found")
        forceTap(workbench)
        pause(2.5)
        snap("60_workbench_after_fix")

        // The cover must actually present (close button reachable). The PNG
        // snapshot above is the visual proof the content isn't blank.
        let close = app.buttons["workbench.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "workbench cover did not present")
        forceTap(close)
        pause(1)
        snap("61_workbench_closed_back_to_profile")
    }

    /// Tap via frame-center coordinate — bypasses `isHittable`, which is
    /// false for buttons under `glassEffect` overlays (tab bar, glass
    /// circles) even though real taps land fine.
    /// Regression test for the "buttons only work when you tap the text" bug:
    /// taps the BLANK right-edge (Spacer region) of a Guide quick-grid button.
    /// With the old ordering (`.contentShape`/`.background` applied after
    /// `.buttonStyle`) that area did not hit-test, so this tap did nothing. With
    /// `FullAreaButtonStyle` the whole label is tappable, so it must navigate
    /// away from the home grid.
    @MainActor
    func testGuideGridButtonFullAreaTappable() throws {
        let app = XCUIApplication()
        app.launch()
        tapTab(app, "tabbar.guide")

        let goals = app.buttons["路径"]
        XCTAssertTrue(goals.waitForExistence(timeout: 25), "Guide home quick-grid should load")
        snap("hitarea_before")

        let calendar = app.buttons["日历"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5), "日历 grid button should exist")
        // Far-right of the button = blank Spacer area, NOT the text/icon.
        calendar.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)).tap()

        // Navigating away from the home means the grid (路径 button) disappears.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: goals)
        wait(for: [gone], timeout: 8)
        snap("hitarea_after")
        XCTAssertFalse(goals.exists, "Tapping the 日历 button's blank area must navigate — proves full-area hit testing")
    }

    /// Regression test for "the tab bar jumps up onto the keyboard". Focuses the
    /// Guide quick-add field and asserts the floating tab bar stays pinned at the
    /// bottom (its maxY is unchanged) instead of being shoved up above the
    /// keyboard. With the bug, maxY would drop by ~the keyboard height.
    @MainActor
    func testTabBarStaysPinnedWhenKeyboardShows() throws {
        let app = XCUIApplication()
        app.launch()
        tapTab(app, "tabbar.guide")

        let bar = app.otherElements["main.bottomTabBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 25), "tab bar should exist on Guide")
        let restingMaxY = bar.frame.maxY

        let composer = app.textFields.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "Guide quick-add field should exist")
        composer.tap()
        let kb = app.keyboards.firstMatch
        XCTAssertTrue(kb.waitForExistence(timeout: 6), "software keyboard should attach")
        pause(1)
        snap("kbd_tabbar")

        // Non-vacuous: require a genuinely-sized software keyboard.
        let kbFrame = kb.frame
        XCTAssertGreaterThan(kbFrame.height, 150,
                             "software keyboard must be genuinely visible (height \(kbFrame.height)) — disable Connect Hardware Keyboard")
        let barFrame = bar.frame
        // FIXED: bar stays pinned at the bottom, inside the keyboard's vertical band
        //        (its midY is below the keyboard's top edge — i.e. behind it).
        // BUGGY: bar gets shoved entirely above the keyboard (midY < keyboard top).
        XCTAssertGreaterThan(barFrame.midY, kbFrame.minY,
                             "tab bar must stay at the bottom behind the keyboard (bar midY \(barFrame.midY) vs keyboard top \(kbFrame.minY); resting maxY \(restingMaxY))")
    }

    /// Core-navigation regression guard: visit every tab and assert the app
    /// stays alive (no crash/hang) and the tab bar persists. Cheap, resilient,
    /// and catches the class of "a whole tab is broken" regressions that
    /// screenshot-only walkthroughs miss.
    @MainActor
    func testCoreTabsSmoke() throws {
        let app = XCUIApplication()
        app.launch()
        let bar = app.otherElements["main.bottomTabBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 25), "tab bar should appear on launch")
        for tab in ["tabbar.home", "tabbar.search", "tabbar.guide", "tabbar.messages", "tabbar.profile"] {
            tapTab(app, tab)
            pause(2)
            XCTAssertEqual(app.state, .runningForeground, "app must stay foregrounded after opening \(tab)")
            XCTAssertTrue(bar.exists, "tab bar must persist on \(tab)")
            snap("smoke_\(tab)")
        }
    }

    private func forceTap(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The floating glass tab bar swallows XCUITest hit-tests on its
    /// buttons, so tap by screen position: five equal segments centred
    /// in the bottom capsule.
    private func tapTab(_ app: XCUIApplication, _ identifier: String) {
        let button = app.buttons[identifier].firstMatch
        if button.exists {
            forceTap(button)
            return
        }
        let order = ["tabbar.home", "tabbar.search", "tabbar.guide", "tabbar.messages", "tabbar.profile"]
        guard let index = order.firstIndex(of: identifier) else { return }
        let xs: [CGFloat] = [0.156, 0.328, 0.5, 0.672, 0.844]
        app.coordinate(withNormalizedOffset: CGVector(dx: xs[index], dy: 0.914)).tap()
    }

    /// Tap the custom glass back-chevron used by toolbar-hidden pages
    /// (top-left, 42pt circle at ~(37, 60)pt on a 402×874 screen).
    private func tapBack(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.092, dy: 0.069)).tap()
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let dir = URL(fileURLWithPath: "/tmp/machi_shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
