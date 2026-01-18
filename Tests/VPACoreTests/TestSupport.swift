import Foundation
import VPACore
import VPABot

final class TestAudioCaptureService: AudioCaptureService {
    var nextAudio: AudioPCM
    var startCount = 0
    var stopCount = 0
    var lastPreRollMs: Int?

    init(nextAudio: AudioPCM) {
        self.nextAudio = nextAudio
    }

    func startCapture() {
        startCount += 1
    }

    func stopCapture() -> AudioPCM {
        stopCount += 1
        return nextAudio
    }

    func setPreRollMs(_ ms: Int) {
        lastPreRollMs = ms
    }
}

final class TestVADSegmenter: VADSegmenter {
    var lastAudio: AudioPCM?
    var segmented: SegmentedAudio?

    init(segmented: SegmentedAudio? = nil) {
        self.segmented = segmented
    }

    func segment(audio: AudioPCM) -> SegmentedAudio {
        lastAudio = audio
        if let segmented { return segmented }
        return SegmentedAudio(audio: audio, segments: [Segment(startMs: 0, endMs: audio.samples.count * 1000 / max(audio.sampleRate, 1))])
    }
}

final class TestSTTEngine: STTEngine {
    var lastAudio: AudioPCM?
    var callCount = 0
    var nextTranscript: Transcript

    init(nextTranscript: Transcript = Transcript(text: "ok", confidence: 0.9)) {
        self.nextTranscript = nextTranscript
    }

    func transcribe(audio: AudioPCM) -> Transcript {
        callCount += 1
        lastAudio = audio
        return nextTranscript
    }
}

final class TestResponder: Responder {
    var lastTranscript: Transcript?
    var callCount = 0
    var nextResponse: Response

    init(nextResponse: Response = Response(text: "ack", type: .success)) {
        self.nextResponse = nextResponse
    }

    func respond(to transcript: Transcript) -> Response {
        callCount += 1
        lastTranscript = transcript
        return nextResponse
    }
}

final class TestPersonaFilter: PersonaFilter {
    var lastResponse: Response?
    var callCount = 0
    var suffix: String = ""

    func apply(to response: Response) -> String {
        callCount += 1
        lastResponse = response
        return response.text + suffix
    }
}

final class TestTTSEngine: TTSEngine {
    var lastText: String?
    var callCount = 0
    var stopCount = 0

    func synthesize(text: String) -> AsyncStream<AudioPCM> {
        callCount += 1
        lastText = text
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    func stop() {
        stopCount += 1
    }
}

final class TestAudioPlayer: AudioPlayer {
    var playCount = 0
    var stopCount = 0

    func play(stream: AsyncStream<AudioPCM>) {
        playCount += 1
        _ = stream
    }

    func stop() {
        stopCount += 1
    }
}

final class TestLLMEngine: LocalLLMEngine {
    var lastPrompt: String?
    var callCount = 0
    var nextOutput: String

    init(nextOutput: String = "NONE") {
        self.nextOutput = nextOutput
    }

    func complete(prompt: String) -> String {
        callCount += 1
        lastPrompt = prompt
        return nextOutput
    }
}

final class TestBotClient: BotClient {
    var joins: [(room: String, seat: Int)] = []
    var creates: [String] = []
    var rulesFetchCount = 0

    func join(room: String, seat: Int) {
        joins.append((room: room, seat: seat))
    }

    func createRoom(room: String) {
        creates.append(room)
    }

    func fetchRules() {
        rulesFetchCount += 1
    }
}

final class TestMetricsSink: MetricsSink {
    var latencyCount = 0
    var errorCount = 0

    func record(latency: LatencyMetrics) {
        latencyCount += 1
        _ = latency
    }

    func record(error: String) {
        errorCount += 1
        _ = error
    }
}

func makePCM(sampleRate: Int = 1000, samples: [Int16]) -> AudioPCM {
    AudioPCM(sampleRate: sampleRate, channels: 1, samples: samples)
}

func samples(value: Int16, count: Int) -> [Int16] {
    Array(repeating: value, count: count)
}
