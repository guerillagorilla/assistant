import Foundation

public final class RollingMetricsSink: MetricsSink {
    private let reportEvery: Int
    private var latencies: [LatencyMetrics] = []
    private let lock = NSLock()

    public init(reportEvery: Int = 5) {
        self.reportEvery = reportEvery
    }

    public func record(latency: LatencyMetrics) {
        lock.lock()
        latencies.append(latency)
        let count = latencies.count
        let snapshot = latencies
        lock.unlock()

        if count % reportEvery == 0 {
            let stt = snapshot.map { $0.sttMs }
            let tts = snapshot.map { $0.ttsStartMs }
            let total = snapshot.map { $0.captureMs + $0.sttMs + $0.responseMs + $0.ttsStartMs }
            print("vpa metrics: p50/p95 stt=\(p50(stt))/\(p95(stt)) ms, ttsStart=\(p50(tts))/\(p95(tts)) ms, total=\(p50(total))/\(p95(total)) ms")
        }
    }

    public func record(error: String) {
        print("vpa metrics: error=\(error)")
    }

    private func p50(_ values: [Int]) -> Int { percentile(values, 50) }
    private func p95(_ values: [Int]) -> Int { percentile(values, 95) }

    private func percentile(_ values: [Int], _ p: Int) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let idx = Int(round((Double(p) / 100.0) * Double(sorted.count - 1)))
        return sorted[max(0, min(idx, sorted.count - 1))]
    }
}
