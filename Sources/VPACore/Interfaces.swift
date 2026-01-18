import Foundation

public struct AudioPCM {
    public let sampleRate: Int
    public let channels: Int
    public let samples: [Int16]

    public init(sampleRate: Int, channels: Int, samples: [Int16]) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.samples = samples
    }
}

public struct WordTiming {
    public let word: String
    public let startMs: Int
    public let endMs: Int

    public init(word: String, startMs: Int, endMs: Int) {
        self.word = word
        self.startMs = startMs
        self.endMs = endMs
    }
}

public struct Transcript {
    public let text: String
    public let confidence: Double
    public let wordTimings: [WordTiming]

    public init(text: String, confidence: Double, wordTimings: [WordTiming] = []) {
        self.text = text
        self.confidence = confidence
        self.wordTimings = wordTimings
    }
}

public struct Segment {
    public let startMs: Int
    public let endMs: Int

    public init(startMs: Int, endMs: Int) {
        self.startMs = startMs
        self.endMs = endMs
    }
}

public struct SegmentedAudio {
    public let audio: AudioPCM
    public let segments: [Segment]

    public init(audio: AudioPCM, segments: [Segment]) {
        self.audio = audio
        self.segments = segments
    }
}

public protocol AudioCaptureService {
    func startCapture()
    func stopCapture() -> AudioPCM
    func setPreRollMs(_ ms: Int)
}

public protocol VADSegmenter {
    func segment(audio: AudioPCM) -> SegmentedAudio
}

public protocol STTEngine {
    func transcribe(audio: AudioPCM) -> Transcript
}

public protocol TTSEngine {
    func synthesize(text: String) -> AsyncStream<AudioPCM>
    func stop()
}

public protocol DirectSpeechEngine {
    func speak(text: String)
    func stop()
}

public enum DebugFlags {
    public static var audio: Bool = false
    public static var input: Bool = false
    public static var ptt: Bool = false
    public static var llm: Bool = false
}

public struct Response {
    public let text: String
    public let type: ResponseType

    public init(text: String, type: ResponseType) {
        self.text = text
        self.type = type
    }
}

public enum ResponseType {
    case success
    case clarification
    case failure
    case confirmation
}

public enum AcknowledgementMode {
    case none
    case earcon
    case text
}

public struct UXSettings {
    public let thinkingPauseMs: Int
    public let maxSilenceMs: Int
    public let acknowledgementMode: AcknowledgementMode
    public let acknowledgementText: String
    public let earconHz: Double
    public let earconMs: Int
    public let earconAmplitude: Double

    public init(thinkingPauseMs: Int = 150, maxSilenceMs: Int = 300, acknowledgementMode: AcknowledgementMode = .earcon, acknowledgementText: String = "Acknowledged.", earconHz: Double = 880.0, earconMs: Int = 120, earconAmplitude: Double = 0.2) {
        self.thinkingPauseMs = thinkingPauseMs
        self.maxSilenceMs = maxSilenceMs
        self.acknowledgementMode = acknowledgementMode
        self.acknowledgementText = acknowledgementText
        self.earconHz = earconHz
        self.earconMs = earconMs
        self.earconAmplitude = earconAmplitude
    }
}

public struct FailureInjection {
    public let forceFailure: Bool
    public let failureRate: Double
    public let forceConfidence: Double?
    public let noiseOnlyInput: Bool

    public init(forceFailure: Bool = false, failureRate: Double = 0.0, forceConfidence: Double? = nil, noiseOnlyInput: Bool = false) {
        self.forceFailure = forceFailure
        self.failureRate = failureRate
        self.forceConfidence = forceConfidence
        self.noiseOnlyInput = noiseOnlyInput
    }
}

public protocol Responder {
    func respond(to transcript: Transcript) -> Response
}

public protocol PersonaFilter {
    func apply(to response: Response) -> String
}

public protocol LocalLLMEngine {
    func complete(prompt: String) -> String
}

public protocol AudioPlayer {
    func play(stream: AsyncStream<AudioPCM>)
    func stop()
}

public protocol InputController {
    func start(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> Bool
    func stop()
}
