//
//  OptionMatrixEvaluationTests.swift
//  foundation_model_sampleTests
//
//  TEXT / STRUCTURED OUTPUT / TOOLS の全デモを、
//  「プリセットではない自作の入力」と「オプションの各値」で実行して結果を確認する。
//
//  見るのは文章の一致ではなく、次の測定可能な基準（Apple の Prompt Evaluation の考え方）:
//    - 入力に追随しているか（自作入力に仕込んだ語・数値が結果に現れるか）
//    - 入力に無い値を作っていないか
//    - オプションを変えたとき、出力の形や設定表示がそれに追随するか
//    - スキーマ制約（@Guide の range / enum のケース / 動的スキーマの項目名）に収まっているか
//    - Tool が呼ばれ、その戻り値が最終応答に反映されているか
//
//  Apple Intelligence が無効な環境では skip する（pass にしない）。
//

import Testing
import Foundation
import FoundationModels
@testable import foundation_model_sample

// MARK: - 自作入力（プリセットと重複しないよう、すべてこのファイル固有の文にしている）

private enum Original {
    /// 要約 / チャンキング用の長文。仕込んだ事実: 加賀棒茶 / 焙煎温度180度 / 出荷は5月 / 3代目の中村。
    static let longText = """
    加賀棒茶は茶葉ではなく茎を焙煎して作る番茶で、金沢では日常的に飲まれています。\
    焙煎温度は180度前後が目安で、これより高いと香りが飛び、低いと青臭さが残ります。\
    茎は一番茶の摘採後に選別され、乾燥させたうえで浅く炒ることで澄んだ琥珀色になります。\
    3代目の中村が戦後に確立した製法が今の標準で、湯温は90度、浸出時間は30秒が推奨されています。\
    新茶の出荷は5月に始まり、夏場は水出しでも飲まれます。\
    茎茶は葉茶よりカフェインが少ないため、就寝前や子どもにも供されることがあります。
    """

    /// 抽出用の業務メモ。仕込んだ実体: 高橋七海 / 小松次郎 / ラベルシール / 12箱 / 5月8日。
    static let extractionMemo = "高橋七海さんが5月8日にラベルシールを12箱、レジロールを4本発注しました。検品は小松次郎さんが担当します。"

    /// 構造化出力用の処方文。単値フィールドへ入るので薬剤名を含めても通る（Extraction の実測参照）。
    static let prescription = "佐々木さんにメトホルミン250mgを1日2回朝夕食後14日分"

    /// 入れ子構造用。患者1人 + 薬2件。
    static let nested = "鈴木一郎さん(72歳、P003)にメトホルミン250mgを1日2回朝夕食後30日分、ランソプラゾール15mgを就寝前1錠30日分を出します。"

    /// 書き換え用の元文。
    static let rewriteSource = "明日の納品は無理です。倉庫の棚卸しが終わってないので手が回りません。"

    /// 分類用。4カテゴリそれぞれに対応する自作入力。
    static let classification: [(text: String, expected: SupportCategory)] = [
        ("更新後にアプリを開くと在庫画面が真っ白のままで、何度再起動しても直りません。", .bug),
        ("棚卸しの締め日を月末から20日に変える設定はどこで行いますか。", .operation),
        ("発注履歴をPDFで書き出せる機能を追加してほしいです。", .request),
        ("来期から店舗を2つ増やすので、契約プランの変更手続きを教えてください。", .contract)
    ]
}

private func containsJapanese(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        switch scalar.value {
        case 0x3040...0x30FF, 0x4E00...0x9FFF: true
        default: false
        }
    }
}

@MainActor
private func fields(_ engine: LabEngine, _ context: String,
                    sourceLocation: SourceLocation = #_sourceLocation) -> [StructuredField]? {
    guard case .structured(let fields, _) = engine.result.payload else {
        Issue.record("\(context): payload が structured ではない (\(engine.result.payload))",
                     sourceLocation: sourceLocation)
        return nil
    }
    return fields
}

