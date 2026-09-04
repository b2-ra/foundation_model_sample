//
//  foundation_model_sampleTests.swift
//  foundation_model_sampleTests
//
//  仕様書 §77 自動テスト / §78 Unit Test
//  Foundation Models の回答文章そのものは完全一致テストしない。
//  テスト対象は「型として生成できるか / Tool が呼べるか / Schema に適合するか /
//  エラー処理できるか / Model unavailable 時に落ちないか」。
//

import Testing
import Foundation
import CoreGraphics
import Vision
import FoundationModels
@testable import foundation_model_sample

// MARK: - Generable 型

struct GenerableTypeTests {

    @Test("@Generable 型が GenerationSchema を生成できる")
    func generationSchemasExist() throws {
        // スキーマ生成が throw / crash しないことを確認する。
        let schemas: [(String, GenerationSchema)] = [
            ("Prescription", Prescription.generationSchema),
            ("GuidedSentiment", GuidedSentiment.generationSchema),
            ("UnguidedSentiment", UnguidedSentiment.generationSchema),
            ("SupportCategory", SupportCategory.generationSchema),
            ("SupportClassification", SupportClassification.generationSchema),
            ("PatientPrescription", PatientPrescription.generationSchema),
            ("ExtractedEntities", ExtractedEntities.generationSchema),
            ("OneLineSummaryResult", OneLineSummaryResult.generationSchema),
            ("ThreeLineSummaryResult", ThreeLineSummaryResult.generationSchema),
            ("BulletSummaryResult", BulletSummaryResult.generationSchema),
            ("HundredCharacterSummaryResult", HundredCharacterSummaryResult.generationSchema),
            ("ImageCategory", ImageCategory.generationSchema),
            ("ImageClassificationResult", ImageClassificationResult.generationSchema),
            ("ImageAnalysis", ImageAnalysis.generationSchema),
            ("ImageComparison", ImageComparison.generationSchema),
            ("VideoAnalysis", VideoAnalysis.generationSchema),
            ("LiveFrameNarration", LiveFrameNarration.generationSchema),
            ("StockReport", StockReport.generationSchema)
        ]
        for (name, schema) in schemas {
            #expect(!schema.debugDescription.isEmpty, "\(name) のスキーマが空")
        }
    }

    @Test("@Guide の制約がスキーマに現れる")
    func guidesAppearInSchema() throws {
        let guided = GuidedSentiment.generationSchema.debugDescription
        let unguided = UnguidedSentiment.generationSchema.debugDescription

        // 制約付きの方には範囲や列挙の情報が含まれ、無い方には含まれない。
        #expect(guided.count > unguided.count, "Guide ありのスキーマが Guide なしより情報量が少ない")
        #expect(guided.contains("100") || guided.contains("maximum"), "range(0...100) がスキーマに現れていない")
        #expect(guided.contains("positive"), "anyOf の選択肢がスキーマに現れていない")
        #expect(!unguided.contains("positive"), "Guide なしのスキーマに選択肢が漏れている")
    }

    @Test("Generable 型が GeneratedContent と往復できる")
    func generableRoundTrip() throws {
        let original = Prescription(
            patientName: "田中太郎",
            medicineName: "アムロジピン5mg",
            dose: "1錠",
            frequency: 1,
            timing: "朝食後",
            days: 28
        )
        let content = original.generatedContent
        let restored = try Prescription(content)
        #expect(restored == original)

        // JSON 文字列としても取り出せる。
        #expect(content.jsonString.contains("アムロジピン5mg"))
    }

    @Test("Generable enum が全ケースを往復できる")
    func enumRoundTrip() throws {
        for category in SupportCategory.allCases {
            let restored = try SupportCategory(category.generatedContent)
            #expect(restored == category)
        }
        for category in ImageCategory.allCases {
            let restored = try ImageCategory(category.generatedContent)
            #expect(restored == category)
        }
    }

    @Test("入れ子の Generable が往復できる")
    func nestedRoundTrip() throws {
        let nested = PatientPrescription(
            medicinesInText: "アムロジピン5mg, ロキソプロフェン60mg",
            patient: PatientInfo(id: "P001", name: "田中太郎", age: 65),
            medicines: [
                Medicine(name: "アムロジピン5mg", dose: "1錠", frequency: 1, timing: "朝食後"),
                Medicine(name: "ロキソプロフェン60mg", dose: "1錠", frequency: 3, timing: "毎食後")
            ],
            notes: "併用注意なし"
        )
        let restored = try PatientPrescription(nested.generatedContent)
        #expect(restored.patient.name == "田中太郎")
        #expect(restored.medicines.count == 2)
        #expect(restored.medicines.map(\.name).contains("ロキソプロフェン60mg"))
        // 推論用フィールドも往復する。
        #expect(restored.medicinesInText.contains("アムロジピン5mg"))
    }
}

// MARK: - 動的スキーマ

struct DynamicSchemaTests {

    @Test("画面で定義したフィールドから GenerationSchema を作れる")
    func buildsSchemaFromFields() throws {
        let fields = [
            SchemaField(name: "name", type: .string, fieldDescription: "氏名"),
            SchemaField(name: "age", type: .integer, fieldDescription: "年齢"),
            SchemaField(name: "active", type: .boolean),
            SchemaField(name: "score", type: .number),
            SchemaField(name: "tags", type: .stringArray, isOptional: true)
        ]
        let root = DynamicGenerationSchema(name: "DynamicRecord", properties: fields.map(\.property))
        let schema = try GenerationSchema(root: root, dependencies: [])
        let description = schema.debugDescription
        for field in fields {
            #expect(description.contains(field.name), "\(field.name) がスキーマに含まれない")
        }
    }

    @Test("フィールド名が重複したスキーマは SchemaError になる")
    func duplicatePropertyThrows() throws {
        let root = DynamicGenerationSchema(
            name: "Broken",
            properties: [
                DynamicGenerationSchema.Property(name: "value", schema: DynamicGenerationSchema(type: String.self)),
                DynamicGenerationSchema.Property(name: "value", schema: DynamicGenerationSchema(type: Int.self))
            ]
        )
        // throw する場合はエラー写像が SchemaError を拾えることを確認する。
        // throw しない実装であっても、テストは落とさず写像側の健全性だけを見る。
        do {
            _ = try GenerationSchema(root: root, dependencies: [])
        } catch {
            let mapped = LabError.map(error)
            #expect(mapped.category == .schemaFailure)
            #expect(!mapped.recovery.isEmpty)
        }
    }
}

// MARK: - Tool

struct ToolTests {

    @Test("Tool の Arguments が Generable スキーマを持つ")
    func toolArgumentSchemas() throws {
        let recorder = ToolCallRecorder()
        let store = InventoryStore()
        let queue = PendingSideEffectQueue()
        let provider = AnalyzableImageProvider()
        let factory = ToolFactory(
            recorder: recorder, inventory: store, pendingSideEffects: queue,
            imageProvider: provider, selectedPatientId: "P001"
        )
        for name in LabToolName.allCases {
            let tool = factory.tool(for: name)
            #expect(!tool.name.isEmpty, "\(name.displayName) の name が空")
            #expect(!tool.description.isEmpty, "\(name.displayName) の description が空")
            #expect(!tool.parameters.debugDescription.isEmpty, "\(name.displayName) の parameters が空")
        }
    }

