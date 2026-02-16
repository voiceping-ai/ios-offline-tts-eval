import Foundation

@MainActor
final class TTSEvalRunner {
    struct ProgressUpdate: Sendable {
        let modelId: String
        let fraction0to1: Double
        let message: String
    }

    private let engineRegistry = TTSEngineRegistry.shared

    func run(
        models: [TTSModel],
        language: PromptLanguage,
        dataset: PromptDataset,
        synthesisSettings: TTSSynthesisSettings,
        promptLimit: Int? = nil,
        onProgress: (@Sendable (ProgressUpdate) -> Void)? = nil
    ) async throws -> BenchmarkExport {
        try Task.checkCancellation()

        let startedAt = Date()
        let device = DeviceInfo.current()
        let promptSetsByLang = try PromptCatalog.load()
        let allPrompts = try PromptCatalog.prompts(for: language, dataset: dataset, setsByLanguage: promptSetsByLang)
        let prompts: [String] = {
            guard let promptLimit, promptLimit > 0 else { return allPrompts }
            return Array(allPrompts.prefix(promptLimit))
        }()

        var runs: [PromptRunResult] = []
        runs.reserveCapacity(models.count * prompts.count)
        var modelLoadMsById: [String: Double] = [:]

        for model in models {
            try Task.checkCancellation()

            onProgress?(.init(modelId: model.id, fraction0to1: 0, message: "Checking model files..."))

            if !ModelStorage.isModelDownloaded(model) {
                if !model.artifacts.isEmpty {
                    onProgress?(.init(modelId: model.id, fraction0to1: 0, message: "Downloading..."))
                    let downloader = HuggingFaceDownloader()
                    downloader.onProgress = { frac in
                        onProgress?(.init(modelId: model.id, fraction0to1: frac, message: "Downloading..."))
                    }
                    try await downloader.downloadArtifacts(modelId: model.id, artifacts: model.artifacts)
                } else if !model.localRequiredPaths.isEmpty {
                    let missing = model.localRequiredPaths.joined(separator: ", ")
                    throw TTSEvalError.modelNotDownloaded(
                        "Model \(model.displayName) requires local import. Missing files: \(missing)."
                    )
                } else {
                    // System/baseline models should always be ready.
                    throw TTSEvalError.modelNotDownloaded("Model \(model.displayName) is not ready")
                }
            }

            guard let engine = engineRegistry.engine(for: model.engineId) else {
                throw TTSEvalError.engineUnavailable("No engine registered for \(model.engineId)")
            }

            do {
                onProgress?(.init(modelId: model.id, fraction0to1: 0, message: "Preparing engine..."))
                do {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    try await engine.prepare(model: model)
                    let t1 = CFAbsoluteTimeGetCurrent()
                    modelLoadMsById[model.id] = max((t1 - t0) * 1000.0, 0)
                } catch let err as TTSEvalError {
                    // If the directory existed but was incomplete (or artifacts list included directories),
                    // prepare() can fail even though `isModelDownloaded` returned true. Retry by downloading
                    // again; the downloader skips already-present files.
                    switch err {
                    case .modelNotDownloaded:
                        guard !model.artifacts.isEmpty else { throw err }
                        onProgress?(.init(modelId: model.id, fraction0to1: 0, message: "Downloading missing files..."))
                        let downloader = HuggingFaceDownloader()
                        downloader.onProgress = { frac in
                            onProgress?(.init(modelId: model.id, fraction0to1: frac, message: "Downloading missing files..."))
                        }
                        try await downloader.downloadArtifacts(modelId: model.id, artifacts: model.artifacts)
                        onProgress?(.init(modelId: model.id, fraction0to1: 0, message: "Preparing engine (retry)..."))
                        let t0 = CFAbsoluteTimeGetCurrent()
                        try await engine.prepare(model: model)
                        let t1 = CFAbsoluteTimeGetCurrent()
                        modelLoadMsById[model.id] = max((t1 - t0) * 1000.0, 0)
                    default:
                        throw err
                    }
                }
                for (idx, prompt) in prompts.enumerated() {
                    try Task.checkCancellation()

                    let frac = Double(idx) / Double(max(1, prompts.count))
                    onProgress?(.init(modelId: model.id, fraction0to1: frac, message: "Running \(idx + 1)/\(prompts.count)"))

                    let run = try await runSingle(
                        model: model,
                        engine: engine,
                        promptIndex: idx,
                        prompt: prompt,
                        synthesisSettings: synthesisSettings
                    )
                    runs.append(run)
                }

                onProgress?(.init(modelId: model.id, fraction0to1: 1, message: "Done"))
            } catch {
                await engine.unload()
                throw error
            }

            // Ensure we don't keep model memory resident across models (benchmark correctness).
            await engine.unload()
        }

        let summaries = Self.computeSummaries(from: runs, modelLoadMsById: modelLoadMsById)

        return BenchmarkExport(
            schemaVersion: 2,
            startedAtISO8601: ISO8601DateFormatter().string(from: startedAt),
            dataset: "\(language.rawValue)_\(dataset.rawValue)",
            device: device,
            runs: runs,
            summaries: summaries
        )
    }

