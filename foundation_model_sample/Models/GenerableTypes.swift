//
//  GenerableTypes.swift
//  Foundation Models Lab
//
//  仕様書 §16-19, §30, §32: @Generable / @Guide の実型定義。
//  すべて実際に respond(to:generating:) へ渡して生成させる。
//

import Foundation
import FoundationModels

// MARK: - DEMO 09 / 16 Guided Generation

@Generable(description: "処方内容を表す構造体")
struct Prescription: Equatable {
    @Guide(description: "患者の氏名。文章中に現れた表記をそのまま使う")
    var patientName: String

    @Guide(description: "薬剤名。規格の数値まで含めて1つの文字列にする（例: アムロジピン5mg）")
    var medicineName: String

    /// 実測: 入力に1回量が書かれていないと、medicineName から規格を切り離して dose に入れてしまう。
    /// 既定値を description で指示して切り離しを防ぐ。
    @Guide(description: "1回に服用する錠数。文中に無ければ 1錠 とする（例: 1錠, 2錠）")
    var dose: String

    @Guide(description: "1日あたりの服用回数", .range(1...6))
    var frequency: Int

    @Guide(description: "服用タイミング（例: 朝食後, 毎食後, 就寝前）")
    var timing: String

    @Guide(description: "処方日数", .range(1...180))
    var days: Int
}

// MARK: - DEMO 10 @Guide 比較

/// @Guide あり: 範囲と列挙で出力を縛る。
@Generable(description: "文章の感情分析結果（制約あり）")
struct GuidedSentiment {
    @Guide(description: "0から100までの整数で表した確信度", .range(0...100))
    var confidence: Int

    @Guide(description: "感情の分類", .anyOf(["positive", "negative", "neutral"]))
    var sentiment: String

    // .maximumCount(1) は下限が無く、この SDK では
    // 生成が GenerationError(-1) で落ちることがあった（実測）。
    // 件数を確定させると安定するので範囲で指定する。
    @Guide(description: "判定理由を1文で", .count(1...2))
    var reasons: [String]
}

/// @Guide なし: 同じ意味のフィールドを制約なしで生成させる。
@Generable(description: "文章の感情分析結果（制約なし）")
struct UnguidedSentiment {
    var confidence: Int
    var sentiment: String
    var reasons: [String]
}

// MARK: - DEMO 11 Enum Guided Generation

/// 判定基準を description に書いている。
/// enum のケース名（bug / operation / …）だけでは意味が伝わらず、実測で誤分類が出たため。
/// Apple「Generating Swift data structures with guided generation」:
/// descriptions を付けるとモデルが意味を理解しやすくなる（ただし短く保つ）。
@Generable(description: "問い合わせのカテゴリ。bug=不具合や異常動作、operation=操作方法や設定場所の質問、request=機能追加の要望、contract=契約やプランの手続き")
enum SupportCategory: String, CaseIterable, Equatable {
    case bug
    case operation
    case request
    case contract

    var display: String {
        switch self {
        case .bug: "障害"
        case .operation: "操作質問"
        case .request: "要望"
        case .contract: "契約"
        }
    }
}

/// 根拠（evidence）を category より前に宣言している。
/// Apple「Prompting an on-device foundation model」の Handle on-device reasoning:
/// 推論用のフィールドは最初のプロパティに置くこと。@Generable のプロパティは宣言順に生成されるため、
/// 先に根拠を書かせてから答えさせると分類が安定する。
@Generable(description: "問い合わせ分類の結果")
struct SupportClassification {
    @Guide(description: "分類の根拠となった文中の表現")
    var evidence: String

    @Guide(description: "問い合わせのカテゴリ")
    var category: SupportCategory
}

// MARK: - DEMO 12 Nested Generable

@Generable(description: "患者情報")
struct PatientInfo {
    @Guide(description: "患者ID。不明なら unknown")
    var id: String
    @Guide(description: "患者の氏名")
    var name: String
    @Guide(description: "年齢。不明なら 0", .range(0...120))
    var age: Int
}