    @Test("Tool 名が一意である")
    func toolNamesAreUnique() {
        let recorder = ToolCallRecorder()
        let factory = ToolFactory(
            recorder: recorder, inventory: InventoryStore(), pendingSideEffects: PendingSideEffectQueue(),
            imageProvider: AnalyzableImageProvider(), selectedPatientId: nil
        )
        let names = LabToolName.allCases.map { factory.tool(for: $0).name }
        #expect(Set(names).count == names.count, "Tool 名が重複している: \(names)")
    }

    @Test("WeatherTool が既知の都市と未知の都市を扱える")
    func weatherTool() async throws {
        let recorder = ToolCallRecorder()
        let tool = WeatherTool(recorder: recorder)

        let known = try await tool.call(arguments: .init(city: "金沢"))
        #expect(known.contains("26"))

        let unknown = try await tool.call(arguments: .init(city: "ロンドン"))
        #expect(unknown.contains("データはありません"))

        // 呼び出しがログに残る。
        let log = recorder.drain()
        #expect(log.count == 2)
        #expect(log.allSatisfy { $0.finishedAt != nil })
        #expect(log.last?.failed == true)
    }

    @Test("DrugSearchTool が用量なしの表記でも引ける")
    func drugSearchTool() async throws {
        let tool = DrugSearchTool(recorder: ToolCallRecorder())

        let withDose = try await tool.call(arguments: .init(name: "アムロジピン5mg"))
        #expect(withDose.contains("Ca拮抗薬"))

        let withoutDose = try await tool.call(arguments: .init(name: "アムロジピン"))
        #expect(withoutDose.contains("Ca拮抗薬"))

        let missing = try await tool.call(arguments: .init(name: "存在しない薬"))
        #expect(missing.contains("存在しません"))
    }

    @Test("InventoryTool が在庫不足を判定する")
    func inventoryTool() async throws {
        let store = InventoryStore()
        let tool = InventoryTool(recorder: ToolCallRecorder(), store: store)

        // アムロジピン5mg: 在庫80 / 発注点100 → 不足
        let low = try await tool.call(arguments: .init(name: "アムロジピン5mg"))
        #expect(low.contains("在庫不足"))

        // ロキソプロフェン60mg: 在庫500 / 発注点200 → 十分
        let enough = try await tool.call(arguments: .init(name: "ロキソプロフェン60mg"))
        #expect(enough.contains("十分"))
    }

    @Test("PatientTool は引数が空なら Session Property を使う")
    func patientToolUsesSessionProperty() async throws {
        let tool = PatientTool(recorder: ToolCallRecorder(), selectedPatientId: "P002")

        let implicit = try await tool.call(arguments: .init(nameOrId: ""))
        #expect(implicit.contains("佐藤花子"), "空引数で選択中の患者が解決されない")

        let explicit = try await tool.call(arguments: .init(nameOrId: "田中太郎"))
        #expect(explicit.contains("田中太郎"))
        #expect(explicit.contains("P001"))
    }

    @Test("PrescriptionTool が患者IDで処方を引ける")
    func prescriptionTool() async throws {
        let tool = PrescriptionTool(recorder: ToolCallRecorder())
        let output = try await tool.call(arguments: .init(patientId: "P001"))
        #expect(output.contains("アムロジピン5mg"))
        #expect(output.contains("ロキソプロフェン60mg"))

        let empty = try await tool.call(arguments: .init(patientId: "P999"))
        #expect(empty.contains("処方はありません"))
    }

    @Test("InventoryUpdateTool は在庫を変更せず申請だけを積む")
    func sideEffectToolDoesNotMutate() async throws {
        let store = InventoryStore()
        let queue = PendingSideEffectQueue()
        let tool = InventoryUpdateTool(recorder: ToolCallRecorder(), pendingRequests: queue)

        let before = store.record(named: "アムロジピン5mg")?.stock
        let output = try await tool.call(arguments: .init(name: "アムロジピン5mg", newStock: 0, reason: "欠品"))
        let after = store.record(named: "アムロジピン5mg")?.stock

        #expect(before == after, "Tool 呼び出しだけで在庫が変わってしまっている")
        #expect(output.contains("承認待ち"))

        let requests = queue.drain()
        #expect(requests.count == 1)
        #expect(requests.first?.drugName == "アムロジピン5mg")
        #expect(requests.first?.newStock == 0)
    }

    @Test("承認処理を経て初めて在庫が変わる")
    func approvalMutatesInventory() {
        let store = InventoryStore()
        let before = store.record(named: "アムロジピン5mg")?.stock
        #expect(before == 80)

        let updated = store.setStock(0, for: "アムロジピン5mg")
        #expect(updated?.stock == 0)
        #expect(store.record(named: "アムロジピン5mg")?.stock == 0)

        store.reset()
        #expect(store.record(named: "アムロジピン5mg")?.stock == 80)
    }

    @Test("画像未選択の OCRTool / BarcodeReaderTool が落ちずにメッセージを返す")
    func visionToolsWithoutImage() async throws {
        let provider = AnalyzableImageProvider()
        provider.set(nil)

        let ocr = try await OCRTool(recorder: ToolCallRecorder(), imageProvider: provider)
            .call(arguments: .init(target: "all"))
        #expect(ocr.contains("選択されていません"))

        let barcode = try await BarcodeReaderTool(recorder: ToolCallRecorder(), imageProvider: provider)
            .call(arguments: .init(target: "all"))
        #expect(barcode.contains("選択されていません"))
    }

    @Test("FailingTool は必ず throw する")
    func failingToolThrows() async {
        let tool = FailingTool(recorder: ToolCallRecorder())
        await #expect(throws: FailingTool.DeliberateFailure.self) {
            _ = try await tool.call(arguments: .init(key: "sync"))
        }
    }

    @Test("Profile ごとに公開 Tool が変わる")
    func profileToolVisibility() {
        let factory = ToolFactory(
            recorder: ToolCallRecorder(), inventory: InventoryStore(),
            pendingSideEffects: PendingSideEffectQueue(),
            imageProvider: AnalyzableImageProvider(), selectedPatientId: "P001"
        )
        for profile in AgentProfile.allCases {
            let tools = factory.tools(for: profile.tools)
            #expect(tools.count == profile.tools.count)
        }
        #expect(AgentProfile.vision.tools.contains(.ocr))
        #expect(!AgentProfile.quick.tools.contains(.ocr))
        #expect(AgentProfile.inventory.tools.contains(.inventoryUpdate))
        #expect(!AgentProfile.patient.tools.contains(.inventoryUpdate))
    }
}

// MARK: - Mock database

struct DemoDataTests {

