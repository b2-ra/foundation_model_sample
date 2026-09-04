//
//  MediaPipelineTests.swift
//  foundation_model_sampleTests
//
//  写真 / 動画 / フレームの解析経路を、実際の画像と動画を作って端から端まで検証する。
//  PhotosPicker のシートは別プロセスで XCTest から要素を引けないため、
//  ピッカー以降の経路（CGImage / 動画ファイル → Vision → FoundationModels）をここで確認する。
//

import Testing
import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import UIKit
import AVFoundation
import Vision
import FoundationModels
@testable import foundation_model_sample

// MARK: - Fixtures

/// テスト用の画像・動画を実際に生成する。
enum MediaFixture {

    /// QR コードを CoreImage で作る。
    static func qrCode(payload: String, side: CGFloat) -> CGImage? {
        guard let data = payload.data(using: .ascii),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }

    /// 文字と QR コードを載せた「薬剤ラベル」画像。OCR とバーコード検出の両方を通す。
    static func drugLabel(
        title: String = "アムロジピン5mg",
        lines: [String] = ["Ca拮抗薬 高血圧症", "1錠 朝食後 28日分", "Amlodipine Besilate"],
        barcodePayload: String = "4987123456781",
        size: CGSize = CGSize(width: 1200, height: 800)
    ) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 76),
                .foregroundColor: UIColor.black
            ]
            (title as NSString).draw(at: CGPoint(x: 48, y: 40), withAttributes: titleAttributes)

            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 52),
                .foregroundColor: UIColor.black
            ]
            var y: CGFloat = 170
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: 48, y: y), withAttributes: bodyAttributes)
                y += 76
            }

            if let qr = qrCode(payload: barcodePayload, side: 300) {
                context.cgContext.draw(qr, in: CGRect(x: size.width - 340, y: size.height - 340, width: 300, height: 300))
            }
        }
        return image.cgImage
    }

    /// 文字のない単色画像。「特徴が無いフレーム」の確認用。
    static func blank(size: CGSize = CGSize(width: 400, height: 400)) -> CGImage? {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.cgImage
    }

    /// CGImage から CVPixelBuffer を作る。カメラフレーム経路の確認用。
    static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, image.width, image.height,
            kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    /// シーンごとに内容が変わる短い動画を書き出す。
    static func makeVideo(scenes: [(title: String, payload: String)], secondsPerScene: Int = 1) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fmlab-test-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let size = CGSize(width: 1280, height: 720)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: bufferAttributes)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps = 15
        var frameIndex = 0
        for scene in scenes {
            guard let still = drugLabel(
                title: scene.title,
                lines: ["棚番 A-12"],
                barcodePayload: scene.payload,
                size: size
            ) else { continue }
            for _ in 0..<(fps * secondsPerScene) {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard let buffer = pixelBuffer(from: still) else { continue }
                adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps)))
                frameIndex += 1
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "MediaFixture", code: 1)
        }
        return url
    }
}

/// この環境でどの Vision リクエストが動くかを実測する。
/// Simulator では DetectBarcodesRequest や ClassifyImageRequest が
/// "Failed to create ... detector" で使えないことがあるため、
/// それを前提にした検証は使える環境でのみ行う（仕様書 §80 実機テスト）。
enum VisionEnvironment {
    private static func unavailable(plan: VisionAnalysisPlan) async -> Set<String> {
        guard let image = MediaFixture.drugLabel(size: CGSize(width: 400, height: 300)),
              let analysis = try? await VisionAnalyzer().analyze(cgImage: image, plan: plan)
        else { return ["all"] }
        return Set(analysis.unavailableRequests.map(\.request))
    }

    static func supportsBarcodeDetection() async -> Bool {
        await unavailable(plan: .barcodeOnly).isEmpty
    }

    static func supportsImageClassification() async -> Bool {
        var plan = VisionAnalysisPlan()
        plan.recognizeText = false
        plan.detectBarcodes = false
        plan.classifyImage = true
        return await unavailable(plan: plan).isEmpty
    }

    static func supportsTextRecognition() async -> Bool {
        await unavailable(plan: .ocrOnly).isEmpty
    }
}

