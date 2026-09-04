//
//  VisionAnalyzer.swift
//  Foundation Models Lab
//
//  Vision framework による画像解析。
//  インストール済み iOS 26 SDK の FoundationModels は画像を直接プロンプトへ受け取れないため、
//  Vision で観測した事実をテキスト化してモデルへ渡す（仕様書 §33 OCRTool / §34 BarcodeReaderTool の構造）。
//

import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import Vision
import ImageIO

// MARK: - Analysis plan

/// 解析の重さを切り替える。カメラのリアルタイム解析では軽い構成を使う。
nonisolated struct VisionAnalysisPlan: Sendable, Equatable {
    var recognizeText = true
    var detectBarcodes = true
    var detectTextRegions = true
    var detectRectangles = true
    var classifyImage = true
    var detectSaliency = false
    var scoreAesthetics = false
    var detectPeople = false
    var detectFaces = false
    var detectHumans = false
    var textRecognitionLevel: RecognizeTextRequest.RecognitionLevel = .accurate

    /// 静止画の精密解析。
    static let full = VisionAnalysisPlan(
        recognizeText: true, detectBarcodes: true, detectTextRegions: true, detectRectangles: true, classifyImage: true,
        detectSaliency: true, scoreAesthetics: true, detectPeople: true,
        textRecognitionLevel: .accurate
    )

    /// 動画のコマ解析。フレーム数が多いので重い処理は落とす。
    static let videoFrame = VisionAnalysisPlan(
        recognizeText: true, detectBarcodes: true, detectTextRegions: true, detectRectangles: false, classifyImage: true,
        detectSaliency: false, scoreAesthetics: false, detectPeople: true,
        textRecognitionLevel: .fast
    )

    /// カメラのリアルタイム解析。1フレームあたりの予算が最も厳しい。
    static let realtime = VisionAnalysisPlan(
        recognizeText: true, detectBarcodes: true, detectTextRegions: true, detectRectangles: false, classifyImage: true,
        detectSaliency: false, scoreAesthetics: false, detectPeople: false,
        textRecognitionLevel: .fast
    )

    /// OCR のみ（仕様書 §33）。
    static let ocrOnly = VisionAnalysisPlan(
        recognizeText: true, detectBarcodes: false, detectTextRegions: true, detectRectangles: false, classifyImage: false,
        detectSaliency: false, scoreAesthetics: false, detectPeople: false,
        textRecognitionLevel: .accurate
    )

    /// バーコードのみ（仕様書 §34）。
    static let barcodeOnly = VisionAnalysisPlan(
        recognizeText: false, detectBarcodes: true, detectTextRegions: false, detectRectangles: false, classifyImage: false,
        detectSaliency: false, scoreAesthetics: false, detectPeople: false
    )

    static let classificationOnly = VisionAnalysisPlan(
        recognizeText: false, detectBarcodes: false, detectTextRegions: false, detectRectangles: false, classifyImage: true,
        detectSaliency: false, scoreAesthetics: false, detectPeople: false
    )

    static let textRectanglesOnly = VisionAnalysisPlan(
        recognizeText: false, detectBarcodes: false, detectTextRegions: true, detectRectangles: false, classifyImage: false,
        detectSaliency: false, scoreAesthetics: false, detectPeople: false
    )

    static let rectanglesOnly = VisionAnalysisPlan(
        recognizeText: false, detectBarcodes: false, detectTextRegions: false, detectRectangles: true, classifyImage: false,
        detectSaliency: false, scoreAesthetics: false, detectPeople: false
    )

    static let facesOnly = VisionAnalysisPlan(
        recognizeText: false, detectBarcodes: false, detectTextRegions: false, detectRectangles: false, classifyImage: false,
        detectSaliency: false, scoreAesthetics: false, detectPeople: false, detectFaces: true
    )

    static let humansOnly = VisionAnalysisPlan(
        recognizeText: false, detectBarcodes: false, detectTextRegions: false, detectRectangles: false, classifyImage: false,
        detectSaliency: false, scoreAesthetics: false, detectPeople: false, detectHumans: true
    )

    static let saliencyOnly = VisionAnalysisPlan(
        recognizeText: false, detectBarcodes: false, detectTextRegions: false, detectRectangles: false, classifyImage: false,
        detectSaliency: true, scoreAesthetics: false, detectPeople: false
    )

    static let aestheticsOnly = VisionAnalysisPlan(
        recognizeText: false, detectBarcodes: false, detectTextRegions: false, detectRectangles: false, classifyImage: false,
        detectSaliency: false, scoreAesthetics: true, detectPeople: false
    )

    /// 実行した Vision リクエスト名（画面の Used APIs / Debug 表示用）。
    var requestNames: [String] {
        var names: [String] = []
        if recognizeText { names.append("RecognizeTextRequest(.\(textRecognitionLevel == .accurate ? "accurate" : "fast"))") }
        if detectBarcodes { names.append("DetectBarcodesRequest") }
        if detectTextRegions { names.append("DetectTextRectanglesRequest") }
        if detectRectangles { names.append("DetectRectanglesRequest") }
        if classifyImage { names.append("ClassifyImageRequest") }
        if detectSaliency { names.append("GenerateObjectnessBasedSaliencyImageRequest") }
        if scoreAesthetics { names.append("CalculateImageAestheticsScoresRequest") }
        if detectPeople || detectFaces { names.append("DetectFaceRectanglesRequest") }
        if detectPeople || detectHumans { names.append("DetectHumanRectanglesRequest") }
        return names
    }
}