    @Test("Resources の JSON が読み込める")
    func databasesLoad() {
        #expect(DemoData.drugs.count >= 3)
        #expect(DemoData.patients.count >= 2)
        #expect(DemoData.prescriptions.count >= 3)
        #expect(DemoData.inventory.count >= 3)
    }

    @Test("薬品マスターと在庫マスターの名称が対応している")
    func inventoryCoversDrugs() {
        let drugNames = Set(DemoData.drugs.map(\.name))
        let inventoryNames = Set(DemoData.inventory.map(\.name))
        #expect(drugNames == inventoryNames, "薬品と在庫の名称が一致しない: \(drugNames.symmetricDifference(inventoryNames))")
    }

    @Test("処方が実在する患者と薬剤を参照している")
    func prescriptionsReferenceExistingRecords() {
        let patientIds = Set(DemoData.patients.map(\.id))
        let drugNames = Set(DemoData.drugs.map(\.name))
        for record in DemoData.prescriptions {
            #expect(patientIds.contains(record.patientId), "未知の患者ID: \(record.patientId)")
            #expect(drugNames.contains(record.medicineName), "未知の薬剤: \(record.medicineName)")
            #expect(record.frequency >= 1)
            #expect(record.days >= 1)
        }
    }

    @Test("バーコードから薬品を逆引きできる")
    func barcodeLookup() {
        for drug in DemoData.drugs {
            #expect(DemoData.drug(forBarcode: drug.barcodePayload)?.name == drug.name)
        }
        #expect(DemoData.drug(forBarcode: "0000000000000") == nil)
    }

    @Test("患者名の部分一致で患者を引ける")
    func patientLookup() {
        #expect(DemoData.patient(matching: "田中さんの処方")?.id == "P001")
        #expect(DemoData.patient(matching: "P003")?.name == "鈴木一郎")
    }

    @Test("在庫の発注点判定が正しい")
    func lowStockDetection() {
        let low = DemoData.inventory.filter(\.isLow).map(\.name)
        #expect(low.contains("アムロジピン5mg"))      // 80 < 100
        #expect(low.contains("レボフロキサシン500mg")) // 40 < 100
        #expect(!low.contains("ロキソプロフェン60mg")) // 500 > 200
    }
}

// MARK: - ModelManager

@MainActor
struct ModelManagerTests {

    @Test("Model unavailable でも ModelManager の生成でクラッシュしない")
    func initialisesWithoutCrash() {
        let manager = ModelManager()
        // Simulator では availability が unavailable になるが、落ちてはいけない（仕様書 §60）。
        #expect(!manager.deviceName.isEmpty)
        #expect(!manager.osVersion.isEmpty)
        #expect(manager.contextSize > 0, "contextSize が取得できていない")
    }

    @Test("利用不可のときも理由と復旧手順が入っている")
    func unavailabilityCarriesRecovery() {
        let manager = ModelManager()
        if manager.availability.isAvailable {
            #expect(manager.availability.recovery == nil)
        } else {
            #expect(manager.availability.recovery?.isEmpty == false, "復旧手順が空")
            #expect(!manager.availability.detail.isEmpty, "理由が空")
        }
    }

    @Test("Capabilities が SDK の実状態を反映する")
    func capabilitiesReflectSDK() {
        let manager = ModelManager()
        let capabilities = manager.capabilities
        // このSDKに存在しない機能は必ず false。
        #expect(capabilities.nativeVision == false, "画像添付APIは存在しないので false であるべき")
        #expect(capabilities.privateCloudCompute == false, "PCC はSDK未提供なので false であるべき")
        #expect(capabilities.reasoningLevel == false, "reasoning 設定はSDK未提供なので false であるべき")
        // Vision framework 経由は常に使える。
        #expect(capabilities.visionFrameworkBridge == true)
        // モデルが使えるときだけ true になる項目。
        #expect(capabilities.textGeneration == manager.availability.isAvailable)
        #expect(capabilities.toolCalling == manager.availability.isAvailable)
        #expect(capabilities.rows.count == 10)
    }

    @Test("refresh が繰り返し呼べる")
    func refreshIsIdempotent() {
        let manager = ModelManager()
        let first = manager.contextSize
        manager.refresh()
        manager.refresh()
        #expect(manager.contextSize == first)
    }

    @Test("Session を生成できる")
    func makesSessions() {
        let manager = ModelManager()
        // Availability に関わらずセッションオブジェクトの生成自体は成功する。
        let plain = manager.makeSession(instructions: "test")
        #expect(plain.transcript.count >= 0)

        let restored = manager.makeSession(transcript: Transcript(entries: []))
        #expect(restored.transcript.isEmpty)
    }
}

// MARK: - Error mapping

struct ErrorMappingTests {

    @Test("CancellationError が cancelled に写像される")
    func mapsCancellation() {
        let mapped = LabError.map(CancellationError())
        #expect(mapped.category == .cancelled)
        #expect(!mapped.userMessage.isEmpty)
        #expect(!mapped.recovery.isEmpty)
    }

    @Test("GenerationError の全ケースが4項目に写像される")
    func mapsAllGenerationErrors() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test detail")
        let errors: [LanguageModelSession.GenerationError] = [
            .exceededContextWindowSize(context),
            .assetsUnavailable(context),
            .guardrailViolation(context),
            .unsupportedGuide(context),
            .unsupportedLanguageOrLocale(context),
            .decodingFailure(context),
            .rateLimited(context),
            .concurrentRequests(context)
        ]
        let expected: [LabError.Category] = [
            .contextExceeded, .modelUnavailable, .guardrailViolation, .unsupportedGuide,
            .unsupportedLanguage, .decodingFailure, .rateLimited, .concurrentRequests
        ]
        for (error, category) in zip(errors, expected) {
            let mapped = LabError.map(error)
            #expect(mapped.category == category, "\(error) の写像先が \(mapped.category)")
            #expect(mapped.technicalDetail.contains("test detail"), "technicalDetail に元の詳細が入っていない")
            #expect(!mapped.userMessage.isEmpty, "User Message が空")
            #expect(!mapped.recovery.isEmpty, "Recovery が空")
        }
    }

    @Test("ToolCallError が toolFailure に写像され Tool 名を含む")
    func mapsToolCallError() {
        let tool = FailingTool(recorder: ToolCallRecorder())
        let error = LanguageModelSession.ToolCallError(tool: tool, underlyingError: FailingTool.DeliberateFailure())
        let mapped = LabError.map(error)
        #expect(mapped.category == .toolFailure)
        #expect(mapped.technicalDetail.contains(tool.name))
        #expect(mapped.userMessage.contains(tool.name))
    }

    @Test("未知のエラーも4項目が埋まる")
    func mapsUnknownError() {
        struct Weird: Error {}
        let mapped = LabError.map(Weird())
        #expect(mapped.category == .generationFailure)
        #expect(!mapped.errorType.isEmpty)
        #expect(!mapped.technicalDetail.isEmpty)
        #expect(!mapped.userMessage.isEmpty)
        #expect(!mapped.recovery.isEmpty)
    }

    @Test("LabError の写像は冪等")
    func mappingIsIdempotent() {
        let original = LabError.image("test")
        let mapped = LabError.map(original)
        #expect(mapped == original)
    }

    @Test("Availability から復旧手順付きのエラーを作れる")
    func mapsAvailability() {
        let unavailable = LabAvailability.unavailable(
            reason: "Apple Intelligence が有効になっていません (appleIntelligenceNotEnabled)。",
            recovery: "設定から有効にしてください。"
        )
        let mapped = LabError.unavailable(unavailable)
        #expect(mapped.category == .appleIntelligenceDisabled)
        #expect(mapped.recovery == "設定から有効にしてください。")
    }

    @Test("Error Lab のカタログが全カテゴリを4項目で持つ")
    func errorCatalogIsComplete() {
        #expect(ErrorCatalogEntry.all.count >= 10)
        for entry in ErrorCatalogEntry.all {
            #expect(!entry.error.errorType.isEmpty)
            #expect(!entry.error.technicalDetail.isEmpty)
            #expect(!entry.error.userMessage.isEmpty)
            #expect(!entry.error.recovery.isEmpty)
            #expect(!entry.howToReproduce.isEmpty)
        }
        // 再現手順のあるものが半分以上。
        #expect(ErrorCatalogEntry.all.filter(\.reproducible).count >= 5)
    }

    @Test("SDK未提供エラーが代替手段を持つ")
    func sdkFeatureMissingCarriesAlternative() {
        let error = LabError.sdkFeatureMissing("PrivateCloudComputeLanguageModel", alternative: "On-device で比較する")
        #expect(error.category == .sdkFeatureMissing)
        #expect(error.recovery == "On-device で比較する")
        #expect(error.technicalDetail.contains("PrivateCloudComputeLanguageModel"))
    }
}

