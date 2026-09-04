//
//  ModelManager.swift
//  Foundation Models Lab
//
//  責務: モデル取得 / Availability確認 / Capabilities確認 / Context Size取得 / モデル切替
//  仕様書 §63 Core設計 - ModelManager
//

import Foundation
import FoundationModels

// MARK: - Model choice

/// 仕様書 §5 の Model A / B / C。
/// iOS 26 SDK が実際に提供するのは SystemLanguageModel のみなので、
/// PCC と Custom は「SDK未提供」を明示したうえでアプリ側の抽象として持つ。
nonisolated enum ModelChoice: String, CaseIterable, Identifiable, Sendable {
    case onDevice
    case pcc
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onDevice: "Apple On-device"
        case .pcc: "Apple PCC"
        case .custom: "Mock Server Model"
        }
    }

    var apiTypeName: String {
        switch self {
        case .onDevice: "SystemLanguageModel"
        case .pcc: "PrivateCloudComputeLanguageModel"
        case .custom: "LabLanguageModel (custom protocol)"
        }
    }

    /// この SDK で実際に呼べるか。
    var isBackedByInstalledSDK: Bool { self == .onDevice }
}

// MARK: - Capabilities

nonisolated struct ModelCapabilities: Sendable, Equatable {
    var textGeneration = false
    var guidedGeneration = false
    var toolCalling = false
    var streaming = false
    var tokenCounting = false
    var transcriptRestore = false
    /// FoundationModels が画像を直接プロンプトに受け取れるか（iOS 26 SDK では不可）。
    var nativeVision = false
    /// Vision framework 経由の画像解析が使えるか。
    var visionFrameworkBridge = false
    var reasoningLevel = false
    var privateCloudCompute = false

    var rows: [(String, Bool, String)] {
        [
            ("Text Generation", textGeneration, "LanguageModelSession.respond(to:)"),
            ("Guided Generation", guidedGeneration, "@Generable / respond(to:generating:)"),
            ("Tool Calling", toolCalling, "Tool protocol"),
            ("Streaming", streaming, "streamResponse(to:)"),
            ("Token Counting", tokenCounting, "SystemLanguageModel.tokenCount(for:)"),
            ("Transcript Restore", transcriptRestore, "LanguageModelSession(transcript:)"),
            ("Vision (native prompt)", nativeVision, "画像添付APIはこのSDKに存在しません"),
            ("Vision (framework bridge)", visionFrameworkBridge, "Vision → テキスト → モデル"),
            ("Reasoning Level", reasoningLevel, "reasoning設定APIはこのSDKに存在しません"),
            ("Private Cloud Compute", privateCloudCompute, "PCCモデル型はこのSDKに存在しません")
        ]
    }
}

// MARK: - Availability

nonisolated enum LabAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String, recovery: String)

    var isAvailable: Bool { self == .available }

    var label: String {
        switch self {
        case .available: "Available"
        case .unavailable: "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .available: "SystemLanguageModel は生成リクエストを受け付けられる状態です。"
        case .unavailable(let reason, _): reason
        }
    }

    var recovery: String? {
        switch self {
        case .available: nil
        case .unavailable(_, let recovery): recovery
        }
    }
}

// MARK: - ModelManager

/// SystemLanguageModel の実状態を読み出す唯一の窓口。
@Observable
final class ModelManager {
    private(set) var availability: LabAvailability = .available
    private(set) var contextSize: Int = 0
    private(set) var supportedLanguageTags: [String] = []
    private(set) var supportsCurrentLocale = false
    private(set) var supportsJapanese = false
    private(set) var capabilities = ModelCapabilities()
    private(set) var lastRefreshed = Date()

    var activeChoice: ModelChoice = .onDevice

    /// UseCase 切替（§5 用途別）。
    var useCase: SystemModelUseCase = .general

    nonisolated let deviceName: String
    nonisolated let osVersion: String

    init() {
        let process = ProcessInfo.processInfo
        deviceName = Self.hardwareIdentifier()
        osVersion = process.operatingSystemVersionString
        refresh()
    }

    /// 現在の UseCase に対応する SystemLanguageModel。
    var systemModel: SystemLanguageModel {
        switch useCase {
        case .general: SystemLanguageModel.default
        case .contentTagging: SystemLanguageModel(useCase: .contentTagging)
        }
    }

    func refresh() {
        let model = systemModel
        availability = Self.map(model.availability)

        // contextSize は実行時のモデルから取得する（仕様書 §39 の注記）。
        contextSize = model.contextSize

        let languages = model.supportedLanguages
        supportedLanguageTags = languages
            .map { $0.maximalIdentifier }
            .sorted()
        supportsCurrentLocale = model.supportsLocale()
        supportsJapanese = languages.contains { $0.languageCode?.identifier == "ja" }

        let live = availability.isAvailable
        capabilities = ModelCapabilities(
            textGeneration: live,
            guidedGeneration: live,
            toolCalling: live,
            streaming: live,
            tokenCounting: live,
            transcriptRestore: live,
            nativeVision: false,
            visionFrameworkBridge: true,
            reasoningLevel: false,
            privateCloudCompute: false
        )
        lastRefreshed = Date()
    }

    // MARK: Session factory

    /// 仕様書 §63 SessionManager: Session生成をここに集約する。
    func makeSession(instructions: String? = nil, tools: [any Tool] = []) -> LanguageModelSession {
        LanguageModelSession(model: systemModel, tools: tools, instructions: instructions)
    }

    func makeSession(transcript: Transcript, tools: [any Tool] = []) -> LanguageModelSession {
        LanguageModelSession(model: systemModel, tools: tools, transcript: transcript)
    }

    // MARK: Token counting (実API)

    func tokenCount(for text: String) async throws -> Int {
        try await systemModel.tokenCount(for: Prompt(text))
    }

    func tokenCount(for entries: some Collection<Transcript.Entry>) async throws -> Int {
        try await systemModel.tokenCount(for: entries)
    }

    func tokenCount(for tools: [any Tool]) async throws -> Int {
        try await systemModel.tokenCount(for: tools)
    }

    // MARK: Mapping

    private static func map(_ availability: SystemLanguageModel.Availability) -> LabAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(
                    reason: "この端末は Apple Intelligence 非対応です (deviceNotEligible)。",
                    recovery: "Apple Intelligence 対応端末で実行してください。"
                )
            case .appleIntelligenceNotEnabled:
                return .unavailable(
                    reason: "Apple Intelligence が有効になっていません (appleIntelligenceNotEnabled)。",
                    recovery: "設定 > Apple Intelligence と Siri から Apple Intelligence をオンにしてください。"
                )
            case .modelNotReady:
                return .unavailable(
                    reason: "モデルのダウンロード / 準備が完了していません (modelNotReady)。",
                    recovery: "電源とネットワークに接続し、しばらく待ってから再確認してください。"
                )
            @unknown default:
                return .unavailable(
                    reason: "未知の理由でモデルを利用できません。",
                    recovery: "OS を更新して再確認してください。"
                )
            }
        @unknown default:
            return .unavailable(reason: "未知の Availability 値です。", recovery: "OS を更新してください。")
        }
    }

    private nonisolated static func hardwareIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return ProcessInfo.processInfo.hostName }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}

nonisolated enum SystemModelUseCase: String, CaseIterable, Identifiable, Sendable {
    case general = "general"
    case contentTagging = "contentTagging"

    var id: String { rawValue }
}
