//
//  LabEngine+Vision.swift
//  Foundation Models Lab
//
//  仕様書 §29-§36 のマルチモーダルデモ。
//
//  重要な前提:
//  インストール済み iOS 26 SDK の FoundationModels には画像をプロンプトへ添付する API が存在しない。
//  そのため本アプリは Vision framework で画像・動画・カメラフレームを解析し、
//  観測できた事実（分類ラベル / OCR結果 / バーコード / 注目領域 / 美的スコア）をテキスト化して
//  言語モデルへ渡す構成をとる。この境界は画面上に明示する。
//

import Foundation
import CoreGraphics
import FoundationModels

extension LabEngine {

    // MARK: - 共通: Vision → モデル

    /// Vision の解析結果をモデルへ渡す共通の前置き。
    private func visionBridgeInstructions(_ role: String) -> String {
        """
        \(role)
        あなたは画像を直接見ていません。Vision framework が画像から抽出した観測結果だけが与えられます。
        観測結果に無いものを推測して断定しないでください。確信が持てない場合はそう述べてください。
        必ず日本語で答えてください。
        """
    }

    /// モデルへ渡せる観測テキスト。何も検出できていなければ nil。
    /// Vision の失敗一覧はモデルに渡さない（エラー一覧を画像の説明として言い換えてしまう）。
    private func modelObservations(_ analyses: FrameAnalysis...) -> String? {
        let joined = analyses.map(\.observationDigest).filter { !$0.isEmpty }
        return joined.isEmpty ? nil : joined.joined(separator: "\n")
    }

    /// 英語で問い直すときの指示。
    /// OCR が英語優位のラベルを読むと、日本語の指示との混在で
    /// モデルが unsupportedLanguageOrLocale を返すことがある。
    /// 言語判定は同じ文面なら安定して同じ結果になるので、
    /// 再試行するときは文面ごと英語へ寄せる。
    private func visionBridgeInstructionsEN(_ role: String) -> String {
        """
        \(role)
        You do not see the image itself. You only receive observations that the
        Vision framework extracted from it. Do not assert anything that is not
        in the observations. Say so when you are not sure.
        """
    }

    /// 日本語で拒否されたら英語で1回だけ問い直す。
    ///
    /// 英語優位の観測テキスト（薬剤ラベルの英字表記など）で
    /// unsupportedLanguageOrLocale になるため、同じ文面での再試行は意味がない。
    /// 英語は supportedLanguages に含まれるので、言語を変えて通す。
    /// isEnglishFallback は画面に断りを出すために返す。
    /// テストからも同じ経路を通せるように internal にしている（アプリの挙動をそのまま検証するため）。
    func respondBridging(
        role: String,
        question: String,
        observations: String
    ) async throws -> (text: String, session: LanguageModelSession, isEnglishFallback: Bool) {
        let jaSession = makeSession(instructions: visionBridgeInstructions(role))
        do {
            let response = try await jaSession.respond(
                to: "\(question)\n\n[Vision解析結果]\n\(observations)",
                options: currentOptions
            )
            return (response.content, jaSession, false)
        } catch {
            guard LabError.isUnsupportedLanguage(error) else { throw error }
            try Task.checkCancellation()
            log(.onError, "日本語の指示が拒否されたため英語で問い直します（観測テキストが英語優位）")

            let enSession = makeSession(instructions: visionBridgeInstructionsEN(role))
            let response = try await enSession.respond(
                to: "\(question)\n\n[Vision observations]\n\(observations)",
                options: currentOptions
            )
            return (response.content, enSession, true)
        }
    }

    /// 構造化出力版の言語フォールバック。
    /// 日本語で拒否されたら、指示だけ英語に替えて1回だけ問い直す。
    /// 出力はスキーマに従うので、指示の言語が変わっても画面表示は壊れない。
    /// テストからも同じ経路を通せるように internal にしている。
    func respondBridgingStructured<Content: Generable>(
        role: String,
        question: String,
        observations: String,
        generating: Content.Type,
        options: GenerationOptions? = nil
    ) async throws -> (
        content: Content,
        raw: GeneratedContent,
        session: LanguageModelSession,
        isEnglishFallback: Bool
    ) {
        do {
            let response = try await respond(
                "\(question)\n\n[Vision解析結果]\n\(observations)",
                generating: generating,
                instructions: visionBridgeInstructions(role),
                options: options
            )
            return (response.content, response.raw, response.session, false)
        } catch {
            guard LabError.isUnsupportedLanguage(error) else { throw error }
            try Task.checkCancellation()
            // 英語へ替えられるのはアプリが持っている文（Instructions と見出し）だけで、
            // question は利用者が編集した文なのでそのまま送る。完全な英語化にはならない。
            log(.onError, "日本語の指示が拒否されたため英語で問い直します（観測テキストが英語優位）")
            let response = try await respond(
                "\(question)\n\n[Vision observations]\n\(observations)",
                generating: generating,
                instructions: visionBridgeInstructionsEN(role),
                options: options
            )
            return (response.content, response.raw, response.session, true)
        }
    }

