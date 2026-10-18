import Foundation

/// Lifecycle / visibility state of a managed window.
///
/// Suspended windows (minimized, fullscreen, hidden) keep their tree slot but
/// take no space when the layout is solved; on resume they reclaim the slot.
public enum WindowState: String, Codable, Sendable, Equatable, CaseIterable {
    case active
    case minimized
    case fullscreen
    case hidden

    /// Whether the solver should allocate space for this window.
    public var participatesInSolve: Bool {
        self == .active
    }

    public var isSuspended: Bool {
        !participatesInSolve
    }
}