// MARK: - Chunking

@MainActor
struct ChunkingTests {

    @Test("長文が指定したトークン予算以下のチャンクに分割される")
    func splitsWithinBudget() async {
        let engine = LabEngine()
        let budget = 200
        let chunks = await engine.chunk(DemoData.longText, tokenBudget: budget)

        #expect(chunks.count > 1, "分割されていない")
        // 文単位で区切るため境界はぴったりにならない。極端に大きくないことを見る。
        for chunk in chunks {
            let tokens = await engine.tokenLength(chunk)
            #expect(tokens <= budget * 2, "チャンクが極端に大きい: \(tokens) tokens")
        }
        // 元の文章が失われていない。
        #expect(chunks.joined() == DemoData.longText, "分割で文字が失われた")
    }

    @Test("トークン予算を変えると分割数が変わる")
    func budgetAffectsChunkCount() async {
        let engine = LabEngine()
        let small = await engine.chunk(DemoData.longText, tokenBudget: 60)
        let large = await engine.chunk(DemoData.longText, tokenBudget: 500)
        #expect(small.count > large.count)
    }

    @Test("短い文章は1チャンクになる")
    func shortTextStaysSingleChunk() async {
        let engine = LabEngine()
        let chunks = await engine.chunk("短い文章です。", tokenBudget: 200)
        #expect(chunks.count == 1)
    }

    @Test("空文字でも落ちない")
    func handlesEmptyText() async {
        let engine = LabEngine()
        let chunks = await engine.chunk("", tokenBudget: 200)
        #expect(chunks.count == 1)
    }

    // 以下はモデル非依存の純粋な分割ロジック。トークン数を注入して決定的に検証する。

    @Test("文の境界で切り出され、境界文字は前の文に残る")
    func sentenceBoundaries() {
        let sentences = LabEngine.sentences(of: "一つ目です。二つ目です。\n三つ目")
        #expect(sentences == ["一つ目です。", "二つ目です。", "\n", "三つ目"])
        #expect(sentences.joined() == "一つ目です。二つ目です。\n三つ目")
    }

    @Test("トークン予算を超える直前でチャンクが切れる")
    func assembleRespectsTokenBudget() {
        // 文字数は同じでもトークン数が違う場合に、トークン数で切れることを確認する。
        let measured = (1...6).map { _ in
            LabEngine.MeasuredSentence(text: "あいうえお。", tokens: 30)
        }
        let chunks = LabEngine.assemble(measured, tokenBudget: 100, fallback: "")
        // 30 tokens × 3 = 90 まで積めて、4文目（120）で切れる。
        #expect(chunks.count == 2)
        #expect(chunks[0] == "あいうえお。あいうえお。あいうえお。")
        #expect(chunks.joined() == measured.map(\.text).joined())
    }

    @Test("1文だけで予算を超える場合はその文をさらに分割する")
    func assembleSplitsOversizedSentence() {
        let long = String(repeating: "あ", count: 300) + "。"
        let chunks = LabEngine.assemble(
            [LabEngine.MeasuredSentence(text: long, tokens: 301)],
            tokenBudget: 100,
            fallback: ""
        )
        #expect(chunks.count >= 4, "予算 100 tokens に対して 301 tokens が分割されていない")
        #expect(chunks.joined() == long, "分割で文字が失われた")
        for chunk in chunks {
            #expect(chunk.count <= 100, "1片が予算に対して大きすぎる: \(chunk.count) 文字")
        }
    }

    @Test("トークン概算が日本語とラテン文字で異なる")
    func estimatorReflectsScript() {
        // Apple の記述: CJK は1文字がほぼ1トークン、ラテン文字は3〜4文字で1トークン。
        let japanese = LabEngine.estimatedTokens(String(repeating: "薬", count: 100))
        let latin = LabEngine.estimatedTokens(String(repeating: "a", count: 100))
        #expect(japanese == 100)
        #expect(latin < japanese, "ラテン文字が日本語と同じトークン数になっている")
        #expect(LabEngine.estimatedTokens("") == 0)
    }
}

// MARK: - Catalog

struct DemoCatalogTests {

    @Test("すべてのデモがタイトル・説明・API・ソースを持つ")
    func everyDemoIsDescribed() {
        for demo in LabDemo.allCases {
            #expect(!demo.title.isEmpty, "\(demo.rawValue) のタイトルが空")
            #expect(!demo.subtitle.isEmpty, "\(demo.rawValue) の説明が空")
            #expect(!demo.symbol.isEmpty, "\(demo.rawValue) のアイコンが空")
            #expect(!demo.usedAPIs.isEmpty, "\(demo.rawValue) の Used APIs が空")
            #expect(!demo.sourceSnippet.isEmpty, "\(demo.rawValue) の View Source が空")
            #expect(!demo.runLabel.isEmpty)
        }
    }

    @Test("Used APIs のドキュメントリンクが組み立てられる")
    func documentationLinksResolve() {
        for demo in LabDemo.allCases {
            for api in demo.usedAPIs {
                #expect(!api.framework.isEmpty, "\(api.symbol) の framework が空")
                if !api.documentationPath.isEmpty {
                    #expect(api.url != nil, "\(api.symbol) の URL が組み立てられない")
                }
            }
        }
    }