    /// Vision が何も観測できなかったときに、モデルを呼ばずに理由を説明する。
    private func noObservationMessage(_ frames: [FrameAnalysis]) -> String {
        let failed = Set(frames.flatMap { $0.unavailableRequests.map(\.request) }).sorted()
        var lines = ["Vision は画像から何も検出できませんでした。モデルには何も渡していません。"]
        if failed.isEmpty {
            lines.append("文字・バーコード・分類のいずれも検出されない画像です。別の画像を試してください。")
        } else {
            lines.append("この環境で実行できなかった解析: \(failed.joined(separator: ", "))")
            lines.append("Simulator では作成できない Vision リクエストがあります。実機で確認してください。")
        }
        return lines.joined(separator: "\n")
    }

    private func requireImage() throws -> ImageBox {
        guard let image else {
            throw LabError.image("画像が選択されていません。")
        }
        return image
    }

    // MARK: - DEMO 21 Photo Description

    func runImageDescription() async throws {
        let image = try requireImage()
        let analysis = try await cachedOrAnalyze(image, cached: imageAnalysis, plan: .full)
        imageAnalysis = analysis

        var media = MediaAnalysisResult(source: .image, frames: [analysis], digest: analysis.digest, visionElapsed: analysis.visionElapsed)
        media.mediaInfo = [
            KeyValueRow(label: "Image Size", value: "\(Int(analysis.imageSize.width)) × \(Int(analysis.imageSize.height))"),
            KeyValueRow(label: "Vision Requests", value: VisionAnalysisPlan.full.requestNames.joined(separator: ", ")),
            KeyValueRow(label: "Vision Elapsed", value: String(format: "%.0f ms", analysis.visionElapsed * 1000))
        ]

        if !modelManager.availability.isAvailable {
            result.executionMode = .visionOnly
            media.modelText = "モデルが利用できないため、Vision の解析結果のみ表示しています。\n\(modelManager.availability.detail)"
        } else if let observations = modelObservations(analysis) {
            let started = Date()
            result.executionMode = .visionBridge
            let bridged = try await respondBridging(
                role: "あなたは画像の内容を説明する担当です。",
                question: prompt,
                observations: observations
            )
            publishTranscript(bridged.session)
            media.modelText = bridged.text
            media.modelElapsed = Date().timeIntervalSince(started)
            result.metrics.responseTokens = await tokenCount(bridged.text)
            if bridged.isEnglishFallback {
                media.mediaInfo.append(KeyValueRow(
                    label: "言語フォールバック",
                    value: "日本語の指示が拒否されたため英語で再実行",
                    status: .warning
                ))
            }
        } else {
            result.executionMode = .visionOnly
            media.modelText = noObservationMessage(media.frames)
        }

        media.mediaInfo += unavailableRequestRows(media.frames)
        result.payload = .media(media)
        result.debugDetail = bridgeExplanation(plan: .full)
    }

    // MARK: - DEMO 22 Photo Classification

    func runImageClassification() async throws {
        let image = try requireImage()
        let analysis = try await analyzeImage(image, plan: .classificationOnly)
        imageAnalysis = analysis

        var lines: [String] = []
        if analysis.labels.isEmpty {
            lines.append("ClassifyImageRequest は分類ラベルを返しませんでした。")
        } else {
            lines.append(contentsOf: analysis.labels.map { "\($0.identifier): \($0.percentText)" })
        }

        var media = MediaAnalysisResult(source: .image, frames: [analysis], digest: lines.joined(separator: "\n"), visionElapsed: analysis.visionElapsed)
        media.mediaInfo = [
            KeyValueRow(label: "Vision ラベル数", value: "\(analysis.labels.count)"),
            KeyValueRow(label: "Vision 最上位ラベル", value: analysis.labels.first.map { "\($0.identifier) \($0.percentText)" } ?? "なし"),
            KeyValueRow(label: "Vision Request", value: "ClassifyImageRequest"),
            KeyValueRow(label: "Vision Elapsed", value: String(format: "%.0f ms", analysis.visionElapsed * 1000))
        ]

        result.executionMode = .visionOnly
        media.mediaInfo += unavailableRequestRows(media.frames)
        result.payload = .media(media)
        result.debugDetail = """
        Apple Developer Documentation: Classifying images for categorization and search

        この画面は ClassifyImageRequest だけを実行する。
        FoundationModels への写像や @Generable enum への変換は行わない。
        """
    }

    // MARK: - DEMO 23 Text Rectangles

    func runTextRectangles() async throws {
        let image = try requireImage()
        let analysis = try await analyzeImage(image, plan: .textRectanglesOnly)
        imageAnalysis = analysis
        publishVisionOnlyImageResult(
            analysis,
            requestName: "DetectTextRectanglesRequest",
            digest: analysis.textRegions.enumerated().map { "TextRegion[\($0.offset)] boundingBox=\($0.element.boundingBox)" }.joined(separator: "\n"),
            rows: [KeyValueRow(label: "Text Regions", value: "\(analysis.textRegions.count)")],
            debugDetail: "Apple Developer Documentation: DetectTextRectanglesRequest\n文字列認識は行わず、文字らしい領域の TextObservation.boundingBox だけを表示する。"
        )
    }