@MainActor
private func columns(_ engine: LabEngine, _ context: String,
                     sourceLocation: SourceLocation = #_sourceLocation) -> [ComparisonColumn]? {
    guard case .comparison(let columns) = engine.result.payload else {
        Issue.record("\(context): payload が comparison ではない (\(engine.result.payload))",
                     sourceLocation: sourceLocation)
        return nil
    }
    return columns
}

@MainActor
private func expectSucceeded(_ engine: LabEngine, _ context: String,
                             sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(engine.result.error == nil,
            "\(context): エラーで終わった: \(engine.result.error?.technicalDetail ?? "-")",
            sourceLocation: sourceLocation)
    #expect(engine.result.executionMode == .foundationModels,
            "\(context): モデル経路を通っていない (\(engine.result.executionMode))",
            sourceLocation: sourceLocation)
    #expect(!engine.result.payload.isEmpty, "\(context): 出力が空", sourceLocation: sourceLocation)
}

/// すべてのフィールド値（入れ子含む）を平坦に集める。
private func allValues(_ fields: [StructuredField]) -> [String] {
    fields.flatMap { [$0.value] + allValues($0.children) }
}

// MARK: - TEXT

@MainActor
struct TextOptionMatrixTests {

    @Test("Simple Generation が自作プロンプトの主題に沿って答える", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func simpleGenerationFollowsOriginalPrompt() async throws {
        let engine = LabEngine()
        engine.activate(.simpleGeneration)
        engine.prompt = "加賀棒茶とはどんなお茶か、80文字程度で説明してください。"

        try await engine.runDemo(.simpleGeneration)
        expectSucceeded(engine, "Simple Generation")

        let text = engine.result.payload.plainText
        #expect(containsJapanese(text), "日本語で返っていない")
        #expect(text.contains("茶"), "プロンプトの主題（お茶）に触れていない: \(text.prefix(120))")
        #expect(text.count >= 20, "応答が短すぎる: \(text.count) 文字")
    }

    @Test("Instructions を自作の文に変えると応答がそれに従う", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func instructionsChangeTheAnswer() async throws {
        let engine = LabEngine()
        engine.activate(.instructions)
        engine.prompt = "会議室の予約方法を2文で説明してください。"
        engine.instructions = """
            あなたは社内総務の担当者です。回答の最後を必ず「以上、手順を確認してください。」という一文で終えてください。
            必ず日本語で答えてください。
            """

        try await engine.runDemo(.instructions)
        expectSucceeded(engine, "Instructions")

        guard let columns = columns(engine, "Instructions"), columns.count == 2 else { return }
        // Instructions あり側は指示した締めの文を守る。
        #expect(columns[0].body.contains("手順を確認"),
                "Instructions で指定した締めの文が出ていない: \(columns[0].body.suffix(60))")
        // なし側には現れない（= Instructions が効いていることの対照）。
        #expect(!columns[1].body.contains("手順を確認"),
                "Instructions なし側にも締めの文が出ている（比較になっていない）")
    }

    @Test("Conversation が同じセッションで自作の名前を覚える", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func conversationRemembersOriginalName() async throws {
        let engine = LabEngine()
        engine.activate(.conversation)

        engine.prompt = "私の名前をハヤトとして覚えてください。"
        try await engine.runDemo(.conversation)
        expectSucceeded(engine, "Conversation 1ターン目")

        engine.prompt = "私の名前は？"
        try await engine.runDemo(.conversation)
        expectSucceeded(engine, "Conversation 2ターン目")

        #expect(engine.result.payload.plainText.contains("ハヤト"),
                "前のターンで渡した名前を保持していない: \(engine.result.payload.plainText.prefix(120))")
        #expect(engine.transcriptEntries.count >= 4, "Transcript に2往復分が積まれていない")
    }

