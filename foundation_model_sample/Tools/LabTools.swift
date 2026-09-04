//
//  LabTools.swift
//  Foundation Models Lab
//
//  仕様書 §23-§27, §33, §34: FoundationModels の Tool protocol を実装した本物の Tool 群。
//  モデルが呼び出しを決め、call(arguments:) がアプリ側のデータへアクセスする。
//

import Foundation
import CoreGraphics
import Vision
import FoundationModels

// MARK: - DEMO 16 WeatherTool

/// 外部APIは使わず固定データを返す（仕様書 §23）。
nonisolated struct WeatherTool: Tool {
    let name = "getWeather"
    let description = "指定した都市の現在の気温を返します。日本国内の都市に対応しています。"
    let recorder: ToolCallRecorder

    @Generable
    struct Arguments {
        @Guide(description: "気温を調べたい都市名。例: 東京, 金沢, 大阪")
        var city: String
    }

    private static let table = ["東京": 28, "金沢": 26, "大阪": 30, "札幌": 22, "那覇": 32]

    func call(arguments: Arguments) async throws -> String {
        let id = recorder.begin(name, arguments: "{ \"city\": \"\(arguments.city)\" }")
        guard let temperature = Self.table.first(where: { arguments.city.contains($0.key) })?.value else {
            let message = "\(arguments.city) のデータはありません。対応都市: \(Self.table.keys.sorted().joined(separator: ", "))"
            recorder.finish(id, output: message, failed: true)
            return message
        }
        let output = "\(arguments.city)の気温は\(temperature)℃です。"
        recorder.finish(id, output: output)
        return output
    }
}

// MARK: - DEMO 17 DrugSearchTool

/// ローカルの DrugDatabase.json を検索する（仕様書 §24）。
nonisolated struct DrugSearchTool: Tool {
    let name = "searchDrug"
    let description = "薬剤名から薬効・分類・注意事項を調べます。在庫数は返しません。"
    let recorder: ToolCallRecorder

    @Generable
    struct Arguments {
        @Guide(description: "調べたい薬剤名。用量は付いていなくてもよい。例: アムロジピン")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        let id = recorder.begin(name, arguments: "{ \"name\": \"\(arguments.name)\" }")
        guard let drug = DemoData.drug(matching: arguments.name) else {
            let message = "\(arguments.name) は薬品マスターに存在しません。登録薬: \(DemoData.drugNames.joined(separator: ", "))"
            recorder.finish(id, output: message, failed: true)
            return message
        }
        let output = """
        name: \(drug.name)
        genericName: \(drug.genericName)
        category: \(drug.category)
        effect: \(drug.effect)
        caution: \(drug.caution)
        """
        recorder.finish(id, output: output)
        return output
    }
}

// MARK: - DEMO 18 InventoryTool

/// 在庫を照会する（仕様書 §25）。
nonisolated struct InventoryTool: Tool {
    let name = "checkInventory"
    let description = "薬剤名から現在の在庫数と発注点を調べます。薬効は返しません。"
    let recorder: ToolCallRecorder
    let store: InventoryStore

    @Generable
    struct Arguments {
        @Guide(description: "在庫を調べたい薬剤名")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        let id = recorder.begin(name, arguments: "{ \"name\": \"\(arguments.name)\" }")
        guard let record = store.record(named: arguments.name) else {
            let message = "\(arguments.name) は在庫マスターに存在しません。"
            recorder.finish(id, output: message, failed: true)
            return message
        }
        let output = "\(record.name): 在庫 \(record.stock)\(record.unit) / 発注点 \(record.reorderPoint)\(record.unit) / 判定 \(record.isLow ? "在庫不足" : "十分")"
        recorder.finish(id, output: output)
        return output
    }
}

// MARK: - PatientTool

/// 患者を検索する（仕様書 §25, §45 Session Property 連携）。
nonisolated struct PatientTool: Tool {
    let name = "findPatient"
    let description = "患者名またはIDから患者情報を調べます。名前が省略された場合は現在選択中の患者を返します。"
    let recorder: ToolCallRecorder
    /// 仕様書 §53 Session Property: セッション共有状態。名前が来なければこれを使う。
    let selectedPatientId: String?

    @Generable
    struct Arguments {
        @Guide(description: "患者名または患者ID。指定がなければ空文字にする")
        var nameOrId: String
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.nameOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        let usedSessionProperty = query.isEmpty
        let id = recorder.begin(
            name,
            arguments: "{ \"nameOrId\": \"\(query)\" }" + (usedSessionProperty ? "\n// 空だったため Session Property の selectedPatientId=\(selectedPatientId ?? "nil") を使用" : "")
        )

        let patient: Patient?
        if usedSessionProperty {
            patient = DemoData.patients.first { $0.id == selectedPatientId }
        } else {
            patient = DemoData.patient(matching: query)
        }

        guard let patient else {
            let message = "該当する患者が見つかりません。登録患者: \(DemoData.patients.map(\.name).joined(separator: ", "))"
            recorder.finish(id, output: message, failed: true)
            return message
        }
        let output = "id: \(patient.id)\nname: \(patient.name)\nage: \(patient.age)\nnote: \(patient.note)"
        recorder.finish(id, output: output)
        return output
    }
}

