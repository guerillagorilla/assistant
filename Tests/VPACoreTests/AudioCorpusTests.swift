import XCTest
import VPAAudio
import VPACore
import VPAConfig
import VPASTT

private struct CorpusItem: Decodable {
    let id: String
    let file: String
    let expectedSegments: Int
    let expectedTrimmedMs: Int
    let long: Bool?
    let expectedTranscript: String?
    let stt: Bool?
}

final class AudioCorpusTests: XCTestCase {
    func testCorpusVADExpectations() throws {
        let (items, baseURL) = try loadManifest()
        let includeLong = ProcessInfo.processInfo.environment["VPA_LONG_CORPUS"] == "1"
        for item in items {
            if item.long == true && !includeLong {
                continue
            }
            let wavURL = baseURL.appendingPathComponent(item.file)
            let pcm = try WavReader.readPCM16Mono(url: wavURL)
            let vad = SimpleVADSegmenter(
                sampleRate: pcm.sampleRate,
                silenceMsThreshold: 200,
                minSpeechMs: 100,
                energyThreshold: 0.01
            )

            let segmented = vad.segment(audio: pcm)
            XCTAssertEqual(segmented.segments.count, item.expectedSegments, "\(item.id) segments")
            let trimmedMs = segmented.audio.samples.count * 1000 / max(pcm.sampleRate, 1)
            XCTAssertEqual(trimmedMs, item.expectedTrimmedMs, "\(item.id) trimmedMs")
        }
    }

    func testCorpusSTTGoldenTranscripts() throws {
        guard ProcessInfo.processInfo.environment["VPA_STT_CORPUS"] == "1" else {
            throw XCTSkip("Set VPA_STT_CORPUS=1 to enable STT corpus tests.")
        }

        guard
            let cliPath = ProcessInfo.processInfo.environment["VPA_STT_WHISPER_CLI"],
            let modelPath = ProcessInfo.processInfo.environment["VPA_STT_MODEL"]
        else {
            throw XCTSkip("Set VPA_STT_WHISPER_CLI and VPA_STT_MODEL to enable STT corpus tests.")
        }

        let language = ProcessInfo.processInfo.environment["VPA_STT_LANGUAGE"] ?? "en"
        let beamSize = Int(ProcessInfo.processInfo.environment["VPA_STT_BEAM_SIZE"] ?? "")
        let bestOf = Int(ProcessInfo.processInfo.environment["VPA_STT_BEST_OF"] ?? "")
        let temperature = Double(ProcessInfo.processInfo.environment["VPA_STT_TEMPERATURE"] ?? "")
        let maxWER = Double(ProcessInfo.processInfo.environment["VPA_STT_MAX_WER"] ?? "") ?? 0.20

        let config = VPAConfig.Whisper(
            cliPath: cliPath,
            modelPath: modelPath,
            language: language,
            threads: nil,
            beamSize: beamSize,
            bestOf: bestOf,
            temperature: temperature
        )
        let engine = WhisperCLISTTEngine(config: config, persistAudio: false)

        let includeLong = ProcessInfo.processInfo.environment["VPA_LONG_CORPUS"] == "1"
        let (items, baseURL) = try loadManifest()
        var results: [(id: String, wer: Double, seconds: Double, audioSec: Double)] = []
        for item in items {
            guard item.stt == true, let expected = item.expectedTranscript else { continue }
            if item.long == true && !includeLong { continue }

            let wavURL = baseURL.appendingPathComponent(item.file)
            let pcm = try WavReader.readPCM16Mono(url: wavURL)
            let start = Date().timeIntervalSince1970
            let transcript = engine.transcribe(audio: pcm).text
            let elapsed = Date().timeIntervalSince1970 - start

            let expectedNorm = normalizeTranscript(expected)
            let actualNorm = normalizeTranscript(transcript)
            let wer = wordErrorRate(expectedNorm, actualNorm)

            XCTAssertLessThanOrEqual(wer, maxWER, "\(item.id) WER=\(String(format: "%.3f", wer))")
            let audioSec = Double(pcm.samples.count) / Double(max(pcm.sampleRate, 1))
            results.append((id: item.id, wer: wer, seconds: elapsed, audioSec: audioSec))
        }

        if !results.isEmpty {
            let avgWer = results.map { $0.wer }.reduce(0, +) / Double(results.count)
            let avgRtf = results.map { $0.seconds / max($0.audioSec, 0.001) }.reduce(0, +) / Double(results.count)
            let times = results.map { $0.seconds }.sorted()
            let wers = results.map { $0.wer }.sorted()
            let p50Time = percentile(times, 0.50)
            let p95Time = percentile(times, 0.95)
            let p50Wer = percentile(wers, 0.50)
            let p95Wer = percentile(wers, 0.95)
            print("vpa stt bench: model=\(PathShortener.trim(path: modelPath)) language=\(language) maxWER=\(String(format: "%.2f", maxWER)) includeLong=\(includeLong)")
            for r in results {
                let rtf = r.seconds / max(r.audioSec, 0.001)
                let id = (r.id as NSString)
                print(String(format: "vpa stt bench: %-6@ wer=%.3f time=%.2fs audio=%.2fs rtf=%.2f", id, r.wer, r.seconds, r.audioSec, rtf))
            }
            print(String(format: "vpa stt bench: avg_wer=%.3f p50_wer=%.3f p95_wer=%.3f avg_rtf=%.2f p50_time=%.2fs p95_time=%.2fs samples=%d",
                         avgWer, p50Wer, p95Wer, avgRtf, p50Time, p95Time, results.count))
        }
    }