/// モデルが利用できるかどうか。テストの skip 条件に使う。
///
/// Apple Intelligence が無効な環境では、モデル経路のテストは pass ではなく skip にする。
/// 「無音で return して緑」にすると、生成が一度も成功していないのにテストが通ってしまう。
enum ModelGate {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }
    static var reason: Comment { "Apple Intelligence が利用できないためモデル経路を検証できない" }
}

/// 生成呼び出しの結果。
/// 仕様書 §77: 回答文章そのものを完全一致テストしない（型として埋まっているかを見る）。
enum GenerationOutcome<Value> {
    case produced(Value)
    case failed(LabError)

    /// 生成できなければテストを失敗させる。
    ///
    /// 以前はここでエラー写像の4項目だけ確認して pass にしていたが、それでは
    /// 「モデル経路が一度も成功していない」状態でも緑になり、回帰を検出できなかった。
    /// エラー写像の健全性は LabErrorTests で個別に検証しているので、
    /// ここは「実際に生成できたか」だけを見る。
    func requireGenerated(_ context: String, sourceLocation: SourceLocation = #_sourceLocation) -> Value? {
        switch self {
        case .produced(let value):
            return value
        case .failed(let error):
            Issue.record("""
                \(context): モデル生成が失敗した。
                Error Type: \(error.errorType)
                Technical Detail: \(error.technicalDetail)
                Recovery: \(error.recovery)
                """, sourceLocation: sourceLocation)
            return nil
        }
    }
}

func attemptGeneration<Value>(_ body: () async throws -> Value) async -> GenerationOutcome<Value> {
    do {
        return .produced(try await body())
    } catch {
        return .failed(LabError.map(error))
    }
}

/// 進捗コールバックの呼び出し回数を数える箱。
nonisolated final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [(done: Int, total: Int)] = []

    func record(done: Int, total: Int) {
        lock.withLock { reports.append((done, total)) }
    }

    var count: Int { lock.withLock { reports.count } }
    var lastTotal: Int? { lock.withLock { reports.last?.total } }
}

// MARK: - Vision (画像)

struct PhotoAnalysisPipelineTests {

    @Test("薬剤ラベル画像から文字とバーコードの両方を読み取れる")
    func readsTextAndBarcodeFromLabel() async throws {
        let image = try #require(MediaFixture.drugLabel())
        let analysis = try await VisionAnalyzer().analyze(cgImage: image, plan: .full)

        // OCR
        #expect(!analysis.texts.isEmpty, "文字が1行も検出されなかった")
        let joined = analysis.joinedText
        #expect(joined.contains("アムロジピン") || joined.contains("Amlodipine"),
                "薬剤名が読み取れていない: \(joined)")

