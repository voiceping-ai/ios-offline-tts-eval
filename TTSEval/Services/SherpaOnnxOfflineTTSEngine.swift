import Foundation
import SherpaOnnxKit

@MainActor
final class SherpaOnnxOfflineTTSEngine: TTSEngine {
    let id: String = TTSEngineIds.sherpa
    let displayName: String = "Sherpa-ONNX Offline TTS (CPU)"

    private var ttsByModelId: [String: SherpaOnnxOfflineTtsWrapper] = [:]
    private var activeModelId: String?

    func prepare(model: TTSModel) async throws {
        guard model.engineId == id else {
            throw TTSEvalError.engineUnavailable("Model \(model.displayName) is not a Sherpa offline TTS model")
        }
        guard let cfg = model.sherpaConfig else {
            throw TTSEvalError.invalidModel("Missing Sherpa config for \(model.displayName)")
        }

        if ttsByModelId[model.id] != nil {
            activeModelId = model.id
            return
        }

        let modelDir = try ModelStorage.modelDirectory(modelId: model.id)
        try validateRequiredFiles(cfg: cfg, in: modelDir, modelName: model.displayName)

        let numThreads = cfg.numThreads ?? Self.recommendedThreads()
        let provider = "cpu"

        let abs: (String?) -> String = { rel in
            guard let rel, !rel.isEmpty else { return "" }
            return modelDir.appendingPathComponent(rel).path
        }

        let absDir: (String?) -> String = { rel in
            guard let rel, !rel.isEmpty else { return "" }
            return modelDir.appendingPathComponent(rel, isDirectory: true).path
        }

        let vitsCfg: SherpaOnnxOfflineTtsVitsModelConfig
        let matchaCfg: SherpaOnnxOfflineTtsMatchaModelConfig
        let kokoroCfg: SherpaOnnxOfflineTtsKokoroModelConfig
        let kittenCfg: SherpaOnnxOfflineTtsKittenModelConfig
        let zipvoiceCfg: SherpaOnnxOfflineTtsZipvoiceModelConfig

        switch cfg.type {
        case .vits:
            vitsCfg = sherpaOnnxOfflineTtsVitsModelConfig(
                model: abs(cfg.modelPath),
                lexicon: abs(cfg.lexiconPath),
                tokens: abs(cfg.tokensPath),
                dataDir: absDir(cfg.dataDir),
                noiseScale: cfg.noiseScale ?? 0.667,
                noiseScaleW: cfg.noiseScaleW ?? 0.8,
                lengthScale: cfg.lengthScale ?? 1.0,
                dictDir: absDir(cfg.dictDir)
            )
            matchaCfg = sherpaOnnxOfflineTtsMatchaModelConfig()
            kokoroCfg = sherpaOnnxOfflineTtsKokoroModelConfig()
            kittenCfg = sherpaOnnxOfflineTtsKittenModelConfig()
            zipvoiceCfg = sherpaOnnxOfflineTtsZipvoiceModelConfig()
        case .matcha:
            vitsCfg = sherpaOnnxOfflineTtsVitsModelConfig()
            matchaCfg = sherpaOnnxOfflineTtsMatchaModelConfig(
                acousticModel: abs(cfg.acousticModelPath),
                vocoder: abs(cfg.vocoderPath),
                lexicon: abs(cfg.lexiconPath),
                tokens: abs(cfg.tokensPath),
                dataDir: absDir(cfg.dataDir),
                noiseScale: cfg.noiseScale ?? 0.667,
                lengthScale: cfg.lengthScale ?? 1.0,
                dictDir: absDir(cfg.dictDir)
            )
            kokoroCfg = sherpaOnnxOfflineTtsKokoroModelConfig()
            kittenCfg = sherpaOnnxOfflineTtsKittenModelConfig()
            zipvoiceCfg = sherpaOnnxOfflineTtsZipvoiceModelConfig()
        case .kokoro:
            vitsCfg = sherpaOnnxOfflineTtsVitsModelConfig()
            matchaCfg = sherpaOnnxOfflineTtsMatchaModelConfig()
            kokoroCfg = sherpaOnnxOfflineTtsKokoroModelConfig(
                model: abs(cfg.modelPath),
                voices: abs(cfg.voicesPath),
                tokens: abs(cfg.tokensPath),
                dataDir: absDir(cfg.dataDir),
                lengthScale: cfg.lengthScale ?? 1.0,
                dictDir: absDir(cfg.dictDir),
                lexicon: abs(cfg.lexiconPath),
                lang: cfg.lang ?? ""
            )
            kittenCfg = sherpaOnnxOfflineTtsKittenModelConfig()
            zipvoiceCfg = sherpaOnnxOfflineTtsZipvoiceModelConfig()
        case .kitten:
            vitsCfg = sherpaOnnxOfflineTtsVitsModelConfig()
            matchaCfg = sherpaOnnxOfflineTtsMatchaModelConfig()
            kokoroCfg = sherpaOnnxOfflineTtsKokoroModelConfig()
            kittenCfg = sherpaOnnxOfflineTtsKittenModelConfig(
                model: abs(cfg.modelPath),
                voices: abs(cfg.voicesPath),
                tokens: abs(cfg.tokensPath),
                dataDir: absDir(cfg.dataDir),
                lengthScale: cfg.lengthScale ?? 1.0
            )
            zipvoiceCfg = sherpaOnnxOfflineTtsZipvoiceModelConfig()
        case .zipvoice:
            vitsCfg = sherpaOnnxOfflineTtsVitsModelConfig()
            matchaCfg = sherpaOnnxOfflineTtsMatchaModelConfig()
            kokoroCfg = sherpaOnnxOfflineTtsKokoroModelConfig()
            kittenCfg = sherpaOnnxOfflineTtsKittenModelConfig()
            zipvoiceCfg = sherpaOnnxOfflineTtsZipvoiceModelConfig(
                tokens: abs(cfg.tokensPath),
                encoder: abs(cfg.encoderPath),
                decoder: abs(cfg.decoderPath),
                vocoder: abs(cfg.vocoderPath),
                dataDir: absDir(cfg.dataDir),
                lexicon: abs(cfg.lexiconPath),
                featScale: cfg.featScale ?? 0.1,
                tShift: cfg.tShift ?? 0.5,
                targetRms: cfg.targetRms ?? 0.1,
                guidanceScale: cfg.guidanceScale ?? 1.0
            )
        }

        let modelCfg = sherpaOnnxOfflineTtsModelConfig(
            vits: vitsCfg,
            matcha: matchaCfg,
            kokoro: kokoroCfg,
            numThreads: numThreads,
            debug: 0,
            provider: provider,
            kitten: kittenCfg,
            zipvoice: zipvoiceCfg
        )

        var ttsCfg = sherpaOnnxOfflineTtsConfig(
            model: modelCfg,
            ruleFsts: "",
            ruleFars: "",
            maxNumSentences: 1,
            silenceScale: 0.2
        )

        let wrapper = withUnsafePointer(to: &ttsCfg) { ptr in
            SherpaOnnxOfflineTtsWrapper(config: ptr)
        }

        if wrapper.tts == nil {
            throw TTSEvalError.synthesisFailed("Failed to initialize Sherpa offline TTS for \(model.displayName)")
        }

        ttsByModelId[model.id] = wrapper
        activeModelId = model.id
    }

