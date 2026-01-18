import Foundation
import VPACore

public final class SimpleVADSegmenter: VADSegmenter {
    private let sampleRate: Int
    private let silenceMsThreshold: Int
    private let minSpeechMs: Int
    private let energyThreshold: Double

    private let removeInternalSilence: Bool

    public init(sampleRate: Int, silenceMsThreshold: Int, minSpeechMs: Int, energyThreshold: Double = 0.015, removeInternalSilence: Bool = false) {
        self.sampleRate = sampleRate
        self.silenceMsThreshold = silenceMsThreshold
        self.minSpeechMs = minSpeechMs
        self.energyThreshold = energyThreshold
        self.removeInternalSilence = removeInternalSilence
    }

    public func segment(audio: AudioPCM) -> SegmentedAudio {
        guard !audio.samples.isEmpty else {
            return SegmentedAudio(audio: audio, segments: [])
        }

        let frameMs = 20
        let frameSize = max(1, (sampleRate * frameMs) / 1000)
        let totalFrames = audio.samples.count / frameSize
        if totalFrames == 0 {
            return SegmentedAudio(audio: audio, segments: [])
        }

        var speechFrames: [Bool] = Array(repeating: false, count: totalFrames)
        for i in 0..<totalFrames {
            let start = i * frameSize
            let end = min(start + frameSize, audio.samples.count)
            var sum: Double = 0
            for j in start..<end {
                sum += Double(abs(Int(audio.samples[j])))
            }
            let avg = sum / Double(end - start)
            let norm = avg / 32768.0
            if norm >= energyThreshold {
                speechFrames[i] = true
            }
        }

        var firstSpeech: Int? = nil
        var lastSpeech: Int? = nil
        for i in 0..<totalFrames {
            if speechFrames[i] {
                if firstSpeech == nil { firstSpeech = i }
                lastSpeech = i
            }
        }

        guard let first = firstSpeech, let last = lastSpeech else {
            return SegmentedAudio(audio: AudioPCM(sampleRate: sampleRate, channels: 1, samples: []), segments: [])
        }

        let silenceFrames = (silenceMsThreshold + frameMs - 1) / frameMs
        let startFrame = max(0, first - silenceFrames)
        let endFrame = min(totalFrames - 1, last + silenceFrames)

        let startSample = startFrame * frameSize
        let endSample = min((endFrame + 1) * frameSize, audio.samples.count)
        let trimmed = Array(audio.samples[startSample..<endSample])

        let speechMs = (endSample - startSample) * 1000 / sampleRate
        if speechMs < minSpeechMs {
            return SegmentedAudio(audio: AudioPCM(sampleRate: sampleRate, channels: 1, samples: []), segments: [])
        }

        let segment = Segment(startMs: startSample * 1000 / sampleRate, endMs: endSample * 1000 / sampleRate)
        if !removeInternalSilence {
            return SegmentedAudio(audio: AudioPCM(sampleRate: sampleRate, channels: 1, samples: trimmed), segments: [segment])
        }

        let internalSamples = removeSilenceWithin(audio: trimmed, frameSize: frameSize)
        return SegmentedAudio(audio: AudioPCM(sampleRate: sampleRate, channels: 1, samples: internalSamples), segments: [segment])
    }

    private func removeSilenceWithin(audio: [Int16], frameSize: Int) -> [Int16] {
        if audio.isEmpty { return audio }
        let totalFrames = audio.count / frameSize
        if totalFrames == 0 { return audio }

        var keepFrames: [Bool] = Array(repeating: false, count: totalFrames)
        for i in 0..<totalFrames {
            let start = i * frameSize
            let end = min(start + frameSize, audio.count)
            var sum: Double = 0
            for j in start..<end {
                sum += Double(abs(Int(audio[j])))
            }
            let avg = sum / Double(end - start)
            let norm = avg / 32768.0
            if norm >= energyThreshold {
                keepFrames[i] = true
            }
        }

        var out: [Int16] = []
        out.reserveCapacity(audio.count)
        for i in 0..<totalFrames {
            guard keepFrames[i] else { continue }
            let start = i * frameSize
            let end = min(start + frameSize, audio.count)
            out.append(contentsOf: audio[start..<end])
        }
        return out
    }
}
