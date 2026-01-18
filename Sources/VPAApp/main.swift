import Foundation
import VPAConfig
import VPACore
import VPAAudio
import VPASTT
import VPATTS
import VPAResponse
import VPABot
import VPAInput
import AVFoundation
import AppKit

let stateMachine = AssistantStateMachine()
let persona = GLaDOSPersonaFilter()
let ttsEngine: TTSEngine
let player: AudioPlayer
let metrics: MetricsSink = RollingMetricsSink(reportEvery: 5)
var menuBarController: MenuBarController?

func loadConfig() -> VPAConfig? {
    let args = CommandLine.arguments
    if let index = args.firstIndex(of: "--config"), index + 1 < args.count {
        let path = args[index + 1]
        do {
            let url = URL(fileURLWithPath: path)
            return try ConfigLoader.load(from: url)
        } catch {
            fputs("Failed to load config at \(path): \(error)\n", stderr)
            exit(1)
        }
    }
    return nil
}

let config = loadConfig()
let captureOnly = CommandLine.arguments.contains("--capture-only")
let listVoices = CommandLine.arguments.contains("--list-voices")
let menuBar = !CommandLine.arguments.contains("--no-menubar")
let debugAudio = CommandLine.arguments.contains("--debug-audio")
let debugInput = CommandLine.arguments.contains("--debug-input")
let debugPTT = CommandLine.arguments.contains("--debug-ptt")
let debugLLM = CommandLine.arguments.contains("--debug-llm")
let persistAudioFlag = CommandLine.arguments.contains("--persist-audio")

DebugFlags.audio = debugAudio
DebugFlags.input = debugInput
DebugFlags.ptt = debugPTT
DebugFlags.llm = debugLLM

if listVoices {
    let voices = AVSpeechSynthesisVoice.speechVoices()
    for voice in voices {
        print("\(voice.identifier) | \(voice.name) | \(voice.language)")
    }
    exit(0)
}

let audioCapture: AudioCaptureService
if let config {
    let gainDb = config.audio.gainDb ?? 0.0
    audioCapture = AVAudioCaptureService(sampleRate: config.audio.sampleRate, preRollMs: config.audio.preRollMs, gainDb: gainDb)
    print("vpa: loaded config (sampleRate=\(config.audio.sampleRate), preRollMs=\(config.audio.preRollMs), gainDb=\(gainDb))")
} else {
    audioCapture = AVAudioCaptureService()
    print("vpa: no config provided; using defaults.")
}

let vad: VADSegmenter
if let config {
    let energy = config.vad.energyThreshold ?? 0.015
    let removeInternal = config.vad.removeInternalSilence ?? false
    vad = SimpleVADSegmenter(sampleRate: config.audio.sampleRate, silenceMsThreshold: config.vad.silenceMsThreshold, minSpeechMs: config.vad.minSpeechMs, energyThreshold: energy, removeInternalSilence: removeInternal)
    print("vpa: VAD=simple (energy=\(energy), removeInternal=\(removeInternal))")
} else {
    vad = StubVADSegmenter()
    print("vpa: VAD=stub")
}

let sttEngine: STTEngine
if captureOnly {
    sttEngine = StubSTTEngine()
    print("vpa: STT=stub (capture-only)")
} else if let config, config.stt.primary == "whisper-cli", let whisper = config.whisper {
    sttEngine = WhisperCLISTTEngine(config: whisper, persistAudio: config.logging.persistAudio)
    print("vpa: STT=whisper-cli")
} else {
    sttEngine = StubSTTEngine()
    print("vpa: STT=stub")
}

let llmEngine = makeLLMEngine(config: config)
let llmResponder = makeLLMResponder(config: config, engine: llmEngine)
let gamePlayer = llmEngine != nil ? GameLLMPlayer(engine: llmEngine!) : nil
var botClient: BotClient?
var pendingRulesAnnouncement: ((String) -> Void)?

