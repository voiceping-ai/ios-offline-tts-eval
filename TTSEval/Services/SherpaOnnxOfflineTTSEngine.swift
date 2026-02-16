import Foundation
import SherpaOnnxKit

@MainActor
final class SherpaOnnxOfflineTTSEngine: TTSEngine {
    let id: String = TTSEngineIds.sherpa
    let displayName: String = "Sherpa-ONNX Offline TTS (CPU)"

    private var wrapper: SherpaOnnxOfflineTtsWrapper?
    private var activeModelId: String?

    func prepare(model: TTSModel) async throws {
        guard model.engineId == id else {
            throw TTSEvalError.engineUnavailable("Model \(model.displayName) is not a Sherpa offline TTS model")
        }
        guard let cfg = model.sherpaConfig else {
            throw TTSEvalError.invalidModel("Missing Sherpa config for \(model.displayName)")
        }

        if activeModelId == model.id, wrapper != nil {
            return
        }
        // Ensure we never keep multiple models resident at once.
        if activeModelId != model.id {
            wrapper = nil
            activeModelId = nil
        }

        let modelDir = try ModelStorage.modelDirectory(modelId: model.id)
        try validateRequiredFiles(cfg: cfg, in: modelDir, modelName: model.displayName)

        let numThreads = cfg.numThreads ?? Self.recommendedThreads()
        let provider = "cpu"

        let absFile: (String?) -> String = { rel in
            guard let rel, !rel.isEmpty else { return "" }
            return modelDir.appendingPathComponent(rel, isDirectory: false).path
        }

        // Some Sherpa configs accept multiple lexicons as a comma-separated list.
        let absFilesCSV: (String?) -> String = { relCSV in
            guard let relCSV else { return "" }
            let parts = relCSV
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.isEmpty { return "" }
            return parts
                .map { modelDir.appendingPathComponent($0, isDirectory: false).path }
                .joined(separator: ",")
        }

        let absDir: (String?) -> String = { rel in
            guard let rel, !rel.isEmpty else { return "" }
            return modelDir.appendingPathComponent(rel, isDirectory: true).path
        }

        let ruleFstsAbs = cfg.ruleFsts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { modelDir.appendingPathComponent($0, isDirectory: false).path }
            .joined(separator: ",")

        let ruleFarsAbs = cfg.ruleFars
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { modelDir.appendingPathComponent($0, isDirectory: false).path }
            .joined(separator: ",")

        let vitsCfg: SherpaOnnxOfflineTtsVitsModelConfig
        let matchaCfg: SherpaOnnxOfflineTtsMatchaModelConfig
        let kokoroCfg: SherpaOnnxOfflineTtsKokoroModelConfig
        let kittenCfg: SherpaOnnxOfflineTtsKittenModelConfig
        let zipvoiceCfg: SherpaOnnxOfflineTtsZipvoiceModelConfig

        switch cfg.type {
        case .vits:
            vitsCfg = sherpaOnnxOfflineTtsVitsModelConfig(
                model: absFile(cfg.modelPath),
                lexicon: absFilesCSV(cfg.lexiconPath),
                tokens: absFile(cfg.tokensPath),
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
                acousticModel: absFile(cfg.acousticModelPath),
                vocoder: absFile(cfg.vocoderPath),
                lexicon: absFilesCSV(cfg.lexiconPath),
                tokens: absFile(cfg.tokensPath),
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
                model: absFile(cfg.modelPath),
                voices: absFile(cfg.voicesPath),
                tokens: absFile(cfg.tokensPath),
                dataDir: absDir(cfg.dataDir),
                lengthScale: cfg.lengthScale ?? 1.0,
                dictDir: absDir(cfg.dictDir),
                lexicon: absFilesCSV(cfg.lexiconPath),
                lang: cfg.lang ?? ""
            )
            kittenCfg = sherpaOnnxOfflineTtsKittenModelConfig()
            zipvoiceCfg = sherpaOnnxOfflineTtsZipvoiceModelConfig()
        case .kitten:
            vitsCfg = sherpaOnnxOfflineTtsVitsModelConfig()
            matchaCfg = sherpaOnnxOfflineTtsMatchaModelConfig()
            kokoroCfg = sherpaOnnxOfflineTtsKokoroModelConfig()
            kittenCfg = sherpaOnnxOfflineTtsKittenModelConfig(
                model: absFile(cfg.modelPath),
                voices: absFile(cfg.voicesPath),
                tokens: absFile(cfg.tokensPath),
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
                tokens: absFile(cfg.tokensPath),
                encoder: absFile(cfg.encoderPath),
                decoder: absFile(cfg.decoderPath),
                vocoder: absFile(cfg.vocoderPath),
                dataDir: absDir(cfg.dataDir),
                lexicon: absFilesCSV(cfg.lexiconPath),
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
            ruleFsts: ruleFstsAbs,
            ruleFars: ruleFarsAbs,
            maxNumSentences: 1,
            silenceScale: 0.2
        )

        let wrapper = withUnsafePointer(to: &ttsCfg) { ptr in
            SherpaOnnxOfflineTtsWrapper(config: ptr)
        }

        if wrapper.tts == nil {
            throw TTSEvalError.synthesisFailed("Failed to initialize Sherpa offline TTS for \(model.displayName)")
        }

        self.wrapper = wrapper
        activeModelId = model.id
    }

    func synthesize(text: String, settings: TTSSynthesisSettings) async throws -> TTSAudio {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw TTSEvalError.synthesisFailed("Text is empty")
        }

        guard activeModelId != nil, let wrapper else {
            throw TTSEvalError.engineUnavailable("Model not prepared")
        }

        let audio = wrapper.generate(text: normalized, sid: settings.sid, speed: settings.speed)
        let sampleRate = Int(audio.sampleRate)
        let samples = audio.samples
        return TTSAudio(samples: samples, sampleRate: sampleRate, channels: 1)
    }

