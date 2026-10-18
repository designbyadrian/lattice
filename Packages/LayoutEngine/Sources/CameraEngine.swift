import Foundation
import LayoutModel

/// Camera navigation over a solved layout (ADDENDUM-3 §1.3, B6/B9/B10).
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

    // MARK: - Camera ops

    public mutating func stepIn(towardPoint point: Point) {
        refresh()
        let world = screenToWorld(point)
        let target = deepestNode(containing: world) ?? workspace.root.id
        frameNode(target)
    }

    public mutating func stepOut() {
        refresh()
        let framed = framedNodeID()
        if let parent = solveResult.slots[framed]?.parent {
            frameNode(parent)
        } else {
            showAll()
        }
    }

    public mutating func frameAlone(_ window: WindowID) {
        refresh()
        frameNode(window.nodeID)
    }

    public mutating func frameDesktop() {
        refresh()
        if TreeOps.find(workspace.root, target: "desktop") != nil {
            frameNode("desktop")
        } else {
            showAll()
        }
    }

    public mutating func showAll() {
        camera = .home
        refresh()
    }

    /// Aspect-fit camera for a world-space rect (B4 frame-rect).
    public mutating func frameRect(_ rect: Rect) {
        let world = screenRectToWorld(rect)
        camera = Camera(Self.aspectFitCamera(around: world))
        refresh()
    }

    public mutating func frameWorldRect(_ edges: EdgeRect) {
        camera = Camera(Self.aspectFitCamera(around: edges))
        refresh()
    }

    /// Continuous pinch: scale camera about a screen point by `factor` (>1 zooms in).
    public mutating func pinchScale(factor: Double, aboutScreenPoint point: Point) {
        guard factor > 0, factor.isFinite else { return }
        let pivot = screenToWorld(point)
        var e = camera.edges
        let cx = (e.x0 + e.x1) / 2
        let cy = (e.y0 + e.y1) / 2
        // Scale about pivot: move edges toward/away from pivot.
        let inv = 1.0 / factor
        e.x0 = pivot.x + (e.x0 - pivot.x) * inv
        e.x1 = pivot.x + (e.x1 - pivot.x) * inv
        e.y0 = pivot.y + (e.y0 - pivot.y) * inv
        e.y1 = pivot.y + (e.y1 - pivot.y) * inv
        // Keep aspect (equal zoom) and clamp into unit square.
        let side = max(e.width, e.height, 1e-6)
        let midX = (e.x0 + e.x1) / 2
        let midY = (e.y0 + e.y1) / 2
        _ = cx; _ = cy
        var cam = EdgeRect(x0: midX - side / 2, y0: midY - side / 2, x1: midX + side / 2, y1: midY + side / 2)
        cam = Self.clampCamera(cam)
        camera = Camera(cam)
        refresh()
    }

    /// On pinch release: settle on the best-fitting node under the pointer (B9 / §5.5).
    public mutating func settlePinch(aboutScreenPoint point: Point) {
        refresh()
        let cfg = workspace.layoutConfig
        let screen = ScreenGeometry(visible: displayRect, frame: displayRect)
        let C = screen.contentEdges(cfg: cfg)
        let home = Size(width: C.width, height: C.height)
        let world = screenToWorld(point)
        let id = LayoutSolver.settleTarget(
            root: workspace.root,
            cfg: cfg,
            homeSize: home,
            cam: camera.edges,
            pointer: world
        )
        frameNode(id)
    }

    /// Pan to a same-depth neighbour region (B10). Returns false at the arrangement edge.
    @discardableResult
    public mutating func pan(_ direction: Edge) -> Bool {
        refresh()
        let framed = framedNodeID()
        guard let slot = solveResult.slots[framed],
              let parentID = slot.parent,
              let loc = TreeOps.find(workspace.root, target: parentID),
              case .split(let sp) = loc.node,
              let idx = sp.children.firstIndex(where: { $0.id == framed }) else {
            return false
        }
        let axisOK = (sp.axis == .horizontal && (direction == .left || direction == .right))
            || (sp.axis == .vertical && (direction == .top || direction == .bottom))
        guard axisOK else { return false }
        let delta = (direction == .left || direction == .top) ? -1 : 1
        let ni = idx + delta
        guard sp.children.indices.contains(ni) else { return false }
        frameNode(sp.children[ni].id)
        return true
    }

    /// Toggle: if already framing `target`, go back via history; else frame it (ADDENDUM A1).
    public mutating func toggleFrame(
        target: NodeID,
        history: inout NavigationHistory
    ) {
        refresh()
        if framedNodeID() == target, history.canGoBack, let back = history.back() {
            camera = back
            refresh()
            return
        }
        frameNode(target)
        history.navigate(to: camera)
    }

    public func framesAt(_ camera: Camera) -> [WindowID: Rect] {
        var ws = workspace
        ws.camera = camera
        return LayoutSolver.solve(
            workspace: ws,
            displayRect: displayRect,
            gaps: gaps,
            minSizes: minSizes
        ).frames
    }

    public func framesAtCamera() -> [WindowID: Rect] {
        framesAt(camera)
    }

    // MARK: - Helpers

    public mutating func frameNode(_ id: NodeID) {
        if let slot = solveResult.slots[id] {
            camera = Camera(slot.world)
        } else if id == workspace.root.id, let slot = solveResult.slots[workspace.root.id] {
            camera = Camera(slot.world)
        } else {
            camera = .home
        }
        refresh()
    }

    /// Deepest node whose world rect equals the camera (framed node), else root.
    public func framedNodeID() -> NodeID {
        let cam = camera.edges
        var best: (depth: Int, id: NodeID)?
        for (id, slot) in solveResult.slots {
            let w = slot.world
            if abs(w.x0 - cam.x0) < 1e-9, abs(w.y0 - cam.y0) < 1e-9,
               abs(w.x1 - cam.x1) < 1e-9, abs(w.y1 - cam.y1) < 1e-9 {
                if best == nil || slot.depth > best!.depth {
                    best = (slot.depth, id)
                }
            }
        }
        return best?.id ?? workspace.root.id
    }

    private func deepestNode(containing world: Point) -> NodeID? {
        var best: (depth: Int, id: NodeID)?
        for (id, slot) in solveResult.slots {
            let w = slot.world
            guard w.contains(pointX: world.x, y: world.y) else { continue }
            // Skip tab members as pinch/step targets (§5.5).
            if case .window = TreeOps.find(workspace.root, target: id)?.node,
               let p = slot.parent,
               case .tabs = TreeOps.find(workspace.root, target: p)?.node {
                continue
            }
            if best == nil || slot.depth > best!.depth {
                best = (slot.depth, id)
            }
        }
        return best?.id
    }

    private func screenToWorld(_ point: Point) -> Point {
        let cfg = workspace.layoutConfig
        let screen = ScreenGeometry(visible: displayRect, frame: displayRect)
        let C = screen.contentEdges(cfg: cfg)
        let cam = camera.edges
        let x = cam.x0 + (point.x - C.x0) * cam.width / max(C.width, 1e-9)
        let y = cam.y0 + (point.y - C.y0) * cam.height / max(C.height, 1e-9)
        return Point(x: x, y: y)
    }

    private func screenRectToWorld(_ rect: Rect) -> EdgeRect {
        let a = screenToWorld(Point(x: rect.minX, y: rect.minY))
        let b = screenToWorld(Point(x: rect.maxX, y: rect.maxY))
        return EdgeRect(
            x0: min(a.x, b.x), y0: min(a.y, b.y),
            x1: max(a.x, b.x), y1: max(a.y, b.y)
        )
    }

    public static func aspectFitCamera(around r: EdgeRect) -> EdgeRect {
        let rw = max(r.width, 1e-9)
        let rh = max(r.height, 1e-9)
        let z = min(1 / rw, 1 / rh)
        if z <= 1 {
            return clampCamera(.unit)
        }
        let side = 1 / z
        let cx = (r.x0 + r.x1) / 2
        let cy = (r.y0 + r.y1) / 2
        return clampCamera(EdgeRect(
            x0: cx - side / 2, y0: cy - side / 2,
            x1: cx + side / 2, y1: cy + side / 2
        ))
    }

    public static func clampCamera(_ cam: EdgeRect) -> EdgeRect {
        var e = cam
        let w = min(max(e.width, 1e-6), 1)
        let h = min(max(e.height, 1e-6), 1)
        // Prefer equal sides for aspect-fit cameras.
        let side = max(w, h)
        var x0 = (e.x0 + e.x1) / 2 - side / 2
        var y0 = (e.y0 + e.y1) / 2 - side / 2
        x0 = min(max(x0, 0), 1 - side)
        y0 = min(max(y0, 0), 1 - side)
        e = EdgeRect(x0: x0, y0: y0, x1: x0 + side, y1: y0 + side)
        if e.width >= 1 - 1e-12, e.height >= 1 - 1e-12 {
            return .unit
        }
        return e
    }
}

func stableKey(_ id: WindowID) -> String {
    let cg = id.cgWindowID.map(String.init) ?? "nil"
    return "\(cg)|\(id.processID)|\(id.bundleID ?? "")|\(id.titleFingerprint)"
}
