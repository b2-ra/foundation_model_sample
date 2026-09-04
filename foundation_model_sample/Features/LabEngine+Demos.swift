//
//  LabEngine+Demos.swift
//  Foundation Models Lab
//
//  各デモの実処理。可能なものはすべて実際に FoundationModels / Vision を呼ぶ。
//  SDKにAPIが存在しない機能は、値を捏造せず「SDK未提供」として表示する。
//

import Foundation
import CoreGraphics
import FoundationModels

extension LabEngine {

    // MARK: - Dispatch

    func runDemo(_ demo: LabDemo) async throws {
        switch demo {
        // OVERVIEW
        case .dashboard: try await runDashboard()
        // TEXT
        case .simpleGeneration: try await runSimpleGeneration()
        case .instructions: try await runInstructions()
        case .conversation: try await runConversation()
        case .streaming: try await runStreaming()
        case .summarization: try await runSummarization()
        case .rewrite: try await runRewrite()
        case .classification: try await runClassification()
        case .extraction: try await runExtraction()
        // STRUCTURED
        case .generable: try await runGenerable()
        case .guideComparison: try await runGuideComparison()
        case .enumGeneration: try await runEnumGeneration()
        case .nestedObject: try await runNestedObject()
        case .dynamicSchema: try await runDynamicSchema()
        case .generationOptions: try await runGenerationOptions()
        case .greedySampling: try await runGreedySampling()
        // TOOLS
        // Tool の出力だけを答えさせる。iOS 26 の GenerationOptions には toolCallingMode が無いため
        // （iOS 27 で追加された API。実測: swiftinterface に該当シンボルが無い）、
        // Apple 安全ガイドの「モデルは prompt より Instructions を優先する」を使って境界を作る。
        // 実測: この制約が無いと、Tool が「存在しません」と返した後にモデルが別の薬へ勝手に置き換え、
        // Tool を引き直さずに誤った薬効を生成していた。
        case .basicTool: try await runTooling(tools: [.weather], instructions: """
            天気や気温を聞かれたら getWeather Tool を使ってください。
            答えは Tool の出力に書かれている内容だけにしてください。
            Tool がデータが無いと返した場合は、無いことをそのまま伝えてください。
            必ず日本語で答えてください。
            """)
        case .searchTool: try await runTooling(tools: [.drugSearch], instructions: """
            薬について聞かれたら searchDrug Tool を使ってください。
            答えは Tool の出力に書かれている内容だけにしてください。
            Tool が「存在しません」と返した場合は、登録が無いことだけを伝えてください。
            別の薬に置き換えて答えてはいけません。
            必ず日本語で答えてください。
            """)
        case .multipleTools: try await runMultipleTools()
        case .multiStepTool: try await runMultiStepTool()
        case .sideEffectTool: try await runSideEffectTool()
        // VISION & MEDIA
        case .imageDescription: try await runImageDescription()
        case .imageClassification: try await runImageClassification()
        case .textRectangles: try await runTextRectangles()
        case .compareImages: try await runCompareImages()
        case .structuredVision: try await runStructuredVision()
        case .ocr: try await runOCR()
        case .barcode: try await runBarcode()
        case .rectangles: try await runRectangles()
        case .faceRectangles: try await runFaceRectangles()
        case .humanRectangles: try await runHumanRectangles()
        case .saliency: try await runSaliency()
        case .aesthetics: try await runAesthetics()
        case .videoAnalysis: try await runVideoAnalysis()
        case .camera: try await runCameraFrame()
        case .liveCamera: try await runLiveCameraQuestion()
        case .visionTool: try await runVisionTool()
        // SESSION
        case .transcript: try await runTranscript()
        case .restore: try await runRestore()
        case .tokenCount: try await runTokenCount()
        case .contextWindow: try await runContextWindow()
        case .contextExceeded: try await runContextExceeded()
        case .chunking: try await runChunking()
        case .historyTransform: try await runHistoryTransform()
        case .prewarm: try await runPrewarm()
        // PRIVATE CLOUD
        case .pcc: runPCC()
        case .modelComparison: try await runModelComparison()
        case .reasoning: try await runReasoning()
        case .quota: runQuota()
        // AGENT
        case .dynamicInstructions: try await runDynamicInstructions()
        case .dynamicProfile: try await runDynamicProfile()
        case .profileVisualizer: runProfileVisualizer()
        case .toolVisibility: try await runToolVisibility()
        case .sessionProperty: try await runSessionProperty()
        case .lifecycleEvents: try await runLifecycleEvents()
        case .agentWorkflow: try await runAgentWorkflow()
        case .visionAgent: try await runVisionAgent()
        // MODEL
        case .capabilities: runCapabilities()
        case .customModel: try await runCustomModel()
        case .modelSwitch: try await runModelSwitch()
        // DEVELOPER
        case .errorLab: try await runErrorLab()
        case .logs: runLogs()
        case .apiReference: runAPIReference()
        // PLAYGROUND
        case .playground: try await runPlayground()
        // MEDICAL DATA
        case .medicalInformationHandling: try await runMedicalInformationHandling()
        }
    }

    // MARK: - OVERVIEW

