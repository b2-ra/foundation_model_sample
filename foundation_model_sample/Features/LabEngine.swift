//
//  LabEngine.swift
//  Foundation Models Lab
//
//  仕様書 §63 SessionManager: Session生成 / 保持 / Reset / Transcript管理 / Streaming管理 / Cancellation
//

import Foundation
import SwiftUI
import PhotosUI
import CoreGraphics
import AVFoundation
import FoundationModels

extension UIImage {
    /// EXIF の向きを反映した CGImage。
    /// `UIImage.cgImage` は回転前のバッファを返すので、そのまま Vision に渡すと
    /// 縦向きで撮った写真の文字が横倒しのまま解析され、OCR が何も拾えなくなる。
    /// 表示とオーバーレイの座標も揃えるため、ここで描き直して向きを確定させる。
    var uprightCGImage: CGImage? {
        guard imageOrientation != .up else { return cgImage }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let redrawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return redrawn.cgImage
    }
}

@Observable
final class LabEngine {

    // MARK: - Dependencies

    let modelManager = ModelManager()
    let camera = CameraController()

    nonisolated let recorder = ToolCallRecorder()
    nonisolated let inventory = InventoryStore()
    nonisolated let pendingSideEffectQueue = PendingSideEffectQueue()
    nonisolated let imageProvider = AnalyzableImageProvider()
    nonisolated private let visionAnalyzer = VisionAnalyzer()
    nonisolated private let videoAnalyzer = VideoAnalyzer()

    // MARK: - Text inputs

    /// デモごとの Prompt。画面を開いたときに、そのデモに合ったサンプルが入っている状態にする（仕様書 §69）。
    private var promptByDemo: [LabDemo: String] = [:]
    /// 現在表示しているデモ。Prompt の出し入れに使う。
    private(set) var activeDemo: LabDemo = .simpleGeneration

    var prompt: String {
        get { promptByDemo[activeDemo] ?? Self.defaultPrompt(for: activeDemo) }
        set { promptByDemo[activeDemo] = newValue }
    }

    /// 画面を切り替えたときに呼ぶ。編集済みの Prompt はデモごとに保持される。
    func activate(_ demo: LabDemo) {
        guard demo != activeDemo else { return }
        activeDemo = demo
        resetPresentation()
    }

    /// 画面の表示状態を初期化する。
    /// 前の画面の Output や Transcript が残っていると、いま何を見ているのか分からなくなるため。
    /// 会話セッション自体は残す（Conversation デモの文脈保持が消えてしまうので、
    /// それを消すのは Reset Session ボタンの役割）。
    private func resetPresentation() {
        cancel(silently: true)
        result = .notExecuted(modelName: activeModelChoice.displayName)
        transcriptEntries = []
        toolLog = []
        _ = recorder.drain()
        lifecycleLog = []
        pendingSideEffects = []
        _ = pendingSideEffectQueue.drain()
        videoProgress = nil
        liveNarration = nil
        liveNarrationPartial = ""
    }

    private static func defaultPrompt(for demo: LabDemo) -> String {
        demo.promptPresets.first?.value ?? "石川県の特徴を100文字程度で説明してください。"
    }
    var instructions = "あなたは丁寧な技術解説者です。必ず日本語で答えてください。"
    var longText = DemoData.longText
    /// デモごとの入力テキスト。Prompt と同じく、画面に合ったサンプルが入っている状態にする。
    private var entityTextByDemo: [LabDemo: String] = [:]
    var entityText: String {
        get { entityTextByDemo[activeDemo] ?? Self.defaultEntityText(for: activeDemo) }
        set { entityTextByDemo[activeDemo] = newValue }
    }

    /// Extraction だけ既定入力が違う。理由は DemoData.entityExtractionSample のコメント。
    static func defaultEntityText(for demo: LabDemo) -> String {
        switch demo {
        case .extraction: DemoData.entityExtractionSample
        default: DemoData.extractionSample
        }
    }

    // MARK: - Media inputs

    var imageSelection: PhotosPickerItem?
    var secondImageSelection: PhotosPickerItem?
    var videoSelection: PhotosPickerItem?

    /// 読み込みが完了している選択。
    /// `.task(id:)` は画面を開き直すたびに同じ item で再発火するので、
    /// これを見て同じメディアの再ダウンロード / 再解析を止める。
    /// （再解析が走ると前画面の破棄で Vision が中断され、空の解析結果が残ってしまう）
    private var loadedImageSelection: PhotosPickerItem?
    private var loadedSecondImageSelection: PhotosPickerItem?
    private var loadedVideoSelection: PhotosPickerItem?

