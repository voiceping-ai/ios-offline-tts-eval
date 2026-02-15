import Foundation
import Observation
import UIKit

enum ModelStatus: Equatable, Sendable {
    case unknown
    case notDownloaded
    case downloading(progress: Double, message: String)
    case ready
    case failed(String)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

@MainActor
@Observable
final class AppModel {
    // Speak
    var inputText: String = "Hello. This is a quick TTS test."
    var synthesisSettings: TTSSynthesisSettings = .init()
    var selectedModelId: String = TTSModelCatalog.baselineAVSpeech.id

    var isSpeaking: Bool = false
    var lastMetrics: TTSEvalMetrics?

    // Models
    private(set) var curatedModels: [TTSModel] = TTSModelCatalog.curated
    private(set) var customModels: [TTSModel] = []
    private(set) var modelStatus: [String: ModelStatus] = [:]

    // Benchmark
    var benchmarkDataset: PromptDataset = .short
    var benchmarkSelectedModelIds: Set<String> = []
    var benchmarkRunning: Bool = false
    var benchmarkProgress: String = ""
    var benchmarkExport: BenchmarkExport?
    var benchmarkArtifacts: ExportArtifacts?

    // Errors
    var lastError: String?

    // Private
    private let engineRegistry = TTSEngineRegistry.shared
    private let audioPlayback = AudioPlaybackService()
    private let runner = TTSEvalRunner()

    private var speakTask: Task<Void, Never>?
    private var benchmarkTask: Task<Void, Never>?
    private var downloaderByModelId: [String: HuggingFaceDownloader] = [:]
    private var didAutorun: Bool = false
    private var lastAutorunStatusWriteAt: CFAbsoluteTime = 0
    private var lastAutorunStatusText: String = ""

    init() {
        audioPlayback.onPlaybackStateChanged = { [weak self] playing in
            self?.isSpeaking = playing
        }
        loadCustomModels()
        refreshStatuses()
        loadLastBenchmarkExport()

        if let saved = UserDefaults.standard.string(forKey: "ttseval.selectedModelId"),
           allModels.contains(where: { $0.id == saved }) {
            selectedModelId = saved
        }
    }

    var allModels: [TTSModel] {
        curatedModels + customModels
    }

    func autorunIfRequested() async {
        guard !didAutorun else { return }
        didAutorun = true

        let env = ProcessInfo.processInfo.environment
        guard let modeRaw = env["TTSEVAL_AUTORUN"], !modeRaw.isEmpty else {
            return
        }

        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        let mode = modeRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch mode {
        case "benchmark":
            await runAutorunBenchmark(env: env)
        default:
            print("TTSEVAL_AUTORUN: unknown mode '\(modeRaw)'; supported: benchmark")
        }
    }

    private func runAutorunBenchmark(env: [String: String]) async {
        let datasetRaw = (env["TTSEVAL_DATASET"] ?? "short").lowercased()
        let dataset = PromptDataset(rawValue: datasetRaw) ?? .short
        let promptLimit: Int? = {
            guard let raw = env["TTSEVAL_PROMPT_LIMIT"], let n = Int(raw), n > 0 else { return nil }
            return n
        }()

        resetAutorunStatusLog()
        let header = "starting benchmark dataset=\(dataset.rawValue) promptLimit=\(promptLimit.map(String.init) ?? "nil")"
        print("TTSEVAL_AUTORUN: \(header)")
        writeAutorunStatus(header, force: true)

        benchmarkArtifacts = nil
        benchmarkRunning = true
        benchmarkProgress = "Autorun benchmark starting..."
        var success = false

        do {
            let export = try await runner.run(
                models: curatedModels,
                dataset: dataset,
                synthesisSettings: synthesisSettings,
                promptLimit: promptLimit
            ) { update in
                Task { @MainActor [weak self] in
                    self?.writeAutorunStatus("\(update.modelId): \(Int(update.fraction0to1 * 100))% \(update.message)")
                    self?.benchmarkProgress = "\(update.modelId): \(Int(update.fraction0to1 * 100))% \(update.message)"
                }
            }

            benchmarkExport = export
            let artifacts = try ExportService.write(export: export)
            benchmarkArtifacts = artifacts
            benchmarkProgress = "Autorun exported."
            success = true

            print("TTSEVAL_AUTORUN: exported_json=\(artifacts.jsonURL.path)")
            print("TTSEVAL_AUTORUN: exported_runs_csv=\(artifacts.runsCSVURL.path)")
            print("TTSEVAL_AUTORUN: exported_summary_csv=\(artifacts.summaryCSVURL.path)")
            writeAutorunStatus("exported results.json + runs.csv + summary.csv", force: true)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            benchmarkProgress = "Autorun failed."
            print("TTSEVAL_AUTORUN: error=\(lastError ?? "unknown")")
            writeAutorunStatus("error: \(lastError ?? "unknown")", force: true)
        }

        benchmarkRunning = false
        print("TTSEVAL_AUTORUN: done success=\(success)")
        writeAutorunStatus("done success=\(success)", force: true)
    }

