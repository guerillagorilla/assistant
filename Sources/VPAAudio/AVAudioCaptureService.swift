import Foundation
import AVFoundation
import VPACore

public final class AVAudioCaptureService: AudioCaptureService {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "vpa.audio.capture")

    private var targetSampleRate: Double
    private var preRollMs: Int
    private var preRollBuffer: [Int16] = []
    private var captureBuffer: [Int16] = []
    private var isCapturing: Bool = false
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var lastDebugLog: TimeInterval = 0
    private var captureStartedAt: TimeInterval?
    private var currentSampleRate: Double
    private var gainDb: Double
    private var gainLinear: Double

    public init(sampleRate: Int = 16000, preRollMs: Int = 250, gainDb: Double = 0.0) {
        self.targetSampleRate = Double(sampleRate)
        self.preRollMs = preRollMs
        self.currentSampleRate = Double(sampleRate)
        self.gainDb = gainDb
        self.gainLinear = pow(10.0, gainDb / 20.0)
        requestMicAccessAndSetup()
    }

    public func setPreRollMs(_ ms: Int) {
        queue.sync {
            preRollMs = ms
            let maxSamples = preRollSamples()
            if preRollBuffer.count > maxSamples {
                preRollBuffer = Array(preRollBuffer.suffix(maxSamples))
            }
        }
    }

    public func startCapture() {
        queue.sync {
            isCapturing = true
            captureBuffer.removeAll(keepingCapacity: true)
            // Seed capture with pre-roll
            if !preRollBuffer.isEmpty {
                captureBuffer.append(contentsOf: preRollBuffer)
            }
            captureStartedAt = Date().timeIntervalSince1970
            if DebugFlags.audio { print("vpa audio: startCapture") }
        }
    }

    public func stopCapture() -> AudioPCM {
        let rawSamples: [Int16] = queue.sync {
            isCapturing = false
            let out = captureBuffer
            captureBuffer.removeAll(keepingCapacity: true)
            return out
        }
        var samples = rawSamples
        let duration = Double(samples.count) / currentSampleRate
        if let started = captureStartedAt {
            let wall = Date().timeIntervalSince1970 - started
            if DebugFlags.audio { print(String(format: "vpa audio: stopCapture (wall=%.2fs)", wall)) }
        } else {
            if DebugFlags.audio { print("vpa audio: stopCapture") }
        }
        if DebugFlags.audio { print(String(format: "vpa audio: captured %.2fs (%d samples)", duration, samples.count)) }

        if currentSampleRate != targetSampleRate, !samples.isEmpty {
            samples = resampleLinear(samples: samples, fromRate: currentSampleRate, toRate: targetSampleRate)
            currentSampleRate = targetSampleRate
        }

        applyGain(to: &samples)
        return AudioPCM(sampleRate: Int(currentSampleRate), channels: 1, samples: samples)
    }

    private func requestMicAccessAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            setupEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.setupEngine()
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func setupEngine() {
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        logActiveInputDevice()
        logInputFormat(inputFormat)

        let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )

        self.targetFormat = target

        if let target {
            converter = AVAudioConverter(from: inputFormat, to: target)
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processInput(buffer: buffer)
        }

        do {
            try engine.start()
        } catch {
            // If engine fails, capture will be empty; higher layers can handle failure UX.
        }
    }

    private func processInput(buffer: AVAudioPCMBuffer) {
        let format = buffer.format
        if format.commonFormat == .pcmFormatFloat32, format.channelCount >= 1,
           let floatPtr = buffer.floatChannelData {
            currentSampleRate = format.sampleRate
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 { return }
            let chan = floatPtr[0]
            var samples: [Int16] = []
            samples.reserveCapacity(frameLength)
            for i in 0..<frameLength {
                let f = max(-1.0, min(1.0, Double(chan[i])))
                let s = Int16(f * 32767.0)
                samples.append(s)
            }
            logLevels(samples: samples)
            queue.sync { self.appendSamples(samples) }
            return
        }

        if format.commonFormat == .pcmFormatInt16, format.channelCount >= 1,
           let int16Ptr = buffer.int16ChannelData {
            currentSampleRate = format.sampleRate
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 { return }
            let samples = Array(UnsafeBufferPointer(start: int16Ptr[0], count: frameLength))
            logLevels(samples: samples)
            queue.sync { self.appendSamples(samples) }
            return
        }

        // Fallback: attempt conversion when format is not float32/int16
        guard let targetFormat else { return }
        guard let converter else { return }

        currentSampleRate = targetFormat.sampleRate
        let inputRate = buffer.format.sampleRate
        let ratio = targetFormat.sampleRate / inputRate
        let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        let capacity = max(estimatedFrames, 1)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var error: NSError?
        var didProvideInput = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .endOfStream
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        if error != nil { return }

        guard let int16Pointer = converted.int16ChannelData else { return }
        let frameLength = Int(converted.frameLength)
        if frameLength == 0 { return }

        let samples = Array(UnsafeBufferPointer(start: int16Pointer[0], count: frameLength))
        logLevels(samples: samples)
        queue.sync { self.appendSamples(samples) }
    }

    private func appendSamples(_ samples: [Int16]) {
        if isCapturing {
            captureBuffer.append(contentsOf: samples)
        } else {
            preRollBuffer.append(contentsOf: samples)
            let maxSamples = preRollSamples()
            if preRollBuffer.count > maxSamples {
                preRollBuffer = Array(preRollBuffer.suffix(maxSamples))
            }
        }
    }

    private func preRollSamples() -> Int {
        return Int((Double(preRollMs) / 1000.0) * targetSampleRate)
    }

    private func applyGain(to samples: inout [Int16]) {
        guard gainDb != 0.0 else { return }
        for i in samples.indices {
            let v = Double(samples[i]) * gainLinear
            if v > Double(Int16.max) {
                samples[i] = Int16.max
            } else if v < Double(Int16.min) {
                samples[i] = Int16.min
            } else {
                samples[i] = Int16(v)
            }
        }
    }

    private func resampleLinear(samples: [Int16], fromRate: Double, toRate: Double) -> [Int16] {
        if samples.isEmpty { return samples }
        let ratio = toRate / fromRate
        let outCount = max(1, Int(Double(samples.count) * ratio))
        var out: [Int16] = []
        out.reserveCapacity(outCount)
        for i in 0..<outCount {
            let srcPos = Double(i) / ratio
            let i0 = Int(floor(srcPos))
            let i1 = min(i0 + 1, samples.count - 1)
            let frac = srcPos - Double(i0)
            let s0 = Double(samples[i0])
            let s1 = Double(samples[i1])
            let v = s0 + (s1 - s0) * frac
            let clamped = max(Double(Int16.min), min(Double(Int16.max), v))
            out.append(Int16(clamped))
        }
        return out
    }

    private func logInputFormat(_ format: AVAudioFormat) {
        let desc = String(format: "input format: %.0f Hz, ch=%d, interleaved=%@",
                          format.sampleRate, format.channelCount, format.isInterleaved ? "yes" : "no")
        if DebugFlags.audio { print("vpa audio: \(desc)") }
    }

    private func logActiveInputDevice() {
        #if os(macOS)
        if let device = AVCaptureDevice.default(for: .audio) {
            if DebugFlags.audio { print("vpa audio: input device = \(device.localizedName)") }
        } else {
            if DebugFlags.audio { print("vpa audio: input device = <none>") }
        }
        #endif
    }

    private func logLevels(samples: [Int16]) {
        let now = Date().timeIntervalSince1970
        if now - lastDebugLog < 1.0 { return }
        lastDebugLog = now
        if samples.isEmpty { return }
        var sum: Double = 0
        var peak: Int16 = 0
        for s in samples {
            let absVal = Int16(abs(Int(s)))
            if absVal > peak { peak = absVal }
            sum += Double(absVal)
        }
        let avg = sum / Double(samples.count)
        if DebugFlags.audio { print(String(format: "vpa audio: level avg=%.1f peak=%d", avg, peak)) }
    }
}
