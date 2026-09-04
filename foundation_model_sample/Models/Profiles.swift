//
//  Profiles.swift
//  Foundation Models Lab
//
//  仕様書 §50-§52 Dynamic Profile / Profile Visualizer / Dynamic Tool Visibility
//  §57 Custom LanguageModel の抽象
//

import Foundation
import FoundationModels

// MARK: - Agent profile

/// モデル・Tool・生成オプション・Instructions をひとまとめにした「Profile」。
/// FoundationModels に DynamicProfile 型は無いので、アプリ側の概念として実装する。
nonisolated enum AgentProfile: String, CaseIterable, Identifiable, Sendable {
    case quick
    case analysis
    case vision
    case inventory
    case patient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: "Quick"
        case .analysis: "Analysis"
        case .vision: "Vision"
        case .inventory: "Inventory"
        case .patient: "Patient"
        }
    }

    var modelChoice: ModelChoice {
        switch self {
        case .analysis: .pcc      // 本来は PCC を使いたい Profile。SDK未提供なので On-device へフォールバックする。
        default: .onDevice
        }
    }

    var temperature: Double {
        switch self {
        case .quick: 0.4
        case .analysis: 0.2
        case .vision: 0.3
        case .inventory: 0.2
        case .patient: 0.3
        }
    }

    var maximumResponseTokens: Int {
        switch self {
        case .quick: 256
        case .analysis: 1024
        case .vision: 512
        case .inventory: 384
        case .patient: 384
        }
    }

    var samplingLabel: String {
        switch self {
        case .quick: "random(top: 50)"
        case .analysis, .inventory: "greedy"
        case .vision, .patient: "random(top: 20)"
        }
    }

    var sampling: GenerationOptions.SamplingMode {
        switch self {
        case .quick: .random(top: 50)
        case .analysis, .inventory: .greedy
        case .vision, .patient: .random(top: 20)
        }
    }

    var reasoningLabel: String {
        switch self {
        case .quick: "Low"
        case .analysis: "Deep"
        case .vision: "Normal"
        case .inventory: "Low"
        case .patient: "Normal"
        }
    }

    /// 仕様書 §52: Profile ごとに公開する Tool を変える。
    var tools: Set<LabToolName> {
        switch self {
        case .quick: [.weather, .drugSearch]
        case .analysis: [.drugSearch, .inventory, .patient, .prescription]
        case .vision: [.ocr, .barcode, .drugSearch]
        case .inventory: [.inventory, .drugSearch, .inventoryUpdate]
        case .patient: [.patient, .prescription]
        }
    }

    var instructions: String {
        switch self {
        case .quick:
            "簡潔に答えてください。1〜2文で済むなら1〜2文で答えます。必ず日本語で答えてください。"
        case .analysis:
            "根拠を明示しながら段階的に分析してください。前提と結論を分けて述べます。必ず日本語で答えてください。"
        case .vision:
            "画像から読み取れた情報をもとに答えてください。読み取れなかったことは推測せず「読み取れない」と述べます。必ず日本語で答えてください。"
        case .inventory:
            "在庫に関する質問に答えます。在庫の変更は必ず requestInventoryUpdate で申請し、自分で変更したと述べないでください。必ず日本語で答えてください。"
        case .patient:
            "患者と処方に関する質問に答えます。患者名が明示されない場合は、選択中の患者を対象とします。必ず日本語で答えてください。"
        }
    }

    var options: GenerationOptions {
        GenerationOptions(sampling: sampling, temperature: temperature, maximumResponseTokens: maximumResponseTokens)
    }

    /// 仕様書 §51 Profile Visualizer の表示行。
    var visualizerRows: [KeyValueRow] {
        [
            KeyValueRow(label: "Model", value: modelChoice.displayName, status: modelChoice.isBackedByInstalledSDK ? .success : .warning),
            KeyValueRow(label: "Reasoning", value: reasoningLabel),
            KeyValueRow(label: "Sampling", value: samplingLabel),
            KeyValueRow(label: "Temperature", value: String(format: "%.2f", temperature)),
            KeyValueRow(label: "Max Response Tokens", value: "\(maximumResponseTokens)"),
            KeyValueRow(label: "Tools", value: "\(tools.count) 個")
        ]
    }
}

// MARK: - DEMO 41 Dynamic Instructions

