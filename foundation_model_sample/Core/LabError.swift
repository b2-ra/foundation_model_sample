//
//  LabError.swift
//  Foundation Models Lab
//
//  仕様書 §59 Error Lab / §60 Model Availability Handling
//  内部エラーをそのまま出さず Error Type / Technical Detail / User Message / Recovery の4項目に正規化する。
//

import Foundation
import FoundationModels

nonisolated struct LabError: Error, Identifiable, Equatable, Sendable {
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case modelUnavailable = "Model unavailable"
        case appleIntelligenceDisabled = "Apple Intelligence disabled"
        case unsupportedDevice = "Unsupported device"
        case unsupportedLanguage = "Unsupported language"
        case contextExceeded = "Context exceeded"
        case rateLimited = "Rate limited"
        case concurrentRequests = "Concurrent requests"
        case guardrailViolation = "Guardrail violation"
        case refusal = "Refusal"
        case unsupportedGuide = "Unsupported guide"
        case decodingFailure = "Decoding failure"
        case toolFailure = "Tool failure"
        case generationFailure = "Generation failure"
        case schemaFailure = "Schema failure"
        case pccUnavailable = "PCC unavailable"
        case pccQuota = "PCC quota"
        case imageError = "Image error"
        case mediaError = "Media error"
        case cameraError = "Camera error"
        case cancelled = "Cancelled"
        case sdkFeatureMissing = "SDK feature missing"

        var id: String { rawValue }
    }

    let id = UUID()
    var category: Category
    var technicalDetail: String
    var userMessage: String
    var recovery: String

    var errorType: String { category.rawValue }

    static func == (lhs: LabError, rhs: LabError) -> Bool {
        lhs.category == rhs.category && lhs.technicalDetail == rhs.technicalDetail
    }

    // MARK: - Factories

    static func sdkFeatureMissing(_ feature: String, alternative: String) -> LabError {
        LabError(
            category: .sdkFeatureMissing,
            technicalDetail: "\(feature) はインストール済みSDK (iOS \(Self.sdkVersion)) の FoundationModels に存在しません。",
            userMessage: "\(feature) はこのSDKでは利用できません。",
            recovery: alternative
        )
    }

    static func media(_ detail: String, recovery: String) -> LabError {
        LabError(category: .mediaError, technicalDetail: detail, userMessage: "メディアの読み込みに失敗しました。", recovery: recovery)
    }

    static func camera(_ detail: String, recovery: String) -> LabError {
        LabError(category: .cameraError, technicalDetail: detail, userMessage: "カメラを利用できません。", recovery: recovery)
    }

    static func image(_ detail: String) -> LabError {
        LabError(category: .imageError, technicalDetail: detail, userMessage: "画像を解析できませんでした。", recovery: "別の画像を選択して再実行してください。")
    }

    static func unavailable(_ availability: LabAvailability) -> LabError {
        guard case .unavailable(let reason, let recovery) = availability else {
            return LabError(category: .modelUnavailable, technicalDetail: "availability = available", userMessage: "モデルは利用可能です。", recovery: "-")
        }
        let category: Category = reason.contains("deviceNotEligible") ? .unsupportedDevice
            : reason.contains("appleIntelligenceNotEnabled") ? .appleIntelligenceDisabled
            : .modelUnavailable
        return LabError(category: category, technicalDetail: reason, userMessage: "Foundation Models を利用できません。", recovery: recovery)
    }

    // MARK: - Mapping

    /// 同じ入力でも結果が揺れる、モデル側の一時的な失敗か。
    ///
    /// 端末モデルは同じプロンプトでも実行ごとに、スキーマへ収まらない出力を返すことがある。
    /// 出力形式の揺れは同じ文面でもう一度生成すれば収まることが多いので、この種類だけ作り直す。
    ///
    /// guardrailViolation と refusal は含めない。
    /// Apple の「Improving the safety of generative model output」は、
    /// ガードレール違反に対しては同じ文面の再送ではなく
    /// 「プロンプトの言い回しを変える」「利用者へ明示して別の入力を促す」ことを求めている。
    /// 同じ文面を黙って再送するのは、判定の揺れに賭けてガードレールをすり抜ける操作になる。
    ///
    /// コンテキスト超過や利用不可のように原因が確定しているものも含めない。
    /// 再試行しても同じ結果になるうえ、Error Lab のように
    /// そのエラーを見せることが目的の画面を壊してしまう。
    static func isRetriableRejection(_ error: Error) -> Bool {
        switch map(error).category {
        case .decodingFailure, .generationFailure:
            true
        default:
            false
        }
    }

    /// プロンプトの言語をモデルが受け付けなかったか。
    /// これは判定が安定しているので、同じ文面での再試行は無意味（文面を変える必要がある）。
    static func isUnsupportedLanguage(_ error: Error) -> Bool {
        map(error).category == .unsupportedLanguage
    }

    /// 実際に飛んできた Error を4項目へ写像する。
    static func map(_ error: Error) -> LabError {
        if let labError = error as? LabError { return labError }

        if error is CancellationError {
            return LabError(
                category: .cancelled,
                technicalDetail: "CancellationError: Swift Concurrency の Task がキャンセルされました。",
                userMessage: "実行をキャンセルしました。",
                recovery: "もう一度 Run Demo を押してください。"
            )
        }

        if let toolError = error as? LanguageModelSession.ToolCallError {
            return LabError(
                category: .toolFailure,
                technicalDetail: "ToolCallError tool=\(toolError.tool.name) underlying=\(toolError.underlyingError)",
                userMessage: "Tool「\(toolError.tool.name)」の実行が失敗しました。",
                recovery: "Tool の引数条件を満たすプロンプトに変更して再実行してください。"
            )
        }

        if let schemaError = error as? GenerationSchema.SchemaError {
            return LabError(
                category: .schemaFailure,
                technicalDetail: "GenerationSchema.SchemaError: \(schemaError.errorDescription ?? String(describing: schemaError))",
                userMessage: "動的スキーマの定義が不正です。",
                recovery: schemaError.recoverySuggestion ?? "フィールド名の重複や未定義参照を修正してください。"
            )
        }

        if let generationError = error as? LanguageModelSession.GenerationError {
            return map(generationError)
        }

        // GenerationError が NSError へブリッジされた形で飛んでくることがある。
        // その場合 as? キャストが通らないので、domain と localizedDescription から拾い直す。
        let nsError = error as NSError
        if nsError.domain.contains("GenerationError") || nsError.domain.contains("FoundationModels") {
            return LabError(
                category: .generationFailure,
                technicalDetail: """
                domain: \(nsError.domain)
                code: \(nsError.code)
                description: \(nsError.localizedDescription)
                \(nsError.localizedFailureReason.map { "reason: \($0)" } ?? "")
                """.trimmingCharacters(in: .whitespacesAndNewlines),
                userMessage: nsError.localizedFailureReason ?? "モデルが生成を完了できませんでした。",
                recovery: nsError.localizedRecoverySuggestion
                    ?? "スキーマの @Guide 制約を単純にする、または入力を短くして再実行してください。"
            )
        }

        return LabError(
            category: .generationFailure,
            technicalDetail: "\(type(of: error)): \(error.localizedDescription)",
            userMessage: "生成に失敗しました。",
            recovery: "入力内容とモデルの利用可否を確認して再実行してください。"
        )
    }

    static func map(_ error: LanguageModelSession.GenerationError) -> LabError {
        let recovery = error.recoverySuggestion
        switch error {
        case .exceededContextWindowSize(let context):
            return LabError(
                category: .contextExceeded,
                technicalDetail: "exceededContextWindowSize: \(context.debugDescription)",
                userMessage: "入力がコンテキストウィンドウを超えました。",
                recovery: recovery ?? "Chunking デモのように文章を分割するか、履歴を削って再実行してください。"
            )
        case .assetsUnavailable(let context):
            return LabError(
                category: .modelUnavailable,
                technicalDetail: "assetsUnavailable: \(context.debugDescription)",
                userMessage: "モデルアセットを利用できません。",
                recovery: recovery ?? "Apple Intelligence の有効化とモデルのダウンロード完了を確認してください。"
            )
        case .guardrailViolation(let context):
            return LabError(
                category: .guardrailViolation,
                technicalDetail: "guardrailViolation: \(context.debugDescription)",
                userMessage: "安全性ガードレールにより生成が停止しました。",
                recovery: recovery ?? "プロンプトの表現を変更して再実行してください。"
            )
        case .unsupportedGuide(let context):
            return LabError(
                category: .unsupportedGuide,
                technicalDetail: "unsupportedGuide: \(context.debugDescription)",
                userMessage: "指定した @Guide 制約はモデルが解釈できません。",
                recovery: recovery ?? "@Guide の制約を単純な範囲や列挙に変更してください。"
            )
        case .unsupportedLanguageOrLocale(let context):
            return LabError(
                category: .unsupportedLanguage,
                technicalDetail: "unsupportedLanguageOrLocale: \(context.debugDescription)",
                userMessage: "この言語 / ロケールはモデルが対応していません。",
                recovery: recovery ?? "Dashboard の Supported Languages に含まれる言語で入力してください。"
            )
        case .decodingFailure(let context):
            return LabError(
                category: .decodingFailure,
                technicalDetail: "decodingFailure: \(context.debugDescription)",
                userMessage: "構造化出力のデコードに失敗しました。",
                recovery: recovery ?? "スキーマを単純化するか、@Guide で説明を補ってください。"
            )
        case .rateLimited(let context):
            return LabError(
                category: .rateLimited,
                technicalDetail: "rateLimited: \(context.debugDescription)",
                userMessage: "リクエストが多すぎます。",
                recovery: recovery ?? "少し待ってから再実行してください。"
            )
        case .concurrentRequests(let context):
            return LabError(
                category: .concurrentRequests,
                technicalDetail: "concurrentRequests: \(context.debugDescription)",
                userMessage: "同一セッションで並列にリクエストを送りました。",
                recovery: recovery ?? "前のリクエストの完了を待ってから再実行してください。"
            )
        case .refusal(_, let context):
            return LabError(
                category: .refusal,
                technicalDetail: "refusal: \(context.debugDescription)",
                userMessage: "モデルが応答を拒否しました。",
                recovery: recovery ?? "内容を変更して再実行してください。"
            )
        @unknown default:
            return LabError(
                category: .generationFailure,
                technicalDetail: "unknown GenerationError: \(error)",
                userMessage: "生成に失敗しました。",
                recovery: recovery ?? "入力を変更して再実行してください。"
            )
        }
    }

    private static let sdkVersion = "26.x"
}