    private func writeAutorunStatus(_ message: String, force: Bool = false) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = CFAbsoluteTimeGetCurrent()
        if !force {
            if trimmed == lastAutorunStatusText { return }
            if now - lastAutorunStatusWriteAt < 0.8 { return }
        }

        lastAutorunStatusText = trimmed
        lastAutorunStatusWriteAt = now

        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "\(ts) \(trimmed)\n"

        do {
            let dir = try ExportService.exportsDirectory()
            let url = dir.appendingPathComponent("autorun-status.txt", isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try line.data(using: .utf8)?.write(to: url, options: [.atomic])
            }
        } catch {
            // Best effort. (We don't want autorun to fail if the status file can't be written.)
        }
    }

    private func resetAutorunStatusLog() {
        do {
            let dir = try ExportService.exportsDirectory()
            let url = dir.appendingPathComponent("autorun-status.txt", isDirectory: false)
            try? FileManager.default.removeItem(at: url)
        } catch {
            // Best effort.
        }
    }

    func model(for id: String) -> TTSModel? {
        allModels.first(where: { $0.id == id })
    }

    func status(for modelId: String) -> ModelStatus {
        modelStatus[modelId] ?? .unknown
    }

    func refreshStatuses() {
        var next: [String: ModelStatus] = modelStatus
        for model in allModels {
            if next[model.id]?.isDownloading == true {
                continue
            }
            next[model.id] = ModelStorage.isModelDownloaded(model) ? .ready : .notDownloaded
        }
        modelStatus = next
    }

    // MARK: - Speak

