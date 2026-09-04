//
//  DemoExecutionResult.swift
//  Foundation Models Lab
//
//  仕様書 §64 DemoExecutionResult / §65 Metrics
//

import Foundation
import FoundationModels

// MARK: - Metrics

nonisolated struct Metrics: Sendable, Equatable {
    var startedAt: Date
    var firstTokenAt: Date?
    var finishedAt: Date?
    /// 実API (SystemLanguageModel.tokenCount) で測った入力トークン。
    var promptTokens: Int?
    var responseTokens: Int?
    var transcriptTokens: Int?
    var contextSize: Int?

    static func started() -> Metrics { Metrics(startedAt: Date()) }

    var elapsed: TimeInterval? { finishedAt.map { $0.timeIntervalSince(startedAt) } }
    var firstTokenLatency: TimeInterval? { firstTokenAt.map { $0.timeIntervalSince(startedAt) } }

    var elapsedText: String { elapsed.map { String(format: "%.2f sec", $0) } ?? "-" }
    var firstTokenText: String { firstTokenLatency.map { String(format: "%.0f ms", $0 * 1000) } ?? "-" }

    var contextUsagePercent: Int? {
        guard let contextSize, contextSize > 0, let used = transcriptTokens ?? promptTokens else { return nil }
        return min(100, Int((Double(used) / Double(contextSize)) * 100))
    }
}

// MARK: - Structured payload shown in the Output section

/// Output セクションの表示形態。デモごとに最適な見せ方を選ぶ。
nonisolated enum DemoPayload: Sendable {
    /// 素のテキスト応答。
    case text(String)
    /// 構造化出力: ラベル付きフィールド + 生JSON。
    case structured(fields: [StructuredField], json: String)
    /// 左右比較（Guide ON/OFF、モデル比較など）。
    case comparison([ComparisonColumn])
    /// キーバリューの一覧（Dashboard、Capabilities など）。
    case keyValue([KeyValueRow])
    /// 段階実行のタイムライン（Agent / Multi-step Tool）。
    case timeline([TimelineStep])
    /// 画像解析の結果。
    case media(MediaAnalysisResult)
    /// 何も出力していない。
    case none

    var plainText: String {
        switch self {
        case .text(let value): value
        case .structured(let fields, _): fields.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
        case .comparison(let columns): columns.map { "\($0.title)\n\($0.body)" }.joined(separator: "\n\n")
        case .keyValue(let rows): rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
        case .timeline(let steps): steps.map { "\($0.title) — \($0.detail)" }.joined(separator: "\n")
        case .media(let result): result.plainText
        case .none: ""
        }
    }

    var isEmpty: Bool {
        if case .none = self { return true }
        return plainText.isEmpty
    }
}

nonisolated struct StructuredField: Identifiable, Sendable {
    let id = UUID()
    var label: String
    var value: String
    /// スキーマ上の型名（Int / String / [Medicine] など）。
    var typeName: String?
    /// @Guide の説明文。
    var guideDescription: String?
    var children: [StructuredField] = []
}

nonisolated struct ComparisonColumn: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var subtitle: String?
    var body: String
    var footnotes: [KeyValueRow] = []
    var isUnavailable = false
}

nonisolated struct KeyValueRow: Identifiable, Sendable {
    let id = UUID()
    var label: String
    var value: String
    var status: Status = .neutral

    enum Status: Sendable {
        case neutral, success, warning, error, running
    }
}

nonisolated struct TimelineStep: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var detail: String
    var kind: Kind
    var elapsed: TimeInterval?

    enum Kind: Sendable {
        case instructions, prompt, toolCall, toolOutput, response, note
    }
}

// MARK: - DemoExecutionResult

/// 仕様書 §64: すべてのデモで共通の実行結果モデル。
nonisolated struct DemoExecutionResult: Sendable {
    var startedAt: Date
    var finishedAt: Date?
    var modelName: String
    var apiTypeName: String
    var payload: DemoPayload = .none
    /// 内部で何が起きたかの技術情報（仕様書 §2「内部情報を積極的に表示する」）。
    var debugDetail: String = ""
    var error: LabError?
    var metrics: Metrics
    var toolCalls: [ToolLogEntry] = []
    var transcript: [TranscriptEntryView] = []
    var capabilities: ModelCapabilities = ModelCapabilities()
    var usedAPIs: [UsedAPI] = []
    /// 実際に FoundationModels を呼んだか、SDK未提供でアプリ側処理に落ちたか。
    var executionMode: ExecutionMode = .notExecuted

    enum ExecutionMode: String, Sendable {
        case notExecuted = "Not executed"
        case foundationModels = "FoundationModels (live)"
        case visionBridge = "Vision framework → FoundationModels"
        case visionOnly = "Vision framework only"
        case localOnly = "App-side only (no model call)"
        case sdkUnavailable = "SDK feature unavailable"

        var isLive: Bool { self == .foundationModels || self == .visionBridge }
    }

    static func notExecuted(modelName: String) -> DemoExecutionResult {
        DemoExecutionResult(
            startedAt: Date(),
            finishedAt: nil,
            modelName: modelName,
            apiTypeName: "-",
            metrics: .started()
        )
    }
}

// MARK: - Used API

nonisolated struct UsedAPI: Identifiable, Hashable, Sendable {
    var id: String { symbol }
    var symbol: String
    var framework: String
    /// Apple Developer Documentation の該当ページ。
    var documentationPath: String

    var url: URL? {
        URL(string: "https://developer.apple.com/documentation/\(documentationPath)")
    }

    static func fm(_ symbol: String, _ path: String) -> UsedAPI {
        UsedAPI(symbol: symbol, framework: "FoundationModels", documentationPath: "foundationmodels/\(path)")
    }

    static func vision(_ symbol: String, _ path: String) -> UsedAPI {
        UsedAPI(symbol: symbol, framework: "Vision", documentationPath: "vision/\(path)")
    }

    static func other(_ symbol: String, framework: String, _ path: String) -> UsedAPI {
        UsedAPI(symbol: symbol, framework: framework, documentationPath: path)
    }
}
