import Foundation

struct ExportArtifacts: Sendable {
    let jsonURL: URL
    let runsCSVURL: URL
    let summaryCSVURL: URL
}

enum ExportService {
    private static let fileManager = FileManager.default

    static func exportsDirectory() throws -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("TTSEvalExports", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func write(export: BenchmarkExport) throws -> ExportArtifacts {
        let dir = try exportsDirectory()
        let ts = export.startedAtISO8601
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")

        let jsonURL = dir.appendingPathComponent("results-\(ts).json")
        let runsCSVURL = dir.appendingPathComponent("results-\(ts)-runs.csv")
        let summaryCSVURL = dir.appendingPathComponent("results-\(ts)-summary.csv")

        // JSON
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try enc.encode(export)
        try json.write(to: jsonURL, options: [.atomic])

        // CSV (runs)
        let runsCSV = runsCSVString(runs: export.runs, dataset: export.dataset, device: export.device)
        guard let runsData = runsCSV.data(using: .utf8) else {
            throw TTSEvalError.exportFailed("Failed to encode runs CSV as UTF-8")
        }
        try runsData.write(to: runsCSVURL, options: [.atomic])

        // CSV (summary)
        let summaryCSV = summaryCSVString(summaries: export.summaries, dataset: export.dataset, device: export.device)
        guard let summaryData = summaryCSV.data(using: .utf8) else {
            throw TTSEvalError.exportFailed("Failed to encode summary CSV as UTF-8")
        }
        try summaryData.write(to: summaryCSVURL, options: [.atomic])

        return ExportArtifacts(jsonURL: jsonURL, runsCSVURL: runsCSVURL, summaryCSVURL: summaryCSVURL)
    }

    private static func runsCSVString(runs: [PromptRunResult], dataset: String, device: DeviceInfo) -> String {
        var out: [String] = []
        out.append("# dataset=\(dataset), device=\(device.deviceModel), iOS=\(device.systemVersion)")
        out.append("timestamp,model_id,model_name,engine_id,prompt_index,token_count,char_count,synthesis_ms,audio_seconds,rtf,tokens_per_sec,chars_per_sec,cpu_avg,cpu_max,mem_max_mb,detected_lang,prompt")

        for r in runs {
            let m = r.metrics
            let row: [String] = [
                r.timestampISO8601,
                r.modelId,
                r.modelDisplayName,
                r.engineId,
                String(r.promptIndex),
                String(m.tokenCount),
                String(m.charCount),
                format(m.synthesisMs),
                m.audioSeconds.map(format) ?? "",
                m.rtf.map(format) ?? "",
                format(m.tokensPerSecond),
                format(m.charsPerSecond),
                format(m.cpuAvg),
                format(m.cpuMax),
                format(m.memMaxMB),
                m.detectedLanguage ?? "",
                r.prompt
            ].map(csvEscape)

            out.append(row.joined(separator: ","))
        }

        return out.joined(separator: "\n") + "\n"
    }

    private static func summaryCSVString(summaries: [ModelSummary], dataset: String, device: DeviceInfo) -> String {
        var out: [String] = []
        out.append("# dataset=\(dataset), device=\(device.deviceModel), iOS=\(device.systemVersion)")
        out.append("model_id,model_name,engine_id,prompt_count,overall_score,speed_score,throughput_score,resource_score,median_rtf,median_tps,median_cpu_avg,median_mem_max_mb")

        for s in summaries {
            let sc = s.score
            let row: [String] = [
                s.modelId,
                s.modelDisplayName,
                s.engineId,
                String(s.promptCount),
                format(sc.overallScore0to100),
                sc.speedScore.map(format) ?? "",
                format(sc.throughputScore),
                format(sc.resourceScore),
                sc.medianRtf.map(format) ?? "",
                format(sc.medianTokensPerSecond),
                format(sc.medianCpuAvg),
                format(sc.medianMemMaxMB)
            ].map(csvEscape)

            out.append(row.joined(separator: ","))
        }

        return out.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\n") || value.contains("\r") || value.contains("\"")
        if !needsQuotes {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}
