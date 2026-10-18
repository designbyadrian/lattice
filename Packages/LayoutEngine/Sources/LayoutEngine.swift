import Foundation
import LayoutModel

/// Lattice layout engine: solve, camera, collapse, history, animation math.
public enum LayoutEngine {
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

    /// ADDENDUM-3 solve returning placements keyed by node id.
    public static func solvePlacements(
        root: LayoutNode,
        cfg: LayoutConfig = .default,
        screen: ScreenGeometry = .golden,
        camera: EdgeRect = .unit,
        framed: NodeID? = nil,
        prevIcons: Set<NodeID> = [],
        prevGroupTiles: Set<NodeID> = []
    ) -> [NodeID: Placement] {
        LayoutSolver.solve(
            root: root,
            cfg: cfg,
            screen: screen,
            camera: camera,
            framed: framed,
            prevIcons: prevIcons,
            prevGroupTiles: prevGroupTiles
        ).placements
    }
}

public enum LayoutEngineModule {
    public static let name = "LayoutEngine"
}
