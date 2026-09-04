//
//  DemoData.swift
//  Foundation Models Lab
//
//  仕様書 §74 デモデータ / §75 個人情報
//  患者データはすべて架空。Resources/*.json から読み込み、無ければ埋め込みフォールバックを使う。
//

import Foundation

// MARK: - Records

nonisolated struct Drug: Identifiable, Codable, Sendable, Equatable {
    var id: String { name }
    var name: String
    var genericName: String
    var category: String
    var effect: String
    var caution: String
    var barcodePayload: String

    var summary: String {
        "\(name) / \(category) / \(effect)"
    }
}

nonisolated struct Patient: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var name: String
    var age: Int
    var note: String
}

nonisolated struct PrescriptionRecord: Identifiable, Codable, Sendable, Equatable {
    var id: String { "\(patientId)-\(medicineName)" }
    var patientId: String
    var medicineName: String
    var dose: String
    var frequency: Int
    var timing: String
    var days: Int

    var summary: String {
        "\(medicineName) \(dose) 1日\(frequency)回 \(timing) \(days)日分"
    }
}

nonisolated struct InventoryRecord: Identifiable, Codable, Sendable, Equatable {
    var id: String { name }
    var name: String
    var stock: Int
    var unit: String
    var reorderPoint: Int

    var isLow: Bool { stock < reorderPoint }
    var summary: String { "\(name): \(stock)\(unit)（発注点 \(reorderPoint)\(unit)）" }
}

// MARK: - Store

