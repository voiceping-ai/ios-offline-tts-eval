import Foundation

@MainActor
final class NemoFastPitchHifiGanTTSEngine: TTSEngine {
    let id: String = TTSEngineIds.nemo
    let displayName: String = "NeMo FastPitch + HiFiGAN (ONNX Runtime, CPU)"

    private var pipeline: NemoOrtPipeline?
    private var activeModelId: String?

    func prepare(model: TTSModel) async throws {
        guard model.engineId == id else {
            throw TTSEvalError.engineUnavailable("Model \(model.displayName) is not a NeMo FastPitch+HiFiGAN model")
        }

        if activeModelId == model.id, pipeline != nil {
            return
        }
        if activeModelId != model.id {
            pipeline = nil
            activeModelId = nil
        }

        let modelDir = try ModelStorage.modelDirectory(modelId: model.id)
        try validateRequiredFiles(model: model, in: modelDir)

        let threads = Self.recommendedThreads()
        pipeline = try NemoOrtPipeline(modelDir: modelDir, numThreads: threads)
        activeModelId = model.id
    }

    func synthesize(text: String, settings: TTSSynthesisSettings) async throws -> TTSAudio {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw TTSEvalError.synthesisFailed("Text is empty")
        }
        guard let pipeline else {
            throw TTSEvalError.engineUnavailable("Model not prepared")
        }
        // NeMo engine does not currently support speaker ids or speed controls.
        _ = settings
        return try pipeline.synthesize(text: normalized)
    }

    func unload() async {
        pipeline = nil
        activeModelId = nil
    }

    private func validateRequiredFiles(model: TTSModel, in dir: URL) throws {
        let required: [String] = {
            if !model.localRequiredPaths.isEmpty { return model.localRequiredPaths }
            return ["fastpitch.onnx", "hifigan.onnx", "symbols.json", "config.json"]
        }()

        for rel in required {
            let trimmed = rel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let url = dir.appendingPathComponent(trimmed, isDirectory: false)
            if !FileManager.default.fileExists(atPath: url.path) {
                throw TTSEvalError.modelNotDownloaded("Missing required file for \(model.displayName): \(trimmed)")
            }
        }
    }

    private nonisolated static func recommendedThreads() -> Int {
        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        return min(4, max(1, cores / 2))
    }
}

// MARK: - NeMo ONNX Runtime pipeline (C API)

private final class NemoOrtPipeline {
    private let ort = Ort.shared

    private let modelDir: URL
    private let sampleRate: Int
    private let nMels: Int
    private let tokenizer: NemoCharTokenizer

    private let fpSession: OpaquePointer
    private let hgSession: OpaquePointer
    private let fpOutputNames: [String]
    private let hgOutputNames: [String]

