import Foundation
import VPACore
import VPABot

public final class EchoResponder: Responder {
    public init() {}

    public func respond(to transcript: Transcript) -> Response {
        if transcript.text.isEmpty || transcript.confidence < 0.5 {
            return Response(text: "That was... not useful audio. Try again.", type: .failure)
        }
        return Response(text: "Heard: \(transcript.text)", type: .success)
    }
}

public final class IntentResponder: Responder {
    private let minConfidence: Double
    private let commandConfidence: Double
    private let llmResponder: LocalLLMResponder?
    private let botClient: BotClient?
    private let botSeat: Int

    public init(minConfidence: Double = 0.5, commandConfidence: Double = 0.75, llmResponder: LocalLLMResponder? = nil, botClient: BotClient? = nil, botSeat: Int = 1) {
        self.minConfidence = minConfidence
        self.commandConfidence = commandConfidence
        self.llmResponder = llmResponder
        self.botClient = botClient
        self.botSeat = botSeat
    }

    public func respond(to transcript: Transcript) -> Response {
        let raw = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || transcript.confidence < minConfidence {
            return Response(text: "That was... not useful audio. Try again.", type: .failure)
        }

        let normalized = normalize(raw)
        let intent = classifyIntent(raw: raw, normalized: normalized)
        if let llmResponder, let llmIntent = llmIntent(for: intent), llmResponder.isAllowed(intent: llmIntent) {
            let llmText = llmResponder.respond(intent: llmIntent, transcript: transcript)
            if !llmText.isEmpty {
                return Response(text: llmText, type: .success)
            }
        }
        return deterministicResponse(intent: intent, raw: raw, confidence: transcript.confidence)
    }

