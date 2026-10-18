import Foundation
import LayoutModel

/// Camera navigation stub over a solved layout (full framing lives in LayoutSolver).
public struct CameraEngine: Equatable, Sendable {
    public var workspace: Workspace
    public var displayRect: Rect
    public var gaps: Gaps
    public var minSizes: MinSizes
    public private(set) var solveResult: SolveResult

    public init(
        workspace: Workspace,
        displayRect: Rect,
        gaps: Gaps = .zero,
        minSizes: MinSizes = [:]
    ) {
        self.workspace = workspace
        self.displayRect = displayRect
        self.gaps = gaps
        self.minSizes = minSizes
        self.solveResult = LayoutSolver.solve(
            workspace: workspace,
            displayRect: displayRect,
            gaps: gaps,
            minSizes: minSizes
        )
    }

    public var camera: Camera {
        get { workspace.camera }
        set { workspace.camera = newValue }
    }

    public mutating func refresh() {
        solveResult = LayoutSolver.solve(
            workspace: workspace,
            displayRect: displayRect,
            gaps: gaps,
            minSizes: minSizes
        )
    }

    public mutating func stepIn(towardPoint point: Point) {
        _ = point
        // Frame root until full solve/camera walk is wired.
        if let id = workspace.root.id as NodeID? {
            if let slot = solveResult.slots[id] {
                camera = Camera(slot.world)
            }
        }
    }

    public mutating func stepOut() {
        camera = .home
    }

    public mutating func frameAlone(_ window: WindowID) {
        let id = window.nodeID
        if let slot = solveResult.slots[id] {
            camera = Camera(slot.world)
        } else if let path = workspace.root.path(to: id),
                  let node = workspace.root.node(at: path),
                  let slot = solveResult.slots[node.id] {
            camera = Camera(slot.world)
        }
    }

    public mutating func showAll() {
        camera = .home
    }

    public mutating func frameRect(_ rect: Rect) {
        _ = rect
        camera = .home
    }

    public func framesAt(_ camera: Camera) -> [WindowID: Rect] {
        _ = camera
        return solveResult.frames
    }

    public func framesAtCamera() -> [WindowID: Rect] {
        framesAt(camera)
    }
}

func stableKey(_ id: WindowID) -> String {
    let cg = id.cgWindowID.map(String.init) ?? "nil"
    return "\(cg)|\(id.processID)|\(id.bundleID ?? "")|\(id.titleFingerprint)"
}
