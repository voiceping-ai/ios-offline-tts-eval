import Foundation
import UIKit

struct PromptRunResult: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let timestampISO8601: String

    let modelId: String
    let modelDisplayName: String
    let engineId: String

    let promptIndex: Int
    let prompt: String
    let metrics: TTSEvalMetrics

    init(
        model: TTSModel,
        promptIndex: Int,
        prompt: String,
        metrics: TTSEvalMetrics,
        timestamp: Date = Date()
    ) {
        self.id = UUID().uuidString
        self.timestampISO8601 = ISO8601DateFormatter().string(from: timestamp)
        self.modelId = model.id
        self.modelDisplayName = model.displayName
        self.engineId = model.engineId
        self.promptIndex = promptIndex
        self.prompt = prompt
        self.metrics = metrics
    }
}

struct ModelSummary: Codable, Hashable, Sendable {
    let modelId: String
    let modelDisplayName: String
    let engineId: String
    let promptCount: Int
    let modelLoadMs: Double?
    let score: TTSEvalScore
}

struct DeviceInfo: Codable, Hashable, Sendable {
    let deviceModel: String
    let systemName: String
    let systemVersion: String

    static func current() -> DeviceInfo {
        DeviceInfo(
            deviceModel: Self.hardwareModel(),
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion
        )
    }

    private static func hardwareModel() -> String {
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

struct BenchmarkExport: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let startedAtISO8601: String
    let dataset: String
    let device: DeviceInfo

    let runs: [PromptRunResult]
    let summaries: [ModelSummary]
}