    @Test("Streaming が自作プロンプトで途中結果と最終結果を返す", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func streamingWithOriginalPrompt() async throws {
        let engine = LabEngine()
        engine.activate(.streaming)
        engine.prompt = "能登ヒノキの特徴を100文字程度で説明してください。"

        var partials: [String] = []
        let (text, _) = try await engine.stream(engine.prompt) { partials.append($0) }

        #expect(!partials.isEmpty, "途中結果が届いていない")
        #expect(containsJapanese(text), "日本語で返っていない")
        for (previous, next) in zip(partials, partials.dropFirst()) {
            #expect(next.count >= previous.count, "途中結果が短くなっている")
        }
        #expect(text.count >= (partials.last?.count ?? 0), "collect() の結果が最後の Snapshot より短い")
    }

    @Test("Summarization の4つのスタイルすべてが自作長文を要約する", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func summarizationCoversEveryStyle() async throws {
        for style in SummaryStyle.allCases {
            let engine = LabEngine()
            engine.activate(.summarization)
            engine.longText = Original.longText
            engine.summaryStyle = style

            try await engine.runDemo(.summarization)
            expectSucceeded(engine, "Summarization(\(style.rawValue))")

            guard let fields = fields(engine, "Summarization(\(style.rawValue))") else { continue }
            let values = allValues(fields).filter { !$0.hasSuffix("件") }
            let summary = values.joined(separator: " ")

            #expect(!summary.isEmpty, "\(style.rawValue): 要約が空")
            #expect(containsJapanese(summary), "\(style.rawValue): 日本語で返っていない")
            // 自作長文の主題に追随している。
            #expect(summary.contains("茶"), "\(style.rawValue): 自作長文の主題が要約に出ていない: \(summary.prefix(120))")
            // 原文より十分短い。複数行・箇条書き・100文字要約は構造上120文字前後まで振れる。
            #expect(summary.count < Original.longText.count * 2 / 3,
                    "\(style.rawValue): 要約が原文の3分の2より長い（\(summary.count) 文字）")

            // スタイルごとに出力の形が変わる。
            switch style {
            case .oneLine, .hundredCharacters:
                #expect(values.count == 1, "\(style.rawValue): 1件のはずが \(values.count) 件")
                if style == .hundredCharacters {
                    #expect((80...140).contains(summary.count),
                            "\(style.rawValue): 100文字程度の範囲外（\(summary.count) 文字）")
                }
            case .threeLines:
                #expect(values.count == 3, "\(style.rawValue): 3件のはずが \(values.count) 件")
            case .bullets:
                #expect((1...5).contains(values.count), "\(style.rawValue): 箇条書きが1〜5件でない（\(values.count) 件）")
            }
        }
    }

