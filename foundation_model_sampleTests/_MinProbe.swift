//
//  一時ファイル: 残り3件にどのスキーマ制約が効くかを最小回数で測る。反映後に削除する。
//

import Testing
import Foundation
import FoundationModels
@testable import foundation_model_sample

@Generable(description: "要約")
struct MinSummaryPattern {
    @Guide(description: "原文の要点をまとめた日本語の要約", .pattern(/.{80,140}/))
    var summary: String
}

@Generable(description: "箇条書き")
struct MinBulletsPattern {
    @Guide(description: "重要ポイント1", .pattern(/.{10,25}/))
    var point1: String
    @Guide(description: "重要ポイント2", .pattern(/.{10,25}/))
    var point2: String
    @Guide(description: "重要ポイント3", .pattern(/.{10,25}/))
    var point3: String
}

@Generable(description: "処方")
struct MinNestedMax2 {
    @Guide(description: "患者情報")
    var patient: PatientInfo
    @Guide(description: "文中に書かれた薬剤だけを列挙する", .maximumCount(2))
    var medicines: [Medicine]
}

@Generable(description: "処方")
struct MinNestedNoCount {
    @Guide(description: "患者情報")
    var patient: PatientInfo
    @Guide(description: "文中に書かれた薬剤だけを列挙する")
    var medicines: [Medicine]
}

@MainActor
struct MinProbe {

    private static let oneMedicine = "佐藤花子さん(48歳、P002)にレボフロキサシン500mgを1日1回朝食後5日分だけ出します。"
    private static let summaryInstructions = """
        あなたは正確な要約者です。原文に無い情報を加えないでください。
        原文をコピーせず、要点だけを日本語でまとめてください。
        """
    private static let nestedInstructions = """
        患者と処方薬を構造化してください。
        medicines には文中に書かれている薬剤だけを入れ、同じ薬剤を繰り返さないでください。
        """

    /// 1件ずつ独立した @Test にして、1つが詰まっても他の結果が取れるようにする。
    private func record(_ label: String, _ body: () async throws -> String) async {
        let started = Date()
        let outcome: String
        do { outcome = try await body() }
        catch { outcome = "NG " + LabError.map(error).errorType }
        Issue.record(Comment(rawValue: String(format: "MIN %@ [%.1fs] %@", label, Date().timeIntervalSince(started), outcome)))
    }

    @Test("A 要約 .pattern(/.{80,140}/)", .enabled(if: ModelGate.isAvailable, ModelGate.reason), .timeLimit(.minutes(1)))
    func summaryPattern() async {
        let engine = LabEngine()
        await record("A 要約 .pattern") {
            let session = engine.makeSession(instructions: Self.summaryInstructions)
            let r = try await session.respond(to: "原文:\n\(DemoData.longText)",
                                              generating: MinSummaryPattern.self,
                                              options: GenerationOptions(sampling: .greedy, temperature: 0.1, maximumResponseTokens: 300))
            return "\(r.content.summary.count)字: \(r.content.summary)"
        }
    }

    @Test("B 箇条書き .pattern(/.{10,25}/)", .enabled(if: ModelGate.isAvailable, ModelGate.reason), .timeLimit(.minutes(1)))
    func bulletsPattern() async {
        let engine = LabEngine()
        await record("B 箇条書き .pattern") {
            let session = engine.makeSession(instructions: Self.summaryInstructions)
            let r = try await session.respond(to: "原文:\n\(DemoData.longText)",
                                              generating: MinBulletsPattern.self,
                                              options: GenerationOptions(sampling: .greedy, temperature: 0.1, maximumResponseTokens: 300))
            return [r.content.point1, r.content.point2, r.content.point3].map { "\($0.count)字:\($0)" }.joined(separator: " | ")
        }
    }

    @Test("C 配列 .maximumCount(2)", .enabled(if: ModelGate.isAvailable, ModelGate.reason), .timeLimit(.minutes(1)))
    func nestedMax2() async {
        let engine = LabEngine()
        await record("C 配列 .maximumCount(2)") {
            let session = engine.makeSession(instructions: Self.nestedInstructions)
            let r = try await session.respond(to: Self.oneMedicine, generating: MinNestedMax2.self,
                                              options: GenerationOptions(sampling: .greedy, temperature: 0.1, maximumResponseTokens: 400))
            return "\(r.content.medicines.count)件: \(r.content.medicines.map(\.name).joined(separator: ","))"
        }
    }

    @Test("D 配列 制約なし", .enabled(if: ModelGate.isAvailable, ModelGate.reason), .timeLimit(.minutes(1)))
    func nestedNoCount() async {
        let engine = LabEngine()
        await record("D 配列 制約なし") {
            let session = engine.makeSession(instructions: Self.nestedInstructions)
            let r = try await session.respond(to: Self.oneMedicine, generating: MinNestedNoCount.self,
                                              options: GenerationOptions(sampling: .greedy, temperature: 0.1, maximumResponseTokens: 400))
            return "\(r.content.medicines.count)件: \(r.content.medicines.map(\.name).joined(separator: ","))"
        }
    }
}
