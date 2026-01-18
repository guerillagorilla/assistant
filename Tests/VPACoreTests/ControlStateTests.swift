import XCTest
import VPACore

final class ControlStateTests: XCTestCase {
    func testPTTBoundariesInvokeSTTOnce() {
        let audio = makePCM(samples: samples(value: 2000, count: 100))
        let capture = TestAudioCaptureService(nextAudio: audio)
        let vad = TestVADSegmenter()
        let stt = TestSTTEngine()
        let responder = TestResponder()
        let persona = TestPersonaFilter()
        let tts = TestTTSEngine()
        let player = TestAudioPlayer()
        let metrics = TestMetricsSink()
        let stateMachine = AssistantStateMachine()

        let assistant = AssistantController(
            stateMachine: stateMachine,
            audioCapture: capture,
            vad: vad,
            stt: stt,
            responder: responder,
            persona: persona,
            tts: tts,
            player: player,
            metrics: metrics
        )

        assistant.onPTTPressed()
        assistant.onPTTReleased()

        let expectation = XCTestExpectation(description: "async pipeline finished")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.stopCount, 1)
        XCTAssertEqual(stt.callCount, 1)
        XCTAssertEqual(responder.callCount, 1)
        XCTAssertEqual(player.playCount, 1)
        XCTAssertEqual(metrics.latencyCount, 1)
    }

    func testBargeInStopsPlaybackAndReturnsToListening() {
        let audio = makePCM(samples: samples(value: 2000, count: 100))
        let capture = TestAudioCaptureService(nextAudio: audio)
        let vad = TestVADSegmenter()
        let stt = TestSTTEngine()
        let responder = TestResponder()
        let persona = TestPersonaFilter()
        let tts = TestTTSEngine()
        let player = TestAudioPlayer()
        let metrics = TestMetricsSink()
        let stateMachine = AssistantStateMachine()
        stateMachine.transition(to: .speaking)

        let assistant = AssistantController(
            stateMachine: stateMachine,
            audioCapture: capture,
            vad: vad,
            stt: stt,
            responder: responder,
            persona: persona,
            tts: tts,
            player: player,
            metrics: metrics
        )

        assistant.onPTTPressed()

        XCTAssertEqual(tts.stopCount, 1)
        XCTAssertEqual(player.stopCount, 1)
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(stateMachine.state, .listening)
    }
}