    init(modelDir: URL, numThreads: Int) throws {
        self.modelDir = modelDir

        let configURL = modelDir.appendingPathComponent("config.json", isDirectory: false)
        let symbolsURL = modelDir.appendingPathComponent("symbols.json", isDirectory: false)

        let config = try NemoConfig.load(url: configURL)
        let symbols = try NemoSymbols.load(url: symbolsURL)

        // symbols.json is authoritative if it specifies ids/flags.
        let effectiveAddBlank = symbols.addBlank ?? config.addBlank
        let effectiveBlankId = Int64(symbols.blankId ?? Int(config.blankId))
        let effectivePadId = Int64(symbols.padId ?? Int(config.padId))

        var symbolToId: [String: Int64] = [:]
        symbolToId.reserveCapacity(symbols.symbols.count)
        for (i, s) in symbols.symbols.enumerated() {
            guard !s.isEmpty else { continue }
            symbolToId[s] = Int64(i)
        }

        self.sampleRate = config.sampleRate
        self.nMels = config.nMels
        self.tokenizer = NemoCharTokenizer(
            symbolToId: symbolToId,
            blankId: effectiveBlankId,
            padId: effectivePadId,
            addBlank: effectiveAddBlank
        )

        let fpPath = modelDir.appendingPathComponent("fastpitch.onnx", isDirectory: false).path
        let hgPath = modelDir.appendingPathComponent("hifigan.onnx", isDirectory: false).path

        self.fpSession = try ort.createSession(modelPath: fpPath, intraOpThreads: numThreads)
        self.hgSession = try ort.createSession(modelPath: hgPath, intraOpThreads: numThreads)

        self.fpOutputNames = try ort.sessionOutputNames(session: fpSession)
        self.hgOutputNames = try ort.sessionOutputNames(session: hgSession)

        // Validate expected IO names for our engine.
        let fpInputs = try ort.sessionInputNames(session: fpSession)
        if !fpInputs.contains("input_ids") || !fpInputs.contains("input_lengths") {
            throw TTSEvalError.invalidModel("FastPitch ONNX must have inputs: input_ids, input_lengths (got: \(fpInputs))")
        }
        if fpOutputNames.isEmpty {
            throw TTSEvalError.invalidModel("FastPitch ONNX has no outputs")
        }

        let hgInputs = try ort.sessionInputNames(session: hgSession)
        if !hgInputs.contains("mel") {
            throw TTSEvalError.invalidModel("HiFiGAN ONNX must have input: mel (got: \(hgInputs))")
        }
        if hgOutputNames.isEmpty {
            throw TTSEvalError.invalidModel("HiFiGAN ONNX has no outputs")
        }
    }

    deinit {
        ort.releaseSession(fpSession)
        ort.releaseSession(hgSession)
    }

    func synthesize(text: String) throws -> TTSAudio {
        let idsI64 = tokenizer.tokenize(text)
        var inputIds = idsI64
        var inputLens: [Int64] = [Int64(inputIds.count)]

        let melOut = try ort.run(
            session: fpSession,
            inputNames: ["input_ids", "input_lengths"],
            makeInputValues: {
                // input_ids: int64[1, L]
                let ids = try ort.makeTensorInt64(data: &inputIds, shape: [1, Int64(inputIds.count)])
                // input_lengths: int64[1]
                let lens = try ort.makeTensorInt64(data: &inputLens, shape: [1])
                return [ids, lens]
            },
            outputNames: fpOutputNames
        )

        guard let melValue = melOut.first else {
            throw TTSEvalError.synthesisFailed("FastPitch produced no outputs")
        }

        let mel = try ort.readTensorFloat(value: melValue)
        let melShape = mel.shape
        guard melShape.count >= 2 else {
            throw TTSEvalError.synthesisFailed("Unexpected mel shape: \(melShape)")
        }

        let melNMels = Int(melShape[melShape.count - 2])
        let melT = Int(melShape.last ?? 0)
        if melNMels <= 0 || melT <= 0 {
            throw TTSEvalError.synthesisFailed("Invalid mel shape: \(melShape)")
        }

        if melNMels != nMels {
            // Not fatal, but likely indicates mismatch between export config and model output.
            print("NeMo: config n_mels=\(nMels) but mel output n_mels=\(melNMels)")
        }

        // HiFiGAN expects float[1, n_mels, T].
        var melFlat = mel.data
        let audioOut = try ort.run(
            session: hgSession,
            inputNames: ["mel"],
            makeInputValues: {
                let melTensor = try ort.makeTensorFloat(data: &melFlat, shape: [1, Int64(melNMels), Int64(melT)])
                return [melTensor]
            },
            outputNames: hgOutputNames
        )

        guard let audioValue = audioOut.first else {
            throw TTSEvalError.synthesisFailed("HiFiGAN produced no outputs")
        }

        let audio = try ort.readTensorFloat(value: audioValue)
        // Output is typically [S] or [1, S] or [1, 1, S]; we just flatten.
        return TTSAudio(samples: audio.data, sampleRate: sampleRate, channels: 1)
    }
}

private struct NemoConfig: Codable, Sendable {
    let sampleRate: Int
    let nMels: Int
    let addBlank: Bool
    let blankId: Int64
    let padId: Int64

