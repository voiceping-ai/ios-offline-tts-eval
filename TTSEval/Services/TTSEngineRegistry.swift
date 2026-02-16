import Foundation

@MainActor
final class TTSEngineRegistry {
    static let shared = TTSEngineRegistry()

    private var engines: [String: TTSEngine] = [:]

    private init() {
        register(NativeAVSpeechTTSEngine())
        register(SherpaOnnxOfflineTTSEngine())
        register(NemoFastPitchHifiGanTTSEngine())
    }

    func register(_ engine: TTSEngine) {
        engines[engine.id] = engine
    }

    func engine(for id: String) -> TTSEngine? {
        engines[id]
    }

    var allEngines: [TTSEngine] {
        Array(engines.values)
    }
}