    /// いまの image がカメラで撮影した1枚か（ピッカーで選んだ写真ではないか）。
    /// image は Photo デモとカメラデモで共有しているので、出所を区別しないと
    /// 選んだ写真を「撮影したフレーム」として見せてしまう。
    private(set) var isImageFromCamera = false

    /// メディア読み込みの Task。画面が消えても続けられるように Engine 側で持つ。
    private var imageLoadTask: Task<Void, Never>?
    private var secondImageLoadTask: Task<Void, Never>?
    private var videoLoadTask: Task<Void, Never>?

    var image: ImageBox?
    var secondImage: ImageBox?
    var imageAnalysis: FrameAnalysis?
    var secondImageAnalysis: FrameAnalysis?
    var isLoadingMedia = false
    var mediaLoadError: String?

    var videoMetadata: VideoMetadata?
    var videoFrames: [FrameAnalysis] = []
    var videoFrameCount = 8
    var videoProgress: (done: Int, total: Int)?

    // MARK: - Live camera

    var liveNarration: LiveFrameNarration?
    var liveNarrationPartial: String = ""
    var isNarrating = false
    var autoNarrate = false
    var narrationIntervalSeconds: Double = 6
    var narrationCount = 0
    var lastNarrationElapsed: TimeInterval?
    private var narrationTask: Task<Void, Never>?

    // MARK: - Options

    var temperature: Double = 0.7
    var maximumResponseTokens = 512
    var samplingChoice: SamplingChoice = .automatic
    var activeProfile: AgentProfile = .quick
    var activeModelChoice: ModelChoice = .onDevice
    var selectedPatientId = "P001"
    var expertiseMode: ExpertiseMode = .beginner
    var summaryStyle: SummaryStyle = .threeLines
    var rewriteStyle: RewriteStyle = .business
    var chunkTokenBudget = 200
    var historyWindow = 20
    var errorTrigger: ErrorTrigger = .contextExceeded
    var schemaFields: [SchemaField] = [
        SchemaField(name: "name", type: .string, fieldDescription: "人物の氏名"),
        SchemaField(name: "age", type: .integer, fieldDescription: "年齢"),
        SchemaField(name: "city", type: .string, fieldDescription: "居住都市")
    ]
    var dynamicSchemaRecordCount = 1
    var playgroundTools: Set<LabToolName> = [.drugSearch, .inventory]
    var useStructuredOutput = false
    var useStreaming = false

    // MARK: - Output state

    var result: DemoExecutionResult
    var toolLog: [ToolLogEntry] = []
    var lifecycleLog: [LifecycleEvent] = []
    var transcriptEntries: [TranscriptEntryView] = []
    /// 画面を切り替えても消さない、セッション全体の履歴。Logs 画面が参照する。
    private(set) var sessionToolLog: [ToolLogEntry] = []
    private(set) var sessionLifecycleLog: [LifecycleEvent] = []
    var pendingSideEffects: [SideEffectRequest] = []
    var isRunning = false
    private var runningTask: Task<Void, Never>?

    /// 仕様書 §10: 会話デモは同じセッションを持ち続ける。
    private(set) var conversationSession: LanguageModelSession?
    /// 仕様書 §38: 保存した Transcript。
    var savedTranscriptData: Data?
    var savedTranscriptEntryCount = 0
    /// History Transform / Context Window 用に積み上げる履歴。
    private(set) var workingSession: LanguageModelSession?

    init() {
        result = .notExecuted(modelName: ModelChoice.onDevice.displayName)
        activeModelChoice = .onDevice
    }

    // MARK: - Derived

    var selectedPatient: Patient? {
        DemoData.patients.first { $0.id == selectedPatientId }
    }

    var toolFactory: ToolFactory {
        ToolFactory(
            recorder: recorder,
            inventory: inventory,
            pendingSideEffects: pendingSideEffectQueue,
            imageProvider: imageProvider,
            selectedPatientId: selectedPatientId
        )
    }

    var currentOptions: GenerationOptions {
        GenerationOptions(
            sampling: samplingChoice.samplingMode,
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
        )
    }

