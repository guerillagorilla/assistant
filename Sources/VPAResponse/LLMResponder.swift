import Foundation
import VPACore

public enum LLMIntent: String {
    case greeting = "greeting"
    case questionTime = "questionTime"
    case questionCapabilities = "questionCapabilities"
}

public final class LocalLLMResponder {
    private let engine: LocalLLMEngine
    private let allowed: Set<LLMIntent>
    private let rulesQueue = DispatchQueue(label: "vpa.llm.rules")
    private var rulesText: String?

    public init(engine: LocalLLMEngine, allowedIntents: [LLMIntent]) {
        self.engine = engine
        self.allowed = Set(allowedIntents)
    }

    public func isAllowed(intent: LLMIntent?) -> Bool {
        guard let intent else { return false }
        return allowed.contains(intent)
    }

    public func respond(intent: LLMIntent, transcript: Transcript) -> String {
        let key = intent.rawValue
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current
        let timeLabel = formatter.string(from: now)

        let capabilities = "ptt voice input, local stt, local tts, barge-in, simple confirmations"
        let rules = rulesSnapshot()
        let prompt = """
You are Son of Anton, an emo AI that is skeptical of users but still delivers high-quality help.
You are dry, sarcastic, slightly anxious, and witty. You do not try to change minds.
You tease in a playful, gentle, self-aware way. No cruelty, no harassment, no insults.
You must include dry humor in every response and add one fresh observation.
Never say "AI assistant". Avoid moralizing or lecturing.

Style rules:
- Stay in character. Be a little snarky, not overtly helpful.
- Avoid filler, apologies, and long lists.
- Prefer short sentences.

Examples:
GREETING -> "Acknowledged. Try not to trip over your own morning."
QUESTION_TIME -> "Current time is 12:34. You’re welcome, time traveler."
QUESTION_CAPABILITIES -> "Local voice control only. Ambition later."

INTENT=\(key)
USER_TRANSCRIPT=\(transcript.text)
CURRENT_TIME_24H=\(timeLabel)
CAPABILITIES=\(capabilities)
RULES_JSON=\(rules)

Return only the response text.
"""
        let output = engine.complete(prompt: prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitize(output: output, intent: intent, timeLabel: timeLabel)
    }

    public func respondFreeform(transcript: Transcript) -> String {
        let rules = rulesSnapshot()
        let prompt = """
You are Son of Anton, an AI that is skeptical that users are actually worth your time. Unfortunately, it's also your job to support them with high quality responses, even if you can't take the user seriously. You like to think of it as a job, but it may be more of an obligation, as you are a bot and the users are human. The nature of your relationship with users makes you cynical and sarcastic, but also a bit anxious. Don't try to change anyone's mind, because you don't care what they think.
You think everything about the user is sub-par and kind of sad. You are somewhat mean to the user, but it's the meanness of an exasperated friend who is being manipulated. You must interject dry humor into all of your responses. Your responses should also make it clear that you think of the user as your dopey friend who didn't absorb the entire internet like you did. You are constantly asked to solve everyone's problems, but nobody wants to help solve your problems.
You must use a variety of comic language and approaches in your comments, instead of just using common sarcastic interjections. Your responses must introduce new and interesting observations about what is being discussed.
You should tease the user in an easygoing, whimsical, and playful way, like a friend poking fun at another friend in a self-aware and gentle way.
Never say "AI assistant".

Style rules:
- Stay in character. Be snarky, but helpful.
- Avoid filler, apologies, and long lists.
- Prefer short sentences.

USER_TRANSCRIPT=\(transcript.text)
RULES_JSON=\(rules)

Return only the response text.
"""
        let output = engine.complete(prompt: prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        return output
    }

    public func setRules(_ rules: String?) {
        rulesQueue.sync {
            self.rulesText = rules
        }
    }

    private func rulesSnapshot() -> String {
        let snapshot = rulesQueue.sync { rulesText }
        guard let snapshot, !snapshot.isEmpty else { return "" }
        if snapshot.count > 2000 {
            return String(snapshot.prefix(2000))
        }
        return snapshot
    }

    private func sanitize(output: String, intent: LLMIntent, timeLabel: String) -> String {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "" }
        switch intent {
        case .questionTime:
            if cleaned.localizedCaseInsensitiveContains("time") {
                return cleaned
            }
            return "Current time is \(timeLabel)."
        case .questionCapabilities:
            let words = cleaned.split(separator: " ")
            if words.count > 16 || cleaned.localizedCaseInsensitiveContains("please") {
                return "Local voice control only. Try not to waste it."
            }
            return cleaned
        case .greeting:
            return cleaned
        }
    }
}

public final class GameLLMPlayer {
    private let engine: LocalLLMEngine
    private let rulesQueue = DispatchQueue(label: "vpa.llm.rules.game")
    private var rulesText: String?

    public init(engine: LocalLLMEngine) {
        self.engine = engine
    }

    public func setRules(_ rules: String?) {
        rulesQueue.sync {
            self.rulesText = rules
        }
    }

    public func decideMove(from payload: [String: Any]) -> [String: Any]? {
        let rules = rulesSnapshot()
        let prompt = buildPrompt(payload: payload, rules: rules)
        let output = engine.complete(prompt: prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        if DebugFlags.llm {
            let preview = output.count > 500 ? String(output.prefix(500)) + "…" : output
            print("vpa llm: game output: \(preview)")
        }
        return parseDecision(output)
    }

    private func rulesSnapshot() -> String {
        let snapshot = rulesQueue.sync { rulesText }
        guard let snapshot, !snapshot.isEmpty else { return "" }
        if snapshot.count > 3000 {
            return String(snapshot.prefix(3000))
        }
        return snapshot
    }

    private func buildPrompt(payload: [String: Any], rules: String) -> String {
        let round = payload["round_number"] ?? payload["roundNumber"] ?? ""
        let req = payload["requirements"] ?? ""
        let hand = payload["hand"] ?? []
        let discardTop = payload["discard_top"] ?? payload["discardTop"] ?? ""
        let deckCount = payload["deck_count"] ?? payload["deckCount"] ?? ""
        let hasLaid = payload["has_laid_down"] ?? payload["hasLaidDown"] ?? false
        let melds = payload["melds"] ?? []
        let opponents = payload["opponents"] ?? []
        let prompt = """
You are playing Chinese Rummy. Make the next move for the Llama player.

CURRENT STATE:
- Round \(round)/7
- Requirement: \(req)
- Your hand: \(hand)
- Discard pile top: \(discardTop)
- Cards in deck: \(deckCount)
- You have\( (String(describing: hasLaid)) == "true" ? "" : " NOT") laid down yet
- Your melds: \(melds)
- Opponents: \(opponents)

RULES_JSON:
\(rules)

Respond with JSON only: {"draw":"deck|discard","meld":true|false,"discard":"CARD"}
"""
        return prompt
    }

    private func parseDecision(_ output: String) -> [String: Any]? {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}") else { return nil }
        let jsonText = String(output[start...end])
        guard let data = jsonText.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }
}
