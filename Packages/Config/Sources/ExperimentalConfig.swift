import Foundation

/// Lattice extension: optional private-API paths (`[experimental]` in `lattice.toml`).
///
/// Off by default. Runtime shims may auto-disable a flag when symbols are missing or a call fails.
public struct ExperimentalConfig: Sendable, Equatable, Codable {
    /// Optional `_AXUIElementGetWindow` shortcut (falls back to public CGWindowList matching).
    public var axWindowID: Bool
    /// Raw multitouch path (safe no-op when symbols are unavailable).
    public var multitouch: Bool

    public init(axWindowID: Bool = false, multitouch: Bool = false) {
        self.axWindowID = axWindowID
        self.multitouch = multitouch
    }

    public static let `default` = ExperimentalConfig()
}
