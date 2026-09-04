//
//  LabEngine+Session.swift
//  Foundation Models Lab
//
//  仕様書 §37-§44 (Transcript / Restore / Token / Context / Chunking / History / Prewarm)
//  §45-§48 (PCC / Reasoning / Capability)
//  §49-§56 (Agent)
//  §57-§58 (Custom Model / Model Switch)
//  §59 (Error Lab) / §84 (Playground)
//

import Foundation
import FoundationModels

extension LabEngine {

    // MARK: - DEMO 29 Transcript Viewer

    func runTranscript() async throws {
        try requireAvailableModel()
        // Tool も含めた Transcript を作るため、Tool 付きセッションで実行する。
        let session = latestSession ?? makeSession(
            instructions: "薬について聞かれたら searchDrug Tool を使ってください。必ず日本語で答えてください。",
            tools: [.drugSearch, .inventory]
        )
        result.executionMode = .foundationModels
        let response = try await session.respond(to: prompt, options: currentOptions)
        publishTranscript(session)
        drainToolLog()

        let entries = Array(session.transcript)
        result.payload = .timeline(timelineSteps(from: entries))
        result.metrics.transcriptTokens = try? await modelManager.tokenCount(for: session.transcript)
        result.debugDetail = """
        Transcript のエントリ数: \(entries.count)
        内訳: \(transcriptBreakdown(entries))
        推定トークン: \(result.metrics.transcriptTokens.map(String.init) ?? "取得不可") / contextSize \(modelManager.contextSize)

        Transcript.Entry は .instructions / .prompt / .toolCalls / .toolOutput / .response の5種類。
        各エントリの segments は .text または .structure（構造化出力）に分かれる。
        _ = response.content
        """
        _ = response
    }

    // MARK: - DEMO 30 Session Restore