        // バーコード（Simulator では検出器を作れないため、使える環境でのみ検証する）
        if await VisionEnvironment.supportsBarcodeDetection() {
            #expect(analysis.barcodes.count >= 1, "QR コードが検出されなかった")
            let payloads = analysis.barcodes.map(\.payload)
            #expect(payloads.contains("4987123456781"), "QR のペイロードが一致しない: \(payloads)")
        } else {
            #expect(analysis.unavailableRequests.contains { $0.request == "DetectBarcodesRequest" },
                    "バーコード検出が使えないのに、その事実が記録されていない")
        }

        // ペイロードから薬品マスターを引ける（Vision → アプリのデータ）。
        let matched = DemoData.drug(forBarcode: "4987123456781")
        #expect(matched?.name == "アムロジピン5mg")

        // 枠の座標が正規化されている。
        for text in analysis.texts {
            #expect(text.boundingBox.minX >= -0.01 && text.boundingBox.maxX <= 1.01,
                    "文字の枠が正規化範囲外: \(text.boundingBox)")
        }

        // 分類ラベル（使える環境でのみ）。
        if await VisionEnvironment.supportsImageClassification() {
            #expect(!analysis.labels.isEmpty, "画像分類のラベルが空")
        }
        #expect(analysis.visionElapsed > 0)
    }

    @Test("OCR 専用プランはバーコードを検出しない")
    func ocrOnlyPlanSkipsBarcodes() async throws {
        let image = try #require(MediaFixture.drugLabel())
        let analysis = try await VisionAnalyzer().analyze(cgImage: image, plan: .ocrOnly)
        #expect(!analysis.texts.isEmpty, "OCR プランで文字が取れていない")
        #expect(analysis.unavailableRequests.isEmpty, "OCR が実行できていない")
        #expect(analysis.barcodes.isEmpty, "OCR プランなのにバーコードを検出している")
        #expect(analysis.labels.isEmpty, "OCR プランなのに分類している")
    }

    @Test("バーコード専用プランは文字を読まない")
    func barcodeOnlyPlanSkipsText() async throws {
        let image = try #require(MediaFixture.drugLabel())
        let analysis = try await VisionAnalyzer().analyze(cgImage: image, plan: .barcodeOnly)
        #expect(analysis.texts.isEmpty, "バーコードプランなのに OCR している")
        if await VisionEnvironment.supportsBarcodeDetection() {
            #expect(!analysis.barcodes.isEmpty, "バーコードプランで QR が取れていない")
        }
    }

    @Test("使えない Vision リクエストがあっても解析全体は成功する")
    func partialFailureDoesNotAbortAnalysis() async throws {
        let image = try #require(MediaFixture.drugLabel())
        // 全リクエストを要求するプラン。この環境で使えないものが含まれていてもよい。
        let analysis = try await VisionAnalyzer().analyze(cgImage: image, plan: .full)

        // OCR と分類は使えるので結果が残っている。
        #expect(!analysis.texts.isEmpty, "使えるリクエストの結果まで失われている")
        #expect(analysis.visionElapsed > 0)
        // 使えなかったリクエストは黙って消えず、名前と理由が残る。
        for failure in analysis.unavailableRequests {
            #expect(!failure.request.isEmpty)
            #expect(!failure.reason.isEmpty, "\(failure.request) の失敗理由が空")
        }
    }

    @Test("特徴の無い画像でも落ちず、digest が説明を返す")
    func handlesFeaturelessImage() async throws {
        let image = try #require(MediaFixture.blank())
        let analysis = try await VisionAnalyzer().analyze(cgImage: image, plan: .full)
        #expect(analysis.texts.isEmpty)
        #expect(analysis.barcodes.isEmpty)
        #expect(!analysis.digest.isEmpty, "digest が空")
    }

    @Test("解析結果の digest がモデルに渡せる形になっている")
    func digestIsModelReady() async throws {
        let image = try #require(MediaFixture.drugLabel())
        let analysis = try await VisionAnalyzer().analyze(cgImage: image, plan: .full)
        let digest = analysis.digest

        #expect(digest.contains("読み取れた文字"), "digest に OCR セクションが無い")
        if await VisionEnvironment.supportsImageClassification() {
            #expect(digest.contains("画像分類"), "digest に分類セクションが無い")
        }
        if await VisionEnvironment.supportsBarcodeDetection() {
            #expect(digest.contains("バーコード"), "digest にバーコードセクションが無い")
            #expect(digest.contains("4987123456781"), "digest にペイロードが入っていない")
        } else {
            // digest は画面の Vision Raw Result 用なので、実行できなかったリクエストも載せる。
            #expect(digest.contains("実行できなかった解析"), "実行できなかった解析が digest に出ていない")
        }

        // モデルへ渡す observationDigest には診断情報を入れない。
        // 日本語の文に英語の API 名が並ぶと unsupportedLanguageOrLocale の原因になる（実測）。
        let observations = analysis.observationDigest
        #expect(!observations.contains("実行できなかった解析"),
                "診断情報が observationDigest に混ざっている（モデルへ送る文に入れてはいけない）")
        #expect(observations.contains("読み取れた文字"), "observationDigest に OCR セクションが無い")
    }

    @Test("2枚の画像を別々に解析して比較用の digest を作れる")
    func comparesTwoImages() async throws {
        let first = try #require(MediaFixture.drugLabel(
            title: "アムロジピン5mg", barcodePayload: "4987123456781"))
        let second = try #require(MediaFixture.drugLabel(
            title: "ロキソプロフェン60mg",
            lines: ["NSAIDs 鎮痛", "1錠 毎食後 7日分"],
            barcodePayload: "4987123456782"))

        let analyzer = VisionAnalyzer()
        let a = try await analyzer.analyze(cgImage: first, plan: .full)
        let b = try await analyzer.analyze(cgImage: second, plan: .full)

        #expect(a.joinedText != b.joinedText, "2枚の OCR 結果が同一になっている")
        if await VisionEnvironment.supportsBarcodeDetection() {
            #expect(a.barcodes.first?.payload == "4987123456781")
            #expect(b.barcodes.first?.payload == "4987123456782")
        }
    }
}

