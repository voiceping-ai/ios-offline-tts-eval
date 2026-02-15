import SwiftUI

struct BenchmarkView: View {
    @Environment(AppModel.self) private var app
    @State private var sortKey: ResultSortKey = .overallScore

    var body: some View {
        Form {
            Section("Dataset") {
                Picker("Prompts", selection: Bindable(app).benchmarkDataset) {
                    ForEach(PromptDataset.allCases) { ds in
                        Text(ds.displayName).tag(ds)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Models") {
                ForEach(app.allModels, id: \.id) { model in
                    Toggle(isOn: bindingForModelSelection(model.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName)
                            Text(model.engineId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if app.benchmarkSelectedModelIds.isEmpty {
                    Text("No models selected: Run will use all curated models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Run") {
                HStack {
                    Button(app.benchmarkRunning ? "Running..." : "Run Benchmark") {
                        app.runBenchmark()
                    }
                    .disabled(app.benchmarkRunning)
                    .buttonStyle(.borderedProminent)

                    Button("Cancel") {
                        app.cancelBenchmark()
                    }
                    .disabled(!app.benchmarkRunning)
                    .buttonStyle(.bordered)
                }

                if !app.benchmarkProgress.isEmpty {
                    Text(app.benchmarkProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Export") {
                if let artifacts = app.benchmarkArtifacts {
                    VStack(alignment: .leading, spacing: 8) {
                        ShareLink(item: artifacts.jsonURL) {
                            Label("Share JSON", systemImage: "square.and.arrow.up")
                        }
                        ShareLink(item: artifacts.runsCSVURL) {
                            Label("Share Runs CSV", systemImage: "square.and.arrow.up")
                        }
                        ShareLink(item: artifacts.summaryCSVURL) {
                            Label("Share Summary CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Text("Run a benchmark to export results.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Results") {
                if let export = app.benchmarkExport {
                    Picker("Sort", selection: $sortKey) {
                        ForEach(ResultSortKey.allCases) { k in
                            Text(k.displayName).tag(k)
                        }
                    }

                    BenchmarkScoreTable(summaries: sortedSummaries(export.summaries, by: sortKey))
                } else {
                    Text("Run a benchmark to see a score table.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Benchmark")
    }

    private func bindingForModelSelection(_ modelId: String) -> Binding<Bool> {
        Binding(
            get: { app.benchmarkSelectedModelIds.contains(modelId) },
            set: { isOn in
                if isOn {
                    app.benchmarkSelectedModelIds.insert(modelId)
                } else {
                    app.benchmarkSelectedModelIds.remove(modelId)
                }
            }
        )
    }

    private func sortedSummaries(_ summaries: [ModelSummary], by key: ResultSortKey) -> [ModelSummary] {
        let ascending: Bool = {
            switch key {
            case .medianRtf, .medianCpuAvg, .medianMemMaxMB:
                return true
            default:
                return false
            }
        }()

        func value(_ s: ModelSummary) -> Double {
            switch key {
            case .overallScore:
                return s.score.overallScore0to100
            case .speedScore:
                // Put "N/A" (baseline) last when sorting best-first.
                return s.score.speedScore ?? -1
            case .throughputScore:
                return s.score.throughputScore
            case .resourceScore:
                return s.score.resourceScore
            case .medianRtf:
                // Lower is better; put "N/A" last.
                return s.score.medianRtf ?? Double.greatestFiniteMagnitude
            case .medianTps:
                return s.score.medianTokensPerSecond
            case .medianCpuAvg:
                return s.score.medianCpuAvg
            case .medianMemMaxMB:
                return s.score.medianMemMaxMB
            }
        }

        return summaries.sorted { a, b in
            let va = value(a)
            let vb = value(b)
            if ascending {
                return va < vb
            }
            return va > vb
        }
    }
}

private enum ResultSortKey: String, CaseIterable, Identifiable {
    case overallScore
    case speedScore
    case throughputScore
    case resourceScore
    case medianRtf
    case medianTps
    case medianCpuAvg
    case medianMemMaxMB

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overallScore: return "Overall"
        case .speedScore: return "Speed Score"
        case .throughputScore: return "Tok/s Score"
        case .resourceScore: return "Resource Score"
        case .medianRtf: return "Median RTF"
        case .medianTps: return "Median Tok/s"
        case .medianCpuAvg: return "Median CPU"
        case .medianMemMaxMB: return "Median Mem"
        }
    }
}

private struct BenchmarkScoreTable: View {
    let summaries: [ModelSummary]

    private let modelWidth: CGFloat = 260
    private let engineWidth: CGFloat = 130
    private let numWidth: CGFloat = 84

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 8) {
                headerRow
                ForEach(summaries, id: \.modelId) { s in
                    row(s)
                }
            }
            .font(.system(.caption, design: .monospaced))
        }
        .scrollIndicators(.automatic)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Model").frame(width: modelWidth, alignment: .leading)
            Text("Engine").frame(width: engineWidth, alignment: .leading)
            Text("Overall").frame(width: numWidth, alignment: .trailing)
            Text("Speed").frame(width: numWidth, alignment: .trailing)
            Text("Tok/s").frame(width: numWidth, alignment: .trailing)
            Text("Res").frame(width: numWidth, alignment: .trailing)
            Text("RTF").frame(width: numWidth, alignment: .trailing)
            Text("TPS").frame(width: numWidth, alignment: .trailing)
            Text("CPU").frame(width: numWidth, alignment: .trailing)
            Text("Mem").frame(width: numWidth, alignment: .trailing)
        }
        .foregroundStyle(.secondary)
    }

    private func row(_ s: ModelSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(s.modelDisplayName).frame(width: modelWidth, alignment: .leading)
            Text(s.engineId).foregroundStyle(.secondary).frame(width: engineWidth, alignment: .leading)

            numberCell(s.score.overallScore0to100)
            numberCell(s.score.speedScore)
            numberCell(s.score.throughputScore)
            numberCell(s.score.resourceScore)
            numberCell(s.score.medianRtf)
            numberCell(s.score.medianTokensPerSecond)
            numberCell(s.score.medianCpuAvg)
            numberCell(s.score.medianMemMaxMB)
        }
    }

    @ViewBuilder
    private func numberCell(_ v: Double?) -> some View {
        if let v {
            Text(String(format: "%.2f", v))
                .monospacedDigit()
                .frame(width: numWidth, alignment: .trailing)
        } else {
            Text("-")
                .foregroundStyle(.secondary)
                .frame(width: numWidth, alignment: .trailing)
        }
    }

    private func numberCell(_ v: Double) -> some View {
        Text(String(format: "%.2f", v))
            .monospacedDigit()
            .frame(width: numWidth, alignment: .trailing)
    }
}