    @Test("Rewrite の6つのスタイルすべてが自作の文を書き換える", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func rewriteCoversEveryStyle() async throws {
        var rewritten: [RewriteStyle: String] = [:]

        for style in RewriteStyle.allCases {
            let engine = LabEngine()
            engine.activate(.rewrite)
            engine.prompt = Original.rewriteSource
            engine.rewriteStyle = style

            try await engine.runDemo(.rewrite)
            expectSucceeded(engine, "Rewrite(\(style.rawValue))")

            guard let columns = columns(engine, "Rewrite(\(style.rawValue))"), columns.count == 2 else { continue }
            #expect(columns[0].body == Original.rewriteSource, "\(style.rawValue): Original 列が自作入力と違う")
            let result = columns[1].body
            #expect(!result.isEmpty, "\(style.rawValue): 書き換え結果が空")
            #expect(result != Original.rewriteSource, "\(style.rawValue): 書き換えられていない")
            #expect(containsJapanese(result), "\(style.rawValue): 日本語で返っていない")
            // 意味を変えないので、元の主題（納品 / 棚卸し）のどちらかは残る。
            #expect(result.contains("納品") || result.contains("棚卸"),
                    "\(style.rawValue): 元の内容から離れている: \(result.prefix(100))")
            rewritten[style] = result
        }

        // 「短くする」は元より短くなる。
        if let shorter = rewritten[.shorter] {
            #expect(shorter.count <= Original.rewriteSource.count,
                    "shorter が元文より長い（\(shorter.count) > \(Original.rewriteSource.count)）")
        }
        // スタイルごとに結果が変わる（全部同じ文なら分岐が効いていない）。
        #expect(Set(rewritten.values).count >= 3,
                "6スタイルで異なる結果が3種類未満。スタイル指定が効いていない疑い")
    }

    @Test("Classification が自作入力4件を正しいカテゴリに分ける", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func classificationHandlesEveryCategory() async throws {
        for sample in Original.classification {
            let engine = LabEngine()
            engine.activate(.classification)
            engine.prompt = sample.text

            try await engine.runDemo(.classification)
            expectSucceeded(engine, "Classification(\(sample.expected.rawValue))")

            guard let fields = fields(engine, "Classification(\(sample.expected.rawValue))"),
                  let first = fields.first else { continue }
            let allowed = SupportCategory.allCases.map(\.rawValue)
            let matched = allowed.filter { first.value.contains($0) }
            #expect(matched.count == 1, "enum のケースに収まっていない: \(first.value)")
            #expect(matched.first == sample.expected.rawValue,
                    "「\(sample.text.prefix(20))…」が \(matched.first ?? "-") に分類された（期待 \(sample.expected.rawValue)）")
        }
    }

    @Test("Extraction が自作メモの語だけを抽出する", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func extractionTracksOriginalMemo() async throws {
        let engine = LabEngine()
        engine.activate(.extraction)
        engine.entityText = Original.extractionMemo

        try await engine.runDemo(.extraction)
        expectSucceeded(engine, "Extraction")

        guard let fields = fields(engine, "Extraction") else { return }
        let extracted = fields.flatMap { $0.children.map(\.value) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "（なし）" }

        #expect(!extracted.isEmpty, "抽出結果が空")
        // 仕込んだ実体を拾えている。
        #expect(extracted.contains { $0.contains("高橋") }, "人物名（高橋七海）を拾えていない: \(extracted)")
        #expect(extracted.contains { $0.contains("ラベル") || $0.contains("レジロール") },
                "品名を拾えていない: \(extracted)")
        // 入力に無い語を作っていない。
        let invented = extracted.filter { !Original.extractionMemo.contains($0) }
        #expect(invented.isEmpty, "自作入力に無い語が出た: \(invented)")
    }
}

// MARK: - STRUCTURED OUTPUT

@MainActor
struct StructuredOptionMatrixTests {