    // MARK: - DEMO 27 Rectangles

    func runRectangles() async throws {
        let image = try requireImage()
        let analysis = try await analyzeImage(image, plan: .rectanglesOnly)
        imageAnalysis = analysis
        publishVisionOnlyImageResult(
            analysis,
            requestName: "DetectRectanglesRequest",
            digest: analysis.rectangles.enumerated().map { "Rectangle[\($0.offset)] boundingBox=\($0.element.boundingBox)" }.joined(separator: "\n"),
            rows: [KeyValueRow(label: "Rectangles", value: "\(analysis.rectangles.count)")],
            debugDetail: "Apple Developer Documentation: DetectRectanglesRequest\nカード、書類、看板のような投影矩形を RectangleObservation として検出する。"
        )
    }

    // MARK: - DEMO 28 Face Rectangles

    func runFaceRectangles() async throws {
        let image = try requireImage()
        let analysis = try await analyzeImage(image, plan: .facesOnly)
        imageAnalysis = analysis
        publishVisionOnlyImageResult(
            analysis,
            requestName: "DetectFaceRectanglesRequest",
            digest: analysis.faceRectangles.enumerated().map { "Face[\($0.offset)] boundingBox=\($0.element.boundingBox)" }.joined(separator: "\n"),
            rows: [KeyValueRow(label: "Faces", value: "\(analysis.faceRectangles.count)")],
            debugDetail: "Apple Developer Documentation: DetectFaceRectanglesRequest\n顔の領域を FaceObservation.boundingBox として検出する。人物全体の検出はこの画面では行わない。"
        )
    }

    // MARK: - DEMO 29 Human Rectangles

    func runHumanRectangles() async throws {
        let image = try requireImage()
        let analysis = try await analyzeImage(image, plan: .humansOnly)
        imageAnalysis = analysis
        publishVisionOnlyImageResult(
            analysis,
            requestName: "DetectHumanRectanglesRequest",
            digest: analysis.humanRectangles.enumerated().map { "Human[\($0.offset)] boundingBox=\($0.element.boundingBox)" }.joined(separator: "\n"),
            rows: [KeyValueRow(label: "Humans", value: "\(analysis.humanRectangles.count)")],
            debugDetail: "Apple Developer Documentation: DetectHumanRectanglesRequest\n人物全体の領域を HumanObservation.boundingBox として検出する。顔検出はこの画面では行わない。"
        )
    }

    // MARK: - DEMO 30 Saliency

    func runSaliency() async throws {
        let image = try requireImage()
        let analysis = try await analyzeImage(image, plan: .saliencyOnly)
        imageAnalysis = analysis
        publishVisionOnlyImageResult(
            analysis,
            requestName: "GenerateObjectnessBasedSaliencyImageRequest",
            digest: analysis.salientObjects.enumerated().map { "SalientObject[\($0.offset)] boundingBox=\($0.element)" }.joined(separator: "\n"),
            rows: [KeyValueRow(label: "Salient Objects", value: "\(analysis.salientObjects.count)")],
            debugDetail: "Apple Developer Documentation: GenerateObjectnessBasedSaliencyImageRequest\n物体らしい注目領域を SaliencyImageObservation.salientObjects として取得する。"
        )
    }

    // MARK: - DEMO 31 Aesthetics

    func runAesthetics() async throws {
        let image = try requireImage()
        let analysis = try await analyzeImage(image, plan: .aestheticsOnly)
        imageAnalysis = analysis
        publishVisionOnlyImageResult(
            analysis,
            requestName: "CalculateImageAestheticsScoresRequest",
            digest: """
            overallScore=\(analysis.aestheticsScore.map { String(format: "%.3f", $0) } ?? "nil")
            isUtility=\(analysis.isUtilityImage.map { $0 ? "true" : "false" } ?? "nil")
            """,
            rows: [
                KeyValueRow(label: "Overall Score", value: analysis.aestheticsScore.map { String(format: "%.3f", $0) } ?? "なし"),
                KeyValueRow(label: "Utility Image", value: analysis.isUtilityImage.map { $0 ? "true" : "false" } ?? "なし")
            ],
            debugDetail: "Apple Developer Documentation: CalculateImageAestheticsScoresRequest\n画像の美的スコアと、実用系画像かどうかを ImageAestheticsScoresObservation から取得する。"
        )
    }

    // MARK: - DEMO 23 Compare Photos

