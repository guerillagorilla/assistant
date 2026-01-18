import XCTest
import VPACore
import VPAResponse

final class LLMPolicyRoutingTests: XCTestCase {
    func testGreetingRoutesToLLM() {
        let llm = TestLLMEngine(nextOutput: "Good morning.")
        let responder = makeResponder(llm: llm)
        let response = responder.respond(to: Transcript(text: "Good morning", confidence: 0.9))

        XCTAssertEqual(llm.callCount, 1)
        XCTAssertEqual(response.text, "Good morning.")
    }

    func testTimeQuestionRoutesToLLM() {
        let llm = TestLLMEngine(nextOutput: "It is 09:00.")
        let responder = makeResponder(llm: llm)
        let response = responder.respond(to: Transcript(text: "What time is it?", confidence: 0.9))

        XCTAssertEqual(llm.callCount, 1)
        XCTAssertEqual(response.text, "It is 09:00.")
    }

    func testCapabilitiesQuestionRoutesToLLM() {
        let llm = TestLLMEngine(nextOutput: "Local voice control only.")
        let responder = makeResponder(llm: llm)
        let response = responder.respond(to: Transcript(text: "What can you do?", confidence: 0.9))

        XCTAssertEqual(llm.callCount, 1)
        XCTAssertEqual(response.text, "Local voice control only.")
    }

    func testCommandsNeverRouteToLLM() {
        let llm = TestLLMEngine(nextOutput: "Open Safari.")
        let responder = makeResponder(llm: llm)
        let response = responder.respond(to: Transcript(text: "Open Safari", confidence: 0.9))

        XCTAssertEqual(llm.callCount, 0)
        XCTAssertEqual(response.type, .confirmation)
    }

    func testJoinGameCommandTriggersBotJoin() {
        let llm = TestLLMEngine(nextOutput: "Nope.")
        let bot = TestBotClient()
        let responder = makeResponder(llm: llm, bot: bot)
        let response = responder.respond(to: Transcript(text: "lets play a game ABCD WXYZ", confidence: 0.9))

        XCTAssertEqual(llm.callCount, 0)
        XCTAssertEqual(bot.joins.count, 1)
        XCTAssertEqual(bot.joins.first?.room, "ABCD WXYZ")
        XCTAssertEqual(bot.joins.first?.seat, 1)
        XCTAssertEqual(bot.rulesFetchCount, 1)
        XCTAssertEqual(response.type, .success)
    }

    func testCreateRoomCommandTriggersBotCreate() {
        let llm = TestLLMEngine(nextOutput: "Nope.")
        let bot = TestBotClient()
        let responder = makeResponder(llm: llm, bot: bot)
        let response = responder.respond(to: Transcript(text: "create room MOON STAR", confidence: 0.9))

        XCTAssertEqual(llm.callCount, 0)
        XCTAssertEqual(bot.creates.count, 1)
        XCTAssertEqual(bot.creates.first, "MOON STAR")
        XCTAssertEqual(bot.rulesFetchCount, 1)
        XCTAssertEqual(response.type, .success)
    }

    func testCreateRoomCommandMissingCodeClarifies() {
        let llm = TestLLMEngine(nextOutput: "Nope.")
        let bot = TestBotClient()
        let responder = makeResponder(llm: llm, bot: bot)
        let response = responder.respond(to: Transcript(text: "create room", confidence: 0.9))

        XCTAssertEqual(llm.callCount, 0)
        XCTAssertEqual(bot.creates.count, 0)
        XCTAssertEqual(bot.rulesFetchCount, 0)
        XCTAssertEqual(response.type, .clarification)
    }

    func testJoinGameWithoutCodeClarifies() {
        let llm = TestLLMEngine(nextOutput: "Nope.")
        let bot = TestBotClient()
        let responder = makeResponder(llm: llm, bot: bot)
        let response = responder.respond(to: Transcript(text: "play a game", confidence: 0.9))

        XCTAssertEqual(llm.callCount, 0)
        XCTAssertEqual(bot.joins.count, 0)
        XCTAssertEqual(response.type, .clarification)
    }

    func testLLMEmptyFallsBack() {
        let llm = TestLLMEngine(nextOutput: "")
        let responder = makeResponder(llm: llm)
        let response = responder.respond(to: Transcript(text: "Hello", confidence: 0.9))

        XCTAssertEqual(llm.callCount, 1)
        XCTAssertEqual(response.text, "Acknowledged.")
    }

    private func makeResponder(llm: TestLLMEngine, bot: TestBotClient? = nil) -> IntentResponder {
        let llmResponder = LocalLLMResponder(engine: llm, allowedIntents: [.greeting, .questionTime, .questionCapabilities])
        return IntentResponder(minConfidence: 0.5, commandConfidence: 0.75, llmResponder: llmResponder, botClient: bot, botSeat: 1)
    }
}
