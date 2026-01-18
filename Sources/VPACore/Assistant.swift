import Foundation

public final class AssistantController {
    private let stateMachine: AssistantStateMachine
    private let audioCapture: AudioCaptureService
    private let vad: VADSegmenter
    private let stt: STTEngine
    private let responder: Responder
    private let persona: PersonaFilter
    private let tts: TTSEngine
    private let player: AudioPlayer
    private let metrics: MetricsSink
    private let ux: UXSettings
    private let failureInjection: FailureInjection?
    private let onTranscript: ((Transcript) -> Void)?
    private let onResponseText: ((String) -> Void)?
    private let onAudioCaptured: ((AudioPCM) -> Void)?
    private var cancelGeneration: Int = 0
    private var lastPressTs: TimeInterval?
    private let processingQueue = DispatchQueue(label: "vpa.assistant.processing")
    private var silenceGuard: DispatchSourceTimer?

    public init(
        stateMachine: AssistantStateMachine,
        audioCapture: AudioCaptureService,
        vad: VADSegmenter,
        stt: STTEngine,
        responder: Responder,
        persona: PersonaFilter,
        tts: TTSEngine,
        player: AudioPlayer,
        metrics: MetricsSink,
        ux: UXSettings = UXSettings(),
        failureInjection: FailureInjection? = nil,
        onTranscript: ((Transcript) -> Void)? = nil,
        onResponseText: ((String) -> Void)? = nil,
        onAudioCaptured: ((AudioPCM) -> Void)? = nil
    ) {
        self.stateMachine = stateMachine
        self.audioCapture = audioCapture
        self.vad = vad
        self.stt = stt
        self.responder = responder
        self.persona = persona
        self.tts = tts
        self.player = player
        self.metrics = metrics
        self.ux = ux
        self.failureInjection = failureInjection
        self.onTranscript = onTranscript
        self.onResponseText = onResponseText
        self.onAudioCaptured = onAudioCaptured
    }

    public func onPTTPressed() {
        let ts = Date().timeIntervalSince1970
        if DebugFlags.ptt { print(String(format: "vpa ptt: pressed at %.3f", ts)) }
        lastPressTs = ts
        cancelGeneration &+= 1
        cancelSilenceGuard()
        tts.stop()
        player.stop()
        if stateMachine.state == .speaking {
            stateMachine.transition(to: .interrupted)
        }
        stateMachine.transition(to: .listening)
        audioCapture.startCapture()
    }

    public func onPTTReleased() {
        let ts = Date().timeIntervalSince1970
        if DebugFlags.ptt { print(String(format: "vpa ptt: released at %.3f", ts)) }
        let generationAtStart = cancelGeneration
        stateMachine.transition(to: .processing)
        let audio = audioCapture.stopCapture()
        onAudioCaptured?(audio)
        let captureMs = lastPressTs != nil ? Int((ts - (lastPressTs ?? ts)) * 1000.0) : 0
        scheduleSilenceGuard(generation: generationAtStart)
        processingQueue.async { [weak self] in
            guard let self else { return }
            let sttStart = Date().timeIntervalSince1970
            let segmented = self.vad.segment(audio: audio)
            var sttAudio = segmented.audio
            if let injection = self.failureInjection, injection.noiseOnlyInput {
                sttAudio = self.makeNoiseLike(segmented.audio)
            }
            let forcedFailure = self.shouldForceFailure(injection: self.failureInjection)
            var transcript = forcedFailure ? Transcript(text: "", confidence: 0.0) : self.stt.transcribe(audio: sttAudio)
            if let forcedConfidence = self.failureInjection?.forceConfidence {
                transcript = Transcript(text: transcript.text, confidence: forcedConfidence, wordTimings: transcript.wordTimings)
            }
            let sttMs = Int((Date().timeIntervalSince1970 - sttStart) * 1000.0)
            self.onTranscript?(transcript)

            let responseStart = Date().timeIntervalSince1970
            let response = self.responder.respond(to: transcript)
            let personaText = self.persona.apply(to: response)
            let responseMs = Int((Date().timeIntervalSince1970 - responseStart) * 1000.0)
            self.onResponseText?(personaText)

            if self.cancelGeneration != generationAtStart {
                return
            }

            self.cancelSilenceGuard()
            if response.type != .failure {
                self.applyThinkingPause(releaseTs: ts)
            }

        let ttsStart = Date().timeIntervalSince1970
        if let direct = self.tts as? DirectSpeechEngine {
            self.stateMachine.transition(to: .speaking)
            direct.speak(text: personaText)
        } else {
            let stream = self.makeGuardedStream(base: self.tts.synthesize(text: personaText), generation: generationAtStart)
            self.stateMachine.transition(to: .speaking)
            self.player.play(stream: stream)
        }
            let ttsStartMs = Int((Date().timeIntervalSince1970 - ttsStart) * 1000.0)
            self.metrics.record(latency: LatencyMetrics(captureMs: captureMs, sttMs: sttMs, responseMs: responseMs, ttsStartMs: ttsStartMs))
            self.stateMachine.transition(to: .idle)
            _ = self.metrics
        }
    }

