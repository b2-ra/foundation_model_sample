//
//  AllDemosRunSweepTests.swift
//  foundation_model_sampleUITests
//
//  全デモを1つずつ開いて Run し、Output に何が出たかを回収する掃引テスト。
//  個々の生成内容の正しさは判定しない。目的は「どのデモが実行できて、
//  どのデモがエラーになるか」を取りこぼしなく一覧にすること。
//

import XCTest

final class AllDemosRunSweepTests: XCTestCase {

    private var app: XCUIApplication!

    /// DemoCatalog の LabDemo 全ケース（rawValue, 画面タイトル）。
    private static let demos: [(id: String, title: String)] = [
        ("dashboard", "Dashboard"),
        ("simpleGeneration", "Simple Generation"),
        ("instructions", "Instructions"),
        ("conversation", "Conversation"),
        ("streaming", "Streaming"),
        ("summarization", "Summarization"),
        ("rewrite", "Rewrite"),
        ("classification", "Classification"),
        ("extraction", "Extraction"),
        ("generable", "Generable"),
        ("guideComparison", "Guide"),
        ("enumGeneration", "Enum"),
        ("nestedObject", "Nested Object"),
        ("dynamicSchema", "Dynamic Schema"),
        ("generationOptions", "Generation Options"),
        ("greedySampling", "Greedy Sampling"),
        ("basicTool", "Basic Tool"),
        ("searchTool", "Search Tool"),
        ("multipleTools", "Multiple Tools"),
        ("multiStepTool", "Multi-step Tool"),
        ("sideEffectTool", "Side Effect Tool"),
        ("imageDescription", "Photo Description"),
        ("imageClassification", "Photo Classification"),
        ("compareImages", "Compare Photos"),
        ("structuredVision", "Structured Vision"),
        ("ocr", "OCR"),
        ("barcode", "Barcode"),
        ("videoAnalysis", "Video Analysis"),
        ("camera", "Camera Frame"),
        ("liveCamera", "Live Camera"),
        ("visionTool", "Vision + Tool"),
        ("transcript", "Transcript"),
        ("restore", "Session Restore"),
        ("tokenCount", "Token Count"),
        ("contextWindow", "Context Window"),
        ("contextExceeded", "Context Exceeded"),
        ("chunking", "Chunking"),
        ("historyTransform", "History Transform"),
        ("prewarm", "Prewarm"),
        ("pcc", "PCC"),
        ("modelComparison", "Model Comparison"),
        ("reasoning", "Reasoning Level"),
        ("quota", "Quota"),
        ("dynamicInstructions", "Dynamic Instructions"),
        ("dynamicProfile", "Dynamic Profile"),
        ("profileVisualizer", "Profile Visualizer"),
        ("toolVisibility", "Tool Visibility"),
        ("sessionProperty", "Session Property"),
        ("lifecycleEvents", "Lifecycle Events"),
        ("agentWorkflow", "Agent Workflow"),
        ("visionAgent", "Vision Agent"),
        ("capabilities", "Capabilities"),
        ("customModel", "Custom Model"),
        ("modelSwitch", "Model Switch"),
        ("errorLab", "Error Lab"),
        ("logs", "Logs"),
        ("apiReference", "API Reference"),
        ("playground", "Foundation Models Playground")
    ]