if let config, config.tts.primary == "system" {
    if captureOnly {
        ttsEngine = StubTTSEngine()
        player = StubAudioPlayer()
        print("vpa: TTS=stub (capture-only)")
    } else {
        let voiceId = config.systemTTS?.voiceIdentifier
        let rate = config.systemTTS?.rate
        ttsEngine = SystemTTSEngine(voiceIdentifier: voiceId, rate: rate)
        player = StubAudioPlayer()
        print("vpa: TTS=system")
    }
} else if let config, config.tts.primary == "system-stream" {
    let voiceId = config.systemTTS?.voiceIdentifier
    let rate = config.systemTTS?.rate
    ttsEngine = AVSpeechStreamTTSEngine(voiceIdentifier: voiceId, rate: rate)
    player = VPAAudioPlayer()
    print("vpa: TTS=system-stream")
} else if let config, config.tts.primary == "piper-cli", let piper = config.piper {
    ttsEngine = PiperCLITTSEngine(config: piper)
    player = VPAAudioPlayer()
    print("vpa: TTS=piper-cli")
} else {
    ttsEngine = StubTTSEngine()
    player = StubAudioPlayer()
    print("vpa: TTS=stub")
}

pendingRulesAnnouncement = { rules in
    llmResponder?.setRules(rules)
    let announcement: Response
    if rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        announcement = Response(text: "Rules missing. Try again.", type: .clarification)
    } else {
        announcement = Response(text: "Rules loaded. I understand.", type: .success)
    }
    let personaText = persona.apply(to: announcement)
    if let direct = ttsEngine as? DirectSpeechEngine {
        direct.speak(text: personaText)
    } else {
        let stream = ttsEngine.synthesize(text: personaText)
        player.play(stream: stream)
    }
}

botClient = BotConnectorFactory.from(config: config, onRoomCreated: { room, seat in
    print("vpa bot: room created \(room) seat \(seat)")
}, onRules: { rules in
    pendingRulesAnnouncement?(rules)
    gamePlayer?.setRules(rules)
}, onYourTurn: { payload in
    guard let gamePlayer, let botClient else { return }
    let decision = gamePlayer.decideMove(from: payload)
    let draw = (decision?["draw"] as? String) ?? "deck"
    let meld = (decision?["meld"] as? Bool) ?? false
    let discard = (decision?["discard"] as? String) ?? ""
    if discard.isEmpty {
        return
    }
    let announce = "Drawing from \(draw). Discarding \(discard). Try to keep up."
    if let direct = ttsEngine as? DirectSpeechEngine {
        direct.speak(text: announce)
    } else {
        let stream = ttsEngine.synthesize(text: announce)
        player.play(stream: stream)
    }
    botClient.play(draw: draw, meld: meld, discard: discard)
})

let responder = IntentResponder(
    minConfidence: config?.responder?.minConfidence ?? 0.5,
    commandConfidence: config?.responder?.commandConfidence ?? 0.75,
    llmResponder: llmResponder,
    llmAll: config?.responder?.llmAll ?? false,
    botClient: botClient,
    botSeat: 1
)
let assistant = AssistantController(
    stateMachine: stateMachine,
    audioCapture: audioCapture,
    vad: vad,
    stt: sttEngine,
    responder: responder,
    persona: persona,
    tts: ttsEngine,
    player: player,
    metrics: metrics,
    ux: makeUXSettings(config: config),
    failureInjection: makeFailureInjection(config: config),
    onTranscript: { transcript in
        let conf = String(format: "%.2f", transcript.confidence)
        print("transcript: \"\(transcript.text)\" (conf=\(conf))")
    },
    onResponseText: { text in
        print("response: \"\(text)\"")
    },
    onAudioCaptured: { audio in
        guard captureOnly else { return }
        let shouldPersist = persistAudioFlag || (config?.logging.persistAudio ?? false)
        guard shouldPersist else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vpa_capture_\(UUID().uuidString).wav")
        if writeWav(audio: audio, to: url) {
            print("vpa capture-only: wav at \(url.path)")
        } else {
            print("vpa capture-only: failed to write wav")
        }
    }
)