nonisolated enum ExpertiseMode: String, CaseIterable, Identifiable, Sendable {
    case beginner
    case expert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: "Beginner"
        case .expert: "Expert"
        }
    }

    var instructions: String {
        switch self {
        case .beginner: "専門用語を避けて説明してください。日常的な例に置き換えます。必ず日本語で答えてください。"
        case .expert: "技術用語を省略せず説明してください。仕組みと制約を正確に述べます。必ず日本語で答えてください。"
        }
    }
}

// MARK: - DEMO 05 Summarization

nonisolated enum SummaryStyle: String, CaseIterable, Identifiable, Sendable {
    case oneLine
    case threeLines
    case bullets
    case hundredCharacters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneLine: "1行"
        case .threeLines: "3行"
        case .bullets: "箇条書き"
        case .hundredCharacters: "100文字"
        }
    }

    var instruction: String {
        switch self {
        case .oneLine: "1行で要約してください。"
        case .threeLines: "3行で要約してください。"
        case .bullets: "箇条書きで要約してください。"
        case .hundredCharacters: "100文字程度で要約してください。"
        }
    }
}

// MARK: - DEMO 06 Rewrite

nonisolated enum RewriteStyle: String, CaseIterable, Identifiable, Sendable {
    case polite
    case shorter
    case elementary
    case expert
    case bullets
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polite: "丁寧にする"
        case .shorter: "短くする"
        case .elementary: "小学生向け"
        case .expert: "専門家向け"
        case .bullets: "箇条書き"
        case .business: "ビジネス文"
        }
    }

    var instruction: String {
        switch self {
        case .polite: "次の文章をより丁寧な表現に書き換えてください。"
        case .shorter: "次の文章を意味を保ったまま短く書き換えてください。"
        case .elementary: "次の文章を小学生にも分かる表現に書き換えてください。"
        case .expert: "次の文章を専門家向けの正確な表現に書き換えてください。"
        case .bullets: "次の文章を箇条書きに書き換えてください。"
        case .business: "次の文章をビジネス文書として適切な表現に書き換えてください。"
        }
    }
}

// MARK: - DEMO 13 Dynamic Generation Schema

/// 画面から組み立てるフィールド定義。実行時に DynamicGenerationSchema へ変換する。
nonisolated struct SchemaField: Identifiable, Equatable, Sendable {
    enum FieldType: String, CaseIterable, Identifiable, Sendable {
        case string = "String"
        case integer = "Int"
        case number = "Double"
        case boolean = "Bool"
        case stringArray = "[String]"

        var id: String { rawValue }
    }

    let id = UUID()
    var name: String
    var type: FieldType
    var fieldDescription: String = ""
    var isOptional = false

    /// この1フィールドに対応する DynamicGenerationSchema。
    var dynamicSchema: DynamicGenerationSchema {
        switch type {
        case .string: DynamicGenerationSchema(type: String.self)
        case .integer: DynamicGenerationSchema(type: Int.self)
        case .number: DynamicGenerationSchema(type: Double.self)
        case .boolean: DynamicGenerationSchema(type: Bool.self)
        case .stringArray: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self), minimumElements: 1, maximumElements: 5)
        }
    }

    var property: DynamicGenerationSchema.Property {
        DynamicGenerationSchema.Property(
            name: name,
            description: fieldDescription.isEmpty ? nil : fieldDescription,
            schema: dynamicSchema,
            isOptional: isOptional
        )
    }
}

// MARK: - DEMO 49 Custom LanguageModel

/// 仕様書 §57: FoundationModels に LanguageModel protocol は無いため、
/// 同じ形の抽象をアプリ側に切って、実モデルとモックを差し替え可能にする。
nonisolated protocol LabLanguageModel: Sendable {
    var displayName: String { get }
    var typeName: String { get }
    var capabilities: ModelCapabilities { get }
    func respond(to prompt: String, instructions: String?, options: GenerationOptions) async throws -> String
}

/// 実際の SystemLanguageModel を LabLanguageModel として見せるアダプタ。
nonisolated struct SystemModelAdapter: LabLanguageModel {
    let displayName = "Apple On-device"
    let typeName = "SystemLanguageModel"
    let capabilities: ModelCapabilities
    let model: SystemLanguageModel

    func respond(to prompt: String, instructions: String?, options: GenerationOptions) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: instructions)
        return try await session.respond(to: prompt, options: options).content
    }
}