// MARK: - PrescriptionTool

nonisolated struct PrescriptionTool: Tool {
    let name = "listPrescriptions"
    let description = "患者IDから、その患者に現在処方されている薬剤の一覧を返します。"
    let recorder: ToolCallRecorder

    @Generable
    struct Arguments {
        @Guide(description: "患者ID。例: P001")
        var patientId: String
    }

    func call(arguments: Arguments) async throws -> String {
        let id = recorder.begin(name, arguments: "{ \"patientId\": \"\(arguments.patientId)\" }")
        let records = DemoData.prescriptions(forPatientId: arguments.patientId)
        guard !records.isEmpty else {
            let message = "\(arguments.patientId) の処方はありません。"
            recorder.finish(id, output: message, failed: true)
            return message
        }
        let output = records.map(\.summary).joined(separator: "\n")
        recorder.finish(id, output: output)
        return output
    }
}

// MARK: - DEMO 20 Side effect tool

/// 仕様書 §27 / §76: モデルは「要求」までしか進めない。
/// 実際の書き換えは人間が Execute を押したときにアプリ側が行う。
nonisolated struct InventoryUpdateTool: Tool {
    let name = "requestInventoryUpdate"
    let description = "在庫数の変更を申請します。この Tool は申請を記録するだけで、実際の在庫は変更しません。変更は担当者の承認後に反映されます。"
    let recorder: ToolCallRecorder
    /// 申請を受け取る箱。承認待ちキューへ積む。
    let pendingRequests: PendingSideEffectQueue

    @Generable
    struct Arguments {
        @Guide(description: "在庫を変更したい薬剤名")
        var name: String
        @Guide(description: "変更後の在庫数。欠品にする場合は0", .minimum(0))
        var newStock: Int
        @Guide(description: "変更する理由")
        var reason: String
    }

    func call(arguments: Arguments) async throws -> String {
        let id = recorder.begin(
            name,
            arguments: "{ \"name\": \"\(arguments.name)\", \"newStock\": \(arguments.newStock), \"reason\": \"\(arguments.reason)\" }"
        )
        guard let record = DemoData.inventory.first(where: { arguments.name.contains($0.name) || $0.name.contains(arguments.name) }) else {
            let message = "\(arguments.name) は在庫マスターに存在しないため申請できません。"
            recorder.finish(id, output: message, failed: true)
            return message
        }
        pendingRequests.enqueue(
            SideEffectRequest(
                toolName: name,
                drugName: record.name,
                currentStock: record.stock,
                newStock: arguments.newStock,
                reason: arguments.reason
            )
        )
        let output = "在庫変更の申請を受け付けました（\(record.name): \(record.stock) → \(arguments.newStock)）。承認待ちです。この時点では在庫は変更されていません。"
        recorder.finish(id, output: output)
        return output
    }
}

/// 承認待ちの副作用要求。
nonisolated struct SideEffectRequest: Identifiable, Sendable, Equatable {
    let id = UUID()
    var toolName: String
    var drugName: String
    var currentStock: Int
    var newStock: Int
    var reason: String

    var summary: String { "\(drugName): \(currentStock) → \(newStock)" }
}

nonisolated final class PendingSideEffectQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [SideEffectRequest] = []

    func enqueue(_ request: SideEffectRequest) {
        lock.withLock { requests.append(request) }
    }

    func drain() -> [SideEffectRequest] {
        lock.withLock {
            let current = requests
            requests.removeAll()
            return current
        }
    }
}

// MARK: - DEMO 25 OCRTool

/// 仕様書 §33: Vision の OCR を Tool としてセッションへ登録する。
/// 解析対象の画像はアプリ側が保持し、モデルは「読み取れ」と指示するだけ。
nonisolated struct OCRTool: Tool {
    let name = "readTextFromImage"
    let description = "現在選択されている画像に写っている文字を Vision の OCR で読み取って返します。引数は不要です。"
    let recorder: ToolCallRecorder
    let imageProvider: AnalyzableImageProvider

    @Generable
    struct Arguments {
        @Guide(description: "読み取り対象。画像全体なら \"all\" を指定する", .anyOf(["all"]))
        var target: String
    }

    func call(arguments: Arguments) async throws -> String {
        let id = recorder.begin(name, arguments: "{ \"target\": \"\(arguments.target)\" }")
        guard let image = imageProvider.currentImage() else {
            let message = "画像が選択されていません。"
            recorder.finish(id, output: message, failed: true)
            return message
        }
        let analysis = try await VisionAnalyzer().analyze(cgImage: image.cgImage, plan: .ocrOnly)
        let text = analysis.joinedText
        let output = text.isEmpty ? "画像から文字は検出されませんでした。" : text
        recorder.finish(id, output: output)
        return output
    }
}

// MARK: - DEMO 26 BarcodeReaderTool