@Generable(description: "1件の薬剤")
struct Medicine {
    @Guide(description: "薬剤名と用量")
    var name: String
    @Guide(description: "1回量")
    var dose: String
    @Guide(description: "1日あたりの回数", .range(1...6))
    var frequency: Int
    @Guide(description: "服用タイミング")
    var timing: String
}

@Generable(description: "患者と複数薬剤を含む処方全体")
struct PatientPrescription {
    /// 推論用フィールド。Apple「Prompting an on-device foundation model」の Handle on-device reasoning に従い、
    /// 答え（medicines）より前に置いている。@Generable のプロパティは宣言順に生成されるため、
    /// 先に「文中に何件あるか」を書かせてから配列を作らせる。
    /// 実測: これが無いと、薬剤1件の入力でも medicines を上限の6件まで同じ薬で埋めていた。
    @Guide(description: "文中に書かれている薬剤名を、出てきた順にカンマ区切りで書く。重複させない")
    var medicinesInText: String

    @Guide(description: "患者情報")
    var patient: PatientInfo
    @Guide(description: "文中に書かれた薬剤だけを、書かれた数だけ列挙する。同じ薬剤を繰り返さない", .count(1...6))
    var medicines: [Medicine]
    @Guide(description: "処方全体に対する注意事項")
    var notes: String
}

// MARK: - DEMO 08 Entity Extraction

@Generable(description: "文章から抽出したエンティティ")
struct ExtractedEntities {
    // 4本すべて制約なしの配列だと出力が伸び続けることがあり、
    // 長く暴れた応答が安全ガードレールで止められて抽出そのものが失敗していた。
    // 件数の上限を入れて生成を収束させる。
    @Guide(description: "文中に現れるすべての人物名。担当者や検品者も必ず含める", .maximumCount(6))
    var people: [String]
    @Guide(description: "登場した薬剤名や製品名", .maximumCount(8))
    var products: [String]
    @Guide(description: "数量・用量の表現", .maximumCount(8))
    var quantities: [String]
    @Guide(description: "日付や期間の表現", .maximumCount(8))
    var dates: [String]
}

// MARK: - DEMO 05 Summarization

@Generable(description: "1行要約")
struct OneLineSummaryResult {
    @Guide(description: "原文の要点を1文でまとめた日本語の要約")
    var summary: String
}

@Generable(description: "3行要約")
struct ThreeLineSummaryResult {
    @Guide(description: "1行目の要約")
    var line1: String
    @Guide(description: "2行目の要約")
    var line2: String
    @Guide(description: "3行目の要約")
    var line3: String
}

@Generable(description: "箇条書き要約")
struct BulletSummaryResult {
    /// 実測で原文の文をそのまま写していたため、「短く言い換える」ことを description に入れている。
    @Guide(description: "重要ポイント1。原文の文を写さず30文字以内に言い換える")
    var point1: String
    @Guide(description: "重要ポイント2。原文の文を写さず30文字以内に言い換える")
    var point2: String
    @Guide(description: "重要ポイント3。原文の文を写さず30文字以内に言い換える")
    var point3: String
    @Guide(description: "重要ポイント4。原文の文を写さず30文字以内に言い換える")
    var point4: String
    @Guide(description: "重要ポイント5。原文の文を写さず30文字以内に言い換える")
    var point5: String
}

@Generable(description: "100文字要約")
struct HundredCharacterSummaryResult {
    /// 実測: pattern guide で文字数を縛ると、このSDKでは生成が完了しないことがある。
    /// FoundationModels には説明で短く寄せ、最終的な表示長はアプリ側で正規化する。
    @Guide(description: "原文の要点をまとめた日本語の要約。80文字以上140文字以内")
    var summary: String
}

// MARK: - DEMO 22 / 24 画像の構造化出力

@Generable(description: "画像の被写体カテゴリ")
enum ImageCategory: String, CaseIterable, Equatable {
    case food
    case animal
    case landscape
    case document
    case person
    case product
    case screenshot
    case other

    var display: String {
        switch self {
        case .food: "食べ物"
        case .animal: "動物"
        case .landscape: "風景"
        case .document: "書類・文字"
        case .person: "人物"
        case .product: "製品・物体"
        case .screenshot: "スクリーンショット"
        case .other: "その他"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .animal: "pawprint"
        case .landscape: "mountain.2"
        case .document: "doc.text"
        case .person: "person"
        case .product: "shippingbox"
        case .screenshot: "iphone"
        case .other: "questionmark.square.dashed"
        }
    }
}