    func unload() async {
        wrapper = nil
        activeModelId = nil
    }

    private func validateRequiredFiles(cfg: SherpaOfflineTTSConfig, in dir: URL, modelName: String) throws {
        func requireNonEmpty(_ rel: String?, label: String) throws -> String {
            let trimmed = (rel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw TTSEvalError.invalidModel("Missing required \(label) config for \(modelName)")
            }
            return trimmed
        }

        func requireFile(_ rel: String, label: String) throws {
            let url = dir.appendingPathComponent(rel, isDirectory: false)
            if !FileManager.default.fileExists(atPath: url.path) {
                throw TTSEvalError.modelNotDownloaded("Missing \(label) for \(modelName): \(rel)")
            }
        }

        func requireFileListCSV(_ relCSV: String?, label: String) throws {
            let parts = (relCSV ?? "")
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for p in parts {
                try requireFile(p, label: label)
            }
        }

        func requireDir(_ rel: String, label: String) throws {
            let url = dir.appendingPathComponent(rel, isDirectory: true)
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) || !isDir.boolValue {
                throw TTSEvalError.modelNotDownloaded("Missing \(label) directory for \(modelName): \(rel)")
            }
        }

        func requireDirIfPresent(_ rel: String?, label: String) throws {
            let trimmed = (rel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            try requireDir(trimmed, label: label)
        }

        func requireFileIfPresent(_ rel: String?, label: String) throws {
            let trimmed = (rel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            try requireFile(trimmed, label: label)
        }

        // Optional rule files.
        for f in cfg.ruleFsts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            try requireFile(f, label: "rule fst")
        }
        for f in cfg.ruleFars.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            try requireFile(f, label: "rule far")
        }

        switch cfg.type {
        case .kokoro:
            try requireFile(requireNonEmpty(cfg.modelPath, label: "model path"), label: "model")
            try requireFile(requireNonEmpty(cfg.voicesPath, label: "voices path"), label: "voices")
            try requireFile(requireNonEmpty(cfg.tokensPath, label: "tokens path"), label: "tokens")
            // Optional: allow Kokoro models without lexicon/dict (e.g., kokoro-en-v0_19).
            try requireFileListCSV(cfg.lexiconPath, label: "lexicon")
            try requireDirIfPresent(cfg.dataDir, label: "data")
            try requireDirIfPresent(cfg.dictDir, label: "dict")
        case .vits:
            try requireFile(requireNonEmpty(cfg.modelPath, label: "model path"), label: "model")
            try requireFile(requireNonEmpty(cfg.tokensPath, label: "tokens path"), label: "tokens")
            try requireFileListCSV(cfg.lexiconPath, label: "lexicon")
            try requireDirIfPresent(cfg.dataDir, label: "data")
        case .matcha:
            try requireFile(requireNonEmpty(cfg.acousticModelPath, label: "acoustic model path"), label: "acoustic model")
            try requireFile(requireNonEmpty(cfg.vocoderPath, label: "vocoder path"), label: "vocoder")
            try requireFile(requireNonEmpty(cfg.tokensPath, label: "tokens path"), label: "tokens")
            try requireFileListCSV(cfg.lexiconPath, label: "lexicon")
            try requireDirIfPresent(cfg.dataDir, label: "data")
        case .kitten:
            try requireFile(requireNonEmpty(cfg.modelPath, label: "model path"), label: "model")
            try requireFile(requireNonEmpty(cfg.voicesPath, label: "voices path"), label: "voices")
            try requireFile(requireNonEmpty(cfg.tokensPath, label: "tokens path"), label: "tokens")
            try requireDirIfPresent(cfg.dataDir, label: "data")
        case .zipvoice:
            try requireFile(requireNonEmpty(cfg.tokensPath, label: "tokens path"), label: "tokens")
            try requireFile(requireNonEmpty(cfg.encoderPath, label: "encoder path"), label: "encoder")
            try requireFile(requireNonEmpty(cfg.decoderPath, label: "decoder path"), label: "decoder")
            try requireFile(requireNonEmpty(cfg.vocoderPath, label: "vocoder path"), label: "vocoder")
            try requireDirIfPresent(cfg.dataDir, label: "data")
            try requireFileListCSV(cfg.lexiconPath, label: "lexicon")
        }
    }

    private nonisolated static func recommendedThreads() -> Int {
        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        return min(4, max(1, cores / 2))
    }
}
