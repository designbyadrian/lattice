import Foundation

/// Protocol-only platform boundary. Implementations live in PlatformMac.
public enum PlatformModule {
    public static let name = "Platform"
}

/// Soft gate for the private `_AXUIElementGetWindow` path (P10).
/// Resolution lives in `PlatformMac` (`AXWindowIDShortcut`); public CG matching is always the fallback.
public enum ExperimentalAXWindowID {
    /// Whether the private AX→CGWindowID shortcut is requested (config / flags).
    public static func isRequested(_ flags: ExperimentalFlags) -> Bool {
        flags.axWindowID
    }
}