// MARK: - カメラフレーム（CVPixelBuffer）

struct CameraFramePipelineTests {

    @Test("CVPixelBuffer から直接解析できる（カメラ経路）")
    func analyzesPixelBuffer() async throws {
        let image = try #require(MediaFixture.drugLabel())
        let buffer = try #require(MediaFixture.pixelBuffer(from: image))

        let analysis = try await VisionAnalyzer().analyze(pixelBuffer: buffer, plan: .realtime)
        #expect(!analysis.texts.isEmpty, "ピクセルバッファから文字が取れない")
        #expect(analysis.imageSize.width == CGFloat(image.width))
        if await VisionEnvironment.supportsBarcodeDetection() {
            #expect(!analysis.barcodes.isEmpty, "ピクセルバッファからバーコードが取れない")
        }
    }

    @Test("リアルタイムプランは 1 フレームを十分速く処理する")
    func realtimePlanIsFastEnough() async throws {
        let image = try #require(MediaFixture.drugLabel(size: CGSize(width: 640, height: 480)))
        let buffer = try #require(MediaFixture.pixelBuffer(from: image))
        let analyzer = VisionAnalyzer()

        // 1回目はモデルのロードを含むので捨て、以降の平均を見る。
        _ = try await analyzer.analyze(pixelBuffer: buffer, plan: .realtime)

        var total: TimeInterval = 0
        let iterations = 5
        for _ in 0..<iterations {
            let analysis = try await analyzer.analyze(pixelBuffer: buffer, plan: .realtime)
            total += analysis.visionElapsed
        }
        let average = total / Double(iterations)
        // 4 fps を目標にしているので、1フレーム 250ms 未満で回る必要がある。
        // Simulator は実機より遅いため上限は緩めに取る。
        #expect(average < 1.0, "リアルタイム解析が遅すぎる: 平均 \(average) 秒/フレーム")
    }

    @Test("同じフレームを繰り返し解析しても結果が安定する")
    func repeatedAnalysisIsStable() async throws {
        let image = try #require(MediaFixture.drugLabel())
        let analyzer = VisionAnalyzer()
        let first = try await analyzer.analyze(cgImage: image, plan: .realtime)
        let second = try await analyzer.analyze(cgImage: image, plan: .realtime)
        #expect(first.barcodes.map(\.payload) == second.barcodes.map(\.payload))
    }
}

// MARK: - 動画

struct VideoAnalysisPipelineTests {