    @Test("Generable が自作処方文の値をそのまま構造化する", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func generableTracksOriginalInput() async throws {
        let engine = LabEngine()
        engine.activate(.generable)
        engine.entityText = Original.prescription

        try await engine.runDemo(.generable)
        expectSucceeded(engine, "Generable")

        guard let fields = fields(engine, "Generable") else { return }
        func value(_ label: String) -> String? { fields.first { $0.label == label }?.value }

        #expect(value("medicineName")?.contains("メトホルミン") == true,
                "自作入力の薬剤名が入っていない: \(value("medicineName") ?? "-")")
        #expect(value("patientName")?.contains("佐々木") == true,
                "自作入力の患者名が入っていない: \(value("patientName") ?? "-")")
        // 入力に書いた「1日2回」「14日分」を拾う。
        #expect(value("frequency") == "2", "frequency が入力と違う: \(value("frequency") ?? "-")")
        #expect(value("days") == "14", "days が入力と違う: \(value("days") ?? "-")")
        // @Guide の範囲内。
        if let frequency = value("frequency").flatMap(Int.init) {
            #expect((1...6).contains(frequency), "frequency が @Guide の範囲外")
        }
        if let days = value("days").flatMap(Int.init) {
            #expect((1...180).contains(days), "days が @Guide の範囲外")
        }
    }

    @Test("Enum 生成が自作入力2件で正しいケースを返す", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func enumGenerationTracksOriginalInput() async throws {
        for sample in [Original.classification[0], Original.classification[2]] {
            let engine = LabEngine()
            engine.activate(.enumGeneration)
            engine.prompt = sample.text

            try await engine.runDemo(.enumGeneration)
            expectSucceeded(engine, "Enum(\(sample.expected.rawValue))")

            guard let fields = fields(engine, "Enum(\(sample.expected.rawValue))"),
                  let selected = fields.first else { continue }
            #expect(selected.value.contains(sample.expected.rawValue),
                    "「\(sample.text.prefix(16))…」が \(selected.value) になった（期待 \(sample.expected.rawValue)）")
            #expect(fields.filter { $0.label == "● selected" }.count == 1, "選択されたケースが1件でない")
        }
    }

    @Test("Nested Object が自作入力の患者と薬2件を入れ子で返す", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func nestedObjectTracksOriginalInput() async throws {
        let engine = LabEngine()
        engine.activate(.nestedObject)
        engine.entityText = Original.nested

        try await engine.runDemo(.nestedObject)
        expectSucceeded(engine, "Nested Object")

        guard let fields = fields(engine, "Nested Object") else { return }
        let values = allValues(fields)
        #expect(fields.contains { !$0.children.isEmpty }, "入れ子のフィールドが無い")
        #expect(values.contains { $0.contains("鈴木") }, "自作入力の患者名が入っていない: \(values)")
        #expect(values.contains { $0.contains("メトホルミン") } && values.contains { $0.contains("ランソプラゾール") },
                "自作入力の薬剤2件が入っていない: \(values)")
    }

    @Test("Guide 比較が自作入力でも制約側は範囲に収まる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func guideComparisonWithOriginalInput() async throws {
        let engine = LabEngine()
        engine.activate(.guideComparison)
        engine.prompt = "新しい発注画面は動作が速くて助かりますが、検索の並び順だけ分かりにくいです。"

        try await engine.runDemo(.guideComparison)
        expectSucceeded(engine, "Guide")

        guard let columns = columns(engine, "Guide"), let guided = columns.first else { return }
        #expect(!guided.body.isEmpty, "Guide あり側の出力が空")
        let numbers = guided.body.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        #expect(numbers.allSatisfy { (0...100).contains($0) },
                "Guide あり側に 0...100 の範囲外の値がある: \(numbers)")
    }

    @Test("Dynamic Schema が自作のフィールド定義どおりに生成する", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func dynamicSchemaUsesOriginalFields() async throws {
        let engine = LabEngine()
        engine.activate(.dynamicSchema)
        // 既定の name / age / city を捨てて、自作の項目定義に差し替える。
        engine.schemaFields = [
            SchemaField(name: "itemName", type: .string, fieldDescription: "備品の名称"),
            SchemaField(name: "boxCount", type: .integer, fieldDescription: "発注する箱数"),
            SchemaField(name: "needsReorder", type: .boolean, fieldDescription: "追加発注が必要かどうか")
        ]
        engine.prompt = "ラベルシールを12箱発注したい。在庫は残り1箱なので追加発注も必要。"

        try await engine.runDemo(.dynamicSchema)
        expectSucceeded(engine, "Dynamic Schema")

        guard let fields = fields(engine, "Dynamic Schema") else { return }
        let labels = fields.flatMap { [$0.label] + $0.children.map(\.label) }
        for field in engine.schemaFields {
            #expect(labels.contains { $0.contains(field.name) },
                    "自作フィールド \(field.name) が出力に無い: \(labels)")
        }
        // 型どおりの値になっている。
        let values = Dictionary(uniqueKeysWithValues: fields.map { ($0.label, $0.value) })
        if let boxCount = values["boxCount"] {
            #expect(Int(boxCount) != nil, "boxCount が Int になっていない: \(boxCount)")
            #expect(Int(boxCount) == 12, "自作入力の箱数(12)が反映されていない: \(boxCount)")
        }
        if let needsReorder = values["needsReorder"] {
            #expect(["true", "false"].contains(needsReorder.lowercased()),
                    "needsReorder が Bool になっていない: \(needsReorder)")
        }
    }

    @Test("Generation Options の4つの sampling すべてで実行でき、設定が表示に出る", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func generationOptionsCoversEverySampling() async throws {
        for choice in SamplingChoice.allCases {
            let engine = LabEngine()
            engine.activate(.generationOptions)
            engine.prompt = "町家を改装した和菓子店のキャッチコピーを1つ作ってください。"
            engine.samplingChoice = choice
            engine.temperature = 0.4
            engine.maximumResponseTokens = 200

            try await engine.runDemo(.generationOptions)
            expectSucceeded(engine, "Generation Options(\(choice.rawValue))")

            guard let columns = columns(engine, "Generation Options(\(choice.rawValue))") else { continue }
            #expect(columns.count == 3, "\(choice.rawValue): 3列の比較になっていない")
            #expect(columns.allSatisfy { !$0.body.isEmpty }, "\(choice.rawValue): 空の列がある")
            // 画面の設定を使う列に、選んだ sampling と temperature が出る。
            let mine = columns[1]
            let expectedSampling = switch choice {
            case .automatic: "sampling: automatic"
            case .greedy: "sampling: greedy"
            case .topK, .threshold: "sampling: random"
            }
            #expect(mine.subtitle?.contains(expectedSampling) == true,
                    "\(choice.rawValue): 選んだ sampling が設定表示に出ていない: \(mine.subtitle ?? "-")")
            #expect(mine.subtitle?.contains("temperature: 0.40") == true,
                    "\(choice.rawValue): 指定した temperature が設定表示に出ていない: \(mine.subtitle ?? "-")")
            #expect(mine.subtitle?.contains("maxTokens: 200") == true,
                    "\(choice.rawValue): 指定した maximumResponseTokens が設定表示に出ていない: \(mine.subtitle ?? "-")")
        }
    }

    @Test("Greedy Sampling が自作プロンプトで揺れないことを実測する", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func greedySamplingIsDeterministic() async throws {
        let engine = LabEngine()
        engine.activate(.greedySampling)
        engine.prompt = "在庫管理アプリの利点を1文で述べてください。"

        try await engine.runDemo(.greedySampling)
        expectSucceeded(engine, "Greedy Sampling")

        guard let columns = columns(engine, "Greedy Sampling"), columns.count == 2 else { return }
        let greedyUnique = columns[0].footnotes.first { $0.label == "3回中の異なる出力数" }?.value
        #expect(greedyUnique == "1",
                "greedy が3回で揺れた（異なる出力数 \(greedyUnique ?? "-")）。決定的でなくなっている")
        #expect(columns[0].footnotes.first { $0.label == "モデル側で停止した回" }?.value == "0 / 3",
                "greedy 側で停止が発生した")
    }
}

