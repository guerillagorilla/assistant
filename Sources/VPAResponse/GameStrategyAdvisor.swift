import Foundation
import VPACore

public struct StrategyAdvice {
    public let vetoIds: [Int]
    public let priorityAdjustments: [String: Double]
    public let flags: [String]
    public let rationale: String

    public init(vetoIds: [Int], priorityAdjustments: [String: Double], flags: [String], rationale: String) {
        self.vetoIds = vetoIds
        self.priorityAdjustments = priorityAdjustments
        self.flags = flags
        self.rationale = rationale
    }

    public func payload() -> [String: Any] {
        return [
            "vetoIds": vetoIds,
            "priorityAdjustments": priorityAdjustments,
            "flags": flags,
            "rationale": rationale
        ]
    }

    public func summary() -> String {
        if !rationale.isEmpty { return rationale }
        if !flags.isEmpty { return flags.joined(separator: ", ") }
        if !vetoIds.isEmpty { return "avoiding \(vetoIds.count) risky options" }
        return "no specific guidance"
    }
}

public final class GameStrategyAdvisor {
    private let engine: LocalLLMEngine
    private let rulesQueue = DispatchQueue(label: "vpa.llm.rules.strategy")
    private var rulesText: String?

    public init(engine: LocalLLMEngine) {
        self.engine = engine
    }

    public func setRules(_ rules: String?) {
        rulesQueue.sync {
            self.rulesText = rules
        }
    }

    public func advise(state: [String: Any], candidates: [[String: Any]]?) -> StrategyAdvice? {
        let rules = rulesSnapshot()
        let prompt = buildPrompt(state: state, candidates: candidates ?? [], rules: rules)
        let output = engine.complete(prompt: prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        if DebugFlags.llm {
            let preview = output.count > 500 ? String(output.prefix(500)) + "…" : output
            print("vpa llm: strategy output: \(preview)")
        }
        return parseAdvice(output)
    }

    private func rulesSnapshot() -> String {
        let snapshot = rulesQueue.sync { rulesText }
        guard let snapshot, !snapshot.isEmpty else { return "" }
        if snapshot.count > 3000 {
            return String(snapshot.prefix(3000))
        }
        return snapshot
    }

    private func buildPrompt(state: [String: Any], candidates: [[String: Any]], rules: String) -> String {
        let round = state["round_number"] ?? state["roundNumber"] ?? ""
        let req = state["requirements"] ?? ""
        let hand = state["hand"] ?? []
        let discardTop = state["discard_top"] ?? state["discardTop"] ?? ""
        let deckCount = state["deck_count"] ?? state["deckCount"] ?? ""
        let hasLaid = state["has_laid_down"] ?? state["hasLaidDown"] ?? false
        let melds = state["melds"] ?? []
        let opponents = state["opponents"] ?? []
        let prompt = """
You are a strategy advisor for Chinese Rummy. You must NEVER choose a move, card, draw source, or discard.
You may only advise the engine using vetoes, priorities, flags, and rationale.

CURRENT STATE:
- Round \(round)/7
- Requirement: \(req)
- Your hand: \(hand)
- Discard pile top: \(discardTop)
- Cards in deck: \(deckCount)
- You have\( (String(describing: hasLaid)) == "true" ? "" : " NOT") laid down yet
- Your melds: \(melds)
- Opponents: \(opponents)

CANDIDATE_MOVES (engine-generated, do not alter):
\(candidates)

RULES_JSON:
\(rules)

Return JSON only with EXACT keys:
{"vetoIds":[Int], "priorityAdjustments":{"candidateId":-1.0}, "flags":["string"], "rationale":"string"}

Do not include any move choice or card selection.
"""
        return prompt
    }

    private func parseAdvice(_ output: String) -> StrategyAdvice? {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}") else { return nil }
        let jsonText = String(output[start...end])
        guard let data = jsonText.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let allowed = Set(["vetoIds", "priorityAdjustments", "flags", "rationale"])
        for key in obj.keys where !allowed.contains(key) {
            return nil
        }
        let vetoIds = obj["vetoIds"] as? [Int] ?? []
        var adjustments: [String: Double] = [:]
        if let raw = obj["priorityAdjustments"] as? [String: Any] {
            for (key, value) in raw {
                if let num = value as? Double {
                    adjustments[key] = num
                } else if let num = value as? Int {
                    adjustments[key] = Double(num)
                }
            }
        }
        let flags = obj["flags"] as? [String] ?? []
        let rationale = obj["rationale"] as? String ?? ""
        return StrategyAdvice(vetoIds: vetoIds, priorityAdjustments: adjustments, flags: flags, rationale: rationale)
    }
}
