//
//  CameraController.swift
//  Foundation Models Lab
//
//  仕様書 §35 DEMO 27 Camera Frame: AVFoundation から CVPixelBuffer を取得し、
//  「Analyze Current Frame」で押した瞬間のフレームだけをモデルへ渡す。
//
//  加えて、Vision による連続フレーム解析（リアルタイム）を用意した。
//  Vision は毎フレーム走らせても実用的だが、言語モデルの呼び出しは重いので
//  一定間隔でしか行わない。この2段構えを画面上で可視化する。
//

import Foundation
@preconcurrency import AVFoundation
import CoreVideo
import CoreImage
import CoreGraphics
import UIKit
import SwiftUI

// MARK: - Frame box

/// キャプチャ出力から受け取った最新フレームを保持する箱。
/// キャプチャは専用キュー、読み出しは MainActor なのでロックで守る。
nonisolated final class LatestFrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?
    private var orientation: CGImagePropertyOrientation = .up
    private var receivedCount = 0
    private var lastReceivedAt: Date?

    func store(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        lock.withLock {
            self.buffer = buffer
            self.orientation = orientation
            receivedCount += 1
            lastReceivedAt = Date()
        }
    }

    func latest() -> (buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation)? {
        lock.withLock {
            guard let buffer else { return nil }
            return (buffer, orientation)
        }
    }

    var frameCount: Int { lock.withLock { receivedCount } }

    func reset() {
        lock.withLock {
            buffer = nil
            receivedCount = 0
            lastReceivedAt = nil
        }
    }
}

// MARK: - Capture delegate

private final class FrameCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let box: LatestFrameBox

    init(box: LatestFrameBox) {
        self.box = box
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        box.store(pixelBuffer, orientation: .up)
    }
}

// MARK: - Camera state

enum CameraState: Equatable, Sendable {
    case idle
    case unsupported(String)
    case denied
    case starting
    case running
    case failed(String)

    var isRunning: Bool { self == .running }

    var message: String? {
        switch self {
        case .idle: nil
        case .unsupported(let reason): reason
        case .denied: "カメラの利用が許可されていません。設定アプリから許可してください。"
        case .starting: "カメラを起動しています…"
        case .running: nil
        case .failed(let reason): reason
        }
    }
}

// MARK: - Controller

/// カメラセッションと、Vision によるリアルタイム解析ループを持つ。
@Observable
final class CameraController {
    private(set) var state: CameraState = .idle
    /// 直近フレームの Vision 解析結果。オーバーレイ描画に使う。
    private(set) var liveAnalysis: FrameAnalysis?
    /// 連続解析の実測値。
    private(set) var analyzedFrameCount = 0
    private(set) var measuredAnalysisFPS: Double = 0
    private(set) var lastVisionElapsed: TimeInterval = 0
    private(set) var isAnalyzing = false

    /// 1秒あたり何回 Vision を走らせるか。
    var targetAnalysisFPS: Double = 4
    var plan: VisionAnalysisPlan = .realtime
    var position: AVCaptureDevice.Position = .back

    nonisolated let session = AVCaptureSession()
    nonisolated private let frameBox = LatestFrameBox()
    nonisolated private let output = AVCaptureVideoDataOutput()
    nonisolated private let queue = DispatchQueue(label: "jp.example.FoundationModelsLab.capture")
    nonisolated private let analyzer = VisionAnalyzer()
    private var delegate: FrameCaptureDelegate?
    private var analysisTask: Task<Void, Never>?
    private var configured = false

    // MARK: Lifecycle

    func start() async {
        guard !state.isRunning else { return }

        #if targetEnvironment(simulator)
        // Simulator にはカメラが無い。理由を表示して止まる（クラッシュさせない / 仕様書 §60）。
        state = .unsupported("Simulator にはカメラがありません。Camera デモは実機で確認してください。Photo / Video デモは Simulator でも動作します。")
        #else
        state = .starting

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                state = .denied
                return
            }
        case .denied, .restricted:
            state = .denied
            return
        @unknown default:
            state = .denied
            return
        }

        do {
            try configureIfNeeded()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        await startSessionOnCaptureQueue()
        state = .running
        startAnalysisLoop()
        #endif
    }

    func stop() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        frameBox.reset()
        state = .idle
        liveAnalysis = nil
        analyzedFrameCount = 0
        measuredAnalysisFPS = 0
    }

    /// セッションの開始はキャプチャ用キューで行う。
    /// AVCaptureSession は Sendable ではないので、nonisolated なこのメソッドの内側に閉じる。
    nonisolated private func startSessionOnCaptureQueue() async {
        await withCheckedContinuation { continuation in
            queue.async { [session] in
                if !session.isRunning { session.startRunning() }
                continuation.resume()
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw LabError.camera("背面カメラが見つかりません。", recovery: "実機で実行してください。")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw LabError.camera("カメラ入力を追加できません。", recovery: "他のアプリがカメラを使用していないか確認してください。")
        }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        let delegate = FrameCaptureDelegate(box: frameBox)
        self.delegate = delegate
        output.setSampleBufferDelegate(delegate, queue: queue)
        guard session.canAddOutput(output) else {
            throw LabError.camera("ビデオ出力を追加できません。", recovery: "セッション構成を確認してください。")
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        configured = true
    }

    // MARK: Realtime analysis loop

    /// Vision をターゲットFPSで回し続ける。言語モデルはここでは呼ばない。
    private func startAnalysisLoop() {
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            var window: [Date] = []
            while !Task.isCancelled {
                let interval = 1.0 / max(1.0, self.targetAnalysisFPS)
                let cycleStarted = Date()

                if let frame = self.frameBox.latest() {
                    self.isAnalyzing = true
                    do {
                        let analysis = try await self.analyzer.analyze(
                            pixelBuffer: frame.buffer,
                            orientation: frame.orientation,
                            plan: self.plan
                        )
                        guard !Task.isCancelled else { return }
                        self.liveAnalysis = analysis
                        self.lastVisionElapsed = analysis.visionElapsed
                        self.analyzedFrameCount += 1

                        window.append(Date())
                        window = window.filter { Date().timeIntervalSince($0) < 2 }
                        self.measuredAnalysisFPS = Double(window.count) / 2.0
                    } catch is CancellationError {
                        return
                    } catch {
                        // 1フレーム失敗しても解析を止めない。
                    }
                    self.isAnalyzing = false
                }

                let spent = Date().timeIntervalSince(cycleStarted)
                if spent < interval {
                    try? await Task.sleep(for: .seconds(interval - spent))
                }
            }
        }
    }

    // MARK: Single frame capture

    /// 仕様書 §35: 押した瞬間のフレームだけを取り出す。
    func captureCurrentFrame() -> (analysis: VisionSource, image: ImageBox)? {
        guard let frame = frameBox.latest() else { return nil }
        let ciImage = CIImage(cvPixelBuffer: frame.buffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return (.cgImage(cgImage, orientation: frame.orientation), ImageBox(cgImage: cgImage))
    }

    var receivedFrameCount: Int { frameBox.frameCount }
}

// MARK: - Preview layer

/// AVCaptureVideoPreviewLayer を SwiftUI に載せる。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
