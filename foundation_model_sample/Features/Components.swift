//
//  Components.swift
//  Foundation Models Lab
//
//  仕様書 §66 共通Demo UI / §70 デザイン方針 / §71 色
//  意味を持つ色のみ使用: Green=Available/Success, Orange=Beta/Warning, Red=Error, Blue=Running/Information
//

import SwiftUI

// MARK: - Section box

struct LabSection<Content: View>: View {
    let title: String
    let symbol: String
    var accessory: AnyView?
    /// UI テストから参照するための識別子。
    var identifier: String?
    @ViewBuilder let content: Content

    init(_ title: String, symbol: String, accessory: AnyView? = nil, identifier: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.accessory = accessory
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let accessory { accessory }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "section.\(title)")
    }
}

// MARK: - Status color

extension KeyValueRow.Status {
    var color: Color {
        switch self {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        case .running: .blue
        }
    }

    var symbol: String? {
        switch self {
        case .neutral: nil
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        case .running: "circle.dotted"
        }
    }
}

// MARK: - Badges

struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(.orange)
    }
}

struct ExecutionModeBadge: View {
    let mode: DemoExecutionResult.ExecutionMode

    var body: some View {
        Label(mode.rawValue, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch mode {
        case .foundationModels, .visionBridge: .green
        case .visionOnly, .localOnly: .blue
        case .sdkUnavailable: .orange
        case .notExecuted: .secondary
        }
    }

    private var symbol: String {
        switch mode {
        case .foundationModels: "cpu"
        case .visionBridge: "arrow.triangle.branch"
        case .visionOnly: "eye"
        case .localOnly: "iphone"
        case .sdkUnavailable: "exclamationmark.triangle"
        case .notExecuted: "circle.dashed"
        }
    }
}

// MARK: - Text editor

struct LabTextEditor: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat = 90
    var presets: [DemoPreset] = []
    var monospaced = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(text.count) 文字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            TextEditor(text: $text)
                .font(monospaced ? .callout.monospaced() : .callout)
                .frame(minHeight: minHeight)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

            if !presets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets) { preset in
                            Button(preset.title) { text = preset.value }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Payload renderer

struct PayloadView: View {
    let payload: DemoPayload
    let isRunning: Bool

    var body: some View {
        switch payload {
        case .none:
            if isRunning {
                Label("Generating…", systemImage: "circle.dotted")
                    .foregroundStyle(.blue)
            } else {
                Text("未実行")
                    .foregroundStyle(.secondary)
            }
        case .text(let text):
            Text(text.isEmpty ? "（空の応答）" : text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .structured(let fields, let json):
            StructuredOutputView(fields: fields, json: json)
        case .comparison(let columns):
            ComparisonView(columns: columns)
        case .keyValue(let rows):
            KeyValueTable(rows: rows)
        case .timeline(let steps):
            TimelineView(steps: steps)
        case .media(let result):
            MediaResultView(result: result)
        }
    }
}

// MARK: - Structured output

struct StructuredOutputView: View {
    let fields: [StructuredField]
    let json: String
    @State private var showJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(fields) { field in
                StructuredFieldRow(field: field, depth: 0)
            }

            if !json.isEmpty {
                Divider()
                DisclosureGroup(isExpanded: $showJSON) {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(json)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                } label: {
                    Label("Raw GeneratedContent (JSON)", systemImage: "curlybraces")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }
}

struct StructuredFieldRow: View {
    let field: StructuredField
    let depth: Int
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !field.children.isEmpty {
                    Button {
                        withAnimation(.snappy) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Text(field.label)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .foregroundStyle(.primary)

                if let typeName = field.typeName {
                    Text(typeName)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.blue)
                }
                Spacer(minLength: 0)
            }

            if field.children.isEmpty {
                Text(field.value)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(field.value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let guide = field.guideDescription {
                Label(guide, systemImage: "ruler")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if expanded, !field.children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(field.children) { child in
                        StructuredFieldRow(field: child, depth: depth + 1)
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1)
                }
            }
        }
        .padding(.leading, depth > 0 ? 2 : 0)
    }
}

// MARK: - Comparison

struct ComparisonView: View {
    let columns: [ComparisonColumn]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns) { column in
                    ComparisonCard(column: column)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(columns) { column in
                    ComparisonCard(column: column)
                }
            }
        }
    }
}

