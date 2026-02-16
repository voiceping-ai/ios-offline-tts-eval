import Foundation

enum TTSEngineIds {
    static let avSpeech = "native.avspeech"
    static let sherpa = "sherpa.offline"
    static let nemo = "nemo.fastpitch_hifigan"
}

enum TTSModelCatalog {
    static let baselineAVSpeech = TTSModel(
        id: "avspeech-system",
        displayName: "AVSpeech (System)",
        engineId: TTSEngineIds.avSpeech,
        languages: ["system"],
        estimatedSizeBytes: nil,
        artifacts: [],
        sherpaConfig: nil,
        licenseSpdx: "system",
        licenseVerified: true
    )

    static let curatedVerified: [TTSModel] = [
        baselineAVSpeech,
        kokoroEnV0_19,
        kokoroInt8MultiLangV1_1,
        kittenNanoEnV0_2Fp16,
        kittenMiniEnV0_1Fp16,
        vitsLjsInt8,
        vitsVctkInt8,
        vitsMeloZhEnInt8
    ]

    // Backward compatibility: existing code paths treat this as "curated".
    static let curated: [TTSModel] = curatedVerified

    static let communityUnverified: [TTSModel] = [
        nemoFastPitchHifiGanEn,
        matchaIcefallEnUsLjspeechVocos,
        kokoroInt8MultiLangV1_0,
        kittenNanoEnV0_1Fp16
    ]

    // MARK: - Curated Sherpa models

    static let kokoroEnV0_19: TTSModel = {
        let repo = "csukuangfj/kokoro-en-v0_19"
        let artifacts: [TTSArtifact] = [
            TTSArtifact(repoId: repo, path: "model.onnx"),
            TTSArtifact(repoId: repo, path: "voices.bin"),
            TTSArtifact(repoId: repo, path: "tokens.txt"),
            // Required runtime data.
            TTSArtifact(repoId: repo, path: "espeak-ng-data/", destinationRelativePath: "espeak-ng-data/")
        ]
        var cfg = SherpaOfflineTTSConfig(type: .kokoro)
        cfg.modelPath = "model.onnx"
        cfg.voicesPath = "voices.bin"
        cfg.tokensPath = "tokens.txt"
        cfg.dataDir = "espeak-ng-data"
        cfg.lang = "en-us"
        cfg.lengthScale = 1.0

        return TTSModel(
            id: "kokoro-en-v0_19",
            displayName: "Kokoro EN (v0.19)",
            engineId: TTSEngineIds.sherpa,
            languages: ["en"],
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg,
            licenseSpdx: "apache-2.0",
            licenseVerified: true
        )
    }()

    static let kokoroInt8MultiLangV1_1: TTSModel = {
        let repo = "csukuangfj/kokoro-int8-multi-lang-v1_1"
        let artifacts: [TTSArtifact] = [
            TTSArtifact(repoId: repo, path: "model.int8.onnx"),
            TTSArtifact(repoId: repo, path: "voices.bin"),
            TTSArtifact(repoId: repo, path: "tokens.txt"),
            // Lexicons (comma-separated in config).
            TTSArtifact(repoId: repo, path: "lexicon-us-en.txt"),
            TTSArtifact(repoId: repo, path: "lexicon-zh.txt"),
            // Rules (FSTs) for Chinese normalization.
            TTSArtifact(repoId: repo, path: "date-zh.fst"),
            TTSArtifact(repoId: repo, path: "number-zh.fst"),
            TTSArtifact(repoId: repo, path: "phone-zh.fst"),
            // Required runtime data.
            TTSArtifact(repoId: repo, path: "espeak-ng-data/", destinationRelativePath: "espeak-ng-data/"),
            TTSArtifact(repoId: repo, path: "dict/", destinationRelativePath: "dict/")
        ]
        var cfg = SherpaOfflineTTSConfig(type: .kokoro)
        cfg.modelPath = "model.int8.onnx"
        cfg.voicesPath = "voices.bin"
        cfg.tokensPath = "tokens.txt"
        cfg.lexiconPath = "lexicon-us-en.txt,lexicon-zh.txt"
        cfg.ruleFsts = ["date-zh.fst", "number-zh.fst", "phone-zh.fst"]
        cfg.dictDir = "dict"
        cfg.dataDir = "espeak-ng-data"
        cfg.lang = "en-us"
        cfg.lengthScale = 1.0

        return TTSModel(
            id: "kokoro-int8-multi-lang-v1_1",
            displayName: "Kokoro Multi-lang INT8 (v1.1)",
            engineId: TTSEngineIds.sherpa,
            languages: ["en", "zh", "ja", "ko"],
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg,
            licenseSpdx: "apache-2.0",
            licenseVerified: true
        )
    }()