    var labModel: any LabLanguageModel {
        switch activeModelChoice {
        case .onDevice:
            SystemModelAdapter(capabilities: modelManager.capabilities, model: modelManager.systemModel)
        case .pcc:
            UnavailablePCCModel()
        case .custom:
            MockExecutorModel()
        }
    }

    // MARK: - Run / Cancel

    func run(_ demo: LabDemo) {
        cancel(silently: true)
        // 画面表示時にも呼んでいるが、Prompt をデモ単位で持っているのでここでも合わせておく。
        if demo != activeDemo {
            activeDemo = demo
        }
        resetPresentation()

        result = DemoExecutionResult(
            startedAt: Date(),
            finishedAt: nil,
            modelName: activeModelChoice.displayName,
            apiTypeName: activeModelChoice.apiTypeName,
            metrics: .started(),
            capabilities: modelManager.capabilities,
            usedAPIs: demo.usedAPIs
        )
        isRunning = true
        log(.onPrompt, "\(demo.title) を実行")

        runningTask = Task { [weak self] in
            guard let self else { return }
            await self.execute(demo)
        }
    }

    func cancel(silently: Bool = false) {
        runningTask?.cancel()
        runningTask = nil
        isRunning = false
        if !silently {
            log(.onCancel, "実行をキャンセルしました")
            result.error = LabError.map(CancellationError())
            result.finishedAt = Date()
            result.metrics.finishedAt = Date()
        }
    }

    /// 仕様書 §63 Session Reset。
    func resetSessions() {
        conversationSession = nil
        workingSession = nil
        transcriptEntries = []
        toolLog = []
        _ = recorder.drain()
        lifecycleLog = []
        sessionToolLog = []
        sessionLifecycleLog = []
        pendingSideEffects = []
        _ = pendingSideEffectQueue.drain()
        inventory.reset()
        result = .notExecuted(modelName: activeModelChoice.displayName)
        log(.onDeactivate, "セッションと履歴をリセットしました")
    }

    func refreshEnvironment() {
        modelManager.refresh()
    }

    // MARK: - Execution wrapper

    private func execute(_ demo: LabDemo) async {
        let started = Date()
        defer { isRunning = false }

        do {
            try await runDemo(demo)
            guard !Task.isCancelled else { return }
            result.finishedAt = Date()
            result.metrics.finishedAt = result.finishedAt
            result.metrics.contextSize = modelManager.contextSize
            log(.onResponse, "\(demo.title) が完了（\(result.metrics.elapsedText)）")
        } catch {
            guard !Task.isCancelled || error is CancellationError else { return }
            let mapped = LabError.map(error)
            result.error = mapped
            result.finishedAt = Date()
            result.metrics.finishedAt = result.finishedAt
            if result.executionMode == .notExecuted {
                result.executionMode = .foundationModels
            }
            if result.payload.isEmpty {
                result.payload = .keyValue([
                    KeyValueRow(label: "Status", value: "エラーで停止しました", status: .error)
                ])
            }
            log(.onError, "\(mapped.errorType): \(mapped.userMessage)")
        }
        drainToolLog()
        drainPendingSideEffects()
        _ = started
    }

    // MARK: - Session helpers

    /// FoundationModels が使えるかを確認し、使えなければ理由付きで throw する。
    func requireAvailableModel() throws {
        guard modelManager.availability.isAvailable else {
            throw LabError.unavailable(modelManager.availability)
        }
    }

    func makeSession(instructions: String? = nil, tools: Set<LabToolName> = []) -> LanguageModelSession {
        modelManager.makeSession(
            instructions: instructions,
            tools: tools.isEmpty ? [] : toolFactory.tools(for: tools)
        )
    }

