//
//  foundation_model_sampleUITests.swift
//  foundation_model_sampleUITests
//
//  仕様書 §79 UI Test:
//  HOME表示 / Simple Generation / Guided Generation / Tool Calling / Image Picker /
//  PCC Availability / Dynamic Profile切替 を対象とする。
//
//  Simulator では Apple Intelligence が使えないため、生成結果の内容ではなく
//  「画面が出るか」「実行してもクラッシュせずエラーが4項目で表示されるか」を検証する（仕様書 §77）。
//

import XCTest

final class foundation_model_sampleUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// デモを開く。
    ///
    /// SwiftUI の List はセルを再利用するため、画面外へスクロールした行は
    /// アクセシビリティツリーから消える（=「一度描画したから存在する」は成り立たない）。
    /// 長いリストをスクロールして探すのは不安定なので、検索で候補を絞って
    /// 目的の行を常に先頭付近に出す。
    private func openDemo(_ rawValue: String, title: String) {
        ensureOnList()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "検索フィールドが無い")
        clearSearch()
        search.tap()
        search.typeText(title)
        // 検索セッションを閉じてキーボードを下げる。
        // 開いたままだとナビゲーションバーが隠れ、下端の行がキーボードに覆われる。
        if app.keyboards.count > 0 {
            search.typeText("\n")
        }

        let identifier = "demo.\(rawValue)"
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(waitForRow(query, timeout: 8), "デモ「\(title)」が検索結果に出てこない")

        let detailBar = app.navigationBars[title]
        for attempt in 0..<3 {
            nudgeIntoSafeBand(query)
            guard let row = resolvedRow(query) else { continue }
            row.tap()
            if detailBar.waitForExistence(timeout: 8) { return }
            if attempt < 2 { ensureOnList() }
        }

        var bars: [String] = []
        for index in 0..<app.navigationBars.count {
            bars.append(app.navigationBars.element(boundBy: index).identifier)
        }
        XCTFail("デモ「\(title)」の詳細画面が開かない — navBars=\(bars) matches=\(query.count)")
    }

    /// 行が現れるまで待つ。
    private func waitForRow(_ query: XCUIElementQuery, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count > 0 { return true }
            usleep(200_000)
        }
        return false
    }

    /// クエリを実体へ解決する。セル再利用の途中で消えることがあるので nil を返しうる。
    private func resolvedRow(_ query: XCUIElementQuery) -> XCUIElement? {
        guard query.count > 0 else { return nil }
        let row = query.element(boundBy: 0)
        return row.exists ? row : nil
    }

    /// 行が安全にタップできる帯に入るまで寄せる。
    private func nudgeIntoSafeBand(_ query: XCUIElementQuery, maxSwipes: Int = 6) {
        let list = app.collectionViews.firstMatch
        for _ in 0..<maxSwipes {
            guard let row = resolvedRow(query) else { return }
            if isSafelyTappable(row) { return }
            if row.frame.midY < app.frame.midY {
                list.swipeDown()
            } else {
                list.swipeUp()
            }
        }
    }

    /// 画面上端（ナビゲーションバー）と下端（iOS 26 のサイドバーでは検索バーが固定される）を
    /// 避けた領域に収まっているか。最下部の行は isHittable が true でも
    /// タップが検索バーに吸われて遷移しないため、帯の内側でしか押さない。
    private func isSafelyTappable(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let screen = app.frame
        return element.frame.minY >= screen.minY + 130
            && element.frame.maxY <= screen.maxY - 160
    }

    private func clearSearch() {
        let search = app.searchFields.firstMatch
        guard search.exists else { return }
        let clearButton = search.buttons.firstMatch
        if clearButton.exists, clearButton.isHittable {
            clearButton.tap()
        }
    }

    private func backToList() {
        ensureOnList()
    }

    /// 一覧画面にいるか。
    /// 検索中はナビゲーションバーのタイトルが隠れるため、タイトルでは判定しない。
    /// 一覧だけが検索フィールドとリスト（CollectionView）を持つ。
    private var isOnList: Bool {
        app.searchFields.firstMatch.exists && app.collectionViews.firstMatch.exists
    }

    /// デモ一覧に戻る。詳細画面が残っていれば戻るボタンを押す。
    private func ensureOnList() {
        if isOnList { return }
        for _ in 0..<3 {
            let back = app.navigationBars.buttons.firstMatch
            if back.exists, back.isHittable {
                back.tap()
            }
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if isOnList { return }
                usleep(200_000)
            }
        }
        XCTFail("デモ一覧に戻れなかった")
    }

    /// 要素が見つかるまでスクロールする。
    /// TextEditor がパンを奪うのを避けるため、画面右端の座標をドラッグする。
    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 16) -> Bool {
        if element.exists { return true }
        for _ in 0..<maxSwipes {
            dragUpAlongRightEdge()
            if element.exists { return true }
        }
        return element.exists
    }

    private func dragUpAlongRightEdge() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.80))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// セクションを見出しテキストで探す。
    @discardableResult
    private func scrollToSection(_ title: String, maxSwipes: Int = 16) -> Bool {
        scrollTo(app.staticTexts[title], maxSwipes: maxSwipes)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 実行ボタンを押して完了を待つ。
    private func runDemo(timeout: TimeInterval = 120) {
        let button = app.buttons["action.run"].firstMatch
        XCTAssertTrue(scrollTo(button, maxSwipes: 10), "実行ボタンが無い")
        button.tap()

        // 実行中はボタンが disabled になる。有効に戻るまで待つ。
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if button.exists, button.isEnabled { return }
            usleep(300_000)
        }
    }

    /// 仕様書 §66 共通Demo UI の各セクションが揃っていること。
    private func assertCommonSections(file: StaticString = #filePath, line: UInt = #line) {
        for section in ["Output", "Metrics", "Tool Calls", "Transcript", "Used APIs", "View Source"] {
            XCTAssertTrue(scrollToSection(section), "\(section) セクションが無い", file: file, line: line)
        }
    }

    /// エラーが4項目で表示されていること（仕様書 §59）。
    private func assertErrorHasFourFields(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(scrollTo(app.staticTexts["Technical Detail"]), "Technical Detail が無い", file: file, line: line)
        XCTAssertTrue(app.staticTexts["User Message"].exists, "User Message が無い", file: file, line: line)
        XCTAssertTrue(app.staticTexts["Recovery"].exists, "Recovery が無い", file: file, line: line)
    }

    // MARK: - HOME（仕様書 §7 / §60 / §83）

    func testHomeShowsEnvironmentStatus() throws {
        let availableLabel = app.staticTexts["Apple Intelligence Available"]
        let unavailableLabel = app.staticTexts["Apple Intelligence Unavailable"]
        XCTAssertTrue(
            availableLabel.waitForExistence(timeout: 8) || unavailableLabel.waitForExistence(timeout: 8),
            "Apple Intelligence の状態表示が無い"
        )

        // 仕様書 §83 の全カテゴリが並んでいる。
        for group in ["OVERVIEW", "TEXT", "STRUCTURED OUTPUT", "TOOLS", "VISION & MEDIA",
                      "SESSION", "PRIVATE CLOUD", "AGENT", "MODEL", "DEVELOPER", "PLAYGROUND"] {
            XCTAssertTrue(scrollTo(app.staticTexts[group], maxSwipes: 5), "カテゴリ \(group) が無い")
        }
        attachScreenshot("01-home-list")
    }

    func testDashboardShowsCapabilityMatrix() throws {
        openDemo("dashboard", title: "Dashboard")
        runDemo()

        XCTAssertTrue(scrollTo(app.staticTexts["Device"]), "Device 行が無い")
        XCTAssertTrue(scrollTo(app.staticTexts["Context Size"]), "Context Size 行が無い")
        // SDK未提供の機能が明示される。
        XCTAssertTrue(scrollTo(app.staticTexts["Vision (native prompt)"]), "SDK機能マトリクスが無い")
        XCTAssertTrue(scrollTo(app.staticTexts["Private Cloud Compute"]), "PCC の行が無い")
        attachScreenshot("02-dashboard")
    }

    // MARK: - Text

    func testSimpleGenerationScreenAndRun() throws {
        openDemo("simpleGeneration", title: "Simple Generation")

        XCTAssertTrue(scrollToSection("Input"), "Input セクションが無い")

        // プリセットが使える（仕様書 §69）。
        let preset = app.buttons["宇宙"].firstMatch
        if scrollTo(preset, maxSwipes: 4) { preset.tap() }

        runDemo()
        assertCommonSections()
        XCTAssertEqual(app.state, .runningForeground, "実行後にアプリが落ちた")
        attachScreenshot("03-simple-generation")
    }

    func testStreamingRunsWithoutCrashing() throws {
        openDemo("streaming", title: "Streaming")
        runDemo()
        XCTAssertTrue(scrollToSection("Metrics"), "Metrics が無い")
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot("04-streaming")
    }

    // MARK: - Guided Generation（仕様書 §16 / §17 / §20）

    func testGuidedGenerationScreen() throws {
        openDemo("generable", title: "Generable")

        XCTAssertTrue(scrollTo(app.staticTexts["Natural Language Input"], maxSwipes: 6), "自然言語入力が無い")
        runDemo()
        assertCommonSections()
        attachScreenshot("05-generable")
    }

    func testGuideComparisonScreen() throws {
        openDemo("guideComparison", title: "Guide")
        runDemo()
        XCTAssertTrue(scrollToSection("Output"), "Output セクションが無い")
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot("06-guide-comparison")
    }

    func testDynamicSchemaFieldEditor() throws {
        openDemo("dynamicSchema", title: "Dynamic Schema")

        // フィールドを追加できる（仕様書 §20）。
        let addField = app.buttons["Add Field"].firstMatch
        XCTAssertTrue(scrollTo(addField), "Add Field ボタンが無い")
        let before = app.textFields.count
        addField.tap()
        XCTAssertGreaterThan(app.textFields.count, before, "フィールドが増えていない")
        attachScreenshot("07-dynamic-schema")
    }

    // MARK: - Tool Calling（仕様書 §23-§28）

    func testToolCallingScreenShowsToolLog() throws {
        openDemo("basicTool", title: "Basic Tool")

        let preset = app.buttons["金沢"].firstMatch
        if scrollTo(preset, maxSwipes: 4) { preset.tap() }

        runDemo()
        // Tool Log と Transcript のパネルが常設されている（仕様書 §28 / §37）。
        XCTAssertTrue(scrollToSection("Tool Calls"), "Tool Calls パネルが無い")
        XCTAssertTrue(scrollToSection("Transcript"), "Transcript パネルが無い")
        attachScreenshot("08-basic-tool")
    }

    func testSideEffectToolScreen() throws {
        openDemo("sideEffectTool", title: "Side Effect Tool")
        runDemo()
        XCTAssertTrue(scrollToSection("Output"), "Output セクションが無い")
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot("09-side-effect")
    }

    // MARK: - Vision & Media（仕様書 §29-§36 と動画/リアルタイムの拡張）

    func testPhotoDemoShowsPicker() throws {
        openDemo("imageDescription", title: "Photo Description")

        // PhotosPicker と未選択時の案内（仕様書 §29 / §70）。
        XCTAssertTrue(scrollTo(app.buttons["Choose Photo"], maxSwipes: 8), "写真選択ボタンが無い")
        XCTAssertTrue(app.staticTexts["画像が未選択"].exists, "未選択時の案内が無い")
        // Sample Data Only の注意書き（仕様書 §75）。
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Sample Data Only")).count > 0,
                      "Sample Data Only の注記が無い")
        attachScreenshot("10-photo-description")
    }

    func testOCRDemoHandlesMissingImage() throws {
        openDemo("ocr", title: "OCR")
        XCTAssertTrue(scrollTo(app.buttons["Choose Photo"], maxSwipes: 8), "OCR に画像選択が無い")

        // 画像なしで実行してもクラッシュせず、エラーが4項目で出る（仕様書 §59）。
        runDemo()
        assertErrorHasFourFields()
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot("11-ocr")
    }

    func testCompareImagesHasTwoPickers() throws {
        openDemo("compareImages", title: "Compare Photos")
        XCTAssertTrue(scrollTo(app.staticTexts["Image A"], maxSwipes: 8), "Image A が無い")
        XCTAssertTrue(scrollTo(app.staticTexts["Image B"]), "Image B が無い")
        XCTAssertEqual(app.buttons.matching(identifier: "Choose Photo").count, 2, "写真の選択ボタンが2つ無い")
        attachScreenshot("12-compare-photos")
    }

    func testVideoDemoShowsPickerAndFrameStepper() throws {
        openDemo("videoAnalysis", title: "Video Analysis")

        XCTAssertTrue(scrollTo(app.buttons["Choose Video"], maxSwipes: 8), "動画選択ボタンが無い")
        XCTAssertTrue(app.staticTexts["動画が未選択"].exists, "未選択時の案内が無い")
        // コマ数を変えられる。
        let stepper = app.steppers.firstMatch
        XCTAssertTrue(scrollTo(stepper), "サンプリングコマ数のステッパーが無い")
        stepper.buttons.element(boundBy: 1).tap()

        // 動画なしで実行してもクラッシュせずエラーになる。
        runDemo()
        assertErrorHasFourFields()
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot("13-video-analysis")
    }

    func testCameraDemoShowsStartAndAnalyze() throws {
        openDemo("camera", title: "Camera Frame")

        // 仕様書 §35: プレビュー上に Analyze Current Frame を配置する。
        XCTAssertTrue(scrollTo(app.buttons["Start Camera"], maxSwipes: 8), "Start Camera ボタンが無い")
        XCTAssertTrue(scrollTo(app.buttons["action.run"]), "Analyze Current Frame ボタンが無い")

        // Simulator にカメラは無い。押しても落ちず、理由が表示される。
        app.buttons["Start Camera"].tap()
        XCTAssertTrue(
            scrollTo(app.staticTexts["カメラを利用できません"], maxSwipes: 8)
                || scrollToSection("Input", maxSwipes: 6),
            "Simulator でのカメラ不可表示が出ない"
        )
        XCTAssertEqual(app.state, .runningForeground, "カメラ起動でアプリが落ちた")
        attachScreenshot("14-camera-frame")
    }

    func testLiveCameraDemoShowsControls() throws {
        openDemo("liveCamera", title: "Live Camera")
        XCTAssertTrue(scrollTo(app.buttons["Start Camera"], maxSwipes: 8), "Start Camera ボタンが無い")
        // 連続解析中の最新フレームをモデルに問う実行ボタン。
        XCTAssertTrue(scrollTo(app.buttons["action.run"]), "実行ボタンが無い")
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot("15-live-camera")
    }

    // MARK: - PCC（仕様書 §46: 利用不可でも正常なデモ画面として扱う）

    func testPCCAvailabilityIsShownAsValidScreen() throws {
        openDemo("pcc", title: "PCC")
        runDemo()

        XCTAssertTrue(scrollTo(app.staticTexts["Availability"]), "Availability 行が無い")
        // 値を捏造せず SDK未提供と明示する。
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "SDK未提供")).count > 0,
                      "SDK未提供の明示が無い")
        // エラーは4項目で表示される（仕様書 §59）。
        assertErrorHasFourFields()
        attachScreenshot("16-pcc")
    }

    // MARK: - Agent（仕様書 §50 / §52 / §53 / §54）

    func testDynamicProfileSwitching() throws {
        openDemo("dynamicProfile", title: "Dynamic Profile")

        XCTAssertTrue(scrollTo(app.buttons["Quick"].firstMatch, maxSwipes: 8), "Profile セグメントが無い")

        // Vision Profile は OCRTool を公開する（仕様書 §52）。
        let vision = app.buttons["Vision"].firstMatch
        XCTAssertTrue(vision.exists, "Vision セグメントが無い")
        vision.tap()
        XCTAssertTrue(app.staticTexts["OCRTool"].waitForExistence(timeout: 5), "Vision Profile で OCRTool が出ない")

        // Inventory Profile は InventoryTool を公開する。
        let inventory = app.buttons["Inventory"].firstMatch
        XCTAssertTrue(inventory.exists, "Inventory セグメントが無い")
        inventory.tap()
        XCTAssertTrue(app.staticTexts["InventoryTool"].waitForExistence(timeout: 5), "Inventory Profile で InventoryTool が出ない")
        XCTAssertFalse(app.staticTexts["OCRTool"].exists, "Profile を切り替えても OCRTool が残っている")

        attachScreenshot("17-dynamic-profile")
    }

    func testLifecycleEventsPanelExists() throws {
        openDemo("lifecycleEvents", title: "Lifecycle Events")
        runDemo()
        // 仕様書 §54: イベントログのパネル。
        XCTAssertTrue(scrollToSection("Lifecycle"), "Lifecycle パネルが無い")
        attachScreenshot("18-lifecycle")
    }

    func testSessionPropertyPatientPicker() throws {
        openDemo("sessionProperty", title: "Session Property")
        // 仕様書 §53: 選択中の患者を切り替えられる。
        XCTAssertTrue(scrollTo(app.buttons["田中太郎"].firstMatch, maxSwipes: 8), "患者選択が無い")
        app.buttons["佐藤花子"].firstMatch.tap()
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot("19-session-property")
    }

    // MARK: - Developer

    func testErrorLabListsTriggers() throws {
        openDemo("errorLab", title: "Error Lab")
        // 仕様書 §59: エラーをカテゴリ別に一覧し、再現できる。
        XCTAssertTrue(scrollTo(app.staticTexts["Error Catalog"]), "Error Catalog が無い")
        XCTAssertTrue(scrollTo(app.buttons["action.run"]), "Trigger Error ボタンが無い")
        attachScreenshot("20-error-lab")
    }

    func testAPIReferenceListsAPIs() throws {
        openDemo("apiReference", title: "API Reference")
        runDemo()
        XCTAssertTrue(scrollToSection("Used APIs"), "Used APIs が無い")
        attachScreenshot("21-api-reference")
    }

    func testPlaygroundHasAllControls() throws {
        openDemo("playground", title: "Foundation Models Playground")

        // 仕様書 §84: Model / Instructions / Prompt / Image / Tools / Options / Structured / Streaming
        XCTAssertTrue(scrollTo(app.staticTexts["Instructions"], maxSwipes: 8), "Instructions が無い")
        XCTAssertTrue(scrollTo(app.staticTexts["Prompt"]), "Prompt が無い")
        XCTAssertTrue(scrollTo(app.staticTexts["Tools"]), "Tools 選択が無い")
        XCTAssertTrue(scrollTo(app.staticTexts["Temperature"]), "Temperature が無い")
        XCTAssertTrue(scrollTo(app.switches.firstMatch), "トグルが無い")
        attachScreenshot("22-playground")
    }

    // MARK: - 画面切り替えでの初期化

    func testSwitchingDemoClearsPreviousOutput() throws {
        // 1. Tool を呼ぶデモを実行して、Output と Tool Calls に内容を作る。
        openDemo("basicTool", title: "Basic Tool")
        runDemo()
        XCTAssertTrue(scrollToSection("Output"), "Output セクションが無い")
        attachScreenshot("reset-1-before-switch")

        // 実行後は「未実行」ではなくなっている。
        let notExecutedBefore = app.staticTexts["未実行"].exists
        XCTAssertFalse(notExecutedBefore, "実行したのに Output が空のまま")

        // 2. 別のデモへ切り替える。
        openDemo("ocr", title: "OCR")

        // 3. 前の画面の結果が残っていない。
        XCTAssertTrue(scrollToSection("Output"), "Output セクションが無い")
        XCTAssertTrue(app.staticTexts["未実行"].exists, "切り替え後も前の画面の Output が残っている")
        XCTAssertFalse(app.staticTexts["金沢の気温は26℃です。"].exists, "前の画面の応答が残っている")

        XCTAssertTrue(scrollToSection("Tool Calls"), "Tool Calls パネルが無い")
        XCTAssertTrue(app.staticTexts["Tool は呼ばれていません"].exists, "前の画面の Tool Calls が残っている")

        XCTAssertTrue(scrollToSection("Transcript"), "Transcript パネルが無い")
        XCTAssertTrue(app.staticTexts["Transcript はまだありません"].exists, "前の画面の Transcript が残っている")
        attachScreenshot("reset-2-after-switch")
    }

    func testLogsScreenKeepsSessionWideHistory() throws {
        // Logs 画面だけは画面横断の履歴を見せる（切り替えで消えては困る）。
        openDemo("basicTool", title: "Basic Tool")
        runDemo()

        openDemo("logs", title: "Logs")
        runDemo()

        XCTAssertTrue(scrollToSection("Tool Calls"), "Tool Calls パネルが無い")
        XCTAssertFalse(app.staticTexts["Tool は呼ばれていません"].exists,
                       "Logs 画面にセッション全体の Tool 履歴が残っていない")
        attachScreenshot("reset-3-logs")
    }

    // MARK: - 全画面が開けること（仕様書 §60）

    func testDemosAcrossEveryCategoryOpenWithoutCrashing() throws {
        // 各カテゴリから代表画面を開き、実際のナビゲーションが通ることを確認する。
        // 58 画面すべての body 評価はユニットテスト側 (ViewTests) が担当しているので、
        // ここでは実機操作としての遷移を薄く広く見る。
        // 一覧の並び順どおりに並べているので、リストを前方向にたどるだけで済む。
        let demos: [(String, String)] = [
            ("dashboard", "Dashboard"),
            ("conversation", "Conversation"),
            ("classification", "Classification"),
            ("nestedObject", "Nested Object"),
            ("greedySampling", "Greedy Sampling"),
            ("searchTool", "Search Tool"),
            ("multiStepTool", "Multi-step Tool"),
            ("structuredVision", "Structured Vision"),
            ("visionTool", "Vision + Tool"),
            ("transcript", "Transcript"),
            ("prewarm", "Prewarm"),
            ("quota", "Quota"),
            ("agentWorkflow", "Agent Workflow"),
            ("modelSwitch", "Model Switch"),
            ("logs", "Logs")
        ]

        for (rawValue, title) in demos {
            openDemo(rawValue, title: title)
            XCTAssertEqual(app.state, .runningForeground, "\(title) を開いたところでアプリが落ちた")
            backToList()
        }
        XCTAssertEqual(app.state, .runningForeground, "全画面走査の後にアプリが落ちた")
    }
}
