import Foundation
import AVFoundation

@MainActor
final class NativeAVSpeechTTSEngine: TTSEngine {
    let id: String = TTSEngineIds.avSpeech
    let displayName: String = "AVSpeechSynthesizer (System)"

    private let synthesizer = AVSpeechSynthesizer()

    func prepare(model: TTSModel) async throws {
        guard model.engineId == id else {
            throw TTSEvalError.engineUnavailable("Model \(model.displayName) is not an AVSpeech model")
        }
        // No model files to load.
    }

    func synthesize(text: String, settings: TTSSynthesisSettings) async throws -> TTSAudio {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw TTSEvalError.synthesisFailed("Text is empty")
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // `write()` is effectively offline rendering; configure an audio session up-front to
        // avoid stalls on some devices/OS versions.
        try configureAudioSession()

        let utterance = AVSpeechUtterance(string: normalized)
        utterance.rate = Self.mapRate01ToAVSpeech(settings.nativeRate)

        // Use write() so we can capture audio for benchmarking/playback.
        return try await withCheckedThrowingContinuation { continuation in
            var sampleRate: Double = 0
            var collected: [Float] = []
            let finishLock = NSLock()
            var finished = false

            synthesizer.write(utterance) { buffer in
                if Task.isCancelled {
                    self.synthesizer.stopSpeaking(at: .immediate)
                    finishLock.lock()
                    defer { finishLock.unlock() }
                    guard !finished else { return }
                    finished = true
                    continuation.resume(throwing: CancellationError())
                    return
                }

                guard let pcm = buffer as? AVAudioPCMBuffer else {
                    return
                }

                if pcm.frameLength == 0 {
                    finishLock.lock()
                    defer { finishLock.unlock() }
                    guard !finished else { return }
                    finished = true

                    let sr = Int(sampleRate == 0 ? 24000 : sampleRate)
                    continuation.resume(returning: TTSAudio(samples: collected, sampleRate: sr, channels: 1))
                    return
                }

                if sampleRate == 0 {
                    sampleRate = pcm.format.sampleRate
                }

                let frames = Int(pcm.frameLength)
                let channels = Int(pcm.format.channelCount)

                switch pcm.format.commonFormat {
                case .pcmFormatFloat32:
                    guard let data = pcm.floatChannelData else { return }
                    collected.reserveCapacity(collected.count + frames)
                    for i in 0..<frames {
                        var sum: Float = 0
                        for ch in 0..<channels {
                            sum += data[ch][i]
                        }
                        collected.append(sum / Float(max(channels, 1)))
                    }

                case .pcmFormatInt16:
                    guard let data = pcm.int16ChannelData else { return }
                    collected.reserveCapacity(collected.count + frames)
                    for i in 0..<frames {
                        var sum: Float = 0
                        for ch in 0..<channels {
                            sum += Float(data[ch][i]) / 32768.0
                        }
                        collected.append(sum / Float(max(channels, 1)))
                    }

                default:
                    // Unsupported format for v1.
                    break
                }
            }
        }
    }

    func unload() async {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private static func mapRate01ToAVSpeech(_ rate01: Float) -> Float {
        let clamped = min(max(rate01, 0), 1)
        let minRate = AVSpeechUtteranceMinimumSpeechRate
        let maxRate = AVSpeechUtteranceMaximumSpeechRate
        return minRate + (maxRate - minRate) * clamped
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }
}