    private func runSingle(
        model: TTSModel,
        engine: TTSEngine,
        promptIndex: Int,
        prompt: String,
        synthesisSettings: TTSSynthesisSettings
    ) async throws -> PromptRunResult {
        try Task.checkCancellation()

        let tokens = Tokenization.tokenCount(prompt)
        let chars = Tokenization.charCount(prompt)
        let lang = Tokenization.detectLanguageCode(prompt)

        let metricsSampler = SystemMetrics()
        let acc = MetricAccumulator()

        let samplingTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                let cpu = metricsSampler.cpuPercent()
                let mem = metricsSampler.memoryMB()
                acc.add(cpu: cpu, memMB: mem)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        let audio = try await engine.synthesize(text: prompt, settings: synthesisSettings)
        let end = CFAbsoluteTimeGetCurrent()

        samplingTask.cancel()
        _ = await samplingTask.value

        try Task.checkCancellation()

        let synthesisSeconds = max(end - start, 0.000_001)
        let synthesisMs = synthesisSeconds * 1000.0

        let audioSeconds = audio.durationSeconds
        let rtfRaw = audioSeconds > 0 ? synthesisSeconds / audioSeconds : nil
        let rtf: Double?
        if model.engineId == TTSEngineIds.avSpeech {
            // Baseline: keep RTF out of comparisons per v1 scoring rules.
            rtf = nil
        } else {
            rtf = rtfRaw
        }

        let tps = Double(tokens) / synthesisSeconds
        let cps = Double(chars) / synthesisSeconds

        let sampled = acc.result()

        let metrics = TTSEvalMetrics(
            tokenCount: tokens,
            charCount: chars,
            synthesisMs: synthesisMs,
            audioSeconds: audioSeconds,
            rtf: rtf,
            tokensPerSecond: tps,
            charsPerSecond: cps,
            cpuAvg: sampled.cpuAvg,
            cpuMax: sampled.cpuMax,
            memMaxMB: sampled.memMaxMB,
            detectedLanguage: lang
        )

        return PromptRunResult(
            model: model,
            promptIndex: promptIndex,
            prompt: prompt,
            metrics: metrics
        )
    }

