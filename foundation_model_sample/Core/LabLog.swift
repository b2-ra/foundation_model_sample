//
//  LabLog.swift
//  Foundation Models Lab
//
//  仕様書 §28 Tool Log / §54 Lifecycle Events / §65 Metrics
//

import Foundation
import FoundationModels

// MARK: - Tool log

nonisolated struct ToolLogEntry: Identifiable, Sendable {
    let id = UUID()
    var toolName: String
    var arguments: String
    var output: String
    var startedAt: Date
    var finishedAt: Date?
    var failed = false

    var elapsedText: String {
        guard let finishedAt else { return "running" }
        return String(format: "%.0f ms", finishedAt.timeIntervalSince(startedAt) * 1000)
    }

    var timeText: String { startedAt.formatted(date: .omitted, time: .standard) }
}

// MARK: - Lifecycle log

nonisolated struct LifecycleEvent: Identifiable, Sendable {
    let id = UUID()
    var kind: Kind
    var detail: String
    var date: Date

    enum Kind: String, Sendable {
        case onActivate, onDeactivate, onPrompt, onResponse, onToolCall, onToolOutput, onError, onCancel

        var symbol: String {
            switch self {
            case .onActivate: "power"
            case .onDeactivate: "power.dotted"
            case .onPrompt: "arrow.up.message"
            case .onResponse: "arrow.down.message"
            case .onToolCall: "wrench.adjustable"
            case .onToolOutput: "arrow.turn.down.left"
            case .onError: "exclamationmark.triangle"
            case .onCancel: "stop.circle"
            }
        }
    }

    var timeText: String { date.formatted(date: .omitted, time: .standard) }
}

// MARK: - Transcript view model

/// 仕様書 §37 Transcript Viewer: Transcript.Entry を画面表示用に落とす。
nonisolated struct TranscriptEntryView: Identifiable, Sendable {
    let id: String
    var kind: Kind
    var title: String
    var body: String
    /// Tool 呼び出しなど、構造化された中身の生JSON。
    var rawJSON: String?

    enum Kind: String, Sendable {
        case instructions = "Instructions"
        case prompt = "Prompt"
        case toolCalls = "Tool Call"
        case toolOutput = "Tool Output"
        case response = "Response"

        var symbol: String {
            switch self {
            case .instructions: "text.badge.checkmark"
            case .prompt: "arrow.up.message"
            case .toolCalls: "wrench.adjustable"
            case .toolOutput: "arrow.turn.down.left"
            case .response: "arrow.down.message"
            }
        }
    }

    /// 実 Transcript から表示用エントリを作る。
    init(entry: Transcript.Entry) {
        id = entry.id
        switch entry {
        case .instructions(let instructions):
            kind = .instructions
            title = "Instructions"
            body = Self.text(from: instructions.segments)
            let tools = instructions.toolDefinitions
            rawJSON = tools.isEmpty ? nil : "toolDefinitions: [\n" + tools.map { "  { name: \"\($0.name)\", description: \"\($0.description)\" }" }.joined(separator: ",\n") + "\n]"
        case .prompt(let prompt):
            kind = .prompt
            title = "Prompt"
            body = Self.text(from: prompt.segments)
            var options: [String] = []
            if let temperature = prompt.options.temperature { options.append("temperature: \(temperature)") }
            if let maximum = prompt.options.maximumResponseTokens { options.append("maximumResponseTokens: \(maximum)") }
            if prompt.options.sampling != nil { options.append("sampling: set") }
            if let format = prompt.responseFormat { options.append("responseFormat: \(format.name)") }
            rawJSON = options.isEmpty ? nil : options.joined(separator: "\n")
        case .toolCalls(let calls):
            kind = .toolCalls
            title = calls.map(\.toolName).joined(separator: ", ")
            body = calls.map { "\($0.toolName)(\($0.arguments.jsonString))" }.joined(separator: "\n")
            rawJSON = calls.map(\.arguments.jsonString).joined(separator: "\n")
        case .toolOutput(let output):
            kind = .toolOutput
            title = output.toolName
            body = Self.text(from: output.segments)
            rawJSON = nil
        case .response(let response):
            kind = .response
            title = "Response"
            body = Self.text(from: response.segments)
            rawJSON = nil
        @unknown default:
            kind = .response
            title = "Unknown entry"
            body = String(describing: entry)
            rawJSON = nil
        }
    }

    /// アプリ側で組み立てた擬似エントリ（SDK未提供機能の説明用）。
    init(id: String = UUID().uuidString, kind: Kind, title: String, body: String, rawJSON: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.rawJSON = rawJSON
    }

    private static func text(from segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text): text.content
            case .structure(let structure): "[\(structure.source)] \(structure.content.jsonString)"
            @unknown default: String(describing: segment)
            }
        }
        .joined(separator: "\n")
    }
}

// MARK: - Shared log store

/// Tool から MainActor を跨いでログを書けるようにするための共有ストア。
/// Tool.call は nonisolated / @concurrent なので、ロックで保護した箱に積む。
nonisolated final class ToolCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ToolLogEntry] = []

    func begin(_ toolName: String, arguments: String) -> UUID {
        let entry = ToolLogEntry(toolName: toolName, arguments: arguments, output: "", startedAt: Date())
        lock.withLock { entries.append(entry) }
        return entry.id
    }

    func finish(_ id: UUID, output: String, failed: Bool = false) {
        lock.withLock {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index].output = output
            entries[index].finishedAt = Date()
            entries[index].failed = failed
        }
    }

    func drain() -> [ToolLogEntry] {
        lock.withLock {
            let current = entries
            entries.removeAll()
            return current
        }
    }

    func snapshot() -> [ToolLogEntry] {
        lock.withLock { entries }
    }
}