    static let kittenNanoEnV0_2Fp16: TTSModel = {
        let repo = "csukuangfj/kitten-nano-en-v0_2-fp16"
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
            id: "kitten-nano-en-v0_2-fp16",
            displayName: "Kitten Nano EN (v0.2 fp16)",
            engineId: TTSEngineIds.sherpa,
            languages: ["en"],
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg,
            licenseSpdx: "apache-2.0",
            licenseVerified: true
        )
    }()

    static let kittenMiniEnV0_1Fp16: TTSModel = {
        let repo = "csukuangfj/kitten-mini-en-v0_1-fp16"
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
            id: "kitten-mini-en-v0_1-fp16",
            displayName: "Kitten Mini EN (v0.1 fp16)",
            engineId: TTSEngineIds.sherpa,
            languages: ["en"],
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg,
            licenseSpdx: "apache-2.0",
            licenseVerified: true
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
        cfg.noiseScale = 0.667
        cfg.noiseScaleW = 0.8
        cfg.lengthScale = 1.0

        return TTSModel(
            id: "vits-ljs-int8",
            displayName: "VITS LJS (Int8)",
            engineId: TTSEngineIds.sherpa,
            languages: ["en"],
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg,
            licenseSpdx: "apache-2.0",
            licenseVerified: true
        )
    }()

    static let vitsVctkInt8: TTSModel = {
        let repo = "csukuangfj/vits-vctk"
        let artifacts: [TTSArtifact] = [
            TTSArtifact(repoId: repo, path: "vits-vctk.int8.onnx"),
            TTSArtifact(repoId: repo, path: "tokens.txt"),
            TTSArtifact(repoId: repo, path: "lexicon.txt")
        ]
        var cfg = SherpaOfflineTTSConfig(type: .vits)
        cfg.modelPath = "vits-vctk.int8.onnx"
        cfg.tokensPath = "tokens.txt"
        cfg.lexiconPath = "lexicon.txt"
        cfg.noiseScale = 0.667
        cfg.noiseScaleW = 0.8
        cfg.lengthScale = 1.0

        return TTSModel(
            id: "vits-vctk-int8",
            displayName: "VITS VCTK (Int8)",
            engineId: TTSEngineIds.sherpa,
            languages: ["en"],
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg,
            licenseSpdx: "apache-2.0",
            licenseVerified: true
        )
    }()

    static let vitsMeloZhEnInt8: TTSModel = {
        let repo = "csukuangfj/vits-melo-tts-zh_en"
        let artifacts: [TTSArtifact] = [
            TTSArtifact(repoId: repo, path: "model.int8.onnx"),
            TTSArtifact(repoId: repo, path: "tokens.txt"),
            TTSArtifact(repoId: repo, path: "lexicon.txt"),
            TTSArtifact(repoId: repo, path: "date.fst"),
            TTSArtifact(repoId: repo, path: "number.fst"),
            TTSArtifact(repoId: repo, path: "phone.fst"),
            TTSArtifact(repoId: repo, path: "new_heteronym.fst")
        ]
        var cfg = SherpaOfflineTTSConfig(type: .vits)
        cfg.modelPath = "model.int8.onnx"
        cfg.tokensPath = "tokens.txt"
        cfg.lexiconPath = "lexicon.txt"
        cfg.ruleFsts = ["date.fst", "number.fst", "phone.fst", "new_heteronym.fst"]
        cfg.noiseScale = 0.667
        cfg.noiseScaleW = 0.8
        cfg.lengthScale = 1.0

        return TTSModel(
            id: "vits-melo-tts-zh_en-int8",
            displayName: "VITS Melo (ZH+EN, Int8)",
            engineId: TTSEngineIds.sherpa,
            languages: ["zh", "en"],
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg,
            licenseSpdx: "mit",
            licenseVerified: true
        )
    }()

    // MARK: - Community / unverified presets

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
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg,
            licenseSpdx: "apache-2.0",
            licenseVerified: true
        )
    }()

    static let matchaIcefallEnUsLjspeechVocos: TTSModel = {
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

        return TTSModel(
            id: "matcha-icefall-en_US-ljspeech-vocos",
            displayName: "Matcha (en_US LJSpeech) + Vocos",
            engineId: TTSEngineIds.sherpa,
            languages: ["en"],
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg,
            licenseSpdx: nil,
            licenseVerified: false
        )
    }()

    static let nemoFastPitchHifiGanEn: TTSModel = {
        TTSModel(
            id: "nemo-fastpitch-hifigan-en",
            displayName: "NVIDIA NeMo FastPitch + HiFiGAN (EN)",
            engineId: TTSEngineIds.nemo,
            languages: ["en"],
            estimatedSizeBytes: nil,
            artifacts: [],
            sherpaConfig: nil,
            licenseSpdx: nil,
            licenseVerified: false,
            localRequiredPaths: [
                "fastpitch.onnx",
                "hifigan.onnx",
                "symbols.json",
                "config.json"
            ]
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
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg,
            licenseSpdx: "apache-2.0",
            licenseVerified: true
        )
    }()
}
