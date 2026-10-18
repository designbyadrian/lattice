import Foundation

/// Protocol-only platform boundary. Implementations live in PlatformMac.
public enum PlatformModule {
    public static let name = "Platform"
}

/// Stub for the private `_AXUIElementGetWindow` path (P10). Always returns nil until implemented.
public enum ExperimentalAXWindowID {
    /// Returns a CGWindowID only when `flags.axWindowID` is on **and** a future shim is present.
    public static func cgWindowIDIfEnabled(flags: ExperimentalFlags) -> UInt32? {
        guard flags.axWindowID else { return nil }
        // P10: call private shim here. Intentionally unimplemented.
        return nil
    }
}
