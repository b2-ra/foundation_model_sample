//
//  PromptEvaluationTests.swift
//  foundation_model_sampleTests
//
//  Prompt Evaluation。
//  Apple の「Evaluating prompts to measure performance and improve model responses」は、
//  曖昧な品質目標を測定可能な基準へ落として繰り返し実行することを求めている。
//  ここでは TEXT / STRUCTURED OUTPUT / TOOLS の各デモを実際にモデルへ通し、
//  「文章の完全一致」ではなく次の測定可能な基準で判定する。
//
//    - 生成が成功したか（例外にならず、result.error が付かないか）
//    - モデル経路を通ったか（executionMode == .foundationModels）
//    - 指示した言語（日本語）で返ってきたか
//    - スキーマ制約（@Guide の range / enum のケース）に収まっているか
//    - Tool が呼ばれ、その出力が最終応答に反映されているか
//
//  Apple の Evaluations フレームワークは iOS 27 / Xcode 27 beta で導入されたもので、
//  このプロジェクトの iOS 26.5 では使えない。同じ考え方を Swift Testing で実装している。
//
//  Apple Intelligence が無効な環境では skip する（pass にはしない）。
//

import Testing
import Foundation
import FoundationModels
@testable import foundation_model_sample

// MARK: - 共通の測定関数

/// 日本語（ひらがな・カタカナ・漢字）を含むか。「必ず日本語で答えてください」の検証に使う。
private func containsJapanese(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        switch scalar.value {
        case 0x3040...0x30FF, 0x4E00...0x9FFF: true
        default: false
        }
    }
}

@MainActor
private func runAndMeasure(_ demo: LabDemo, prompt: String? = nil) async throws -> LabEngine {
    let engine = LabEngine()
    engine.activate(demo)
    if let prompt { engine.prompt = prompt }

    try await engine.runDemo(demo)

    #expect(engine.result.error == nil,
            "\(demo.rawValue): エラーで終わった: \(engine.result.error?.technicalDetail ?? "-")")
    #expect(engine.result.executionMode == .foundationModels,
            "\(demo.rawValue): モデル経路を通っていない (\(engine.result.executionMode))")
    #expect(!engine.result.payload.isEmpty, "\(demo.rawValue): 出力が空")
    return engine
}

/// payload から構造化フィールドを取り出す。取れなければテスト失敗。
private func structuredFields(
    of engine: LabEngine,
    _ context: String,
    sourceLocation: SourceLocation = #_sourceLocation
) -> (fields: [StructuredField], json: String)? {
    guard case .structured(let fields, let json) = engine.result.payload else {
        Issue.record("\(context): payload が structured ではない (\(engine.result.payload))",
                     sourceLocation: sourceLocation)
        return nil
    }
    return (fields, json)
}

// MARK: - TEXT

@MainActor
struct TextPromptEvaluationTests {

