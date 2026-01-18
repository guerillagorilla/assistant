import Foundation
import AVFoundation
import VPACore

public final class AVSpeechStreamTTSEngine: TTSEngine {
    private let synthesizer = AVSpeechSynthesizer()
    private let voiceIdentifier: String?
    private let rate: Double?

    public init(voiceIdentifier: String? = nil, rate: Double? = nil) {
        self.voiceIdentifier = voiceIdentifier
        self.rate = rate
    }

    public func synthesize(text: String) -> AsyncStream<AudioPCM> {
        return AsyncStream { continuation in
            let utterance = AVSpeechUtterance(string: text)
            if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
                utterance.voice = voice
            }
            if let rate {
                utterance.rate = Float(rate)
            } else {
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            }

            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                if pcmBuffer.frameLength == 0 {
                    continuation.finish()
                    return
                }
                if let audio = Self.pcmBufferToAudio(pcmBuffer: pcmBuffer) {
                    continuation.yield(audio)
                }
            }
        }
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private static func pcmBufferToAudio(pcmBuffer: AVAudioPCMBuffer) -> AudioPCM? {
        let format = pcmBuffer.format
        let sampleRate = Int(format.sampleRate)
        let frameLength = Int(pcmBuffer.frameLength)
        if frameLength == 0 { return nil }

        if format.commonFormat == .pcmFormatFloat32, let floatPtr = pcmBuffer.floatChannelData {
            let chan = floatPtr[0]
            var samples: [Int16] = []
            samples.reserveCapacity(frameLength)
            for i in 0..<frameLength {
                let f = max(-1.0, min(1.0, Double(chan[i])))
                samples.append(Int16(f * 32767.0))
            }
            return AudioPCM(sampleRate: sampleRate, channels: 1, samples: samples)
        }

        if format.commonFormat == .pcmFormatInt16, let int16Ptr = pcmBuffer.int16ChannelData {
            let samples = Array(UnsafeBufferPointer(start: int16Ptr[0], count: frameLength))
            return AudioPCM(sampleRate: sampleRate, channels: 1, samples: samples)
        }

        return nil
    }
}
