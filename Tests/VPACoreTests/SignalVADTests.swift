import XCTest
import VPAAudio
import VPACore

final class SignalVADTests: XCTestCase {
    func testTrailingSilenceTrim() {
        let sampleRate = 1000
        let speech = samples(value: 2000, count: 200) // 200ms
        let silence = samples(value: 0, count: 1000)  // 1000ms
        let audio = makePCM(sampleRate: sampleRate, samples: speech + silence)
        let vad = SimpleVADSegmenter(sampleRate: sampleRate, silenceMsThreshold: 200, minSpeechMs: 100, energyThreshold: 0.01)

        let segmented = vad.segment(audio: audio)

        XCTAssertEqual(segmented.audio.samples.count, 400)
        XCTAssertEqual(segmented.segments.count, 1)
        XCTAssertEqual(segmented.segments[0].endMs, 400)
    }

    func testLeadingSilenceTrimWithPadding() {
        let sampleRate = 1000
        let leading = samples(value: 0, count: 400)    // 400ms
        let speech = samples(value: 2000, count: 200)  // 200ms
        let audio = makePCM(sampleRate: sampleRate, samples: leading + speech)
        let vad = SimpleVADSegmenter(sampleRate: sampleRate, silenceMsThreshold: 200, minSpeechMs: 100, energyThreshold: 0.01)

        let segmented = vad.segment(audio: audio)

        XCTAssertEqual(segmented.audio.samples.count, 400)
        XCTAssertEqual(segmented.audio.samples.prefix(200).allSatisfy { $0 == 0 }, true)
    }

    func testSilenceOnlyReturnsEmpty() {
        let sampleRate = 1000
        let silence = samples(value: 0, count: 3000)
        let audio = makePCM(sampleRate: sampleRate, samples: silence)
        let vad = SimpleVADSegmenter(sampleRate: sampleRate, silenceMsThreshold: 200, minSpeechMs: 100, energyThreshold: 0.01)

        let segmented = vad.segment(audio: audio)

        XCTAssertEqual(segmented.audio.samples.count, 0)
        XCTAssertEqual(segmented.segments.count, 0)
    }
}