// MARK: - TOOLS

@MainActor
struct ToolOptionMatrixTests {

    @Test("Basic Tool が自作プロンプトの都市で呼ばれる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func basicToolUsesOriginalCity() async throws {
        let engine = LabEngine()
        engine.activate(.basicTool)
        engine.prompt = "那覇は今何度ですか？"

        try await engine.runDemo(.basicTool)
        expectSucceeded(engine, "Basic Tool")

        let called = engine.toolLog
        #expect(called.map(\.toolName).contains("getWeather"), "getWeather が呼ばれていない: \(called.map(\.toolName))")
        #expect(called.contains { $0.arguments.contains("那覇") }, "自作プロンプトの都市が引数に渡っていない: \(called.map(\.arguments))")
        // 固定データの 32℃ が最終応答に反映される。
        #expect(engine.result.payload.plainText.contains("32"),
                "Tool の戻り値（32℃）が応答に出ていない: \(engine.result.payload.plainText.prefix(200))")
        #expect(called.allSatisfy { !$0.failed }, "失敗した Tool 呼び出しがある")
    }

    @Test("Search Tool が自作プロンプトの薬の注意点を辞書から返す", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func searchToolUsesOriginalDrug() async throws {
        let engine = LabEngine()
        engine.activate(.searchTool)
        engine.prompt = "レボフロキサシン500mgを飲むときに気をつけることは？"

        try await engine.runDemo(.searchTool)
        expectSucceeded(engine, "Search Tool")

        #expect(engine.toolLog.map(\.toolName).contains("searchDrug"),
                "searchDrug が呼ばれていない: \(engine.toolLog.map(\.toolName))")
        let output = engine.result.payload.plainText
        // 辞書の caution（腱障害 / QT延長 / 金属カチオン）に基づいていること。
        #expect(output.contains("腱") || output.contains("QT") || output.contains("カチオン"),
                "辞書の注意点が応答に反映されていない: \(output.prefix(200))")
    }

    @Test("Multiple Tools が自作プロンプトに応じて Tool を選ぶ", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func multipleToolsPicksByOriginalPrompt() async throws {
        // 在庫を聞く → checkInventory（メトホルミンの在庫は 620 錠）
        let inventory = LabEngine()
        inventory.activate(.multipleTools)
        inventory.prompt = "メトホルミン250mgの在庫はいくつありますか？"
        try await inventory.runDemo(.multipleTools)
        expectSucceeded(inventory, "Multiple Tools(在庫)")
        #expect(inventory.toolLog.map(\.toolName).contains("checkInventory"),
                "在庫質問で checkInventory が選ばれていない: \(inventory.toolLog.map(\.toolName))")
        #expect(inventory.result.payload.plainText.contains("620"),
                "在庫数(620)が応答に出ていない: \(inventory.result.payload.plainText.prefix(200))")

        // 薬効を聞く → searchDrug（プロンプトを変えると選ぶ Tool が変わる）
        let effect = LabEngine()
        effect.activate(.multipleTools)
        effect.prompt = "ランソプラゾール15mgは何のための薬ですか？"
        try await effect.runDemo(.multipleTools)
        expectSucceeded(effect, "Multiple Tools(薬効)")
        #expect(effect.toolLog.map(\.toolName).contains("searchDrug"),
                "薬効質問で searchDrug が選ばれていない: \(effect.toolLog.map(\.toolName))")
    }

    @Test("Multi-step Tool が自作プロンプトで複数の Tool を順に呼ぶ", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func multiStepToolChainsWithOriginalPrompt() async throws {
        let engine = LabEngine()
        engine.activate(.multiStepTool)
        // 鈴木一郎(P003) の処方は メトホルミン250mg(在庫620) と ランソプラゾール15mg(在庫95)。
        // 100錠未満は ランソプラゾール だけ。処方照会 → 在庫照会の2段が必要になる。
        engine.prompt = "鈴木さんに出ている薬のうち、在庫が100錠を下回っているものはどれですか？"

        try await engine.runDemo(.multiStepTool)
        expectSucceeded(engine, "Multi-step Tool")

        let called = engine.toolLog.map(\.toolName)
        #expect(called.count >= 2, "複数段の Tool 呼び出しになっていない: \(called)")
        #expect(Set(called).count >= 2, "同じ Tool しか呼ばれていない: \(called)")
        let output = engine.result.payload.plainText
        #expect(output.contains("ランソプラゾール"),
                "在庫100錠未満の薬（ランソプラゾール15mg）を特定できていない: \(output.prefix(300))")
    }

    @Test("副作用 Tool が自作プロンプトの数量で承認待ちを作る", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func sideEffectToolUsesOriginalQuantity() async throws {
        let engine = LabEngine()
        engine.activate(.sideEffectTool)
        engine.prompt = "レボフロキサシン500mgの在庫を7錠に修正してください。"
        let before = engine.inventory.all.map(\.stock)

        try await engine.runDemo(.sideEffectTool)
        expectSucceeded(engine, "Side Effect Tool")

        // モデル呼び出しだけでは在庫を動かさない。
        #expect(engine.inventory.all.map(\.stock) == before, "モデル呼び出しだけで在庫が変わった")
        // 自作プロンプトの薬剤名と数量が申請に入る。
        let request = engine.pendingSideEffects.first
        #expect(request != nil, "承認待ちの申請が作られていない")
        #expect(request?.drugName.contains("レボフロキサシン") == true,
                "申請の薬剤名が自作プロンプトと違う: \(request?.drugName ?? "-")")
        #expect(request?.newStock == 7, "申請の数量が自作プロンプトの7と違う: \(request?.newStock.description ?? "-")")

        // 承認すると在庫が動く（Human Confirmation の経路）。
        engine.approve(request!)
        #expect(engine.inventory.record(named: "レボフロキサシン500mg")?.stock == 7,
                "承認しても在庫が更新されていない")
    }
}

