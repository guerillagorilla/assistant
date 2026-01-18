import Foundation

public struct LatencyMetrics {
    public let captureMs: Int
    public let sttMs: Int
    public let responseMs: Int
    public let ttsStartMs: Int

    public init(captureMs: Int, sttMs: Int, responseMs: Int, ttsStartMs: Int) {
        self.captureMs = captureMs
        self.sttMs = sttMs
        self.responseMs = responseMs
        self.ttsStartMs = ttsStartMs
    }
}

public protocol MetricsSink {
    func record(latency: LatencyMetrics)
    func record(error: String)
}

public final class NoopMetricsSink: MetricsSink {
    public init() {}
    public func record(latency: LatencyMetrics) {}
    public func record(error: String) {}
}