    private func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let cleaned = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == " " { return ch }
            return " "
        }
        return String(cleaned)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func isQuestion(_ raw: String, normalized: String) -> Bool {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") {
            return true
        }
        let prefixes = [
            "who", "what", "where", "when", "why", "how",
            "is", "are", "am", "was", "were", "do", "does", "did",
            "can", "could", "would", "should", "will", "have", "has", "had"
        ]
        for p in prefixes {
            if normalized.hasPrefix(p + " ") { return true }
        }
        if normalized.hasPrefix("whats ") || normalized.hasPrefix("what s ") {
            return true
        }
        return false
    }

    private func isCommand(_ normalized: String) -> Bool {
        if normalized.hasPrefix("please ") { return true }
        let verbs = [
            "open", "close", "start", "stop", "restart", "quit", "launch",
            "turn on", "turn off", "enable", "disable", "set", "increase",
            "decrease", "mute", "unmute", "record", "save", "delete",
            "create", "remove"
        ]
        for v in verbs {
            if normalized == v || normalized.hasPrefix(v + " ") {
                return true
            }
        }
        return false
    }

    private func isGreeting(_ normalized: String) -> Bool {
        let greetings = [
            "hi", "hello", "hey", "morning", "good morning",
            "good afternoon", "good evening", "yo"
        ]
        for g in greetings {
            if normalized == g || normalized.hasPrefix(g + " ") {
                return true
            }
        }
        return false
    }

    private enum Intent {
        case command
        case joinGame(String)
        case joinGameMissing
        case createGame(String)
        case createGameMissing
        case confirm
        case cancel
        case questionTime
        case questionCapabilities
        case questionOther
        case greeting
        case declarativeFile
        case declarativeSystem
        case declarative
    }

    private func classifyIntent(raw: String, normalized: String) -> Intent {
        if isConfirm(normalized) { return .confirm }
        if isCancel(normalized) { return .cancel }
        let create = parseCreateRoom(normalized: normalized, raw: raw)
        if create.matched {
            if let room = create.room {
                return .createGame(room)
            }
            return .createGameMissing
        }
        let join = parseJoinGame(normalized: normalized, raw: raw)
        if join.matched {
            if let room = join.room {
                return .joinGame(room)
            }
            return .joinGameMissing
        }
        if isCommand(normalized) { return .command }
        if isGreeting(normalized) { return .greeting }
        if isQuestion(raw, normalized: normalized) {
            if isTimeQuestion(normalized) { return .questionTime }
            if isCapabilitiesQuestion(normalized) { return .questionCapabilities }
            return .questionOther
        }
        switch reflectionKind(normalized) {
        case .file:
            return .declarativeFile
        case .system:
            return .declarativeSystem
        case .abstract:
            return .declarative
        }
    }

    private func deterministicResponse(intent: Intent, raw: String, confidence: Double) -> Response {
        switch intent {
        case .command:
            let prefix = confidence < commandConfidence ? "I think you said: " : ""
            return Response(text: "\(prefix)\(raw). Confirm or cancel.", type: .confirmation)
        case .joinGame(let room):
            if DebugFlags.input {
                print("vpa bot: join room=\(room)")
            }
            botClient?.join(room: room, seat: botSeat)
            botClient?.fetchRules()
            return Response(text: "Joining room \(room). Try not to embarrass me.", type: .success)
        case .joinGameMissing:
            return Response(text: "Room code missing. Say two four-letter words.", type: .clarification)
        case .createGame(let room):
            botClient?.createRoom(room: room)
            botClient?.fetchRules()
            return Response(text: "Creating room \(room). Try not to fumble.", type: .success)
        case .createGameMissing:
            return Response(text: "Room code missing. Say two four-letter words.", type: .clarification)
        case .confirm:
            return Response(text: "Confirmed.", type: .success)
        case .cancel:
            return Response(text: "Cancelled.", type: .success)
        case .questionTime, .questionCapabilities, .questionOther:
            return Response(text: "That’s a question. I’m not wired for answers yet.", type: .success)
        case .greeting:
            return Response(text: "Acknowledged.", type: .success)
        case .declarativeFile:
            return Response(text: "Noted: file operations.", type: .success)
        case .declarativeSystem:
            return Response(text: "Understood. No action taken.", type: .success)
        case .declarative:
            return Response(text: "I heard that. Standing by.", type: .success)
        }
    }

    private func llmIntent(for intent: Intent) -> LLMIntent? {
        switch intent {
        case .greeting:
            return .greeting
        case .questionTime:
            return .questionTime
        case .questionCapabilities:
            return .questionCapabilities
        default:
            return nil
        }
    }

    private func isDeterministicOnly(intent: Intent) -> Bool {
        switch intent {
        case .command, .confirm, .cancel, .joinGame, .joinGameMissing, .createGame, .createGameMissing:
            return true
        default:
            return false
        }
    }

    private enum ReflectionKind {
        case file
        case system
        case abstract
    }

    private func reflectionKind(_ normalized: String) -> ReflectionKind {
        let fileHints = [
            "file", "files", "folder", "folders", "directory", "path",
            "move", "moved", "copy", "copied", "rename", "renamed",
            "delete", "deleted", "save", "saved", "download", "uploaded",
            "open", "close", "read", "write"
        ]
        for hint in fileHints {
            if normalized.contains(hint) {
                return .file
            }
        }
        let systemHints = [
            "cpu", "memory", "ram", "disk", "storage", "network",
            "wifi", "bluetooth", "battery", "volume", "sound",
            "process", "service", "daemon", "system", "update",
            "restart", "shutdown", "boot", "login", "logout"
        ]
        for hint in systemHints {
            if normalized.contains(hint) {
                return .system
            }
        }
        return .abstract
    }

    private func isConfirm(_ normalized: String) -> Bool {
        let confirms = ["confirm", "confirmed", "yes", "yep", "do it", "proceed", "ok", "okay"]
        for c in confirms {
            if normalized == c { return true }
        }
        return false
    }

    private func isCancel(_ normalized: String) -> Bool {
        let cancels = ["cancel", "cancel that", "nevermind", "never mind", "stop", "abort"]
        for c in cancels {
            if normalized == c { return true }
        }
        return false
    }

    private func isTimeQuestion(_ normalized: String) -> Bool {
        if normalized.contains("what time") { return true }
        if normalized.contains("time is it") { return true }
        if normalized.contains("tell me the time") { return true }
        if normalized == "time" { return true }
        return false
    }

    private func isCapabilitiesQuestion(_ normalized: String) -> Bool {
        if normalized.contains("what can you do") { return true }
        if normalized.contains("what are you") { return true }
        if normalized.contains("help") { return true }
        if normalized.contains("capabilities") { return true }
        if normalized.contains("what can i say") { return true }
        return false
    }

    private func parseJoinGame(normalized: String, raw: String) -> (matched: Bool, room: String?) {
        let joinHints = [
            "lets play a game", "let's play a game", "join game", "join room", "connect to game",
            "play a game", "join the game", "start game", "start room"
        ]
        var matches = false
        for hint in joinHints {
            if normalized.contains(hint) { matches = true; break }
        }
        if !matches { return (false, nil) }
        if let room = extractRoomCode(from: raw) {
            return (true, room)
        }
        if normalized.contains("join game") || normalized.contains("join room") {
            return (true, "MINT WAVE")
        }
        return (true, nil)
    }

    private func parseCreateRoom(normalized: String, raw: String) -> (matched: Bool, room: String?) {
        let hints = ["create room", "create game", "new room", "make room"]
        var matched = false
        for h in hints {
            if normalized.contains(h) { matched = true; break }
        }
        if !matched { return (false, nil) }
        let room = extractRoomCode(from: raw)
        return (true, room)
    }

    private func extractRoomCode(from raw: String) -> String? {
        let parts = raw
            .map { ch -> Character in
                if ch.isLetter || ch.isNumber || ch == " " { return ch }
                return " "
            }
            .split(separator: " ")
        let stop = Set(["JOIN", "GAME", "PLAY", "ROOM", "LETS", "LET", "START", "CONNECT", "CREATE", "MAKE", "NEW"])
        var candidates: [String] = []
        for part in parts {
            let token = String(part).uppercased()
            if stop.contains(token) { continue }
            if stop.contains(where: { token.hasPrefix($0) }) { continue }
            if token.count == 4 {
                candidates.append(token)
            }
        }
        if candidates.count >= 2 {
            let lastTwo = candidates.suffix(2)
            return lastTwo.joined(separator: " ")
        }
        return nil
    }
}

public final class GLaDOSPersonaFilter: PersonaFilter {
    public init() {}

    public func apply(to response: Response) -> String {
        switch response.type {
        case .success:
            return response.text
        case .clarification:
            return response.text
        case .failure:
            return response.text
        case .confirmation:
            return response.text
        }
    }
}