// MARK: - Source

/// Vision に渡せる入力。CGImage / CVPixelBuffer は Sendable ではないので箱に入れて運ぶ。
nonisolated enum VisionSource: @unchecked Sendable {
    case cgImage(CGImage, orientation: CGImagePropertyOrientation?)
    case pixelBuffer(CVPixelBuffer, orientation: CGImagePropertyOrientation?)

    var pixelSize: CGSize {
        switch self {
        case .cgImage(let image, _):
            CGSize(width: image.width, height: image.height)
        case .pixelBuffer(let buffer, _):
            CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        }
    }
}

// MARK: - Analyzer

/// Vision リクエストを組み立てて実行する。MainActor から切り離して動かす。
nonisolated struct VisionAnalyzer: Sendable {

    init() {}

    func analyze(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation? = nil,
        plan: VisionAnalysisPlan = .full,
        timestamp: TimeInterval? = nil,
        thumbnail: CGImage? = nil
    ) async throws -> FrameAnalysis {
        try await analyze(
            source: .cgImage(cgImage, orientation: orientation),
            plan: plan,
            timestamp: timestamp,
            thumbnail: thumbnail.map { ImageBox(cgImage: $0) }
        )
    }

    func analyze(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation? = nil,
        plan: VisionAnalysisPlan = .realtime,
        timestamp: TimeInterval? = nil
    ) async throws -> FrameAnalysis {
        try await analyze(
            source: .pixelBuffer(pixelBuffer, orientation: orientation),
            plan: plan,
            timestamp: timestamp,
            thumbnail: nil
        )
    }

    func analyze(
        source: VisionSource,
        plan: VisionAnalysisPlan,
        timestamp: TimeInterval? = nil,
        thumbnail: ImageBox? = nil
    ) async throws -> FrameAnalysis {
        try Task.checkCancellation()

        let started = Date()
        var analysis = FrameAnalysis(timestamp: timestamp, imageSize: source.pixelSize, thumbnail: thumbnail)
        var failures: [(request: String, reason: String)] = []

        // 各リクエストは独立して実行する。
        // 実行環境によって使えないリクエストがある（Simulator の DetectBarcodesRequest など）ため、
        // 1つ失敗しても解析全体を落とさず、失敗したリクエスト名を残す。
        if plan.recognizeText {
            var request = RecognizeTextRequest()
            request.recognitionLevel = plan.textRecognitionLevel
            request.automaticallyDetectsLanguage = true
            request.usesLanguageCorrection = plan.textRecognitionLevel == .accurate
            // 薬剤名などのドメイン語を優先的に拾わせる（仕様書 §74 デモデータ）。
            request.customWords = DemoData.drugNames
            if let failure = try await attempt("RecognizeTextRequest", {
                let observations = try await perform(request, on: source)
                analysis.texts = observations.compactMap { observation in
                    let transcript = observation.transcript
                    guard !transcript.isEmpty else { return nil }
                    return DetectedText(
                        text: transcript,
                        confidence: observation.confidence,
                        boundingBox: observation.boundingBox.cgRect,
                        isTitle: observation.isTitle,
                        languages: observation.recognitionLanguages.map(\.maximalIdentifier)
                    )
                }
            }) { failures.append(failure) }
        }

        if plan.detectBarcodes {
            if let failure = try await attempt("DetectBarcodesRequest", {
                let observations = try await perform(DetectBarcodesRequest(), on: source)
                analysis.barcodes = observations.compactMap { observation in
                    let payload = observation.payloadString
                        ?? observation.payloadData.map { $0.base64EncodedString() }
                    guard let payload, !payload.isEmpty else { return nil }
                    return DetectedBarcode(
                        payload: payload,
                        symbology: String(describing: observation.symbology),
                        boundingBox: observation.boundingBox.cgRect,
                        isGS1DataCarrier: observation.isGS1DataCarrier
                    )
                }
            }) { failures.append(failure) }
        }

        if plan.detectTextRegions {
            if let failure = try await attempt("DetectTextRectanglesRequest", {
                let observations = try await perform(DetectTextRectanglesRequest(), on: source)
                analysis.textRegions = observations.map {
                    DetectedRegion(kind: "TextRegion", boundingBox: $0.boundingBox.cgRect)
                }
            }) { failures.append(failure) }
        }

        if plan.detectRectangles {
            if let failure = try await attempt("DetectRectanglesRequest", {
                let observations = try await perform(DetectRectanglesRequest(), on: source)
                analysis.rectangles = observations.map {
                    DetectedRegion(kind: "Rectangle", boundingBox: $0.boundingBox.cgRect)
                }
            }) { failures.append(failure) }
        }

        if plan.classifyImage {
            if let failure = try await attempt("ClassifyImageRequest", {
                let observations = try await perform(ClassifyImageRequest(), on: source)
                analysis.labels = observations
                    .filter { $0.hasMinimumPrecision(0.2, forRecall: 0.3) }
                    .sorted { $0.confidence > $1.confidence }
                    .prefix(8)
                    .map { DetectedLabel(identifier: $0.identifier, confidence: $0.confidence) }
            }) { failures.append(failure) }
        }

        if plan.detectSaliency {
            if let failure = try await attempt("GenerateObjectnessBasedSaliencyImageRequest", {
                let observation = try await perform(GenerateObjectnessBasedSaliencyImageRequest(), on: source)
                analysis.salientObjects = observation.salientObjects.map { $0.boundingBox.cgRect }
            }) { failures.append(failure) }
        }

        if plan.scoreAesthetics {
            if let failure = try await attempt("CalculateImageAestheticsScoresRequest", {
                let observation = try await perform(CalculateImageAestheticsScoresRequest(), on: source)
                analysis.aestheticsScore = observation.overallScore
                analysis.isUtilityImage = observation.isUtility
            }) { failures.append(failure) }
        }

        if plan.detectPeople || plan.detectFaces {
            if let failure = try await attempt("DetectFaceRectanglesRequest", {
                let observations = try await perform(DetectFaceRectanglesRequest(), on: source)
                analysis.faceRectangles = observations.map {
                    DetectedRegion(kind: "Face", boundingBox: $0.boundingBox.cgRect)
                }
                analysis.faceCount = analysis.faceRectangles.count
            }) { failures.append(failure) }
        }

        if plan.detectPeople || plan.detectHumans {
            if let failure = try await attempt("DetectHumanRectanglesRequest", {
                let observations = try await perform(DetectHumanRectanglesRequest(), on: source)
                analysis.humanRectangles = observations.map {
                    DetectedRegion(kind: "Human", boundingBox: $0.boundingBox.cgRect)
                }
                analysis.humanCount = analysis.humanRectangles.count
            }) { failures.append(failure) }
        }

        analysis.unavailableRequests = failures
        analysis.visionElapsed = Date().timeIntervalSince(started)
        return analysis
    }

    /// 1つの Vision リクエストを実行する。実行環境の都合で使えないリクエストは
    /// throw せず失敗の内容を返し、解析全体は続行する。
    ///
    /// ただし Task 自体が中断された場合だけは例外で、呼び出し側へ投げ返す。
    /// 中断を「失敗なし・検出0件」として飲み込むと、中身が空の FrameAnalysis が
    /// 「特徴の無い画像」と区別できなくなるため。
    private func attempt(
        _ name: String,
        _ body: () async throws -> Void
    ) async throws -> (request: String, reason: String)? {
        do {
            try await body()
            return nil
        } catch {
            // Vision は中断時に CancellationError ではなく requestCancelled を投げる。
            // どちらの形で来ても中断として扱う。
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            return (request: name, reason: "\(error)")
        }
    }

    // MARK: - Generic perform

    /// ImageProcessingRequest は associatedtype Result を持つので、existential ではなくジェネリクスで受ける。
    private func perform<R: ImageProcessingRequest>(_ request: R, on source: VisionSource) async throws -> R.Result {
        switch source {
        case .cgImage(let image, let orientation):
            try await request.perform(on: image, orientation: orientation)
        case .pixelBuffer(let buffer, let orientation):
            try await request.perform(on: buffer, orientation: orientation)
        }
    }
}