    private func scheduleSilenceGuard(generation: Int) {
        let maxSilence = ux.maxSilenceMs
        guard maxSilence > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now() + .milliseconds(maxSilence))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.cancelGeneration != generation { return }
            if self.stateMachine.state != .processing { return }
            self.emitAcknowledgement()
        }
        silenceGuard?.cancel()
        silenceGuard = timer
        timer.resume()
    }

    private func cancelSilenceGuard() {
        silenceGuard?.cancel()
        silenceGuard = nil
    }

    private func applyThinkingPause(releaseTs: TimeInterval) {
        let pauseMs = ux.thinkingPauseMs
        guard pauseMs > 0 else { return }
        let elapsedMs = Int((Date().timeIntervalSince1970 - releaseTs) * 1000.0)
        var sleepMs = pauseMs
        if ux.maxSilenceMs > 0 && elapsedMs >= ux.maxSilenceMs {
            sleepMs = 0
        } else if ux.maxSilenceMs > 0 && elapsedMs + pauseMs > ux.maxSilenceMs {
            sleepMs = max(0, ux.maxSilenceMs - elapsedMs)
        }
        if sleepMs > 0 {
            Thread.sleep(forTimeInterval: Double(sleepMs) / 1000.0)
        }
    }

    private func emitAcknowledgement() {
        switch ux.acknowledgementMode {
        case .none:
            return
        case .earcon:
            let tone = makeEarcon()
            let stream = AsyncStream<AudioPCM> { continuation in
                continuation.yield(tone)
                continuation.finish()
            }
            player.play(stream: stream)
        case .text:
            let text = ux.acknowledgementText
            if let direct = tts as? DirectSpeechEngine {
                direct.speak(text: text)
            } else {
                let stream = makeGuardedStream(base: tts.synthesize(text: text), generation: cancelGeneration)
                player.play(stream: stream)
            }
        }
    }

    private func makeEarcon() -> AudioPCM {
        let sampleRate = 16000
        let totalSamples = max(1, ux.earconMs * sampleRate / 1000)
        let amplitude = max(0.0, min(1.0, ux.earconAmplitude))
        let scale = Double(Int16.max) * amplitude
        var samples: [Int16] = []
        samples.reserveCapacity(totalSamples)
        let freq = ux.earconHz
        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let value = sin(2.0 * Double.pi * freq * t)
            let raw = Int(scale * value)
            let clamped = max(Int(Int16.min), min(Int(Int16.max), raw))
            let sample = Int16(clamped)
            samples.append(sample)
        }
        return AudioPCM(sampleRate: sampleRate, channels: 1, samples: samples)
    }

    private func shouldForceFailure(injection: FailureInjection?) -> Bool {
        guard let injection else { return false }
        if injection.forceFailure { return true }
        let rate = max(0.0, min(1.0, injection.failureRate))
        guard rate > 0 else { return false }
        return Double.random(in: 0.0...1.0) < rate
    }

    private func makeNoiseLike(_ audio: AudioPCM) -> AudioPCM {
        let count = audio.samples.count
        var samples: [Int16] = []
        samples.reserveCapacity(count)
        for _ in 0..<count {
            let value = Int16.random(in: Int16.min...Int16.max)
            samples.append(value)
        }
        return AudioPCM(sampleRate: audio.sampleRate, channels: audio.channels, samples: samples)
    }

    private func makeGuardedStream(base: AsyncStream<AudioPCM>, generation: Int) -> AsyncStream<AudioPCM> {
        return AsyncStream { continuation in
            Task {
                for await chunk in base {
                    if self.cancelGeneration != generation {
                        break
                    }
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }
}
