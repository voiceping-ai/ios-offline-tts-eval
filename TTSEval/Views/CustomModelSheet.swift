import SwiftUI

struct CustomModelSheet: View {
    let onAdd: (TTSModel) -> Void
    let onCancel: () -> Void

    @State private var type: SherpaTTSModelType = .kokoro
    @State private var repoId: String = ""
    @State private var displayName: String = ""

    // Common files
    @State private var modelFile: String = "model.int8.onnx"
    @State private var voicesFile: String = "voices.bin"
    @State private var tokensFile: String = "tokens.txt"
    @State private var lexiconFile: String = "lexicon-us-en.txt"

    // Matcha
    @State private var acousticModelFile: String = "model-steps-3.onnx"
    @State private var useVocosVocoder: Bool = true
    @State private var vocoderRepoId: String = "k2-fsa/sherpa-onnx-models"
    @State private var vocoderPath: String = "vocoder-models/vocos-22khz-univ.onnx"

    // Directories
    @State private var includeEspeakData: Bool = true
    @State private var includeDictDir: Bool = true

    // Kokoro
    @State private var kokoroLang: String = "en-us"
    @State private var lengthScale: Float = 1.0

    // Zipvoice
    @State private var encoderFile: String = "encoder.onnx"
    @State private var decoderFile: String = "decoder.onnx"
    @State private var zipvoiceVocoderFile: String = "vocoder.onnx"

    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Type") {
                Picker("Model Type", selection: $type) {
                    ForEach(SherpaTTSModelType.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .onChange(of: type) { _, newValue in
                    applyDefaults(for: newValue)
                }
            }

            Section("Source") {
                TextField("Hugging Face repo id (org/name)", text: $repoId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Display name (optional)", text: $displayName)
            }

            Section("Files") {
                switch type {
                case .kokoro:
                    TextField("model file", text: $modelFile)
                    TextField("voices file", text: $voicesFile)
                    TextField("tokens file", text: $tokensFile)
                    TextField("lexicon file", text: $lexiconFile)

                case .vits:
                    TextField("model file", text: $modelFile)
                    TextField("tokens file", text: $tokensFile)
                    TextField("lexicon file", text: $lexiconFile)

                case .matcha:
                    TextField("acoustic model file", text: $acousticModelFile)
                    TextField("tokens file", text: $tokensFile)

                    Toggle("Use Vocos vocoder (22k)", isOn: $useVocosVocoder)

                    if !useVocosVocoder {
                        TextField("vocoder repo id", text: $vocoderRepoId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("vocoder path", text: $vocoderPath)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                case .kitten:
                    TextField("model file", text: $modelFile)
                    TextField("voices file", text: $voicesFile)
                    TextField("tokens file", text: $tokensFile)

                case .zipvoice:
                    TextField("tokens file", text: $tokensFile)
                    TextField("encoder file", text: $encoderFile)
                    TextField("decoder file", text: $decoderFile)
                    TextField("vocoder file", text: $zipvoiceVocoderFile)
                }
            }

            Section("Options") {
                if type == .kokoro {
                    TextField("lang", text: $kokoroLang)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Text("lengthScale")
                        Slider(value: Binding(get: { Double(lengthScale) }, set: { lengthScale = Float($0) }), in: 0.7...1.3, step: 0.05)
                        Text(String(format: "%.2f", lengthScale))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if type == .kokoro || type == .matcha || type == .kitten {
                    Toggle("Include espeak-ng-data/", isOn: $includeEspeakData)
                }
                if type == .kokoro {
                    Toggle("Include dict/", isOn: $includeDictDir)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Add Custom")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    do {
                        let model = try buildModel()
                        onAdd(model)
                    } catch {
                        errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    }
                }
            }
        }
        .onAppear {
            applyDefaults(for: type)
        }
    }

    private func applyDefaults(for type: SherpaTTSModelType) {
        errorMessage = nil
        switch type {
        case .kokoro:
            modelFile = "model.int8.onnx"
            voicesFile = "voices.bin"
            tokensFile = "tokens.txt"
            lexiconFile = "lexicon-us-en.txt"
            includeEspeakData = true
            includeDictDir = true
            kokoroLang = "en-us"
            lengthScale = 1.0
        case .vits:
            modelFile = "vits-ljs.int8.onnx"
            tokensFile = "tokens.txt"
            lexiconFile = "lexicon.txt"
            includeEspeakData = false
            includeDictDir = false
        case .matcha:
            acousticModelFile = "model-steps-3.onnx"
            tokensFile = "tokens.txt"
            includeEspeakData = true
            useVocosVocoder = true
            vocoderRepoId = "k2-fsa/sherpa-onnx-models"
            vocoderPath = "vocoder-models/vocos-22khz-univ.onnx"
            includeDictDir = false
        case .kitten:
            modelFile = "model.fp16.onnx"
            voicesFile = "voices.bin"
            tokensFile = "tokens.txt"
            includeEspeakData = true
            includeDictDir = false
        case .zipvoice:
            tokensFile = "tokens.txt"
            encoderFile = "encoder.onnx"
            decoderFile = "decoder.onnx"
            zipvoiceVocoderFile = "vocoder.onnx"
            includeEspeakData = false
            includeDictDir = false
        }
    }

    private func buildModel() throws -> TTSModel {
        let repo = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty, repo.contains("/") else {
            throw TTSEvalError.invalidModel("Enter a valid Hugging Face repo id (org/name)")
        }

        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "Custom \(type.displayName)" : name

        let id = makeModelId(type: type, repoId: repo)

        var artifacts: [TTSArtifact] = []
        var cfg = SherpaOfflineTTSConfig(type: type)

        switch type {
        case .kokoro:
            artifacts.append(TTSArtifact(repoId: repo, path: modelFile))
            artifacts.append(TTSArtifact(repoId: repo, path: voicesFile))
            artifacts.append(TTSArtifact(repoId: repo, path: tokensFile))
            artifacts.append(TTSArtifact(repoId: repo, path: lexiconFile))
            if includeEspeakData {
                artifacts.append(TTSArtifact(repoId: repo, path: "espeak-ng-data/", destinationRelativePath: "espeak-ng-data/"))
                cfg.dataDir = "espeak-ng-data"
            }
            if includeDictDir {
                artifacts.append(TTSArtifact(repoId: repo, path: "dict/", destinationRelativePath: "dict/"))
                cfg.dictDir = "dict"
            }

            cfg.modelPath = modelFile
            cfg.voicesPath = voicesFile
            cfg.tokensPath = tokensFile
            cfg.lexiconPath = lexiconFile
            cfg.lang = kokoroLang
            cfg.lengthScale = lengthScale

        case .vits:
            artifacts.append(TTSArtifact(repoId: repo, path: modelFile))
            artifacts.append(TTSArtifact(repoId: repo, path: tokensFile))
            artifacts.append(TTSArtifact(repoId: repo, path: lexiconFile))
            cfg.modelPath = modelFile
            cfg.tokensPath = tokensFile
            cfg.lexiconPath = lexiconFile

        case .matcha:
            artifacts.append(TTSArtifact(repoId: repo, path: acousticModelFile))
            artifacts.append(TTSArtifact(repoId: repo, path: tokensFile))
            if includeEspeakData {
                artifacts.append(TTSArtifact(repoId: repo, path: "espeak-ng-data/", destinationRelativePath: "espeak-ng-data/"))
                cfg.dataDir = "espeak-ng-data"
            }

            let vocRepo = useVocosVocoder ? "k2-fsa/sherpa-onnx-models" : vocoderRepoId
            let vocPath = useVocosVocoder ? "vocoder-models/vocos-22khz-univ.onnx" : vocoderPath
            artifacts.append(TTSArtifact(repoId: vocRepo, path: vocPath, destinationRelativePath: vocPath))

            cfg.acousticModelPath = acousticModelFile
            cfg.tokensPath = tokensFile
            cfg.vocoderPath = vocPath

        case .kitten:
            artifacts.append(TTSArtifact(repoId: repo, path: modelFile))
            artifacts.append(TTSArtifact(repoId: repo, path: voicesFile))
            artifacts.append(TTSArtifact(repoId: repo, path: tokensFile))
            if includeEspeakData {
                artifacts.append(TTSArtifact(repoId: repo, path: "espeak-ng-data/", destinationRelativePath: "espeak-ng-data/"))
                cfg.dataDir = "espeak-ng-data"
            }

            cfg.modelPath = modelFile
            cfg.voicesPath = voicesFile
            cfg.tokensPath = tokensFile
            cfg.lengthScale = lengthScale

        case .zipvoice:
            artifacts.append(TTSArtifact(repoId: repo, path: tokensFile))
            artifacts.append(TTSArtifact(repoId: repo, path: encoderFile))
            artifacts.append(TTSArtifact(repoId: repo, path: decoderFile))
            artifacts.append(TTSArtifact(repoId: repo, path: zipvoiceVocoderFile))
            cfg.tokensPath = tokensFile
            cfg.encoderPath = encoderFile
            cfg.decoderPath = decoderFile
            cfg.vocoderPath = zipvoiceVocoderFile
        }

        return TTSModel(
            id: id,
            displayName: finalName,
            engineId: TTSEngineIds.sherpa,
            languages: [],
            estimatedSizeBytes: nil,
            artifacts: artifacts,
            sherpaConfig: cfg
        )
    }

    private func makeModelId(type: SherpaTTSModelType, repoId: String) -> String {
        let base = repoId
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let suffix = UUID().uuidString.prefix(8)
        return "\(type.rawValue)-\(base)-\(suffix)"
    }
}