    static func load(url: URL) throws -> NemoConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(NemoConfig.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case nMels = "n_mels"
        case addBlank = "add_blank"
        case blankId = "blank_id"
        case padId = "pad_id"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.sampleRate = try c.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 22_050
        self.nMels = try c.decodeIfPresent(Int.self, forKey: .nMels) ?? 80
        self.addBlank = try c.decodeIfPresent(Bool.self, forKey: .addBlank) ?? true
        self.blankId = try c.decodeIfPresent(Int64.self, forKey: .blankId) ?? 0
        self.padId = try c.decodeIfPresent(Int64.self, forKey: .padId) ?? 0
    }
}

private struct NemoSymbols: Codable, Sendable {
    let symbols: [String]
    let blankId: Int?
    let padId: Int?
    let addBlank: Bool?

    static func load(url: URL) throws -> NemoSymbols {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(NemoSymbols.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case symbols
        case blankId = "blank_id"
        case padId = "pad_id"
        case addBlank = "add_blank"
    }
}

private final class Ort {
    static let shared = Ort()

    private let api: UnsafePointer<OrtApi>
    private let env: OpaquePointer
    private let allocator: UnsafeMutablePointer<OrtAllocator>
    private let cpuMemInfo: OpaquePointer

    private init() {
        // NOTE: This must match the ORT headers in the shared xcframework.
        let ortApiVersion: UInt32 = 17

        guard let base = OrtGetApiBase() else {
            fatalError("OrtGetApiBase returned nil")
        }
        guard let api = base.pointee.GetApi(ortApiVersion) else {
            fatalError("OrtApiBase.GetApi(\(ortApiVersion)) returned nil")
        }
        self.api = api

        var envOut: OpaquePointer?
        let st1 = api.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "ttseval", &envOut)
        if let st1 {
            let msg = api.pointee.GetErrorMessage(st1).map { String(cString: $0) } ?? "unknown"
            api.pointee.ReleaseStatus(st1)
            fatalError("ORT CreateEnv failed: \(msg)")
        }
        guard let envOut else {
            fatalError("ORT CreateEnv returned nil env")
        }
        self.env = envOut

        var allocOut: UnsafeMutablePointer<OrtAllocator>?
        let st2 = api.pointee.GetAllocatorWithDefaultOptions(&allocOut)
        try? Self.check(status: st2, api: api, context: "GetAllocatorWithDefaultOptions")
        guard let allocOut else {
            fatalError("ORT GetAllocatorWithDefaultOptions returned nil allocator")
        }
        self.allocator = allocOut