@Generable(description: "画像分類の結果")
struct ImageClassificationResult {
    @Guide(description: "最も当てはまるカテゴリ")
    var category: ImageCategory
    @Guide(description: "その判断の確信度を0から100の整数で", .range(0...100))
    var confidence: Int
    @Guide(description: "判断の根拠を1文で")
    var rationale: String
}

@Generable(description: "画像の構造化解析結果")
struct ImageAnalysis {
    @Guide(description: "画像に付ける短いタイトル")
    var title: String
    @Guide(description: "画像に写っている主要な物体", .count(1...8))
    var objects: [String]
    @Guide(description: "画像全体の説明文")
    var description: String
    @Guide(description: "画像に文字が含まれる場合、その要点。なければ空文字")
    var textSummary: String
    @Guide(description: "検索に使えるタグ", .count(1...6))
    var tags: [String]
}

// MARK: - DEMO 23 複数画像比較

@Generable(description: "2枚の画像の比較結果")
struct ImageComparison {
    @Guide(description: "2枚に共通している点", .count(1...4))
    var similarities: [String]
    @Guide(description: "2枚の相違点。3点以上挙げる", .count(3...6))
    var differences: [String]
    @Guide(description: "比較の総括を1文で")
    var verdict: String
}

// MARK: - 動画解析（このアプリで追加した拡張デモ）

@Generable(description: "動画の1シーンの説明")
struct VideoScene {
    @Guide(description: "シーンの開始秒数", .minimum(0))
    var startSeconds: Int
    @Guide(description: "そのシーンで何が起きているかの説明")
    var description: String
    @Guide(description: "そのシーンを表すラベル", .count(1...4))
    var labels: [String]
}

@Generable(description: "動画全体の解析結果")
struct VideoAnalysis {
    @Guide(description: "動画に付ける短いタイトル")
    var title: String
    @Guide(description: "動画全体の内容の説明")
    var summary: String
    @Guide(description: "時系列に並べたシーン", .count(1...8))
    var scenes: [VideoScene]
    @Guide(description: "動画中に読み取れた文字の要点。なければ空文字")
    var onScreenText: String
    @Guide(description: "動画を表すタグ", .count(1...6))
    var tags: [String]
}

// MARK: - リアルタイムカメラ解析（このアプリで追加した拡張デモ）

@Generable(description: "カメラに今映っているものの実況")
struct LiveFrameNarration {
    @Guide(description: "今カメラに映っているものを1文で")
    var scene: String
    @Guide(description: "注目すべき要素", .count(1...4))
    var highlights: [String]
    @Guide(description: "読み取れた文字があればその内容。なければ空文字")
    var readableText: String
    @Guide(description: "この場面で次に取れる行動の提案を1文で")
    var suggestion: String
}

// MARK: - contentTagging useCase 用

/// SystemLanguageModel(useCase: .contentTagging) 用のタグ型。
///
/// この useCase は制約が強く、実測で次の2点が分かっている。
///  - 素の `String` フィールドを含めると入力が数千トークンに膨らみ exceededContextWindowSize になる。
///    そのため配列フィールドだけで構成する。
///  - 薬剤名を含む文は refusal("May contain sensitive content") になる。
///    このアプリのデモデータは薬局が題材なので、この useCase には中立的な文を渡す。
@Generable(description: "文章に付けるタグ")
struct ContentTags {
    @Guide(description: "文章の主題を表すタグ", .maximumCount(3))
    var topics: [String]
}

// MARK: - DEMO 47 Agent Workflow

@Generable(description: "在庫確認の結論")
struct StockReport {
    @Guide(description: "対象となった患者名")
    var patientName: String
    @Guide(description: "在庫が不足している薬剤名の一覧")
    var lowStockMedicines: [String]
    @Guide(description: "在庫が十分な薬剤名の一覧")
    var sufficientMedicines: [String]
    @Guide(description: "薬剤師に向けた申し送り文")
    var recommendation: String
}