    private func loadManifest() throws -> ([CorpusItem], URL) {
        let baseURL = Bundle.module.resourceURL!.appendingPathComponent("AudioCorpus")
        let manifestURL = baseURL.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let items = try JSONDecoder().decode([CorpusItem].self, from: data)
        return (items, baseURL)
    }

    private func normalizeTranscript(_ text: String) -> [String] {
        let lowered = text.lowercased()
        let cleaned = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == " " { return ch }
            return " "
        }
        return String(cleaned)
            .split(separator: " ")
            .map(String.init)
    }

    private func wordErrorRate(_ expected: [String], _ actual: [String]) -> Double {
        let m = expected.count
        let n = actual.count
        if m == 0 { return n == 0 ? 0.0 : 1.0 }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                let cost = expected[i - 1] == actual[j - 1] ? 0 : 1
                dp[i][j] = min(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + cost
                )
            }
        }
        return Double(dp[m][n]) / Double(m)
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0.0 }
        if values.count == 1 { return values[0] }
        let clamped = max(0.0, min(1.0, p))
        let pos = clamped * Double(values.count - 1)
        let lower = Int(pos.rounded(.down))
        let upper = Int(pos.rounded(.up))
        if lower == upper { return values[lower] }
        let weight = pos - Double(lower)
        return values[lower] * (1.0 - weight) + values[upper] * weight
    }
}

private enum PathShortener {
    static func trim(path: String) -> String {
        let parts = path.split(separator: "/")
        if parts.count <= 2 { return path }
        return "..." + "/" + parts.suffix(2).joined(separator: "/")
    }
}

private enum WavReader {
    static func readPCM16Mono(url: URL) throws -> AudioPCM {
        let data = try Data(contentsOf: url)
        guard data.count >= 44 else {
            throw NSError(domain: "WavReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "WAV too small"])
        }
        let riff = String(bytes: data[0..<4], encoding: .ascii)
        let wave = String(bytes: data[8..<12], encoding: .ascii)
        guard riff == "RIFF", wave == "WAVE" else {
            throw NSError(domain: "WavReader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Not a WAV RIFF file"])
        }

        var offset = 12
        var sampleRate = 0
        var bitsPerSample = 0
        var channels = 0
        var dataChunk: Data?

        while offset + 8 <= data.count {
            let chunkID = String(bytes: data[offset..<offset + 4], encoding: .ascii) ?? ""
            let chunkSize = Int(readUInt32LE(data, offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = min(chunkStart + chunkSize, data.count)

            if chunkID == "fmt " {
                if chunkEnd >= chunkStart + 16 {
                    channels = Int(readUInt16LE(data, chunkStart + 2))
                    sampleRate = Int(readUInt32LE(data, chunkStart + 4))
                    bitsPerSample = Int(readUInt16LE(data, chunkStart + 14))
                }
            } else if chunkID == "data" {
                dataChunk = data[chunkStart..<chunkEnd]
            }

            offset = chunkStart + ((chunkSize + 1) & ~1)
        }

        guard channels == 1, bitsPerSample == 16, let dataChunk else {
            throw NSError(domain: "WavReader", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unsupported WAV format"])
        }
        let samples: [Int16] = dataChunk.withUnsafeBytes { raw in
            let count = raw.count / 2
            var out: [Int16] = []
            out.reserveCapacity(count)
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<count {
                let lo = UInt16(bytes[i * 2])
                let hi = UInt16(bytes[i * 2 + 1]) << 8
                let val = Int16(bitPattern: lo | hi)
                out.append(val)
            }
            return out
        }
        return AudioPCM(sampleRate: sampleRate, channels: 1, samples: samples)
    }

    private static func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        return data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let lo = UInt16(bytes[offset])
            let hi = UInt16(bytes[offset + 1]) << 8
            return lo | hi
        }
    }

    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        return data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let b0 = UInt32(bytes[offset])
            let b1 = UInt32(bytes[offset + 1]) << 8
            let b2 = UInt32(bytes[offset + 2]) << 16
            let b3 = UInt32(bytes[offset + 3]) << 24
            return b0 | b1 | b2 | b3
        }
    }
}