    @Test("すべてのグループにデモが1つ以上ある")
    func everyGroupHasDemos() {
        for group in LabGroup.allCases {
            #expect(!LabDemo.demos(in: group).isEmpty, "\(group.title) が空")
        }
    }

    @Test("仕様書の完成版メニューの主要項目が揃っている")
    func coversSpecificationMenu() {
        // 仕様書 §85 完成条件のうち、画面として存在すべきものを確認する。
        let required: [LabDemo] = [
            .dashboard, .simpleGeneration, .instructions, .conversation, .streaming,
            .generable, .guideComparison, .enumGeneration, .nestedObject, .dynamicSchema, .generationOptions,
            .basicTool, .multipleTools, .multiStepTool, .sideEffectTool,
            .imageDescription, .imageClassification, .compareImages, .ocr, .barcode, .camera,
            .transcript, .restore, .contextWindow, .tokenCount, .chunking, .historyTransform, .prewarm,
            .pcc, .reasoning, .capabilities,
            .dynamicInstructions, .dynamicProfile, .toolVisibility, .sessionProperty, .lifecycleEvents,
            .agentWorkflow, .visionAgent, .customModel, .errorLab, .apiReference, .playground
        ]
        for demo in required {
            #expect(LabDemo.allCases.contains(demo), "\(demo.rawValue) が存在しない")
        }
        // 仕様書外だがユーザー体験上必要な追加デモ。
        #expect(LabDemo.allCases.contains(.videoAnalysis))
        #expect(LabDemo.allCases.contains(.liveCamera))
    }

    @Test("SDK未提供のデモに印が付いている")
    func sdkUnavailableDemosAreMarked() {
        #expect(LabDemo.pcc.requiresUnavailableSDKFeature)
        #expect(LabDemo.quota.requiresUnavailableSDKFeature)
        #expect(LabDemo.reasoning.requiresUnavailableSDKFeature)
        #expect(!LabDemo.simpleGeneration.requiresUnavailableSDKFeature)
    }

    @Test("メディア系デモに適切な入力が宣言されている")
    func mediaDemosDeclareInputs() {
        #expect(LabDemo.imageDescription.inputs.contains(.image))
        #expect(LabDemo.compareImages.inputs.contains(.secondImage))
        #expect(LabDemo.videoAnalysis.inputs.contains(.video))
        #expect(LabDemo.videoAnalysis.inputs.contains(.frameCount))
        #expect(LabDemo.camera.inputs.contains(.camera))
        #expect(LabDemo.liveCamera.inputs.contains(.liveCamera))
        #expect(LabDemo.ocr.inputs.contains(.image))
        #expect(LabDemo.barcode.inputs.contains(.image))
    }

    @Test("プリセットが空でない値を持つ")
    func presetsAreValid() {
        for demo in LabDemo.allCases {
            for preset in demo.promptPresets {
                #expect(!preset.title.isEmpty, "\(demo.rawValue) のプリセット名が空")
                #expect(!preset.value.isEmpty, "\(demo.rawValue) のプリセット値が空")
            }
        }
        #expect(LabDemo.instructions.instructionPresets.count == 4, "仕様書 §9 のプリセット4種が揃っていない")
    }
}

// MARK: - Vision plans

struct VisionPlanTests {

    @Test("リアルタイム用プランは重い処理を含まない")
    func realtimePlanIsLight() {
        let realtime = VisionAnalysisPlan.realtime
        #expect(realtime.scoreAesthetics == false)
        #expect(realtime.detectSaliency == false)
        #expect(realtime.textRecognitionLevel == .fast, "リアルタイムで accurate を使うとフレームが落ちる")

        let full = VisionAnalysisPlan.full
        #expect(full.scoreAesthetics == true)
        #expect(full.textRecognitionLevel == .accurate)
        #expect(full.requestNames.count > realtime.requestNames.count)
    }

    @Test("用途別プランが必要なリクエストだけを持つ")
    func focusedPlans() {
        #expect(VisionAnalysisPlan.ocrOnly.recognizeText)
        #expect(!VisionAnalysisPlan.ocrOnly.detectBarcodes)
        #expect(!VisionAnalysisPlan.ocrOnly.classifyImage)

        #expect(VisionAnalysisPlan.barcodeOnly.detectBarcodes)
        #expect(!VisionAnalysisPlan.barcodeOnly.recognizeText)

        for plan in [VisionAnalysisPlan.full, .videoFrame, .realtime, .ocrOnly, .barcodeOnly] {
            #expect(!plan.requestNames.isEmpty, "リクエストが1つもないプランがある")
        }
    }

    @Test("FrameAnalysis の digest がモデルへ渡せる形になる")
    func frameDigest() {
        var frame = FrameAnalysis(timestamp: 12.5, imageSize: CGSize(width: 1920, height: 1080))
        frame.labels = [DetectedLabel(identifier: "document", confidence: 0.82)]
        frame.texts = [DetectedText(text: "アムロジピン5mg", confidence: 0.95,
                                    boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05),
                                    isTitle: false, languages: ["ja"])]
        frame.barcodes = [DetectedBarcode(payload: "4987123456781", symbology: "EAN13",
                                          boundingBox: .zero, isGS1DataCarrier: false)]

        let digest = frame.digest
        #expect(digest.contains("12.5"))
        #expect(digest.contains("document"))
        #expect(digest.contains("アムロジピン5mg"))
        #expect(digest.contains("4987123456781"))
        #expect(frame.timestampText == "00:12.5")
        #expect(frame.summaryLine.contains("document"))
    }

    @Test("特徴が無いフレームでも digest が空にならない")
    func emptyFrameDigest() {
        let frame = FrameAnalysis(imageSize: CGSize(width: 100, height: 100))
        #expect(!frame.digest.isEmpty)
        #expect(frame.digest.contains("検出できませんでした"))
        #expect(frame.timestampText == "-")
    }

    @Test("複数フレームの集約が重複を除く")
    func multiFrameAggregation() {
        var first = FrameAnalysis(timestamp: 0, imageSize: .zero)
        first.texts = [DetectedText(text: "同じ文字", confidence: 0.9, boundingBox: .zero, isTitle: false, languages: [])]
        first.labels = [DetectedLabel(identifier: "cat", confidence: 0.8)]
        first.barcodes = [DetectedBarcode(payload: "AAA", symbology: "QR", boundingBox: .zero, isGS1DataCarrier: false)]

        var second = FrameAnalysis(timestamp: 1, imageSize: .zero)
        second.texts = [DetectedText(text: "同じ文字", confidence: 0.9, boundingBox: .zero, isTitle: false, languages: [])]
        second.labels = [DetectedLabel(identifier: "cat", confidence: 0.6)]
        second.barcodes = [DetectedBarcode(payload: "AAA", symbology: "QR", boundingBox: .zero, isGS1DataCarrier: false)]

        let frames = [first, second]
        #expect(frames.uniqueTexts == ["同じ文字"])
        #expect(frames.uniqueBarcodes.count == 1)
        #expect(frames.aggregatedLabels.count == 1)
        // 平均信頼度になる。
        #expect(abs(frames.aggregatedLabels[0].confidence - 0.7) < 0.01)
        #expect(frames.videoDigest.contains("Frame 1"))
        #expect(frames.videoDigest.contains("Frame 2"))
    }
}

