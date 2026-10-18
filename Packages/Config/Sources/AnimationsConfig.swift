import Foundation

/// `[animations]` — off under Reduce Motion at runtime.
public struct AnimationsConfig: Sendable, Equatable {
    public var enabled: Bool
    public var durationMs: Int

    public init(enabled: Bool = true, durationMs: Int = 450) {
        self.enabled = enabled
        self.durationMs = durationMs
    }

    public static let `default` = AnimationsConfig()

    public var durationSeconds: Double {
        Double(durationMs) / 1000.0
    }
}