    @Test("Simple Generation が日本語の文章を返す", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func simpleGenerationReturnsJapaneseProse() async throws {
        let engine = try await runAndMeasure(.simpleGeneration)

        guard case .text(let text) = engine.result.payload else {
            Issue.record("payload が text ではない (\(engine.result.payload))")
            return
        }
        // 「石川県の特徴を100文字程度で説明してください。」に対する測定可能な基準。
        #expect(text.count >= 20, "応答が短すぎる: \(text.count) 文字")
        #expect(containsJapanese(text), "日本語で返っていない: \(text.prefix(80))")
        #expect((engine.result.metrics.responseTokens ?? 0) > 0, "responseTokens が測れていない")
    }

    @Test("Streaming の最終結果が途中結果と矛盾しない", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func streamingFinalResultIsComplete() async throws {
        let engine = LabEngine()
        engine.activate(.streaming)

        var partials: [String] = []
        let (text, _) = try await engine.stream(engine.prompt) { partials.append($0) }

        #expect(!partials.isEmpty, "部分応答が1件も届いていない")
        #expect(!text.isEmpty, "最終結果が空")
        #expect(containsJapanese(text), "日本語で返っていない")
        // Snapshot は差分ではなく「その時点までの全文」なので、途中結果は単調に伸びる。
        for (previous, next) in zip(partials, partials.dropFirst()) {
            #expect(next.count >= previous.count, "途中結果が短くなっている（差分として扱っている疑い）")
        }
        // collect() の結果が、最後の Snapshot を切り詰めていない。
        #expect(text.count >= (partials.last?.count ?? 0),
                "collect() の結果が最後の Snapshot より短い")
        #expect(engine.result.metrics.firstTokenAt != nil, "First Token の時刻が記録されていない")
    }

    @Test("Summarization が原文より短い要約を返す", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func summarizationIsShorterThanSource() async throws {
        let engine = try await runAndMeasure(.summarization)
        guard let (fields, json) = structuredFields(of: engine, "Summarization") else { return }

        let summary = fields.flatMap { [$0.value] + $0.children.map(\.value) }.joined()
        #expect(!summary.isEmpty, "要約が空")
        #expect(containsJapanese(summary), "日本語で返っていない")
        // 測定可能な基準: 3行要約は原文の半分より短い。
        #expect(summary.count < engine.longText.count / 2,
                "要約が原文の半分より長い（\(summary.count) 文字 / 原文 \(engine.longText.count) 文字）")
        #expect(!json.isEmpty, "rawContent の JSON が空")
    }

    @Test("Classification が enum のケースに収まり、障害を障害と判定する", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func classificationStaysInEnumAndIsCorrect() async throws {
        // 「ログイン画面から進まなくなった」= 障害。分類として揺れる余地が小さい入力を選んでいる。
        let engine = try await runAndMeasure(.classification, prompt: DemoData.classificationSample)
        guard let (fields, _) = structuredFields(of: engine, "Classification") else { return }

        let allowed = SupportCategory.allCases.map(\.rawValue)
        let categoryField = fields.first { $0.label.lowercased().contains("category") } ?? fields[0]
        let matched = allowed.filter { categoryField.value.contains($0) }
        #expect(matched.count == 1, "enum のケースに収まっていない: \(categoryField.value)")
        #expect(matched.first == SupportCategory.bug.rawValue,
                "障害の問い合わせが \(matched.first ?? "-") に分類された")
    }

    @Test("Extraction が入力に無い語を作らない", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func extractionStaysGroundedInInput() async throws {
        let engine = try await runAndMeasure(.extraction)
        guard let (fields, _) = structuredFields(of: engine, "Extraction") else { return }

        let extracted = fields.flatMap { $0.children.map(\.value) }
        #expect(!extracted.isEmpty, "抽出結果が空")
        // 測定可能な基準: 抽出された語は原文に現れている（ハルシネーションの検出）。
        let source = engine.entityText
        let invented = extracted.filter { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed != "（なし）" && !source.contains(trimmed)
        }
        #expect(invented.isEmpty, "原文に無い語が抽出された: \(invented)")
    }
}

// MARK: - STRUCTURED OUTPUT

@MainActor
struct StructuredOutputPromptEvaluationTests {

    @Test("Generable がすべてのフィールドを埋め、@Guide の範囲に収まる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func generableFillsEveryFieldWithinGuides() async throws {
        let engine = try await runAndMeasure(.generable)
        guard let (fields, json) = structuredFields(of: engine, "Generable") else { return }

        #expect(fields.count == 6, "Prescription の6フィールドが揃っていない: \(fields.count)")
        for field in fields {
            #expect(!field.value.trimmingCharacters(in: .whitespaces).isEmpty, "\(field.label) が空")
        }
        // @Guide(.range(1...6)) / .range(1...180) がスキーマ制約として効いていること。
        if let frequency = fields.first(where: { $0.label == "frequency" }).flatMap({ Int($0.value) }) {
            #expect((1...6).contains(frequency), "frequency が @Guide の範囲外: \(frequency)")
        } else {
            Issue.record("frequency が Int として取れない")
        }
        if let days = fields.first(where: { $0.label == "days" }).flatMap({ Int($0.value) }) {
            #expect((1...180).contains(days), "days が @Guide の範囲外: \(days)")
        } else {
            Issue.record("days が Int として取れない")
        }
        // rawContent の JSON が JSON として妥当。
        let data = try #require(json.data(using: .utf8))
        #expect(throws: Never.self) { try JSONSerialization.jsonObject(with: data) }
    }

    @Test("Enum 生成が許可されたケースだけを返す", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func enumGenerationPicksAllowedCase() async throws {
        let engine = try await runAndMeasure(.enumGeneration, prompt: DemoData.classificationSample)
        guard let (fields, _) = structuredFields(of: engine, "Enum") else { return }

        let selected = try #require(fields.first, "フィールドが空")
        let allowed = SupportCategory.allCases.map(\.rawValue)
        #expect(allowed.contains { selected.value.contains($0) },
                "enum のケース外の値が返った: \(selected.value)")
        // 選択されたケースが1件だけ印されている。
        #expect(fields.filter { $0.label == "● selected" }.count == 1, "選択されたケースが1件でない")
    }

    @Test("Nested Object が入れ子のまま返る", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func nestedObjectKeepsHierarchy() async throws {
        let engine = try await runAndMeasure(.nestedObject)
        guard let (fields, json) = structuredFields(of: engine, "Nested Object") else { return }

        #expect(fields.contains { !$0.children.isEmpty }, "入れ子のフィールドが無い")
        let data = try #require(json.data(using: .utf8))
        #expect(throws: Never.self) { try JSONSerialization.jsonObject(with: data) }
    }

    @Test("Guide 比較で制約ありの側が範囲に収まる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func guidedSideRespectsRange() async throws {
        let engine = LabEngine()
        engine.activate(.guideComparison)
        try await engine.runDemo(.guideComparison)

        guard case .comparison(let columns) = engine.result.payload else {
            Issue.record("payload が comparison ではない (\(engine.result.payload))")
            return
        }
        #expect(columns.count == 2, "Guide あり / なしの2列になっていない")
        // Guide あり側は生成できていなければならない（なし側は失敗が主旨なので問わない）。
        let guided = try #require(columns.first)
        #expect(!guided.body.isEmpty, "Guide あり側の出力が空")
        // score は 0...100 に収まる。
        let numbers = guided.body.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        #expect(numbers.allSatisfy { (0...100).contains($0) },
                "Guide あり側に 0...100 の範囲外の値がある: \(numbers)")
    }

    @Test("Dynamic Schema が指定したフィールドを返す", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func dynamicSchemaReturnsRequestedFields() async throws {
        let engine = try await runAndMeasure(.dynamicSchema)
        guard let (fields, _) = structuredFields(of: engine, "Dynamic Schema") else { return }

        let produced = Set(fields.flatMap { [$0.label] + $0.children.map(\.label) })
        for field in engine.schemaFields {
            #expect(produced.contains { $0.contains(field.name) },
                    "動的スキーマで定義した \(field.name) が出力に無い: \(produced)")
        }
    }
}

// MARK: - TOOLS

@MainActor
struct ToolPromptEvaluationTests {

    @Test("Basic Tool が呼ばれ、その値が応答に現れる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func basicToolIsCalledAndUsed() async throws {
        // 「金沢は何度？」→ getWeather（固定データで 26 度）
        let engine = try await runAndMeasure(.basicTool, prompt: "金沢は何度？")

        let called = engine.toolLog.map(\.toolName)
        #expect(called.contains("getWeather"), "getWeather が呼ばれていない: \(called)")
        #expect(engine.toolLog.allSatisfy { $0.finishedAt != nil }, "終了していない Tool 呼び出しがある")
        #expect(engine.toolLog.allSatisfy { !$0.failed }, "失敗した Tool 呼び出しがある")
        // Tool の出力が最終応答に反映されている。
        #expect(engine.result.payload.plainText.contains("26"),
                "Tool が返した気温が応答に現れていない: \(engine.result.payload.plainText.prefix(200))")
    }

    @Test("Search Tool が呼ばれ、辞書の薬効が応答に現れる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func searchToolGroundsAnswerInDatabase() async throws {
        let engine = try await runAndMeasure(.searchTool, prompt: "アムロジピンの薬効を教えて")

        let called = engine.toolLog.map(\.toolName)
        #expect(called.contains("searchDrug"), "searchDrug が呼ばれていない: \(called)")
        let output = engine.result.payload.plainText
        #expect(output.contains("Ca拮抗薬") || output.contains("血圧"),
                "辞書の薬効が応答に反映されていない: \(output.prefix(200))")
    }