/// 仕様書 §34: Vision のバーコード検出を Tool として登録する。
nonisolated struct BarcodeReaderTool: Tool {
    let name = "readBarcode"
    let description = "現在選択されている画像からバーコード・QRコードを検出し、種類とペイロードを返します。引数は不要です。"
    let recorder: ToolCallRecorder
    let imageProvider: AnalyzableImageProvider

    @Generable
    struct Arguments {
        @Guide(description: "検出対象。画像全体なら \"all\" を指定する", .anyOf(["all"]))
        var target: String
    }

    func call(arguments: Arguments) async throws -> String {
        let id = recorder.begin(name, arguments: "{ \"target\": \"\(arguments.target)\" }")
        guard let image = imageProvider.currentImage() else {
            let message = "画像が選択されていません。"
            recorder.finish(id, output: message, failed: true)
            return message
        }
        let analysis = try await VisionAnalyzer().analyze(cgImage: image.cgImage, plan: .barcodeOnly)
        guard !analysis.barcodes.isEmpty else {
            let message = "バーコードは検出されませんでした。"
            recorder.finish(id, output: message, failed: true)
            return message
        }
        let output = analysis.barcodes
            .map { "type: \($0.typeLabel)\npayload: \($0.payload)" }
            .joined(separator: "\n---\n")
        recorder.finish(id, output: output)
        return output
    }
}

/// 画像を Tool へ渡すための橋。MainActor 側の選択状態をロック越しに読む。
nonisolated final class AnalyzableImageProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var image: ImageBox?

    func set(_ image: ImageBox?) {
        lock.withLock { self.image = image }
    }

    func currentImage() -> ImageBox? {
        lock.withLock { image }
    }
}

// MARK: - Error Lab 用の必ず失敗する Tool

/// 仕様書 §59 Tool failure を実際に発生させる。
nonisolated struct FailingTool: Tool {
    struct DeliberateFailure: Error, LocalizedError {
        var errorDescription: String? { "この Tool は Error Lab のデモとして意図的に失敗します。" }
    }

    let name = "unstableLookup"
    let description = "在庫の同期状態を確認します。このデモ用 Tool は必ず失敗します。"
    let recorder: ToolCallRecorder

    @Generable
    struct Arguments {
        @Guide(description: "確認したい項目名")
        var key: String
    }

    func call(arguments: Arguments) async throws -> String {
        let id = recorder.begin(name, arguments: "{ \"key\": \"\(arguments.key)\" }")
        recorder.finish(id, output: "DeliberateFailure", failed: true)
        throw DeliberateFailure()
    }
}

// MARK: - Tool set factory

/// 仕様書 §52 Dynamic Tool Visibility: Profile ごとに公開する Tool を切り替える。
nonisolated struct ToolFactory: Sendable {
    let recorder: ToolCallRecorder
    let inventory: InventoryStore
    let pendingSideEffects: PendingSideEffectQueue
    let imageProvider: AnalyzableImageProvider
    var selectedPatientId: String?

    func tools(for names: Set<LabToolName>) -> [any Tool] {
        names.sorted { $0.rawValue < $1.rawValue }.map { tool(for: $0) }
    }

    func tool(for name: LabToolName) -> any Tool {
        switch name {
        case .weather: WeatherTool(recorder: recorder)
        case .drugSearch: DrugSearchTool(recorder: recorder)
        case .inventory: InventoryTool(recorder: recorder, store: inventory)
        case .patient: PatientTool(recorder: recorder, selectedPatientId: selectedPatientId)
        case .prescription: PrescriptionTool(recorder: recorder)
        case .inventoryUpdate: InventoryUpdateTool(recorder: recorder, pendingRequests: pendingSideEffects)
        case .ocr: OCRTool(recorder: recorder, imageProvider: imageProvider)
        case .barcode: BarcodeReaderTool(recorder: recorder, imageProvider: imageProvider)
        case .failing: FailingTool(recorder: recorder)
        }
    }
}

nonisolated enum LabToolName: String, CaseIterable, Identifiable, Sendable {
    case weather
    case drugSearch
    case inventory
    case patient
    case prescription
    case inventoryUpdate
    case ocr
    case barcode
    case failing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weather: "WeatherTool"
        case .drugSearch: "DrugSearchTool"
        case .inventory: "InventoryTool"
        case .patient: "PatientTool"
        case .prescription: "PrescriptionTool"
        case .inventoryUpdate: "InventoryUpdateTool"
        case .ocr: "OCRTool"
        case .barcode: "BarcodeReaderTool"
        case .failing: "FailingTool"
        }
    }

    var symbol: String {
        switch self {
        case .weather: "cloud.sun"
        case .drugSearch: "pills"
        case .inventory: "shippingbox"
        case .patient: "person.text.rectangle"
        case .prescription: "list.clipboard"
        case .inventoryUpdate: "square.and.pencil"
        case .ocr: "text.viewfinder"
        case .barcode: "barcode.viewfinder"
        case .failing: "exclamationmark.triangle"
        }
    }

    /// 副作用を持つか（仕様書 §76）。
    var hasSideEffect: Bool { self == .inventoryUpdate }
}