    func runRestore() async throws {
        try requireAvailableModel()

        // 1. 現在のセッションの Transcript を保存する。
        //    まだ会話が無い場合は、保存対象を作るために1往復しておく。
        let session: LanguageModelSession
        if let existing = latestSession ?? conversationSession {
            session = existing
        } else {
            let fresh = conversationSessionOrCreate()
            _ = try await fresh.respond(to: prompt, options: currentOptions)
            publishTranscript(fresh)
            session = fresh
        }

        let transcript = session.transcript
        let data = try JSONEncoder().encode(transcript)
        savedTranscriptData = data
        savedTranscriptEntryCount = transcript.count

        // 2. 保存したデータから新しいセッションを作る。
        let decoded = try JSONDecoder().decode(Transcript.self, from: data)
        let restored = modelManager.makeSession(transcript: decoded)
        result.executionMode = .foundationModels

        // 3. 復元したセッションに履歴を前提とした質問をする。
        let response = try await restored.respond(to: "さっき何について話していた？", options: currentOptions)
        publishTranscript(restored)

        result.payload = .keyValue([
            KeyValueRow(label: "保存したエントリ数", value: "\(savedTranscriptEntryCount)"),
            KeyValueRow(label: "エンコードサイズ", value: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)),
            KeyValueRow(label: "復元後のエントリ数", value: "\(decoded.count)", status: decoded.count == savedTranscriptEntryCount ? .success : .warning),
            KeyValueRow(label: "質問", value: "さっき何について話していた？"),
            KeyValueRow(label: "復元セッションの回答", value: response.content, status: .success)
        ])
        result.debugDetail = """
        Transcript は Codable なので JSONEncoder でそのまま保存できる。
        LanguageModelSession(model:tools:transcript:) に渡すと、新しいセッションが履歴を持った状態で始まる。

        保存した JSON の先頭:
        \(String(data: data.prefix(600), encoding: .utf8) ?? "-")…
        """
    }

    // MARK: - DEMO 32 Token Count

    func runTokenCount() async throws {
        try requireAvailableModel()
        result.executionMode = .foundationModels

        let samples: [(String, String)] = [
            ("入力テキスト", longText),
            ("日本語サンプル", "吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。"),
            ("英語サンプル", "I am a cat. As yet I have no name. I have no idea where I was born."),
            ("混在サンプル", "FoundationModels の tokenCount(for:) は Prompt / Instructions / Tool / Schema / Transcript を測れます。")
        ]

        var rows: [KeyValueRow] = []
        for (label, text) in samples {
            try Task.checkCancellation()
            let tokens = try await modelManager.tokenCount(for: text)
            let characters = text.count
            let ratio = Double(tokens) / Double(max(1, characters))
            rows.append(KeyValueRow(label: label, value: "\(characters.formatted()) 文字 → \(tokens.formatted()) tokens（1文字あたり \(String(format: "%.2f", ratio))）"))
        }

        // Instructions / Tool / Schema も測れることを示す。
        let instructionTokens = try await modelManager.systemModel.tokenCount(for: Instructions(instructions))
        let tools = toolFactory.tools(for: [.drugSearch, .inventory, .patient])
        let toolTokens = try await modelManager.tokenCount(for: tools)
        let schemaTokens = try await modelManager.systemModel.tokenCount(for: Prescription.generationSchema)

        rows.append(contentsOf: [
            KeyValueRow(label: "Instructions", value: "\(instructionTokens.formatted()) tokens", status: .neutral),
            KeyValueRow(label: "Tools (3個の定義)", value: "\(toolTokens.formatted()) tokens", status: .neutral),
            KeyValueRow(label: "GenerationSchema (Prescription)", value: "\(schemaTokens.formatted()) tokens", status: .neutral),
            KeyValueRow(label: "Context Size", value: "\(modelManager.contextSize.formatted()) tokens", status: .success)
        ])

        result.payload = .keyValue(rows)
        result.metrics.promptTokens = try? await modelManager.tokenCount(for: longText)
        result.debugDetail = """
        これらは推定値ではなく SystemLanguageModel.tokenCount(for:) の実測値。
        日本語は1文字あたりのトークン数が英語より多くなる傾向があり、同じ文字数でも消費が異なる。

        Tool やスキーマの定義文もコンテキストを消費するため、Tool を増やすほど本文に使える余地が減る。
        送信前に tokenCount で測っておけば、exceededContextWindowSize を事前に避けられる。
        """
    }

    // MARK: - DEMO 31 Context Window

    func runContextWindow() async throws {
        try requireAvailableModel()
        result.executionMode = .foundationModels

        let session = latestSession ?? makeSession(instructions: instructions)
        let response = try await session.respond(to: prompt, options: currentOptions)
        publishTranscript(session)

        let maximum = modelManager.contextSize
        let used = (try? await modelManager.tokenCount(for: session.transcript)) ?? 0
        let promptTokens = (try? await modelManager.tokenCount(for: prompt)) ?? 0
        let longTextTokens = (try? await modelManager.tokenCount(for: longText)) ?? 0
        let percent = maximum > 0 ? Int((Double(used) / Double(maximum)) * 100) : 0

        result.metrics.transcriptTokens = used
        result.metrics.contextSize = maximum

        result.payload = .keyValue([
            KeyValueRow(label: "Current (Transcript)", value: "\(used.formatted()) tokens"),
            KeyValueRow(label: "Maximum (contextSize)", value: "\(maximum.formatted()) tokens"),
            KeyValueRow(label: "Usage", value: "\(percent)%  \(bar(percent))",
                        status: percent > 80 ? .error : percent > 50 ? .warning : .success),
            KeyValueRow(label: "残り", value: "\((maximum - used).formatted()) tokens"),
            KeyValueRow(label: "現在の Prompt", value: "\(promptTokens.formatted()) tokens"),
            KeyValueRow(label: "Long Text を追加送信したら", value: "\((used + longTextTokens).formatted()) tokens（\(used + longTextTokens > maximum ? "上限超過" : "収まる")）",
                        status: used + longTextTokens > maximum ? .error : .success),
            KeyValueRow(label: "直近の応答", value: response.content)
        ])
        result.debugDetail = """
        Maximum は SystemLanguageModel.contextSize の実行時値。UIにハードコードしていない（仕様書 §39 の注記）。
        Current は同じセッションの transcript を tokenCount(for:) に渡した実測値。

        同じセッションで respond を繰り返すと Current が増え続ける。
        History Transform デモでこれを抑える方法を確認できる。
        """
    }

    // MARK: - DEMO 33 Context Size Exceeded

    func runContextExceeded() async throws {
        try requireAvailableModel()
        result.executionMode = .foundationModels

        // contextSize を確実に超える長さを実測から組み立てる。
        let unitTokens = max(1, (try? await modelManager.tokenCount(for: longText)) ?? 200)
        let repeatCount = max(2, Int(ceil(Double(modelManager.contextSize) / Double(unitTokens))) + 2)
        let huge = Array(repeating: longText, count: repeatCount).joined(separator: "\n\n")
        let hugeTokens = (try? await modelManager.tokenCount(for: huge)) ?? -1

        result.metrics.promptTokens = hugeTokens >= 0 ? hugeTokens : nil
        result.debugDetail = """
        送信前の実測:
        - longText 1回 = \(unitTokens) tokens
        - contextSize = \(modelManager.contextSize) tokens
        - \(repeatCount) 回繰り返して \(hugeTokens) tokens の Prompt を作成
        これを実際に respond へ渡す。エラーは捏造ではなく実際に発生したものを表示する。
        """

        let session = makeSession(instructions: "要約してください。")
        // ここで実際に GenerationError.exceededContextWindowSize が飛ぶことを期待する。
        let response = try await session.respond(to: huge, options: GenerationOptions(maximumResponseTokens: 128))
        publishTranscript(session)

        // 万一エラーにならなかった場合も、値を捏造せず事実を表示する。
        result.payload = .keyValue([
            KeyValueRow(label: "結果", value: "エラーになりませんでした", status: .warning),
            KeyValueRow(label: "送信トークン", value: "\(hugeTokens)"),
            KeyValueRow(label: "contextSize", value: "\(modelManager.contextSize)"),
            KeyValueRow(label: "応答", value: String(response.content.prefix(400)))
        ])
        result.debugDetail += "\n\nこの実行では例外が発生しなかった。モデル側で入力が切り詰められた可能性がある。"
    }

    // MARK: - DEMO 34 Chunking

    func runChunking() async throws {
        try requireAvailableModel()
        result.executionMode = .foundationModels

        let measured = await measuredChunks(longText, tokenBudget: chunkTokenBudget)
        let chunks = measured.map(\.text)
        let documentTokens = await tokenLength(longText)
        var steps: [TimelineStep] = [
            TimelineStep(
                title: "Document",
                detail: "\(longText.count) 文字 / \(documentTokens) tokens → \(chunks.count) チャンク（1チャンク上限 \(chunkTokenBudget) tokens）",
                kind: .note
            )
        ]

        var partials: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let started = Date()
            // チャンクごとに新しいセッションを使い、履歴を溜めない。
            let session = makeSession(instructions: "渡された断片だけを1〜2文で要約してください。断片に無い情報を足さないでください。必ず日本語で答えてください。")
            // Apple の Managing the context window どおり、前のチャンクの要約だけを次へ渡して
            // 文脈をつなぐ。全文ではなく要約なので、チャンク数を増やしても消費は伸びない。
            let chunkPrompt = index == 0
                ? chunk
                : """
                  [前の断片の要約]
                  \(partials[index - 1])

                  [今回の断片]
                  \(chunk)
                  """
            let response = try await session.respond(
                to: chunkPrompt,
                options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 160)
            )
            partials.append(response.content)
            // 予算はチャンク本体にかかる。前の要約を足した送信量は別に見せる（混同を避ける）。
            // チャンク本体のトークン数は分割時に実測済みなので、ここでは測り直さない。
            let chunkTokens = measured[index].tokens
            let sentTokens = index == 0 ? chunkTokens : await tokenLength(chunkPrompt)
            let sizeLine = index == 0
                ? "チャンク \(chunk.count) 文字 / \(chunkTokens) tokens（上限 \(chunkTokenBudget)）"
                : "チャンク \(chunk.count) 文字 / \(chunkTokens) tokens（上限 \(chunkTokenBudget)）＋ 前の要約 → 送信 \(sentTokens) tokens"
            steps.append(TimelineStep(
                title: "Chunk \(index + 1) / \(chunks.count)",
                detail: "\(sizeLine)\n\n\(response.content)",
                kind: .response,
                elapsed: Date().timeIntervalSince(started)
            ))
        }

        // 部分要約を統合する。
        let mergeStarted = Date()
        let mergeSession = makeSession(instructions: "複数の部分要約を、重複を除いてひとつの要約に統合してください。必ず日本語で答えてください。")
        let merged = try await mergeSession.respond(
            to: "次の部分要約を統合して、全体を3〜4文でまとめてください。\n\n" + partials.enumerated().map { "(\($0.offset + 1)) \($0.element)" }.joined(separator: "\n"),
            options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 400)
        )
        publishTranscript(mergeSession)
        steps.append(TimelineStep(
            title: "統合要約",
            detail: merged.content,
            kind: .response,
            elapsed: Date().timeIntervalSince(mergeStarted)
        ))

        result.payload = .timeline(steps)
        result.debugDetail = """
        Chunk 数: \(chunks.count)（上限 \(chunkTokenBudget) tokens / 実測 tokenCount(for:) で判定）
        モデル呼び出し回数: \(chunks.count) + 1（統合）= \(chunks.count + 1)

        分割の境界は文単位、収まるかどうかの判定はトークン数で行う。
        文字数はトークン数の近似にしかならない（日本語は1文字がほぼ1トークン、
        ラテン文字は3〜4文字で1トークン）ため、文字数だけで切ると言語によって収まり方が変わる。

        各チャンクは独立したセッションで処理するため、チャンク数を増やしても
        1回あたりのコンテキスト消費は増えない。文脈は「前のチャンクの要約」だけを
        次のプロンプトへ渡してつなぐ。長文はこの map-reduce 型で扱う。
        """
    }

    /// 文の境界を尊重しつつ、トークン予算に収まるように分割する。
    ///
    /// Apple の Managing the context window は「コンテキストウィンドウに収まるチャンクへ分割する」ことを
    /// 求めている。文字数はトークン数の近似にしかならない（日本語はほぼ1文字が1トークン、
    /// ラテン文字は3〜4文字で1トークン）ため、同じ文字数でも収まるかどうかは言語で変わる。
    /// そこで境界は文で決め、収まっているかはトークン数で判定する。
    ///
    /// 手順は2段。
    /// 1. 概算で文を積んで下書きの分割を作る（モデル呼び出しなし）
    /// 2. 各チャンクを tokenCount(for:) で実測し、予算を超えていたものだけ割り直す
    ///
    /// 文ごとに実 API を呼ぶと呼び出しが文の数だけ増えて画面が目に見えて遅くなる。
    /// Apple「Managing the context window」が求めているのは
    /// 「コンテキストに収まるチャンクにすること」なので、収まりの判定を実測で行えば足りる。
    func measuredChunks(_ text: String, tokenBudget: Int) async -> [MeasuredSentence] {
        let budget = max(40, tokenBudget)
        let draft = Self.assemble(
            Self.sentences(of: text).map { MeasuredSentence(text: $0, tokens: Self.estimatedTokens($0)) },
            tokenBudget: budget,
            fallback: text
        )

        var result: [MeasuredSentence] = []
        for chunk in draft {
            let tokens = await tokenLength(chunk)
            if tokens <= budget {
                result.append(MeasuredSentence(text: chunk, tokens: tokens))
                continue
            }
            // 概算が実測より小さかった分だけ補正して割り直す。
            let estimate = max(1, Self.estimatedTokens(chunk))
            let ratio = Double(tokens) / Double(estimate)
            let corrected = Self.sentences(of: chunk).map {
                MeasuredSentence(text: $0, tokens: Int((Double(Self.estimatedTokens($0)) * ratio).rounded(.up)))
            }
            for piece in Self.assemble(corrected, tokenBudget: budget, fallback: chunk) {
                result.append(MeasuredSentence(text: piece, tokens: await tokenLength(piece)))
            }
        }
        return result.isEmpty ? [MeasuredSentence(text: text, tokens: await tokenLength(text))] : result
    }

    /// 分割結果の文字列だけが必要な場合。
    func chunk(_ text: String, tokenBudget: Int) async -> [String] {
        await measuredChunks(text, tokenBudget: tokenBudget).map(\.text)
    }

    /// トークン数の実測値。モデルが使えないときは概算に落とす。
    func tokenLength(_ text: String) async -> Int {
        if modelManager.availability.isAvailable,
           let exact = try? await modelManager.tokenCount(for: text) {
            return exact
        }
        return Self.estimatedTokens(text)
    }

    struct MeasuredSentence: Sendable {
        var text: String
        var tokens: Int
    }

    /// 句点と改行を文の境界とみなして切り出す。境界文字は前の文に含める。
    static func sentences(of text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "。" || character == "\n" {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty { sentences.append(current) }
        return sentences
    }

    /// 計測済みの文を、予算を超えない範囲で連結する。
    static func assemble(_ measured: [MeasuredSentence], tokenBudget: Int, fallback: String) -> [String] {
        var chunks: [String] = []
        var buffer = ""
        var bufferTokens = 0

        for sentence in measured {
            // 1文だけで予算を超えるときは、その文をさらに割ってから積む。
            if sentence.tokens > tokenBudget {
                if !buffer.isEmpty {
                    chunks.append(buffer)
                    buffer = ""
                    bufferTokens = 0
                }
                chunks.append(contentsOf: splitOversized(sentence, tokenBudget: tokenBudget))
                continue
            }
            if bufferTokens + sentence.tokens > tokenBudget, !buffer.isEmpty {
                chunks.append(buffer)
                buffer = ""
                bufferTokens = 0
            }
            buffer += sentence.text
            bufferTokens += sentence.tokens
        }
        if !buffer.isEmpty { chunks.append(buffer) }
        return chunks.isEmpty ? [fallback] : chunks
    }

    /// 1文で予算を超えた場合の分割。トークン数と文字数はおおむね比例するので、
    /// 必要な分割数から1片の文字数を決める。
    private static func splitOversized(_ sentence: MeasuredSentence, tokenBudget: Int) -> [String] {
        let pieces = max(2, Int((Double(sentence.tokens) / Double(tokenBudget)).rounded(.up)))
        let perPiece = max(1, Int((Double(sentence.text.count) / Double(pieces)).rounded(.up)))
        var result: [String] = []
        var current = ""
        for character in sentence.text {
            current.append(character)
            if current.count >= perPiece {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// トークン数の概算。モデルの tokenCount が使えない環境（Apple Intelligence 無効）用。
    /// Apple の記述（CJK は1文字1トークン / ラテン文字は3〜4文字で1トークン）に合わせている。
    static func estimatedTokens(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        var score = 0.0
        for scalar in text.unicodeScalars {
            score += isWideScript(scalar) ? 1.0 : 0.3
        }
        return max(1, Int(score.rounded(.up)))
    }

    private static func isWideScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x30FF,   // CJK 記号・ひらがな・カタカナ
             0x3400...0x4DBF,   // CJK 拡張A
             0x4E00...0x9FFF,   // CJK 統合漢字
             0xAC00...0xD7AF,   // ハングル
             0xF900...0xFAFF,   // CJK 互換漢字
             0xFF00...0xFF60:   // 全角形
            true
        default:
            false
        }
    }

    // MARK: - DEMO 35 History Transform

    func runHistoryTransform() async throws {
        try requireAvailableModel()
        result.executionMode = .foundationModels

        // 履歴を意図的に積み上げる。
        let session = conversationSessionOrCreate()
        if session.transcript.count < 6 {
            let seedPrompts = [
                "私の名前はTaroです。覚えてください。",
                "私は薬局で在庫管理を担当しています。",
                "よく扱う薬はアムロジピンとロキソプロフェンです。",
                "在庫の発注点は100錠に設定しています。"
            ]
            for seed in seedPrompts {
                try Task.checkCancellation()
                _ = try await session.respond(to: seed, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 80))
            }
        }
        _ = try await session.respond(to: prompt, options: currentOptions)
        publishTranscript(session)

        let all = Array(session.transcript)
        let totalTokens = (try? await modelManager.tokenCount(for: all)) ?? 0

        // Instructions は必ず残し、直近 N 件だけを送る。
        let instructionEntries = all.filter { if case .instructions = $0 { return true } else { return false } }
        let others = all.filter { if case .instructions = $0 { return false } else { return true } }
        let window = max(2, historyWindow)
        let kept = Array(others.suffix(window))
        let trimmedEntries = instructionEntries + kept
        let trimmed = Transcript(entries: trimmedEntries)
        let trimmedTokens = (try? await modelManager.tokenCount(for: trimmedEntries)) ?? 0

        // 縮めた履歴で新しいセッションを作り、まだ答えられるかを確認する。
        let trimmedSession = modelManager.makeSession(transcript: trimmed)
        let response = try await trimmedSession.respond(to: "私の名前と担当業務を教えて。", options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 200))

        result.metrics.transcriptTokens = trimmedTokens
        result.payload = .keyValue([
            KeyValueRow(label: "Total", value: "\(all.count) entries / \(totalTokens.formatted()) tokens"),
            KeyValueRow(label: "Sent to Model", value: "\(trimmedEntries.count) entries / \(trimmedTokens.formatted()) tokens", status: .success),
            KeyValueRow(label: "削減率", value: totalTokens > 0 ? "\(Int((1 - Double(trimmedTokens) / Double(totalTokens)) * 100))%" : "-"),
            KeyValueRow(label: "Window", value: "直近 \(window) entries + Instructions"),
            KeyValueRow(label: "縮小後の質問", value: "私の名前と担当業務を教えて。"),
            KeyValueRow(label: "縮小後の回答", value: response.content,
                        status: response.content.contains("Taro") ? .success : .warning)
        ])
        result.debugDetail = """
        全履歴の内訳: \(transcriptBreakdown(all))
        送信した履歴の内訳: \(transcriptBreakdown(trimmedEntries))

        Instructions を落とすとモデルの振る舞いが変わってしまうため、先頭の .instructions は常に残す。
        window を小さくしすぎると、古い履歴にしか無い情報（名前など）を答えられなくなる。
        上の「縮小後の回答」で、必要な情報が窓に残っているかを確認できる。
        """
    }

    // MARK: - DEMO 36 Prewarm

    func runPrewarm() async throws {
        try requireAvailableModel()
        result.executionMode = .foundationModels

        // OFF: prewarm せずに1往復。
        let coldSession = makeSession(instructions: "簡潔に、必ず日本語で答えてください。")
        let coldStarted = Date()
        let coldResponse = try await coldSession.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: 200))
        let coldElapsed = Date().timeIntervalSince(coldStarted)

        try Task.checkCancellation()

        // ON: prewarm してから1往復。
        let warmSession = makeSession(instructions: "簡潔に、必ず日本語で答えてください。")
        let prewarmStarted = Date()
        warmSession.prewarm(promptPrefix: Prompt(prompt))
        let prewarmCallElapsed = Date().timeIntervalSince(prewarmStarted)
        // prewarm は非同期に準備を進めるので、少し待ってから送る。
        try await Task.sleep(for: .milliseconds(400))
        let warmStarted = Date()
        let warmResponse = try await warmSession.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: 200))
        let warmElapsed = Date().timeIntervalSince(warmStarted)
        publishTranscript(warmSession)

        result.payload = .comparison([
            ComparisonColumn(
                title: "Prewarm OFF",
                subtitle: "セッション生成 → 即 respond",
                body: coldResponse.content,
                footnotes: [KeyValueRow(label: "First Response Latency", value: String(format: "%.0f ms", coldElapsed * 1000))]
            ),
            ComparisonColumn(
                title: "Prewarm ON",
                subtitle: "prewarm(promptPrefix:) → 400ms 待機 → respond",
                body: warmResponse.content,
                footnotes: [
                    KeyValueRow(label: "First Response Latency", value: String(format: "%.0f ms", warmElapsed * 1000),
                                status: warmElapsed < coldElapsed ? .success : .warning),
                    KeyValueRow(label: "prewarm 呼び出し自体", value: String(format: "%.1f ms（即座に返る）", prewarmCallElapsed * 1000)),
                    KeyValueRow(label: "差", value: String(format: "%+.0f ms", (warmElapsed - coldElapsed) * 1000))
                ]
            )
        ])
        result.debugDetail = """
        これは1回ずつの実測値であり、端末の状態（他アプリの負荷、モデルが既にメモリにあるか）に大きく左右される。
        prewarm が効くのは「モデルの読み込みがまだ済んでいない初回」であり、
        既に温まっている状態では差が出ない、あるいは逆転することもある。
        仕様書 §44 の注記どおり、これは性能を保証する機能ではない。

        prewarm(promptPrefix:) は即座に返る非同期のヒントであり、完了を待つ API は無い。
        この画面では 400ms の待機を挟んでから respond している。
        """
    }

    // MARK: - DEMO 37/38 PCC, DEMO 40 Quota

    func runPCC() {
        result.executionMode = .sdkUnavailable
        result.payload = .keyValue([
            KeyValueRow(label: "Availability", value: "SDK未提供", status: .error),
            KeyValueRow(label: "型", value: "PrivateCloudComputeLanguageModel", status: .error),
            KeyValueRow(label: "確認方法", value: "FoundationModels.framework の swiftinterface に該当型が存在しない"),
            KeyValueRow(label: "Context Size", value: "取得不可（型が無いため）"),
            KeyValueRow(label: "Japanese", value: "取得不可"),
            KeyValueRow(label: "Quota", value: "取得不可"),
            KeyValueRow(label: "代替", value: "On-device の SystemLanguageModel で比較する", status: .warning),
            KeyValueRow(label: "On-device Availability", value: modelManager.availability.label,
                        status: modelManager.availability.isAvailable ? .success : .error),
            KeyValueRow(label: "On-device Context Size", value: "\(modelManager.contextSize.formatted()) tokens", status: .success)
        ])
        result.error = LabError.sdkFeatureMissing(
            "PrivateCloudComputeLanguageModel",
            alternative: "PCC を提供するSDK / OS に更新してください。それまでは On-device モデルで比較できます。"
        )
        result.debugDetail = """
        仕様書 §11 / §45 / §46 は Model B として PrivateCloudComputeLanguageModel を想定しているが、
        インストール済みSDK（iOS 26 系）の FoundationModels には該当する型が存在しない。

        確認したもの:
        - FoundationModels.framework の公開型に PCC 関連の型が無い
        - SystemLanguageModel には PCC へ切り替える API が無い
        - reasoning レベルを指定する API も無い

        仕様書 §46 の「PCC利用不可の場合も正常なデモ画面として扱う」に従い、
        推測値を表示せず、取得できない項目は「取得不可」と明示している。
        """
    }

    func runQuota() {
        result.executionMode = .sdkUnavailable
        result.payload = .keyValue([
            KeyValueRow(label: "PCC Quota API", value: "SDK未提供", status: .error),
            KeyValueRow(label: "Rate Limit", value: "GenerationError.rateLimited として実行時に飛ぶのみ", status: .warning),
            KeyValueRow(label: "事前に残量を問い合わせる API", value: "存在しない", status: .error),
            KeyValueRow(label: "アプリ側で測れること", value: "リクエスト回数と rateLimited の発生回数"),
            KeyValueRow(label: "このセッションのモデル呼び出し回数", value: "\(lifecycleLog.filter { $0.kind == .onPrompt }.count)"),
            KeyValueRow(label: "rateLimited 発生回数", value: "\(lifecycleLog.filter { $0.detail.contains("Rate limited") }.count)")
        ])
        result.error = LabError.sdkFeatureMissing("PCC Quota", alternative: "実行時の rateLimited エラーをカウントして代替把握してください。")
        result.debugDetail = "残量を事前に取得する API は無いため、この画面はアプリ側で数えられる実測値のみを表示している。"
    }

    // MARK: - DEMO 39 Reasoning Level

    func runReasoning() async throws {
        // reasoning 設定の API は無い。代わりに「何が代替になるか」を実測で示す。
        result.executionMode = .foundationModels
        try requireAvailableModel()

        let question = prompt
        // 浅い: 短く即答させる
        let shallowStarted = Date()
        let shallow = try await makeSession(instructions: "結論だけを1文で答えてください。過程は書かないでください。必ず日本語で答えてください。")
            .respond(to: question, options: GenerationOptions(sampling: .greedy, temperature: 0.1, maximumResponseTokens: 120))
        let shallowElapsed = Date().timeIntervalSince(shallowStarted)

        try Task.checkCancellation()

        // 深い: 段階的に考えさせる（Instructions と maxTokens による近似）
        let deepStarted = Date()
        let deep = try await makeSession(instructions: "前提を分解し、順を追って検討したうえで結論を述べてください。検算できる場合は検算してください。必ず日本語で答えてください。")
            .respond(to: question, options: GenerationOptions(sampling: .greedy, temperature: 0.1, maximumResponseTokens: 1024))
        let deepElapsed = Date().timeIntervalSince(deepStarted)

        result.payload = .comparison([
            ComparisonColumn(
                title: "Shallow（近似）",
                subtitle: "Instructions で即答を要求 / maxTokens 120",
                body: shallow.content,
                footnotes: [
                    KeyValueRow(label: "Elapsed", value: String(format: "%.2f sec", shallowElapsed)),
                    KeyValueRow(label: "文字数", value: "\(shallow.content.count)")
                ]
            ),
            ComparisonColumn(
                title: "Deep（近似）",
                subtitle: "Instructions で段階的検討を要求 / maxTokens 1024",
                body: deep.content,
                footnotes: [
                    KeyValueRow(label: "Elapsed", value: String(format: "%.2f sec", deepElapsed)),
                    KeyValueRow(label: "文字数", value: "\(deep.content.count)")
                ]
            ),
            ComparisonColumn(
                title: "Reasoning Level API",
                subtitle: "GenerationOptions に reasoning 相当のプロパティ",
                body: "SDK未提供。GenerationOptions が持つのは sampling / temperature / maximumResponseTokens の3つのみ。",
                footnotes: [KeyValueRow(label: "状態", value: "取得不可", status: .error)],
                isUnavailable: true
            )
        ])
        result.debugDetail = """
        仕様書 §47 は「APIで利用可能なreasoning設定を選択可能とする」としているが、
        インストール済みSDKの GenerationOptions に reasoning レベルのプロパティは存在しない。

        そのためこの画面では、reasoning そのものではなく
        「Instructions と maxTokens で推論の深さをどこまで近似できるか」を実測で並べている。
        左2列は実際の応答と実測時間。3列目は API が無いことの明示。
        """
    }

    // MARK: - DEMO 40 Capabilities

    func runCapabilities() {
        modelManager.refresh()
        result.executionMode = .localOnly
        result.payload = .keyValue(
            [
                KeyValueRow(label: "Current Model", value: activeModelChoice.apiTypeName,
                            status: activeModelChoice.isBackedByInstalledSDK ? .success : .error),
                KeyValueRow(label: "Availability", value: modelManager.availability.label,
                            status: modelManager.availability.isAvailable ? .success : .error),
                KeyValueRow(label: "Context Size", value: "\(modelManager.contextSize.formatted()) tokens"),
                KeyValueRow(label: "Use Case", value: modelManager.useCase.rawValue),
                KeyValueRow(label: "Current Locale", value: modelManager.supportsCurrentLocale ? "Supported" : "Not supported",
                            status: modelManager.supportsCurrentLocale ? .success : .warning)
            ]
            + modelManager.capabilities.rows.map {
                KeyValueRow(label: $0.0, value: ($0.1 ? "✓ " : "— ") + $0.2, status: $0.1 ? .success : .warning)
            }
            + [KeyValueRow(label: "Supported Languages", value: modelManager.supportedLanguageTags.joined(separator: ", "))]
        )
        result.debugDetail = """
        FoundationModels には Capabilities を列挙する API が無いため、この表は
        「SDKにその型/メソッドが存在するか」＋「availability が available か」から構成している。

        存在を確認した API:
        SystemLanguageModel.availability / .contextSize / .supportedLanguages / .supportsLocale(_:) / .tokenCount(for:)
        LanguageModelSession.respond(to:) / .respond(to:generating:) / .respond(to:schema:) / .streamResponse(to:) / .prewarm(promptPrefix:) / .transcript
        Tool protocol / @Generable / @Guide / GenerationSchema / DynamicGenerationSchema / GenerationOptions / Transcript(Codable)

        公開 API として存在しないもの:
        - 画像添付（ランタイムにもシンボルが無い）
        - PrivateCloudComputeLanguageModel / LanguageModel protocol / LanguageModelExecutor
          → ランタイムには実装済みで存在するが swiftinterface から除外された SPI。参照できない。
        - reasoning レベル指定
        """
    }

    // MARK: - DEMO 49 Custom Model / DEMO 50 Model Switch

    func runCustomModel() async throws {
        let model = labModel
        let started = Date()
        do {
            let text = try await model.respond(
                to: prompt,
                instructions: instructions,
                options: currentOptions
            )
            result.executionMode = activeModelChoice == .onDevice ? .foundationModels : .localOnly
            result.modelName = model.displayName
            result.apiTypeName = model.typeName
            result.payload = .keyValue([
                KeyValueRow(label: "Model", value: model.displayName, status: .success),
                KeyValueRow(label: "Type", value: model.typeName),
                KeyValueRow(label: "Elapsed", value: String(format: "%.2f sec", Date().timeIntervalSince(started))),
                KeyValueRow(label: "Response", value: text)
            ])
        } catch let error as LabError where error.category == .sdkFeatureMissing {
            result.executionMode = .sdkUnavailable
            result.error = error
            result.payload = .keyValue([
                KeyValueRow(label: "Model", value: model.displayName, status: .error),
                KeyValueRow(label: "Type", value: model.typeName, status: .error),
                KeyValueRow(label: "結果", value: "このモデルはSDK未提供のため呼び出せません", status: .error)
            ])
        }
        result.debugDetail = """
        FoundationModels に LanguageModel protocol は無いため、アプリ側に LabLanguageModel を定義し、
        SystemModelAdapter / MockExecutorModel / UnavailablePCCModel の3実装を切り替えている。

        protocol LabLanguageModel: Sendable {
            var displayName: String { get }
            func respond(to prompt: String, instructions: String?, options: GenerationOptions) async throws -> String
        }

        Mock Server Model を選ぶと、FoundationModels の呼び出し形（Instructions + Prompt + GenerationOptions）を
        保ったまま処理が独自 Executor へ流れる。第2段階でこの Executor を外部LLMの実装へ差し替えられる。
        """
    }

    /// 仕様書 §45 DEMO 37 PCC Basic: On-device と PCC を同一 Prompt で並べる。
    func runModelComparison() async throws {
        try requireAvailableModel()
        result.executionMode = .foundationModels

        // On-device は実際に呼ぶ。
        let started = Date()
        let session = makeSession(instructions: instructions)
        let response = try await session.respond(to: prompt, options: currentOptions)
        publishTranscript(session)
        let elapsed = Date().timeIntervalSince(started)
        let promptTokens = (try? await modelManager.tokenCount(for: prompt)) ?? 0
        let responseTokens = (try? await modelManager.tokenCount(for: response.content)) ?? 0
        result.metrics.promptTokens = promptTokens
        result.metrics.responseTokens = responseTokens

        result.payload = .comparison([
            ComparisonColumn(
                title: "On Device",
                subtitle: "SystemLanguageModel",
                body: response.content,
                footnotes: [
                    KeyValueRow(label: "Elapsed", value: String(format: "%.2f sec", elapsed)),
                    KeyValueRow(label: "Context", value: "\(modelManager.contextSize.formatted()) tokens"),
                    KeyValueRow(label: "Prompt / Response Tokens", value: "\(promptTokens) / \(responseTokens)"),
                    KeyValueRow(label: "実行", value: "実際に呼び出し", status: .success)
                ]
            ),
            ComparisonColumn(
                title: "PCC",
                subtitle: "PrivateCloudComputeLanguageModel",
                body: """
                SDK未提供のため実行できません。
                インストール済み FoundationModels にこの型は存在しません。

                本来ここで比較したい項目:
                - 長文への追従性
                - 強い推論を要する問題の正答
                - より大きな context の利用
                """,
                footnotes: [
                    KeyValueRow(label: "Elapsed", value: "取得不可", status: .error),
                    KeyValueRow(label: "Context", value: "取得不可", status: .error),
                    KeyValueRow(label: "実行", value: "呼び出し不可", status: .error)
                ],
                isUnavailable: true
            )
        ])
        result.debugDetail = """
        仕様書 §45 は On-device と PCC を同一 Prompt で比較する画面を求めているが、
        PCC モデル型がSDKに無いため右列は実行できない。値を推測せず「取得不可」と表示している。

        3モデル（On-device / PCC / Custom Mock）の比較は Model Switch デモで行う。
        """
    }

    func runModelSwitch() async throws {
        var columns: [ComparisonColumn] = []
        for choice in ModelChoice.allCases {
            try Task.checkCancellation()
            let model: any LabLanguageModel = switch choice {
            case .onDevice: SystemModelAdapter(capabilities: modelManager.capabilities, model: modelManager.systemModel)
            case .pcc: UnavailablePCCModel()
            case .custom: MockExecutorModel()
            }
            let started = Date()
            do {
                let text = try await model.respond(to: prompt, instructions: instructions, options: currentOptions)
                let elapsed = Date().timeIntervalSince(started)
                columns.append(ComparisonColumn(
                    title: model.displayName,
                    subtitle: model.typeName,
                    body: text,
                    footnotes: [
                        KeyValueRow(label: "Latency", value: String(format: "%.2f sec", elapsed)),
                        KeyValueRow(label: "Guided Generation", value: model.capabilities.guidedGeneration ? "✓" : "—"),
                        KeyValueRow(label: "Tool Calling", value: model.capabilities.toolCalling ? "✓" : "—"),
                        KeyValueRow(label: "Streaming", value: model.capabilities.streaming ? "✓" : "—")
                    ]
                ))
                if choice == .onDevice { result.executionMode = .foundationModels }
            } catch {
                let mapped = LabError.map(error)
                columns.append(ComparisonColumn(
                    title: model.displayName,
                    subtitle: model.typeName,
                    body: "\(mapped.errorType)\n\(mapped.technicalDetail)\n\n復旧: \(mapped.recovery)",
                    footnotes: [KeyValueRow(label: "状態", value: "呼び出し不可", status: .error)],
                    isUnavailable: true
                ))
            }
        }
        result.payload = .comparison(columns)
        result.debugDetail = """
        同一 Prompt / Instructions / GenerationOptions を3つのモデル実装へ投げた結果。
        On-device のみ実際の FoundationModels、PCC はSDK未提供、Custom はモック Executor。
        """
    }

    // MARK: - Developer

    func runLogs() {
        result.executionMode = .localOnly
        result.payload = .keyValue(
            [
                KeyValueRow(label: "Tool 呼び出し累計", value: "\(sessionToolLog.count)"),
                KeyValueRow(label: "失敗した Tool 呼び出し", value: "\(sessionToolLog.filter(\.failed).count)",
                            status: sessionToolLog.contains(where: \.failed) ? .warning : .success),
                KeyValueRow(label: "Lifecycle イベント数", value: "\(sessionLifecycleLog.count)"),
                KeyValueRow(label: "呼ばれた Tool の種類", value: Set(sessionToolLog.map(\.toolName)).sorted().joined(separator: ", ").ifEmpty("なし")),
                KeyValueRow(label: "承認待ちの副作用", value: "\(pendingSideEffects.count)",
                            status: pendingSideEffects.isEmpty ? .success : .warning)
            ]
            + inventory.all.map { KeyValueRow(label: "在庫: \($0.name)", value: "\($0.stock)\($0.unit)", status: $0.isLow ? .warning : .success) }
        )
        result.debugDetail = """
        この画面だけはセッション全体の履歴を表示する。
        他のデモ画面は、切り替えたときに Output / Transcript / Tool Calls を初期化する
        （前の画面の結果が残っていると、いま何を見ているのか分からなくなるため）。
        全部消したいときは Reset Session を押す。
        """
    }

    func runAPIReference() {
        result.executionMode = .localOnly
        let all = LabDemo.allCases.flatMap(\.usedAPIs)
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.symbol).inserted }
        result.payload = .keyValue(
            unique.sorted { ($0.framework, $0.symbol) < ($1.framework, $1.symbol) }
                .map { KeyValueRow(label: $0.framework, value: $0.symbol) }
        )
        result.usedAPIs = unique
        result.debugDetail = """
        全 \(LabDemo.allCases.count) デモが参照している API を重複排除して \(unique.count) 件。
        各デモ画面の Used APIs セクションからも同じリンクへ飛べる。
        """
    }

    // MARK: - Helpers

    private func transcriptBreakdown(_ entries: [Transcript.Entry]) -> String {
        var counts: [String: Int] = [:]
        for entry in entries {
            let key: String = switch entry {
            case .instructions: "instructions"
            case .prompt: "prompt"
            case .toolCalls: "toolCalls"
            case .toolOutput: "toolOutput"
            case .response: "response"
            @unknown default: "unknown"
            }
            counts[key, default: 0] += 1
        }
        return counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }

    func bar(_ percent: Int) -> String {
        let filled = min(20, max(0, percent / 5))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: 20 - filled)
    }
}
