import Foundation
import AVFoundation

@MainActor
final class AudioPlaybackService {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private(set) var isPlaying: Bool = false
    var onPlaybackStateChanged: ((Bool) -> Void)?

    init() {
        engine.attach(player)
    }

    func stop() {
        if player.isPlaying {
            player.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
        updatePlaybackState(false)
    }

    func play(_ audio: TTSAudio, normalize: Bool) throws {
        stop()
        guard audio.sampleRate > 0, !audio.samples.isEmpty else {
            throw TTSEvalError.audioPlaybackFailed("No audio samples to play")
        }

        try configureAudioSession()

        let samples = normalize ? Self.normalized(samples: audio.samples) : audio.samples

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(audio.sampleRate),
            channels: AVAudioChannelCount(max(1, audio.channels)),
            interleaved: false
        ) else {
            throw TTSEvalError.audioPlaybackFailed("Failed to create AVAudioFormat")
        }

        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let frames = AVAudioFrameCount(samples.count / max(1, audio.channels))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw TTSEvalError.audioPlaybackFailed("Failed to allocate PCM buffer")
        }
        buffer.frameLength = frames

        // v1: mono only; if channels > 1, duplicate into all channels.
        let channels = Int(format.channelCount)
        for ch in 0..<channels {
            guard let dst = buffer.floatChannelData?[ch] else { continue }
            for i in 0..<Int(frames) {
                let v = samples[min(i, samples.count - 1)]
                dst[i] = v
            }
        }

        try engine.start()

        updatePlaybackState(true)
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor in
                self?.updatePlaybackState(false)
            }
        }
        player.play()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }

    private static func normalized(samples: [Float]) -> [Float] {
        var peak: Float = 0
        for s in samples {
            peak = max(peak, abs(s))
        }
        if peak < 0.0001 {
            return samples
        }
        let target: Float = 0.95
        let scale = target / peak
        if scale >= 0.999 {
            return samples
        }
        return samples.map { $0 * scale }
    }

    private func updatePlaybackState(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
        onPlaybackStateChanged?(playing)
    }
}
