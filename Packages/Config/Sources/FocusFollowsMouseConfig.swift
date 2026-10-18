import Foundation

/// `[focus-follows-mouse]` stub (Dinky keys + Lattice `exclude-apps`).
public struct FocusFollowsMouseConfig: Sendable, Equatable {
    public var enabled: Bool
    public var delayMs: Int
    /// Accepted for compatibility; no effect (Lattice has no accordion).
    public var accordionEdges: Bool
    /// Lattice extension: bundle IDs that never receive FFM focus.
    public var excludeApps: [String]

    public init(
        enabled: Bool = false,
        delayMs: Int = 100,
        accordionEdges: Bool = false,
        excludeApps: [String] = []
    ) {
        self.enabled = enabled
        self.delayMs = delayMs
        self.accordionEdges = accordionEdges
        self.excludeApps = excludeApps
    }

    public static let `default` = FocusFollowsMouseConfig()
}
