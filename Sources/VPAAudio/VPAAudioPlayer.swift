import Foundation
import AVFoundation
import VPACore

public final class VPAAudioPlayer: AudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isStarted = false
    private var currentSampleRate: Double?
    private let queue = DispatchQueue(label: "vpa.audio.player")
    private var pending: [AVAudioPCMBuffer] = []
    private let minBuffered = 3

    public init() {
        engine.attach(player)
        player.volume = 1.0
        engine.mainMixerNode.outputVolume = 1.0
    }

    public func play(stream: AsyncStream<AudioPCM>) {
        Task {
            for await chunk in stream {
                if chunk.samples.isEmpty { continue }
                self.schedule(chunk: chunk)
            }
        }
    }

    public func stop() {
        queue.sync {
            pending.removeAll()
            player.stop()
            engine.stop()
            engine.reset()
            isStarted = false
            currentSampleRate = nil
        }
    }

    private func schedule(chunk: AudioPCM) {
        queue.async {
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(chunk.sampleRate), channels: 1, interleaved: false)
            guard let format else {
                return
            }
            if self.isStarted, let current = self.currentSampleRate, current != format.sampleRate {
                self.player.stop()
                self.engine.stop()
                self.engine.reset()
                self.pending.removeAll()
                self.isStarted = false
            }
            let frameCount = AVAudioFrameCount(chunk.samples.count)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
            buffer.frameLength = frameCount
            if let int16Ptr = buffer.int16ChannelData {
                chunk.samples.withUnsafeBufferPointer { src in
                    int16Ptr[0].update(from: src.baseAddress!, count: chunk.samples.count)
                }
            }

            if !self.isStarted {
                self.engine.connect(self.player, to: self.engine.mainMixerNode, format: format)
                do {
                    try self.engine.start()
                    self.isStarted = true
                    self.currentSampleRate = format.sampleRate
                    self.player.volume = 1.0
                    self.engine.mainMixerNode.outputVolume = 1.0
                } catch {
                    return
                }
            }

            if !self.player.isPlaying && self.pending.isEmpty {
                self.player.scheduleBuffer(buffer, completionHandler: nil)
                self.player.play()
                return
            }
            if self.player.isPlaying || self.pending.count >= self.minBuffered {
                self.player.scheduleBuffer(buffer, completionHandler: nil)
                if !self.player.isPlaying {
                    self.player.play()
                }
            } else {
                self.pending.append(buffer)
                if self.pending.count >= self.minBuffered {
                    for buf in self.pending {
                        self.player.scheduleBuffer(buf, completionHandler: nil)
                    }
                    self.pending.removeAll()
                    if !self.player.isPlaying {
                        self.player.play()
                    }
                }
            }
        }
    }
}
