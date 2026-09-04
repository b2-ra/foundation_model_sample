//
//  DemoCatalog.swift
//  Foundation Models Lab
//
//  仕様書 §6 画面構成 / §83 完成版メニュー / §67 API表示 / §68 Source Code表示 / §69 Demo Preset
//

import Foundation

// MARK: - Group

nonisolated enum LabGroup: String, CaseIterable, Identifiable, Sendable {
    case overview
    case text
    case structured
    case tools
    case vision
    case session
    case privateCloud
    case agent
    case model
    case developer
    case playground
    case medical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "OVERVIEW"
        case .text: "TEXT"
        case .structured: "STRUCTURED OUTPUT"
        case .tools: "TOOLS"
        case .vision: "VISION & MEDIA"
        case .session: "SESSION"
        case .privateCloud: "PRIVATE CLOUD"
        case .agent: "AGENT"
        case .model: "MODEL"
        case .developer: "DEVELOPER"
        case .playground: "PLAYGROUND"
        case .medical: "MEDICAL DATA"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .text: "text.alignleft"
        case .structured: "curlybraces.square"
        case .tools: "wrench.and.screwdriver"
        case .vision: "photo.on.rectangle.angled"
        case .session: "rectangle.stack"
        case .privateCloud: "icloud"
        case .agent: "point.3.connected.trianglepath.dotted"
        case .model: "cpu"
        case .developer: "ladybug"
        case .playground: "sparkles"
        case .medical: "cross.case"
        }
    }
}

// MARK: - Inputs

/// 画面に出す入力コントロールの集合。
nonisolated struct DemoInputs: OptionSet, Sendable {
    let rawValue: Int

    static let prompt            = DemoInputs(rawValue: 1 << 0)
    static let instructions      = DemoInputs(rawValue: 1 << 1)
    static let longText          = DemoInputs(rawValue: 1 << 2)
    static let entityText        = DemoInputs(rawValue: 1 << 3)
    static let image             = DemoInputs(rawValue: 1 << 4)
    static let secondImage       = DemoInputs(rawValue: 1 << 5)
    static let video             = DemoInputs(rawValue: 1 << 6)
    static let camera            = DemoInputs(rawValue: 1 << 7)
    static let liveCamera        = DemoInputs(rawValue: 1 << 8)
    static let schemaFields      = DemoInputs(rawValue: 1 << 9)
    static let samplingOptions   = DemoInputs(rawValue: 1 << 10)
    static let summaryStyle      = DemoInputs(rawValue: 1 << 11)
    static let rewriteStyle      = DemoInputs(rawValue: 1 << 12)
    static let instructionPreset = DemoInputs(rawValue: 1 << 13)
    static let patientPicker     = DemoInputs(rawValue: 1 << 14)
    static let profilePicker     = DemoInputs(rawValue: 1 << 15)
    static let modelPicker       = DemoInputs(rawValue: 1 << 16)
    static let toolPicker        = DemoInputs(rawValue: 1 << 17)
    static let frameCount        = DemoInputs(rawValue: 1 << 18)
    static let expertiseMode     = DemoInputs(rawValue: 1 << 19)
    static let chunkSize         = DemoInputs(rawValue: 1 << 20)
    static let historyWindow     = DemoInputs(rawValue: 1 << 21)
    static let errorTrigger      = DemoInputs(rawValue: 1 << 22)
    static let structuredToggle  = DemoInputs(rawValue: 1 << 23)
    static let streamToggle      = DemoInputs(rawValue: 1 << 24)
    static let useCasePicker     = DemoInputs(rawValue: 1 << 25)

    var isEmpty: Bool { rawValue == 0 }

    /// Input セクションに置くコントロール。
    static let inputControls: DemoInputs = [
        .prompt, .instructions, .instructionPreset, .longText, .entityText,
        .image, .secondImage, .video, .camera, .liveCamera
    ]

    /// Options セクションに置くコントロール。
    /// frameCount は動画プレビューの直下に置きたいので Input 側で描く（ここには含めない）。
    static let optionControls: DemoInputs = [
        .schemaFields, .samplingOptions, .summaryStyle, .rewriteStyle, .patientPicker,
        .profilePicker, .modelPicker, .toolPicker, .expertiseMode, .chunkSize,
        .historyWindow, .errorTrigger, .structuredToggle, .streamToggle, .useCasePicker
    ]

    var hasInputControls: Bool { !intersection(Self.inputControls).isEmpty }
    var hasOptionControls: Bool { !intersection(Self.optionControls).isEmpty }
}

// MARK: - Demo