    func runCompareImages() async throws {
        guard let first = image, let second = secondImage else {
            throw LabError.image("比較には2枚の画像が必要です。Image A と Image B を選択してください。")
        }
        let analysisA = try await cachedOrAnalyze(first, cached: imageAnalysis, plan: .full)
        let analysisB = try await cachedOrAnalyze(second, cached: secondImageAnalysis, plan: .full)
        imageAnalysis = analysisA
        secondImageAnalysis = analysisB

        let digest = """
        [画像A の解析結果]
        \(analysisA.observationDigest)

        [画像B の解析結果]
        \(analysisB.observationDigest)
        """

        var media = MediaAnalysisResult(
            source: .imagePair,
            frames: [analysisA, analysisB],
            digest: digest,
            visionElapsed: analysisA.visionElapsed + analysisB.visionElapsed
        )
        media.mediaInfo = [
            KeyValueRow(label: "Image A", value: "\(Int(analysisA.imageSize.width))×\(Int(analysisA.imageSize.height)) / ラベル\(analysisA.labels.count) / 文字\(analysisA.texts.count)"),
            KeyValueRow(label: "Image B", value: "\(Int(analysisB.imageSize.width))×\(Int(analysisB.imageSize.height)) / ラベル\(analysisB.labels.count) / 文字\(analysisB.texts.count)")
        ]

        if let observations = modelObservations(analysisA, analysisB), modelManager.availability.isAvailable {
            let started = Date()
            let response = try await respondBridgingStructured(
                role: "あなたは2枚の画像を比較する担当です。",
                question: prompt,
                observations: observations,
                generating: ImageComparison.self
            )
            result.executionMode = .visionBridge
            if response.isEnglishFallback {
                media.mediaInfo.append(KeyValueRow(
                    label: "言語フォールバック",
                    value: "日本語の指示が拒否されたため英語で再実行",
                    status: .warning
                ))
            }
            let content = response.content
            media.modelFields = [
                StructuredField(label: "similarities", value: "\(content.similarities.count) 件", typeName: "[String]",
                                children: content.similarities.enumerated().map { StructuredField(label: "[\($0.offset)]", value: $0.element, typeName: "String") }),
                StructuredField(label: "differences", value: "\(content.differences.count) 件", typeName: "[String]",
                                guideDescription: "3点以上 (.count(3...6))",
                                children: content.differences.enumerated().map { StructuredField(label: "[\($0.offset)]", value: $0.element, typeName: "String") }),
                StructuredField(label: "verdict", value: content.verdict, typeName: "String")
            ]
            media.modelJSON = response.raw.jsonString
            media.modelElapsed = Date().timeIntervalSince(started)
        } else {
            result.executionMode = .visionOnly
            media.modelText = "モデルが利用できないため、2枚それぞれの Vision 解析結果のみ表示しています。"
        }

        media.mediaInfo += unavailableRequestRows(media.frames)
        result.payload = .media(media)
        result.debugDetail = bridgeExplanation(plan: .full)
    }

    // MARK: - DEMO 24 Structured Vision

    func runStructuredVision() async throws {
        let image = try requireImage()
        let analysis = try await cachedOrAnalyze(image, cached: imageAnalysis, plan: .full)
        imageAnalysis = analysis

        var media = MediaAnalysisResult(source: .image, frames: [analysis], digest: analysis.digest, visionElapsed: analysis.visionElapsed)

        guard let observations = modelObservations(analysis) else {
            result.executionMode = .visionOnly
            media.modelText = noObservationMessage(media.frames)
            media.mediaInfo = [KeyValueRow(label: "Vision Elapsed", value: String(format: "%.0f ms", analysis.visionElapsed * 1000))]
            media.mediaInfo += unavailableRequestRows(media.frames)
            result.payload = .media(media)
            result.debugDetail = "観測結果が空だったため、構造化出力の生成は行っていない。"
            return
        }

        let started = Date()
        let response = try await respondBridgingStructured(
            role: "あなたは画像を構造化する担当です。",
            question: "この画像の解析結果から ImageAnalysis を作ってください。",
            observations: observations,
            generating: ImageAnalysis.self
        )
        result.executionMode = .visionBridge
        let content = response.content
        media.modelFields = [
            StructuredField(label: "title", value: content.title, typeName: "String", guideDescription: "画像に付ける短いタイトル"),
            StructuredField(label: "objects", value: "\(content.objects.count) 件", typeName: "[String]",
                            guideDescription: "主要な物体 (.count(1...8))",
                            children: content.objects.enumerated().map { StructuredField(label: "[\($0.offset)]", value: $0.element, typeName: "String") }),
            StructuredField(label: "description", value: content.description, typeName: "String"),
            StructuredField(label: "textSummary", value: content.textSummary.isEmpty ? "（文字なし）" : content.textSummary, typeName: "String"),
            StructuredField(label: "tags", value: "\(content.tags.count) 件", typeName: "[String]",
                            children: content.tags.enumerated().map { StructuredField(label: "[\($0.offset)]", value: $0.element, typeName: "String") })
        ]
        media.modelJSON = response.raw.jsonString
        media.modelElapsed = Date().timeIntervalSince(started)
        media.mediaInfo = [KeyValueRow(label: "Vision Elapsed", value: String(format: "%.0f ms", analysis.visionElapsed * 1000))]

        media.mediaInfo += unavailableRequestRows(media.frames)
        result.payload = .media(media)
        result.debugDetail = """
        \(bridgeExplanation(plan: .full))

        GenerationSchema:
        \(ImageAnalysis.generationSchema.debugDescription)
        """
    }

    // MARK: - DEMO 25 OCR

