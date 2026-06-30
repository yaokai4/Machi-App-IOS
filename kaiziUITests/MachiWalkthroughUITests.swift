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

    /// Launch into a deterministic, signed-in state for behavioural assertions.
    ///
    /// The raw `app.launch()` lands on the auth wall, so any test that expects
    /// the tab bar / Guide surfaces to exist must first cross it. Rather than
    /// scripting taps through the login flow (brittle, network-dependent), we
    /// reuse the same hermetic launch arguments as `MachiCoreFlowE2EUITests`:
    /// local fixtures + auto-login + an ephemeral store, with the language
    /// pinned to zh so localized labels are stable.
    @MainActor
    private func launchSignedIn() -> XCUIApplication {
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
        let app = launchSignedIn()
        tapTab(app, "tabbar.guide")

        // Query by the stable, locale-independent identifiers (not the localized
        // "学校库"/"公司库" labels) so the test survives a language switch. The
        // Guide home now leads with the two core-library cards; both are
        // FullArea buttons, so their blank Spacer area must hit-test.
        let schools = app.buttons["guide.library.schools"]
        XCTAssertTrue(schools.waitForExistence(timeout: 25), "Guide home core libraries should load")
        snap("hitarea_before")

        let companies = app.buttons["guide.library.companies"]
        XCTAssertTrue(companies.waitForExistence(timeout: 5), "公司库 card should exist")
        // Far-right of the card = blank Spacer area, NOT the icon/title.
        companies.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5)).tap()

        // Navigating away from the home means the 学校库 card disappears.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: schools)
        wait(for: [gone], timeout: 8)
        snap("hitarea_after")
        XCTAssertFalse(schools.exists, "Tapping the 公司库 card's blank area must navigate — proves full-area hit testing")
    }

    /// Regression test for "the tab bar jumps up onto the keyboard". Focuses the
    /// Guide search field and asserts the floating tab bar stays pinned at the
    /// bottom (its maxY is unchanged) instead of being shoved up above the
    /// keyboard. With the bug, maxY would drop by ~the keyboard height.
    @MainActor
    func testTabBarStaysPinnedWhenKeyboardShows() throws {
        let app = launchSignedIn()
        tapTab(app, "tabbar.guide")

        let bar = app.otherElements["main.bottomTabBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 25), "tab bar should exist on Guide")
        let restingMaxY = bar.frame.maxY

        let composer = app.textFields["guide.search.field"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "Guide search field should exist")
        composer.tap()
        let kb = app.keyboards.firstMatch
        XCTAssertTrue(kb.waitForExistence(timeout: 6), "software keyboard should attach")
        pause(1)
        snap("kbd_tabbar")

        // Non-vacuous: require a genuinely-sized software keyboard. If this
        // fails the keyboard never really showed (hardware keyboard connected),
        // so the pinned-bar assertion below would be meaningless.
        let kbFrame = kb.frame
        XCTAssertGreaterThan(kbFrame.height, 150,
                             "software keyboard must be genuinely visible (height \(kbFrame.height)) — disable Connect Hardware Keyboard")
        let barFrame = bar.frame
        // The actual product guarantee: the floating tab bar is pinned to the
        // absolute screen bottom and does NOT move when the keyboard appears.
        //   FIXED: barFrame.maxY stays == restingMaxY (bar didn't budge).
        //   BUGGY: the bar gets shoved up onto the keyboard, so maxY drops by
        //          roughly the keyboard height.
        // We assert position-unchanged directly rather than comparing against
        // the keyboard's top edge: on some simulators/devices the reported
        // keyboard frame sits below the bar's resting band, which made the old
        // "midY > keyboard.minY" heuristic geometry-dependent and flaky even
        // though the bar was correctly pinned. maxY-unchanged is the real,
        // device-independent invariant.
        XCTAssertEqual(barFrame.maxY, restingMaxY, accuracy: 2.0,
                       "tab bar must stay pinned at the bottom when the keyboard shows (bar maxY \(barFrame.maxY) vs resting \(restingMaxY); keyboard top \(kbFrame.minY), height \(kbFrame.height))")
    }

    /// Core-navigation regression guard: visit every tab and assert the app
    /// stays alive (no crash/hang) and the tab bar persists. Cheap, resilient,
    /// and catches the class of "a whole tab is broken" regressions that
    /// screenshot-only walkthroughs miss.
    @MainActor
    func testCoreTabsSmoke() throws {
        let app = launchSignedIn()
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

    // MARK: - App Store 宣传图采集（真实模拟器界面 → /tmp/machi_shots/PROMO_*）

    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["允许一次", "使用App时允许", "不允许", "允许", "Allow Once", "Allow While Using App", "Don't Allow", "Allow", "稍后", "好"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 2) { b.tap(); break }
        }
    }

    /// 游客 + 生产数据：采集面向用户的公开核心界面（首页社区流 / 发现 / 四频道 /
    /// 地图 / 帖子详情 / Machi AI 入口）。全程软处理，单个元素缺失不影响整轮。
    @MainActor
    func testAppStorePromo() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguageCode", "zh"]
        app.launch()
        dismissSystemAlerts()
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 20) { forceTap(guest) }
        _ = app.buttons["tabbar.home"].waitForExistence(timeout: 40)
        pause(4)
        dismissSystemAlerts()
        pause(2)

        // 1) 首页社区流（社交）
        tapTab(app, "tabbar.home"); pause(4)
        snap("PROMO_01_home")
        app.swipeUp(); pause(1.5); snap("PROMO_01b_home_scroll")

        // 2) 发现页（城市入口 + 频道 + 正在发生）
        tapTab(app, "tabbar.search"); pause(3)
        snap("PROMO_02_discover")
        app.swipeUp(); pause(1.5); snap("PROMO_02b_happening")
        app.swipeUp(); pause(1.2); snap("PROMO_02c_happening2")

        // 3) 四频道列表 + 地图 + 筛选
        let channels: [(label: String, key: String)] = [
            ("租房 · 住宿", "rental"),
            ("二手市场", "secondhand"),
            ("工作", "work"),
            ("商家与服务", "service"),
        ]
        for ch in channels {
            tapTab(app, "tabbar.search"); pause(1.5)
            let card = app.staticTexts[ch.label].firstMatch
            guard card.waitForExistence(timeout: 8) else { continue }
            forceTap(card); pause(3.5)
            snap("PROMO_ch_\(ch.key)")
            app.swipeUp(); pause(1.2); snap("PROMO_ch_\(ch.key)_scroll")
            app.swipeDown(); pause(1)
            if ch.key == "rental" {
                let mapBtn = app.buttons["地图"].firstMatch
                if mapBtn.waitForExistence(timeout: 4) {
                    forceTap(mapBtn); pause(8); snap("PROMO_map")
                    let listBtn = app.buttons["列表"].firstMatch
                    if listBtn.exists { forceTap(listBtn); pause(1) }
                }
            }
            if ch.key == "service" {
                let filters = app.buttons["筛选"].firstMatch
                if filters.waitForExistence(timeout: 4) {
                    forceTap(filters); pause(2); snap("PROMO_filters")
                    app.swipeDown(velocity: .fast); pause(1)
                }
            }
            tapBack(app); pause(1.5)
        }

        // 4) 帖子详情（社交内容）
        tapTab(app, "tabbar.home"); pause(3)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        pause(3)
        snap("PROMO_post_detail")
        tapBack(app); pause(1)

        // 5) Machi AI 入口（指南 tab → AI 卡 → 聊天页 intro）
        tapTab(app, "tabbar.guide"); pause(3)
        let ai = app.buttons["guide.ai.entry"].firstMatch
        if ai.waitForExistence(timeout: 8) {
            forceTap(ai); pause(3)
            snap("PROMO_ai_intro")
        }
    }

    /// 登录态（本地 fixtures，绕过登录墙）：私信列表 / 聊天 / 我的 / Machi AI 对话。
    @MainActor
    func testAppStorePromoSignedIn() throws {
        let app = launchSignedIn()
        _ = app.buttons["tabbar.home"].waitForExistence(timeout: 40)
        pause(4)

        // 私信列表 + 聊天
        tapTab(app, "tabbar.messages"); pause(3)
        snap("PROMO_messages")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)).tap()
        pause(2.5)
        snap("PROMO_chat")

        // 我的
        tapTab(app, "tabbar.profile"); pause(3)
        snap("PROMO_profile")

        // Machi AI 对话（登录态可发送；尝试捕捉真实回答气泡）
        tapTab(app, "tabbar.guide"); pause(2)
        let ai = app.buttons["guide.ai.entry"].firstMatch
        if ai.waitForExistence(timeout: 8) {
            forceTap(ai); pause(2)
            snap("PROMO_ai_intro_signed")
            let field: XCUIElement = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
            if field.waitForExistence(timeout: 4) {
                field.tap(); pause(0.5)
                field.typeText("在留卡快到期了，续签需要准备哪些材料？")
                pause(0.5)
                let send = app.buttons["发送"].firstMatch
                if send.exists { forceTap(send) }
                else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.915)).tap() }
                pause(7)
                snap("PROMO_ai_chat")
            }
        }
    }

    /// 修正版：游客 + 生产，专采四频道列表 / 地图 / 筛选 / 真实帖子详情。
    /// 不在发现页预滚动（否则频道卡滚出可视区导致找不到），频道标签用真实文案。
    @MainActor
    func testAppStorePromoChannels() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguageCode", "zh"]
        app.launch()
        dismissSystemAlerts()
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 20) { forceTap(guest) }
        _ = app.buttons["tabbar.search"].waitForExistence(timeout: 40)
        pause(4)
        dismissSystemAlerts(); pause(1)

        let channels: [(label: String, key: String)] = [
            ("租房·住宿", "rental"),
            ("二手市场", "secondhand"),
            ("工作", "work"),
            ("商家与服务", "service"),
        ]
        for ch in channels {
            tapTab(app, "tabbar.search"); pause(2.5)
            let card = app.staticTexts[ch.label].firstMatch
            guard card.waitForExistence(timeout: 8) else { snap("PROMO_ch_\(ch.key)_MISS"); continue }
            forceTap(card); pause(4)
            snap("PROMO_ch_\(ch.key)")
            app.swipeUp(); pause(1.3); snap("PROMO_ch_\(ch.key)_scroll")
            app.swipeDown(); pause(1.2)
            if ch.key == "rental" {
                let mapBtn = app.buttons["地图"].firstMatch
                if mapBtn.waitForExistence(timeout: 4) {
                    forceTap(mapBtn); pause(8); snap("PROMO_map")
                    let lb = app.buttons["列表"].firstMatch
                    if lb.exists { forceTap(lb); pause(1) }
                }
            }
            if ch.key == "secondhand" {
                let filters = app.buttons["筛选"].firstMatch
                if filters.waitForExistence(timeout: 4) {
                    forceTap(filters); pause(2); snap("PROMO_filters")
                    app.swipeDown(velocity: .fast); pause(1)
                }
            }
            tapBack(app); pause(1.5)
        }

        // 真实帖子详情：首页第一条帖子正文（游客可浏览）
        tapTab(app, "tabbar.home"); pause(3.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.33)).tap()
        pause(3.5)
        snap("PROMO_post_detail2")
    }

    /// 补采：租房频道 + 地图（中点字符不确定，改用 BEGINSWITH "租房" + 坐标兜底）。
    @MainActor
    func testAppStorePromoRentalMap() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguageCode", "zh"]
        app.launch()
        dismissSystemAlerts()
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 20) { forceTap(guest) }
        _ = app.buttons["tabbar.search"].waitForExistence(timeout: 40)
        pause(4); dismissSystemAlerts(); pause(1)
        tapTab(app, "tabbar.search"); pause(2.5)

        let card = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "租房")).firstMatch
        if card.waitForExistence(timeout: 8) {
            forceTap(card)
        } else {
            // 兜底：发现页「生活功能入口」2×2 网格右上角即租房·住宿。
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.74, dy: 0.30)).tap()
        }
        pause(4)
        snap("PROMO_ch_rental")
        app.swipeUp(); pause(1.3); snap("PROMO_ch_rental_scroll")
        app.swipeDown(); pause(1.2)
        let mapBtn = app.buttons["地图"].firstMatch
        if mapBtn.waitForExistence(timeout: 5) {
            forceTap(mapBtn); pause(9); snap("PROMO_map")
        }
    }

    /// 终版：单次游客会话内顺序采集全部 10 张（搭配 simctl 状态栏 9:41 覆盖）。
    /// 顺序经过设计：先发现页 + 四频道（不预滚动），再正在发生 / 首页 / 帖子 / AI。
    @MainActor
    func testAppStoreFinal() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguageCode", "zh"]
        app.launch()
        dismissSystemAlerts()
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 20) { forceTap(guest) }
        _ = app.buttons["tabbar.search"].waitForExistence(timeout: 40)
        pause(4); dismissSystemAlerts(); pause(1)

        // 1) 发现页
        tapTab(app, "tabbar.search"); pause(3)
        snap("FINAL_discover")

        // 2) 租房 + 地图
        openRentalCard(app); pause(4)
        snap("FINAL_rental")
        let mapBtn = app.buttons["地图"].firstMatch
        if mapBtn.waitForExistence(timeout: 4) {
            forceTap(mapBtn); pause(9); snap("FINAL_map")
            let lb = app.buttons["列表"].firstMatch; if lb.exists { forceTap(lb); pause(1) }
        }
        tapBack(app); pause(1.5)

        // 3) 二手 + 筛选
        openCard(app, "二手市场"); pause(4); snap("FINAL_secondhand")
        let filters = app.buttons["筛选"].firstMatch
        if filters.waitForExistence(timeout: 4) {
            forceTap(filters); pause(2); snap("FINAL_filters"); app.swipeDown(velocity: .fast); pause(1)
        }
        tapBack(app); pause(1.5)

        // 4) 工作
        openCard(app, "工作"); pause(4); snap("FINAL_work"); tapBack(app); pause(1.5)

        // 5) 商家与服务
        openCard(app, "商家与服务"); pause(4); snap("FINAL_service"); tapBack(app); pause(1.5)

        // 6) 正在发生 / 热榜
        tapTab(app, "tabbar.search"); pause(2)
        app.swipeUp(); pause(1.2); app.swipeUp(); pause(1.4)
        snap("FINAL_happening")

        // 7) 首页社区流
        tapTab(app, "tabbar.home"); pause(3.5)
        snap("FINAL_home")

        // 8) 帖子详情
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.33)).tap(); pause(3.5)
        snap("FINAL_post"); tapBack(app); pause(1.5)

        // 9) Machi AI 入口（中心 tab → AI 卡 → 聊天 intro）
        tapTab(app, "tabbar.guide"); pause(3)
        let ai = app.buttons["guide.ai.entry"].firstMatch
        if ai.waitForExistence(timeout: 8) { forceTap(ai); pause(3); snap("FINAL_ai") }
    }

    /// iPad 终版：同一导航逻辑，截到 IPAD_* （搭配 iPad 模拟器 9:41 覆盖）。
    @MainActor
    func testAppStoreFinalIPad() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguageCode", "zh"]
        app.launch()
        dismissSystemAlerts()
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 20) { forceTap(guest) }
        _ = app.buttons["tabbar.search"].waitForExistence(timeout: 40)
        pause(5); dismissSystemAlerts(); pause(1)

        tapTab(app, "tabbar.search"); pause(3); snap("IPAD_discover")
        openRentalCard(app); pause(4); snap("IPAD_rental")
        let mapBtn = app.buttons["地图"].firstMatch
        if mapBtn.waitForExistence(timeout: 4) {
            forceTap(mapBtn); pause(9); snap("IPAD_map")
            let lb = app.buttons["列表"].firstMatch; if lb.exists { forceTap(lb); pause(1) }
        }
        tapBack(app); pause(1.5)
        openCard(app, "二手市场"); pause(4); snap("IPAD_secondhand"); tapBack(app); pause(1.5)
        openCard(app, "工作"); pause(4); snap("IPAD_work"); tapBack(app); pause(1.5)
        openCard(app, "商家与服务"); pause(4); snap("IPAD_service"); tapBack(app); pause(1.5)
        tapTab(app, "tabbar.search"); pause(2); app.swipeUp(); pause(1.2); app.swipeUp(); pause(1.4); snap("IPAD_happening")
        tapTab(app, "tabbar.home"); pause(3.5); snap("IPAD_home")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.26)).tap(); pause(3.5); snap("IPAD_post"); tapBack(app); pause(1.5)
        tapTab(app, "tabbar.guide"); pause(3)
        let ai = app.buttons["guide.ai.entry"].firstMatch
        if ai.waitForExistence(timeout: 8) { forceTap(ai); pause(3); snap("IPAD_ai") }
    }

    /// iPad 第二轮：iPad 专用坐标（底部胶囊居中 + 左上返回）+ 充分加载等待，
    /// 补采 首页 / 发现 / 二手 / 工作 / 商家 / Machi AI。
    @MainActor
    func testAppStoreFinalIPad2() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguageCode", "zh"]
        app.launch()
        dismissSystemAlerts()
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 20) { forceTap(guest) }
        _ = app.buttons["tabbar.home"].waitForExistence(timeout: 40)
        pause(8); dismissSystemAlerts(); pause(2)

        let xs: [CGFloat] = [0.325, 0.421, 0.5, 0.578, 0.675]  // home / 发现 / Machi AI / 消息 / 我的
        func ipadTab(_ i: Int) { app.coordinate(withNormalizedOffset: CGVector(dx: xs[i], dy: 0.956)).tap() }
        func ipadBack() { app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.038)).tap() }

        // 首页社区流（充分加载）
        ipadTab(0); pause(6); snap("IPAD2_home")
        app.swipeUp(); pause(2); snap("IPAD2_home2")

        // 发现
        ipadTab(1); pause(6); snap("IPAD2_discover")

        // 频道列表：二手 / 工作 / 商家
        for (label, key) in [("二手市场","secondhand"), ("工作","work"), ("商家与服务","service")] {
            ipadTab(1); pause(3)
            let card = app.staticTexts[label].firstMatch
            if card.waitForExistence(timeout: 8) {
                forceTap(card); pause(6); snap("IPAD2_\(key)")
                ipadBack(); pause(2)
            }
        }

        // Machi AI（中心 tab → AI 卡 → 聊天 intro）
        ipadTab(2); pause(5)
        let ai = app.buttons["guide.ai.entry"].firstMatch
        if ai.waitForExistence(timeout: 8) { forceTap(ai); pause(4); snap("IPAD2_ai") }
        else { snap("IPAD2_guide") }
    }

    /// iPad 补缺：商家与服务 + Machi AI。
    @MainActor
    func testAppStoreIPadAIService() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-appLanguageCode", "zh"]
        app.launch()
        dismissSystemAlerts()
        let guest = app.buttons["auth.browseAsGuest"].firstMatch
        if guest.waitForExistence(timeout: 20) { forceTap(guest) }
        _ = app.buttons["tabbar.home"].waitForExistence(timeout: 40)
        pause(7); dismissSystemAlerts(); pause(2)
        let xs: [CGFloat] = [0.325, 0.421, 0.5, 0.578, 0.675]
        func ipadTab(_ i: Int) { app.coordinate(withNormalizedOffset: CGVector(dx: xs[i], dy: 0.956)).tap() }
        func ipadBack() { app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.038)).tap() }

        ipadTab(1); pause(5)
        let svc = app.staticTexts["商家与服务"].firstMatch
        if svc.waitForExistence(timeout: 8) { forceTap(svc); pause(6); snap("IPAD2_service"); ipadBack(); pause(2) }

        ipadTab(2); pause(5)
        let ai = app.buttons["guide.ai.entry"].firstMatch
        if ai.waitForExistence(timeout: 8) { forceTap(ai); pause(4); snap("IPAD2_ai") }
        else { snap("IPAD2_ai") }
    }

    private func openRentalCard(_ app: XCUIApplication) {
        tapTab(app, "tabbar.search"); pause(2.5)
        let card = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "租房")).firstMatch
        if card.waitForExistence(timeout: 8) { forceTap(card) }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.74, dy: 0.30)).tap() }
    }

    private func openCard(_ app: XCUIApplication, _ label: String) {
        tapTab(app, "tabbar.search"); pause(2.5)
        let card = app.staticTexts[label].firstMatch
        if card.waitForExistence(timeout: 8) { forceTap(card) }
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
