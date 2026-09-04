//
//  MediaViews.swift
//  Foundation Models Lab
//
//  画像 / 動画 / カメラの表示とオーバーレイ。
//  「アップロードした結果がどう解析されたか」を目で確認できるようにする。
//

import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Detection overlay

/// Vision の正規化座標（原点は左下）を SwiftUI の座標（原点は左上）へ変換して枠を描く。
struct DetectionOverlay: View {
    let analysis: FrameAnalysis?
    var imageSize: CGSize?
    var contentMode: ContentMode = .fit
    var showText = true
    var showBarcodes = true
    var showTextRegions = true
    var showRectangles = true
    var showFaces = true
    var showHumans = true
    var showSaliency = true
    var showLabels = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let imageRect = renderedImageRect(in: size)
            ZStack(alignment: .topLeading) {
                if let analysis {
                    if showSaliency {
                        ForEach(Array(analysis.salientObjects.enumerated()), id: \.offset) { _, box in
                            rect(box, in: imageRect)
                                .stroke(.purple, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                    if showRectangles {
                        ForEach(analysis.rectangles) { region in
                            rect(region.boundingBox, in: imageRect)
                                .stroke(.blue, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        }
                    }
                    if showFaces {
                        ForEach(analysis.faceRectangles) { region in
                            rect(region.boundingBox, in: imageRect)
                                .stroke(.pink, lineWidth: 2.0)
                        }
                    }
                    if showHumans {
                        ForEach(analysis.humanRectangles) { region in
                            rect(region.boundingBox, in: imageRect)
                                .stroke(.cyan, lineWidth: 2.0)
                        }
                    }
                    if showTextRegions {
                        ForEach(analysis.textRegions) { region in
                            rect(region.boundingBox, in: imageRect)
                                .stroke(.red, lineWidth: 1.2)
                        }
                    }
                    if showText {
                        ForEach(analysis.texts) { text in
                            let frame = convert(text.boundingBox, in: imageRect)
                            rect(text.boundingBox, in: imageRect)
                                .stroke(.green, lineWidth: 1.8)
                            Text(text.text)
                                .font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(.green.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.white)
                                .frame(maxWidth: max(40, frame.width))
                                .position(x: frame.midX, y: max(6, frame.minY - 7))
                        }
                    }
                    if showBarcodes {
                        ForEach(analysis.barcodes) { barcode in
                            let frame = convert(barcode.boundingBox, in: imageRect)
                            rect(barcode.boundingBox, in: imageRect)
                                .stroke(.orange, lineWidth: 2.5)
                            Text("\(barcode.typeLabel): \(barcode.payload)")
                                .font(.system(size: 9, weight: .bold))
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.orange, in: RoundedRectangle(cornerRadius: 3))
                                .foregroundStyle(.white)
                                .position(x: frame.midX, y: max(8, frame.minY - 9))
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
    }

    private func renderedImageRect(in container: CGSize) -> CGRect {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }

        let scale: CGFloat = switch contentMode {
        case .fit:
            min(container.width / imageSize.width, container.height / imageSize.height)
        case .fill:
            max(container.width / imageSize.width, container.height / imageSize.height)
        }
        let drawnSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - drawnSize.width) / 2,
            y: (container.height - drawnSize.height) / 2,
            width: drawnSize.width,
            height: drawnSize.height
        )
    }

    private func convert(_ box: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + box.minX * imageRect.width,
            y: imageRect.minY + (1 - box.maxY) * imageRect.height,
            width: box.width * imageRect.width,
            height: box.height * imageRect.height
        )
    }

    private func rect(_ box: CGRect, in imageRect: CGRect) -> Path {
        Path(roundedRect: convert(box, in: imageRect), cornerRadius: 2)
    }
}

// MARK: - System camera sheet

/// 写真デモ用のカメラ。標準の撮影UI（シャッター / 撮り直し / 使用）で1枚撮り、
/// 撮影結果をそのまま画像スロットへ渡す。
/// Camera Frame デモが使う AVCaptureSession（仕様書 §35 の連続フレーム経路）とは別物。
struct CameraCaptureSheet: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCapture: (UIImage) -> Void

    /// Simulator にはカメラが無いので、この環境では使えないことを呼び出し側に伝える。
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onFinish: { isPresented = false })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}

// MARK: - Image picker with preview

struct ImageInputView: View {
    let title: String
    @Binding var selection: PhotosPickerItem?
    let image: ImageBox?
    let analysis: FrameAnalysis?
    /// カメラで撮影した1枚を受け取る。nil を渡すと Take Photo を出さない。
    var onCapture: ((UIImage) -> Void)?
    var onClear: (() -> Void)?