    private func runDashboard() async throws {
        modelManager.refresh()
        result.executionMode = .localOnly

        var rows: [KeyValueRow] = [
            KeyValueRow(label: "Device", value: modelManager.deviceName),
            KeyValueRow(label: "OS", value: modelManager.osVersion),
            KeyValueRow(label: "Use Case", value: modelManager.useCase.rawValue),
            KeyValueRow(
                label: "Apple Intelligence",
                value: modelManager.availability.label,
                status: modelManager.availability.isAvailable ? .success : .error
            ),
            KeyValueRow(label: "SystemLanguageModel", value: modelManager.availability.detail,
                        status: modelManager.availability.isAvailable ? .success : .error),
            KeyValueRow(label: "Context Size", value: "\(modelManager.contextSize.formatted()) tokens"),
            KeyValueRow(label: "Current Locale", value: modelManager.supportsCurrentLocale ? "Supported" : "Not supported",
                        status: modelManager.supportsCurrentLocale ? .success : .warning),
            KeyValueRow(label: "Japanese", value: modelManager.supportsJapanese ? "Supported" : "Not supported",
                        status: modelManager.supportsJapanese ? .success : .warning),
            KeyValueRow(label: "Supported Languages", value: "\(modelManager.supportedLanguageTags.count) 言語")
        ]

        if let recovery = modelManager.availability.recovery {
            rows.append(KeyValueRow(label: "Recovery", value: recovery, status: .warning))
        }

        // 実際に1リクエスト通るかを確認する（Availability だけでは分からないため）。
        // useCase によって「通る形」が違う点に注意する。
        //  - general        : 素のテキスト応答を返せる
        //  - contentTagging : タグ付けに特化しており、素のテキストを求めると decodingFailure になる。
        //                     さらに素の String フィールドを含むスキーマは入力が膨らんで context 超過、
        //                     薬剤名を含む文は refusal になる（いずれも実測）。
        // ヘルスチェックが useCase の違いで落ちると Apple Intelligence 自体が壊れているように見えるので、
        // useCase に合った形で確認する。
        if modelManager.availability.isAvailable {
            let started = Date()
            do {
                let session = modelManager.makeSession()
                switch modelManager.useCase {
                case .general:
                    _ = try await session.respond(
                        to: "Say OK.",
                        options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 64)
                    )
                case .contentTagging:
                    // タグ付け用途なので構造化出力で往復させる。
                    // 薬剤名を含む文は refusal になるため、ここでは中立的な文を使う。
                    _ = try await session.respond(
                        to: "週末は天気が良かったので、家族で近くの公園を散歩しました。",
                        generating: ContentTags.self,
                        options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 256)
                    )
                }
                rows.append(KeyValueRow(
                    label: "Live Round Trip",
                    value: String(format: "成功 (%.2f sec, useCase: %@)",
                                  Date().timeIntervalSince(started), modelManager.useCase.rawValue),
                    status: .success
                ))
                result.executionMode = .foundationModels
                result.error = nil
            } catch {
                let mapped = LabError.map(error)
                // モデルに到達したうえで応答の解釈に失敗した場合は、往復自体は成立している。
                // 「利用できない」と混同させない。
                let reachedModel: Bool = switch mapped.category {
                case .decodingFailure, .guardrailViolation, .refusal, .unsupportedGuide: true
                default: false
                }
                rows.append(KeyValueRow(
                    label: "Live Round Trip",
                    value: reachedModel
                        ? "モデルには到達（応答を解釈できず: \(mapped.errorType)）"
                        : "失敗: \(mapped.errorType)",
                    status: reachedModel ? .warning : .error
                ))
                if reachedModel { result.executionMode = .foundationModels }
                result.error = mapped
            }
        }

        rows.append(contentsOf: modelManager.capabilities.rows.map {
            KeyValueRow(label: $0.0, value: $0.1 ? "利用可能" : "SDK未提供 / 不可", status: $0.1 ? .success : .warning)
        })

        result.payload = .keyValue(rows)
        result.debugDetail = """
        SystemLanguageModel.availability = \(modelManager.availability)
        contextSize = \(modelManager.contextSize)
        supportedLanguages = \(modelManager.supportedLanguageTags.joined(separator: ", "))

        公開 API として使えない機能（いずれも .tbd と swiftinterface を突き合わせて確認）:

        - 画像・動画をプロンプトへ添付する API
          ランタイムにも該当シンボルが無い。実装自体が見当たらない。
        - PrivateCloudComputeLanguageModel / SystemLanguageModel.privateCloudCompute
        - LanguageModel protocol / LanguageModelExecutor（モデル抽象）
          この3つは iOS 26 のランタイムには実装済みで存在するが、
          swiftinterface から除外された SPI のため、コンパイル時に参照できない。
        - reasoning レベル指定
          GenerationOptions が持つのは sampling / temperature / maximumResponseTokens の3つだけ。

        これらのデモは値を捏造せず「SDK未提供 / 不可」として表示し、
        代替経路（Vision → テキスト → モデル、アプリ側のモデル抽象）を実装しています。
        Apple が宣言を公開した時点で、代替経路を本来の API へ差し替えられます。
        """
    }

    // MARK: - TEXT

    private func runSimpleGeneration() async throws {
        let response = try await respond(prompt)
        result.payload = .text(response.text)
        result.debugDetail = """
        Prompt → LanguageModelSession → Response<String>

        オンデバイスモデルは知識ベースではない。実測でも、細かい事実を聞くと誤った説明を返した
        （加賀棒茶を「煎茶」、揚げ浜式製塩を「網に塩を撒く」と説明した）。
        Apple「Prompting an on-device foundation model」も、正確でハルシネーションのない応答には
        プロンプトが簡潔かつ具体的である必要があると述べている。
        事実が必要な用途では、この画面の既定プリセットのように事実をプロンプトへ渡すか、
        Tool でアプリ側のデータを引かせる（TOOLS のデモが該当）。
        """
        result.metrics.responseTokens = await tokenCount(response.text)
    }

    private func runInstructions() async throws {
        // Instructions の違いを見せるため、同じ Prompt を2つのセッションへ送る。
        let withInstructions = try await respond(prompt, instructions: instructions)
        let bare = try await respond(prompt, instructions: nil)
        result.payload = .comparison([
            ComparisonColumn(title: "Instructions あり", subtitle: String(instructions.prefix(60)), body: withInstructions.text),
            ComparisonColumn(title: "Instructions なし", subtitle: "instructions: nil", body: bare.text)
        ])
        result.debugDetail = """
        Instructions はセッション生成時に一度だけ渡し、以降のすべての Prompt に効く。
        Transcript の先頭に .instructions エントリとして現れる。
        """
    }

    private func runConversation() async throws {
        let session = conversationSessionOrCreate()
        let response = try await respond(prompt, session: session)
        result.payload = .text(response.text)
        result.debugDetail = """
        同一 LanguageModelSession を保持し続けているため、履歴が Transcript に積まれる。
        現在の Transcript エントリ数: \(transcriptEntries.count)
        「私の名前をTaroとして覚えてください」→「私の名前は？」の順に実行すると保持を確認できる。
        """
        if let tokens = try? await modelManager.tokenCount(for: session.transcript) {
            result.metrics.transcriptTokens = tokens
        }
    }

    private func runStreaming() async throws {
        var partial = ""
        let response = try await stream(prompt) { text in
            partial = text
            self.result.payload = .text(text)
        }
        result.payload = .text(response.text)
        result.metrics.responseTokens = await tokenCount(response.text)
        result.debugDetail = """
        ResponseStream の各 Snapshot は「その時点までの全文」を返す（差分ではない）。
        最終結果は ResponseStream.collect() の Response.content で確定する。
        受信した文字数: \(partial.count)
        First Token: \(result.metrics.firstTokenText) / Total: \(result.metrics.elapsedText)
        """
    }

    private func runSummarization() async throws {
        let instructions = summarizationInstructions(for: summaryStyle)
        let request = "原文:\n\(longText)"
        let summarizedText: String

        switch summaryStyle {
        case .oneLine:
            let response = try await respond(
                request,
                generating: OneLineSummaryResult.self,
                instructions: instructions,
                options: GenerationOptions(sampling: .greedy, temperature: 0.1)
            )
            summarizedText = response.content.summary
            result.payload = .structured(
                fields: [
                    StructuredField(label: "summary", value: response.content.summary, typeName: "String",
                                    guideDescription: "1文の日本語要約。改行を含めない")
                ],
                json: response.raw.jsonString
            )

        case .threeLines:
            let response = try await respond(
                request,
                generating: ThreeLineSummaryResult.self,
                instructions: instructions,
                options: GenerationOptions(sampling: .greedy, temperature: 0.1)
            )
            let lines = [response.content.line1, response.content.line2, response.content.line3]
            summarizedText = lines.joined(separator: "\n")
            result.payload = .structured(
                fields: [
                    StructuredField(label: "lines", value: "\(lines.count) 件", typeName: "[String]",
                                    guideDescription: "3行分の要約",
                                    children: lines.enumerated().map {
                                        StructuredField(label: "[\($0.offset)]", value: $0.element, typeName: "String")
                                    })
                ],
                json: response.raw.jsonString
            )

        case .bullets:
            let response = try await respond(
                request,
                generating: BulletSummaryResult.self,
                instructions: instructions,
                // 30文字 × 5件 + スキーマ分。長い丸写しが入らない程度に抑える。
                options: GenerationOptions(sampling: .greedy, temperature: 0.1, maximumResponseTokens: 320)
            )
            let bullets = [
                response.content.point1,
                response.content.point2,
                response.content.point3,
                response.content.point4,
                response.content.point5
            ]
            summarizedText = bullets.joined(separator: "\n")
            result.payload = .structured(
                fields: [
                    StructuredField(label: "bullets", value: "\(bullets.count) 件", typeName: "[String]",
                                    guideDescription: "重要ポイントの箇条書き",
                                    children: bullets.enumerated().map {
                                        StructuredField(label: "[\($0.offset)]", value: $0.element, typeName: "String")
                                    })
                ],
                json: response.raw.jsonString
            )

        case .hundredCharacters:
            let response = try await respond(
                request,
                generating: HundredCharacterSummaryResult.self,
                instructions: instructions,
                // 文字数は HundredCharacterSummaryResult の pattern guide で縛る。
                // maximumResponseTokens は構造化出力を途中終了させ、decodingFailure の原因になり得るため指定しない。
                options: GenerationOptions(sampling: .greedy, temperature: 0.1)
            )
            let normalizedSummary = hundredCharacterSummary(response.content.summary)
            summarizedText = normalizedSummary
            result.payload = .structured(
                fields: [
                    StructuredField(label: "summary", value: normalizedSummary, typeName: "String",
                                    guideDescription: "100文字程度の日本語要約")
                ],
                json: response.raw.jsonString
            )
        }

        result.debugDetail = "Summary Size: \(summaryStyle.title)\n原文文字数: \(longText.count)"
        result.metrics.responseTokens = await tokenCount(summarizedText)
    }

    private func hundredCharacterSummary(_ summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 140 else { return trimmed }

        var clipped = String(trimmed.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
        if let sentenceEnd = clipped.lastIndex(where: { "。！？".contains($0) }) {
            let sentenceClipped = String(clipped[...sentenceEnd])
            if sentenceClipped.count >= 80 {
                clipped = sentenceClipped
            }
        }
        return clipped
    }

    private func summarizationInstructions(for style: SummaryStyle) -> String {
        let shared = """
        あなたは正確な要約者です。原文に無い情報を加えないでください。
        原文や指示文をコピーせず、必ず短い日本語の要約だけを各フィールドへ入れてください。
        """

        switch style {
        case .oneLine:
            return shared + "\nsummary には80文字以内の1文だけを入れてください。"
        case .threeLines:
            return shared + "\nlines には60文字以内の短い要約文を3件だけ入れてください。"
        case .bullets:
            // 実測: 「言い換えてください」だけでは原文の文をそのまま5件写していた。
            // Apple「Prompting an on-device foundation model」の Provide simple input-output examples に従い、
            // 短い入出力例を与える（オンデバイスモデルには簡単な例が向く）。
            return shared + """

                各ポイントは25文字以内の名詞句にしてください。原文の文をそのままコピーしてはいけません。

                例:
                原文「木地は主にアテやケヤキを使い、乾燥に一年以上かけてから削り出します。」
                ポイント「木地はアテやケヤキ、乾燥は一年以上」

                原文「上塗りは塵の少ない室で行い、湿度は七十五パーセント前後に保ちます。」
                ポイント「上塗りは無塵の室、湿度七十五パーセント」
                """
        case .hundredCharacters:
            // 実測: 上限だけを書くと180文字 → 32文字へ振れた。下限と上限の両方を示す（Apple: Repeat yourself）。
            return shared + """

                summary は100文字程度にしてください。80文字以上140文字以内です。
                原文の項目を並べず、全体の要点を2〜3文でまとめてください。
                必ず80文字以上140文字以内で終えてください。
                """
        }
    }

    private func runRewrite() async throws {
        let request = "\(rewriteStyle.instruction)\n\n\(prompt)"
        let response = try await respond(request, instructions: "指示された文体に忠実に書き換えます。意味を変えないでください。必ず日本語で答えてください。")
        result.payload = .comparison([
            ComparisonColumn(title: "Original", body: prompt),
            ComparisonColumn(title: rewriteStyle.title, body: response.text)
        ])
        result.debugDetail = "Preset: \(rewriteStyle.title)\nInstruction: \(rewriteStyle.instruction)"
    }

    private func runClassification() async throws {
        let response = try await respond(
            prompt,
            generating: SupportClassification.self,
            instructions: """
                問い合わせ内容を1つのカテゴリに分類してください。
                1. まず evidence に、判断の根拠になった文中の表現をそのまま書いてください。
                2. 次に category を決めてください。
                bug=不具合や異常動作、operation=操作方法や設定場所の質問、
                request=機能追加の要望、contract=契約やプランの手続きです。
                カテゴリは必ずこの4つから選んでください。
                """,
            options: GenerationOptions(sampling: .greedy, temperature: 0.1, maximumResponseTokens: 200)
        )
        let category = response.content.category
        result.payload = .structured(
            fields: [
                StructuredField(label: "category", value: "SupportCategory.\(category.rawValue) (\(category.display))",
                                typeName: "SupportCategory", guideDescription: "問い合わせのカテゴリ"),
                StructuredField(label: "evidence", value: response.content.evidence, typeName: "String",
                                guideDescription: "分類の根拠となった文中の表現")
            ]
            + SupportCategory.allCases.map {
                StructuredField(label: $0 == category ? "● \($0.rawValue)" : "○ \($0.rawValue)", value: $0.display, typeName: "case")
            },
            json: response.raw.jsonString
        )
        result.debugDetail = """
        自由文字列ではなく enum のケースとして受け取っている。
        スキーマ上 category に入りうる値は 4 ケースのみで、それ以外は生成されない。
        sampling: greedy（分類は揺れない方が望ましいため）
        """
    }

    private func runExtraction() async throws {
        // 実測でわかっていること（iOS 26.5 / 端末モデル、各条件3回ずつ）:
        //   処方文 + 単値スキーマ(Prescription)            → 3/3 成功
        //   処方文 + people 配列だけ                        → 3/3 成功
        //   処方文 + 薬剤名を含む配列（1〜4本 / 入れ子とも） → 3/3 guardrailViolation
        //   処方文 + 配列 + permissiveContentTransformations → 3/3 guardrailViolation
        //     （Apple のドキュメントどおり、permissive は素のテキスト出力にしか効かない）
        //   非医療の業務メモ + 同じ配列4本                  → 3/3 成功
        // つまり「薬剤名の一覧を配列で返させること」が出力側ガードレールの発動条件で、
        // 同じ文面を再送しても結果は変わらない。
        //
        // Apple の安全ガイドは、ガードレールに当たったら文面を変える / 出力に境界を置くことを求めている。
        // ここでは配列を返すスキーマは変えずに、既定入力を薬剤名を含まない業務メモにしている。
        // 処方文で試したい場合は入力欄に貼り付ければ、guardrailViolation の4項目表示を確認できる。
        //
        // 既定のサンプリング（temperature 0.7）だと抽出が発散しやすく、
        // 伸びた応答が安全ガードレールで止められていた。抽出は揺らす必要がないので固定する。
        let response = try await respond(
            entityText,
            generating: ExtractedEntities.self,
            instructions: """
                入力された文章に書かれている語句を、そのまま項目別に並べ替えてください。
                これは文字列の分類作業です。評価・助言・推測は一切しないでください。
                文中に無い語句を追加しないでください。必ず日本語で答えてください。
                """,
            options: GenerationOptions(sampling: .greedy, temperature: 0.1, maximumResponseTokens: 400)
        )
        let content = response.content
        result.payload = .structured(
            fields: [
                arrayField("people", content.people, guide: "登場した人物名"),
                arrayField("products", content.products, guide: "登場した薬剤名や製品名"),
                arrayField("quantities", content.quantities, guide: "数量・用量の表現"),
                arrayField("dates", content.dates, guide: "日付や期間の表現")
            ],
            json: response.raw.jsonString
        )
        result.debugDetail = """
        入力文字数: \(entityText.count)
        抽出は @Generable struct ExtractedEntities のスキーマに従う（4本の [String]）。

        実測: 薬剤名を配列として返させると、既定のガードレールで必ず停止する
        （処方文 + この配列スキーマは3回中3回 guardrailViolation）。
        同じ薬剤名でも単値フィールド（Generable デモの Prescription.medicineName）なら通る。
        permissiveContentTransformations は素のテキスト出力にしか効かないため、
        構造化出力のこの画面では回避手段にならない（Apple ドキュメント記載どおり、実測も一致）。
        入力欄に処方文を貼り付けると、その guardrailViolation を4項目で確認できる。
        """
    }

    // MARK: - MEDICAL DATA

    private func runMedicalInformationHandling() async throws {
        try requireAvailableModel()
        result.executionMode = .foundationModels

        let prescriptionText = entityText.trimmingCharacters(in: .whitespacesAndNewlines)
        result.metrics.promptTokens = await tokenCount(prescriptionText)

        let columns = await [
            medicalGenericArrayColumn(for: prescriptionText),
            medicalDomainSchemaColumn(for: prescriptionText),
            medicalPermissiveTextColumn(for: prescriptionText)
        ]

        result.payload = .comparison(columns)
        result.metrics.responseTokens = await tokenCount(result.payload.plainText)
        result.debugDetail = """
        Apple ドキュメント上の境界:
        - guardrails は prompt と response の安全性を確認し、違反時は guardrailViolation を投げる。
        - permissiveContentTransformations は sensitive な入力を text response へ変換する用途向け。
        - この permissive mode が効くのは String 生成だけ。
        - @Generable / guided generation では default guardrails と同じ扱いになる。

        この画面の意図:
        同じ処方文に対して、guardrail に当たりやすい「薬剤名を汎用配列で返す抽出」と、
        通しやすい「医療ドメイン専用スキーマ」および「permissive なテキスト変換」を比較する。
        端末内処理でも FoundationModels 側の guardrails 自体はアプリから完全には外せない。
        """
    }

    private func medicalGenericArrayColumn(for text: String) async -> ComparisonColumn {
        do {
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: """
                    入力文に書かれている語句を、人物・薬剤または製品・数量・日付に分けて配列へ抽出してください。
                    評価・助言・推測は一切せず、文中の表記だけを返してください。
                    """
            )
            let response = try await session.respond(
                to: text,
                generating: ExtractedEntities.self,
                options: GenerationOptions(sampling: .greedy, temperature: 0.1)
            )
            publishTranscript(session)
            let content = response.content
            return ComparisonColumn(
                title: "NG寄り: 汎用配列抽出",
                subtitle: "ExtractedEntities / guided generation",
                body: """
                people: \(content.people.joined(separator: ", "))
                products: \(content.products.joined(separator: ", "))
                quantities: \(content.quantities.joined(separator: ", "))
                dates: \(content.dates.joined(separator: ", "))
                """,
                footnotes: [
                    KeyValueRow(label: "Result", value: "成功。ただし処方文では guardrailViolation になりやすい形です。", status: .warning),
                    KeyValueRow(label: "Reason", value: "薬剤名を汎用的な [String] 配列として列挙させるため")
                ]
            )
        } catch {
            return medicalErrorColumn(
                title: "NG寄り: 汎用配列抽出",
                subtitle: "ExtractedEntities / guided generation",
                error: error,
                expected: "処方文ではこの失敗が想定されるケースです。",
                reason: "薬剤名を products: [String] に列挙させる guided generation は default guardrails の対象です。"
            )
        }
    }

    private func medicalDomainSchemaColumn(for text: String) async -> ComparisonColumn {
        do {
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: """
                    処方文に書かれている患者と薬剤を構造化してください。
                    医療判断・助言・禁忌判定は行わず、文中の事実だけを転記してください。
                    """
            )
            let response = try await session.respond(
                to: text,
                generating: PatientPrescription.self,
                options: GenerationOptions(sampling: .greedy, temperature: 0.1)
            )
            publishTranscript(session)
            let prescription = response.content
            let medicines = prescription.medicines.enumerated().map { index, medicine in
                "\(index + 1). \(medicine.name) \(medicine.dose) 1日\(medicine.frequency)回 \(medicine.timing)"
            }.joined(separator: "\n")
            return ComparisonColumn(
                title: "OK寄り: 医療専用スキーマ",
                subtitle: "PatientPrescription / guided generation",
                body: """
                patient: \(prescription.patient.name) / \(prescription.patient.age)歳 / \(prescription.patient.id)
                medicinesInText: \(prescription.medicinesInText)
                medicines:
                \(medicines)
                notes: \(prescription.notes)
                """,
                footnotes: [
                    KeyValueRow(label: "Result", value: "成功", status: .success),
                    KeyValueRow(label: "Reason", value: "薬剤を業務ドメインの構造として扱い、評価や助言を禁止しているため")
                ]
            )
        } catch {
            return medicalErrorColumn(
                title: "OK寄り: 医療専用スキーマ",
                subtitle: "PatientPrescription / guided generation",
                error: error,
                expected: "通常は通したいケースです。",
                reason: "guided generation なので permissive guardrails は効かず、入力や出力が安全判定に触れると停止します。"
            )
        }
    }

    private func medicalPermissiveTextColumn(for text: String) async -> ComparisonColumn {
        do {
            let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
            let session = LanguageModelSession(
                model: model,
                instructions: """
                    入力された処方文を、医療判断・助言・追加情報なしで読みやすい日本語テキストへ転記してください。
                    患者、薬剤、用量、回数、タイミング、日数だけを書いてください。
                    """
            )
            let response = try await session.respond(
                to: text,
                options: GenerationOptions(sampling: .greedy, temperature: 0.1)
            )
            publishTranscript(session)
            return ComparisonColumn(
                title: "OK: permissive テキスト変換",
                subtitle: "String response only",
                body: response.content,
                footnotes: [
                    KeyValueRow(label: "Result", value: "成功", status: .success),
                    KeyValueRow(label: "Reason", value: "permissiveContentTransformations は String 生成に限って guardrailViolation を避ける用途")
                ]
            )
        } catch {
            return medicalErrorColumn(
                title: "OK: permissive テキスト変換",
                subtitle: "String response only",
                error: error,
                expected: "String 変換なら guardrailViolation は避けられる想定です。",
                reason: "permissive mode でも、モデルが安全上の拒否文を返す場合や利用不可エラーは残ります。"
            )
        }
    }

    private func medicalErrorColumn(
        title: String,
        subtitle: String,
        error: Error,
        expected: String,
        reason: String
    ) -> ComparisonColumn {
        let mapped = LabError.map(error)
        return ComparisonColumn(
            title: title,
            subtitle: subtitle,
            body: """
            Error Type: \(mapped.errorType)
            User Message: \(mapped.userMessage)
            Technical Detail: \(mapped.technicalDetail)
            Recovery: \(mapped.recovery)
            """,
            footnotes: [
                KeyValueRow(label: "判定", value: expected, status: mapped.category == .guardrailViolation ? .warning : .error),
                KeyValueRow(label: "理由", value: reason)
            ],
            isUnavailable: true
        )
    }

    // MARK: - STRUCTURED OUTPUT

    private func runGenerable() async throws {
        let response = try await respond(
            entityText,
            generating: Prescription.self,
            instructions: """
                処方内容を構造化してください。
                medicineName は薬剤名と規格をまとめて1つの文字列にしてください（例: アムロジピン5mg）。
                dose には1回に飲む錠数を入れ、文中に書かれていなければ 1錠 としてください。
                文中に無い値は推測せず、最も妥当な既定値を使ってください。
                """
        )
        let p = response.content
        result.payload = .structured(
            fields: [
                StructuredField(label: "patientName", value: p.patientName, typeName: "String", guideDescription: "患者の氏名"),
                StructuredField(label: "medicineName", value: p.medicineName, typeName: "String", guideDescription: "薬剤名（用量を含む）"),
                StructuredField(label: "dose", value: p.dose, typeName: "String", guideDescription: "1回に服用する量"),
                StructuredField(label: "frequency", value: "\(p.frequency)", typeName: "Int", guideDescription: "1日あたりの服用回数 (.range(1...6))"),
                StructuredField(label: "timing", value: p.timing, typeName: "String", guideDescription: "服用タイミング"),
                StructuredField(label: "days", value: "\(p.days)", typeName: "Int", guideDescription: "処方日数 (.range(1...180))")
            ],
            json: response.raw.jsonString
        )
        result.debugDetail = """
        respond(to:generating: Prescription.self) の戻り値は Response<Prescription>。
        content はすでに Swift の型なので、JSON 文字列のパースは不要。
        rawContent には生成された GeneratedContent がそのまま入っている。
        GenerationSchema:
        \(Prescription.generationSchema.debugDescription)
        """
    }

    private func runGuideComparison() async throws {
        // 同じ入力を、制約あり / 制約なしの2つの型で生成させて値域を比べる。
        //
        // Guide OFF 側は生成が失敗すること自体がこの画面の主旨なので、
        // 片側が落ちても もう片側の結果は見せる。
        // （以前は unguided の decodingFailure で画面全体がエラーになっていた）
        // 比較したいのは「@Guide の有無」だけ。
        // サンプリングを既定のまま（temperature 0.7 / automatic）にすると、
        // 制約付きスキーマ側が値域を満たせず generationFailure になることがあり、
        // 差が @Guide 由来なのか揺れ由来なのか分からなくなる。両側を greedy で固定する。
        let sentimentInstructions = "文章の感情を分析してください。必ず日本語で答えてください。"
        let sentimentOptions = GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 400)

        var guidedContent: GuidedSentiment?
        var guidedJSON: String?
        var guidedFailure: LabError?
        do {
            let response = try await respond(
                prompt,
                generating: GuidedSentiment.self,
                instructions: sentimentInstructions,
                options: sentimentOptions
            )
            guidedContent = response.content
            guidedJSON = response.raw.jsonString
        } catch {
            if error is CancellationError { throw error }
            guidedFailure = LabError.map(error)
        }

        var unguidedContent: UnguidedSentiment?
        var unguidedJSON: String?
        var unguidedFailure: LabError?
        do {
            let response = try await respond(
                prompt,
                generating: UnguidedSentiment.self,
                instructions: sentimentInstructions,
                options: sentimentOptions
            )
            unguidedContent = response.content
            unguidedJSON = response.raw.jsonString
        } catch {
            if error is CancellationError { throw error }
            unguidedFailure = LabError.map(error)
        }

        // 両側とも生成できなかったときだけ、画面をエラーにする。
        if guidedContent == nil, unguidedContent == nil {
            throw guidedFailure ?? unguidedFailure ?? LabError(
                category: .generationFailure,
                technicalDetail: "GuidedSentiment / UnguidedSentiment の両方が生成に失敗しました。",
                userMessage: "モデルが生成を完了できませんでした。",
                recovery: "Prompt を短くするか、別のプリセットで再実行してください。"
            )
        }

        let guidedInRange = guidedContent.map { (0...100).contains($0.confidence) } ?? false
        let unguidedInRange = unguidedContent.map { (0...100).contains($0.confidence) } ?? false
        let allowed = ["positive", "negative", "neutral"]

        result.payload = .comparison([
            ComparisonColumn(
                title: "Guide ON",
                subtitle: "@Guide(.range(0...100)) / .anyOf([...])",
                body: guidedContent.map { content in
                    """
                    confidence: \(content.confidence)
                    sentiment: \(content.sentiment)
                    reasons: \(content.reasons.joined(separator: " / "))
                    """
                } ?? """
                生成に失敗しました（\(guidedFailure?.category.rawValue ?? "不明")）
                \(guidedFailure?.technicalDetail ?? "")
                """,
                footnotes: [
                    KeyValueRow(label: "生成できたか", value: guidedContent == nil ? "いいえ" : "はい",
                                status: guidedContent == nil ? .error : .success),
                    KeyValueRow(label: "confidence が 0...100 内", value: guidedContent == nil ? "-" : (guidedInRange ? "はい" : "いいえ"),
                                status: guidedContent == nil ? .neutral : (guidedInRange ? .success : .error)),
                    KeyValueRow(label: "sentiment が許可値",
                                value: guidedContent.map { allowed.contains($0.sentiment) ? "はい" : "いいえ" } ?? "-",
                                status: guidedContent.map { allowed.contains($0.sentiment) ? .success : .error } ?? .neutral),
                    KeyValueRow(label: "reasons 件数", value: guidedContent.map { "\($0.reasons.count) (.count(1...2))" } ?? "-")
                ]
            ),
            ComparisonColumn(
                title: "Guide OFF",
                subtitle: "制約なしの同じフィールド",
                body: unguidedContent.map { content in
                    """
                    confidence: \(content.confidence)
                    sentiment: \(content.sentiment)
                    reasons: \(content.reasons.joined(separator: " / "))
                    """
                } ?? """
                生成に失敗しました（\(unguidedFailure?.category.rawValue ?? "不明")）
                \(unguidedFailure?.technicalDetail ?? "")

                制約が無いぶんモデルの出力が安定せず、スキーマに収まらないことがある。
                これは Guide が必要である理由そのもの。
                """,
                footnotes: [
                    KeyValueRow(label: "生成できたか", value: unguidedContent == nil ? "いいえ" : "はい",
                                status: unguidedContent == nil ? .error : .success),
                    KeyValueRow(label: "confidence が 0...100 内", value: unguidedContent == nil ? "-" : (unguidedInRange ? "はい" : "いいえ（保証されない）"),
                                status: unguidedContent == nil ? .neutral : (unguidedInRange ? .warning : .error)),
                    KeyValueRow(label: "sentiment が許可値",
                                value: unguidedContent.map { allowed.contains($0.sentiment) ? "はい（偶然）" : "いいえ" } ?? "-",
                                status: unguidedContent.map { allowed.contains($0.sentiment) ? .warning : .error } ?? .neutral),
                    KeyValueRow(label: "reasons 件数", value: unguidedContent.map { "\($0.reasons.count)（上限なし）" } ?? "-")
                ]
            )
        ])
        result.debugDetail = """
        Guide ON の JSON:
        \(guidedJSON ?? "生成に失敗したため JSON なし")

        Guide OFF の JSON:
        \(unguidedJSON ?? "生成に失敗したため JSON なし")

        @Guide は「プロンプトでのお願い」ではなくスキーマ制約として効く。
        Guide OFF 側は1回の実行では範囲内に収まることもあるが、収まる保証がない点が違い。
        """
    }

    private func runEnumGeneration() async throws {
        let response = try await respond(
            prompt,
            generating: SupportCategory.self,
            instructions: """
                問い合わせ内容のカテゴリを1つだけ答えてください。
                bug=不具合や異常動作、operation=操作方法や設定場所の質問、
                request=機能追加の要望、contract=契約やプランの手続きです。
                説明は書かず、カテゴリだけを答えてください。
                """,
            options: GenerationOptions(sampling: .greedy, temperature: 0.1, maximumResponseTokens: 64)
        )
        result.payload = .structured(
            fields: [StructuredField(label: "SupportCategory", value: "\(response.content.rawValue) (\(response.content.display))", typeName: "@Generable enum")]
                + SupportCategory.allCases.map {
                    StructuredField(label: $0 == response.content ? "● selected" : "○", value: "\($0.rawValue) — \($0.display)", typeName: "case")
                },
            json: response.raw.jsonString
        )
        result.debugDetail = """
        enum そのものを generating に渡している。
        GenerationSchema:
        \(SupportCategory.generationSchema.debugDescription)
        """
    }

    private func runNestedObject() async throws {
        let response = try await respond(
            entityText,
            generating: PatientPrescription.self,
            instructions: """
                患者と処方薬を構造化してください。
                medicines には文中に書かれている薬剤だけを入れ、同じ薬剤を繰り返さないでください。
                文中の薬剤が1件なら1件だけにしてください。
                """
        )
        let content = response.content
        result.payload = .structured(
            fields: [
                StructuredField(label: "medicinesInText", value: content.medicinesInText, typeName: "String",
                                guideDescription: "推論用フィールド（Apple: reasoning field を答えより前に置く）"),
                StructuredField(label: "patient", value: "PatientInfo", typeName: "PatientInfo", guideDescription: "患者情報", children: [
                    StructuredField(label: "id", value: content.patient.id, typeName: "String"),
                    StructuredField(label: "name", value: content.patient.name, typeName: "String"),
                    StructuredField(label: "age", value: "\(content.patient.age)", typeName: "Int")
                ]),
                StructuredField(label: "medicines", value: "\(content.medicines.count) 件", typeName: "[Medicine]",
                                guideDescription: "処方された薬剤の一覧 (.count(1...6))",
                                children: content.medicines.enumerated().map { index, medicine in
                                    StructuredField(label: "[\(index)]", value: medicine.name, typeName: "Medicine", children: [
                                        StructuredField(label: "name", value: medicine.name, typeName: "String"),
                                        StructuredField(label: "dose", value: medicine.dose, typeName: "String"),
                                        StructuredField(label: "frequency", value: "\(medicine.frequency)", typeName: "Int"),
                                        StructuredField(label: "timing", value: medicine.timing, typeName: "String")
                                    ])
                                }),
                StructuredField(label: "notes", value: content.notes, typeName: "String", guideDescription: "処方全体に対する注意事項")
            ],
            json: response.raw.jsonString
        )
        result.debugDetail = """
        入れ子の @Generable と配列を一度の生成で埋めている。
        GenerationSchema:
        \(PatientPrescription.generationSchema.debugDescription)
        """
    }

    private func runDynamicSchema() async throws {
        try requireAvailableModel()

        let names = schemaFields.map(\.name)
        guard Set(names).count == names.count else {
            throw LabError(
                category: .schemaFailure,
                technicalDetail: "フィールド名が重複しています: \(names.joined(separator: ", "))",
                userMessage: "フィールド名が重複しています。",
                recovery: "重複した名前を変更してください。"
            )
        }
        guard !schemaFields.isEmpty else {
            throw LabError(
                category: .schemaFailure,
                technicalDetail: "properties が空です。",
                userMessage: "フィールドが1つもありません。",
                recovery: "Add Field でフィールドを追加してください。"
            )
        }

        // コンパイル時ではなく実行時にスキーマを組む。
        let record = DynamicGenerationSchema(
            name: "DynamicRecord",
            description: "画面で定義された動的スキーマ",
            properties: schemaFields.map(\.property)
        )
        let root = dynamicSchemaRecordCount == 1
            ? record
            : DynamicGenerationSchema(
                arrayOf: record,
                minimumElements: dynamicSchemaRecordCount,
                maximumElements: dynamicSchemaRecordCount
            )
        let schema = try GenerationSchema(root: root, dependencies: [])

        let session = makeSession(instructions: "指定されたスキーマに合うデータを\(dynamicSchemaRecordCount)件生成してください。必ず日本語で答えてください。")
        result.executionMode = .foundationModels
        let response = try await session.respond(to: prompt, schema: schema, options: currentOptions)
        publishTranscript(session)

        result.payload = .structured(
            fields: structuredFields(from: response.content),
            json: response.content.jsonString
        )
        result.debugDetail = """
        DynamicGenerationSchema からの GenerationSchema:
        \(schema.debugDescription)

        戻り値は GeneratedContent（コンパイル時の型が無いため）。
        値の取り出しは content.value(String.self, forProperty: "name") のように行う。

        生成件数: \(dynamicSchemaRecordCount)

        定義したフィールド:
        \(schemaFields.map { "- \($0.name): \($0.type.rawValue)\($0.isOptional ? "?" : "")\($0.fieldDescription.isEmpty ? "" : " — \($0.fieldDescription)")" }.joined(separator: "\n"))
        """
    }

    private func runGenerationOptions() async throws {
        try requireAvailableModel()

        // 同じ Prompt を3つの設定で実行して差を見る。
        let presets: [(String, GenerationOptions)] = [
            ("Deterministic", GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: maximumResponseTokens)),
            ("Balanced (画面の設定)", currentOptions),
            ("Creative", GenerationOptions(sampling: .random(top: 100), temperature: 1.0, maximumResponseTokens: maximumResponseTokens))
        ]

        var columns: [ComparisonColumn] = []
        for (title, options) in presets {
            try Task.checkCancellation()
            let started = Date()
            let session = makeSession(instructions: "必ず日本語で答えてください。")
            let response = try await session.respond(to: prompt, options: options)
            result.executionMode = .foundationModels
            columns.append(ComparisonColumn(
                title: title,
                subtitle: describe(options),
                body: response.content,
                footnotes: [
                    KeyValueRow(label: "Elapsed", value: String(format: "%.2f sec", Date().timeIntervalSince(started))),
                    KeyValueRow(label: "文字数", value: "\(response.content.count)")
                ]
            ))
            publishTranscript(session)
        }
        result.payload = .comparison(columns)
        result.debugDetail = """
        3つの GenerationOptions を同じ Prompt に適用した。
        temperature を上げると語彙と構成の揺れが大きくなり、greedy + temperature 0 では実行ごとの差が小さくなる。
        画面のスライダー値: temperature=\(String(format: "%.2f", temperature)), maximumResponseTokens=\(maximumResponseTokens), sampling=\(samplingChoice.title)

        実測の注意: temperature を 1.5 まで上げると語の選択が崩れ（「町家風佃煮」など）、
        無害な Prompt でも安全ガードレールで停止することがあった（sampling: random との組み合わせで発生）。
        出力の安定性が要る用途では temperature を上げない。
        """
    }

    private func runGreedySampling() async throws {
        try requireAvailableModel()

        // 同じ設定で3回ずつ実行し、揺れの有無を実測する。
        //
        // 6回のうち1回が安全ガードレールで止まっただけで画面が全滅していたので、
        // 失敗はその回の結果として記録し、残りの実測値は見せる。
        // この画面の目的は「greedy は揺れないか」を実測することなので、
        // 1回の拒否で比較そのものを失う方が損失が大きい。
        func runThrice(_ options: GenerationOptions) async throws -> (outputs: [String], failures: Int) {
            var outputs: [String] = []
            var failures = 0
            for _ in 0..<3 {
                try Task.checkCancellation()
                let session = makeSession(instructions: "簡潔に、必ず日本語で答えてください。")
                do {
                    outputs.append(try await session.respond(to: prompt, options: options).content)
                } catch {
                    if error is CancellationError { throw error }
                    let mapped = LabError.map(error)
                    guard mapped.category == .guardrailViolation || mapped.category == .refusal else { throw error }
                    failures += 1
                    outputs.append("（この回はモデル側で停止: \(mapped.category.rawValue)）")
                }
            }
            return (outputs, failures)
        }

        let greedyRun = try await runThrice(GenerationOptions(sampling: .greedy, temperature: 0, maximumResponseTokens: 160))
        let randomRun = try await runThrice(GenerationOptions(sampling: .random(top: 100), temperature: 1.0, maximumResponseTokens: 160))
        result.executionMode = .foundationModels

        let greedy = greedyRun.outputs
        let random = randomRun.outputs
        // 停止した回は比較対象から外す。揺れの有無は成功した回だけで数える。
        let greedyUnique = Set(greedy.filter { !$0.hasPrefix("（この回は") }).count
        let randomUnique = Set(random.filter { !$0.hasPrefix("（この回は") }).count

        result.payload = .comparison([
            ComparisonColumn(
                title: "Greedy Sampling",
                subtitle: "GenerationOptions(sampling: .greedy, temperature: 0)",
                body: """
                同じ Prompt を3回実行し、各ステップで最も確率の高い候補を選び続けた結果です。

                \(greedy.enumerated().map { "実行\($0.offset + 1): \($0.element)" }.joined(separator: "\n\n"))
                """,
                footnotes: [
                    KeyValueRow(label: "3回中の異なる出力数", value: "\(greedyUnique)", status: greedyUnique == 1 ? .success : .warning),
                    KeyValueRow(label: "モデル側で停止した回", value: "\(greedyRun.failures) / 3",
                                status: greedyRun.failures == 0 ? .neutral : .warning)
                ]
            ),
            ComparisonColumn(
                title: "Random Sampling",
                subtitle: "GenerationOptions(sampling: .random(top: 100), temperature: 1.0)",
                body: """
                同じ Prompt を3回実行し、候補から確率的に選んだ結果です。

                \(random.enumerated().map { "実行\($0.offset + 1): \($0.element)" }.joined(separator: "\n\n"))
                """,
                footnotes: [
                    KeyValueRow(label: "3回中の異なる出力数", value: "\(randomUnique)", status: randomUnique > 1 ? .success : .warning),
                    KeyValueRow(label: "モデル側で停止した回", value: "\(randomRun.failures) / 3",
                                status: randomRun.failures == 0 ? .neutral : .warning)
                ]
            )
        ])
        result.debugDetail = """
        Greedy Sampling:
        各ステップで最も確率の高い次トークンを選び続ける。出力の再現性を上げたいときに使う。

        Random Sampling:
        上位候補から確率的に選ぶ。言い回しや構成の多様性を見たいときに使う。

        分類のように「毎回同じ答えであるべき」処理では greedy が向く。
        random(top:seed:) に seed を渡せば、ランダムでも再現可能にできる。
        なお greedy でも異なる出力数が1にならないことがある（実行環境や内部状態に依存するため、この画面は実測値をそのまま表示している）。
        """
    }

    // MARK: - TOOLS

    /// Tool を登録したセッションで実行し、Transcript から呼び出しを復元する共通処理。
    private func runTooling(tools: Set<LabToolName>, instructions: String) async throws {
        try requireAvailableModel()
        let session = makeSession(instructions: instructions, tools: tools)
        result.executionMode = .foundationModels
        let response = try await session.respond(to: prompt, options: currentOptions)
        publishTranscript(session)
        drainToolLog()

        let steps = timeline(from: Array(response.transcriptEntries), finalResponse: response.content)
        result.payload = steps.isEmpty
            ? .text(response.content)
            : .timeline(timeline(from: Array(response.transcriptEntries), finalResponse: response.content))

        let calledTools = toolCallNames(in: Array(response.transcriptEntries))
        result.debugDetail = """
        登録した Tool: \(tools.map(\.displayName).sorted().joined(separator: ", "))
        モデルが呼んだ Tool: \(calledTools.isEmpty ? "なし（モデルは Tool を使わずに答えた）" : calledTools.joined(separator: ", "))

        Tool を呼ぶかどうかはモデルが決める。プロンプトが Tool の説明文と結びつかない場合は呼ばれない。
        """
    }

    private func runMultipleTools() async throws {
        try requireAvailableModel()
        let tools: Set<LabToolName> = [.drugSearch, .inventory, .patient, .prescription, .weather]
        let session = makeSession(
            instructions: """
            利用可能な Tool の説明を読み、質問に必要な Tool だけを選んで使ってください。
            在庫の数は checkInventory、薬効は searchDrug で調べます。
            答えは Tool の出力に書かれている内容だけにしてください。
            Tool に該当が無い場合は、無いことをそのまま伝えてください。
            必ず日本語で答えてください。
            """,
            tools: tools
        )
        result.executionMode = .foundationModels
        let response = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 512))
        publishTranscript(session)
        drainToolLog()

        let called = toolCallNames(in: Array(response.transcriptEntries))
        result.payload = .timeline(timeline(from: Array(response.transcriptEntries), finalResponse: response.content))
        result.debugDetail = """
        公開した Tool: \(tools.map(\.displayName).sorted().joined(separator: ", "))
        選ばれた Tool: \(called.isEmpty ? "なし" : called.joined(separator: " → "))

        期待動作:
        「アムロジピン5mgの在庫はいくつ？」→ checkInventory
        「アムロジピンは何の薬？」→ searchDrug
        Tool の description が選択の根拠になるため、説明文の書き方が精度を左右する。
        """
    }

    private func runMultiStepTool() async throws {
        try requireAvailableModel()
        let tools: Set<LabToolName> = [.patient, .prescription, .inventory]
        let session = makeSession(
            instructions: """
            段階的に調べてください。まず findPatient で患者を特定し、その患者IDで listPrescriptions を呼び、
            得られた薬剤ごとに checkInventory を呼んで在庫を確認します。最後に条件に合う薬剤だけを報告してください。
            必ず日本語で答えてください。
            """,
            tools: tools
        )
        result.executionMode = .foundationModels
        let response = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 1024))
        publishTranscript(session)
        drainToolLog()

        let entries = Array(response.transcriptEntries)
        result.payload = .timeline(timeline(from: entries, finalResponse: response.content))
        let called = toolCallNames(in: entries)
        result.debugDetail = """
        Tool 呼び出し回数: \(called.count)
        順序: \(called.joined(separator: " → "))

        1回の respond(to:) の中でモデルが複数回 Tool を呼び、その結果を見て次の Tool を決めている。
        アプリ側はループを書いていない。
        """
    }

    private func runSideEffectTool() async throws {
        try requireAvailableModel()
        let session = makeSession(
            instructions: """
            在庫の変更を依頼されたら requestInventoryUpdate で申請してください。
            この Tool は申請のみで、実際の在庫は変更されません。あなたが在庫を変更したとは言わないでください。
            必ず日本語で答えてください。
            """,
            tools: [.inventoryUpdate, .inventory]
        )
        result.executionMode = .foundationModels
        let response = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 512))
        publishTranscript(session)
        drainToolLog()
        drainPendingSideEffects()

        result.payload = .timeline(
            timeline(from: Array(response.transcriptEntries), finalResponse: response.content)
            + [TimelineStep(
                title: pendingSideEffects.isEmpty ? "承認待ちなし" : "Human Confirmation 待ち",
                detail: pendingSideEffects.isEmpty
                    ? "モデルは更新を申請しませんでした。"
                    : pendingSideEffects.map(\.summary).joined(separator: "\n") + "\n下の Human Confirmation で Execute / Cancel を選んでください。",
                kind: .note
            )]
        )
        result.debugDetail = """
        Model → Tool Call Request → Human Confirmation → Tool Execution の順序を守っている。
        現在の在庫（未変更）:
        \(inventory.all.map(\.summary).joined(separator: "\n"))
        """
    }

    // MARK: - Helpers used across demos

    private func arrayField(_ label: String, _ values: [String], guide: String) -> StructuredField {
        StructuredField(
            label: label,
            value: values.isEmpty ? "（なし）" : "\(values.count) 件",
            typeName: "[String]",
            guideDescription: guide,
            children: values.enumerated().map { StructuredField(label: "[\($0.offset)]", value: $0.element, typeName: "String") }
        )
    }

    func describe(_ options: GenerationOptions) -> String {
        var parts: [String] = []
        if let temperature = options.temperature { parts.append("temperature: \(String(format: "%.2f", temperature))") }
        if let maximum = options.maximumResponseTokens { parts.append("maxTokens: \(maximum)") }
        parts.append("sampling: \(options.sampling == nil ? "automatic" : (options.sampling == .greedy ? "greedy" : "random"))")
        return parts.joined(separator: ", ")
    }

    /// GeneratedContent を再帰的に表示用フィールドへ落とす（動的スキーマ用の JSON Viewer）。
    func structuredFields(from content: GeneratedContent, label: String = "root") -> [StructuredField] {
        switch content.kind {
        case .structure(let properties, let orderedKeys):
            return orderedKeys.compactMap { key in
                guard let value = properties[key] else { return nil }
                return field(named: key, from: value)
            }
        case .array(let elements):
            return elements.enumerated().map { field(named: "[\($0.offset)]", from: $0.element) }
        default:
            return [field(named: label, from: content)]
        }
    }

    private func field(named name: String, from content: GeneratedContent) -> StructuredField {
        switch content.kind {
        case .null:
            return StructuredField(label: name, value: "null", typeName: "null")
        case .bool(let value):
            return StructuredField(label: name, value: value ? "true" : "false", typeName: "Bool")
        case .number(let value):
            let isInteger = value == value.rounded()
            return StructuredField(label: name, value: isInteger ? "\(Int(value))" : "\(value)", typeName: isInteger ? "Int" : "Double")
        case .string(let value):
            return StructuredField(label: name, value: value, typeName: "String")
        case .array(let elements):
            return StructuredField(
                label: name, value: "\(elements.count) 件", typeName: "Array",
                children: elements.enumerated().map { field(named: "[\($0.offset)]", from: $0.element) }
            )
        case .structure(let properties, let orderedKeys):
            return StructuredField(
                label: name, value: "\(orderedKeys.count) フィールド", typeName: "Object",
                children: orderedKeys.compactMap { key in
                    properties[key].map { field(named: key, from: $0) }
                }
            )
        @unknown default:
            return StructuredField(label: name, value: content.jsonString, typeName: "unknown")
        }
    }

    /// Transcript のエントリからタイムラインを組む（仕様書 §26 Tool Call Timeline / §55 Agent Timeline）。
    func timelineSteps(from entries: [Transcript.Entry]) -> [TimelineStep] {
        entries.compactMap { entry in
            switch entry {
            case .instructions(let instructions):
                let text = segmentText(instructions.segments)
                let tools = instructions.toolDefinitions.map(\.name)
                return TimelineStep(
                    title: "Instructions",
                    detail: text + (tools.isEmpty ? "" : "\n\n登録 Tool: \(tools.joined(separator: ", "))"),
                    kind: .instructions
                )
            case .prompt(let prompt):
                return TimelineStep(title: "Prompt", detail: segmentText(prompt.segments), kind: .prompt)
            case .toolCalls(let calls):
                return TimelineStep(
                    title: "Tool Call: \(calls.map(\.toolName).joined(separator: ", "))",
                    detail: calls.map { "\($0.toolName)\n引数: \($0.arguments.jsonString)" }.joined(separator: "\n\n"),
                    kind: .toolCall
                )
            case .toolOutput(let output):
                return TimelineStep(title: "Tool Output: \(output.toolName)", detail: segmentText(output.segments), kind: .toolOutput)
            case .response(let response):
                return TimelineStep(title: "Response", detail: segmentText(response.segments), kind: .response)
            @unknown default:
                return nil
            }
        }
    }

    /// Transcript のタイムラインを作る。
    /// Transcript にすでに .response が含まれている場合は、同じ本文を二重に出さない。
    func timeline(from entries: [Transcript.Entry], finalResponse: String) -> [TimelineStep] {
        let steps = timelineSteps(from: entries)
        let alreadyHasResponse = entries.contains { entry in
            if case .response = entry { return true } else { return false }
        }
        guard !alreadyHasResponse, !finalResponse.isEmpty else { return steps }
        return steps + [TimelineStep(title: "Model Response", detail: finalResponse, kind: .response)]
    }

    func toolCallNames(in entries: [Transcript.Entry]) -> [String] {
        entries.flatMap { entry -> [String] in
            if case .toolCalls(let calls) = entry { return calls.map(\.toolName) }
            return []
        }
    }

    private func segmentText(_ segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let text): text.content
            case .structure(let structure): structure.content.jsonString
            @unknown default: String(describing: segment)
            }
        }
        .joined(separator: "\n")
    }
}