        var memInfoOut: OpaquePointer?
        let st3 = api.pointee.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memInfoOut)
        try? Self.check(status: st3, api: api, context: "CreateCpuMemoryInfo")
        guard let memInfoOut else {
            fatalError("ORT CreateCpuMemoryInfo returned nil memory info")
        }
        self.cpuMemInfo = memInfoOut
    }

    deinit {
        // Keep the ORT env for the app lifetime. (ORT also documents CreateEnv as a singleton.)
        api.pointee.ReleaseMemoryInfo(cpuMemInfo)
        api.pointee.ReleaseEnv(env)
    }

    func createSession(modelPath: String, intraOpThreads: Int) throws -> OpaquePointer {
        var opts: OpaquePointer?
        try Self.check(status: api.pointee.CreateSessionOptions(&opts), api: api, context: "CreateSessionOptions")
        guard let opts else {
            throw TTSEvalError.synthesisFailed("ORT CreateSessionOptions returned nil")
        }
        defer { api.pointee.ReleaseSessionOptions(opts) }

        _ = api.pointee.SetIntraOpNumThreads(opts, Int32(intraOpThreads))
        _ = api.pointee.SetInterOpNumThreads(opts, 1)

        var sessionOut: OpaquePointer?
        try modelPath.withCString { cstr in
            try Self.check(status: api.pointee.CreateSession(env, cstr, opts, &sessionOut), api: api, context: "CreateSession")
        }
        guard let sessionOut else {
            throw TTSEvalError.synthesisFailed("ORT CreateSession returned nil session")
        }
        return sessionOut
    }

    func releaseSession(_ session: OpaquePointer) {
        api.pointee.ReleaseSession(session)
    }

    func sessionInputNames(session: OpaquePointer) throws -> [String] {
        var count: Int = 0
        try Self.check(status: api.pointee.SessionGetInputCount(session, &count), api: api, context: "SessionGetInputCount")
        if count <= 0 { return [] }

        var out: [String] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            var namePtr: UnsafeMutablePointer<CChar>?
            try Self.check(status: api.pointee.SessionGetInputName(session, i, allocator, &namePtr), api: api, context: "SessionGetInputName")
            guard let namePtr else { continue }
            defer { _ = api.pointee.AllocatorFree(allocator, namePtr) }
            out.append(String(cString: namePtr))
        }
        return out
    }

    func sessionOutputNames(session: OpaquePointer) throws -> [String] {
        var count: Int = 0
        try Self.check(status: api.pointee.SessionGetOutputCount(session, &count), api: api, context: "SessionGetOutputCount")
        if count <= 0 { return [] }

        var out: [String] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            var namePtr: UnsafeMutablePointer<CChar>?
            try Self.check(status: api.pointee.SessionGetOutputName(session, i, allocator, &namePtr), api: api, context: "SessionGetOutputName")
            guard let namePtr else { continue }
            defer { _ = api.pointee.AllocatorFree(allocator, namePtr) }
            out.append(String(cString: namePtr))
        }
        return out
    }

    func makeTensorInt64(data: inout [Int64], shape: [Int64]) throws -> OpaquePointer {
        var value: OpaquePointer?
        let bytes = data.count * MemoryLayout<Int64>.size
        try data.withUnsafeMutableBytes { rawBuf in
            guard let base = rawBuf.baseAddress else {
                throw TTSEvalError.synthesisFailed("ORT tensor data buffer is nil")
            }
            try shape.withUnsafeBufferPointer { shapeBuf in
                try Self.check(
                    status: api.pointee.CreateTensorWithDataAsOrtValue(
                        cpuMemInfo,
                        base,
                        bytes,
                        shapeBuf.baseAddress,
                        shape.count,
                        ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                        &value
                    ),
                    api: api,
                    context: "CreateTensorWithDataAsOrtValue(int64)"
                )
            }
        }
        guard let value else {
            throw TTSEvalError.synthesisFailed("ORT CreateTensorWithDataAsOrtValue returned nil")
        }
        return value
    }

    func makeTensorFloat(data: inout [Float], shape: [Int64]) throws -> OpaquePointer {
        var value: OpaquePointer?
        let bytes = data.count * MemoryLayout<Float>.size
        try data.withUnsafeMutableBytes { rawBuf in
            guard let base = rawBuf.baseAddress else {
                throw TTSEvalError.synthesisFailed("ORT tensor data buffer is nil")
            }
            try shape.withUnsafeBufferPointer { shapeBuf in
                try Self.check(
                    status: api.pointee.CreateTensorWithDataAsOrtValue(
                        cpuMemInfo,
                        base,
                        bytes,
                        shapeBuf.baseAddress,
                        shape.count,
                        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
                        &value
                    ),
                    api: api,
                    context: "CreateTensorWithDataAsOrtValue(float)"
                )
            }
        }
        guard let value else {
            throw TTSEvalError.synthesisFailed("ORT CreateTensorWithDataAsOrtValue returned nil")
        }
        return value
    }

    func run(
        session: OpaquePointer,
        inputNames: [String],
        makeInputValues: () throws -> [OpaquePointer],
        outputNames: [String]
    ) throws -> [OpaquePointer] {
        let inputVals = try makeInputValues()
        defer { inputVals.forEach { api.pointee.ReleaseValue($0) } }

        let inNamePtrs = try Self.cStringPointers(inputNames)
        defer { inNamePtrs.forEach { free($0) } }
        let outNamePtrs = try Self.cStringPointers(outputNames)
        defer { outNamePtrs.forEach { free($0) } }

        var inNameConst: [UnsafePointer<CChar>?] = inNamePtrs.map { UnsafePointer($0) }
        var outNameConst: [UnsafePointer<CChar>?] = outNamePtrs.map { UnsafePointer($0) }
        var inValsOpt: [OpaquePointer?] = inputVals.map { $0 }
        var outVals: [OpaquePointer?] = Array(repeating: nil, count: outputNames.count)

        try inNameConst.withUnsafeMutableBufferPointer { inNamesBuf in
            try outNameConst.withUnsafeMutableBufferPointer { outNamesBuf in
                try inValsOpt.withUnsafeMutableBufferPointer { inValsBuf in
                    try outVals.withUnsafeMutableBufferPointer { outValsBuf in
                        try Self.check(
                            status: api.pointee.Run(
                                session,
                                nil,
                                inNamesBuf.baseAddress,
                                UnsafePointer(inValsBuf.baseAddress),
                                inputNames.count,
                                outNamesBuf.baseAddress,
                                outputNames.count,
                                outValsBuf.baseAddress
                            ),
                            api: api,
                            context: "Run"
                        )
                    }
                }
            }
        }

        let outs: [OpaquePointer] = outVals.compactMap { $0 }
        if outs.count != outputNames.count {
            // Release any partial outputs.
            for v in outs { api.pointee.ReleaseValue(v) }
            throw TTSEvalError.synthesisFailed("ORT Run returned unexpected number of outputs (\(outs.count)/\(outputNames.count))")
        }
        return outs
    }

    struct FloatTensor {
        let data: [Float]
        let shape: [Int64]
    }

    func readTensorFloat(value: OpaquePointer) throws -> FloatTensor {
        var info: OpaquePointer?
        try Self.check(status: api.pointee.GetTensorTypeAndShape(value, &info), api: api, context: "GetTensorTypeAndShape")
        guard let info else {
            throw TTSEvalError.synthesisFailed("ORT GetTensorTypeAndShape returned nil")
        }
        defer { api.pointee.ReleaseTensorTypeAndShapeInfo(info) }

        var dimCount: Int = 0
        try Self.check(status: api.pointee.GetDimensionsCount(info, &dimCount), api: api, context: "GetDimensionsCount")
        var dims: [Int64] = Array(repeating: 0, count: max(dimCount, 0))
        if dimCount > 0 {
            try dims.withUnsafeMutableBufferPointer { buf in
                try Self.check(status: api.pointee.GetDimensions(info, buf.baseAddress, dimCount), api: api, context: "GetDimensions")
            }
        }

        var elemCount: Int = 0
        try Self.check(status: api.pointee.GetTensorShapeElementCount(info, &elemCount), api: api, context: "GetTensorShapeElementCount")
        if elemCount <= 0 {
            return .init(data: [], shape: dims)
        }

        var rawOut: UnsafeMutableRawPointer?
        try Self.check(status: api.pointee.GetTensorMutableData(value, &rawOut), api: api, context: "GetTensorMutableData")
        guard let rawOut else {
            throw TTSEvalError.synthesisFailed("ORT GetTensorMutableData returned nil")
        }

        let ptr = rawOut.assumingMemoryBound(to: Float.self)
        let buf = UnsafeBufferPointer(start: ptr, count: elemCount)
        return .init(data: Array(buf), shape: dims)
    }

    private static func cStringPointers(_ strings: [String]) throws -> [UnsafeMutablePointer<CChar>] {
        var out: [UnsafeMutablePointer<CChar>] = []
        out.reserveCapacity(strings.count)
        for s in strings {
            guard let p = strdup(s) else {
                throw TTSEvalError.synthesisFailed("strdup failed")
            }
            out.append(p)
        }
        return out
    }

    private static func check(status: OpaquePointer?, api: UnsafePointer<OrtApi>, context: String) throws {
        guard let status else { return }
        let msg = api.pointee.GetErrorMessage(status).map { String(cString: $0) } ?? "unknown"
        api.pointee.ReleaseStatus(status)
        throw TTSEvalError.synthesisFailed("ORT \(context) failed: \(msg)")
    }
}
