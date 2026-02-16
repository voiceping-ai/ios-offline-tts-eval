import Foundation

// MARK: - Errors

enum TTSEvalError: LocalizedError, Sendable {
    case invalidModel(String)
    case modelNotDownloaded(String)
    case downloadFailed(String)
    case engineUnavailable(String)
    case synthesisFailed(String)
    case audioPlaybackFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidModel(let msg): return msg
        case .modelNotDownloaded(let msg): return msg
        case .downloadFailed(let msg): return msg
        case .engineUnavailable(let msg): return msg
        case .synthesisFailed(let msg): return msg
        case .audioPlaybackFailed(let msg): return msg
        case .exportFailed(let msg): return msg
        }
    }
}

// MARK: - Engine Protocol

@MainActor
protocol TTSEngine: AnyObject {
    var id: String { get }
    var displayName: String { get }

    func prepare(model: TTSModel) async throws
    func synthesize(text: String, settings: TTSSynthesisSettings) async throws -> TTSAudio
    func unload() async
}

// MARK: - Model Definitions

struct TTSArtifact: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let repoId: String
    let path: String
    let destinationRelativePath: String

    init(
        id: String? = nil,
        repoId: String,
        path: String,
        destinationRelativePath: String? = nil
    ) {
        self.id = id ?? "\(repoId):\(path)"
        self.repoId = repoId
        self.path = path
        self.destinationRelativePath = destinationRelativePath ?? path
    }
}

enum SherpaTTSModelType: String, Codable, CaseIterable, Sendable, Identifiable {
    case kokoro
    case vits
    case matcha
    case kitten
    case zipvoice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kokoro: return "Kokoro"
        case .vits: return "VITS"
        case .matcha: return "Matcha"
        case .kitten: return "Kitten"
        case .zipvoice: return "Zipvoice"
        }
    }
}

struct SherpaOfflineTTSConfig: Codable, Hashable, Sendable {
    let type: SherpaTTSModelType

    // Common
    var numThreads: Int? = nil
    var ruleFsts: [String] = []
    var ruleFars: [String] = []

    // Kokoro
    var modelPath: String? = nil
    var voicesPath: String? = nil
    var tokensPath: String? = nil
    var lexiconPath: String? = nil
    var dictDir: String? = nil
    var dataDir: String? = nil
    var lang: String? = nil
    var lengthScale: Float? = nil

    // VITS
    var noiseScale: Float? = nil
    var noiseScaleW: Float? = nil

    // Matcha
    var acousticModelPath: String? = nil
    var vocoderPath: String? = nil

    // Zipvoice
    var encoderPath: String? = nil
    var decoderPath: String? = nil
    var featScale: Float? = nil
    var tShift: Float? = nil
    var targetRms: Float? = nil
    var guidanceScale: Float? = nil
}

struct TTSModel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let engineId: String
    let languages: [String]
    let estimatedSizeBytes: Int64?
    let artifacts: [TTSArtifact]
    let sherpaConfig: SherpaOfflineTTSConfig?
    let licenseSpdx: String?
    let licenseVerified: Bool
    let localRequiredPaths: [String]

    init(
        id: String,
        displayName: String,
        engineId: String,
        languages: [String] = [],
        estimatedSizeBytes: Int64? = nil,
        artifacts: [TTSArtifact] = [],
        sherpaConfig: SherpaOfflineTTSConfig? = nil,
        licenseSpdx: String? = nil,
        licenseVerified: Bool = false,
        localRequiredPaths: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.engineId = engineId
        self.languages = languages
        self.estimatedSizeBytes = estimatedSizeBytes
        self.artifacts = artifacts
        self.sherpaConfig = sherpaConfig
        self.licenseSpdx = licenseSpdx
        self.licenseVerified = licenseVerified
        self.localRequiredPaths = localRequiredPaths
    }

    // Backward-compatible decoding for older custom_models.json.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.displayName = try c.decode(String.self, forKey: .displayName)
        self.engineId = try c.decode(String.self, forKey: .engineId)
        self.languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? []
        self.estimatedSizeBytes = try c.decodeIfPresent(Int64.self, forKey: .estimatedSizeBytes)
        self.artifacts = try c.decodeIfPresent([TTSArtifact].self, forKey: .artifacts) ?? []
        self.sherpaConfig = try c.decodeIfPresent(SherpaOfflineTTSConfig.self, forKey: .sherpaConfig)
        self.licenseSpdx = try c.decodeIfPresent(String.self, forKey: .licenseSpdx)
        self.licenseVerified = try c.decodeIfPresent(Bool.self, forKey: .licenseVerified) ?? false
        self.localRequiredPaths = try c.decodeIfPresent([String].self, forKey: .localRequiredPaths) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(engineId, forKey: .engineId)
        try c.encode(languages, forKey: .languages)
        try c.encodeIfPresent(estimatedSizeBytes, forKey: .estimatedSizeBytes)
        try c.encode(artifacts, forKey: .artifacts)
        try c.encodeIfPresent(sherpaConfig, forKey: .sherpaConfig)
        try c.encodeIfPresent(licenseSpdx, forKey: .licenseSpdx)
        try c.encode(licenseVerified, forKey: .licenseVerified)
        try c.encode(localRequiredPaths, forKey: .localRequiredPaths)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case engineId
        case languages
        case estimatedSizeBytes
        case artifacts
        case sherpaConfig
        case licenseSpdx
        case licenseVerified
        case localRequiredPaths
    }
}

struct TTSSynthesisSettings: Hashable, Sendable {
    var sid: Int = 0
    var speed: Float = 1.0
    var nativeRate: Float = 0.5
    var normalizeAudio: Bool = true
}

struct TTSAudio: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let channels: Int

    init(samples: [Float], sampleRate: Int, channels: Int = 1) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channels = channels
    }

    var durationSeconds: Double {
        guard sampleRate > 0, channels > 0 else { return 0 }
        return Double(samples.count) / Double(sampleRate * channels)
    }
}

// MARK: - Metrics & Scoring

struct TTSEvalMetrics: Codable, Hashable, Sendable {
    var tokenCount: Int
    var charCount: Int

    var synthesisMs: Double
    var audioSeconds: Double?
    var rtf: Double?

    var tokensPerSecond: Double
    var charsPerSecond: Double

    var cpuAvg: Double
    var cpuMax: Double
    var memMaxMB: Double

    var detectedLanguage: String?
}

struct TTSEvalScore: Codable, Hashable, Sendable {
    var overallScore0to100: Double
    var speedScore: Double?
    var resourceScore: Double
    var throughputScore: Double

    // Raw median metrics
    var medianRtf: Double?
    var medianTokensPerSecond: Double
    var medianCpuAvg: Double
    var medianMemMaxMB: Double
}
