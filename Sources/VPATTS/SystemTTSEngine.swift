import Foundation
import AVFoundation
import VPACore

public final class SystemTTSEngine: TTSEngine, DirectSpeechEngine {
    private let synthesizer = AVSpeechSynthesizer()
    private let voiceIdentifier: String?
    private let rate: Double?

    public init(voiceIdentifier: String? = nil, rate: Double? = nil) {
        self.voiceIdentifier = voiceIdentifier
        self.rate = rate
    }

    public func synthesize(text: String) -> AsyncStream<AudioPCM> {
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }
        if let rate {
            utterance.rate = Float(rate)
        } else {
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        }
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