    func runOCR() async throws {
        let image = try requireImage()
        let analysis = try await analyzeImage(image, plan: .ocrOnly)
        imageAnalysis = analysis

        let digest = analysis.texts.enumerated().map { index, text in
            """
            Text[\(index)]
              transcript: \(text.text)
              confidence: \(String(format: "%.2f", text.confidence))
              boundingBox: \(text.boundingBox)
              languages: \(text.languages.joined(separator: ", ").ifEmpty("unknown"))
            """
        }.joined(separator: "\n\n")

        var media = MediaAnalysisResult(
            source: .image,
            frames: [analysis],
            digest: digest.ifEmpty("RecognizeTextRequest は 0 件の RecognizedTextObservation を返しました。"),
            visionElapsed: analysis.visionElapsed
        )
        media.mediaInfo = [
            KeyValueRow(label: "検出行数", value: "\(analysis.texts.count)"),
            KeyValueRow(label: "認識言語", value: Set(analysis.texts.flatMap(\.languages)).sorted().joined(separator: ", ").ifEmpty("なし")),
            KeyValueRow(label: "Vision Request", value: "RecognizeTextRequest"),
            KeyValueRow(label: "Recognition Level", value: "accurate"),
            KeyValueRow(label: "Vision Elapsed", value: String(format: "%.0f ms", analysis.visionElapsed * 1000)),
            KeyValueRow(label: "Custom Words", value: DemoData.drugNames.joined(separator: ", "))
        ]

        result.executionMode = .visionOnly
        media.mediaInfo += unavailableRequestRows(media.frames)
        result.payload = .media(media)
        result.debugDetail = """
        Apple Developer Documentation: Locating and displaying recognized text

        この画面は RecognizeTextRequest だけを実行する。
        transcript / confidence / boundingBox / recognitionLanguages をそのまま表示する。
        モデル要約や OCRTool は Vision + Tool 画面で扱う。
        """
    }

    // MARK: - DEMO 26 Barcode

    func runBarcode() async throws {
        let image = try requireImage()
        let analysis = try await analyzeImage(image, plan: .barcodeOnly)
        imageAnalysis = analysis

        let digest = analysis.barcodes.enumerated().map { index, barcode in
            """
            Barcode[\(index)]
              symbology: \(barcode.typeLabel)
              payload: \(barcode.payload)
              isGS1DataCarrier: \(barcode.isGS1DataCarrier)
              boundingBox: \(barcode.boundingBox)
            """
        }.joined(separator: "\n\n")

        var media = MediaAnalysisResult(
            source: .image,
            frames: [analysis],
            digest: digest.ifEmpty("DetectBarcodesRequest は 0 件の BarcodeObservation を返しました。"),
            visionElapsed: analysis.visionElapsed
        )
        media.mediaInfo = [
            KeyValueRow(label: "検出数", value: "\(analysis.barcodes.count)"),
            KeyValueRow(label: "Vision Request", value: "DetectBarcodesRequest"),
            KeyValueRow(label: "Vision Elapsed", value: String(format: "%.0f ms", analysis.visionElapsed * 1000))
        ]

        result.executionMode = .visionOnly
        media.mediaInfo += unavailableRequestRows(media.frames)
        result.payload = .media(media)
        result.debugDetail = """
        Apple Developer Documentation: DetectBarcodesRequest

        この画面は DetectBarcodesRequest だけを実行する。
        symbology / payloadString / isGS1DataCarrier / boundingBox をそのまま表示する。
        DrugDatabase 照合や BarcodeReaderTool は Vision + Tool 画面で扱う。
        """
    }

    // MARK: - Video Analysis（仕様書外の拡張）

