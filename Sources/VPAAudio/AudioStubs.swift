import Foundation
import VPACore

public final class StubAudioCaptureService: AudioCaptureService {
    private var preRollMs: Int = 0

    public init() {}

    public func startCapture() {}

    public func stopCapture() -> AudioPCM {
        return AudioPCM(sampleRate: 16000, channels: 1, samples: [])
    }

    public func setPreRollMs(_ ms: Int) {
        preRollMs = ms
    }
}

public final class StubVADSegmenter: VADSegmenter {
    public init() {}

    public func segment(audio: AudioPCM) -> SegmentedAudio {
        return SegmentedAudio(audio: audio, segments: [])
    }
}

public final class StubAudioPlayer: AudioPlayer {
    public init() {}

    public func play(stream: AsyncStream<AudioPCM>) {
        Task {
            for await _ in stream {
                break
            }
        }
    }

    public func stop() {}
}