// MARK: - Error Lab カタログ

/// 仕様書 §59: 発生しうるエラーを一覧化し、それぞれの4項目表示を確認できるようにする。
nonisolated struct ErrorCatalogEntry: Identifiable, Sendable {
    var id: String { error.category.rawValue }
    var error: LabError
    /// アプリ内で実際にこのエラーを再現できるか。
    var reproducible: Bool
    var howToReproduce: String

    static let all: [ErrorCatalogEntry] = [
        ErrorCatalogEntry(
            error: LabError(category: .contextExceeded,
                            technicalDetail: "LanguageModelSession.GenerationError.exceededContextWindowSize",
                            userMessage: "入力がコンテキストウィンドウを超えました。",
                            recovery: "文章を分割するか履歴を削ってください。"),
            reproducible: true,
            howToReproduce: "Context Exceeded デモで巨大プロンプトを実送信する"),
        ErrorCatalogEntry(
            error: LabError(category: .guardrailViolation,
                            technicalDetail: "LanguageModelSession.GenerationError.guardrailViolation",
                            userMessage: "安全性ガードレールにより生成が停止しました。",
                            recovery: "表現を変更してください。"),
            reproducible: true,
            howToReproduce: "Error Lab の Guardrail トリガーを実行する"),
        ErrorCatalogEntry(
            error: LabError(category: .unsupportedLanguage,
                            technicalDetail: "LanguageModelSession.GenerationError.unsupportedLanguageOrLocale",
                            userMessage: "この言語はモデルが対応していません。",
                            recovery: "対応言語で入力してください。"),
            reproducible: true,
            howToReproduce: "Error Lab で非対応言語のプロンプトを送る"),
        ErrorCatalogEntry(
            error: LabError(category: .decodingFailure,
                            technicalDetail: "LanguageModelSession.GenerationError.decodingFailure",
                            userMessage: "構造化出力のデコードに失敗しました。",
                            recovery: "スキーマを単純化してください。"),
            reproducible: true,
            howToReproduce: "Dynamic Schema で解釈困難なフィールド定義を送る"),
        ErrorCatalogEntry(
            error: LabError(category: .concurrentRequests,
                            technicalDetail: "LanguageModelSession.GenerationError.concurrentRequests",
                            userMessage: "同一セッションで並列にリクエストを送りました。",
                            recovery: "完了を待ってください。"),
            reproducible: true,
            howToReproduce: "Error Lab の並列リクエストトリガーを実行する"),
        ErrorCatalogEntry(
            error: LabError(category: .toolFailure,
                            technicalDetail: "LanguageModelSession.ToolCallError",
                            userMessage: "Tool の実行が失敗しました。",
                            recovery: "Tool の引数条件を確認してください。"),
            reproducible: true,
            howToReproduce: "Error Lab の失敗する Tool を登録したセッションを実行する"),
        ErrorCatalogEntry(
            error: LabError(category: .appleIntelligenceDisabled,
                            technicalDetail: "SystemLanguageModel.Availability.unavailable(.appleIntelligenceNotEnabled)",
                            userMessage: "Apple Intelligence が無効です。",
                            recovery: "設定から Apple Intelligence を有効にしてください。"),
            reproducible: false,
            howToReproduce: "端末設定で Apple Intelligence をオフにすると Dashboard に反映される"),
        ErrorCatalogEntry(
            error: LabError(category: .unsupportedDevice,
                            technicalDetail: "SystemLanguageModel.Availability.unavailable(.deviceNotEligible)",
                            userMessage: "この端末は対応していません。",
                            recovery: "対応端末で実行してください。"),
            reproducible: false,
            howToReproduce: "非対応端末 / Simulator で起動すると Dashboard に反映される"),
        ErrorCatalogEntry(
            error: LabError(category: .modelUnavailable,
                            technicalDetail: "SystemLanguageModel.Availability.unavailable(.modelNotReady)",
                            userMessage: "モデルの準備が完了していません。",
                            recovery: "しばらく待って再確認してください。"),
            reproducible: false,
            howToReproduce: "初回のモデルダウンロード中に発生する"),
        ErrorCatalogEntry(
            error: LabError(category: .rateLimited,
                            technicalDetail: "LanguageModelSession.GenerationError.rateLimited",
                            userMessage: "リクエストが多すぎます。",
                            recovery: "待ってから再実行してください。"),
            reproducible: false,
            howToReproduce: "バックグラウンドで大量リクエストを送った場合にOSが返す"),
        ErrorCatalogEntry(
            error: LabError(category: .imageError,
                            technicalDetail: "CGImage 変換失敗 / Vision リクエスト失敗",
                            userMessage: "画像を解析できませんでした。",
                            recovery: "別の画像を選択してください。"),
            reproducible: true,
            howToReproduce: "Vision デモで壊れた画像を渡す"),
        ErrorCatalogEntry(
            error: LabError(category: .pccUnavailable,
                            technicalDetail: "PrivateCloudComputeLanguageModel 型がSDKに存在しない",
                            userMessage: "PCC はこのSDKでは利用できません。",
                            recovery: "PCC 対応SDKに更新してください。"),
            reproducible: true,
            howToReproduce: "PCC デモを開くと SDK未提供として表示される"),
        ErrorCatalogEntry(
            error: LabError(category: .pccQuota,
                            technicalDetail: "PCC quota API がSDKに存在しない",
                            userMessage: "PCC のクォータを取得できません。",
                            recovery: "PCC 対応SDKに更新してください。"),
            reproducible: true,
            howToReproduce: "Quota デモを開くと SDK未提供として表示される"),
        ErrorCatalogEntry(
            error: LabError(category: .cameraError,
                            technicalDetail: "AVCaptureDevice が見つからない / 権限拒否",
                            userMessage: "カメラを利用できません。",
                            recovery: "実機で実行し、カメラ権限を許可してください。"),
            reproducible: true,
            howToReproduce: "Simulator で Camera デモを開く")
    ]
}
