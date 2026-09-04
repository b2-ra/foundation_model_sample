//
//  MediaModels.swift
//  Foundation Models Lab
//
//  画像 / 動画 / カメラフレームの解析結果モデル。
//

import Foundation
import CoreGraphics
import Vision

// MARK: - Sendable image box

/// CGImage は Sendable ではないが実体は不変なので、明示的に箱に入れて運ぶ。
nonisolated struct ImageBox: @unchecked Sendable, Identifiable, Equatable {
    let id = UUID()
    let cgImage: CGImage

    var size: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }

    static func == (lhs: ImageBox, rhs: ImageBox) -> Bool { lhs.id == rhs.id }
}

// MARK: - Detections

nonisolated struct DetectedText: Identifiable, Sendable {
    let id = UUID()
    var text: String
    var confidence: Float
    /// Vision の正規化座標（原点は左下）。
    var boundingBox: CGRect
    var isTitle: Bool
    var languages: [String]
}

nonisolated struct DetectedBarcode: Identifiable, Sendable {
    let id = UUID()
    var payload: String
    var symbology: String
    var boundingBox: CGRect
    var isGS1DataCarrier: Bool

    /// 仕様書 §34 の Type 表示用。
    var typeLabel: String {
        symbology
            .replacingOccurrences(of: "VNBarcodeSymbology", with: "")
            .replacingOccurrences(of: "BarcodeSymbology(rawValue: \"", with: "")
            .replacingOccurrences(of: "\")", with: "")
    }
}

nonisolated struct DetectedRegion: Identifiable, Sendable {
    let id = UUID()
    var kind: String
    var boundingBox: CGRect
}

nonisolated struct DetectedLabel: Identifiable, Sendable {
    let id = UUID()
    var identifier: String
    var confidence: Float

    var percentText: String { String(format: "%.0f%%", confidence * 100) }
}

// MARK: - Frame analysis