// MARK: - Multi-frame digest helpers

extension Array where Element == FrameAnalysis {
    /// 動画のように複数フレームある場合の、画面の Vision Raw Result 用テキスト。
    /// 実行できなかったリクエストの一覧も含むので、モデルへは videoObservationDigest を渡す。
    var videoDigest: String {
        enumerated().map { index, frame in
            "--- Frame \(index + 1) (\(frame.timestampText)) ---\n\(frame.digest)"
        }
        .joined(separator: "\n\n")
    }

    /// モデルへ渡す時系列ダイジェスト。実行できなかったリクエストの一覧は含めない。
    /// 観測が1件も無いフレームは落とし、全滅なら空文字を返す。
    var videoObservationDigest: String {
        enumerated().compactMap { index, frame -> String? in
            let observations = frame.observationDigest
            guard !observations.isEmpty else { return nil }
            return "--- Frame \(index + 1) (\(frame.timestampText)) ---\n\(observations)"
        }
        .joined(separator: "\n\n")
    }

    /// 全フレームを通して読み取れた文字（重複を除く）。
    var uniqueTexts: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for frame in self {
            for text in frame.texts where !seen.contains(text.text) {
                seen.insert(text.text)
                result.append(text.text)
            }
        }
        return result
    }

    /// 全フレームを通したラベルを平均信頼度順に集約。
    var aggregatedLabels: [DetectedLabel] {
        var totals: [String: (sum: Float, count: Int)] = [:]
        for frame in self {
            for label in frame.labels {
                let current = totals[label.identifier] ?? (0, 0)
                totals[label.identifier] = (current.sum + label.confidence, current.count + 1)
            }
        }
        return totals
            .map { DetectedLabel(identifier: $0.key, confidence: $0.value.sum / Float($0.value.count)) }
            .sorted { $0.confidence > $1.confidence }
    }

    var uniqueBarcodes: [DetectedBarcode] {
        var seen = Set<String>()
        var result: [DetectedBarcode] = []
        for frame in self {
            for barcode in frame.barcodes where !seen.contains(barcode.payload) {
                seen.insert(barcode.payload)
                result.append(barcode)
            }
        }
        return result
    }

    var totalVisionElapsed: TimeInterval { reduce(0) { $0 + $1.visionElapsed } }
}
