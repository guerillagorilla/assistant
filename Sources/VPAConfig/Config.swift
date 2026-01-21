import Foundation

public struct VPAConfig: Codable {
    public struct BackendChoice: Codable {
        public let primary: String
        public let fallback: String

        public init(primary: String, fallback: String) {
            self.primary = primary
            self.fallback = fallback
        }
    }

    public struct SystemTTS: Codable {
        public let voiceIdentifier: String?
        public let rate: Double?

        public init(voiceIdentifier: String? = nil, rate: Double? = nil) {
            self.voiceIdentifier = voiceIdentifier
            self.rate = rate
        }
    }

    public struct Piper: Codable {
        public let cliPath: String
        public let modelPath: String
        public let configPath: String?
        public let speakerId: Int?
        public let lengthScale: Double?
        public let noiseScale: Double?
        public let noiseW: Double?
        public let sentenceSilence: Double?
        public let phonemeSilence: Double?

        public init(cliPath: String, modelPath: String, configPath: String? = nil, speakerId: Int? = nil, lengthScale: Double? = nil, noiseScale: Double? = nil, noiseW: Double? = nil, sentenceSilence: Double? = nil, phonemeSilence: Double? = nil) {
            self.cliPath = cliPath
            self.modelPath = modelPath
            self.configPath = configPath
            self.speakerId = speakerId
            self.lengthScale = lengthScale
            self.noiseScale = noiseScale
            self.noiseW = noiseW
            self.sentenceSilence = sentenceSilence
            self.phonemeSilence = phonemeSilence
        }
    }

    public struct Whisper: Codable {
        public let cliPath: String
        public let modelPath: String
        public let language: String?
        public let threads: Int?
        public let beamSize: Int?
        public let bestOf: Int?
        public let temperature: Double?

        public init(cliPath: String, modelPath: String, language: String? = nil, threads: Int? = nil, beamSize: Int? = nil, bestOf: Int? = nil, temperature: Double? = nil) {
            self.cliPath = cliPath
            self.modelPath = modelPath
            self.language = language
            self.threads = threads
            self.beamSize = beamSize
            self.bestOf = bestOf
            self.temperature = temperature
        }
    }

    public struct Audio: Codable {
        public let sampleRate: Int
        public let preRollMs: Int
        public let gainDb: Double?

        public init(sampleRate: Int, preRollMs: Int, gainDb: Double? = nil) {
            self.sampleRate = sampleRate
            self.preRollMs = preRollMs
            self.gainDb = gainDb
        }
    }

    public struct VAD: Codable {
        public let silenceMsThreshold: Int
        public let minSpeechMs: Int
        public let energyThreshold: Double?
        public let removeInternalSilence: Bool?

        public init(silenceMsThreshold: Int, minSpeechMs: Int, energyThreshold: Double? = nil, removeInternalSilence: Bool? = nil) {
            self.silenceMsThreshold = silenceMsThreshold
            self.minSpeechMs = minSpeechMs
            self.energyThreshold = energyThreshold
            self.removeInternalSilence = removeInternalSilence
        }
    }

    public struct Persona: Codable {
        public let style: String

        public init(style: String) {
            self.style = style
        }
    }

    public struct ResponderConfig: Codable {
        public let minConfidence: Double?
        public let commandConfidence: Double?
        public let intentConfidenceThreshold: Double?
        public let strategyEnabled: Bool?
        public let explainMoves: Bool?
        public let voiceEnabled: Bool?

        public init(minConfidence: Double? = nil, commandConfidence: Double? = nil, intentConfidenceThreshold: Double? = nil, strategyEnabled: Bool? = nil, explainMoves: Bool? = nil, voiceEnabled: Bool? = nil) {
            self.minConfidence = minConfidence
            self.commandConfidence = commandConfidence
            self.intentConfidenceThreshold = intentConfidenceThreshold
            self.strategyEnabled = strategyEnabled
            self.explainMoves = explainMoves
            self.voiceEnabled = voiceEnabled
        }
    }

    public struct Logging: Codable {
        public let level: String
        public let persistAudio: Bool