    @State private var showOverlay = true
    @State private var showsCamera = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if image != nil {
                    Toggle(isOn: $showOverlay) {
                        Label("Overlay", systemImage: "square.dashed")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }

            if let image {
                ZStack {
                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    if showOverlay {
                        DetectionOverlay(analysis: analysis, imageSize: image.size, contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 340)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if let analysis {
                    VisionSummaryStrip(analysis: analysis)
                }
            } else {
                ContentUnavailableView {
                    Label("画像が未選択", systemImage: "photo.badge.plus")
                } description: {
                    Text("下のボタンから写真を選ぶと、Vision が解析して枠を重ねて表示します。")
                }
                .frame(height: 150)
            }

            HStack {
                // photoLibrary: .shared() を渡すとピッカーがアプリ内プロセスで動き、
                // 写真ライブラリの許可が必要になる（未許可だと選んでも何も返らない）。
                // ここは選択した1枚を読むだけなので、許可の要らない標準ピッカーを使う。
                PhotosPicker(selection: $selection, matching: .images) {
                    Label(image == nil ? "Choose Photo" : "Change", systemImage: "photo.on.rectangle")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("picker.photo.\(title)")

                if onCapture != nil {
                    Button {
                        showsCamera = true
                    } label: {
                        Label(image == nil ? "Take Photo" : "Retake", systemImage: "camera.fill")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!CameraCaptureSheet.isAvailable)
                    .accessibilityIdentifier("action.takePhoto.\(title)")
                }

                if image != nil, let onClear {
                    Button(role: .destructive) { onClear() } label: {
                        Label("Clear", systemImage: "trash")
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                }
            }
            // 3つ並ぶと狭い端末で折り返すので、はみ出したら横スクロールさせる。
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .leading)

            if onCapture != nil, !CameraCaptureSheet.isAvailable {
                Text("この環境にはカメラがありません。Take Photo は実機でのみ使えます。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Text("Sample Data Only — 実際の患者情報や機微な画像は使用しないでください。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showsCamera) {
            if let onCapture {
                CameraCaptureSheet(isPresented: $showsCamera, onCapture: onCapture)
                    .ignoresSafeArea()
            }
        }
    }
}

/// Vision が何を検出したかの1行サマリ。
struct VisionSummaryStrip: View {
    let analysis: FrameAnalysis

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("photo", "\(Int(analysis.imageSize.width))×\(Int(analysis.imageSize.height))", .secondary)
                chip("text.viewfinder", "文字 \(analysis.texts.count)", analysis.texts.isEmpty ? .secondary : .green)
                chip("text.viewfinder", "文字領域 \(analysis.textRegions.count)", analysis.textRegions.isEmpty ? .secondary : .red)
                chip("barcode.viewfinder", "コード \(analysis.barcodes.count)", analysis.barcodes.isEmpty ? .secondary : .orange)
                chip("rectangle.dashed", "矩形 \(analysis.rectangles.count)", analysis.rectangles.isEmpty ? .secondary : .blue)
                chip("face.smiling", "顔 \(analysis.faceRectangles.count)", analysis.faceRectangles.isEmpty ? .secondary : .pink)
                chip("figure.stand", "人物 \(analysis.humanRectangles.count)", analysis.humanRectangles.isEmpty ? .secondary : .cyan)
                chip("tag", "ラベル \(analysis.labels.count)", analysis.labels.isEmpty ? .secondary : .blue)
                if !analysis.salientObjects.isEmpty { chip("viewfinder", "注目 \(analysis.salientObjects.count)", .purple) }
                if let score = analysis.aestheticsScore {
                    chip("sparkles", String(format: "美的 %.2f", score), .secondary)
                }
                chip("timer", String(format: "%.0f ms", analysis.visionElapsed * 1000), .secondary)
                if !analysis.unavailableRequests.isEmpty {
                    chip("exclamationmark.triangle", "実行不可 \(analysis.unavailableRequests.count)", .orange)
                }
            }
        }
    }

    private func chip(_ symbol: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Video input

struct VideoInputView: View {
    @Binding var selection: PhotosPickerItem?
    let metadata: VideoMetadata?
    let frames: [FrameAnalysis]
    let progress: (done: Int, total: Int)?
    @Binding var frameCount: Int
    var onClear: (() -> Void)?

    @State private var selectedFrameID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let metadata {
                KeyValueTable(rows: metadata.rows, compact: true)
            } else {
                ContentUnavailableView {
                    Label("動画が未選択", systemImage: "film.stack")
                } description: {
                    Text("動画を選ぶと、等間隔にコマを取り出して1枚ずつ Vision で解析し、時系列としてモデルにまとめさせます。")
                }
                .frame(height: 170)
            }

            HStack {
                PhotosPicker(selection: $selection, matching: .videos) {
                    Label(metadata == nil ? "Choose Video" : "Change Video", systemImage: "film")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("picker.video")

                if metadata != nil, let onClear {
                    Button(role: .destructive) { onClear() } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Stepper("サンプリングするコマ数: \(frameCount)", value: $frameCount, in: 2...24)
                .font(.subheadline)
                .accessibilityIdentifier("stepper.videoFrameCount")

            if let progress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                    Text("コマを解析中 \(progress.done) / \(progress.total)")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            if !frames.isEmpty {
                VideoFrameTimeline(frames: frames, selectedFrameID: $selectedFrameID)
            }

            Text("Sample Data Only — 音声トラックは解析対象外です。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 抽出したコマをサムネイル付きで時系列に並べる。
struct VideoFrameTimeline: View {
    let frames: [FrameAnalysis]
    @Binding var selectedFrameID: UUID?

    private var selected: FrameAnalysis? {
        frames.first { $0.id == selectedFrameID } ?? frames.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Extracted Frames (\(frames.count))")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 10) {
                    ForEach(frames) { frame in
                        Button {
                            selectedFrameID = frame.id
                        } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    if let thumbnail = frame.thumbnail {
                                        Image(decorative: thumbnail.cgImage, scale: 1)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } else {
                                        Color(.tertiarySystemGroupedBackground)
                                    }
                                    DetectionOverlay(
                                        analysis: frame,
                                        imageSize: frame.imageSize,
                                        contentMode: .fill,
                                        showSaliency: false
                                    )
                                }
                                .frame(width: 132, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(frame.id == (selectedFrameID ?? frames.first?.id) ? .blue : .clear, lineWidth: 2.5)
                                }

                                Text(frame.timestampText)
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                Text(frame.summaryLine)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 132)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if let selected {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frame @ \(selected.timestampText)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    VisionSummaryStrip(analysis: selected)
                    Text(selected.digest)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - Camera input

struct CameraInputView: View {
    let engine: LabEngine
    /// 連続解析＋実況のUIを出すか（Live Camera デモ）。
    let showsLiveControls: Bool

    @State private var showOverlay = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch engine.camera.state {
            case .running:
                preview
            case .idle:
                placeholder(
                    symbol: "camera.fill",
                    title: "カメラは停止中",
                    message: showsLiveControls
                        ? "Start Camera を押すと、Vision が連続してフレームを解析し、結果を映像に重ねて表示します。"
                        : "Start Camera を押すと、押した瞬間の1フレームだけを解析できます。"
                )
            case .starting:
                ProgressView("カメラを起動しています…")
                    .frame(maxWidth: .infinity, minHeight: 200)
            case .denied:
                placeholder(symbol: "lock.fill", title: "カメラ権限がありません",
                            message: "設定 > プライバシーとセキュリティ > カメラ からこのアプリを許可してください。", tint: .red)
            case .unsupported(let reason):
                placeholder(symbol: "iphone.slash", title: "カメラを利用できません", message: reason, tint: .orange)
            case .failed(let reason):
                placeholder(symbol: "exclamationmark.triangle.fill", title: "カメラの起動に失敗", message: reason, tint: .red)
            }

            HStack {
                if engine.camera.state.isRunning {
                    // 撮影した1枚は写真ピッカーで選んだのと同じ画像スロットへ入る。
                    if !showsLiveControls {
                        Button {
                            Task { await engine.captureCameraStill() }
                        } label: {
                            Label("Capture Frame", systemImage: "camera.aperture")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("action.captureFrame")
                    }

                    Button {
                        engine.stopCamera()
                    } label: {
                        Label("Stop Camera", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("action.stopCamera")
                } else {
                    Button {
                        Task { await engine.startCamera() }
                    } label: {
                        Label("Start Camera", systemImage: "camera.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("action.startCamera")
                }

                if engine.camera.state.isRunning {
                    Toggle(isOn: $showOverlay) {
                        Label("Overlay", systemImage: "square.dashed")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }

            if !showsLiveControls, engine.isImageFromCamera, let captured = engine.image {
                capturedFrame(captured)
            }

            if engine.camera.state.isRunning {
                liveStats

                if showsLiveControls {
                    liveControls
                }
            }
        }
    }

    /// 撮影して画像スロットに入った1枚。Photo デモと同じ見え方に揃える。
    @ViewBuilder
    private func capturedFrame(_ box: ImageBox) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("取り込んだフレーム").font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    engine.clearMedia()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("action.clearCapturedFrame")
            }

            ZStack {
                Image(decorative: box.cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                if showOverlay {
                    DetectionOverlay(analysis: engine.imageAnalysis, imageSize: box.size, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 280)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if let analysis = engine.imageAnalysis {
                VisionSummaryStrip(analysis: analysis)
            }

            Text("この1枚は Photo デモと同じ画像スロットに入っています。カメラを止めても残ります。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("panel.capturedFrame")
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            CameraPreviewView(session: engine.camera.session)
            if showOverlay {
                DetectionOverlay(
                    analysis: engine.camera.liveAnalysis,
                    imageSize: engine.camera.liveAnalysis?.imageSize,
                    contentMode: .fill
                )
            }
            if engine.isNarrating {
                VStack {
                    Spacer()
                    HStack {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("モデルが実況を生成中…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.85), in: Capsule())
                    .padding(.bottom, 10)
                }
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var liveStats: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                stat("Vision 実測", String(format: "%.1f fps", engine.camera.measuredAnalysisFPS),
                     engine.camera.measuredAnalysisFPS >= engine.camera.targetAnalysisFPS * 0.7 ? .green : .orange)
                stat("目標", String(format: "%.0f fps", engine.camera.targetAnalysisFPS), .secondary)
                stat("1フレーム", String(format: "%.0f ms", engine.camera.lastVisionElapsed * 1000), .secondary)
                stat("解析済", "\(engine.camera.analyzedFrameCount)", .secondary)
                stat("受信", "\(engine.camera.receivedFrameCount)", .secondary)
                if showsLiveControls {
                    stat("実況回数", "\(engine.narrationCount)", .blue)
                    if let elapsed = engine.lastNarrationElapsed {
                        stat("実況所要", String(format: "%.2f sec", elapsed), .blue)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var liveControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Text("Vision 目標 FPS")
                    .font(.subheadline)
                Slider(value: Binding(
                    get: { engine.camera.targetAnalysisFPS },
                    set: { engine.camera.targetAnalysisFPS = $0 }
                ), in: 1...15, step: 1)
                Text(String(format: "%.0f", engine.camera.targetAnalysisFPS))
                    .font(.subheadline.monospacedDigit())
                    .frame(width: 26)
            }

            Toggle(isOn: Binding(
                get: { engine.autoNarrate },
                set: { engine.setAutoNarration($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Narration").font(.subheadline.weight(.medium))
                    Text("一定間隔で最新フレームをモデルに実況させる")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if engine.autoNarrate {
                HStack {
                    Text("間隔")
                        .font(.subheadline)
                    Slider(value: Binding(
                        get: { engine.narrationIntervalSeconds },
                        set: { engine.narrationIntervalSeconds = $0 }
                    ), in: 3...30, step: 1)
                    Text("\(Int(engine.narrationIntervalSeconds)) 秒")
                        .font(.subheadline.monospacedDigit())
                        .frame(width: 46)
                }
            }

            if !engine.liveNarrationPartial.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Model Narration", systemImage: "text.bubble")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(engine.liveNarrationPartial)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let narration = engine.liveNarration, !narration.highlights.isEmpty {
                        ForEach(Array(narration.highlights.enumerated()), id: \.offset) { _, item in
                            Label(item, systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .labelStyle(BulletLabelStyle())
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if let analysis = engine.camera.liveAnalysis {
                VisionSummaryStrip(analysis: analysis)
                if !analysis.joinedText.isEmpty {
                    Text("読み取り中の文字: \(analysis.joinedText)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.green)
                        .lineLimit(3)
                }
                if !analysis.labels.isEmpty {
                    Text("分類: " + analysis.topLabels.map { "\($0.identifier) \($0.percentText)" }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
    }

    private func placeholder(symbol: String, title: String, message: String, tint: Color = .secondary) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .frame(minHeight: 190)
        .foregroundStyle(tint == .secondary ? .secondary : tint)
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 4))
            configuration.title
        }
    }
}

// MARK: - Media result

/// 仕様書 §33: OCR Raw Result と Model Interpretation を分離して表示する。
struct MediaResultView: View {
    let result: MediaAnalysisResult
    @State private var showDigest = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !result.mediaInfo.isEmpty {
                KeyValueTable(rows: result.mediaInfo, compact: true)
                Divider()
            }

            // 1. Vision が観測した生の結果（= モデルへ渡したテキスト）
            DisclosureGroup(isExpanded: $showDigest) {
                Text(result.digest.isEmpty ? "（検出なし）" : result.digest)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            } label: {
                HStack {
                    Label("Vision Raw Result", systemImage: "eye")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(format: "%.0f ms", result.visionElapsed * 1000))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // 2. モデルの解釈
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Model Interpretation", systemImage: "cpu")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let elapsed = result.modelElapsed {
                        Text(String(format: "%.2f sec", elapsed))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if let text = result.modelText, !text.isEmpty {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !result.modelFields.isEmpty {
                    StructuredOutputView(fields: result.modelFields, json: result.modelJSON ?? "")
                }

                if result.modelText == nil, result.modelFields.isEmpty {
                    Text("モデルの解釈はありません。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
