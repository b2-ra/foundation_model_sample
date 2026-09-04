//
//  DemoScreen.swift
//  Foundation Models Lab
//
//  仕様書 §66 共通Demo UI:
//  Feature Name / Short Description / Input / Options / Run / Output / Metrics / Tool Calls / Transcript / API
//

import SwiftUI
import PhotosUI

struct DemoScreen: View {
    let demo: LabDemo
    @Bindable var engine: LabEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                unavailabilityNotice
                if demo.inputs.hasInputControls { inputSection }
                if demo.inputs.hasOptionControls { optionSection }
                actionSection
                if !engine.pendingSideEffects.isEmpty {
                    SideEffectConfirmationPanel(
                        requests: engine.pendingSideEffects,
                        onApprove: { engine.approve($0) },
                        onReject: { engine.reject($0) }
                    )
                }
                outputSection
                MetricsPanel(result: engine.result)
                // Logs 画面はセッション全体を見せる場所なので、画面切り替えで消えない履歴を参照する。
                ToolLogPanel(entries: demo == .logs ? engine.sessionToolLog : engine.toolLog)
                if demo.group == .agent || demo == .logs {
                    LifecyclePanel(events: demo == .logs ? engine.sessionLifecycleLog : engine.lifecycleLog)
                }
                TranscriptPanel(entries: engine.transcriptEntries)
                UsedAPIPanel(apis: demo.usedAPIs)
                SourcePanel(source: demo.sourceSnippet)
            }
            .padding(20)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(demo.title)
        // 画面内に見出し（アイコン + 説明 + カテゴリ）を持つので、ナビゲーションバーは細く保つ。
        .navigationBarTitleDisplayMode(.inline)
        .task(id: demo) {
            engine.activate(demo)
            // 選択済みなのに未読み込みの状態で画面へ戻ってきた場合の取りこぼしを拾う。
            // 通常は下のピッカー用 Binding が書き込み時点で読み込みを始める。
            engine.loadImageIfNeeded(engine.imageSelection, slot: .primary)
            engine.loadImageIfNeeded(engine.secondImageSelection, slot: .secondary)
            engine.loadVideoIfNeeded(engine.videoSelection)
        }
        .onDisappear {
            if demo.inputs.contains(.camera) || demo.inputs.contains(.liveCamera) {
                engine.stopCamera()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: demo.symbol)
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text(demo.title)
                    .font(.largeTitle.bold())
                if demo.isBeta { BetaBadge() }
                Spacer()
            }
            Text(demo.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(demo.group.title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.blue.opacity(0.12), in: Capsule())
                .foregroundStyle(.blue)
        }
    }

    /// 仕様書 §60: 利用不可でもクラッシュせず、理由と復旧手順を出す。
    @ViewBuilder
    private var unavailabilityNotice: some View {
        if !engine.modelManager.availability.isAvailable {
            VStack(alignment: .leading, spacing: 6) {
                Label("Foundation Models unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(engine.modelManager.availability.detail)
                    .font(.callout)
                if let recovery = engine.modelManager.availability.recovery {
                    Text(recovery)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Vision framework を使うデモ（OCR / Barcode / Photo / Video / Camera）は、モデルが使えなくても解析結果まで確認できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    engine.refreshEnvironment()
                } label: {
                    Label("再確認", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }

        if demo.requiresUnavailableSDKFeature {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                Text("このデモが対象とする API はインストール済みSDKに存在しません。取得できない項目は「取得不可」と表示し、値を推測しません。")
                    .font(.caption)
            }
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        LabSection("Input", symbol: "keyboard", identifier: "section.input") {
            VStack(alignment: .leading, spacing: 16) {
                if demo.inputs.contains(.liveCamera) {
                    CameraInputView(engine: engine, showsLiveControls: true)
                } else if demo.inputs.contains(.camera) {
                    CameraInputView(engine: engine, showsLiveControls: false)
                }

                if demo.inputs.contains(.video) {
                    VideoInputView(
                        selection: Binding(
                            get: { engine.videoSelection },
                            set: { newValue in
                                engine.videoSelection = newValue
                                engine.loadVideoIfNeeded(newValue)
                            }
                        ),
                        metadata: engine.videoMetadata,
                        frames: engine.videoFrames,
                        progress: engine.videoProgress,
                        frameCount: $engine.videoFrameCount,
                        onClear: { engine.clearMedia() }
                    )
                }

                if demo.inputs.contains(.image) {
                    ImageInputView(
                        title: demo.inputs.contains(.secondImage) ? "Image A" : "Photo",
                        selection: Binding(
                            get: { engine.imageSelection },
                            set: { newValue in
                                engine.imageSelection = newValue
                                engine.loadImageIfNeeded(newValue, slot: .primary)
                            }
                        ),
                        image: engine.image,
                        analysis: engine.imageAnalysis,
                        onCapture: { engine.acceptCapturedPhoto($0, slot: .primary) },
                        onClear: { engine.clearMedia() }
                    )
                }

                if demo.inputs.contains(.secondImage) {
                    ImageInputView(
                        title: "Image B",
                        selection: Binding(
                            get: { engine.secondImageSelection },
                            set: { newValue in
                                engine.secondImageSelection = newValue
                                engine.loadImageIfNeeded(newValue, slot: .secondary)
                            }
                        ),
                        image: engine.secondImage,
                        analysis: engine.secondImageAnalysis,
                        onCapture: { engine.acceptCapturedPhoto($0, slot: .secondary) }
                    )
                }

                if engine.isLoadingMedia {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("メディアを読み込んで解析しています…")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                if let error = engine.mediaLoadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if demo.inputs.contains(.instructions) {
                    LabTextEditor(
                        title: "Instructions",
                        text: $engine.instructions,
                        minHeight: 80,
                        presets: demo.inputs.contains(.instructionPreset) ? demo.instructionPresets : []
                    )
                }

                if demo.inputs.contains(.entityText) {
                    LabTextEditor(
                        title: "Natural Language Input",
                        text: $engine.entityText,
                        minHeight: 90,
                        presets: entityTextPresets
                    )
                }

                if demo.inputs.contains(.prompt) {
                    LabTextEditor(
                        title: "Prompt",
                        text: $engine.prompt,
                        minHeight: 80,
                        presets: demo.promptPresets
                    )
                }

                if demo.inputs.contains(.longText) {
                    LabTextEditor(
                        title: "Long Text",
                        text: $engine.longText,
                        minHeight: 140,
                        presets: [
                            DemoPreset("既定の長文", DemoData.longText),
                            DemoPreset("英語", "Apple Intelligence enables on-device language model access through the FoundationModels framework. Applications create a session, provide instructions, and send prompts. Responses can be received as Swift types annotated with @Generable, and @Guide declares value constraints so that model output stays inside them."),
                            DemoPreset("短文", "吾輩は猫である。名前はまだ無い。")
                        ]
                    )
                }
            }
        }
    }

    // MARK: - Options

    private var entityTextPresets: [DemoPreset] {
        if demo == .extraction {
            return [
                DemoPreset("備品発注メモ", DemoData.entityExtractionSample),
                DemoPreset("発注メモ2", "高橋七海さんが5月8日にラベルシールを12箱、レジロールを4本発注しました。検品は小松次郎さんが担当します。"),
                DemoPreset("納品メモ", "中村葵さんが6月3日に冷蔵ケースを2台、棚札を40枚受け取りました。設置確認は田村健さんが行います。")
            ]
        }

        return [
            DemoPreset("備品発注メモ", DemoData.entityExtractionSample),
            DemoPreset("処方1", DemoData.extractionSample),
            DemoPreset("処方2", DemoData.prescriptionSample),
            DemoPreset("複数薬剤", "鈴木一郎さん(72歳、P003)にメトホルミン250mgを1日2回朝夕食後30日分、ランソプラゾール15mgを就寝前1錠30日分処方します。")
        ]
    }

    private var optionSection: some View {
        LabSection("Options", symbol: "slider.horizontal.3", identifier: "section.options") {
            VStack(alignment: .leading, spacing: 16) {
                if demo.inputs.contains(.useCasePicker) {
                    Picker("Use Case", selection: Binding(
                        get: { engine.modelManager.useCase },
                        set: { engine.modelManager.useCase = $0; engine.refreshEnvironment() }
                    )) {
                        ForEach(SystemModelUseCase.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("SystemLanguageModel(useCase:) を切り替える。contentTagging は分類・タグ付けに特化した構成。")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                if demo.inputs.contains(.summaryStyle) {
                    Picker("Summary Size", selection: $engine.summaryStyle) {
                        ForEach(SummaryStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if demo.inputs.contains(.rewriteStyle) {
                    Picker("Preset", selection: $engine.rewriteStyle) {
                        ForEach(RewriteStyle.allCases) { Text($0.title).tag($0) }
                    }
                }

                if demo.inputs.contains(.expertiseMode) {
                    Picker("Mode", selection: $engine.expertiseMode) {
                        ForEach(ExpertiseMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(engine.expertiseMode.instructions)
                        .font(.caption2).foregroundStyle(.secondary)
                }

                if demo.inputs.contains(.profilePicker) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Profile", selection: $engine.activeProfile) {
                            ForEach(AgentProfile.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        // 仕様書 §51: Profile 変更時にアニメーションで切り替える。
                        VStack(alignment: .leading, spacing: 6) {
                            KeyValueTable(rows: engine.activeProfile.visualizerRows, compact: true)
                            // Tool 名は長いので横スクロールにする。折り返すと読めなくなる。
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(engine.activeProfile.tools.sorted { $0.rawValue < $1.rawValue }) { tool in
                                        Label(tool.displayName, systemImage: tool.symbol)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .fixedSize()
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4)
                                            .background((tool.hasSideEffect ? Color.orange : Color.blue).opacity(0.14), in: Capsule())
                                            .foregroundStyle(tool.hasSideEffect ? .orange : .blue)
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                        .id(engine.activeProfile)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .animation(.snappy, value: engine.activeProfile)
                    }
                }

                if demo.inputs.contains(.modelPicker) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Model", selection: $engine.activeModelChoice) {
                            ForEach(ModelChoice.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text("\(engine.activeModelChoice.apiTypeName) — \(engine.activeModelChoice.isBackedByInstalledSDK ? "このSDKで実際に呼べます" : "このSDKには型が存在しません")")
                            .font(.caption2)
                            .foregroundStyle(engine.activeModelChoice.isBackedByInstalledSDK ? .green : .orange)
                    }
                }

                if demo.inputs.contains(.patientPicker) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Selected Patient", selection: $engine.selectedPatientId) {
                            ForEach(DemoData.patients) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.segmented)
                        if let patient = engine.selectedPatient {
                            Text("\(patient.id) / \(patient.age)歳 / \(patient.note)")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text("処方: " + DemoData.prescriptions(forPatientId: patient.id).map(\.medicineName).joined(separator: ", "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                if demo.inputs.contains(.toolPicker) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tools").font(.subheadline.weight(.semibold))
                        ForEach(LabToolName.allCases.filter { $0 != .failing }) { tool in
                            Toggle(isOn: Binding(
                                get: { engine.playgroundTools.contains(tool) },
                                set: { isOn in
                                    if isOn { engine.playgroundTools.insert(tool) } else { engine.playgroundTools.remove(tool) }
                                }
                            )) {
                                HStack {
                                    Label(tool.displayName, systemImage: tool.symbol)
                                        .font(.subheadline)
                                    if tool.hasSideEffect { BetaBadge() }
                                }
                            }
                        }
                    }
                }

                if demo.inputs.contains(.samplingOptions) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Sampling Mode", selection: $engine.samplingChoice) {
                            ForEach(SamplingChoice.allCases) { Text($0.title).tag($0) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Temperature").font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", engine.temperature))
                                    .font(.subheadline.monospacedDigit())
                            }
                            Slider(value: $engine.temperature, in: 0...2)
                        }
                        Stepper("Maximum Response Tokens: \(engine.maximumResponseTokens)",
                                value: $engine.maximumResponseTokens, in: 32...4096, step: 32)
                            .font(.subheadline)
                    }
                }

                if demo.inputs.contains(.structuredToggle) {
                    Toggle("Structured Output (@Generable ImageAnalysis)", isOn: $engine.useStructuredOutput)
                        .font(.subheadline)
                }
                if demo.inputs.contains(.streamToggle) {
                    Toggle("Streaming (streamResponse)", isOn: $engine.useStreaming)
                        .font(.subheadline)
                        .disabled(engine.useStructuredOutput)
                }

                if demo.inputs.contains(.chunkSize) {
                    Stepper("チャンク上限トークン数: \(engine.chunkTokenBudget)",
                            value: $engine.chunkTokenBudget, in: 40...800, step: 20)
                        .font(.subheadline)
                }

                if demo.inputs.contains(.historyWindow) {
                    Stepper("モデルへ送る直近エントリ数: \(engine.historyWindow)",
                            value: $engine.historyWindow, in: 2...60, step: 2)
                        .font(.subheadline)
                }

                if demo.inputs.contains(.errorTrigger) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Error Trigger", selection: $engine.errorTrigger) {
                            ForEach(ErrorTrigger.allCases) { Text($0.title).tag($0) }
                        }
                        Text(engine.errorTrigger.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider()
                        Text("Error Catalog")
                            .font(.subheadline.weight(.semibold))
                        ForEach(ErrorCatalogEntry.all) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: entry.reproducible ? "play.circle" : "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(entry.reproducible ? .blue : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.error.errorType).font(.caption.weight(.semibold))
                                    Text(entry.howToReproduce).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if demo.inputs.contains(.schemaFields) {
                    schemaFieldEditor
                }
            }
        }
    }

    private var schemaFieldEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schema Fields").font(.subheadline.weight(.semibold))
            Stepper("生成件数: \(engine.dynamicSchemaRecordCount)",
                    value: $engine.dynamicSchemaRecordCount, in: 1...5)
                .font(.subheadline)
            ForEach($engine.schemaFields) { $field in
                VStack(spacing: 6) {
                    HStack {
                        TextField("name", text: $field.name)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                        Picker("", selection: $field.type) {
                            ForEach(SchemaField.FieldType.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        Button(role: .destructive) {
                            engine.schemaFields.removeAll { $0.id == field.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(engine.schemaFields.count <= 1)
                    }
                    HStack {
                        TextField("description (@Guide)", text: $field.fieldDescription)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        Toggle("Optional", isOn: $field.isOptional)
                            .font(.caption)
                            .fixedSize()
                    }
                }
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
            Button {
                engine.schemaFields.append(SchemaField(name: "field\(engine.schemaFields.count + 1)", type: .string))
            } label: {
                Label("Add Field", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Action

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 実行ボタンは主役なので幅を取り、副次的な操作は折り返して並べる。
            // iPhone 幅で1行に詰め込むとラベルが読めなくなるため。
            Button {
                engine.run(demo)
            } label: {
                Label(engine.isRunning ? "Running…" : demo.runLabel, systemImage: engine.isRunning ? "hourglass" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(engine.isRunning)
            .accessibilityIdentifier("action.run")

            HStack(spacing: 10) {
                Button {
                    engine.cancel()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!engine.isRunning)
                .accessibilityIdentifier("action.cancel")

                if demo.inputs.contains(.liveCamera), engine.camera.state.isRunning {
                    Button {
                        Task { await engine.narrateCurrentFrame() }
                    } label: {
                        Label("Narrate", systemImage: "text.bubble")
                    }
                    .buttonStyle(.bordered)
                    .disabled(engine.isNarrating)
                    .accessibilityIdentifier("action.narrate")
                }

                Button {
                    engine.resetSessions()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("action.reset")

                Spacer(minLength: 0)
            }
            .lineLimit(1)

            if engine.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Generating…")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        LabSection("Output", symbol: "doc.text", identifier: "section.output") {
            VStack(alignment: .leading, spacing: 14) {
                PayloadView(payload: engine.result.payload, isRunning: engine.isRunning)

                if let error = engine.result.error {
                    ErrorPanel(error: error)
                }

                if !engine.result.debugDetail.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Debug / 解説", systemImage: "info.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(engine.result.debugDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