    func speak() {
        speakTask?.cancel()
        lastError = nil
        lastMetrics = nil

        guard let model = model(for: selectedModelId) else {
            lastError = "Selected model not found"
            return
        }

        speakTask = Task { [weak self] in
            guard let self else { return }
            do {
                let metrics = try await self.synthesizeAndPlay(model: model, text: self.inputText)
                self.lastMetrics = metrics
            } catch is CancellationError {
                // no-op
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
        }

        UserDefaults.standard.set(selectedModelId, forKey: "ttseval.selectedModelId")
    }

    func stop() {
        speakTask?.cancel()
        audioPlayback.stop()
    }

    private func synthesizeAndPlay(model: TTSModel, text: String) async throws -> TTSEvalMetrics {
        try Task.checkCancellation()

        if !ModelStorage.isModelDownloaded(model) {
            try await downloadModel(model)
        }

        try Task.checkCancellation()

        guard let engine = engineRegistry.engine(for: model.engineId) else {
            throw TTSEvalError.engineUnavailable("No engine for \(model.engineId)")
        }

        do {
            try await engine.prepare(model: model)
        } catch let err as TTSEvalError {
            switch err {
            case .modelNotDownloaded:
                // Handle partially-downloaded models where the model directory exists but required files are missing.
                try await downloadModel(model)
                try await engine.prepare(model: model)
            default:
                throw err
            }
        } catch {
            throw error
        }

        try Task.checkCancellation()

        // Sample CPU/mem during synthesize.
        let sys = SystemMetrics()
        let acc = MetricAccumulator()
        let samplingTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                acc.add(cpu: sys.cpuPercent(), memMB: sys.memoryMB())
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        let tokens = Tokenization.tokenCount(text)
        let chars = Tokenization.charCount(text)
        let lang = Tokenization.detectLanguageCode(text)

        let start = CFAbsoluteTimeGetCurrent()
        let audio = try await engine.synthesize(text: text, settings: synthesisSettings)
        let end = CFAbsoluteTimeGetCurrent()

        samplingTask.cancel()
        _ = await samplingTask.value

        try Task.checkCancellation()

        let synthesisSeconds = max(end - start, 0.000_001)
        let synthesisMs = synthesisSeconds * 1000
        let audioSeconds = audio.durationSeconds

        let rtfRaw = audioSeconds > 0 ? synthesisSeconds / audioSeconds : nil
        let rtf: Double?
        if model.engineId == TTSEngineIds.avSpeech {
            rtf = nil
        } else {
            rtf = rtfRaw
        }

        let sampled = acc.result()

        let metrics = TTSEvalMetrics(
            tokenCount: tokens,
            charCount: chars,
            synthesisMs: synthesisMs,
            audioSeconds: audioSeconds,
            rtf: rtf,
            tokensPerSecond: Double(tokens) / synthesisSeconds,
            charsPerSecond: Double(chars) / synthesisSeconds,
            cpuAvg: sampled.cpuAvg,
            cpuMax: sampled.cpuMax,
            memMaxMB: sampled.memMaxMB,
            detectedLanguage: lang
        )

        try audioPlayback.play(audio, normalize: synthesisSettings.normalizeAudio)
        return metrics
    }

    // MARK: - Downloads

    func downloadSelectedModel() {
        guard let model = model(for: selectedModelId) else { return }
        Task { [weak self] in
            do {
                try await self?.downloadModel(model)
            } catch {
                await MainActor.run {
                    self?.lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                }
            }
        }
    }

    func downloadModel(_ model: TTSModel) async throws {
        if ModelStorage.isModelDownloaded(model) {
            modelStatus[model.id] = .ready
            return
        }
        guard !model.artifacts.isEmpty else {
            throw TTSEvalError.modelNotDownloaded("Model \(model.displayName) has no downloadable artifacts")
        }

        let downloader = HuggingFaceDownloader()
        downloaderByModelId[model.id] = downloader

        modelStatus[model.id] = .downloading(progress: 0, message: "Downloading...")
        downloader.onProgress = { [weak self] frac in
            self?.modelStatus[model.id] = .downloading(progress: frac, message: "Downloading...")
        }

        do {
            try await downloader.downloadArtifacts(modelId: model.id, artifacts: model.artifacts)
            modelStatus[model.id] = .ready
        } catch {
            modelStatus[model.id] = .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
            throw error
        }
    }

    func cancelDownload(modelId: String) {
        downloaderByModelId[modelId]?.cancel()
        downloaderByModelId[modelId] = nil
        refreshStatuses()
    }

    func deleteDownloaded(modelId: String) {
        do {
            try ModelStorage.deleteDownloadedModel(modelId: modelId)
            refreshStatuses()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    // MARK: - Benchmark

    func runBenchmark() {
        benchmarkTask?.cancel()
        benchmarkExport = nil
        benchmarkArtifacts = nil
        lastError = nil
        benchmarkRunning = true
        benchmarkProgress = "Starting..."

        let selected: [TTSModel] = {
            if benchmarkSelectedModelIds.isEmpty {
                // Default: all curated models.
                return curatedModels
            }
            return allModels.filter { benchmarkSelectedModelIds.contains($0.id) }
        }()

        benchmarkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let export = try await self.runner.run(
                    models: selected,
                    dataset: self.benchmarkDataset,
                    synthesisSettings: self.synthesisSettings
                ) { update in
                    Task { @MainActor [weak self] in
                        self?.benchmarkProgress = "\(update.modelId): \(Int(update.fraction0to1 * 100))% \(update.message)"
                    }
                }

                self.benchmarkExport = export
                let artifacts = try ExportService.write(export: export)
                self.benchmarkArtifacts = artifacts
                self.benchmarkProgress = "Exported."
            } catch is CancellationError {
                self.benchmarkProgress = "Cancelled."
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                self.benchmarkProgress = "Failed."
            }
            self.benchmarkRunning = false
        }
    }

    func cancelBenchmark() {
        benchmarkTask?.cancel()
        benchmarkRunning = false
    }

    // MARK: - Custom Models

    func addCustomModel(_ model: TTSModel) {
        customModels.append(model)
        persistCustomModels()
        refreshStatuses()
    }

    func deleteCustomModel(modelId: String) {
        customModels.removeAll(where: { $0.id == modelId })
        persistCustomModels()
        refreshStatuses()
    }

    private func loadCustomModels() {
        customModels = ModelStorage.loadCustomModels()
    }

    private func persistCustomModels() {
        do {
            try ModelStorage.saveCustomModels(customModels)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func loadLastBenchmarkExport() {
        do {
            let dir = try ExportService.exportsDirectory()
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let jsons = urls.filter { url in
                url.lastPathComponent.hasPrefix("results-") && url.pathExtension.lowercased() == "json"
            }
            guard let latest = jsons.max(by: { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }) else { return }

            let data = try Data(contentsOf: latest)
            let export = try JSONDecoder().decode(BenchmarkExport.self, from: data)
            benchmarkExport = export

            let base = latest.deletingPathExtension().lastPathComponent
            let runs = dir.appendingPathComponent("\(base)-runs.csv", isDirectory: false)
            let summary = dir.appendingPathComponent("\(base)-summary.csv", isDirectory: false)
            if FileManager.default.fileExists(atPath: runs.path),
               FileManager.default.fileExists(atPath: summary.path) {
                benchmarkArtifacts = ExportArtifacts(jsonURL: latest, runsCSVURL: runs, summaryCSVURL: summary)
            }
        } catch {
            // Best-effort: ignore any errors; users can run a fresh benchmark.
        }
    }
}

private final class MetricAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var cpuSum: Double = 0
    private var cpuCount: Int = 0
    private var cpuMax: Double = 0
    private var memMax: Double = 0

    func add(cpu: Double, memMB: Double) {
        lock.lock()
        cpuSum += cpu
        cpuCount += 1
        cpuMax = max(cpuMax, cpu)
        memMax = max(memMax, memMB)
        lock.unlock()
    }

    func result() -> (cpuAvg: Double, cpuMax: Double, memMaxMB: Double) {
        lock.lock()
        defer { lock.unlock() }
        let avg = cpuCount > 0 ? (cpuSum / Double(cpuCount)) : 0
        return (avg, cpuMax, memMax)
    }
}