private struct ComparisonCard: View {
    let column: ComparisonColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(column.title)
                    .font(.subheadline.weight(.semibold))
                if column.isUnavailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if let subtitle = column.subtitle {
                Text(subtitle)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text(column.body)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !column.footnotes.isEmpty {
                Divider()
                KeyValueTable(rows: column.footnotes, compact: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (column.isUnavailable ? Color.orange.opacity(0.06) : Color(.tertiarySystemGroupedBackground)),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }
}

// MARK: - Key value table

struct KeyValueTable: View {
    let rows: [KeyValueRow]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            ForEach(rows) { row in
                // 横に並べて収まらない値（長い説明文など）は縦積みにする。
                // iPhone 幅でラベル列を固定すると、値が細い一列に折り返されて読めなくなる。
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        label(row)
                            .frame(width: compact ? 150 : 190, alignment: .leading)
                        value(row)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        label(row)
                        value(row)
                    }
                }
            }
        }
    }

    private func label(_ row: KeyValueRow) -> some View {
        Text(row.label)
            .font(compact ? .caption : .subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func value(_ row: KeyValueRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol = row.status.symbol {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(row.status.color)
            }
            Text(row.value)
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(row.status == .neutral ? .primary : row.status.color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Timeline

struct TimelineView: View {
    let steps: [TimelineStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(color(for: step.kind))
                            .frame(width: 10, height: 10)
                            .overlay {
                                Image(systemName: symbol(for: step.kind))
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(.quaternary)
                                .frame(width: 1.5)
                                .frame(minHeight: 24)
                        }
                    }
                    .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(step.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(color(for: step.kind))
                            Spacer()
                            if let elapsed = step.elapsed {
                                Text(String(format: "%.2f sec", elapsed))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(step.detail)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, index < steps.count - 1 ? 16 : 0)
                }
            }
        }
    }

    private func color(for kind: TimelineStep.Kind) -> Color {
        switch kind {
        case .instructions: .purple
        case .prompt: .blue
        case .toolCall: .orange
        case .toolOutput: .teal
        case .response: .green
        case .note: .secondary
        }
    }

    private func symbol(for kind: TimelineStep.Kind) -> String {
        switch kind {
        case .instructions: "text.badge.checkmark"
        case .prompt: "arrow.up"
        case .toolCall: "wrench.adjustable"
        case .toolOutput: "arrow.down"
        case .response: "checkmark"
        case .note: "info"
        }
    }
}

// MARK: - Metrics panel（仕様書 §65）

struct MetricsPanel: View {
    let result: DemoExecutionResult

    var body: some View {
        LabSection("Metrics", symbol: "timer", accessory: AnyView(ExecutionModeBadge(mode: result.executionMode)), identifier: "section.metrics") {
            KeyValueTable(rows: rows)
            if let percent = result.metrics.contextUsagePercent {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(percent), total: 100)
                        .tint(percent > 80 ? .red : percent > 50 ? .orange : .green)
                    Text("Context 使用率 \(percent)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rows: [KeyValueRow] {
        var rows: [KeyValueRow] = [
            KeyValueRow(label: "Model", value: result.modelName),
            KeyValueRow(label: "API Type", value: result.apiTypeName),
            KeyValueRow(label: "Start Time", value: result.startedAt.formatted(date: .omitted, time: .standard)),
            KeyValueRow(label: "First Response", value: result.metrics.firstTokenText),
            KeyValueRow(label: "Elapsed", value: result.metrics.elapsedText,
                        status: result.finishedAt == nil ? .running : .neutral)
        ]
        if let tokens = result.metrics.promptTokens {
            rows.append(KeyValueRow(label: "Prompt Tokens", value: "\(tokens.formatted())（tokenCount 実測）"))
        }
        if let tokens = result.metrics.responseTokens {
            rows.append(KeyValueRow(label: "Response Tokens", value: "\(tokens.formatted())（tokenCount 実測）"))
        }
        if let tokens = result.metrics.transcriptTokens {
            rows.append(KeyValueRow(label: "Transcript Tokens", value: "\(tokens.formatted())"))
        }
        if let contextSize = result.metrics.contextSize, contextSize > 0 {
            rows.append(KeyValueRow(label: "Context Size", value: "\(contextSize.formatted()) tokens"))
        }
        return rows
    }
}

// MARK: - Tool log panel（仕様書 §28）

struct ToolLogPanel: View {
    let entries: [ToolLogEntry]

    var body: some View {
        LabSection("Tool Calls", symbol: "wrench.and.screwdriver",
                   accessory: AnyView(Text("\(entries.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)),
                   identifier: "section.toolCalls") {
            if entries.isEmpty {
                Text("Tool は呼ばれていません")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(entries.suffix(12).reversed()) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: entry.failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(entry.failed ? .red : .green)
                                Text(entry.toolName)
                                    .font(.subheadline.monospaced().weight(.semibold))
                                Spacer()
                                Text(entry.timeText)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(entry.elapsedText)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text("Arguments")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(entry.arguments)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Text("Tool returned")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(entry.output)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

// MARK: - Lifecycle panel（仕様書 §54）

struct LifecyclePanel: View {
    let events: [LifecycleEvent]

    var body: some View {
        LabSection("Lifecycle", symbol: "waveform.path.ecg",
                   accessory: AnyView(Text("\(events.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)),
                   identifier: "section.lifecycle") {
            if events.isEmpty {
                Text("イベントはありません").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events.suffix(20).reversed()) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(event.timeText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 68, alignment: .leading)
                            Image(systemName: event.kind.symbol)
                                .font(.caption2)
                                .foregroundStyle(event.kind == .onError ? .red : .blue)
                                .frame(width: 16)
                            Text(event.kind.rawValue)
                                .font(.caption.monospaced().weight(.semibold))
                                .frame(width: 108, alignment: .leading)
                            Text(event.detail)
                                .font(.caption)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Transcript panel（仕様書 §37）

struct TranscriptPanel: View {
    let entries: [TranscriptEntryView]

    var body: some View {
        LabSection("Transcript", symbol: "list.bullet.rectangle",
                   accessory: AnyView(Text("\(entries.count) entries").font(.caption.monospacedDigit()).foregroundStyle(.secondary)),
                   identifier: "section.transcript") {
            if entries.isEmpty {
                Text("Transcript はまだありません")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Image(systemName: entry.kind.symbol)
                                    .font(.caption2)
                                Text(entry.kind.rawValue)
                                    .font(.caption.weight(.semibold))
                                if entry.title != entry.kind.rawValue, !entry.title.isEmpty {
                                    Text("· \(entry.title)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(color(for: entry.kind))

                            Text(entry.body.isEmpty ? "（空）" : entry.body)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let raw = entry.rawJSON {
                                Text(raw)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(color(for: entry.kind).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func color(for kind: TranscriptEntryView.Kind) -> Color {
        switch kind {
        case .instructions: .purple
        case .prompt: .blue
        case .toolCalls: .orange
        case .toolOutput: .teal
        case .response: .green
        }
    }
}

// MARK: - Used APIs（仕様書 §67）

struct UsedAPIPanel: View {
    let apis: [UsedAPI]

    var body: some View {
        LabSection("Used APIs", symbol: "chevron.left.forwardslash.chevron.right", identifier: "section.usedAPIs") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(grouped, id: \.0) { framework, items in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(framework)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(items) { api in
                            if let url = api.url {
                                Link(destination: url) {
                                    HStack(spacing: 5) {
                                        Text(api.symbol)
                                            .font(.callout.monospaced())
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.caption2)
                                    }
                                }
                            } else {
                                Text(api.symbol).font(.callout.monospaced())
                            }
                        }
                    }
                }
            }
        }
    }

    private var grouped: [(String, [UsedAPI])] {
        Dictionary(grouping: apis, by: \.framework)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }
}

// MARK: - View Source（仕様書 §68）

struct SourcePanel: View {
    let source: String
    @State private var expanded = false

    var body: some View {
        LabSection("View Source", symbol: "swift", identifier: "section.viewSource") {
            DisclosureGroup(isExpanded: $expanded) {
                ScrollView(.horizontal, showsIndicators: true) {
                    SyntaxHighlightedCode(source: source)
                        .padding(12)
                }
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            } label: {
                Text(expanded ? "コードを隠す" : "この画面の中核コードを表示")
                    .font(.subheadline.weight(.medium))
            }
        }
    }
}

/// 軽量な Swift シンタックスハイライト。
struct SyntaxHighlightedCode: View {
    let source: String

    private static let keywords: Set<String> = [
        "let", "var", "func", "struct", "enum", "class", "protocol", "extension", "if", "else", "guard",
        "for", "in", "while", "switch", "case", "default", "return", "try", "await", "async", "throws",
        "throw", "do", "catch", "self", "nil", "true", "false", "some", "any", "init", "where", "import",
        "private", "public", "static", "mutating", "nonisolated"
    ]

    var body: some View {
        Text(highlighted)
            .font(.caption.monospaced())
            .textSelection(.enabled)
    }

    private var highlighted: AttributedString {
        var output = AttributedString()
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                var comment = AttributedString(String(line))
                comment.foregroundColor = .green
                output += comment
            } else {
                output += highlight(line: String(line))
            }
            output += AttributedString("\n")
        }
        return output
    }

    private func highlight(line: String) -> AttributedString {
        var output = AttributedString()
        var token = ""

        func flush() {
            guard !token.isEmpty else { return }
            var piece = AttributedString(token)
            if Self.keywords.contains(token) {
                piece.foregroundColor = .pink
            } else if token.hasPrefix("@") {
                piece.foregroundColor = .orange
            } else if let first = token.first, first.isUppercase {
                piece.foregroundColor = .cyan
            }
            output += piece
            token = ""
        }

        for character in line {
            if character.isLetter || character.isNumber || character == "_" || character == "@" {
                token.append(character)
            } else {
                flush()
                output += AttributedString(String(character))
            }
        }
        flush()
        return output
    }
}

// MARK: - Error panel（仕様書 §59 の4項目）

struct ErrorPanel: View {
    let error: LabError

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                Text(error.errorType).font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.red)

            field("Technical Detail", error.technicalDetail, monospaced: true)
            field("User Message", error.userMessage)
            field("Recovery", error.recovery)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("panel.error")
    }

    private func field(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Side effect confirmation（仕様書 §27 / §76）

struct SideEffectConfirmationPanel: View {
    let requests: [SideEffectRequest]
    let onApprove: (SideEffectRequest) -> Void
    let onReject: (SideEffectRequest) -> Void

    var body: some View {
        LabSection("Human Confirmation", symbol: "exclamationmark.shield.fill", identifier: "section.humanConfirmation") {
            VStack(alignment: .leading, spacing: 14) {
                Text("AIが以下の操作を要求しています。実行するまで状態は変わりません。")
                    .font(.callout)
                    .foregroundStyle(.orange)

                ForEach(requests) { request in
                    VStack(alignment: .leading, spacing: 10) {
                        KeyValueTable(rows: [
                            KeyValueRow(label: "Tool", value: request.toolName),
                            KeyValueRow(label: "Drug", value: request.drugName),
                            KeyValueRow(label: "Current Stock", value: "\(request.currentStock)"),
                            KeyValueRow(label: "Requested Stock", value: "\(request.newStock)", status: .warning),
                            KeyValueRow(label: "Reason", value: request.reason)
                        ], compact: true)

                        HStack {
                            Button(role: .cancel) { onReject(request) } label: {
                                Label("Cancel", systemImage: "xmark")
                            }
                            .buttonStyle(.bordered)

                            Button { onApprove(request) } label: {
                                Label("Execute", systemImage: "checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}