let input = GlobeKeyInputController()
let started = input.start(
    onPress: { assistant.onPTTPressed() },
    onRelease: { assistant.onPTTReleased() }
)

print("vpa: ready (stub).")
if started {
    print("Hold the Globe/Fn key to talk. Release to send. Ctrl+C to quit.")
    if captureOnly {
        print("capture-only enabled: will write WAV and skip STT/TTS.")
    }
    if menuBar {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)
        let controller = MenuBarController()
        stateMachine.addObserver(controller)
        menuBarController = controller
        app.run()
    } else {
        RunLoop.main.run()
    }
} else {
    print("PTT hook failed; falling back to Enter key simulation.")
    print("Press Enter to simulate PTT press, Enter again to release. Ctrl+C to quit.")
    while true {
        _ = readLine()
        assistant.onPTTPressed()
        _ = readLine()
        assistant.onPTTReleased()
    }
}

private func makeFailureInjection(config: VPAConfig?) -> FailureInjection? {
    guard let debug = config?.debug else { return nil }
    let forceFailure = debug.forceSttFailure ?? false
    let failureRate = debug.sttFailureRate ?? 0.0
    let forceConfidence = debug.forceConfidence
    let noiseOnly = debug.noiseOnlyInput ?? false
    if !forceFailure && failureRate <= 0 && forceConfidence == nil && !noiseOnly {
        return nil
    }
    return FailureInjection(
        forceFailure: forceFailure,
        failureRate: failureRate,
        forceConfidence: forceConfidence,
        noiseOnlyInput: noiseOnly
    )
}

private func makeLLMEngine(config: VPAConfig?) -> LocalLLMEngine? {
    guard let llm = config?.llm else { return nil }
    let backend = llm.backend?.lowercased() ?? ""
    let engine: LocalLLMEngine
    if backend == "ollama-http" || backend == "ollama" || llm.cliPath.lowercased().contains("ollama") {
        engine = OllamaHTTPLocalLLMEngine(config: llm)
    } else {
        engine = LlamaCLILocalLLMEngine(config: llm)
    }
    let resolvedBackend = backend.isEmpty ? (llm.cliPath.lowercased().contains("ollama") ? "ollama-http" : "llama-cli") : backend
    let modelLabel = llm.modelName ?? llm.modelPath ?? "default"
    print("vpa llm: enabled (backend=\(resolvedBackend), model=\(modelLabel))")
    return engine
}

private func makeLLMResponder(config: VPAConfig?, engine: LocalLLMEngine?) -> LocalLLMResponder? {
    guard let engine else { return nil }
    let allowed: [LLMIntent] = [.greeting, .questionTime, .questionCapabilities]
    return LocalLLMResponder(engine: engine, allowedIntents: allowed)
}

private func writeWav(audio: AudioPCM, to url: URL) -> Bool {
    do {
        let sampleRate = UInt32(audio.sampleRate)
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = UInt32(audio.samples.count * MemoryLayout<Int16>.size)
        let riffChunkSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(contentsOf: withUnsafeBytes(of: riffChunkSize.littleEndian, Array.init))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        data.append(contentsOf: Array("data".utf8))
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        for sample in audio.samples {
            var s = sample.littleEndian
            withUnsafeBytes(of: &s) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        try data.write(to: url)
        return true
    } catch {
        return false
    }
}

private func makeUXSettings(config: VPAConfig?) -> UXSettings {
    guard let ux = config?.ux else { return UXSettings() }
    let mode: AcknowledgementMode
    switch ux.ackMode.lowercased() {
    case "none":
        mode = .none
    case "text":
        mode = .text
    default:
        mode = .earcon
    }
    return UXSettings(
        thinkingPauseMs: ux.thinkingPauseMs,
        maxSilenceMs: ux.maxSilenceMs,
        acknowledgementMode: mode,
        acknowledgementText: ux.ackText ?? "Acknowledged.",
        earconHz: ux.earconHz ?? 880.0,
        earconMs: ux.earconMs ?? 120,
        earconAmplitude: ux.earconAmplitude ?? 0.2
    )
}
