import Foundation

/// Feature flags for optional / private-API paths.
///
/// `axWindowID` gates `_AXUIElementGetWindow` (P10). Public matching is always the fallback.
/// `multitouch` gates the raw MultitouchSupport path (P10). Both are off by default and may
/// auto-disable at runtime when symbols are missing or a call fails.
public struct ExperimentalFlags: Sendable, Equatable, Codable {
    /// When true, allow the private AX→CGWindowID shortcut (PlatformMac `AXWindowIDShortcut`).
    public var axWindowID: Bool
    /// When true, arm the raw multitouch path (PlatformMac `ExperimentalMultitouchSession`).
    public var multitouch: Bool

    public init(axWindowID: Bool = false, multitouch: Bool = false) {
        self.axWindowID = axWindowID
        self.multitouch = multitouch
    }

    public static let `default` = ExperimentalFlags()
}
