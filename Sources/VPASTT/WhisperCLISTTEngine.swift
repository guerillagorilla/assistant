import Foundation
import VPACore
import VPAConfig

public final class WhisperCLISTTEngine: STTEngine {
    private let cliPath: String
    private let modelPath: String
    private let language: String?
    private let threads: Int?
    private let persistAudio: Bool
    private let beamSize: Int?
    private let bestOf: Int?
    private let temperature: Double?

    public init(config: VPAConfig.Whisper, persistAudio: Bool = false) {
        self.cliPath = config.cliPath
        self.modelPath = config.modelPath
        self.language = config.language
        self.threads = config.threads
        self.persistAudio = persistAudio
        self.beamSize = config.beamSize
        self.bestOf = config.bestOf
        self.temperature = config.temperature
    }

    public func transcribe(audio: AudioPCM) -> Transcript {
        guard !audio.samples.isEmpty else {
            return Transcript(text: "", confidence: 0.0)
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let wavURL = tempDir.appendingPathComponent("vpa_\(UUID().uuidString).wav")

        do {
            try WAVWriter.writePCM16Mono(audio: audio, to: wavURL)
        } catch {
            return Transcript(text: "", confidence: 0.0)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)

        var args: [String] = [
            "-m", modelPath,
            "-f", wavURL.path
        ]
        if let language, !language.isEmpty {
            args.append(contentsOf: ["-l", language])
        }
        if let threads, threads > 0 {
            args.append(contentsOf: ["-t", String(threads)])
        }
        if let beamSize, beamSize > 0 {
            args.append(contentsOf: ["--beam-size", String(beamSize)])
        }
        if let bestOf, bestOf > 0 {
            args.append(contentsOf: ["--best-of", String(bestOf)])
        }
        if let temperature {
            args.append(contentsOf: ["--temperature", String(temperature)])
        }
        let env = ProcessInfo.processInfo.environment
        if env["VPA_STT_NO_GPU"] == "1" {
            args.append("-ng")
        }
        if env["VPA_STT_NO_FLASH_ATTN"] == "1" {
            args.append("-nfa")
        }
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return Transcript(text: "", confidence: 0.0)
        }

        process.waitUntilExit()

        let text = parseStdout(pipe: stdout)

        if persistAudio {
            if DebugFlags.audio { print("vpa stt: kept wav at \(wavURL.path)") }
        } else {
            cleanup(urls: [wavURL])
        }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationSec = Double(audio.samples.count) / Double(audio.sampleRate)
        if DebugFlags.audio { print(String(format: "vpa stt: audio duration %.2fs", durationSec)) }
        return Transcript(text: cleaned, confidence: cleaned.isEmpty ? 0.0 : 0.7)
    }

    private func parseStdout(pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8) else { return "" }
        let lines = raw.split(separator: "\n")
        var parts: [String] = []
        for line in lines {
            if let bracketIndex = line.firstIndex(of: "]") {
                let after = line[line.index(after: bracketIndex)...]
                let trimmed = after.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { parts.append(trimmed) }
            }
        }
        if parts.isEmpty {
            return raw
        }
        return parts.joined(separator: " ")
    }

    private func cleanup(urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private enum WAVWriter {
    static func writePCM16Mono(audio: AudioPCM, to url: URL) throws {
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
    }
}