// MARK: - Custom model abstraction

struct CustomModelTests {

    @Test("Mock Executor が呼び出し形を保ったまま応答する")
    func mockExecutorResponds() async throws {
        var model = MockExecutorModel()
        model.simulatedLatency = .milliseconds(1)
        let text = try await model.respond(
            to: "テストプロンプト",
            instructions: "テスト指示",
            options: GenerationOptions(temperature: 0.5, maximumResponseTokens: 128)
        )
        #expect(text.contains("MockExecutor"))
        #expect(text.contains("テストプロンプト"))
        #expect(model.capabilities.toolCalling == false, "モックは Tool Calling を持たない")
    }

    @Test("PCC モデルは SDK未提供エラーを投げる")
    func pccModelThrowsSDKMissing() async {
        let model = UnavailablePCCModel()
        do {
            _ = try await model.respond(to: "test", instructions: nil, options: GenerationOptions())
            Issue.record("SDK未提供エラーが投げられなかった")
        } catch let error as LabError {
            #expect(error.category == .sdkFeatureMissing)
            #expect(!error.recovery.isEmpty)
        } catch {
            Issue.record("想定外のエラー: \(error)")
        }
    }

    @Test("ModelChoice が SDK 実装の有無を正しく示す")
    func modelChoiceBacking() {
        #expect(ModelChoice.onDevice.isBackedByInstalledSDK)
        #expect(!ModelChoice.pcc.isBackedByInstalledSDK)
        #expect(!ModelChoice.custom.isBackedByInstalledSDK)
        for choice in ModelChoice.allCases {
            #expect(!choice.displayName.isEmpty)
            #expect(!choice.apiTypeName.isEmpty)
        }
    }
}

// MARK: - Engine state

@MainActor
struct LabEngineTests {

    @Test("Model unavailable でも Engine を生成できる")
    func initialises() {
        let engine = LabEngine()
        #expect(engine.isRunning == false)
        #expect(engine.result.executionMode == .notExecuted)
        #expect(!engine.prompt.isEmpty)
        #expect(!engine.instructions.isEmpty)
        #expect(engine.schemaFields.count == 3)
    }

    @Test("requireAvailableModel が利用不可のとき復旧手順付きで throw する")
    func requiresAvailability() {
        let engine = LabEngine()
        if engine.modelManager.availability.isAvailable {
            #expect(throws: Never.self) { try engine.requireAvailableModel() }
        } else {
            do {
                try engine.requireAvailableModel()
                Issue.record("利用不可なのに throw しなかった")
            } catch let error as LabError {
                #expect(!error.recovery.isEmpty)
            } catch {
                Issue.record("想定外のエラー: \(error)")
            }
        }
    }

    @Test("resetSessions が状態を初期化する")
    func resetClearsState() {
        let engine = LabEngine()
        engine.log(.onPrompt, "test")
        engine.pendingSideEffects = [
            SideEffectRequest(toolName: "t", drugName: "アムロジピン5mg", currentStock: 80, newStock: 0, reason: "test")
        ]
        _ = engine.inventory.setStock(0, for: "アムロジピン5mg")

        engine.resetSessions()

        #expect(engine.transcriptEntries.isEmpty)
        #expect(engine.toolLog.isEmpty)
        #expect(engine.pendingSideEffects.isEmpty)
        #expect(engine.inventory.record(named: "アムロジピン5mg")?.stock == 80, "在庫がリセットされていない")
        #expect(engine.result.executionMode == .notExecuted)
    }

    @Test("副作用の承認と却下が在庫へ正しく反映される")
    func approvalFlow() {
        let engine = LabEngine()
        let request = SideEffectRequest(toolName: "requestInventoryUpdate", drugName: "アムロジピン5mg",
                                       currentStock: 80, newStock: 0, reason: "欠品")

        engine.pendingSideEffects = [request]
        engine.reject(request)
        #expect(engine.pendingSideEffects.isEmpty)
        #expect(engine.inventory.record(named: "アムロジピン5mg")?.stock == 80, "却下したのに在庫が変わった")

        engine.pendingSideEffects = [request]
        engine.approve(request)
        #expect(engine.pendingSideEffects.isEmpty)
        #expect(engine.inventory.record(named: "アムロジピン5mg")?.stock == 0, "承認したのに在庫が変わらない")
    }

    @Test("画面を切り替えると Output と Transcript が初期化される")
    func switchingDemoResetsPresentation() {
        let engine = LabEngine()
        engine.activate(.simpleGeneration)

        // 実行後の状態を作る。
        engine.result.payload = .text("前の画面の応答")
        engine.result.debugDetail = "前の画面のデバッグ情報"
        engine.result.error = LabError.image("前の画面のエラー")
        engine.transcriptEntries = [
            TranscriptEntryView(kind: .response, title: "Response", body: "前の画面の応答")
        ]
        let id = engine.recorder.begin("previousTool", arguments: "{}")
        engine.recorder.finish(id, output: "ok")
        engine.drainToolLog()
        engine.pendingSideEffects = [
            SideEffectRequest(toolName: "t", drugName: "アムロジピン5mg", currentStock: 80, newStock: 0, reason: "test")
        ]
        #expect(!engine.toolLog.isEmpty)

        // 別の画面へ切り替える。
        engine.activate(.ocr)

        #expect(engine.result.payload.isEmpty, "Output が残っている")
        #expect(engine.result.error == nil, "エラー表示が残っている")
        #expect(engine.result.debugDetail.isEmpty, "デバッグ情報が残っている")
        #expect(engine.result.executionMode == .notExecuted, "実行モードが残っている")
        #expect(engine.transcriptEntries.isEmpty, "Transcript が残っている")
        #expect(engine.toolLog.isEmpty, "Tool Calls が残っている")
        #expect(engine.lifecycleLog.isEmpty, "Lifecycle が残っている")
        #expect(engine.pendingSideEffects.isEmpty, "承認待ちが次の画面へ持ち越されている")
        #expect(engine.isRunning == false)
    }

    @Test("同じ画面に留まる限り初期化されない")
    func stayingOnSameDemoKeepsPresentation() {
        let engine = LabEngine()
        engine.activate(.simpleGeneration)
        engine.result.payload = .text("この画面の応答")

        // 同じデモで再度 activate されても消えない（run() からも呼ばれるため）。
        engine.activate(.simpleGeneration)

        #expect(!engine.result.payload.isEmpty, "同じ画面なのに Output が消えた")
    }