// MARK: - PLAYGROUND（全オプションを持つ画面）

@MainActor
struct PlaygroundOptionMatrixTests {

    @Test("Playground: 素のテキスト / 構造化 / ストリーミングの3通りすべてで動く",
          .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func playgroundCoversEveryOutputToggle() async throws {
        // 素のテキスト + Tool
        let plain = LabEngine()
        plain.activate(.playground)
        plain.prompt = "ランソプラゾール15mgの在庫を教えてください。"
        plain.instructions = "在庫を聞かれたら checkInventory Tool を使ってください。必ず日本語で答えてください。"
        plain.playgroundTools = [.inventory]
        plain.useStructuredOutput = false
        plain.useStreaming = false
        try await plain.runDemo(.playground)
        expectSucceeded(plain, "Playground(素のテキスト)")
        #expect(plain.toolLog.map(\.toolName).contains("checkInventory"),
                "選んだ Tool が呼ばれていない: \(plain.toolLog.map(\.toolName))")
        #expect(plain.result.payload.plainText.contains("95"),
                "在庫数(95)が応答に出ていない: \(plain.result.payload.plainText.prefix(200))")

        // ストリーミング（トグルを変えると出力形態が変わる）
        let streaming = LabEngine()
        streaming.activate(.playground)
        streaming.prompt = "在庫管理で棚卸しが必要な理由を2文で説明してください。"
        streaming.playgroundTools = []
        streaming.useStructuredOutput = false
        streaming.useStreaming = true
        try await streaming.runDemo(.playground)
        expectSucceeded(streaming, "Playground(ストリーミング)")
        if case .text(let text) = streaming.result.payload {
            #expect(containsJapanese(text), "ストリーミング結果が日本語でない")
        } else {
            Issue.record("ストリーミングの payload が text ではない (\(streaming.result.payload))")
        }
        #expect(streaming.result.metrics.firstTokenAt != nil, "First Token が記録されていない")