/// 1フレーム（静止画1枚、動画の1コマ、カメラの1フレーム）に対する Vision 解析結果。
nonisolated struct FrameAnalysis: Identifiable, Sendable {
    let id = UUID()
    /// 動画の場合の再生位置。静止画では nil。
    var timestamp: TimeInterval?
    var imageSize: CGSize
    var texts: [DetectedText] = []
    var barcodes: [DetectedBarcode] = []
    var textRegions: [DetectedRegion] = []
    var rectangles: [DetectedRegion] = []
    var faceRectangles: [DetectedRegion] = []
    var humanRectangles: [DetectedRegion] = []
    var labels: [DetectedLabel] = []
    var salientObjects: [CGRect] = []
    var aestheticsScore: Float?
    var isUtilityImage: Bool?
    var faceCount: Int = 0
    var humanCount: Int = 0
    var visionElapsed: TimeInterval = 0
    /// タイムライン表示用のサムネイル。
    var thumbnail: ImageBox?
    /// この環境で実行できなかった Vision リクエストと理由。
    /// 例: Simulator では DetectBarcodesRequest が使えない。
    var unavailableRequests: [(request: String, reason: String)] = []

    var joinedText: String {
        texts.map(\.text).joined(separator: "\n")
    }

    /// Vision が何か1つでも検出したか。
    var hasDetections: Bool {
        !texts.isEmpty || !barcodes.isEmpty || !textRegions.isEmpty || !rectangles.isEmpty
            || !faceRectangles.isEmpty || !humanRectangles.isEmpty || !labels.isEmpty || !salientObjects.isEmpty
            || faceCount > 0 || humanCount > 0 || aestheticsScore != nil
    }

    /// キャッシュとして再利用してよい解析結果か。
    /// 何も検出できていない かつ 失敗したリクエストがある場合は、
    /// 「特徴の無い画像」ではなく「解析できなかった」なので作り直す。
    var isReusable: Bool { hasDetections || unavailableRequests.isEmpty }

    var topLabels: [DetectedLabel] { Array(labels.prefix(5)) }

    var timestampText: String {
        guard let timestamp else { return "-" }
        let total = Int(timestamp)
        return String(format: "%02d:%02d.%d", total / 60, total % 60, Int((timestamp - Double(total)) * 10))
    }

    /// モデルへ渡すためのテキスト要約。ここが Vision → FoundationModels の橋渡し。
    /// モデルへ渡す観測テキスト。検出できたものだけを並べる。
    /// `digest` と違い、実行できなかったリクエストの一覧（英語のAPI名）は含めない。
    /// あれを混ぜるとモデルがエラー一覧を「画像の内容」として言い換えてしまう。
    ///
    /// 実測（iOS 26.5 Simulator / 薬剤ラベル画像、各2回）: この一覧を混ぜた文を送ると、
    /// 日本語でも英語でも unsupportedLanguageOrLocale になった（日本語の文に英語のAPI名が並ぶため）。
    /// 除いた文なら日本語のまま生成できた。Simulator は実行できないリクエストが多いので、
    /// 混ぜてしまうと診断行が観測テキストの大半を占める。モデルへ渡すのは必ずこちらを使う。
    /// 何も検出できていない場合は空文字を返すので、呼び出し側でモデルを呼ばない判断ができる。
    var observationDigest: String {
        var lines: [String] = []
        if let timestamp { lines.append("時刻: \(String(format: "%.1f", timestamp))秒") }
        if !labels.isEmpty {
            lines.append("画像分類: " + topLabels.map { "\($0.identifier)(\($0.percentText))" }.joined(separator: ", "))
        }
        if !textRegions.isEmpty { lines.append("文字領域: \(textRegions.count)箇所") }
        if !rectangles.isEmpty { lines.append("矩形領域: \(rectangles.count)箇所") }
        if !faceRectangles.isEmpty { lines.append("顔領域: \(faceRectangles.count)箇所") }
        if !humanRectangles.isEmpty { lines.append("人物領域: \(humanRectangles.count)箇所") }
        if faceCount > 0 { lines.append("顔検出: \(faceCount)件") }
        if humanCount > 0 { lines.append("人物検出: \(humanCount)件") }
        if !salientObjects.isEmpty { lines.append("注目領域: \(salientObjects.count)箇所") }
        if let aestheticsScore {
            lines.append("美的スコア: \(String(format: "%.2f", aestheticsScore))\(isUtilityImage == true ? "（実用系画像）" : "")")
        }
        if !texts.isEmpty {
            lines.append("読み取れた文字:\n" + texts.map { "  - \($0.text)" }.joined(separator: "\n"))
        }
        if !barcodes.isEmpty {
            lines.append("バーコード:\n" + barcodes.map { "  - \($0.typeLabel): \($0.payload)" }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    /// 画面の Vision Raw Result 用。実行できなかったリクエストもここには残す。
    var digest: String {
        var lines: [String] = []
        if let timestamp { lines.append("時刻: \(String(format: "%.1f", timestamp))秒") }
        if !labels.isEmpty {
            lines.append("画像分類: " + topLabels.map { "\($0.identifier)(\($0.percentText))" }.joined(separator: ", "))
        }
        if !textRegions.isEmpty { lines.append("文字領域: \(textRegions.count)箇所") }
        if !rectangles.isEmpty { lines.append("矩形領域: \(rectangles.count)箇所") }
        if !faceRectangles.isEmpty { lines.append("顔領域: \(faceRectangles.count)箇所") }
        if !humanRectangles.isEmpty { lines.append("人物領域: \(humanRectangles.count)箇所") }
        if faceCount > 0 { lines.append("顔検出: \(faceCount)件") }
        if humanCount > 0 { lines.append("人物検出: \(humanCount)件") }
        if !salientObjects.isEmpty { lines.append("注目領域: \(salientObjects.count)箇所") }
        if let aestheticsScore {
            lines.append("美的スコア: \(String(format: "%.2f", aestheticsScore))\(isUtilityImage == true ? "（実用系画像）" : "")")
        }
        if !texts.isEmpty {
            lines.append("読み取れた文字:\n" + texts.map { "  - \($0.text)" }.joined(separator: "\n"))
        }
        if !barcodes.isEmpty {
            lines.append("バーコード:\n" + barcodes.map { "  - \($0.typeLabel): \($0.payload)" }.joined(separator: "\n"))
        }
        if lines.isEmpty { lines.append("Vision は特徴を検出できませんでした。") }
        if !unavailableRequests.isEmpty {
            lines.append("この環境で実行できなかった解析: " + unavailableRequests.map(\.request).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    var summaryLine: String {
        var parts: [String] = []
        if let first = labels.first { parts.append(first.identifier) }
        if !texts.isEmpty { parts.append("文字\(texts.count)") }
        if !barcodes.isEmpty { parts.append("コード\(barcodes.count)") }
        if !rectangles.isEmpty { parts.append("矩形\(rectangles.count)") }
        if !faceRectangles.isEmpty { parts.append("顔\(faceRectangles.count)") }
        if !humanRectangles.isEmpty { parts.append("人物\(humanRectangles.count)") }
        if parts.isEmpty { parts.append("特徴なし") }
        return parts.joined(separator: " / ")
    }
}

// MARK: - Media analysis result

nonisolated enum MediaSource: String, Sendable {
    case image = "静止画"
    case imagePair = "2枚比較"
    case video = "動画"
    case cameraFrame = "カメラ単一フレーム"
    case cameraLive = "カメラ連続解析"
}

/// Vision の解析結果とモデルの解釈をセットで持つ。
/// 仕様書 §33 の「OCR Raw Result / Model Interpretation を分離して表示する」に対応。
nonisolated struct MediaAnalysisResult: Sendable {
    var source: MediaSource
    var frames: [FrameAnalysis] = []
    /// モデルへ実際に渡したテキスト（Vision の生結果）。
    var digest: String = ""
    /// モデルが返した構造化出力。
    var modelFields: [StructuredField] = []
    var modelJSON: String?
    /// モデルが返した自由文。
    var modelText: String?
    var visionElapsed: TimeInterval = 0
    var modelElapsed: TimeInterval?
    /// 動画の総尺 / サンプリング情報。
    var mediaInfo: [KeyValueRow] = []

    var plainText: String {
        var sections: [String] = []
        if !digest.isEmpty { sections.append("Vision Raw Result\n\(digest)") }
        if let modelText, !modelText.isEmpty { sections.append("Model Interpretation\n\(modelText)") }
        if !modelFields.isEmpty {
            sections.append("Model Structured Output\n" + modelFields.map { "\($0.label): \($0.value)" }.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }
}
