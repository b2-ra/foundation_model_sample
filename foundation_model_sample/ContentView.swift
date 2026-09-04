//
//  ContentView.swift
//  foundation_model_sample
//
//  Foundation Models Lab — ナビゲーションシェル
//  仕様書 §6: NavigationSplitView を使う。iPhone 幅では自動的に NavigationStack と同じ挙動へ折り畳まれる。
//

import SwiftUI

struct ContentView: View {
    @State private var engine = LabEngine()
    /// 起動時は未選択にしておく。
    /// NavigationSplitView は iPhone 幅では NavigationStack と同じ挙動に折り畳まれるが、
    /// 折り畳み前に選択が入っていると詳細が push されないため、初期値は nil にする（仕様書 §6）。
    @State private var selection: LabDemo?
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            demoList
                .navigationTitle("Foundation Models Lab")
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let selection {
                DemoScreen(demo: selection, engine: engine)
            } else {
                ContentUnavailableView(
                    "デモを選択してください",
                    systemImage: "sparkles",
                    description: Text("リストから確認したい Foundation Models の機能を選びます。まずは Dashboard で、この端末とSDKで何が使えるかを確認してください。")
                )
            }
        }
        .task {
            engine.refreshEnvironment()
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var demoList: some View {
        List(selection: $selection) {
            Section {
                statusRow
            }

            ForEach(visibleGroups) { group in
                Section(group.title) {
                    ForEach(demos(in: group)) { demo in
                        label(for: demo).tag(demo)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "デモを検索")
    }

    private func label(for demo: LabDemo) -> some View {
        rowContent(for: demo)
            // 行をひとつの要素として扱う。
            // VoiceOver がアイコン名やバッジを読み上げず、UI テストからも一意に引ける。
            .accessibilityElement(children: .combine)
            .accessibilityLabel(demo.title)
            .accessibilityIdentifier("demo.\(demo.rawValue)")
    }

    private func rowContent(for demo: LabDemo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: demo.symbol)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(demo.title)
            Spacer(minLength: 0)
            if demo.isBeta {
                Text("BETA")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
            if demo.requiresUnavailableSDKFeature {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }
        }
    }

    /// サイドバー上部の環境ステータス（仕様書 §7 HOME / §60）。
    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.modelManager.availability.isAvailable ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(engine.modelManager.availability.isAvailable ? "Apple Intelligence Available" : "Apple Intelligence Unavailable")
                    .font(.caption.weight(.semibold))
            }
            Text("\(engine.modelManager.deviceName) · context \(engine.modelManager.contextSize.formatted())")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Search filtering

    private var filtered: [LabDemo] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return LabDemo.allCases }
        return LabDemo.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
                || $0.group.title.localizedCaseInsensitiveContains(query)
                || $0.usedAPIs.contains { $0.symbol.localizedCaseInsensitiveContains(query) }
        }
    }

    private var visibleGroups: [LabGroup] {
        let available = Set(filtered.map(\.group))
        return LabGroup.allCases.filter { available.contains($0) }
    }

    private func demos(in group: LabGroup) -> [LabDemo] {
        filtered.filter { $0.group == group }
    }
}

#Preview {
    ContentView()
}