        public init(level: String, persistAudio: Bool) {
            self.level = level
            self.persistAudio = persistAudio
        }
    }

    public struct Latency: Codable {
        public let maxMs: Int

        public init(maxMs: Int) {
            self.maxMs = maxMs
        }
    }

    public struct UX: Codable {
        public let thinkingPauseMs: Int
        public let maxSilenceMs: Int
        public let ackMode: String
        public let ackText: String?
        public let earconHz: Double?
        public let earconMs: Int?
        public let earconAmplitude: Double?

        public init(thinkingPauseMs: Int, maxSilenceMs: Int, ackMode: String, ackText: String? = nil, earconHz: Double? = nil, earconMs: Int? = nil, earconAmplitude: Double? = nil) {
            self.thinkingPauseMs = thinkingPauseMs
            self.maxSilenceMs = maxSilenceMs
            self.ackMode = ackMode
            self.ackText = ackText
            self.earconHz = earconHz
            self.earconMs = earconMs
            self.earconAmplitude = earconAmplitude
        }
    }

    public struct Debug: Codable {
        public let forceSttFailure: Bool?
        public let sttFailureRate: Double?
        public let forceConfidence: Double?
        public let noiseOnlyInput: Bool?

        public init(forceSttFailure: Bool? = nil, sttFailureRate: Double? = nil, forceConfidence: Double? = nil, noiseOnlyInput: Bool? = nil) {
            self.forceSttFailure = forceSttFailure
            self.sttFailureRate = sttFailureRate
            self.forceConfidence = forceConfidence
            self.noiseOnlyInput = noiseOnlyInput
        }
    }

    public struct LLM: Codable {
        public let backend: String?
        public let cliPath: String
        public let modelPath: String?
        public let modelName: String?
        public let apiURL: String?
        public let args: [String]?
        public let maxTokens: Int?
        public let temperature: Double?
        public let useStdin: Bool?

        public init(backend: String? = nil, cliPath: String, modelPath: String? = nil, modelName: String? = nil, apiURL: String? = nil, args: [String]? = nil, maxTokens: Int? = nil, temperature: Double? = nil, useStdin: Bool? = nil) {
            self.backend = backend
            self.cliPath = cliPath
            self.modelPath = modelPath
            self.modelName = modelName
            self.apiURL = apiURL
            self.args = args
            self.maxTokens = maxTokens
            self.temperature = temperature
            self.useStdin = useStdin
        }
    }

    public struct Bot: Codable {
        public let wsURL: String
        public let rulesURL: String?

        public init(wsURL: String, rulesURL: String? = nil) {
            self.wsURL = wsURL
            self.rulesURL = rulesURL
        }
    }

    public let stt: BackendChoice
    public let tts: BackendChoice
    public let audio: Audio
    public let vad: VAD
    public let persona: Persona
    public let responder: ResponderConfig?
    public let logging: Logging
    public let latency: Latency
    public let ux: UX?
    public let debug: Debug?
    public let llm: LLM?
    public let bot: Bot?
    public let whisper: Whisper?
    public let systemTTS: SystemTTS?
    public let piper: Piper?

    public init(stt: BackendChoice, tts: BackendChoice, audio: Audio, vad: VAD, persona: Persona, responder: ResponderConfig? = nil, logging: Logging, latency: Latency, ux: UX? = nil, debug: Debug? = nil, llm: LLM? = nil, bot: Bot? = nil, whisper: Whisper? = nil, systemTTS: SystemTTS? = nil, piper: Piper? = nil) {
        self.stt = stt
        self.tts = tts
        self.audio = audio
        self.vad = vad
        self.persona = persona
        self.responder = responder
        self.logging = logging
        self.latency = latency
        self.ux = ux
        self.debug = debug
        self.llm = llm
        self.bot = bot
        self.whisper = whisper
        self.systemTTS = systemTTS
        self.piper = piper
    }
}

public enum ConfigLoader {
    public static func load(from url: URL) throws -> VPAConfig {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(VPAConfig.self, from: data)
    }
}
