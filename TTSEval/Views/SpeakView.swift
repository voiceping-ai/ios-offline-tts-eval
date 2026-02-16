import SwiftUI

struct SpeakView: View {
    @Environment(AppModel.self) private var app

    private var selectedModel: TTSModel? {
        app.model(for: app.selectedModelId)
    }

    var body: some View {
        Form {
            Section("Text") {
                TextEditor(text: Bindable(app).inputText)
                    .frame(minHeight: 120)
                    .font(.body)
            }

            Section("Model") {
                Picker("Voice Model", selection: Bindable(app).selectedModelId) {
                    ForEach(app.allModels, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }

                if let model = selectedModel {
                    modelStatusRow(model)
                }
            }

            Section("Controls") {
                Stepper("Speaker ID: \(app.synthesisSettings.sid)", value: Bindable(app).synthesisSettings.sid, in: 0...32)

                HStack {
                    Text("Speed")
                    Slider(value: Bindable(app).synthesisSettings.speed, in: 0.5...1.5, step: 0.05)
                    Text(String(format: "%.2f", app.synthesisSettings.speed))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if selectedModel?.engineId == TTSEngineIds.avSpeech {
                    HStack {
                        Text("Native Rate")
                        Slider(value: Bindable(app).synthesisSettings.nativeRate, in: 0...1, step: 0.05)
                        Text(String(format: "%.2f", app.synthesisSettings.nativeRate))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Normalize Audio", isOn: Bindable(app).synthesisSettings.normalizeAudio)
            }

            Section("Actions") {
                HStack {
                    Button("Speak") {
                        app.speak()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Stop") {
                        app.stop()
                    }
                    .buttonStyle(.bordered)
                }

                if let model = selectedModel {
                    if case .notDownloaded = app.status(for: model.id) {
                        if !model.artifacts.isEmpty {
                            Button("Download Model") {
                                app.downloadSelectedModel()
                            }
                        } else if !model.localRequiredPaths.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("This model must be imported locally (not downloaded).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Scan Imports") {
                                    app.importPendingBundles()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            Section("Metrics") {
                if let m = app.lastMetrics {
                    MetricsView(metrics: m)
                } else {
                    Text("Run Speak to see metrics.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Speak")
    }

    @ViewBuilder
    private func modelStatusRow(_ model: TTSModel) -> some View {
        switch app.status(for: model.id) {
        case .ready:
            HStack {
                Text("Status")
                Spacer()
                Text("Ready")
                    .foregroundStyle(.green)
            }
        case .notDownloaded:
            HStack {
                Text("Status")
                Spacer()
                Text("Not downloaded")
                    .foregroundStyle(.secondary)
            }
        case .downloading(let progress, let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Downloading")
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel Download") {
                    app.cancelDownload(modelId: model.id)
                }
            }
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Status")
                    Spacer()
                    Text("Failed")
                        .foregroundStyle(.red)
                }
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.artifacts.isEmpty {
                    Button("Retry Download") {
                        app.downloadSelectedModel()
                    }
                } else if !model.localRequiredPaths.isEmpty {
                    Button("Scan Imports") {
                        app.importPendingBundles()
                    }
                }
            }
        case .unknown:
            HStack {
                Text("Status")
                Spacer()
                Text("Unknown")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MetricsView: View {
    let metrics: TTSEvalMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metricRow("Tokens", "\(metrics.tokenCount)")
            metricRow("Chars", "\(metrics.charCount)")
            metricRow("Synthesis (ms)", String(format: "%.1f", metrics.synthesisMs))
            metricRow("Audio (s)", metrics.audioSeconds.map { String(format: "%.2f", $0) } ?? "-")
            metricRow("RTF", metrics.rtf.map { String(format: "%.3f", $0) } ?? "-")
            metricRow("Tok/s", String(format: "%.2f", metrics.tokensPerSecond))
            metricRow("CPU avg", String(format: "%.1f", metrics.cpuAvg))
            metricRow("CPU max", String(format: "%.1f", metrics.cpuMax))
            metricRow("Mem max (MB)", String(format: "%.1f", metrics.memMaxMB))
            metricRow("Lang", metrics.detectedLanguage ?? "-")
        }
        .font(.system(.subheadline, design: .monospaced))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
        }
    }
}