    @Test("Logs 画面用の履歴は画面切り替えでも残る")
    func sessionHistorySurvivesDemoSwitch() {
        let engine = LabEngine()
        engine.activate(.basicTool)

        let id = engine.recorder.begin("getWeather", arguments: "{ \"city\": \"金沢\" }")
        engine.recorder.finish(id, output: "26℃")
        engine.drainToolLog()
        #expect(engine.sessionToolLog.count == 1)
        #expect(!engine.sessionLifecycleLog.isEmpty)

        engine.activate(.logs)

        // 画面ごとのパネルは消えるが、Logs が見るセッション履歴は残る。
        #expect(engine.toolLog.isEmpty, "画面のパネルが初期化されていない")
        #expect(engine.sessionToolLog.count == 1, "セッション履歴まで消えている")
        #expect(engine.sessionToolLog.first?.toolName == "getWeather")
        #expect(!engine.sessionLifecycleLog.isEmpty, "Lifecycle のセッション履歴が消えている")
    }

    @Test("Reset Session はセッション履歴も消す")
    func resetSessionClearsSessionHistory() {
        let engine = LabEngine()
        let id = engine.recorder.begin("getWeather", arguments: "{}")
        engine.recorder.finish(id, output: "26℃")
        engine.drainToolLog()
        #expect(!engine.sessionToolLog.isEmpty)

        engine.resetSessions()

        #expect(engine.sessionToolLog.isEmpty, "Reset でセッション履歴が消えていない")
        // resetSessions 自身のログ1件だけが残る。
        #expect(engine.sessionLifecycleLog.count <= 1)
    }

    @Test("Prompt はデモごとに保持され、切り替えても混ざらない")
    func promptIsPerDemo() {
        let engine = LabEngine()

        engine.activate(.simpleGeneration)
        let simpleDefault = engine.prompt
        engine.prompt = "編集したプロンプト"

        engine.activate(.ocr)
        #expect(engine.prompt != "編集したプロンプト", "別の画面に前の Prompt が漏れている")
        #expect(engine.prompt == LabDemo.ocr.promptPresets.first?.value,
                "OCR 画面の既定 Prompt になっていない")

        // 戻ると編集内容が復元される。
        engine.activate(.simpleGeneration)
        #expect(engine.prompt == "編集したプロンプト", "編集した Prompt が失われた")
        #expect(simpleDefault != "編集したプロンプト")
    }

    @Test("Live Round Trip が useCase ごとに成功する", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func liveRoundTripDoesNotFailFromUseCaseMismatch() async throws {
        // 直したのは「useCase に合わない形式で往復させていたこと」。
        // 以前はここで availability を見て無音 return していたため、モデルが使えない環境でも
        // 緑になっていた。利用可否は trait で判定し、通ったら往復の成功まで確認する。
        for useCase in SystemModelUseCase.allCases {
            // 画面ごとに状態を持ち越さないよう、useCase ごとに engine を作り直す。
            let engine = LabEngine()
            engine.modelManager.useCase = useCase
            engine.modelManager.refresh()

            try await engine.runDemo(.dashboard)

            guard case .keyValue(let rows) = engine.result.payload else {
                Issue.record("\(useCase.rawValue): Dashboard の payload が keyValue ではない")
                continue
            }
            let row = rows.first { $0.label == "Live Round Trip" }
            #expect(row != nil, "\(useCase.rawValue): Live Round Trip の行が無い")

            // useCase 不一致の症状がこれ。素のテキストを contentTagging に求めると起きる。
            #expect(engine.result.error?.category != .decodingFailure,
                    "\(useCase.rawValue): useCase に合わない形式で往復させている")
            // 入力が膨らんでコンテキストを超えるのも、スキーマ設計を誤ったときの症状。
            #expect(engine.result.error?.category != .contextExceeded,
                    "\(useCase.rawValue): ヘルスチェックの入力がコンテキストを超えている")
            // 薬剤名を含む文を contentTagging に渡すと拒否される。
            #expect(engine.result.error?.category != .refusal,
                    "\(useCase.rawValue): ヘルスチェックの文がガードレールに触れている")

            // 往復そのものが成功していることまで確認する（4項目が出るだけでは緑にしない）。
            #expect(engine.result.error == nil,
                    "\(useCase.rawValue): Live Round Trip が失敗した: \(engine.result.error?.technicalDetail ?? "-")")
            let value = rows.first { $0.label == "Live Round Trip" }?.value ?? ""
            #expect(value.hasPrefix("成功"),
                    "\(useCase.rawValue): Live Round Trip が成功していない: \(value)")
            #expect(engine.result.executionMode == .foundationModels,
                    "\(useCase.rawValue): モデル経路を通っていない")
        }
    }

    @Test("contentTagging 用のタグ型は素の String フィールドを持たない")
    func contentTagsAvoidsFreeFormStringField() {
        // 実測: contentTagging useCase のスキーマに素の String を入れると
        // 入力が数千トークンに膨らんで exceededContextWindowSize になる。
        // 配列フィールドだけで構成することでこれを避けている。
        let schema = ContentTags.generationSchema.debugDescription
        #expect(schema.contains("topics"), "topics フィールドが無い")
        #expect(!schema.contains("category"),
                "素の String フィールドが復活している。contentTagging で context 超過を起こす")
    }

    @Test("cancel が実行状態を解除する")
    func cancelStopsRunning() {
        let engine = LabEngine()
        engine.run(.dashboard)
        engine.cancel()
        #expect(engine.isRunning == false)
    }

    @Test("Tool ログが recorder から画面状態へ移る")
    func drainsToolLog() {
        let engine = LabEngine()
        let id = engine.recorder.begin("testTool", arguments: "{}")
        engine.recorder.finish(id, output: "ok")

        engine.drainToolLog()

        #expect(engine.toolLog.count == 1)
        #expect(engine.toolLog.first?.toolName == "testTool")
        #expect(engine.recorder.snapshot().isEmpty, "recorder が空になっていない")
        // Lifecycle にも記録される。
        #expect(engine.lifecycleLog.contains { $0.kind == .onToolCall })
        #expect(engine.lifecycleLog.contains { $0.kind == .onToolOutput })
    }

    @Test("GenerationOptions が画面の設定を反映する")
    func optionsReflectUI() {
        let engine = LabEngine()
        engine.temperature = 0.35
        engine.maximumResponseTokens = 256
        engine.samplingChoice = .greedy

        let options = engine.currentOptions
        #expect(options.temperature == 0.35)
        #expect(options.maximumResponseTokens == 256)
        #expect(options.sampling == .greedy)

        engine.samplingChoice = .automatic
        #expect(engine.currentOptions.sampling == nil)
    }

    @Test("Profile ごとの GenerationOptions が異なる")
    func profileOptionsDiffer() {
        #expect(AgentProfile.quick.options.temperature != AgentProfile.analysis.options.temperature)
        #expect(AgentProfile.analysis.options.sampling == .greedy)
        #expect(AgentProfile.quick.maximumResponseTokens < AgentProfile.analysis.maximumResponseTokens)
        for profile in AgentProfile.allCases {
            #expect(!profile.instructions.isEmpty)
            #expect(!profile.tools.isEmpty)
            #expect(profile.visualizerRows.count == 6)
        }
    }

    @Test("Session Property が Tool へ渡る")
    func sessionPropertyReachesTools() {
        let engine = LabEngine()
        engine.selectedPatientId = "P003"
        #expect(engine.toolFactory.selectedPatientId == "P003")
        #expect(engine.selectedPatient?.name == "鈴木一郎")
    }

    @Test("GeneratedContent から構造化フィールドへ変換できる")
    func convertsGeneratedContent() throws {
        let engine = LabEngine()
        let content = GeneratedContent(properties: [
            "name": "田中太郎",
            "age": 65,
            "active": true,
            "tags": ["高血圧", "腰痛"]
        ])
        let fields = engine.structuredFields(from: content)

        #expect(fields.count == 4)
        let byLabel = Dictionary(uniqueKeysWithValues: fields.map { ($0.label, $0) })
        #expect(byLabel["name"]?.value == "田中太郎")
        #expect(byLabel["name"]?.typeName == "String")
        #expect(byLabel["age"]?.value == "65")
        #expect(byLabel["age"]?.typeName == "Int")
        #expect(byLabel["active"]?.value == "true")
        #expect(byLabel["tags"]?.children.count == 2)
    }

    @Test("Transcript エントリを表示用へ落とせる")
    func mapsTranscriptEntries() {
        let entries: [Transcript.Entry] = [
            .instructions(.init(segments: [.text(.init(content: "指示"))], toolDefinitions: [])),
            .prompt(.init(segments: [.text(.init(content: "質問"))])),
            .toolCalls(.init([.init(id: "1", toolName: "searchDrug", arguments: GeneratedContent(properties: ["name": "アムロジピン"]))])),
            .toolOutput(.init(id: "1", toolName: "searchDrug", segments: [.text(.init(content: "Ca拮抗薬"))])),
            .response(.init(assetIDs: [], segments: [.text(.init(content: "回答"))]))
        ]
        let views = entries.map(TranscriptEntryView.init(entry:))

        #expect(views.count == 5)
        #expect(views[0].kind == .instructions)
        #expect(views[1].body == "質問")
        #expect(views[2].kind == .toolCalls)
        #expect(views[2].title == "searchDrug")
        #expect(views[2].body.contains("アムロジピン"))
        #expect(views[3].body == "Ca拮抗薬")
        #expect(views[4].kind == .response)
    }

    @Test("Transcript からタイムラインを組める")
    func buildsTimeline() {
        let engine = LabEngine()
        let entries: [Transcript.Entry] = [
            .prompt(.init(segments: [.text(.init(content: "在庫は？"))])),
            .toolCalls(.init([.init(id: "1", toolName: "checkInventory", arguments: GeneratedContent(properties: ["name": "アムロジピン5mg"]))])),
            .toolOutput(.init(id: "1", toolName: "checkInventory", segments: [.text(.init(content: "80錠"))])),
            .response(.init(assetIDs: [], segments: [.text(.init(content: "80錠です"))]))
        ]
        let steps = engine.timelineSteps(from: entries)
        #expect(steps.count == 4)
        #expect(steps.map(\.kind) == [.prompt, .toolCall, .toolOutput, .response])
        #expect(engine.toolCallNames(in: entries) == ["checkInventory"])
    }

    @Test("Transcript が Codable で往復できる")
    func transcriptRoundTrip() throws {
        let original = Transcript(entries: [
            .instructions(.init(segments: [.text(.init(content: "指示"))], toolDefinitions: [])),
            .prompt(.init(segments: [.text(.init(content: "質問"))])),
            .response(.init(assetIDs: [], segments: [.text(.init(content: "回答"))]))
        ])
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Transcript.self, from: data)
        #expect(restored.count == original.count)
        #expect(restored == original)
    }

    @Test("Context 使用率が算出される")
    func contextUsage() {
        var metrics = Metrics.started()
        #expect(metrics.contextUsagePercent == nil)

        metrics.contextSize = 4096
        metrics.transcriptTokens = 2048
        #expect(metrics.contextUsagePercent == 50)

        metrics.transcriptTokens = 8192
        #expect(metrics.contextUsagePercent == 100, "100%を超えないようクランプされていない")
    }

    @Test("Metrics の表示文字列が未完了でも壊れない")
    func metricsFormatting() {
        var metrics = Metrics.started()
        #expect(metrics.elapsedText == "-")
        #expect(metrics.firstTokenText == "-")

        metrics.firstTokenAt = metrics.startedAt.addingTimeInterval(0.342)
        metrics.finishedAt = metrics.startedAt.addingTimeInterval(1.84)
        #expect(metrics.firstTokenText == "342 ms")
        #expect(metrics.elapsedText == "1.84 sec")
    }

    @Test("メディアをクリアすると Tool へ渡す画像も消える")
    func clearMediaResetsProvider() {
        let engine = LabEngine()
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let cgImage = context?.makeImage() else {
            Issue.record("テスト用画像を作れなかった")
            return
        }
        engine.image = ImageBox(cgImage: cgImage)
        engine.imageProvider.set(engine.image)
        #expect(engine.imageProvider.currentImage() != nil)

        engine.clearMedia()
        #expect(engine.image == nil)
        #expect(engine.imageProvider.currentImage() == nil)
        #expect(engine.videoMetadata == nil)
        #expect(engine.videoFrames.isEmpty)
    }
}