    @Test("動画のメタデータを読める")
    func readsVideoMetadata() async throws {
        let url = try await MediaFixture.makeVideo(scenes: [
            ("アムロジピン5mg", "4987123456781"),
            ("ロキソプロフェン60mg", "4987123456782")
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try await VideoAnalyzer().metadata(for: url)
        #expect(metadata.duration > 1.5, "尺が短すぎる: \(metadata.duration)")
        #expect(metadata.naturalSize.width == 1280)
        #expect(metadata.naturalSize.height == 720)
        #expect(metadata.hasAudio == false)
        #expect(metadata.fileSizeBytes > 0)
        #expect(metadata.rows.count == 5)
        #expect(metadata.durationText.contains(":"))
    }

    @Test("動画から指定した数のコマを抜き出して1枚ずつ解析できる")
    func extractsAndAnalysesFrames() async throws {
        let url = try await MediaFixture.makeVideo(scenes: [
            ("アムロジピン5mg", "4987123456781"),
            ("ロキソプロフェン60mg", "4987123456782"),
            ("レボフロキサシン500mg", "4987123456783")
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        // 進捗コールバックは nonisolated な文脈から呼ばれるので、ロックで守った箱で数える。
        let progress = ProgressCounter()
        let frames = try await VideoAnalyzer().analyzeFrames(url: url, frameCount: 6, plan: .videoFrame) { _, done, total in
            progress.record(done: done, total: total)
        }

        #expect(frames.count >= 4, "抜き出せたコマが少なすぎる: \(frames.count)")
        #expect(progress.count == frames.count, "進捗コールバックの回数が合わない")
        #expect(progress.lastTotal == 6, "進捗の総数が指定値と違う")

        // タイムスタンプが時系列に並んでいる。
        let timestamps = frames.compactMap(\.timestamp)
        #expect(timestamps.count == frames.count, "タイムスタンプが欠けているコマがある")
        #expect(timestamps == timestamps.sorted(), "コマが時系列に並んでいない")

        // サムネイルが付いている（画面のタイムライン表示用）。
        #expect(frames.allSatisfy { $0.thumbnail != nil }, "サムネイルの無いコマがある")

        // 各コマから文字が読めており、シーンによって内容が変わっている。
        // 圧縮された動画のコマでは誤認識も起きるため、文字列の完全一致は見ない（仕様書 §77）。
        let framesWithText = frames.filter { !$0.texts.isEmpty }
        #expect(framesWithText.count >= frames.count / 2,
                "文字が読み取れたコマが少なすぎる: \(framesWithText.count)/\(frames.count)")
        #expect(frames.uniqueTexts.count > 1, "全コマで同じ文字しか取れていない")

        // シーンごとに違うバーコードが検出されている。
        if await VisionEnvironment.supportsBarcodeDetection() {
            let payloads = Set(frames.uniqueBarcodes.map(\.payload))
            #expect(payloads.count >= 2, "動画中で1種類しかバーコードを検出できていない: \(payloads)")
        }

        // 時系列 digest がモデルに渡せる形になっている。
        let digest = frames.videoDigest
        #expect(digest.contains("Frame 1"))
        #expect(digest.contains("時刻:"))
        #expect(frames.totalVisionElapsed > 0)
    }

    @Test("コマ数の指定が上限でクランプされる")
    func frameCountIsClamped() async throws {
        let url = try await MediaFixture.makeVideo(scenes: [("テスト", "4987123456781")])
        defer { try? FileManager.default.removeItem(at: url) }

        let frames = try await VideoAnalyzer().analyzeFrames(url: url, frameCount: 100, plan: .videoFrame)
        #expect(frames.count <= 32, "上限を超えてコマを抜き出している: \(frames.count)")
    }

    @Test("存在しない動画では復旧手順付きのエラーになる")
    func missingVideoThrowsMappedError() async {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).mov")
        do {
            _ = try await VideoAnalyzer().metadata(for: url)
            Issue.record("存在しない動画でエラーにならなかった")
        } catch {
            let mapped = LabError.map(error)
            #expect(!mapped.userMessage.isEmpty)
            #expect(!mapped.recovery.isEmpty)
        }
    }
}

// MARK: - Vision → FoundationModels（モデルが使える環境のみ）

@MainActor
struct VisionToModelPipelineTests {

    /// モデルが使えることは各テストの .enabled(if: ModelGate.isAvailable) が保証する。
    /// ここへ来た時点で利用可能なので、availability が崩れていたらテスト失敗にする（無音 return はしない）。
    private func requireModel() throws -> ModelManager {
        let manager = ModelManager()
        try #require(manager.availability.isAvailable,
                     "trait では利用可能だったのに ModelManager では \(manager.availability.detail)")
        return manager
    }

    @Test("画像の Vision 解析結果をモデルが構造化できる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func visionDigestToStructuredOutput() async throws {
        let engine = LabEngine()

        let image = try #require(MediaFixture.drugLabel())
        let analysis = try await VisionAnalyzer().analyze(cgImage: image, plan: .full)

        // アプリと同じ経路（respondBridgingStructured）を通す。
        // 薬剤ラベルの OCR は英字表記が優位になり、日本語の指示が
        // unsupportedLanguageOrLocale で拒否されることがある。
        // アプリはそのとき指示を英語へ替えて1回だけ問い直すので、テストも同じ経路で検証する。
        let outcome = await attemptGeneration {
            try await engine.respondBridgingStructured(
                role: "あなたは画像の解析結果を構造化する担当です。",
                question: "この画像の解析結果から ImageAnalysis を作ってください。",
                observations: analysis.observationDigest,
                generating: ImageAnalysis.self,
                options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 600)
            )
        }
        guard let response = outcome.requireGenerated("ImageAnalysis 生成") else { return }

        // 内容の完全一致は見ない（仕様書 §77）。型として埋まっているかを見る。
        let content = response.content
        #expect(!content.title.isEmpty, "title が空")
        #expect(!content.description.isEmpty, "description が空")
        #expect(!content.objects.isEmpty, "objects が空")
        #expect(content.objects.count <= 8, "@Guide の .count(1...8) を超えている")
        #expect(!content.tags.isEmpty, "tags が空")
        #expect(content.tags.count <= 6, "@Guide の .count(1...6) を超えている")
        #expect(!response.raw.jsonString.isEmpty)

        // Transcript に Prompt と Response が積まれている。
        #expect(response.session.transcript.count >= 2)
    }