    override func setUpWithError() throws {
        // 1件失敗しても掃引を止めない。
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testEveryDemoRunsAndReportsOutput() throws {
        XCTAssertEqual(Self.demos.count, 58, "デモ一覧の件数が想定と違う")

        var lines: [String] = []
        for demo in Self.demos {
            let line = sweep(demo)
            lines.append(line)
            // xcodebuild のログから拾えるように 1 行で出す。
            print("SWEEP|\(line)")
        }

        let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
        attachment.name = "all-demos-sweep"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertEqual(app.state, .runningForeground, "掃引中にアプリが落ちた")
    }

    // MARK: - 1デモ分

    private func sweep(_ demo: (id: String, title: String)) -> String {
        guard open(demo) else { return "\(demo.id)|OPEN_FAILED|-" }
        guard tapRun() else { return "\(demo.id)|NO_RUN_BUTTON|-" }
        waitForRunToFinish()

        let output = captureOutputSection()
        let status = hasError() ? "ERROR" : (output.isEmpty ? "EMPTY" : "OK")
        return "\(demo.id)|\(status)|\(output)"
    }

    // MARK: - Navigation（失敗しても XCTFail せず false を返す）

    private func open(_ demo: (id: String, title: String)) -> Bool {
        guard backToList() else { return false }

        let search = app.searchFields.firstMatch
        guard search.waitForExistence(timeout: 10) else { return false }
        clearSearch()
        search.tap()
        search.typeText(demo.title)
        if app.keyboards.count > 0 { search.typeText("\n") }

        let query = app.descendants(matching: .any).matching(identifier: "demo.\(demo.id)")
        guard waitForRow(query, timeout: 8) else { return false }

        let detailBar = app.navigationBars[demo.title]
        for attempt in 0..<3 {
            nudgeIntoSafeBand(query)
            guard let row = resolvedRow(query) else { continue }
            row.tap()
            if detailBar.waitForExistence(timeout: 8) { return true }
            if attempt < 2 { _ = backToList() }
        }
        return false
    }

    @discardableResult
    private func backToList() -> Bool {
        if isOnList { return true }
        for _ in 0..<4 {
            let back = app.navigationBars.buttons.firstMatch
            if back.exists, back.isHittable { back.tap() }
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if isOnList { return true }
                usleep(200_000)
            }
        }
        return isOnList
    }

    private var isOnList: Bool {
        app.searchFields.firstMatch.exists && app.collectionViews.firstMatch.exists
    }

    private func clearSearch() {
        let search = app.searchFields.firstMatch
        guard search.exists else { return }
        let clearButton = search.buttons.firstMatch
        if clearButton.exists, clearButton.isHittable { clearButton.tap() }
    }

    private func waitForRow(_ query: XCUIElementQuery, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count > 0 { return true }
            usleep(200_000)
        }
        return false
    }

    private func resolvedRow(_ query: XCUIElementQuery) -> XCUIElement? {
        guard query.count > 0 else { return nil }
        let row = query.element(boundBy: 0)
        return row.exists ? row : nil
    }

    private func nudgeIntoSafeBand(_ query: XCUIElementQuery, maxSwipes: Int = 6) {
        let list = app.collectionViews.firstMatch
        for _ in 0..<maxSwipes {
            guard let row = resolvedRow(query) else { return }
            if isSafelyTappable(row) { return }
            if row.frame.midY < app.frame.midY { list.swipeDown() } else { list.swipeUp() }
        }
    }

    private func isSafelyTappable(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let screen = app.frame
        return element.frame.minY > screen.minY + 120 && element.frame.maxY < screen.maxY - 140
    }

    // MARK: - Run

    private func tapRun() -> Bool {
        let button = app.buttons["action.run"].firstMatch
        guard scrollTo(button, maxSwipes: 10) else { return false }
        // exists だけでは足りない。Options が長い画面ではボタンが画面外にあり
        // isHittable が false になるので、押せる位置まで送る。
        for _ in 0..<12 {
            if button.isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.80))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.30))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        guard button.isHittable else { return false }
        button.tap()
        return true
    }

    /// 実行中は Run ボタンが disabled になる。有効に戻るまで待つ。
    private func waitForRunToFinish(timeout: TimeInterval = 150) {
        let button = app.buttons["action.run"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        // まず disabled になるのを少し待つ（即座に終わるデモもあるので短く）
        let startDeadline = Date().addingTimeInterval(2)
        while Date() < startDeadline {
            if button.exists, !button.isEnabled { break }
            usleep(100_000)
        }
        while Date() < deadline {
            if button.exists, button.isEnabled { return }
            usleep(300_000)
        }
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 16) -> Bool {
        if element.exists { return true }
        for _ in 0..<maxSwipes {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.80))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.22))
            start.press(forDuration: 0.05, thenDragTo: end)
            if element.exists { return true }
        }
        return element.exists
    }

    // MARK: - Output 回収

    private func outputSection() -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "section.output").firstMatch
    }

    private func hasError() -> Bool {
        outputSection().staticTexts["Technical Detail"].exists
    }

    private func captureOutputSection() -> String {
        let section = outputSection()
        guard section.waitForExistence(timeout: 5) else { return "" }
        let texts = section.descendants(matching: .staticText)
        var parts: [String] = []
        let limit = min(texts.count, 14)
        for index in 0..<limit {
            let label = texts.element(boundBy: index).label
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if !label.isEmpty { parts.append(label) }
        }
        let joined = parts.joined(separator: " / ")
        return String(joined.prefix(300))
    }
}
