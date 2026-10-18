import Foundation

/// Per-OS input capability state (P5a matrix → safety net).
public struct InputSafetyNetState: Sendable, Equatable {
    /// When true, disable modifier-drag swallow, pinch-over-apps, and L/R modifier distinction.
    public var reducedInputFeatures: Bool
    /// Human-readable reason shown in the menu when reduced.
    public var notice: String?

    public init(reducedInputFeatures: Bool = false, notice: String? = nil) {
        self.reducedInputFeatures = reducedInputFeatures
        self.notice = notice
    }

    public static let full = InputSafetyNetState()

    public static func reduced(reason: String) -> InputSafetyNetState {
        InputSafetyNetState(
            reducedInputFeatures: true,
            notice: reason
        )
    }

    /// Features disabled under the safety net (only these three).
    public var disablesModifierDrag: Bool { reducedInputFeatures }
    public var disablesPinchOverApps: Bool { reducedInputFeatures }
    public var disablesLeftRightModifiers: Bool { reducedInputFeatures }

    /// Derive state from tap creation / P5a matrix outcome for this OS.
    public static func from(
        tapCreated: Bool,
        inputMonitoringPrompted: Bool,
        osMajor: Int
    ) -> InputSafetyNetState {
        if !tapCreated {
            return .reduced(reason: "Event tap unavailable on macOS \(osMajor); using Carbon hotkey fallback.")
        }
        if inputMonitoringPrompted {
            return .reduced(reason: "Input Monitoring prompted on macOS \(osMajor); reduced input features active.")
        }
        return .full
    }
}
