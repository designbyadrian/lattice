import Foundation
import LayoutModel

/// Minimum size request for a window (points). Legacy AppCore bridge.
public typealias MinSizes = [WindowID: Size]

/// Result of solving a workspace tree into frames (legacy shape for AppCore).
public struct SolveResult: Equatable, Sendable {
    public var frames: [WindowID: Rect]
    public var nodeFrames: [NodePath: Rect]
    public var forcedFloating: Set<WindowID>
    public var placements: [NodeID: Placement]
    public var slots: [NodeID: WorldSlot]

    public init(
        frames: [WindowID: Rect] = [:],
        nodeFrames: [NodePath: Rect] = [:],
        forcedFloating: Set<WindowID> = [],
        placements: [NodeID: Placement] = [:],
        slots: [NodeID: WorldSlot] = [:]
    ) {
        self.frames = frames
        self.nodeFrames = nodeFrames
        self.forcedFloating = forcedFloating
        self.placements = placements
        self.slots = slots
    }
}

/// Placement class + frames (ADDENDUM-3 S7–S9).
public struct Placement: Equatable, Sendable {
    public var id: NodeID
    public var cls: String
    public var frame: Rect
    public var real: Rect?

    public init(id: NodeID, cls: String, frame: Rect, real: Rect? = nil) {
        self.id = id
        self.cls = cls
        self.frame = frame
        self.real = real
    }
}

/// Stub solver — replaced in LayoutEngine rewrite commit.
public enum LayoutSolver {
    public static func solve(
        workspace: Workspace,
        displayRect: Rect,
        gaps: Gaps = .zero,
        minSizes: MinSizes = [:]
    ) -> SolveResult {
        _ = (workspace, displayRect, gaps, minSizes)
        return SolveResult()
    }

    public static func solveFrames(
        workspace: Workspace,
        displayRect: Rect,
        gaps: Gaps = .zero,
        minSizes: MinSizes = [:]
    ) -> [WindowID: Rect] {
        solve(workspace: workspace, displayRect: displayRect, gaps: gaps, minSizes: minSizes).frames
    }
}