    func runVideoAnalysis() async throws {
        guard let metadata = videoMetadata else {
            throw LabError.media("動画が選択されていません。", recovery: "Choose Video から動画を選択してください。")
        }

        // 1. 等間隔にコマを取り出して1枚ずつ Vision で解析する。
        let frames = try await analyzeVideoFrames(plan: .videoFrame)

        var media = MediaAnalysisResult(
            source: .video,
            frames: frames,
            digest: frames.videoDigest,
            visionElapsed: frames.totalVisionElapsed
        )
        media.mediaInfo = metadata.rows + [
            KeyValueRow(label: "Sampled Frames", value: "\(frames.count) / 指定 \(videoFrameCount)"),
            KeyValueRow(label: "Vision Total", value: String(format: "%.2f sec", frames.totalVisionElapsed)),
            KeyValueRow(label: "Vision / Frame", value: String(format: "%.0f ms", frames.totalVisionElapsed / Double(max(1, frames.count)) * 1000)),
            KeyValueRow(label: "Detected Text (unique)", value: "\(frames.uniqueTexts.count) 行"),
            KeyValueRow(label: "Detected Barcodes", value: "\(frames.uniqueBarcodes.count) 件"),
            KeyValueRow(label: "Top Labels", value: frames.aggregatedLabels.prefix(5).map { "\($0.identifier) \($0.percentText)" }.joined(separator: ", ").ifEmpty("なし"))
        ]

        // 2. 時系列のダイジェストを言語モデルへ渡して構造化させる。
        // モデルへ渡すのは観測結果だけ。実行できなかったリクエストの一覧は画面用に残す。
        var observationDigest = frames.videoObservationDigest
        if observationDigest.isEmpty {
            result.executionMode = .visionOnly
            media.modelText = noObservationMessage(frames)
            media.mediaInfo += unavailableRequestRows(media.frames)
            result.payload = .media(media)
            result.debugDetail = "どのコマからも観測結果が得られなかったため、モデルへは渡していない。"
            return
        }

        if modelManager.availability.isAvailable {
            let started = Date()
            // 動画は digest が長くなるのでトークン数を測ってから送る。
            let digestTokens = await tokenCount(observationDigest)
            if let digestTokens, digestTokens > modelManager.contextSize - 512 {
                // コンテキストに収まらない場合はフレームを間引く（実測に基づく縮退）。
                let reduced = Array(frames.enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
                observationDigest = reduced.videoObservationDigest
                media.digest = reduced.videoDigest
                media.mediaInfo.append(KeyValueRow(
                    label: "Digest 縮退",
                    value: "\(digestTokens) tokens はコンテキスト上限に近いため \(reduced.count) フレームへ間引き",
                    status: .warning
                ))
            }
            result.metrics.promptTokens = digestTokens

            let response = try await respond(
                """
                以下は1本の動画から等間隔に取り出したコマを、Vision framework で解析した結果です。
                時系列順に並んでいます。これをもとに動画全体の内容をまとめてください。

                ユーザーの指示: \(prompt)

                \(observationDigest)
                """,
                generating: VideoAnalysis.self,
                instructions: visionBridgeInstructions("あなたは動画の内容を時系列でまとめる担当です。各コマの解析結果をつなげて、動画として何が起きているかを説明します。")
            )
            result.executionMode = .visionBridge
            let content = response.content
            media.modelFields = [
                StructuredField(label: "title", value: content.title, typeName: "String"),
                StructuredField(label: "summary", value: content.summary, typeName: "String"),
                StructuredField(label: "scenes", value: "\(content.scenes.count) シーン", typeName: "[VideoScene]",
                                guideDescription: "時系列に並べたシーン (.count(1...8))",
                                children: content.scenes.map { scene in
                                    StructuredField(label: "\(scene.startSeconds)s", value: scene.description, typeName: "VideoScene", children: [
                                        StructuredField(label: "startSeconds", value: "\(scene.startSeconds)", typeName: "Int"),
                                        StructuredField(label: "description", value: scene.description, typeName: "String"),
                                        StructuredField(label: "labels", value: scene.labels.joined(separator: ", "), typeName: "[String]")
                                    ])
                                }),
                StructuredField(label: "onScreenText", value: content.onScreenText.isEmpty ? "（文字なし）" : content.onScreenText, typeName: "String"),
                StructuredField(label: "tags", value: content.tags.joined(separator: ", "), typeName: "[String]")
            ]
            media.modelJSON = response.raw.jsonString
            media.modelElapsed = Date().timeIntervalSince(started)
        } else {
            result.executionMode = .visionOnly
            media.modelText = "モデルが利用できないため、各コマの Vision 解析結果のみ表示しています。"
        }

        media.mediaInfo += unavailableRequestRows(media.frames)
        result.payload = .media(media)
        result.debugDetail = """
        動画そのものをモデルへ渡す API はこのSDKに存在しない。
        そこで AVAssetImageGenerator で \(frames.count) コマを抽出し、1コマずつ Vision で解析したうえで、
        時系列テキスト（digest）を1回のリクエストで言語モデルへ渡している。

        Vision requests / frame: \(VisionAnalysisPlan.videoFrame.requestNames.joined(separator: ", "))
        音声トラックは解析対象外（音声認識は別フレームワークの領域）。

        実測の注意: 薬剤名が並ぶ映像（棚の薬品ラベルを流し撮りしたものなど）は、
        scenes 配列に薬剤名の一覧が載るため既定のガードレールで停止することがある。
        これは Extraction デモで実測した「薬剤名を配列で返させると停止する」条件と同じで、
        同じ映像を再送しても結果は変わらない（4項目エラーとして表示する）。
        """
    }

    // MARK: - DEMO 27 Camera Frame

    func runCameraFrame() async throws {
        // 仕様書 §35: 押した瞬間のフレームだけを渡す。連続動画推論は行わない。
        // Capture Frame で取り込んだ1枚があればそれを使う（カメラを止めた後でも実行できる）。
        // 無ければ従来どおり、実行した瞬間のフレームをプレビューから取り出す。
        let source: VisionSource
        let captureNote: String
        if isImageFromCamera, let captured = image {
            source = .cgImage(captured.cgImage, orientation: nil)
            captureNote = "Capture Frame で取り込んだ1枚"
        } else {
            let captured = try captureCameraFrame()
            image = captured.image
            source = captured.source
            captureNote = "実行時にプレビューから取り出した1枚"
        }

        let analysis: FrameAnalysis
        if let cached = imageAnalysis, cached.isReusable {
            analysis = cached
        } else {
            analysis = try await analyze(source: source, plan: .full)
        }
        imageAnalysis = analysis

        var media = MediaAnalysisResult(source: .cameraFrame, frames: [analysis], digest: analysis.digest, visionElapsed: analysis.visionElapsed)
        media.mediaInfo = [
            KeyValueRow(label: "Frame Size", value: "\(Int(analysis.imageSize.width)) × \(Int(analysis.imageSize.height))"),
            KeyValueRow(label: "取り込み", value: captureNote),
            KeyValueRow(label: "受信フレーム総数", value: "\(camera.receivedFrameCount)"),
            KeyValueRow(label: "Vision Elapsed", value: String(format: "%.0f ms", analysis.visionElapsed * 1000)),
            KeyValueRow(label: "解析方式", value: "単一フレーム（連続動画推論は行わない）")
        ]

        if modelManager.availability.isAvailable {
            let started = Date()
            result.executionMode = .visionBridge
            let observations = modelObservations(analysis) ?? "（観測結果なし）"
            let bridged = try await respondBridging(
                role: "あなたはカメラで撮った1枚の内容を説明する担当です。",
                question: prompt,
                observations: observations
            )
            publishTranscript(bridged.session)
            media.modelText = bridged.text
            media.modelElapsed = Date().timeIntervalSince(started)
            if bridged.isEnglishFallback {
                media.mediaInfo.append(KeyValueRow(
                    label: "言語フォールバック",
                    value: "日本語の指示が拒否されたため英語で再実行",
                    status: .warning
                ))
            }
        } else {
            result.executionMode = .visionOnly
            media.modelText = "モデルが利用できないため、Vision の解析結果のみ表示しています。"
        }

        media.mediaInfo += unavailableRequestRows(media.frames)
        result.payload = .media(media)
        result.debugDetail = """
        AVCaptureVideoDataOutput のデリゲートが最新の CVPixelBuffer を保持し、
        ボタンを押した瞬間にその1フレームだけを取り出して CGImage へ変換し、Vision に渡している。

        \(bridgeExplanation(plan: .full))
        """
    }

    // MARK: - Live Camera（仕様書外の拡張）

    /// 連続解析中の最新フレームについて、明示的にモデルへ問いかける。
    func runLiveCameraQuestion() async throws {
        guard camera.state.isRunning else {
            throw LabError.camera(
                camera.state.message ?? "カメラが起動していません。",
                recovery: "Start Camera を押してカメラを起動してください。"
            )
        }
        guard let analysis = camera.liveAnalysis else {
            throw LabError.camera("まだ解析結果がありません。", recovery: "1〜2秒待ってから再実行してください。")
        }

        var media = MediaAnalysisResult(source: .cameraLive, frames: [analysis], digest: analysis.digest, visionElapsed: analysis.visionElapsed)
        media.mediaInfo = [
            KeyValueRow(label: "Vision 目標 FPS", value: String(format: "%.0f", camera.targetAnalysisFPS)),
            KeyValueRow(label: "Vision 実測 FPS", value: String(format: "%.1f", camera.measuredAnalysisFPS),
                        status: camera.measuredAnalysisFPS >= camera.targetAnalysisFPS * 0.7 ? .success : .warning),
            KeyValueRow(label: "解析済みフレーム", value: "\(camera.analyzedFrameCount)"),
            KeyValueRow(label: "受信フレーム総数", value: "\(camera.receivedFrameCount)"),
            KeyValueRow(label: "直近 Vision Elapsed", value: String(format: "%.0f ms", camera.lastVisionElapsed * 1000)),
            KeyValueRow(label: "モデル実況回数", value: "\(narrationCount)")
        ]

        await narrateCurrentFrame()
        result.executionMode = modelManager.availability.isAvailable ? .visionBridge : .visionOnly

        if let narration = liveNarration {
            media.modelFields = [
                StructuredField(label: "scene", value: narration.scene, typeName: "String", guideDescription: "今カメラに映っているもの"),
                StructuredField(label: "highlights", value: "\(narration.highlights.count) 件", typeName: "[String]",
                                children: narration.highlights.enumerated().map { StructuredField(label: "[\($0.offset)]", value: $0.element, typeName: "String") }),
                StructuredField(label: "readableText", value: narration.readableText.isEmpty ? "（なし）" : narration.readableText, typeName: "String"),
                StructuredField(label: "suggestion", value: narration.suggestion, typeName: "String")
            ]
        } else {
            media.modelText = liveNarrationPartial.ifEmpty("実況を取得できませんでした。")
        }
        if let elapsed = lastNarrationElapsed {
            media.modelElapsed = elapsed
        }

        media.mediaInfo += unavailableRequestRows(media.frames)
        result.payload = .media(media)
        result.debugDetail = """
        2段構えになっている:
        1. Vision は毎フレーム（目標 \(Int(camera.targetAnalysisFPS)) fps）走り続け、オーバーレイをリアルタイム更新する。
           プラン: \(VisionAnalysisPlan.realtime.requestNames.joined(separator: ", "))
        2. 言語モデルは1回あたり数百ミリ秒〜数秒かかるため毎フレームは呼べない。
           手動実行、または Auto Narration の間隔（\(Int(narrationIntervalSeconds))秒）でのみ呼び、
           そのときの最新解析結果を @Generable LiveFrameNarration として受け取る。

        この分離により「映像は滑らかに解析し続けつつ、言語化は間隔を空ける」という実用的な構成を確認できる。
        """
    }

    private func publishVisionOnlyImageResult(
        _ analysis: FrameAnalysis,
        requestName: String,
        digest: String,
        rows: [KeyValueRow],
        debugDetail: String
    ) {
        result.executionMode = .visionOnly
        var media = MediaAnalysisResult(
            source: .image,
            frames: [analysis],
            digest: digest.ifEmpty("\(requestName) は検出結果を返しませんでした。"),
            visionElapsed: analysis.visionElapsed
        )
        media.mediaInfo = rows + [
            KeyValueRow(label: "Vision Request", value: requestName),
            KeyValueRow(label: "Image Size", value: "\(Int(analysis.imageSize.width)) × \(Int(analysis.imageSize.height))"),
            KeyValueRow(label: "Vision Elapsed", value: String(format: "%.0f ms", analysis.visionElapsed * 1000))
        ]
        media.mediaInfo += unavailableRequestRows(media.frames)
        result.payload = .media(media)
        result.debugDetail = debugDetail
    }

    // MARK: - DEMO 28 Vision + Tool / DEMO 48 Vision Agent

    func runVisionTool() async throws {
        let image = try requireImage()
        imageProvider.set(image)
        try requireAvailableModel()

        let session = makeSession(
            instructions: """
            あなたは薬局の在庫担当です。画像から薬品を特定し、必要な情報を Tool で調べて報告してください。
            手順: readBarcode または readTextFromImage で画像の情報を読み取る →
            searchDrug で薬品情報を調べる → checkInventory で在庫を確認する。
            画像から読み取れなかったことは推測しないでください。必ず日本語で答えてください。
            """,
            tools: [.ocr, .barcode, .drugSearch, .inventory]
        )
        result.executionMode = .visionBridge
        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 1024)
        )
        publishTranscript(session)
        drainToolLog()

