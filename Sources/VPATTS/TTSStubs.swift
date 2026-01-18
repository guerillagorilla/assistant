import Foundation
import VPACore

public final class StubTTSEngine: TTSEngine {
    public init() {}

    public func synthesize(text: String) -> AsyncStream<AudioPCM> {
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func stop() {}
}
