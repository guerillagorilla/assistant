import Foundation
import VPACore

public final class StubSTTEngine: STTEngine {
    public init() {}

    public func transcribe(audio: AudioPCM) -> Transcript {
        return Transcript(text: "", confidence: 0.0)
    }
}