        let entries = Array(response.transcriptEntries)
        let called = toolCallNames(in: entries)
        result.payload = .timeline(timeline(from: entries, finalResponse: response.content))
        result.debugDetail = """
        画像は Tool を通してのみモデルに触れる。モデルは「画像を読む Tool」を呼ぶ判断だけを行う。
        公開した Tool: OCRTool, BarcodeReaderTool, DrugSearchTool, InventoryTool
        呼ばれた順: \(called.joined(separator: " → ").ifEmpty("なし"))

        画像 → OCR/Barcode → DrugSearch → Inventory → 回答 のフローが Transcript にそのまま現れる。
        """
    }

    func runVisionAgent() async throws {
        // 仕様書 §56: カメラまたは画像から始まる複合フロー。
        if image == nil, camera.state.isRunning {
            let captured = try captureCameraFrame()
            image = captured.image
            imageAnalysis = try await analyze(source: captured.source, plan: .full)
        }

        try await runVisionTool()
        result.debugDetail += """


        Vision Agent（仕様書 §56）の経路:
        Camera / Image → BarcodeReaderTool → DrugSearchTool → InventoryTool → Foundation Model → 回答
        カメラが起動中で画像が未選択の場合は、現在のフレームを自動で取り込んでから実行する。
        """
    }

    /// 既に解析済みならそれを使い、無ければ解析する。
    private func cachedOrAnalyze(_ image: ImageBox, cached: FrameAnalysis?, plan: VisionAnalysisPlan) async throws -> FrameAnalysis {
        // 中断などで中身が空になった解析結果は「検出0件」と区別できないので、作り直す。
        if let cached, cached.isReusable { return cached }
        return try await analyzeImage(image, plan: plan)
    }

    // MARK: - 共通の説明文

    /// この環境で実行できなかった Vision リクエストを表示行にする。
    func unavailableRequestRows(_ frames: [FrameAnalysis]) -> [KeyValueRow] {
        var seen = Set<String>()
        var rows: [KeyValueRow] = []
        for frame in frames {
            for failure in frame.unavailableRequests where seen.insert(failure.request).inserted {
                rows.append(KeyValueRow(
                    label: "実行不可: \(failure.request)",
                    value: failure.reason,
                    status: .warning
                ))
            }
        }
        return rows
    }

    private func bridgeExplanation(plan: VisionAnalysisPlan) -> String {
        """
        画像の扱いについて:
        インストール済み iOS 26 SDK の FoundationModels には、画像を Prompt へ添付する API（Attachment 相当）が存在しない。
        そのため本デモは次の経路をとる。

        画像 → Vision framework で観測 → 観測結果をテキスト化 → LanguageModelSession へ渡す

        実行した Vision リクエスト:
        \(plan.requestNames.map { "- \($0)" }.joined(separator: "\n"))

        モデルへ渡したテキストは画面の「Vision Raw Result」に全文表示している。
        モデルはこのテキストしか見ていないため、ここに無い情報を答えた場合はモデルの推測である。
        """
    }
}

// MARK: - String helper

extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