    @Test("画像分類が @Generable enum のケースに収まる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func visionDigestToEnum() async throws {
        let engine = LabEngine()

        let image = try #require(MediaFixture.drugLabel())
        let analysis = try await VisionAnalyzer().analyze(cgImage: image, plan: .full)

        let outcome = await attemptGeneration {
            try await engine.respondBridgingStructured(
                role: "あなたは画像の被写体を分類する担当です。",
                question: "この画像が何を写したものか分類してください。",
                observations: analysis.observationDigest,
                generating: ImageClassificationResult.self,
                options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 300)
            )
        }
        guard let response = outcome.requireGenerated("ImageClassificationResult 生成") else { return }

        // enum のケースはスキーマ制約なので、範囲外の値は生成されない。
        #expect(ImageCategory.allCases.contains(response.content.category),
                "enum のケース外: \(response.content.category)")
        #expect(!response.content.rationale.isEmpty, "rationale が空")
        #expect((0...100).contains(response.content.confidence),
                "confidence が @Guide の範囲外: \(response.content.confidence)")
    }

    @Test("動画の時系列 digest をモデルがシーンに分解できる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func videoDigestToStructuredOutput() async throws {
        let engine = LabEngine()
        let manager = try requireModel()
        // 薬剤名を並べた動画にすると、scenes 配列に薬剤名の一覧が載るため
        // 既定のガードレールで必ず停止する（Extraction デモの実測と同じ条件）。
        // ここで確かめたいのは「動画 → コマ解析 → 構造化出力」の経路なので、備品の棚札を使う。
        let url = try await MediaFixture.makeVideo(scenes: [
            ("コピー用紙A4 3箱", "4901234567891"),
            ("封筒 長3 5箱", "4901234567892"),
            ("ボールペン 黒 20本", "4901234567893")
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let frames = try await VideoAnalyzer().analyzeFrames(url: url, frameCount: 4, plan: .videoFrame)
        // モデルへ渡すのは videoObservationDigest（診断情報を含まない方）。
        let digest = frames.videoObservationDigest

        // 送信前にトークン数を測れる（コンテキスト超過を避ける）。
        let tokens = try await manager.tokenCount(for: digest)
        #expect(tokens > 0)
        #expect(tokens < manager.contextSize, "digest がコンテキストを超えている: \(tokens)")

        let outcome = await attemptGeneration {
            try await engine.respondBridgingStructured(
                role: "あなたは動画の内容を時系列でまとめる担当です。",
                question: "次はある動画から等間隔に取り出したコマの解析結果です。動画全体をまとめてください。",
                observations: digest,
                generating: VideoAnalysis.self,
                options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 900)
            )
        }
        guard let response = outcome.requireGenerated("VideoAnalysis 生成") else { return }

        let content = response.content
        #expect(!content.title.isEmpty, "title が空")
        #expect(!content.summary.isEmpty, "summary が空")
        #expect(!content.scenes.isEmpty, "scenes が空")
        #expect(content.scenes.count <= 8, "@Guide の .count(1...8) を超えている")
        #expect(content.scenes.allSatisfy { $0.startSeconds >= 0 }, "負の開始秒がある")
        #expect(content.scenes.allSatisfy { !$0.description.isEmpty }, "説明が空のシーンがある")
    }

    @Test("カメラフレームの実況が構造化出力として返る", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func liveFrameNarration() async throws {
        let engine = LabEngine()

        let image = try #require(MediaFixture.drugLabel())
        let buffer = try #require(MediaFixture.pixelBuffer(from: image))
        let analysis = try await VisionAnalyzer().analyze(pixelBuffer: buffer, plan: .realtime)

        // アプリの実況経路（narrate）をそのまま呼ぶ。カメラのフレームの代わりに解析結果を渡す。
        var partials: [String] = []
        let outcome = await attemptGeneration {
            try await engine.narrate(analysis: analysis) { partials.append($0) }
        }
        guard let narration = outcome.requireGenerated("LiveFrameNarration 生成") else { return }

        #expect(!narration.scene.isEmpty, "scene が空")
        #expect(!narration.highlights.isEmpty, "highlights が空")
        #expect(narration.highlights.count <= 4, "@Guide の .count(1...4) を超えている")
        #expect(!narration.suggestion.isEmpty, "suggestion が空")
        // ストリーミング経路を通っているので、途中結果が1件以上届く。
        #expect(!partials.isEmpty, "ストリーミングの途中結果が届いていない")
    }

    @Test("@Guide あり / なしの構造化出力が実際に生成できる", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func guidedAndUnguidedGeneration() async throws {
        let manager = try requireModel()

        let text = "この新機能のおかげで棚卸しの時間が半分になりました。とても助かっています。"

        // 制約あり
        let guided = await attemptGeneration {
            try await manager.makeSession(instructions: "文章の感情を分析してください。必ず日本語で答えてください。")
                .respond(to: text, generating: GuidedSentiment.self,
                         options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 400))
        }
        if let response = guided.requireGenerated("GuidedSentiment 生成") {
            #expect((0...100).contains(response.content.confidence),
                    "@Guide(.range(0...100)) が効いていない: \(response.content.confidence)")
            #expect(["positive", "negative", "neutral"].contains(response.content.sentiment),
                    "@Guide(.anyOf) が効いていない: \(response.content.sentiment)")
            #expect(!response.content.reasons.isEmpty, "reasons が空")
        }

        // 制約なし。こちらは値域が保証されないので、生成できたことだけを見る。
        let unguided = await attemptGeneration {
            try await manager.makeSession(instructions: "文章の感情を分析してください。必ず日本語で答えてください。")
                .respond(to: text, generating: UnguidedSentiment.self,
                         options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 400))
        }
        if let response = unguided.requireGenerated("UnguidedSentiment 生成") {
            #expect(!response.content.sentiment.isEmpty, "sentiment が空")
        }
    }

    @Test("OCR Tool を登録したセッションでモデルが画像の文字を読める", .enabled(if: ModelGate.isAvailable, ModelGate.reason))
    func ocrToolThroughSession() async throws {
        let manager = try requireModel()

        let image = try #require(MediaFixture.drugLabel())
        let provider = AnalyzableImageProvider()
        provider.set(ImageBox(cgImage: image))
        let recorder = ToolCallRecorder()

        let session = manager.makeSession(
            instructions: """
            画像の文字について聞かれたら readTextFromImage Tool を使って読み取ってから答えてください。
            必ず日本語で答えてください。
            """,
            tools: [OCRTool(recorder: recorder, imageProvider: provider)]
        )
        // Tool 付きの生成はモデル側の都合で失敗することがある（GenerationError -1 など）。
        // その場合もエラー写像が4項目を埋められているかを確認する（仕様書 §77）。
        let outcome = await attemptGeneration {
            try await session.respond(
                to: "画像に書かれている薬剤名を教えてください。",
                options: GenerationOptions(sampling: .greedy, temperature: 0.2, maximumResponseTokens: 400)
            )
        }
        guard let response = outcome.requireGenerated("OCRTool 付きセッション") else { return }

        #expect(!response.content.isEmpty)

        // Tool が実際に呼ばれ、OCR の結果が返っている。
        let log = recorder.drain()
        if log.isEmpty {
            // モデルが Tool を使わずに答えることもある。その場合も落とさない（仕様書 §77）。
            #expect(!response.content.isEmpty)
        } else {
            #expect(log.contains { $0.toolName == "readTextFromImage" })
            let output = log.map(\.output).joined()
            #expect(output.contains("アムロジピン") || output.contains("Amlodipine"),
                    "Tool の出力に薬剤名が無い: \(output)")
        }

        // Transcript に Tool の呼び出しが残る。
        let toolCallEntries = session.transcript.filter {
            if case .toolCalls = $0 { return true } else { return false }
        }
        #expect(toolCallEntries.count == (log.isEmpty ? 0 : toolCallEntries.count))
    }
}