        // 構造化出力（Structured と Streaming を同時に有効にしたら Structured 優先）
        let structured = LabEngine()
        structured.activate(.playground)
        structured.prompt = "棚に並んだ在庫の写真という想定で、ImageAnalysis を作ってください。"
        structured.playgroundTools = []
        structured.useStructuredOutput = true
        structured.useStreaming = true
        try await structured.runDemo(.playground)
        expectSucceeded(structured, "Playground(構造化)")
        guard let fields = fields(structured, "Playground(構造化)") else { return }
        #expect(!fields.isEmpty, "構造化出力のフィールドが空")
        #expect(allValues(fields).allSatisfy { !$0.isEmpty }, "空の値があるフィールドがある")
    }

    @Test("Playground: sampling と maximumResponseTokens の指定が効く",
          .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func playgroundRespectsSamplingOptions() async throws {
        let engine = LabEngine()
        engine.activate(.playground)
        engine.prompt = "棚卸しの手順を1文で述べてください。"
        engine.playgroundTools = []
        engine.useStructuredOutput = false
        engine.useStreaming = false
        engine.samplingChoice = .greedy
        engine.temperature = 0
        engine.maximumResponseTokens = 64

        try await engine.runDemo(.playground)
        expectSucceeded(engine, "Playground(greedy / 64 tokens)")

        #expect(engine.result.debugDetail.contains("sampling: greedy"), "選んだ sampling が Debug に出ていない")
        #expect(engine.result.debugDetail.contains("maxTokens: 64"), "指定した maximumResponseTokens が Debug に出ていない")
        // maximumResponseTokens の指定を超えていない（トークン実測で確認）。
        if let responseTokens = engine.result.metrics.responseTokens {
            #expect(responseTokens <= 64, "maximumResponseTokens(64) を超えた: \(responseTokens)")
        }
    }
}