    /// 出力形式の揺れ（decodingFailure / generationFailure）だけ、可能なら1回作り直して再試行する。
    ///
    /// 端末モデルは同じ入力でもスキーマへ収まらない出力を返すことがある。
    /// 1回のデコード失敗でデモ全体を失敗させると、実装が正しいのに画面がエラーになり、
    /// 何を確認する画面なのか分からなくなる。2回目も失敗したら投げ返し、4項目エラーとして見せる。
    /// ただし既存の LanguageModelSession を渡された場合は、失敗した試行の状態を安全に捨てられないため再試行しない。
    ///
    /// guardrailViolation と refusal はここで再試行しない（LabError.isRetriableRejection 参照）。
    /// Apple の安全ガイドは、ガードレール違反には言い回しの変更と利用者への明示を求めており、
    /// 同じ文面の自動再送は推奨されていない。画面には recovery「プロンプトの表現を変更して
    /// 再実行してください」を出し、判断を利用者に返す。
    func retryingOnTransientFailure<T>(retryAllowed: Bool = true, _ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            guard retryAllowed && LabError.isRetriableRejection(error) else { throw error }
            try Task.checkCancellation()
            log(.onError, "出力形式の揺れで失敗したため1回だけ再試行します（\(LabError.map(error).category.rawValue)）")
            return try await body()
        }
    }

    /// 素のテキスト応答。実行モードとメトリクスを記録する。
    func respond(
        _ prompt: String,
        instructions: String? = nil,
        tools: Set<LabToolName> = [],
        options: GenerationOptions? = nil,
        session existing: LanguageModelSession? = nil
    ) async throws -> (text: String, session: LanguageModelSession) {
        try requireAvailableModel()
        result.executionMode = .foundationModels
        result.promptTokensIfPossible(await tokenCount(prompt))

        // 新規セッションの単発生成だけ1回作り直す。既存セッションでは履歴状態を壊さないため再試行しない。
        let (content, session) = try await retryingOnTransientFailure(retryAllowed: existing == nil) { () -> (String, LanguageModelSession) in
            let session = existing ?? self.makeSession(instructions: instructions, tools: tools)
            let response = try await session.respond(to: prompt, options: options ?? self.currentOptions)
            return (response.content, session)
        }
        publishTranscript(session)
        return (content, session)
    }

    /// 構造化出力。
    func respond<Content: Generable>(
        _ prompt: String,
        generating type: Content.Type,
        instructions: String? = nil,
        tools: Set<LabToolName> = [],
        options: GenerationOptions? = nil,
        session existing: LanguageModelSession? = nil
    ) async throws -> (content: Content, raw: GeneratedContent, session: LanguageModelSession) {
        try requireAvailableModel()
        result.executionMode = .foundationModels
        result.promptTokensIfPossible(await tokenCount(prompt))

        let (content, raw, session) = try await retryingOnTransientFailure(retryAllowed: existing == nil) { () -> (Content, GeneratedContent, LanguageModelSession) in
            let session = existing ?? self.makeSession(instructions: instructions, tools: tools)
            let response = try await session.respond(to: prompt, generating: type, options: options ?? self.currentOptions)
            return (response.content, response.rawContent, session)
        }
        publishTranscript(session)
        return (content, raw, session)
    }

    /// ストリーミング。partial が届くたびにコールバックする。
    func stream(
        _ prompt: String,
        instructions: String? = nil,
        tools: Set<LabToolName> = [],
        options: GenerationOptions? = nil,
        session existing: LanguageModelSession? = nil,
        onPartial: (String) -> Void
    ) async throws -> (text: String, session: LanguageModelSession) {
        try requireAvailableModel()
        let session = existing ?? makeSession(instructions: instructions, tools: tools)
        result.executionMode = .foundationModels
        let responseStream = session.streamResponse(to: prompt, options: options ?? currentOptions)
        var text = ""
        var first: Date?
        for try await snapshot in responseStream {
            try Task.checkCancellation()
            if first == nil {
                first = Date()
                result.metrics.firstTokenAt = first
            }
            text = snapshot.content
            onPartial(text)
        }
        let response = try await responseStream.collect()
        text = response.content
        onPartial(text)
        publishTranscript(session)
        return (text, session)
    }

    func tokenCount(_ text: String) async -> Int? {
        guard modelManager.availability.isAvailable else { return nil }
        return try? await modelManager.tokenCount(for: text)
    }

    // MARK: - Transcript

    func publishTranscript(_ session: LanguageModelSession) {
        transcriptEntries = session.transcript.map(TranscriptEntryView.init(entry:))
        result.transcript = transcriptEntries
        workingSession = session
    }

    var latestSession: LanguageModelSession? { workingSession ?? conversationSession }

    func conversationSessionOrCreate() -> LanguageModelSession {
        if let conversationSession { return conversationSession }
        // Instructions に if-else を書かない（Apple「Prompting an on-device foundation model」の
        // Turn conditional prompting into programming logic）。
        // 実測: 「履歴が無い状態で『さっき』と聞かれたら…と答えてください」という条件文を入れていたところ、
        // モデルがその条件文をそのまま応答へ復唱し、1ターン目から「会話履歴はまだありません」と言い出して
        // 名前の保持にも失敗した。条件は文章で持たせず、必要ならコード側で分岐させる。
        let session = modelManager.makeSession(
            instructions: """
            あなたは会話の文脈を覚えているアシスタントです。
            ユーザーが伝えた名前や役割は、後の質問で必ず使ってください。
            会話に出ていない話題や名前は推測しないでください。
            必ず日本語で答えてください。
            """
        )
        conversationSession = session
        return session
    }

    // MARK: - Logs

    func log(_ kind: LifecycleEvent.Kind, _ detail: String) {
        let event = LifecycleEvent(kind: kind, detail: detail, date: Date())
        lifecycleLog.append(event)
        if lifecycleLog.count > 200 { lifecycleLog.removeFirst(lifecycleLog.count - 200) }
        sessionLifecycleLog.append(event)
        if sessionLifecycleLog.count > 500 { sessionLifecycleLog.removeFirst(sessionLifecycleLog.count - 500) }
    }

    /// Tool 側（nonisolated）で積まれたログを画面状態へ移す。
    func drainToolLog() {
        let drained = recorder.drain()
        guard !drained.isEmpty else { return }
        for entry in drained {
            log(.onToolCall, "\(entry.toolName) \(entry.arguments)")
            log(.onToolOutput, "\(entry.toolName) → \(entry.output.prefix(80))")
        }
        toolLog.append(contentsOf: drained)
        if toolLog.count > 100 { toolLog.removeFirst(toolLog.count - 100) }
        sessionToolLog.append(contentsOf: drained)
        if sessionToolLog.count > 300 { sessionToolLog.removeFirst(sessionToolLog.count - 300) }
        result.toolCalls = drained
    }

    func drainPendingSideEffects() {
        let drained = pendingSideEffectQueue.drain()
        guard !drained.isEmpty else { return }
        pendingSideEffects.append(contentsOf: drained)
    }

    // MARK: - Side effect approval（仕様書 §76）

    func approve(_ request: SideEffectRequest) {
        guard let updated = inventory.setStock(request.newStock, for: request.drugName) else { return }
        pendingSideEffects.removeAll { $0.id == request.id }
        log(.onToolOutput, "人間の承認により \(updated.name) を \(updated.stock)\(updated.unit) へ更新")
        result.payload = .keyValue(
            [KeyValueRow(label: "承認結果", value: "\(updated.name) を \(request.currentStock) → \(updated.stock) に更新しました", status: .success)]
                + inventory.all.map { KeyValueRow(label: $0.name, value: "\($0.stock)\($0.unit)", status: $0.isLow ? .warning : .success) }
        )
        result.debugDetail = "Tool は申請のみを行い、実際の書き換えはこの承認ハンドラで実行された。AIの判断だけでは状態が変わらない。"
    }

    func reject(_ request: SideEffectRequest) {
        pendingSideEffects.removeAll { $0.id == request.id }
        log(.onToolOutput, "人間の判断により \(request.drugName) の更新を却下")
        result.payload = .keyValue([
            KeyValueRow(label: "承認結果", value: "更新をキャンセルしました。在庫は変更されていません。", status: .warning),
            KeyValueRow(label: request.drugName, value: "\(request.currentStock)錠（変更なし）")
        ])
        result.debugDetail = "Tool Call → Human Confirmation → (却下) の経路。AIは状態を変更できない。"
    }

    // MARK: - Media loading

    func loadImage(_ item: PhotosPickerItem?, slot: ImageSlot) async {
        guard let item else { return }
        // 同じ写真が使える状態で残っているなら何もしない。
        // 解析が中断されて残らなかった場合だけ、開き直したときに取り直す。
        guard !isFullyLoaded(item, slot: slot) else { return }
        isLoadingMedia = true
        mediaLoadError = nil
        defer { isLoadingMedia = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            mediaLoadError = "画像データを読み込めませんでした。"
            return
        }
        guard let uiImage = UIImage(data: data), let cgImage = uiImage.uprightCGImage else {
            mediaLoadError = "画像を CGImage へ変換できませんでした。"
            return
        }
        let box = ImageBox(cgImage: cgImage)

        switch slot {
        case .primary:
            image = box
            imageProvider.set(box)
            loadedImageSelection = item
            isImageFromCamera = false
            // 前の写真の解析結果を先に捨てる。中断された場合は nil のまま残し、
            // 実行時に作り直させる（空の解析結果を「検出0件」として見せない）。
            imageAnalysis = nil
            imageAnalysis = try? await visionAnalyzer.analyze(cgImage: cgImage, plan: .full)
        case .secondary:
            secondImage = box
            loadedSecondImageSelection = item
            secondImageAnalysis = nil
            secondImageAnalysis = try? await visionAnalyzer.analyze(cgImage: cgImage, plan: .full)
        }
        log(.onActivate, "画像を読み込みました (\(cgImage.width)×\(cgImage.height))")
    }

    /// 写真ピッカーが選択を書き込んだ瞬間に、ここから読み込みを開始する。
    ///
    /// 以前は DemoScreen の `.task(id: engine.imageSelection)` に任せていたが、
    /// 画面の再評価やナビゲーションのタイミング次第で発火せず / 途中で中断され、
    /// 「選択したのに画像が入らない」状態になることがあった。
    /// Task を Engine 側で持つことで、画面の生存期間から切り離す。
    func loadImageIfNeeded(_ item: PhotosPickerItem?, slot: ImageSlot) {
        guard let item, !isFullyLoaded(item, slot: slot) else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadImage(item, slot: slot)
        }
        switch slot {
        case .primary:
            imageLoadTask?.cancel()
            imageLoadTask = task
        case .secondary:
            secondImageLoadTask?.cancel()
            secondImageLoadTask = task
        }
    }

    func loadVideoIfNeeded(_ item: PhotosPickerItem?) {
        guard let item, !(loadedVideoSelection == item && videoMetadata != nil) else { return }
        videoLoadTask?.cancel()
        videoLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadVideo(item)
        }
    }

    /// 標準カメラで撮影した1枚を、写真ピッカーで選んだのと同じ画像スロットへ入れる。
    func acceptCapturedPhoto(_ uiImage: UIImage, slot: ImageSlot) {
        Task { await loadCapturedPhoto(uiImage, slot: slot) }
    }

    func loadCapturedPhoto(_ uiImage: UIImage, slot: ImageSlot) async {
        isLoadingMedia = true
        mediaLoadError = nil
        defer { isLoadingMedia = false }

        guard let cgImage = uiImage.uprightCGImage else {
            mediaLoadError = "撮影した画像を CGImage へ変換できませんでした。"
            return
        }
        let box = ImageBox(cgImage: cgImage)

        switch slot {
        case .primary:
            // ピッカー由来の選択は切り離す（同じ写真をあとで選び直せるようにする）。
            imageSelection = nil
            loadedImageSelection = nil
            image = box
            imageProvider.set(box)
            isImageFromCamera = true
            imageAnalysis = nil
            imageAnalysis = try? await visionAnalyzer.analyze(cgImage: cgImage, plan: .full)
        case .secondary:
            secondImageSelection = nil
            loadedSecondImageSelection = nil
            secondImage = box
            secondImageAnalysis = nil
            secondImageAnalysis = try? await visionAnalyzer.analyze(cgImage: cgImage, plan: .full)
        }
        log(.onActivate, "カメラで撮影した画像を取り込みました (\(cgImage.width)×\(cgImage.height))")
    }

    /// その写真が「表示も解析も済んでいる」状態か。
    func isFullyLoaded(_ item: PhotosPickerItem, slot: ImageSlot) -> Bool {
        switch slot {
        case .primary:
            loadedImageSelection == item && image != nil && imageAnalysis?.isReusable == true
        case .secondary:
            loadedSecondImageSelection == item && secondImage != nil && secondImageAnalysis?.isReusable == true
        }
    }

    func loadVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        // 同じ動画なら読み直さない。ここを通すと解析済みのコマまで消えてしまう。
        guard !(loadedVideoSelection == item && videoMetadata != nil) else { return }
        isLoadingMedia = true
        mediaLoadError = nil
        videoFrames = []
        videoMetadata = nil
        defer { isLoadingMedia = false }

        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else {
            mediaLoadError = "動画データを読み込めませんでした。別の動画を選択してください。"
            return
        }
        do {
            videoMetadata = try await videoAnalyzer.metadata(for: movie.url)
            loadedVideoSelection = item
            log(.onActivate, "動画を読み込みました (\(videoMetadata?.durationText ?? "-"))")
        } catch {
            mediaLoadError = LabError.map(error).userMessage
        }
    }

    func clearMedia() {
        imageLoadTask?.cancel()
        secondImageLoadTask?.cancel()
        videoLoadTask?.cancel()
        image = nil
        secondImage = nil
        imageAnalysis = nil
        secondImageAnalysis = nil
        imageSelection = nil
        secondImageSelection = nil
        videoSelection = nil
        loadedImageSelection = nil
        loadedSecondImageSelection = nil
        loadedVideoSelection = nil
        isImageFromCamera = false
        videoMetadata = nil
        videoFrames = []
        videoProgress = nil
        imageProvider.set(nil)
        mediaLoadError = nil
    }

    enum ImageSlot: Sendable { case primary, secondary }

    /// カメラプレビューから1枚取り込み、写真ピッカーで選んだのと同じ画像スロットへ入れる。
    /// これで撮影した1枚が Photo デモと同じ扱いになり、
    /// カメラを止めても画像・Vision 解析・オーバーレイが残る。
    func captureCameraStill() async {
        isLoadingMedia = true
        mediaLoadError = nil
        defer { isLoadingMedia = false }

        let captured: (source: VisionSource, image: ImageBox)
        do {
            captured = try captureCameraFrame()
        } catch {
            mediaLoadError = LabError.map(error).userMessage
            log(.onError, LabError.map(error).userMessage)
            return
        }

        // ピッカー由来の選択とは切り離す。
        // ここを残すと、同じ写真をあとで選び直しても読み込まれない。
        imageSelection = nil
        loadedImageSelection = nil
        image = captured.image
        isImageFromCamera = true
        imageAnalysis = nil
        imageAnalysis = try? await analyze(source: captured.source, plan: .full)
        log(.onActivate, "カメラのフレームを取り込みました (\(captured.image.cgImage.width)×\(captured.image.cgImage.height))")
    }

    // MARK: - Live camera narration

    func startCamera() async {
        await camera.start()
        if camera.state.isRunning {
            log(.onActivate, "カメラセッションを開始（Vision \(Int(camera.targetAnalysisFPS)) fps 目標）")
        } else if let message = camera.state.message {
            log(.onError, message)
        }
    }

    func stopCamera() {
        stopAutoNarration()
        camera.stop()
        log(.onDeactivate, "カメラセッションを停止")
    }

    func setAutoNarration(_ enabled: Bool) {
        autoNarrate = enabled
        if enabled {
            startAutoNarration()
        } else {
            stopAutoNarration()
        }
    }

    private func startAutoNarration() {
        narrationTask?.cancel()
        narrationTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if self.camera.state.isRunning, self.camera.liveAnalysis != nil, !self.isNarrating {
                    await self.narrateCurrentFrame()
                }
                let interval = max(2.0, self.narrationIntervalSeconds)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func stopAutoNarration() {
        narrationTask?.cancel()
        narrationTask = nil
        isNarrating = false
    }

    /// 直近の Vision 解析結果を言語モデルへ渡し、実況を構造化出力で受け取る。
    func narrateCurrentFrame() async {
        guard let analysis = camera.liveAnalysis else { return }
        guard modelManager.availability.isAvailable else {
            liveNarrationPartial = "モデルが利用できないため実況できません。Vision の解析結果のみ表示しています。"
            return
        }
        isNarrating = true
        let started = Date()
        defer {
            isNarrating = false
            lastNarrationElapsed = Date().timeIntervalSince(started)
        }

        do {
            let narration = try await narrate(analysis: analysis) { [weak self] scene in
                self?.liveNarrationPartial = scene
            }
            liveNarration = narration
            liveNarrationPartial = narration.scene
            narrationCount += 1
        } catch is CancellationError {
            return
        } catch {
            liveNarrationPartial = LabError.map(error).userMessage
        }
    }

    /// 実況生成の本体。カメラを持たないテストからも同じ経路を通せるように分けている。
    ///
    /// 英語優位のラベル（薬剤ラベルの英字表記など）を OCR が読むと、日本語の指示が
    /// unsupportedLanguageOrLocale で拒否される。Vision デモ（respondBridging）と同じく、
    /// 拒否されたら指示を英語へ替えて1回だけ問い直す。同じ文面での再送は意味がない。
    func narrate(
        analysis: FrameAnalysis,
        onPartial: @escaping (String) -> Void = { _ in }
    ) async throws -> LiveFrameNarration {
        guard !analysis.observationDigest.isEmpty else {
            throw LabError.media("Vision がフレームから何も検出できませんでした。",
                                 recovery: "文字やバーコードが写るようにカメラを向けてください。")
        }
        do {
            return try await streamNarration(analysis: analysis, inEnglish: false, onPartial: onPartial)
        } catch {
            guard LabError.isUnsupportedLanguage(error) else { throw error }
            try Task.checkCancellation()
            log(.onError, "日本語の指示が拒否されたため英語で問い直します（観測テキストが英語優位）")
            return try await streamNarration(analysis: analysis, inEnglish: true, onPartial: onPartial)
        }
    }

    private func streamNarration(
        analysis: FrameAnalysis,
        inEnglish: Bool,
        onPartial: @escaping (String) -> Void
    ) async throws -> LiveFrameNarration {
        let instructions = inEnglish
            ? """
              You narrate what a camera currently sees. Base your answer only on the
              observations extracted by the Vision framework. Do not assert anything that
              is not in the observations.
              """
            : """
              あなたはカメラ映像の実況担当です。渡された Vision の解析結果だけを根拠に、今映っているものを説明してください。
              解析結果に無いものを推測して述べないでください。必ず日本語で答えてください。
              """
        // モデルへ渡すのは observationDigest（実行できなかったリクエストの一覧を含まない方）。
        // digest は画面の Vision Raw Result 用で、英語の API 名が並ぶためモデルへ渡すと
        // unsupportedLanguageOrLocale の原因になる。
        let promptText = inEnglish
            ? "[Vision observations]\n\(analysis.observationDigest)"
            : "[Vision解析結果]\n\(analysis.observationDigest)"

        let session = modelManager.makeSession(instructions: instructions)
        let stream = session.streamResponse(
            to: promptText,
            generating: LiveFrameNarration.self,
            options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 300)
        )
        for try await snapshot in stream {
            try Task.checkCancellation()
            if let scene = snapshot.content.scene {
                onPartial(scene)
            }
        }
        // 最終結果は同じストリームの collect() から取る。
        // ここで respond() を呼び直すと、1フレームにつき2回生成することになる。
        // collect() は正常終了済みのストリームに対しては即座に返る。
        return try await stream.collect().content
    }

    // MARK: - Vision access for demos

    func analyzeImage(_ image: ImageBox, plan: VisionAnalysisPlan) async throws -> FrameAnalysis {
        try await visionAnalyzer.analyze(cgImage: image.cgImage, plan: plan)
    }

    func analyzeVideoFrames(plan: VisionAnalysisPlan = .videoFrame) async throws -> [FrameAnalysis] {
        guard let metadata = videoMetadata else {
            throw LabError.media("動画が選択されていません。", recovery: "Choose Video から動画を選択してください。")
        }
        videoProgress = (0, videoFrameCount)
        let frames = try await videoAnalyzer.analyzeFrames(
            url: metadata.url,
            frameCount: videoFrameCount,
            plan: plan
        ) { _, done, total in
            // コールバックは nonisolated な文脈から呼ばれるので、MainActor へ明示的に渡す。
            Task { @MainActor [weak self] in
                self?.videoProgress = (done, total)
            }
        }
        videoFrames = frames
        videoProgress = nil
        return frames
    }

    func captureCameraFrame() throws -> (source: VisionSource, image: ImageBox) {
        guard camera.state.isRunning else {
            throw LabError.camera(
                camera.state.message ?? "カメラが起動していません。",
                recovery: "Start Camera を押してカメラを起動してください。"
            )
        }
        guard let captured = camera.captureCurrentFrame() else {
            throw LabError.camera("フレームをまだ受信していません。", recovery: "1〜2秒待ってから再実行してください。")
        }
        imageProvider.set(captured.image)
        return (captured.analysis, captured.image)
    }

    func analyze(source: VisionSource, plan: VisionAnalysisPlan) async throws -> FrameAnalysis {
        try await visionAnalyzer.analyze(source: source, plan: plan)
    }
}

// MARK: - Sampling choice

nonisolated enum SamplingChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case greedy
    case topK
    case threshold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .greedy: "Greedy"
        case .topK: "random(top: 50)"
        case .threshold: "random(p: 0.9)"
        }
    }

    var samplingMode: GenerationOptions.SamplingMode? {
        switch self {
        case .automatic: nil
        case .greedy: .greedy
        case .topK: .random(top: 50)
        case .threshold: .random(probabilityThreshold: 0.9)
        }
    }
}

// MARK: - Metrics helper

private extension DemoExecutionResult {
    mutating func promptTokensIfPossible(_ tokens: Int?) {
        if let tokens { metrics.promptTokens = tokens }
    }
}