    func synthesize(text: String, settings: TTSSynthesisSettings) async throws -> TTSAudio {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw TTSEvalError.synthesisFailed("Text is empty")
        }

        guard let activeModelId, let wrapper = ttsByModelId[activeModelId] else {
            throw TTSEvalError.engineUnavailable("Model not prepared")
        }

        let audio = wrapper.generate(text: normalized, sid: settings.sid, speed: settings.speed)
        let sampleRate = Int(audio.sampleRate)
        let samples = audio.samples
        return TTSAudio(samples: samples, sampleRate: sampleRate, channels: 1)
    }

    func unload() async {
        ttsByModelId.removeAll()
        activeModelId = nil
    }

    private func validateRequiredFiles(cfg: SherpaOfflineTTSConfig, in dir: URL, modelName: String) throws {
        func requireFile(_ rel: String?, label: String) throws {
            guard let rel, !rel.isEmpty else { return }
            let url = dir.appendingPathComponent(rel)
            if !FileManager.default.fileExists(atPath: url.path) {
                throw TTSEvalError.modelNotDownloaded("Missing \(label) for \(modelName): \(rel)")
            }
        }

        func requireDir(_ rel: String?, label: String) throws {
            guard let rel, !rel.isEmpty else { return }
            let url = dir.appendingPathComponent(rel, isDirectory: true)
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) || !isDir.boolValue {
                throw TTSEvalError.modelNotDownloaded("Missing \(label) directory for \(modelName): \(rel)")
            }
        }

        switch cfg.type {
        case .kokoro:
            try requireFile(cfg.modelPath, label: "model")
            try requireFile(cfg.voicesPath, label: "voices")
            try requireFile(cfg.tokensPath, label: "tokens")
            try requireFile(cfg.lexiconPath, label: "lexicon")
            try requireDir(cfg.dataDir, label: "data")
            try requireDir(cfg.dictDir, label: "dict")
        case .vits:
            try requireFile(cfg.modelPath, label: "model")
            try requireFile(cfg.tokensPath, label: "tokens")
            try requireFile(cfg.lexiconPath, label: "lexicon")
        case .matcha:
            try requireFile(cfg.acousticModelPath, label: "acoustic model")
            try requireFile(cfg.vocoderPath, label: "vocoder")
            try requireFile(cfg.tokensPath, label: "tokens")
            try requireDir(cfg.dataDir, label: "data")
        case .kitten:
            try requireFile(cfg.modelPath, label: "model")
            try requireFile(cfg.voicesPath, label: "voices")
            try requireFile(cfg.tokensPath, label: "tokens")
            try requireDir(cfg.dataDir, label: "data")
        case .zipvoice:
            try requireFile(cfg.tokensPath, label: "tokens")
            try requireFile(cfg.encoderPath, label: "encoder")
            try requireFile(cfg.decoderPath, label: "decoder")
            try requireFile(cfg.vocoderPath, label: "vocoder")
        }
    }

    private nonisolated static func recommendedThreads() -> Int {
        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        return min(4, max(1, cores / 2))
    }
}