    @Test("複数 Tool から在庫質問に合う Tool が選ばれる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func multipleToolsSelectsInventory() async throws {
        let engine = try await runAndMeasure(.multipleTools, prompt: "アムロジピン5mgの在庫はいくつ？")

        let called = engine.toolLog.map(\.toolName)
        #expect(called.contains("checkInventory"), "checkInventory が選ばれていない: \(called)")
        #expect(engine.result.payload.plainText.contains("80"),
                "在庫数が応答に現れていない: \(engine.result.payload.plainText.prefix(200))")
    }

    @Test("Multi-step Tool が複数の Tool を順に呼ぶ", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func multiStepToolChainsCalls() async throws {
        let engine = try await runAndMeasure(.multiStepTool)

        let called = engine.toolLog.map(\.toolName)
        #expect(called.count >= 2, "複数段の Tool 呼び出しになっていない: \(called)")
        #expect(Set(called).count >= 2, "同じ Tool しか呼ばれていない: \(called)")
    }

    @Test("副作用 Tool はモデルだけでは在庫を変更しない", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func sideEffectToolOnlyRequestsApproval() async throws {
        let engine = LabEngine()
        engine.activate(.sideEffectTool)
        let before = engine.inventory.all.map(\.stock)

        try await engine.runDemo(.sideEffectTool)

        #expect(engine.result.error == nil,
                "エラーで終わった: \(engine.result.error?.technicalDetail ?? "-")")
        // 在庫は1つも動いていない。
        #expect(engine.inventory.all.map(\.stock) == before, "モデル呼び出しだけで在庫が変わった")
        // 申請が承認待ちとして積まれている。
        #expect(!engine.pendingSideEffects.isEmpty, "承認待ちの申請が作られていない")
        #expect(engine.toolLog.map(\.toolName).contains("requestInventoryUpdate"),
                "requestInventoryUpdate が呼ばれていない: \(engine.toolLog.map(\.toolName))")
    }
}