nonisolated enum LabDemo: String, CaseIterable, Identifiable, Sendable {
    // OVERVIEW
    case dashboard
    // TEXT
    case simpleGeneration, instructions, conversation, streaming, summarization, rewrite, classification, extraction
    // STRUCTURED OUTPUT
    case generable, guideComparison, enumGeneration, nestedObject, dynamicSchema, generationOptions, greedySampling
    // TOOLS
    case basicTool, searchTool, multipleTools, multiStepTool, sideEffectTool
    // VISION & MEDIA
    case imageDescription, imageClassification, textRectangles, barcode, rectangles, faceRectangles, humanRectangles, saliency, aesthetics, compareImages, structuredVision, ocr, videoAnalysis, camera, liveCamera, visionTool
    // SESSION
    case transcript, restore, tokenCount, contextWindow, contextExceeded, chunking, historyTransform, prewarm
    // PRIVATE CLOUD
    case pcc, modelComparison, reasoning, quota
    // AGENT
    case dynamicInstructions, dynamicProfile, profileVisualizer, toolVisibility, sessionProperty, lifecycleEvents, agentWorkflow, visionAgent
    // MODEL
    case capabilities, customModel, modelSwitch
    // DEVELOPER
    case errorLab, logs, apiReference
    // PLAYGROUND
    case playground
    // MEDICAL DATA
    case medicalInformationHandling

    var id: String { rawValue }

    static func demos(in group: LabGroup) -> [LabDemo] {
        allCases.filter { $0.group == group }
    }

    var group: LabGroup {
        switch self {
        case .dashboard: .overview
        case .simpleGeneration, .instructions, .conversation, .streaming, .summarization, .rewrite, .classification, .extraction: .text
        case .generable, .guideComparison, .enumGeneration, .nestedObject, .dynamicSchema, .generationOptions, .greedySampling: .structured
        case .basicTool, .searchTool, .multipleTools, .multiStepTool, .sideEffectTool: .tools
        case .imageDescription, .imageClassification, .textRectangles, .barcode, .rectangles, .faceRectangles, .humanRectangles, .saliency, .aesthetics, .compareImages, .structuredVision, .ocr, .videoAnalysis, .camera, .liveCamera, .visionTool: .vision
        case .transcript, .restore, .tokenCount, .contextWindow, .contextExceeded, .chunking, .historyTransform, .prewarm: .session
        case .pcc, .modelComparison, .reasoning, .quota: .privateCloud
        case .dynamicInstructions, .dynamicProfile, .profileVisualizer, .toolVisibility, .sessionProperty, .lifecycleEvents, .agentWorkflow, .visionAgent: .agent
        case .capabilities, .customModel, .modelSwitch: .model
        case .errorLab, .logs, .apiReference: .developer
        case .playground: .playground
        case .medicalInformationHandling: .medical
        }
    }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .simpleGeneration: "Simple Generation"
        case .instructions: "Instructions"
        case .conversation: "Conversation"
        case .streaming: "Streaming"
        case .summarization: "Summarization"
        case .rewrite: "Rewrite"
        case .classification: "Classification"
        case .extraction: "Extraction"
        case .generable: "Generable"
        case .guideComparison: "Guide"
        case .enumGeneration: "Enum"
        case .nestedObject: "Nested Object"
        case .dynamicSchema: "Dynamic Schema"
        case .generationOptions: "Generation Options"
        case .greedySampling: "Greedy Sampling"
        case .basicTool: "Basic Tool"
        case .searchTool: "Search Tool"
        case .multipleTools: "Multiple Tools"
        case .multiStepTool: "Multi-step Tool"
        case .sideEffectTool: "Side Effect Tool"
        case .imageDescription: "Photo Description"
        case .imageClassification: "Photo Classification"
        case .textRectangles: "Text Rectangles"
        case .compareImages: "Compare Photos"
        case .structuredVision: "Structured Vision"
        case .ocr: "OCR"
        case .barcode: "Barcode"
        case .rectangles: "Rectangles"
        case .faceRectangles: "Face Rectangles"
        case .humanRectangles: "Human Rectangles"
        case .saliency: "Saliency"
        case .aesthetics: "Aesthetics"
        case .videoAnalysis: "Video Analysis"
        case .camera: "Camera Frame"
        case .liveCamera: "Live Camera"
        case .visionTool: "Vision + Tool"
        case .transcript: "Transcript"
        case .restore: "Session Restore"
        case .tokenCount: "Token Count"
        case .contextWindow: "Context Window"
        case .contextExceeded: "Context Exceeded"
        case .chunking: "Chunking"
        case .historyTransform: "History Transform"
        case .prewarm: "Prewarm"
        case .pcc: "PCC"
        case .modelComparison: "Model Comparison"
        case .reasoning: "Reasoning Level"
        case .quota: "Quota"
        case .dynamicInstructions: "Dynamic Instructions"
        case .dynamicProfile: "Dynamic Profile"
        case .profileVisualizer: "Profile Visualizer"
        case .toolVisibility: "Tool Visibility"
        case .sessionProperty: "Session Property"
        case .lifecycleEvents: "Lifecycle Events"
        case .agentWorkflow: "Agent Workflow"
        case .visionAgent: "Vision Agent"
        case .capabilities: "Capabilities"
        case .customModel: "Custom Model"
        case .modelSwitch: "Model Switch"
        case .errorLab: "Error Lab"
        case .logs: "Logs"
        case .apiReference: "API Reference"
        case .playground: "Foundation Models Playground"
        case .medicalInformationHandling: "Medical Information Handling"
        }
    }

    /// 1行の説明（仕様書 §66 Short Description）。
    var subtitle: String {
        switch self {
        case .dashboard: "この端末の Apple Intelligence / モデル状態と、SDKが実際に提供している機能を確認する"
        case .simpleGeneration: "Prompt → LanguageModelSession → Response<String> という最小構成を確認する"
        case .instructions: "Instructions を書き換えると同じ Prompt の回答スタイルが変わることを確認する"
        case .conversation: "同一セッションが会話コンテキストを保持することを確認する"
        case .streaming: "streamResponse で部分応答が届く様子と初回トークン到達時間を見る"
        case .summarization: "要約の長さを指定し、@Generable で要点も一緒に受け取る"
        case .rewrite: "同じ文章をプリセットごとに書き換える"
        case .classification: "自由文を @Generable enum のケースとして受け取る"
        case .extraction: "文章から人物・品名・数量・日付を配列として抽出する"
        case .generable: "@Generable な Swift の型として処方内容を生成する"
        case .guideComparison: "同じ入力に対する @Guide あり / なしの出力を並べて比較する"
        case .enumGeneration: "自由文字列ではなく enum のケースに必ず収める"
        case .nestedObject: "入れ子と配列を含む複雑な構造を一度に生成する"
        case .dynamicSchema: "コンパイル時に型を決めず、画面で組んだ DynamicGenerationSchema で生成する"
        case .generationOptions: "temperature と最大トークン数を変えて同じ Prompt を複数回実行する"
        case .greedySampling: "greedy と random サンプリングで結果の揺れ方を比較する"
        case .basicTool: "モデルが WeatherTool を呼ぶ様子を Transcript で確認する"
        case .searchTool: "ローカルの DrugDatabase.json を Tool 経由で検索させる"
        case .multipleTools: "複数の Tool から適切なものをモデルが選ぶことを確認する"
        case .multiStepTool: "複数の Tool を連続して呼ぶ過程をタイムラインで見る"
        case .sideEffectTool: "更新系 Tool は申請だけを行い、実行前に人間の確認を挟む"
        case .imageDescription: "写真を選び、Vision の解析結果をモデルに説明させる"
        case .imageClassification: "ClassifyImageRequest だけを実行し、分類ラベルと信頼度を見る"
        case .textRectangles: "DetectTextRectanglesRequest だけを実行し、文字らしい領域の枠を見る"
        case .compareImages: "2枚の写真の解析結果を比較させる"
        case .structuredVision: "写真から ImageAnalysis 構造体を生成する"
        case .ocr: "RecognizeTextRequest だけを実行し、文字列・信頼度・位置を表示する"
        case .barcode: "DetectBarcodesRequest だけを実行し、種別・ペイロード・位置を表示する"
        case .rectangles: "DetectRectanglesRequest だけを実行し、カードや書類のような矩形を検出する"
        case .faceRectangles: "DetectFaceRectanglesRequest だけを実行し、顔の領域を検出する"
        case .humanRectangles: "DetectHumanRectanglesRequest だけを実行し、人物の領域を検出する"
        case .saliency: "GenerateObjectnessBasedSaliencyImageRequest だけを実行し、注目領域を見る"
        case .aesthetics: "CalculateImageAestheticsScoresRequest だけを実行し、美的スコアを見る"
        case .videoAnalysis: "動画からコマを抜き出して1枚ずつ解析し、時系列としてモデルにまとめさせる"
        case .camera: "カメラプレビュー上で押した瞬間の1フレームだけを解析する"
        case .liveCamera: "カメラの連続フレームを Vision で解析し続け、一定間隔でモデルに実況させる"
        case .visionTool: "画像 → OCR/Barcode Tool → DrugSearchTool → 回答 をモデルに自走させる"
        case .transcript: "セッションの Transcript を Instruction / Prompt / Tool / Response に分解して見る"
        case .restore: "Transcript を保存し、新しいセッションへ履歴を引き継ぐ"
        case .tokenCount: "tokenCount(for:) で日本語と英語のトークン数を実測して比べる"
        case .contextWindow: "モデルの contextSize と現在の使用量を実測値で表示する"
        case .contextExceeded: "意図的に巨大な Prompt を送り、実際のエラーを4項目で表示する"
        case .chunking: "長文を分割して個別要約し、それを統合要約する"
        case .historyTransform: "長くなった履歴のうち直近N件だけをモデルへ送る"
        case .prewarm: "prewarm あり / なしで初回応答までの時間を実測して比べる"
        case .pcc: "Private Cloud Compute の利用可否をこのSDKで確認できる範囲で表示する"
        case .modelComparison: "同一 Prompt を複数モデルへ投げて結果と時間を並べる"
        case .reasoning: "reasoning 設定の有無をこのSDKで確認できる範囲で扱う"
        case .quota: "PCC のクォータ情報をこのSDKで確認できる範囲で表示する"
        case .dynamicInstructions: "アプリの状態に応じて Instructions を切り替える"
        case .dynamicProfile: "モデル・Tool・生成オプションをまとめた Profile を切り替える"
        case .profileVisualizer: "現在有効な Profile の中身を可視化する"
        case .toolVisibility: "Profile によってモデルに見せる Tool の範囲を変える"
        case .sessionProperty: "選択中の患者を Tool から参照させ、名前を言わずに処理させる"
        case .lifecycleEvents: "onActivate / onPrompt / onToolCall / onResponse の発火順を記録する"
        case .agentWorkflow: "患者検索 → 処方取得 → 在庫照会 → 判定 をモデルに自走させる"
        case .visionAgent: "画像 → バーコード → 薬品 → 在庫 → 回答 の複合フローを実行する"
        case .capabilities: "現在のモデルの Capabilities と、SDKが提供していない機能を区別して表示する"
        case .customModel: "LanguageModel 抽象を自作し、Mock Executor へ処理を流す"
        case .modelSwitch: "On-device / PCC / Custom を切り替えて比較する"
        case .errorLab: "発生しうるエラーを種類別に、4項目形式で表示・再現する"
        case .logs: "Tool Log と Lifecycle Log と Metrics をまとめて見る"
        case .apiReference: "全画面で使っている API の一覧とドキュメントリンク"
        case .playground: "モデル・Instructions・Prompt・Tool・構造化出力・オプションを自由に組み合わせる"
        case .medicalInformationHandling: "処方文を扱うときの guardrail に当たりやすい形と通しやすい形を同じ入力で比較する"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .simpleGeneration: "text.bubble"
        case .instructions: "text.badge.checkmark"
        case .conversation: "bubble.left.and.bubble.right"
        case .streaming: "dot.radiowaves.right"
        case .summarization: "text.line.first.and.arrowtriangle.forward"
        case .rewrite: "arrow.triangle.2.circlepath"
        case .classification: "tag"
        case .extraction: "square.and.arrow.up.on.square"
        case .generable: "curlybraces"
        case .guideComparison: "ruler"
        case .enumGeneration: "list.bullet.indent"
        case .nestedObject: "square.stack.3d.down.right"
        case .dynamicSchema: "slider.horizontal.below.square.filled.and.square"
        case .generationOptions: "dial.medium"
        case .greedySampling: "die.face.3"
        case .basicTool: "cloud.sun"
        case .searchTool: "magnifyingglass"
        case .multipleTools: "square.grid.2x2"
        case .multiStepTool: "arrow.trianglehead.branch"
        case .sideEffectTool: "exclamationmark.shield"
        case .imageDescription: "photo"
        case .imageClassification: "square.grid.3x3.square"
        case .textRectangles: "text.viewfinder"
        case .compareImages: "rectangle.on.rectangle"
        case .structuredVision: "text.below.photo"
        case .ocr: "text.viewfinder"
        case .barcode: "barcode.viewfinder"
        case .rectangles: "rectangle.dashed"
        case .faceRectangles: "face.smiling"
        case .humanRectangles: "figure.stand"
        case .saliency: "viewfinder"
        case .aesthetics: "sparkles"
        case .videoAnalysis: "film"
        case .camera: "camera"
        case .liveCamera: "video.badge.waveform"
        case .visionTool: "photo.badge.magnifyingglass"
        case .transcript: "list.bullet.rectangle"
        case .restore: "arrow.counterclockwise.circle"
        case .tokenCount: "number"
        case .contextWindow: "rectangle.compress.vertical"
        case .contextExceeded: "exclamationmark.arrow.triangle.2.circlepath"
        case .chunking: "rectangle.split.3x1"
        case .historyTransform: "clock.arrow.circlepath"
        case .prewarm: "flame"
        case .pcc: "icloud"
        case .modelComparison: "rectangle.split.2x1"
        case .reasoning: "brain"
        case .quota: "gauge.with.needle"
        case .dynamicInstructions: "text.badge.plus"
        case .dynamicProfile: "person.crop.circle.badge.checkmark"
        case .profileVisualizer: "eye"
        case .toolVisibility: "eye.trianglebadge.exclamationmark"
        case .sessionProperty: "person.text.rectangle"
        case .lifecycleEvents: "waveform.path.ecg"
        case .agentWorkflow: "point.3.filled.connected.trianglepath.dotted"
        case .visionAgent: "camera.metering.center.weighted"
        case .capabilities: "checklist"
        case .customModel: "server.rack"
        case .modelSwitch: "arrow.left.arrow.right"
        case .errorLab: "ladybug"
        case .logs: "doc.text.magnifyingglass"
        case .apiReference: "book"
        case .playground: "sparkles"
        case .medicalInformationHandling: "cross.case"
        }
    }

    /// BETA バッジ（仕様書 §61）。
    var isBeta: Bool {
        switch self {
        case .videoAnalysis, .liveCamera, .dynamicProfile, .profileVisualizer, .toolVisibility, .sessionProperty, .lifecycleEvents, .customModel:
            true
        default:
            false
        }
    }

    /// インストール済みSDKにAPIが無いデモ（仕様書 §46「利用不可の場合も正常なデモ画面として扱う」）。
    var requiresUnavailableSDKFeature: Bool {
        switch self {
        case .pcc, .quota, .reasoning: true
        default: false
        }
    }

    // MARK: Inputs

    var inputs: DemoInputs {
        switch self {
        case .dashboard: [.useCasePicker]
        case .simpleGeneration: [.prompt]
        case .instructions: [.prompt, .instructions, .instructionPreset]
        case .conversation: [.prompt]
        case .streaming: [.prompt]
        case .summarization: [.longText, .summaryStyle]
        case .rewrite: [.prompt, .rewriteStyle]
        case .classification: [.prompt]
        case .extraction: [.entityText]
        case .generable: [.entityText]
        case .guideComparison: [.prompt]
        case .enumGeneration: [.prompt]
        case .nestedObject: [.entityText]
        case .dynamicSchema: [.prompt, .schemaFields]
        case .generationOptions: [.prompt, .samplingOptions]
        case .greedySampling: [.prompt, .samplingOptions]
        case .basicTool: [.prompt]
        case .searchTool: [.prompt]
        case .multipleTools: [.prompt]
        case .multiStepTool: [.prompt]
        case .sideEffectTool: [.prompt]
        case .imageDescription: [.image, .prompt]
        case .imageClassification: [.image]
        case .textRectangles: [.image]
        case .rectangles: [.image]
        case .faceRectangles: [.image]
        case .humanRectangles: [.image]
        case .saliency: [.image]
        case .aesthetics: [.image]
        case .compareImages: [.image, .secondImage, .prompt]
        case .structuredVision: [.image]
        case .ocr: [.image, .prompt]
        case .barcode: [.image]
        case .videoAnalysis: [.video, .frameCount, .prompt]
        case .camera: [.camera, .prompt]
        case .liveCamera: [.liveCamera]
        case .visionTool: [.image, .prompt]
        case .transcript: [.prompt]
        case .restore: [.prompt]
        case .tokenCount: [.longText]
        case .contextWindow: [.prompt, .longText]
        case .contextExceeded: [.longText]
        case .chunking: [.longText, .chunkSize]
        case .historyTransform: [.prompt, .historyWindow]
        case .prewarm: [.prompt]
        case .pcc: []
        case .modelComparison: [.prompt]
        case .reasoning: [.prompt]
        case .quota: []
        case .dynamicInstructions: [.prompt, .expertiseMode]
        case .dynamicProfile: [.prompt, .profilePicker]
        case .profileVisualizer: [.profilePicker]
        case .toolVisibility: [.prompt, .profilePicker]
        case .sessionProperty: [.prompt, .patientPicker]
        case .lifecycleEvents: [.prompt, .profilePicker]
        case .agentWorkflow: [.prompt, .patientPicker]
        case .visionAgent: [.image, .prompt]
        case .capabilities: [.useCasePicker]
        case .customModel: [.prompt, .modelPicker]
        case .modelSwitch: [.prompt]
        case .errorLab: [.errorTrigger]
        case .logs: []
        case .apiReference: []
        case .playground: [.prompt, .instructions, .image, .toolPicker, .modelPicker, .samplingOptions, .structuredToggle, .streamToggle]
        case .medicalInformationHandling: [.entityText]
        }
    }

    /// 実行ボタンのラベル。
    var runLabel: String {
        switch self {
        case .dashboard, .capabilities, .pcc, .quota, .logs, .apiReference: "Refresh"
        case .streaming: "Stream"
        case .summarization: "Summarize"
        case .compareImages: "Compare"
        case .camera: "Analyze Current Frame"
        case .liveCamera: "Ask the Model About This Frame"
        case .videoAnalysis: "Analyze Video"
        case .errorLab: "Trigger Error"
        case .medicalInformationHandling: "Compare Patterns"
        default: "Run Demo"
        }
    }

    // MARK: Presets（仕様書 §69）

    var promptPresets: [DemoPreset] {
        switch self {
        case .simpleGeneration, .streaming, .transcript, .prewarm, .modelSwitch, .modelComparison, .customModel, .reasoning:
            [
                // 既定は「事実を渡して書かせる」形にしている。
                // オンデバイスモデルは知識ベースではなく、細かい事実を聞くと実測で誤答した
                // （例: 加賀棒茶を「煎茶」、揚げ浜式製塩を「網に塩を撒く」と説明した）。
                // Apple「Prompting an on-device foundation model」も、正確でハルシネーションのない応答には
                // プロンプトが簡潔かつ具体的である必要があると述べている。
                DemoPreset("事実を渡して書く", """
                    次の事実だけを使って、加賀棒茶の紹介文を80文字程度で書いてください。事実に無いことは書かないでください。
                    ・茶葉ではなく茎を焙煎した番茶
                    ・焙煎温度は180度前後
                    ・湯温は90度、浸出時間は30秒
                    """),
                DemoPreset("石川県の特徴", "石川県の特徴を100文字程度で説明してください。"),
                DemoPreset("宇宙", "宇宙について300文字程度で説明してください。"),
                DemoPreset("量子コンピュータ", "量子コンピュータの仕組みを説明してください。")
            ]
        case .instructions, .dynamicInstructions:
            [
                DemoPreset("量子コンピュータ", "量子コンピュータについて説明してください。"),
                DemoPreset("薬の飲み合わせ", "薬の飲み合わせに注意が必要な理由を説明してください。")
            ]
        case .conversation:
            [
                DemoPreset("名前を覚えさせる", "私の名前をTaroとして覚えてください。"),
                DemoPreset("名前を聞く", "私の名前は？"),
                DemoPreset("直前の話題", "さっき何について話していた？")
            ]
        case .classification, .enumGeneration:
            [
                DemoPreset("障害", DemoData.classificationSample),
                DemoPreset("操作質問", "パスワードを変更する画面はどこにありますか。"),
                DemoPreset("要望", "処方履歴をCSVで書き出せるようにしてほしいです。"),
                DemoPreset("契約", "来月からプランを1つ上のものに変更したいのですが手続きを教えてください。")
            ]
        case .guideComparison:
            [
                DemoPreset("肯定的な文", "この新機能のおかげで棚卸しの時間が半分になりました。とても助かっています。"),
                DemoPreset("否定的な文", "更新してから起動が遅くなり、毎回落ちるので業務が止まっています。")
            ]
        case .rewrite:
            [
                DemoPreset("社内連絡", "本件について確認しました。次回の会議で詳細を共有します。"),
                DemoPreset("問い合わせ返信", "在庫はあります。取り置きするので明日までに来てください。")
            ]
        case .basicTool:
            [
                DemoPreset("金沢", "金沢は何度？"),
                DemoPreset("2都市", "東京と大阪はどちらが暑い？")
            ]
        case .searchTool:
            [
                DemoPreset("薬効", "アムロジピンの薬効を教えて"),
                DemoPreset("注意点", "レボフロキサシンを飲むときの注意点は？")
            ]
        case .multipleTools:
            [
                DemoPreset("在庫を聞く", "アムロジピン5mgの在庫はいくつ？"),
                DemoPreset("薬効を聞く", "アムロジピンは何の薬？"),
                DemoPreset("天気を聞く", "金沢の気温を教えて")
            ]
        case .multiStepTool, .agentWorkflow:
            [
                DemoPreset("在庫が少ない薬", "田中さんの処方薬のうち在庫が100錠未満の薬を教えて。"),
                DemoPreset("処方一覧", "田中さんに今どんな薬が出ているか教えて。")
            ]
        case .sideEffectTool:
            [
                DemoPreset("欠品にする", "アムロジピン5mgを欠品にして。"),
                DemoPreset("在庫を直す", "レボフロキサシン500mgの在庫を200錠に修正して。")
            ]
        case .imageDescription, .camera:
            [
                DemoPreset("説明させる", "この画像の内容を説明してください。"),
                DemoPreset("何が写っているか", "この画像に何が写っているか、箇条書きで挙げてください。")
            ]
        case .compareImages:
            [DemoPreset("違いを3点", "この2枚の画像の違いを3点挙げてください。")]
        case .ocr:
            [DemoPreset("読んで要約", "この画像に記載されている文字を読み取り、内容を要約してください。")]
        case .videoAnalysis:
            [
                DemoPreset("動画を説明", "この動画に何が写っているか、時系列で説明してください。"),
                DemoPreset("文字を読む", "動画中に映っている文字を読み取って要約してください。")
            ]
        case .visionTool, .visionAgent:
            [
                DemoPreset("薬を特定", "この画像に写っている薬を特定して、薬効と在庫を教えてください。"),
                DemoPreset("コードを読む", "画像のコードを読み取って、該当する薬品の情報を調べてください。")
            ]
        case .dynamicSchema:
            [DemoPreset("人物を作る", "架空の人物のプロフィールを1件作ってください。")]
        case .generationOptions, .greedySampling:
            [
                DemoPreset("キャッチコピー", "薬局向けの在庫管理アプリのキャッチコピーを1つ作ってください。"),
                DemoPreset("分類", DemoData.classificationSample)
            ]
        case .sessionProperty:
            [
                DemoPreset("処方を出す", "この患者の処方を出して"),
                DemoPreset("年齢を聞く", "この患者は何歳？")
            ]
        case .dynamicProfile, .toolVisibility, .lifecycleEvents:
            [
                DemoPreset("在庫", "アムロジピン5mgの在庫はいくつ？"),
                DemoPreset("薬効", "アムロジピンは何の薬？")
            ]
        case .contextWindow, .historyTransform, .restore:
            [DemoPreset("直前の話題", "ここまでの会話を3行でまとめて。")]
        case .playground:
            [
                DemoPreset("石川県", "石川県の特徴を100文字程度で説明してください。"),
                DemoPreset("在庫確認", "田中さんの処方薬で在庫が少ないものを教えて。")
            ]
        case .medicalInformationHandling:
            []
        default:
            []
        }
    }

    var instructionPresets: [DemoPreset] {
        [
            DemoPreset("小学生向け", "あなたは小学生向けの先生です。専門用語を使わず、身近な例に置き換えて説明してください。必ず日本語で答えてください。"),
            DemoPreset("エンジニア向け", "あなたはソフトウェアエンジニア向けの技術ライターです。用語を省略せず、仕組みと制約を正確に説明してください。必ず日本語で答えてください。"),
            DemoPreset("経営者向け", "あなたは経営者向けのコンサルタントです。投資判断に必要な要点と影響範囲に絞って説明してください。必ず日本語で答えてください。"),
            DemoPreset("薬剤師向け", "あなたは薬剤師向けの医薬情報担当者です。作用機序、相互作用、実務上の注意点を説明してください。必ず日本語で答えてください。")
        ]
    }

    // MARK: Used APIs（仕様書 §67）

    var usedAPIs: [UsedAPI] {
        var apis: [UsedAPI] = []
        switch self {
        case .dashboard, .capabilities:
            apis = [
                .fm("SystemLanguageModel.default", "systemlanguagemodel"),
                .fm("SystemLanguageModel.availability", "systemlanguagemodel/availability"),
                .fm("SystemLanguageModel.contextSize", "systemlanguagemodel/contextsize"),
                .fm("SystemLanguageModel.supportedLanguages", "systemlanguagemodel/supportedlanguages"),
                .fm("SystemLanguageModel.supportsLocale(_:)", "systemlanguagemodel/supportslocale(_:)")
            ]
        case .simpleGeneration:
            apis = [.fm("LanguageModelSession", "languagemodelsession"), .fm("respond(to:)", "languagemodelsession/respond(to:options:)")]
        case .instructions, .dynamicInstructions:
            apis = [.fm("LanguageModelSession(instructions:)", "languagemodelsession/init(model:tools:instructions:)"), .fm("Instructions", "instructions")]
        case .conversation:
            apis = [.fm("LanguageModelSession", "languagemodelsession"), .fm("Transcript", "transcript")]
        case .streaming:
            apis = [
                .fm("streamResponse(to:)", "languagemodelsession/streamresponse(to:options:)"),
                .fm("ResponseStream.Snapshot", "languagemodelsession/responsestream/snapshot"),
                .fm("ResponseStream.collect()", "languagemodelsession/responsestream/collect()")
            ]
        case .summarization:
            apis = [.fm("respond(to:generating:)", "languagemodelsession/respond(to:generating:includeschemainprompt:options:)"), .fm("@Generable", "generable")]
        case .rewrite:
            apis = [.fm("Instructions", "instructions"), .fm("GenerationOptions", "generationoptions")]
        case .classification, .enumGeneration:
            apis = [.fm("@Generable enum", "generable"), .fm("respond(to:generating:)", "languagemodelsession/respond(to:generating:includeschemainprompt:options:)")]
        case .extraction, .generable, .nestedObject:
            apis = [.fm("@Generable", "generable"), .fm("@Guide", "guide(description:)"), .fm("respond(to:generating:)", "languagemodelsession/respond(to:generating:includeschemainprompt:options:)")]
        case .medicalInformationHandling:
            apis = [
                .fm("SystemLanguageModel(guardrails:)", "systemlanguagemodel/init(usecase:guardrails:)"),
                .fm("Guardrails.permissiveContentTransformations", "systemlanguagemodel/guardrails/permissivecontenttransformations"),
                .fm("@Generable", "generable"),
                .fm("respond(to:)", "languagemodelsession/respond(to:options:)"),
                .fm("respond(to:generating:)", "languagemodelsession/respond(to:generating:includeschemainprompt:options:)")
            ]
        case .guideComparison:
            apis = [.fm("@Guide", "guide(description:)"), .fm("GenerationGuide", "generationguide")]
        case .dynamicSchema:
            apis = [.fm("DynamicGenerationSchema", "dynamicgenerationschema"), .fm("GenerationSchema(root:dependencies:)", "generationschema"), .fm("GeneratedContent", "generatedcontent"), .fm("respond(to:schema:)", "languagemodelsession/respond(to:schema:includeschemainprompt:options:)")]
        case .generationOptions:
            apis = [.fm("GenerationOptions", "generationoptions"), .fm("GenerationOptions.temperature", "generationoptions/temperature"), .fm("maximumResponseTokens", "generationoptions/maximumresponsetokens")]
        case .greedySampling:
            apis = [.fm("GenerationOptions.SamplingMode.greedy", "generationoptions/samplingmode"), .fm("SamplingMode.random(top:seed:)", "generationoptions/samplingmode")]
        case .basicTool, .searchTool:
            apis = [.fm("Tool", "tool"), .fm("Tool.call(arguments:)", "tool/call(arguments:)"), .fm("Transcript.ToolCall", "transcript/toolcall")]
        case .multipleTools, .multiStepTool, .toolVisibility:
            apis = [.fm("Tool", "tool"), .fm("LanguageModelSession(tools:)", "languagemodelsession/init(model:tools:instructions:)"), .fm("Transcript.ToolCalls", "transcript/toolcalls")]
        case .sideEffectTool:
            apis = [.fm("Tool", "tool"), .fm("Transcript.ToolOutput", "transcript/tooloutput")]
        case .imageDescription, .structuredVision, .compareImages:
            apis = [
                .vision("ClassifyImageRequest", "classifyimagerequest"),
                .vision("RecognizeTextRequest", "recognizetextrequest"),
                .vision("CalculateImageAestheticsScoresRequest", "calculateimageaestheticsscoresrequest"),
                .fm("respond(to:generating:)", "languagemodelsession/respond(to:generating:includeschemainprompt:options:)"),
                .other("PhotosPicker", framework: "PhotosUI", "photokit/photospicker")
            ]
        case .imageClassification:
            apis = [.vision("ClassifyImageRequest", "classifyimagerequest"), .vision("ClassificationObservation", "classificationobservation"), .other("PhotosPickerItem.loadTransferable(type:)", framework: "PhotosUI", "photosui/photospickeritem/loadtransferable(type:)")]
        case .ocr:
            apis = [.vision("RecognizeTextRequest", "recognizetextrequest"), .vision("RecognizedTextObservation", "recognizedtextobservation"), .vision("BoundingBoxProviding.boundingBox", "boundingboxproviding/boundingbox")]
        case .textRectangles:
            apis = [.vision("DetectTextRectanglesRequest", "detecttextrectanglesrequest"), .vision("TextObservation", "textobservation"), .vision("BoundingBoxProviding.boundingBox", "boundingboxproviding/boundingbox")]
        case .barcode:
            apis = [.vision("DetectBarcodesRequest", "detectbarcodesrequest"), .vision("BarcodeObservation", "barcodeobservation"), .vision("BarcodeSymbology", "barcodesymbology")]
        case .rectangles:
            apis = [.vision("DetectRectanglesRequest", "detectrectanglesrequest"), .vision("RectangleObservation", "rectangleobservation"), .vision("BoundingBoxProviding.boundingBox", "boundingboxproviding/boundingbox")]
        case .faceRectangles:
            apis = [.vision("DetectFaceRectanglesRequest", "detectfacerectanglesrequest"), .vision("FaceObservation", "faceobservation"), .vision("BoundingBoxProviding.boundingBox", "boundingboxproviding/boundingbox")]
        case .humanRectangles:
            apis = [.vision("DetectHumanRectanglesRequest", "detecthumanrectanglesrequest"), .vision("HumanObservation", "humanobservation"), .vision("BoundingBoxProviding.boundingBox", "boundingboxproviding/boundingbox")]
        case .saliency:
            apis = [.vision("GenerateObjectnessBasedSaliencyImageRequest", "generateobjectnessbasedsaliencyimagerequest"), .vision("SaliencyImageObservation", "saliencyimageobservation")]
        case .aesthetics:
            apis = [.vision("CalculateImageAestheticsScoresRequest", "calculateimageaestheticsscoresrequest"), .vision("ImageAestheticsScoresObservation", "imageaestheticsscoresobservation")]
        case .videoAnalysis:
            apis = [
                .other("AVURLAsset", framework: "AVFoundation", "avfoundation/avurlasset"),
                .other("AVAssetImageGenerator.image(at:)", framework: "AVFoundation", "avfoundation/avassetimagegenerator/image(at:)"),
                .vision("RecognizeTextRequest", "recognizetextrequest"),
                .vision("ClassifyImageRequest", "classifyimagerequest"),
                .fm("respond(to:generating:)", "languagemodelsession/respond(to:generating:includeschemainprompt:options:)")
            ]
        case .camera, .liveCamera:
            apis = [
                .other("AVCaptureSession", framework: "AVFoundation", "avfoundation/avcapturesession"),
                .other("AVCaptureVideoDataOutput", framework: "AVFoundation", "avfoundation/avcapturevideodataoutput"),
                .other("CVPixelBuffer", framework: "CoreVideo", "corevideo/cvpixelbuffer"),
                .vision("perform(on:orientation:)", "imageprocessingrequest"),
                .fm("streamResponse(to:generating:)", "languagemodelsession/streamresponse(to:generating:includeschemainprompt:options:)")
            ]
        case .visionTool, .visionAgent:
            apis = [.fm("Tool", "tool"), .vision("RecognizeTextRequest", "recognizetextrequest"), .vision("DetectBarcodesRequest", "detectbarcodesrequest"), .fm("Transcript", "transcript")]
        case .transcript:
            apis = [.fm("LanguageModelSession.transcript", "languagemodelsession/transcript"), .fm("Transcript.Entry", "transcript/entry"), .fm("Transcript.Segment", "transcript/segment")]
        case .restore:
            apis = [.fm("LanguageModelSession(transcript:)", "languagemodelsession/init(model:tools:transcript:)"), .fm("Transcript: Codable", "transcript")]
        case .tokenCount:
            apis = [.fm("SystemLanguageModel.tokenCount(for:)", "systemlanguagemodel"), .fm("Prompt", "prompt")]
        case .contextWindow:
            apis = [.fm("SystemLanguageModel.contextSize", "systemlanguagemodel/contextsize"), .fm("tokenCount(for:)", "systemlanguagemodel")]
        case .contextExceeded:
            apis = [.fm("GenerationError.exceededContextWindowSize", "languagemodelsession/generationerror")]
        case .chunking:
            apis = [.fm("respond(to:)", "languagemodelsession/respond(to:options:)"), .fm("tokenCount(for:)", "systemlanguagemodel")]
        case .historyTransform:
            apis = [.fm("Transcript", "transcript"), .fm("LanguageModelSession(transcript:)", "languagemodelsession/init(model:tools:transcript:)")]
        case .prewarm:
            apis = [.fm("prewarm(promptPrefix:)", "languagemodelsession/prewarm(promptprefix:)")]
        case .pcc, .quota:
            apis = [.fm("SystemLanguageModel", "systemlanguagemodel")]
        case .reasoning:
            apis = [.fm("GenerationOptions", "generationoptions")]
        case .modelComparison, .modelSwitch, .customModel:
            apis = [.fm("SystemLanguageModel", "systemlanguagemodel"), .fm("GenerationOptions", "generationoptions")]
        case .dynamicProfile, .profileVisualizer, .sessionProperty, .lifecycleEvents:
            apis = [.fm("LanguageModelSession(model:tools:instructions:)", "languagemodelsession/init(model:tools:instructions:)"), .fm("GenerationOptions", "generationoptions"), .fm("Tool", "tool")]
        case .agentWorkflow:
            apis = [.fm("Tool", "tool"), .fm("Transcript", "transcript"), .fm("respond(to:generating:)", "languagemodelsession/respond(to:generating:includeschemainprompt:options:)")]
        case .errorLab:
            apis = [.fm("GenerationError", "languagemodelsession/generationerror"), .fm("ToolCallError", "languagemodelsession/toolcallerror"), .fm("GenerationSchema.SchemaError", "generationschema/schemaerror")]
        case .logs:
            apis = [.fm("Transcript", "transcript"), .fm("Tool", "tool")]
        case .apiReference:
            apis = [.fm("FoundationModels", "")]
        case .playground:
            apis = [
                .fm("LanguageModelSession", "languagemodelsession"),
                .fm("Instructions", "instructions"),
                .fm("Prompt", "prompt"),
                .fm("GenerationOptions", "generationoptions"),
                .fm("Tool", "tool"),
                .fm("@Generable", "generable"),
                .fm("streamResponse(to:)", "languagemodelsession/streamresponse(to:options:)")
            ]
        }
        return apis
    }

    // MARK: View Source（仕様書 §68）

    /// この画面の中核となる実コードの抜粋。
    var sourceSnippet: String {
        switch self {
        case .simpleGeneration:
            """
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt)
            // response.content: String
            """
        case .instructions, .dynamicInstructions:
            """
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: prompt)
            """
        case .conversation:
            """
            // セッションを保持し続けると Transcript に履歴が積まれる
            if conversationSession == nil {
                conversationSession = LanguageModelSession(model: model, instructions: "…")
            }
            let response = try await conversationSession!.respond(to: prompt)
            """
        case .streaming:
            """
            let stream = session.streamResponse(to: prompt)
            for try await snapshot in stream {
                if firstTokenAt == nil { firstTokenAt = Date() }
                partialText = snapshot.content   // 途中結果
            }
            let response = try await stream.collect()
            finalText = response.content
            """
        case .summarization:
            """
            @Generable struct BulletSummaryResult {
                @Guide(description: "重要ポイント1") var point1: String
                @Guide(description: "重要ポイント2") var point2: String
                @Guide(description: "重要ポイント3") var point3: String
                @Guide(description: "重要ポイント4") var point4: String
                @Guide(description: "重要ポイント5") var point5: String
            }

            let response = try await session.respond(
                to: "次の文章を箇条書きで要約してください。\\n\\n\\(text)",
                generating: BulletSummaryResult.self
            )
            """
        case .classification, .enumGeneration:
            """
            @Generable enum SupportCategory { case bug, operation, request, contract }

            @Generable struct SupportClassification {
                @Guide(description: "問い合わせのカテゴリ") var category: SupportCategory
                @Guide(description: "分類の根拠") var evidence: String
            }

            let response = try await session.respond(to: text, generating: SupportClassification.self)
            // response.content.category は必ず4つのケースのいずれか
            """
        case .generable, .extraction:
            """
            @Generable struct Prescription {
                @Guide(description: "患者の氏名") var patientName: String
                @Guide(description: "薬剤名") var medicineName: String
                @Guide(description: "1回量") var dose: String
                @Guide(description: "1日あたりの回数", .range(1...6)) var frequency: Int
                @Guide(description: "服用タイミング") var timing: String
                @Guide(description: "処方日数", .range(1...180)) var days: Int
            }

            let response = try await session.respond(to: text, generating: Prescription.self)
            """
        case .guideComparison:
            """
            // 制約あり
            @Generable struct GuidedSentiment {
                @Guide(description: "0から100の整数", .range(0...100)) var confidence: Int
                @Guide(description: "感情", .anyOf(["positive", "negative", "neutral"])) var sentiment: String
            }
            // 制約なし
            @Generable struct UnguidedSentiment {
                var confidence: Int
                var sentiment: String
            }
            // 同じ入力を両方の型で生成し、値域を比べる
            """
        case .nestedObject:
            """
            @Generable struct PatientPrescription {
                @Guide(description: "患者情報") var patient: PatientInfo
                @Guide(description: "薬剤の一覧", .count(1...6)) var medicines: [Medicine]
                @Guide(description: "注意事項") var notes: String
            }
            """
        case .dynamicSchema:
            """
            // 画面で組んだフィールドから実行時にスキーマを作る
            let properties = fields.map { field in
                DynamicGenerationSchema.Property(
                    name: field.name,
                    description: field.fieldDescription,
                    schema: field.dynamicSchema
                )
            }
            let root = DynamicGenerationSchema(name: "DynamicRecord", properties: properties)
            let schema = try GenerationSchema(root: root, dependencies: [])
            let response = try await session.respond(to: prompt, schema: schema)
            // response.content: GeneratedContent
            """
        case .generationOptions:
            """
            let options = GenerationOptions(
                sampling: .random(top: 50),
                temperature: temperature,
                maximumResponseTokens: maximumResponseTokens
            )
            let response = try await session.respond(to: prompt, options: options)
            """
        case .greedySampling:
            """
            // greedy: 同じ入力なら毎回同じ出力に寄る
            let greedy = GenerationOptions(sampling: .greedy)
            // random: seed を固定しなければ実行ごとに揺れる
            let random = GenerationOptions(sampling: .random(top: 50), temperature: 1.0)
            """
        case .basicTool, .searchTool, .multipleTools, .multiStepTool:
            """
            struct DrugSearchTool: Tool {
                let name = "searchDrug"
                let description = "薬剤名から薬効・分類・注意事項を調べます。"

                @Generable struct Arguments {
                    @Guide(description: "調べたい薬剤名") var name: String
                }

                func call(arguments: Arguments) async throws -> String {
                    guard let drug = DemoData.drug(matching: arguments.name) else { … }
                    return "category: \\(drug.category)\\neffect: \\(drug.effect)"
                }
            }

            let session = LanguageModelSession(model: model, tools: [DrugSearchTool(…)], instructions: …)
            let response = try await session.respond(to: prompt)
            // どの Tool が呼ばれたかは session.transcript の .toolCalls で分かる
            """
        case .sideEffectTool:
            """
            // Tool は「申請」までしか行わない
            func call(arguments: Arguments) async throws -> String {
                pendingRequests.enqueue(SideEffectRequest(…))
                return "申請を受け付けました。承認待ちです。在庫はまだ変更されていません。"
            }

            // 実際の書き換えは人間が Execute を押したときにアプリが行う
            func approve(_ request: SideEffectRequest) {
                inventory.setStock(request.newStock, for: request.drugName)
            }
            """
        case .imageDescription, .structuredVision, .compareImages:
            """
            // このSDKの FoundationModels は画像を直接 Prompt へ渡せないため、
            // Vision で観測した事実をテキスト化してモデルへ渡す。
            let frame = try await VisionAnalyzer().analyze(cgImage: cgImage, plan: .full)
            // frame.observationDigest: 分類ラベル・OCR結果・バーコード・注目領域をまとめたテキスト
            // （digest と違い「実行できなかったリクエスト」の英語API名を含まない。混ぜると言語判定が壊れる）

            let response = try await session.respond(
                to: "\\(userPrompt)\\n\\n[Vision解析結果]\\n\\(frame.observationDigest)",
                generating: ImageAnalysis.self
            )
            """
        case .imageClassification:
            """
            let observations = try await ClassifyImageRequest().perform(on: cgImage)
            for observation in observations {
                observation.identifier
                observation.confidence
            }
            """
        case .textRectangles:
            """
            let observations = try await DetectTextRectanglesRequest().perform(on: cgImage)
            for observation in observations {
                observation.boundingBox
            }

            // observation.boundingBox は正規化座標・左下原点。
            // 表示時は画像の aspect-fit / fill 領域に合わせて左上原点へ変換する。
            """
        case .ocr:
            """
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            request.customWords = DemoData.drugNames
            let observations = try await request.perform(on: cgImage)
            let raw = observations.map(\\.transcript).joined(separator: "\\n")
            """
        case .barcode:
            """
            let observations = try await DetectBarcodesRequest().perform(on: cgImage)
            for observation in observations {
                observation.symbology      // QR, EAN13, …
                observation.payloadString  // ペイロード
            }
            """
        case .rectangles:
            """
            let observations = try await DetectRectanglesRequest().perform(on: cgImage)
            for observation in observations {
                observation.boundingBox
            }
            """
        case .faceRectangles:
            """
            let observations = try await DetectFaceRectanglesRequest().perform(on: cgImage)
            for observation in observations {
                observation.boundingBox
            }
            """
        case .humanRectangles:
            """
            let observations = try await DetectHumanRectanglesRequest().perform(on: cgImage)
            for observation in observations {
                observation.boundingBox
            }
            """
        case .saliency:
            """
            let observation = try await GenerateObjectnessBasedSaliencyImageRequest().perform(on: cgImage)
            let salientObjects = observation.salientObjects
            """
        case .aesthetics:
            """
            let observation = try await CalculateImageAestheticsScoresRequest().perform(on: cgImage)
            observation.overallScore
            observation.isUtility
            """
        case .videoAnalysis:
            """
            // 等間隔にコマを取り出す
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            for index in 0..<frameCount {
                let time = CMTime(seconds: duration * (Double(index) + 0.5) / Double(frameCount), preferredTimescale: 600)
                let (image, actualTime) = try await generator.image(at: time)
                // 1コマずつ Vision で解析
                frames.append(try await VisionAnalyzer().analyze(cgImage: image, plan: .videoFrame, timestamp: actualTime.seconds))
            }

            // 時系列にまとめてモデルへ
            let response = try await session.respond(to: frames.videoDigest, generating: VideoAnalysis.self)
            """
        case .camera:
            """
            // AVCaptureVideoDataOutput のデリゲートが最新フレームを箱に置く
            func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from: AVCaptureConnection) {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                box.store(pixelBuffer, orientation: .up)
            }

            // ボタンを押した瞬間の1フレームだけを解析する（連続動画推論はしない）
            let frame = box.latest()!
            let analysis = try await VisionAnalyzer().analyze(pixelBuffer: frame.buffer, plan: .full)
            let response = try await session.respond(to: "\\(prompt)\\n\\n\\(analysis.observationDigest)")
            """
        case .liveCamera:
            """
            // Vision は毎フレーム回す（軽い .realtime プラン）
            while !Task.isCancelled {
                if let frame = box.latest() {
                    liveAnalysis = try await analyzer.analyze(pixelBuffer: frame.buffer, plan: .realtime)
                }
                try await Task.sleep(for: .seconds(1 / targetAnalysisFPS))
            }

            // 言語モデルは重いので一定間隔だけ。ストリーミングで実況を更新する
            let stream = session.streamResponse(to: latestDigest, generating: LiveFrameNarration.self)
            for try await snapshot in stream {
                partial = snapshot.content.scene      // 生成途中は各プロパティが Optional
            }
            // 確定値は collect()。ここで respond() を呼び直すと1フレームで2回生成してしまう
            narration = try await stream.collect().content
            """
        case .visionTool, .visionAgent:
            """
            let session = LanguageModelSession(
                model: model,
                tools: [
                    OCRTool(recorder: recorder, imageProvider: imageProvider),
                    BarcodeReaderTool(recorder: recorder, imageProvider: imageProvider),
                    DrugSearchTool(recorder: recorder),
                    InventoryTool(recorder: recorder, store: inventory)
                ],
                instructions: "画像から情報を読み取り、必要な Tool を使って調べてください。"
            )
            let response = try await session.respond(to: prompt)
            // モデルが OCR → 薬品検索 → 在庫照会 の順に Tool を選ぶ
            """
        case .transcript:
            """
            for entry in session.transcript {
                switch entry {
                case .instructions(let instructions): …
                case .prompt(let prompt):             …
                case .toolCalls(let calls):           …
                case .toolOutput(let output):         …
                case .response(let response):        …
                }
            }
            """
        case .restore:
            """
            // Transcript は Codable なので保存できる
            let data = try JSONEncoder().encode(session.transcript)

            // 別のセッションへ履歴を引き継ぐ
            let restored = try JSONDecoder().decode(Transcript.self, from: data)
            let newSession = LanguageModelSession(model: model, transcript: restored)
            let response = try await newSession.respond(to: "さっき何について話していた？")
            """
        case .tokenCount:
            """
            let tokens = try await model.tokenCount(for: Prompt(text))
            let characters = text.count
            // 日本語と英語で1文字あたりのトークン数が異なることを比べる
            """
        case .contextWindow:
            """
            let maximum = model.contextSize                             // 実行時に取得（ハードコードしない）
            let used = try await model.tokenCount(for: session.transcript)
            let percent = Double(used) / Double(maximum) * 100
            """
        case .contextExceeded:
            """
            do {
                _ = try await session.respond(to: hugePrompt)
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize(let context) = error {
                    // Error Type / Technical Detail / User Message / Recovery に分解して表示
                }
            }
            """
        case .chunking:
            """
            // 境界は文単位で決め、収まるかどうかは実測トークン数で判定する
            var chunks: [String] = []
            var buffer = ""
            var bufferTokens = 0
            for sentence in sentences(of: text) {
                let tokens = try await model.tokenCount(for: Prompt(sentence))
                if bufferTokens + tokens > tokenBudget, !buffer.isEmpty {
                    chunks.append(buffer)
                    buffer = ""
                    bufferTokens = 0
                }
                buffer += sentence
                bufferTokens += tokens
            }
            if !buffer.isEmpty { chunks.append(buffer) }

            var partials: [String] = []
            for (index, chunk) in chunks.enumerated() {
                // チャンクごとに独立したセッションを使い、履歴を溜めない
                let session = LanguageModelSession(model: model, instructions: …)
                // 文脈は「前のチャンクの要約」だけを渡してつなぐ
                let prompt = index == 0 ? chunk : "[前の断片の要約]\\n\\(partials[index - 1])\\n\\n[今回の断片]\\n\\(chunk)"
                partials.append(try await session.respond(to: prompt).content)
            }
            let merged = try await mergeSession.respond(to: "次の部分要約を統合して: \\(partials.joined())")
            """
        case .historyTransform:
            """
            // 全履歴ではなく直近N件だけを新しいセッションへ渡す
            let all = Array(session.transcript)
            let instructions = all.prefix { if case .instructions = $0 { true } else { false } }
            let recent = all.suffix(windowSize)
            let trimmed = Transcript(entries: Array(instructions) + Array(recent))
            let session = LanguageModelSession(model: model, transcript: trimmed)
            """
        case .prewarm:
            """
            // OFF: 何もせず respond
            let cold = LanguageModelSession(model: model)
            let coldElapsed = await measure { try await cold.respond(to: prompt) }

            // ON: prewarm してから respond
            let warm = LanguageModelSession(model: model)
            warm.prewarm(promptPrefix: Prompt(prompt))
            let warmElapsed = await measure { try await warm.respond(to: prompt) }
            """
        case .dynamicProfile, .profileVisualizer, .toolVisibility:
            """
            // Profile = モデル + Tool + GenerationOptions + Instructions のまとまり
            struct AgentProfile {
                var tools: Set<LabToolName>
                var options: GenerationOptions
                var instructions: String
            }

            // 切り替えたら新しいセッションを作り直す
            let session = LanguageModelSession(
                model: model,
                tools: factory.tools(for: profile.tools),
                instructions: profile.instructions
            )
            """
        case .sessionProperty:
            """
            // Tool にセッション共有状態を注入する
            struct PatientTool: Tool {
                let selectedPatientId: String?
                func call(arguments: Arguments) async throws -> String {
                    // 引数が空なら共有状態を使う → 「この患者の処方を出して」で通る
                    let patient = arguments.nameOrId.isEmpty
                        ? DemoData.patients.first { $0.id == selectedPatientId }
                        : DemoData.patient(matching: arguments.nameOrId)
                    …
                }
            }
            """
        case .lifecycleEvents:
            """
            log(.onActivate, "profile=\\(profile.title)")
            log(.onPrompt, prompt)
            let response = try await session.respond(to: prompt)
            // Transcript を走査して Tool の発火を復元する
            for entry in response.transcriptEntries {
                if case .toolCalls(let calls) = entry { log(.onToolCall, …) }
                if case .toolOutput(let output) = entry { log(.onToolOutput, …) }
            }
            log(.onResponse, response.content)
            """
        case .agentWorkflow:
            """
            let session = LanguageModelSession(
                model: model,
                tools: [PatientTool(…), PrescriptionTool(…), InventoryTool(…)],
                instructions: "患者を調べ、処方を取得し、各薬剤の在庫を確認して、在庫不足の薬を報告してください。"
            )
            let response = try await session.respond(to: prompt, generating: StockReport.self)
            // response.transcriptEntries から Tool 呼び出しの順序を復元してタイムライン表示
            """
        case .customModel, .modelSwitch, .modelComparison:
            """
            // このSDKの FoundationModels に LanguageModel protocol は無いので、
            // アプリ側で同じ形の抽象を切って差し替え可能にする
            protocol LabLanguageModel: Sendable {
                var displayName: String { get }
                func respond(to prompt: String, instructions: String?, options: GenerationOptions) async throws -> String
            }

            struct SystemModelAdapter: LabLanguageModel { /* 実際に respond する */ }
            struct MockExecutorModel: LabLanguageModel { /* 外部LLM互換の応答を返す */ }
            """
        case .errorLab:
            """
            switch error {
            case .exceededContextWindowSize(let context): …
            case .guardrailViolation(let context):        …
            case .unsupportedLanguageOrLocale(let context): …
            case .decodingFailure(let context):           …
            case .rateLimited(let context):               …
            case .concurrentRequests(let context):        …
            case .refusal(let refusal, let context):      …
            }
            // Error Type / Technical Detail / User Message / Recovery の4項目に正規化して表示
            """
        case .playground:
            """
            let session = LanguageModelSession(
                model: model,
                tools: factory.tools(for: selectedTools),
                instructions: instructions
            )
            let options = GenerationOptions(sampling: sampling, temperature: temperature, maximumResponseTokens: maxTokens)

            if useStructuredOutput {
                let response = try await session.respond(to: prompt, generating: ImageAnalysis.self, options: options)
            } else if useStreaming {
                let stream = session.streamResponse(to: prompt, options: options)
                for try await snapshot in stream { … }          // 途中結果（その時点までの全文）
                let response = try await stream.collect()        // 最終結果はここで確定させる
            } else {
                let response = try await session.respond(to: prompt, options: options)
            }
            """
        case .medicalInformationHandling:
            """
            // NGになりやすい: 処方文から薬剤名を汎用配列へ guided generation
            let blocked = try await session.respond(
                to: prescriptionText,
                generating: ExtractedEntities.self
            )

            // OKになりやすい: 医療ドメイン専用の構造へ guided generation
            let structured = try await session.respond(
                to: prescriptionText,
                generating: PatientPrescription.self
            )

            // permissiveContentTransformations は String 生成だけに効く
            let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
            let textSession = LanguageModelSession(model: model, instructions: "医療判断を加えず転記する")
            let text = try await textSession.respond(to: prescriptionText)
            """
        default:
            """
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let response = try await session.respond(to: prompt)
            """
        }
    }
}

// MARK: - Preset

nonisolated struct DemoPreset: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }
}