/// Resources の JSON を読む静的ストア。Tool から nonisolated に参照される。
nonisolated enum DemoData {
    static let drugs: [Drug] = load("DrugDatabase", fallback: fallbackDrugs)
    static let patients: [Patient] = load("PatientDatabase", fallback: fallbackPatients)
    static let prescriptions: [PrescriptionRecord] = load("PrescriptionDatabase", fallback: fallbackPrescriptions)
    static let inventory: [InventoryRecord] = load("InventoryDatabase", fallback: fallbackInventory)

    static let drugNames: [String] = drugs.map(\.name)

    static func prescriptions(forPatientId id: String) -> [PrescriptionRecord] {
        prescriptions.filter { $0.patientId == id }
    }

    static func patient(matching query: String) -> Patient? {
        patients.first { query.contains($0.name) || $0.name.contains(query) || $0.id == query }
            ?? patients.first { query.contains($0.name.prefix(2)) }
    }

    static func drug(matching query: String) -> Drug? {
        if let exact = drugs.first(where: { $0.name == query }) { return exact }
        if let contained = drugs.first(where: { query.contains($0.name) || $0.name.contains(query) }) { return contained }
        // 「アムロジピン」のように用量抜きで来るケース。
        let stripped = query.replacingOccurrences(of: #"[0-9]+\s*(mg|錠|g|ml)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }
        return drugs.first { $0.name.contains(stripped) || $0.genericName.localizedCaseInsensitiveContains(stripped) }
            ?? drugs.first { stripped.contains($0.name.prefix(4)) }
    }

    static func drug(forBarcode payload: String) -> Drug? {
        drugs.first { $0.barcodePayload == payload }
            ?? drugs.first { payload.contains($0.barcodePayload) }
    }

    // MARK: Long text presets

    /// 仕様書 §12 Summarization / §42 Chunking 用の長文。
    static let longText = """
    Apple Intelligence 対応デバイスでは、FoundationModels framework を通じてオンデバイスの言語モデルへ直接アクセスできます。\
    アプリは LanguageModelSession を作り、Instructions で振る舞いを固定し、Prompt を送って応答を受け取ります。\
    応答は単なる文字列に留まらず、@Generable を付けた Swift の型として受け取ることができ、@Guide で値の範囲や選択肢を宣言すれば、\
    モデルの出力はその制約の中に収まります。これは JSON を文字列としてパースする従来の手法と比べて、型の安全性と失敗時の扱いやすさが大きく異なります。\
    さらに Tool protocol を実装した型をセッションに登録すると、モデルは必要に応じてその Tool を呼び出し、\
    ローカルのデータベース照会や計算をアプリ側のコードに委譲できます。呼び出しの経過は Transcript として観測でき、\
    どの Tool にどんな引数が渡り、何が返ってきたかを開発者は完全に把握できます。\
    オンデバイス実行であるためネットワークを介さず、入力内容が端末外へ出ません。一方でコンテキストウィンドウには上限があるため、\
    長い文書を扱う場合は分割して個別に要約し、その要約をさらに統合するという二段構えの処理が必要になります。\
    トークン数は SystemLanguageModel.tokenCount(for:) で事前に測れるので、送信前に上限を超えるかどうかを判定できます。\
    prewarm を呼んでおけば初回応答までの待ち時間を短縮できる可能性がありますが、実際の効果は端末の状態に依存します。
    """

    /// 仕様書 §15 Entity Extraction のサンプル。処方文なので Generable / Nested Object で使う。
    static let extractionSample = "田中太郎さんにロキソプロフェン60mgが1日3回毎食後7日分処方されました。あわせてアムロジピン5mgを朝食後1錠28日分継続します。"

    /// Extraction デモの既定入力。薬剤名を含まない業務メモ。
    ///
    /// 実測（iOS 26.5 / 端末モデル）: 薬剤名を [String] 配列として返すスキーマは、
    /// 既定のガードレールで必ず停止する（27回中27回 guardrailViolation）。
    /// 単値フィールド（Prescription.medicineName など）なら同じ薬剤名でも通る。
    /// Extraction は可変長の配列を返すデモなので、既定入力は薬剤名を含まないものにしている。
    static let entityExtractionSample = "山田太郎さんが4月10日にA4コピー用紙を20箱、トナーカートリッジを3本発注しました。納品は4月17日予定で、受け取りは佐藤花子さんが担当します。"

    /// 仕様書 §14 Classification のサンプル。
    static let classificationSample = "アプリを起動するとログイン画面から進まなくなりました。パスワードは合っているはずです。"

    /// 仕様書 §16 Guided Generation のサンプル。
    static let prescriptionSample = "田中さんにアムロジピン5mgを朝食後1錠28日分"

    // MARK: Loading

    private static func load<T: Decodable>(_ resource: String, fallback: [T]) -> [T] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([T].self, from: data)
        else {
            return fallback
        }
        return decoded
    }

    // MARK: Fallbacks (バンドルに JSON が入らなかった場合)

    private static let fallbackDrugs = [
        Drug(name: "アムロジピン5mg", genericName: "amlodipine besilate", category: "Ca拮抗薬",
             effect: "血管を広げて血圧を下げます。高血圧症・狭心症に用いられます。",
             caution: "ふらつき、歯肉肥厚に注意。グレープフルーツジュースとの併用を避けます。",
             barcodePayload: "4987123456781"),
        Drug(name: "ロキソプロフェン60mg", genericName: "loxoprofen sodium hydrate", category: "NSAIDs",
             effect: "痛みや炎症、発熱を抑えます。",
             caution: "空腹時の服用を避けます。胃腸障害・腎機能低下に注意。",
             barcodePayload: "4987123456782"),
        Drug(name: "レボフロキサシン500mg", genericName: "levofloxacin hydrate", category: "ニューキノロン系抗菌薬",
             effect: "細菌のDNA複製を阻害して感染症を治療します。",
             caution: "腱障害、QT延長、金属カチオン含有製剤との相互作用に注意。",
             barcodePayload: "4987123456783"),
        Drug(name: "メトホルミン250mg", genericName: "metformin hydrochloride", category: "ビグアナイド系糖尿病薬",
             effect: "肝臓での糖新生を抑えて血糖値を下げます。",
             caution: "乳酸アシドーシス、造影剤使用前後の休薬に注意。",
             barcodePayload: "4987123456784"),
        Drug(name: "ランソプラゾール15mg", genericName: "lansoprazole", category: "プロトンポンプ阻害薬",
             effect: "胃酸の分泌を抑え、胃潰瘍や逆流性食道炎を治療します。",
             caution: "長期投与時の骨折リスク、クロピドグレルとの相互作用に注意。",
             barcodePayload: "4987123456785")
    ]

    private static let fallbackPatients = [
        Patient(id: "P001", name: "田中太郎", age: 65, note: "高血圧と腰痛で通院中"),
        Patient(id: "P002", name: "佐藤花子", age: 48, note: "感染症治療のため短期処方"),
        Patient(id: "P003", name: "鈴木一郎", age: 72, note: "糖尿病と胃炎の併用療法")
    ]

    private static let fallbackPrescriptions = [
        PrescriptionRecord(patientId: "P001", medicineName: "アムロジピン5mg", dose: "1錠", frequency: 1, timing: "朝食後", days: 28),
        PrescriptionRecord(patientId: "P001", medicineName: "ロキソプロフェン60mg", dose: "1錠", frequency: 3, timing: "毎食後", days: 7),
        PrescriptionRecord(patientId: "P002", medicineName: "レボフロキサシン500mg", dose: "1錠", frequency: 1, timing: "朝食後", days: 5),
        PrescriptionRecord(patientId: "P003", medicineName: "メトホルミン250mg", dose: "1錠", frequency: 2, timing: "朝夕食後", days: 30),
        PrescriptionRecord(patientId: "P003", medicineName: "ランソプラゾール15mg", dose: "1錠", frequency: 1, timing: "就寝前", days: 30)
    ]

    private static let fallbackInventory = [
        InventoryRecord(name: "アムロジピン5mg", stock: 80, unit: "錠", reorderPoint: 100),
        InventoryRecord(name: "ロキソプロフェン60mg", stock: 500, unit: "錠", reorderPoint: 200),
        InventoryRecord(name: "レボフロキサシン500mg", stock: 40, unit: "錠", reorderPoint: 100),
        InventoryRecord(name: "メトホルミン250mg", stock: 620, unit: "錠", reorderPoint: 200),
        InventoryRecord(name: "ランソプラゾール15mg", stock: 95, unit: "錠", reorderPoint: 100)
    ]
}

// MARK: - Mutable inventory (副作用Toolの対象)

/// 仕様書 §27 / §76: Tool が書き換える対象。更新は必ず人間の確認を経る。
nonisolated final class InventoryStore: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: InventoryRecord]

    init(records: [InventoryRecord] = DemoData.inventory) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.name, $0) })
    }

    var all: [InventoryRecord] {
        lock.withLock { records.values.sorted { $0.name < $1.name } }
    }

    func record(named name: String) -> InventoryRecord? {
        lock.withLock {
            if let exact = records[name] { return exact }
            return records.values.first { name.contains($0.name) || $0.name.contains(name) }
        }
    }

    func setStock(_ stock: Int, for name: String) -> InventoryRecord? {
        lock.withLock {
            guard var record = records[name] ?? records.values.first(where: { name.contains($0.name) }) else { return nil }
            record.stock = max(0, stock)
            records[record.name] = record
            return record
        }
    }

    func reset() {
        lock.withLock {
            records = Dictionary(uniqueKeysWithValues: DemoData.inventory.map { ($0.name, $0) })
        }
    }
}
