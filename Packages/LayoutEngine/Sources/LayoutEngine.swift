import Foundation
import LayoutModel

/// Lattice layout engine: solve, camera, collapse, history, animation math.
/// Foundation + LayoutModel only (no AppKit).
public enum LayoutEngine {
    /// Solve tiled + floating frames for a workspace.
    public static func solve(
        workspace: Workspace,
        displayRect: Rect,
        gaps: Gaps = .zero,
        minSizes: MinSizes = [:]
    ) -> [WindowID: Rect] {
        LayoutSolver.solveFrames(
            workspace: workspace,
            displayRect: displayRect,
            gaps: gaps,
            minSizes: minSizes
        )
    }

    /// Full solve including node frames and forced-float set.
    public static func solveDetailed(
        workspace: Workspace,
        displayRect: Rect,
        gaps: Gaps = .zero,
        minSizes: MinSizes = [:]
    ) -> SolveResult {
        LayoutSolver.solve(
            workspace: workspace,
            displayRect: displayRect,
            gaps: gaps,
            minSizes: minSizes
        )
    }
}

/// Package marker (kept for smoke tests / discoverability).
public enum LayoutEngineModule {
    public static let name = "LayoutEngine"
}
