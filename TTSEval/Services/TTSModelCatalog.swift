import Foundation

enum TTSEngineIds {
    static let avSpeech = "native.avspeech"
    static let sherpa = "sherpa.offline"
}

enum TTSModelCatalog {
    static let baselineAVSpeech = TTSModel(
        id: "avspeech-system",
        displayName: "AVSpeech (System)",
        engineId: TTSEngineIds.avSpeech,
        languages: ["system"],
        estimatedSizeBytes: nil,
        artifacts: [],
        sherpaConfig: nil
    )

    static let curated: [TTSModel] = [
        baselineAVSpeech,
        kokoroInt8MultiLangV1_0,
        vitsLjsInt8,
        matchaIcefallEnUsLjspeech,
        kittenNanoEnV0_1Fp16
    ]

    // MARK: - Curated Sherpa models

    static let kokoroInt8MultiLangV1_0: TTSModel = {
        let repo = "csukuangfj/kokoro-int8-multi-lang-v1_0"
        let artifacts: [TTSArtifact] = [
            TTSArtifact(repoId: repo, path: "model.int8.onnx"),
            TTSArtifact(repoId: repo, path: "voices.bin"),
            TTSArtifact(repoId: repo, path: "tokens.txt"),
            // Default English lexicon. Users can switch via Custom Model if needed.
            TTSArtifact(repoId: repo, path: "lexicon-us-en.txt"),
            // Required runtime data.
            TTSArtifact(repoId: repo, path: "espeak-ng-data/", destinationRelativePath: "espeak-ng-data/"),
            TTSArtifact(repoId: repo, path: "dict/", destinationRelativePath: "dict/")
        ]
        var cfg = SherpaOfflineTTSConfig(type: .kokoro)
        cfg.modelPath = "model.int8.onnx"
        cfg.voicesPath = "voices.bin"
        cfg.tokensPath = "tokens.txt"
        cfg.lexiconPath = "lexicon-us-en.txt"
        cfg.dictDir = "dict"
        cfg.dataDir = "espeak-ng-data"
        cfg.lang = "en-us"
        cfg.lengthScale = 1.0
        return TTSModel(
            id: "kokoro-int8-multi-lang-v1_0",
            displayName: "Kokoro Int8 (Multi-lang v1.0)",
            engineId: TTSEngineIds.sherpa,
            languages: ["en", "zh", "ja", "ko"],
            estimatedSizeBytes: 170_000_000,
            artifacts: artifacts,
            sherpaConfig: cfg
        )
    }()

    static let vitsLjsInt8: TTSModel = {
        let repo = "csukuangfj/vits-ljs"
        let artifacts: [TTSArtifact] = [
            TTSArtifact(repoId: repo, path: "vits-ljs.int8.onnx"),
            TTSArtifact(repoId: repo, path: "tokens.txt"),
            TTSArtifact(repoId: repo, path: "lexicon.txt")
        ]
        var cfg = SherpaOfflineTTSConfig(type: .vits)
        cfg.modelPath = "vits-ljs.int8.onnx"
        cfg.tokensPath = "tokens.txt"
        cfg.lexiconPath = "lexicon.txt"
        cfg.dataDir = ""
        cfg.noiseScale = 0.667
        cfg.noiseScaleW = 0.8
        cfg.lengthScale = 1.0
        cfg.dictDir = ""

        return TTSModel(
            id: "vits-ljs-int8",
            displayName: "VITS LJS (Int8)",
            engineId: TTSEngineIds.sherpa,
            languages: ["en"],
            estimatedSizeBytes: 450_000_000,
            artifacts: artifacts,
            sherpaConfig: cfg
        )
    }()

    static let matchaIcefallEnUsLjspeech: TTSModel = {
        let repo = "csukuangfj/matcha-icefall-en_US-ljspeech"
        let vocRepo = "k2-fsa/sherpa-onnx-models"
        let artifacts: [TTSArtifact] = [
            TTSArtifact(repoId: repo, path: "model-steps-3.onnx"),
            TTSArtifact(repoId: repo, path: "tokens.txt"),
            TTSArtifact(repoId: repo, path: "espeak-ng-data/", destinationRelativePath: "espeak-ng-data/"),
            TTSArtifact(repoId: vocRepo, path: "vocoder-models/vocos-22khz-univ.onnx", destinationRelativePath: "vocoder-models/vocos-22khz-univ.onnx")
        ]

        var cfg = SherpaOfflineTTSConfig(type: .matcha)
        cfg.acousticModelPath = "model-steps-3.onnx"
        cfg.vocoderPath = "vocoder-models/vocos-22khz-univ.onnx"
        cfg.tokensPath = "tokens.txt"
        cfg.dataDir = "espeak-ng-data"
        cfg.noiseScale = 0.667
        cfg.lengthScale = 1.0
        cfg.dictDir = ""

        return TTSModel(
            id: "matcha-icefall-en_US-ljspeech-vocos",
            displayName: "Matcha (en_US LJSpeech) + Vocos",
            engineId: TTSEngineIds.sherpa,
            languages: ["en"],
            estimatedSizeBytes: 260_000_000,
            artifacts: artifacts,
            sherpaConfig: cfg
        )
    }()

    static let kittenNanoEnV0_1Fp16: TTSModel = {
        let repo = "csukuangfj/kitten-nano-en-v0_1-fp16"
        let artifacts: [TTSArtifact] = [
            TTSArtifact(repoId: repo, path: "model.fp16.onnx"),
            TTSArtifact(repoId: repo, path: "voices.bin"),
            TTSArtifact(repoId: repo, path: "tokens.txt"),
            TTSArtifact(repoId: repo, path: "espeak-ng-data/", destinationRelativePath: "espeak-ng-data/")
        ]

        var cfg = SherpaOfflineTTSConfig(type: .kitten)
        cfg.modelPath = "model.fp16.onnx"
        cfg.voicesPath = "voices.bin"
        cfg.tokensPath = "tokens.txt"
        cfg.dataDir = "espeak-ng-data"
        cfg.lengthScale = 1.0

        return TTSModel(
            id: "kitten-nano-en-v0_1-fp16",
            displayName: "Kitten Nano (en v0.1 fp16)",
            engineId: TTSEngineIds.sherpa,
            languages: ["en"],
            estimatedSizeBytes: 40_000_000,
            artifacts: artifacts,
            sherpaConfig: cfg
        )
    }()
}
