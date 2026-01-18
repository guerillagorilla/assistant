import Foundation
import VPACore
import VPAConfig

public final class PiperCLITTSEngine: TTSEngine {
    private let cliPath: String
    private let modelPath: String
    private let configPath: String?
    private let speakerId: Int?
    private let lengthScale: Double?
    private let noiseScale: Double?
    private let noiseW: Double?
    private let sentenceSilence: Double?
    private let phonemeSilence: Double?
    private let sampleRate: Int
    private var currentProcess: Process?
    private let queue = DispatchQueue(label: "vpa.piper.tts")

    public init(config: VPAConfig.Piper) {
        self.cliPath = config.cliPath
        self.modelPath = config.modelPath
        self.configPath = config.configPath
        self.speakerId = config.speakerId
        self.lengthScale = config.lengthScale
        self.noiseScale = config.noiseScale
        self.noiseW = config.noiseW
        self.sentenceSilence = config.sentenceSilence
        self.phonemeSilence = config.phonemeSilence
        self.sampleRate = PiperCLITTSEngine.readSampleRate(configPath: config.configPath) ?? 22050
    }

    public func synthesize(text: String) -> AsyncStream<AudioPCM> {
        return AsyncStream { continuation in
            queue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.cliPath)

                var args: [String] = ["-m", self.modelPath, "--output-raw", "-f", "-"]
                if let configPath = self.configPath {
                    args.append(contentsOf: ["-c", configPath])
                }
                if let speakerId = self.speakerId {
                    args.append(contentsOf: ["--speaker", String(speakerId)])
                }
                if let lengthScale = self.lengthScale {
                    args.append(contentsOf: ["--length_scale", String(lengthScale)])
                }
                if let noiseScale = self.noiseScale {
                    args.append(contentsOf: ["--noise_scale", String(noiseScale)])
                }
                if let noiseW = self.noiseW {
                    args.append(contentsOf: ["--noise_w", String(noiseW)])
                }
                if let sentenceSilence = self.sentenceSilence {
                    args.append(contentsOf: ["--sentence_silence", String(sentenceSilence)])
                }
                if let phonemeSilence = self.phonemeSilence {
                    args.append(contentsOf: ["--phoneme_silence", String(phonemeSilence)])
                }
                process.arguments = args

                let stdinPipe = Pipe()
                let stdoutPipe = Pipe()
                process.standardInput = stdinPipe
                process.standardOutput = stdoutPipe
                let stderrPipe = Pipe()
                process.standardError = stderrPipe
                self.currentProcess?.terminate()
                self.currentProcess = process

                do {
                    try process.run()
                } catch {
                    continuation.finish()
                    return
                }

                if let data = text.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(data)
                }
                stdinPipe.fileHandleForWriting.closeFile()

                let chunkSize = 4096
                while true {
                    let data = stdoutPipe.fileHandleForReading.readData(ofLength: chunkSize)
                    if data.isEmpty { break }
                    let samples = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [Int16] in
                        let count = data.count / 2
                        let buf = ptr.bindMemory(to: Int16.self)
                        return Array(buf.prefix(count))
                    }
                    if !samples.isEmpty {
                        continuation.yield(AudioPCM(sampleRate: self.sampleRate, channels: 1, samples: samples))
                    }
                }

                process.waitUntilExit()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if DebugFlags.audio, let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                    print("vpa piper stderr: \(errStr)")
                }
                continuation.finish()
            }
        }
    }

    public func stop() {
        queue.sync {
            self.currentProcess?.terminate()
            self.currentProcess = nil
        }
    }

    private static func readSampleRate(configPath: String?) -> Int? {
        guard let configPath else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let audio = json["audio"] as? [String: Any],
           let rate = audio["sample_rate"] as? Int {
            return rate
        }
        return nil
    }
}
