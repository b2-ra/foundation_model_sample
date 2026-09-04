//
//  VideoAnalyzer.swift
//  Foundation Models Lab
//
//  動画ファイルの解析。
//  AVAssetImageGenerator で等間隔にコマを取り出し、各コマを Vision で解析して時系列にまとめる。
//  仕様書には動画デモの記載がないが、「写真や動画ファイルの分析」を体験できるようにするための拡張。
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Transferable movie

/// PhotosPicker から動画を受け取るための Transferable。
/// 動画は巨大になりうるので Data ではなくファイルとしてコピーする。
nonisolated struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("fmlab-\(UUID().uuidString)")
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

// MARK: - Video analysis

nonisolated struct VideoMetadata: Sendable {
    var url: URL
    var duration: TimeInterval
    var naturalSize: CGSize
    var nominalFrameRate: Float
    var fileSizeBytes: Int64
    var hasAudio: Bool

    var durationText: String {
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var rows: [KeyValueRow] {
        [
            KeyValueRow(label: "Duration", value: durationText),
            KeyValueRow(label: "Resolution", value: "\(Int(naturalSize.width)) × \(Int(naturalSize.height))"),
            KeyValueRow(label: "Frame Rate", value: String(format: "%.1f fps", nominalFrameRate)),
            KeyValueRow(label: "File Size", value: fileSizeText),
            KeyValueRow(label: "Audio Track", value: hasAudio ? "あり（解析対象外）" : "なし")
        ]
    }
}

nonisolated struct VideoAnalyzer: Sendable {
    let analyzer = VisionAnalyzer()

    /// 動画のメタデータを読む。
    func metadata(for url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let track = videoTracks.first else {
            throw LabError.media("動画トラックが見つかりません: \(url.lastPathComponent)", recovery: "別の動画を選択してください。")
        }
        let size = try await track.load(.naturalSize)
        let frameRate = try await track.load(.nominalFrameRate)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64

        return VideoMetadata(
            url: url,
            duration: duration.isFinite ? duration : 0,
            naturalSize: size,
            nominalFrameRate: frameRate,
            fileSizeBytes: fileSize ?? 0,
            hasAudio: !audioTracks.isEmpty
        )
    }

    /// 等間隔にコマを取り出して1枚ずつ Vision で解析する。
    /// - Parameter onFrame: 1コマ解析するたびに呼ばれる。進捗表示に使う。
    ///   呼び出し元が MainActor へ渡す責任を持つ（ここは nonisolated なので self を跨がせない）。
    func analyzeFrames(
        url: URL,
        frameCount: Int,
        plan: VisionAnalysisPlan = .videoFrame,
        onFrame: @Sendable (FrameAnalysis, Int, Int) -> Void = { _, _, _ in }
    ) async throws -> [FrameAnalysis] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let totalSeconds = duration.seconds
        guard totalSeconds.isFinite, totalSeconds > 0 else {
            throw LabError.media("動画の長さを取得できません。", recovery: "別の動画を選択してください。")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)
        // サムネイルは表示用なので小さく作る。解析には原寸を使わないので統一する。
        generator.maximumSize = CGSize(width: 1024, height: 1024)

        let count = max(1, min(frameCount, 32))
        var results: [FrameAnalysis] = []

        for index in 0..<count {
            try Task.checkCancellation()
            // 端に寄り過ぎないよう区間の中央をサンプリングする。
            let fraction = (Double(index) + 0.5) / Double(count)
            let time = CMTime(seconds: totalSeconds * fraction, preferredTimescale: 600)

            let generated: (image: CGImage, actualTime: CMTime)
            do {
                generated = try await generator.image(at: time)
            } catch {
                // 特定のコマが取れなくても解析全体は続ける。
                continue
            }

            let analysis = try await analyzer.analyze(
                cgImage: generated.image,
                plan: plan,
                timestamp: generated.actualTime.seconds,
                thumbnail: generated.image
            )
            results.append(analysis)
            onFrame(analysis, index + 1, count)
        }

        guard !results.isEmpty else {
            throw LabError.media("動画からコマを取り出せませんでした。", recovery: "別の形式の動画を選択してください。")
        }
        return results
    }
}