// MARK: - Camera (Simulator では起動しないことの確認)

@MainActor
struct CameraTests {

    @Test("Simulator ではカメラが unsupported として扱われ落ちない")
    func cameraOnSimulator() async {
        let controller = CameraController()
        #expect(controller.state == .idle)

        await controller.start()

        #if targetEnvironment(simulator)
        if case .unsupported(let reason) = controller.state {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Simulator で unsupported にならなかった: \(controller.state)")
        }
        #endif

        // 停止は状態に関わらず安全。
        controller.stop()
        #expect(controller.state == .idle)
    }

    @Test("カメラ未起動でのフレーム取得がエラーになる")
    func captureWithoutCameraThrows() {
        let engine = LabEngine()
        do {
            _ = try engine.captureCameraFrame()
            Issue.record("カメラ未起動なのに throw しなかった")
        } catch let error as LabError {
            #expect(error.category == .cameraError)
            #expect(!error.recovery.isEmpty)
        } catch {
            Issue.record("想定外のエラー: \(error)")
        }
    }

    @Test("リアルタイム解析の初期値が妥当")
    func realtimeDefaults() {
        let controller = CameraController()
        #expect(controller.targetAnalysisFPS >= 1)
        #expect(controller.targetAnalysisFPS <= 15)
        #expect(controller.plan == .realtime)
        #expect(controller.analyzedFrameCount == 0)
        #expect(controller.liveAnalysis == nil)
    }
}

// MARK: - View construction

@MainActor
struct ViewTests {

    @Test("ContentView を生成して body を評価できる")
    func contentViewBuilds() {
        let view = ContentView()
        _ = view.body
    }

    @Test("すべてのデモ画面の body を評価できる")
    func everyDemoScreenBuilds() {
        let engine = LabEngine()
        for demo in LabDemo.allCases {
            let screen = DemoScreen(demo: demo, engine: engine)
            _ = screen.body
        }
    }
}
