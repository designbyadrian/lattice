import Foundation

/// Feature flags for optional / private-API paths.
///
/// `axWindowID` gates `_AXUIElementGetWindow` (P10). Public matching is always used first.
public struct ExperimentalFlags: Sendable, Equatable, Codable {
    /// When true, allow the private AX→CGWindowID fallback (not implemented until P10).
    public var axWindowID: Bool
    public var multitouch: Bool

    public init(axWindowID: Bool = false, multitouch: Bool = false) {
        self.axWindowID = axWindowID
        self.multitouch = multitouch
    }

    public static let `default` = ExperimentalFlags()
}