    private static func computeSummaries(from runs: [PromptRunResult], modelLoadMsById: [String: Double]) -> [ModelSummary] {
        struct Aggregate {
            let modelId: String
            let modelName: String
            let engineId: String
            let promptCount: Int
            let medianRtf: Double?
            let medianTps: Double
            let medianCpuAvg: Double
            let medianMemMax: Double
        }

        let grouped = Dictionary(grouping: runs, by: { $0.modelId })
        var aggregates: [Aggregate] = []
        aggregates.reserveCapacity(grouped.count)

        for (_, items) in grouped {
            guard let first = items.first else { continue }

            let rtfValues = items.compactMap { $0.metrics.rtf }.filter { $0 > 0 }
            let tpsValues = items.map { $0.metrics.tokensPerSecond }.filter { $0.isFinite && $0 > 0 }
            let cpuValues = items.map { $0.metrics.cpuAvg }.filter { $0.isFinite && $0 >= 0 }
            let memValues = items.map { $0.metrics.memMaxMB }.filter { $0.isFinite && $0 >= 0 }

            let agg = Aggregate(
                modelId: first.modelId,
                modelName: first.modelDisplayName,
                engineId: first.engineId,
                promptCount: items.count,
                medianRtf: median(of: rtfValues),
                medianTps: median(of: tpsValues) ?? 0,
                medianCpuAvg: median(of: cpuValues) ?? 0,
                medianMemMax: median(of: memValues) ?? 0
            )
            aggregates.append(agg)
        }

        // Treat AVSpeech as a baseline: show it in the output, but exclude it from
        // normalization so it doesn't collapse the score distribution for offline models.
        let scoredAggregates = aggregates.filter { $0.engineId != TTSEngineIds.avSpeech }
        let bestTps = (scoredAggregates.map { $0.medianTps }.max() ?? 0) > 0
            ? (scoredAggregates.map { $0.medianTps }.max() ?? 0)
            : (aggregates.map { $0.medianTps }.max() ?? 0)

        func resourceCost(cpuAvg: Double, memMax: Double) -> Double {
            cpuAvg + (memMax / 10.0)
        }
        let bestCost = (scoredAggregates.map { resourceCost(cpuAvg: $0.medianCpuAvg, memMax: $0.medianMemMax) }.min() ?? 0) > 0
            ? (scoredAggregates.map { resourceCost(cpuAvg: $0.medianCpuAvg, memMax: $0.medianMemMax) }.min() ?? 0)
            : (aggregates.map { resourceCost(cpuAvg: $0.medianCpuAvg, memMax: $0.medianMemMax) }.min() ?? 0)

        var summaries: [ModelSummary] = []
        summaries.reserveCapacity(aggregates.count)

        for agg in aggregates {
            let throughputScore: Double = {
                guard bestTps > 0 else { return 0 }
                return clamp01(agg.medianTps / bestTps) * 100.0
            }()

            let resourceScore: Double = {
                let cost = resourceCost(cpuAvg: agg.medianCpuAvg, memMax: agg.medianMemMax)
                if cost <= 0 { return 100 }
                if bestCost <= 0 { return 100 }
                return clamp01(bestCost / cost) * 100.0
            }()

            let speedScore: Double? = {
                guard let rtf = agg.medianRtf else { return nil }
                if rtf <= 0 { return 100 }
                let s = (1.5 - rtf) / 1.5
                return clamp01(s) * 100.0
            }()

            let overall: Double = {
                if let speedScore {
                    return 0.5 * speedScore + 0.3 * throughputScore + 0.2 * resourceScore
                }
                // Baseline: no RTF.
                return 0.6 * throughputScore + 0.4 * resourceScore
            }()

            let score = TTSEvalScore(
                overallScore0to100: overall,
                speedScore: speedScore,
                resourceScore: resourceScore,
                throughputScore: throughputScore,
                medianRtf: agg.medianRtf,
                medianTokensPerSecond: agg.medianTps,
                medianCpuAvg: agg.medianCpuAvg,
                medianMemMaxMB: agg.medianMemMax
            )

            summaries.append(ModelSummary(
                modelId: agg.modelId,
                modelDisplayName: agg.modelName,
                engineId: agg.engineId,
                promptCount: agg.promptCount,
                modelLoadMs: modelLoadMsById[agg.modelId],
                score: score
            ))
        }

        return summaries.sorted(by: { $0.score.overallScore0to100 > $1.score.overallScore0to100 })
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

private func median(of values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    if sorted.count % 2 == 1 {
        return sorted[mid]
    }
    return (sorted[mid - 1] + sorted[mid]) / 2.0
}

private func clamp01(_ x: Double) -> Double {
    min(max(x, 0), 1)
}