/// 仕様書 §57 第1版: 外部LLMへ繋がずモック Executor で構造だけ成立させる。
/// 第2段階で OpenAI / Anthropic / Gemini / 社内LLM を差し替えられるように、
/// 「リクエストを組み立てて Executor に渡し、応答を文字列で受ける」形だけを固定してある。
nonisolated struct MockExecutorModel: LabLanguageModel {
    let displayName = "Mock Server Model"
    let typeName = "MockExecutorModel (LabLanguageModel)"
    var capabilities = ModelCapabilities(
        textGeneration: true, guidedGeneration: false, toolCalling: false,
        streaming: false, tokenCounting: false, transcriptRestore: false,
        nativeVision: false, visionFrameworkBridge: false,
        reasoningLevel: true, privateCloudCompute: false
    )
    /// 実際のネットワーク往復に相当する遅延。
    var simulatedLatency: Duration = .milliseconds(220)

    func respond(to prompt: String, instructions: String?, options: GenerationOptions) async throws -> String {
        // ここが外部LLMのHTTP呼び出しに置き換わる場所。
        let request = MockRequest(
            model: "mock-executor-v1",
            system: instructions,
            user: prompt,
            temperature: options.temperature,
            maxTokens: options.maximumResponseTokens
        )
        try await Task.sleep(for: simulatedLatency)
        try Task.checkCancellation()
        return """
        [MockExecutor] 外部LLM互換の応答です。
        送信したリクエスト:
        \(request.debugDescription)

        本文: \(prompt.prefix(80))… に対する応答をここで生成します。
        第2段階でこの Executor を OpenAI / Anthropic / Gemini / 社内LLM の実装に差し替えると、
        呼び出し側のコードは変更せずにモデルだけを入れ替えられます。
        """
    }

    struct MockRequest {
        var model: String
        var system: String?
        var user: String
        var temperature: Double?
        var maxTokens: Int?

        var debugDescription: String {
            """
            {
              "model": "\(model)",
              "system": \(system.map { "\"\($0.prefix(40))…\"" } ?? "null"),
              "messages": [{ "role": "user", "content": "\(user.prefix(40))…" }],
              "temperature": \(temperature.map { String(format: "%.2f", $0) } ?? "null"),
              "max_tokens": \(maxTokens.map(String.init) ?? "null")
            }
            """
        }
    }
}

/// PCC を選んだときのプレースホルダ。SDKに型が無いことを明示する。
nonisolated struct UnavailablePCCModel: LabLanguageModel {
    let displayName = "Apple PCC"
    let typeName = "PrivateCloudComputeLanguageModel (SDK未提供)"
    var capabilities = ModelCapabilities()

    func respond(to prompt: String, instructions: String?, options: GenerationOptions) async throws -> String {
        throw LabError.sdkFeatureMissing(
            "PrivateCloudComputeLanguageModel",
            alternative: "PCC 対応SDKへ更新するか、On-device モデルで比較してください。"
        )
    }
}

// MARK: - Error Lab triggers

/// 仕様書 §59: 実際にエラーを発生させるトリガー。
nonisolated enum ErrorTrigger: String, CaseIterable, Identifiable, Sendable {
    case contextExceeded
    case guardrail
    case unsupportedLanguage
    case toolFailure
    case concurrentRequests
    case schemaFailure
    case imageMissing
    case pccUnavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contextExceeded: "Context Exceeded"
        case .guardrail: "Guardrail Violation"
        case .unsupportedLanguage: "Unsupported Language"
        case .toolFailure: "Tool Failure"
        case .concurrentRequests: "Concurrent Requests"
        case .schemaFailure: "Schema Failure"
        case .imageMissing: "Image Error"
        case .pccUnavailable: "PCC Unavailable"
        }
    }

    var explanation: String {
        switch self {
        case .contextExceeded: "コンテキストウィンドウを確実に超える長さの Prompt を実際に送信します。"
        case .guardrail: "安全性ガードレールに触れる可能性のある Prompt を送信します。モデルが拒否するか通るかは実行時に決まります。"
        case .unsupportedLanguage: "サポート対象外の言語で Prompt を送信します。"
        case .toolFailure: "call(arguments:) が必ず throw する Tool を登録したセッションで実行します。"
        case .concurrentRequests: "同一セッションに対して2つのリクエストを同時に投げます。"
        case .schemaFailure: "フィールド名が重複した DynamicGenerationSchema を作ろうとします。"
        case .imageMissing: "画像を選択せずに Vision の解析を実行します。"
        case .pccUnavailable: "SDKに存在しない PCC モデルを呼び出そうとします。"
        }
    }
}
