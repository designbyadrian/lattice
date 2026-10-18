import Foundation
import LayoutModel

/// Camera navigation and view transforms over a solved layout.
public struct CameraEngine: Equatable, Sendable {
    public var workspace: Workspace
    public var displayRect: Rect
    public var gaps: Gaps
    public var minSizes: MinSizes
    /// Latest solve used for navigation (recomputed when workspace changes).
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

    /// Re-solve after workspace mutations.
    public mutating func refresh() {
        solveResult = LayoutSolver.solve(
            workspace: workspace,
            displayRect: displayRect,
            gaps: gaps,
            minSizes: minSizes
        )
    }

    // MARK: - Operations

    /// Step one nesting level toward the child under `point` (display coordinates).
    public mutating func stepIn(towardPoint point: Point) {
        let worldPoint = screenToWorld(point, camera: camera)
        let focus = camera.focusPath
        guard let node = workspace.root.node(at: focus) else { return }

        switch node {
        case .split(let split):
            for (index, _) in split.children.enumerated() {
                let childPath = focus + [index]
                guard let childFrame = solveResult.nodeFrames[childPath] else { continue }
                if childFrame.contains(point: worldPoint) {
                    camera = Camera(focusPath: childPath, zoom: 1)
                    return
                }
            }
            // Fallback: nearest child by center distance.
            var best: (NodePath, Double)?
            for (index, _) in split.children.enumerated() {
                let childPath = focus + [index]
                guard let childFrame = solveResult.nodeFrames[childPath] else { continue }
                let dx = childFrame.midX - worldPoint.x
                let dy = childFrame.midY - worldPoint.y
                let d = dx * dx + dy * dy
                if best == nil || d < best!.1 {
                    best = (childPath, d)
                }
            }
            if let best {
                camera = Camera(focusPath: best.0, zoom: 1)
            }
        case .panel, .tabs, .desktop:
            // Already a leaf under focus — ensure zoomed in.
            camera = Camera(focusPath: focus, zoom: 1)
        }
    }

    /// Step out one nesting level.
    public mutating func stepOut() {
        var path = camera.focusPath
        if path.isEmpty {
            camera = .showAll
            return
        }
        path.removeLast()
        if path.isEmpty {
            camera = .showAll
        } else {
            camera = Camera(focusPath: path, zoom: 1)
        }
    }

    /// Zoom so `window` alone fills the display.
    public mutating func frameAlone(_ window: WindowID) {
        guard let path = workspace.root.path(to: window) else { return }
        camera = Camera(focusPath: path, zoom: 1)
    }

    /// Show the entire tree.
    public mutating func showAll() {
        camera = .showAll
    }

    /// Zoom to fit a dragged rectangle (world / solve coordinates).
    public mutating func frameRect(_ rect: Rect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let center = Point(x: rect.midX, y: rect.midY)
        // Deepest node containing the center.
        var bestPath: NodePath = []
        for path in workspace.root.allPaths().sorted(by: { $0.count > $1.count }) {
            guard let frame = solveResult.nodeFrames[path], frame.contains(point: center) else { continue }
            bestPath = path
            break
        }
        guard let nodeFrame = solveResult.nodeFrames[bestPath], nodeFrame.width > 0, nodeFrame.height > 0 else {
            camera = .showAll
            return
        }
        // zoom interpolates identity → node-fill. Choose zoom so visible ≈ rect.
        // At zoom t, visible world size ≈ lerp(display, nodeFrame, t) inverted roughly:
        // visibleWidth ≈ display.width / scale where scale = lerp(1, display.w/node.w, t)
        let scaleX = displayRect.width / max(nodeFrame.width, 1)
        let targetScaleX = displayRect.width / max(rect.width, 1)
        // scale(t) = 1 + t * (scaleX - 1)  => t = (targetScale - 1) / (scaleX - 1)
        let t: Double
        if abs(scaleX - 1) < 1e-9 {
            t = 0
        } else {
            t = (targetScaleX - 1) / (scaleX - 1)
        }
        camera = Camera(focusPath: bestPath, zoom: min(max(t, 0), 1))
    }

    // MARK: - Frames at camera

    /// Map solved tree frames through the camera. Return integral frames; park off-screen windows.
    public func framesAt(_ camera: Camera) -> [WindowID: Rect] {
        let world = solveResult.frames
        let transform = viewTransform(for: camera)
        var result: [WindowID: Rect] = [:]
        // Stable parking order.
        let keys = world.keys.sorted { a, b in
            stableKey(a) < stableKey(b)
        }
        var parkIndex = 0
        for id in keys {
            guard let frame = world[id] else { continue }
            let mapped = transform.apply(frame).integralized()
            if mapped.intersects(displayRect) {
                result[id] = mapped
            } else {
                result[id] = parkedFrame(index: parkIndex, size: frame.size)
                parkIndex += 1
            }
        }
        // Floating that may not be in solve as tiled — already in world.
        return result
    }

    /// Frames for the workspace's current camera.
    public func framesAtCamera() -> [WindowID: Rect] {
        framesAt(camera)
    }

    // MARK: - Transform

    struct ViewTransform: Equatable, Sendable {
        var scaleX: Double
        var scaleY: Double
        var translateX: Double
        var translateY: Double

        static let identity = ViewTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0)

        func apply(_ rect: Rect) -> Rect {
            Rect(
                x: rect.x * scaleX + translateX,
                y: rect.y * scaleY + translateY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            )
        }

        func apply(_ point: Point) -> Point {
            Point(x: point.x * scaleX + translateX, y: point.y * scaleY + translateY)
        }

        func inverted() -> ViewTransform {
            let sx = scaleX == 0 ? 1 : 1 / scaleX
            let sy = scaleY == 0 ? 1 : 1 / scaleY
            return ViewTransform(
                scaleX: sx,
                scaleY: sy,
                translateX: -translateX * sx,
                translateY: -translateY * sy
            )
        }
    }

    func viewTransform(for camera: Camera) -> ViewTransform {
        let focusFrame = solveResult.nodeFrames[camera.focusPath] ?? gaps.contentRect(in: displayRect)
        let target = transformMapping(focusFrame, onto: displayRect)
        let t = min(max(camera.zoom, 0), 1)
        return ViewTransform(
            scaleX: 1 + (target.scaleX - 1) * t,
            scaleY: 1 + (target.scaleY - 1) * t,
            translateX: target.translateX * t,
            translateY: target.translateY * t
        )
    }

    private func transformMapping(_ source: Rect, onto dest: Rect) -> ViewTransform {
        guard source.width > 0, source.height > 0 else { return .identity }
        let sx = dest.width / source.width
        let sy = dest.height / source.height
        // Map source.origin → dest.origin
        let tx = dest.x - source.x * sx
        let ty = dest.y - source.y * sy
        return ViewTransform(scaleX: sx, scaleY: sy, translateX: tx, translateY: ty)
    }

    private func screenToWorld(_ point: Point, camera: Camera) -> Point {
        viewTransform(for: camera).inverted().apply(point)
    }

    /// Park just outside the display, stacked to the right (reversible / stable).
    private func parkedFrame(index: Int, size: Size) -> Rect {
        let gap: Double = 8
        let x = displayRect.maxX + gap
        let y = displayRect.y + Double(index) * (size.height + gap)
        return Rect(x: x, y: y, width: size.width, height: size.height).integralized()
    }
}

func stableKey(_ id: WindowID) -> String {
    let cg = id.cgWindowID.map(String.init) ?? "nil"
    return "\(cg)|\(id.processID)|\(id.bundleID ?? "")|\(id.titleFingerprint)"
}
