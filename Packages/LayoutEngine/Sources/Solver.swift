import Foundation
import LayoutModel

/// Minimum size request for a window (points). Legacy AppCore bridge.
public typealias MinSizes = [WindowID: Size]

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

/// Result of solving a workspace tree into frames.
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

/// World-solve entry (node + slot).
public struct WorldEntry: Equatable, Sendable {
    public var node: LayoutNode
    public var slot: WorldSlot

    public init(node: LayoutNode, slot: WorldSlot) {
        self.node = node
        self.slot = slot
    }
}

/// Pure layout solver: tree → placements (ADDENDUM-3 S0–S9).
public enum LayoutSolver {

    // MARK: - Public API

    public static func solve(
        root: LayoutNode,
        cfg: LayoutConfig = .default,
        screen: ScreenGeometry = .golden,
        camera: EdgeRect = .unit,
        framed: NodeID? = nil,
        prevIcons: Set<NodeID> = [],
        prevGroupTiles: Set<NodeID> = []
    ) -> (placements: [NodeID: Placement], slots: [NodeID: WorldSlot]) {
        let prepared = root.normalizedOrDesktop(cfg: cfg)
        let C = screen.contentEdges(cfg: cfg)
        let home = Size(width: C.width, height: C.height)
        let ents = solveWorld(prepared, cfg: cfg, homeSize: home)
        let vis = screen.visible
        var res: [NodeID: Placement] = [:]
        var grouped = Set<NodeID>()

        for (k, en) in ents {
            if case .split = en.node, en.slot.parent != nil, k != framed {
                let t = tileOf(en.slot.world, cam: camera, C: C, cfg: cfg)
                let side = min(t.width, t.height)
                let limit = prevGroupTiles.contains(k) ? Double(cfg.groupTileAbove) : Double(cfg.groupTileBelow)
                if side < limit && !disjoint(t, vis) {
                    grouped.insert(k)
                }
            }
        }

        func underGroupTile(_ k: NodeID) -> NodeID? {
            var p = ents[k]?.slot.parent
            while let cur = p {
                if grouped.contains(cur) { return cur }
                p = ents[cur]?.slot.parent
            }
            return nil
        }

        for (k, en) in ents {
            let n = en.node
            if case .split = n {
                if grouped.contains(k), underGroupTile(k) == nil {
                    res[k] = Placement(id: k, cls: "group-tile", frame: tileOf(en.slot.world, cam: camera, C: C, cfg: cfg), real: nil)
                }
                continue
            }
            if let parent = en.slot.parent, case .tabs = ents[parent]?.node {
                continue
            }
            let t = tileOf(en.slot.world, cam: camera, C: C, cfg: cfg)
            if underGroupTile(k) != nil {
                emitInGroupTile(n, t: t, res: &res)
                continue
            }
            if case .desktop(let d) = n {
                res[k] = Placement(id: k, cls: "desktop", frame: t, real: nil)
                for f in d.floats {
                    placeFloat(f, deskTile: t, cfg: cfg, screen: screen, vis: vis, prevIcons: prevIcons, res: &res)
                }
                continue
            }
            if case .tabs(let g) = n {
                placeTabs(g, t: t, cfg: cfg, screen: screen, vis: vis, prevIcons: prevIcons, res: &res)
                continue
            }
            if case .window(let w) = n {
                placeWindow(w, t: t, cfg: cfg, vis: vis, prevIcons: prevIcons, res: &res)
            }
        }

        var slots: [NodeID: WorldSlot] = [:]
        for (k, en) in ents { slots[k] = en.slot }
        return (res, slots)
    }

    /// Workspace-oriented solve for AppCore.
    public static func solve(
        workspace: Workspace,
        displayRect: Rect,
        gaps: Gaps = .zero,
        minSizes: MinSizes = [:]
    ) -> SolveResult {
        _ = minSizes
        let cfg = workspace.layoutConfig
        let screen = ScreenGeometry(
            visible: displayRect,
            frame: displayRect
        )
        // Ignore legacy Gaps when LayoutConfig is present; keep signature for AppCore.
        _ = gaps
        let (placements, slots) = solve(
            root: workspace.root,
            cfg: cfg,
            screen: screen,
            camera: workspace.camera.edges
        )
        let identities = Self.windowIdentities(in: workspace.root)
        var frames: [WindowID: Rect] = [:]
        for (id, p) in placements {
            let windowID = identities[id] ?? WindowID.named(id)
            if let ax = Self.axFrame(for: p, screen: screen) {
                frames[windowID] = ax
            }
        }
        return SolveResult(frames: frames, placements: placements, slots: slots)
    }

    /// Frame written to AX for a placement (ADDENDUM-3 §5.1 / §5.4).
    public static func axFrame(for placement: Placement, screen: ScreenGeometry) -> Rect? {
        if let real = placement.real { return real }
        switch placement.cls {
        case "live", "float-live", "float-nudged":
            return placement.frame
        case "icon", "clipped", "parked", "in-group-tile", "float-parked", "float-clipped", "float-icon":
            // Park at a display corner; size is tile-floor / last size (use placement frame size).
            return parkFrame(
                screen,
                size: Size(width: max(1, placement.frame.width), height: max(1, placement.frame.height))
            )
        case "hidden-tab":
            return parkFrame(
                screen,
                size: Size(width: max(1, placement.frame.width), height: max(1, placement.frame.height))
            )
        default:
            return nil
        }
    }

    /// Map layout node ids → platform `WindowID` (preserves cgWindowID for AX writes).
    public static func windowIdentities(in root: LayoutNode) -> [NodeID: WindowID] {
        var out: [NodeID: WindowID] = [:]
        func walk(_ node: LayoutNode) {
            switch node {
            case .window(let w):
                out[w.id] = w.identity
            case .tabs(let t):
                for m in t.members { out[m.id] = m.identity }
            case .desktop(let d):
                for f in d.floats { out[f.window.id] = f.window.identity }
            case .split(let s):
                for c in s.children { walk(c) }
            }
        }
        walk(root)
        return out
    }

    public static func solveFrames(
        workspace: Workspace,
        displayRect: Rect,
        gaps: Gaps = .zero,
        minSizes: MinSizes = [:]
    ) -> [WindowID: Rect] {
        solve(workspace: workspace, displayRect: displayRect, gaps: gaps, minSizes: minSizes).frames
    }

    // MARK: - Requirements

    public static func liveMin(_ w: WindowLeaf, cfg: LayoutConfig) -> Size {
        let f = cfg.tileFloor
        if let m = w.appMin {
            return Size(width: max(f.width, m.width), height: max(f.height, m.height))
        }
        return f
    }

    public static func distMin(_ w: WindowLeaf, cfg: LayoutConfig) -> Size {
        LayoutRequirements.distMin(w, cfg: cfg)
    }

    public static func requirement(_ node: LayoutNode, cfg: LayoutConfig) -> Size {
        LayoutRequirements.requirement(node, cfg: cfg)
    }

    public static func maxAlong(_ node: LayoutNode, axis: Axis, cfg: LayoutConfig) -> Double {
        let gx = Double(cfg.gapInnerX), gy = Double(cfg.gapInnerY)
        if case .window(let w) = node, let mx = w.appMax {
            return axis == .horizontal ? mx.width + gx : mx.height + gy
        }
        if case .split(let s) = node, s.axis == axis {
            return s.children.map { maxAlong($0, axis: axis, cfg: cfg) }.reduce(0, +)
        }
        return LayoutMath.inf
    }

    // MARK: - World solve

    public static func solveWorld(
        _ root: LayoutNode,
        cfg: LayoutConfig,
        homeSize: Size
    ) -> [NodeID: WorldEntry] {
        var out: [NodeID: WorldEntry] = [:]

        func rec(_ node: LayoutNode, e: EdgeRect, vs: Size, cum: Double, depth: Int, parent: NodeID?) {
            let req = requirement(node, cfg: cfg)
            var vs = vs
            var cum = cum
            var s = min(1.0, vs.width / req.width, vs.height / req.height)
            if s < 1 - LayoutMath.tol {
                vs = Size(width: vs.width / s, height: vs.height / s)
                cum *= s
            } else {
                s = 1
            }
            let slot = WorldSlot(world: e, vsize: vs, scale: cum, depth: depth, parent: parent)
            out[node.id] = WorldEntry(node: node, slot: slot)

            if case .tabs(let t) = node {
                for w in t.members {
                    out[w.id] = WorldEntry(
                        node: .window(w),
                        slot: WorldSlot(world: e, vsize: vs, scale: cum, depth: depth + 1, parent: node.id)
                    )
                }
            }
            guard case .split(let split) = node else { return }

            let ax = split.axis == .horizontal ? 0 : 1
            let T = ax == 0 ? vs.width : vs.height
            let mins = split.children.map { requirement($0, cfg: cfg) }.map { ax == 0 ? $0.width : $0.height }
            let maxs = split.children.map { maxAlong($0, axis: split.axis, cfg: cfg) }
            let p = ShareSpace.share(total: T, ratios: split.ratios, mins: mins, maxes: maxs)
            var b: [Double] = [0]
            for q in p.dropLast() {
                b.append(b.last! + q / T)
            }
            b.append(1)
            let x0 = e.x0, y0 = e.y0, x1 = e.x1, y1 = e.y1
            for (i, c) in split.children.enumerated() {
                let ce: EdgeRect
                let cvs: Size
                if ax == 0 {
                    ce = EdgeRect(
                        x0: x0 + b[i] * (x1 - x0),
                        y0: y0,
                        x1: x0 + b[i + 1] * (x1 - x0),
                        y1: y1
                    )
                    cvs = Size(width: p[i], height: vs.height)
                } else {
                    ce = EdgeRect(
                        x0: x0,
                        y0: y0 + b[i] * (y1 - y0),
                        x1: x1,
                        y1: y0 + b[i + 1] * (y1 - y0)
                    )
                    cvs = Size(width: vs.width, height: p[i])
                }
                rec(c, e: ce, vs: cvs, cum: cum, depth: depth + 1, parent: node.id)
            }
        }

        rec(root, e: .unit, vs: homeSize, cum: 1, depth: 0, parent: nil)
        return out
    }

    // MARK: - Camera / tile

    public static func toScreen(_ e: EdgeRect, cam: EdgeRect, C: EdgeRect) -> EdgeRect {
        let sx = C.width / (cam.x1 - cam.x0)
        let sy = C.height / (cam.y1 - cam.y0)
        return EdgeRect(
            x0: C.x0 + (e.x0 - cam.x0) * sx,
            y0: C.y0 + (e.y0 - cam.y0) * sy,
            x1: C.x0 + (e.x1 - cam.x0) * sx,
            y1: C.y0 + (e.y1 - cam.y0) * sy
        )
    }

    public static func tileOf(_ e: EdgeRect, cam: EdgeRect, C: EdgeRect, cfg: LayoutConfig) -> Rect {
        let s = toScreen(e, cam: cam, C: C)
        let x0 = LayoutMath.rnd(s.x0)
        let y0 = LayoutMath.rnd(s.y0)
        let x1 = LayoutMath.rnd(s.x1)
        let y1 = LayoutMath.rnd(s.y1)
        let hl = Double(cfg.gapInnerX / 2)
        let hr = Double(cfg.gapInnerX - cfg.gapInnerX / 2)
        let ht = Double(cfg.gapInnerY / 2)
        let hb = Double(cfg.gapInnerY - cfg.gapInnerY / 2)
        var tx0 = x0 + hl, ty0 = y0 + ht, tx1 = x1 - hr, ty1 = y1 - hb
        tx1 = max(tx1, tx0)
        ty1 = max(ty1, ty0)
        return Rect(x: tx0, y: ty0, width: tx1 - tx0, height: ty1 - ty0)
    }

    // MARK: - Classification helpers

    public static func disjoint(_ r: Rect, _ vis: Rect) -> Bool {
        r.maxX <= vis.x || r.maxY <= vis.y || r.x >= vis.maxX || r.y >= vis.maxY || r.width <= 0 || r.height <= 0
    }

    public static func parkFrame(_ screen: ScreenGeometry, size: Size) -> Rect {
        let fx = screen.frame.x, fy = screen.frame.y, fw = screen.frame.width, fh = screen.frame.height
        return Rect(x: fx + fw - 1, y: fy + fh - 1, width: size.width, height: size.height)
    }

    public static func visibleFraction(_ r: Rect, _ vis: Rect) -> Double {
        if r.width <= 0 || r.height <= 0 { return 0 }
        let ix = max(0, min(r.maxX, vis.maxX) - max(r.x, vis.x))
        let iy = max(0, min(r.maxY, vis.maxY) - max(r.y, vis.y))
        return ix * iy / (r.width * r.height)
    }

    public static func intersect(_ a: Rect, _ b: Rect) -> Rect {
        let x0 = max(a.x, b.x), y0 = max(a.y, b.y)
        let x1 = min(a.maxX, b.maxX), y1 = min(a.maxY, b.maxY)
        return Rect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    public static func desktopUsable(_ deskTile: Rect, vis: Rect, cfg: LayoutConfig) -> Bool {
        let r = intersect(deskTile, vis)
        return r.width >= cfg.desktopMinSize.width && r.height >= cfg.desktopMinSize.height
    }

    public static func nudgeInto(_ r: Rect, area: Rect) -> Rect {
        var out = r
        // x axis
        if r.width > area.width {
            out.x = area.x + floor((area.width - r.width) / 2)
        } else {
            out.x = min(max(r.x, area.x), area.x + area.width - r.width)
        }
        // y axis
        if r.height > area.height {
            out.y = area.y + floor((area.height - r.height) / 2)
        } else {
            out.y = min(max(r.y, area.y), area.y + area.height - r.height)
        }
        return out
    }

    public static func realFrame(_ w: WindowLeaf, _ t: Rect) -> Rect {
        if let mx = w.appMax, t.width > mx.width || t.height > mx.height {
            let mw = min(t.width, mx.width)
            let mh = min(t.height, mx.height)
            let x = t.x + floor((t.width - mw) / 2)
            let y = t.y + floor((t.height - mh) / 2)
            return Rect(x: x, y: y, width: mw, height: mh)
        }
        return t
    }

    public static func classify(
        _ w: WindowLeaf,
        t: Rect,
        cfg: LayoutConfig,
        vis: Rect,
        prevIcons: Set<NodeID>
    ) -> String {
        let f = visibleFraction(t, vis)
        if f <= 0 { return "parked" }
        if f < cfg.liveVisibleFraction - LayoutMath.tol { return "clipped" }
        let m = liveMin(w, cfg: cfg)
        let slack = prevIcons.contains(w.id) ? 0.0 : Double(cfg.iconTileSlack)
        if t.width < m.width - slack || t.height < m.height - slack {
            return "icon"
        }
        return "live"
    }

    public static func tabBarPx(_ t: Rect, cfg: LayoutConfig) -> Double {
        var k = min(1.0, t.width / cfg.tabBarRefSize.width, t.height / cfg.tabBarRefSize.height)
        k = max(cfg.tabBarMinScale, k)
        return LayoutMath.rnd(Double(cfg.tabBarHeight) * k)
    }

    // MARK: - Place

    private static func emitInGroupTile(_ n: LayoutNode, t: Rect, res: inout [NodeID: Placement]) {
        let ws: [WindowLeaf]
        switch n {
        case .tabs(let g): ws = g.members
        case .window(let w): ws = [w]
        default: ws = []
        }
        for w in ws {
            res[w.id] = Placement(id: w.id, cls: "in-group-tile", frame: t, real: nil)
        }
    }

    private static func placeWindow(
        _ w: WindowLeaf,
        t: Rect,
        cfg: LayoutConfig,
        vis: Rect,
        prevIcons: Set<NodeID>,
        res: inout [NodeID: Placement]
    ) {
        let c = classify(w, t: t, cfg: cfg, vis: vis, prevIcons: prevIcons)
        let real = c == "live" ? realFrame(w, t) : nil
        res[w.id] = Placement(id: w.id, cls: c, frame: t, real: real)
    }

    private static func placeTabs(
        _ g: TabGroup,
        t: Rect,
        cfg: LayoutConfig,
        screen: ScreenGeometry,
        vis: Rect,
        prevIcons: Set<NodeID>,
        res: inout [NodeID: Placement]
    ) {
        let sh = tabBarPx(t, cfg: cfg)
        let content = Rect(x: t.x, y: t.y + sh, width: t.width, height: max(0, t.height - sh))
        let act = g.members[g.active]
        if sh < Double(cfg.tabBarHideBelow) {
            res[g.id] = Placement(id: g.id, cls: "icon", frame: t, real: nil)
            for w in g.members {
                res[w.id] = Placement(id: w.id, cls: "icon", frame: t, real: nil)
            }
            return
        }
        res[g.id] = Placement(id: g.id, cls: "tab-bar", frame: Rect(x: t.x, y: t.y, width: t.width, height: sh), real: nil)
        let c = classify(act, t: content, cfg: cfg, vis: vis, prevIcons: prevIcons)
        res[act.id] = Placement(
            id: act.id,
            cls: c,
            frame: content,
            real: c == "live" ? realFrame(act, content) : nil
        )
        for w in g.members where w.id != act.id {
            res[w.id] = Placement(
                id: w.id,
                cls: "hidden-tab",
                frame: content,
                real: parkFrame(screen, size: Size(width: content.width, height: content.height))
            )
        }
    }

    private static func placeFloat(
        _ f: FloatWin,
        deskTile: Rect,
        cfg: LayoutConfig,
        screen: ScreenGeometry,
        vis: Rect,
        prevIcons: Set<NodeID>,
        res: inout [NodeID: Placement]
    ) {
        _ = screen
        _ = prevIcons
        let x = deskTile.x, y = deskTile.y, w = deskTile.width, h = deskTile.height
        let fx0 = f.frac.x0, fy0 = f.frac.y0, fx1 = f.frac.x1, fy1 = f.frac.y1
        let e0 = LayoutMath.rnd(x + fx0 * w)
        let e1 = LayoutMath.rnd(y + fy0 * h)
        let e2 = LayoutMath.rnd(x + fx1 * w)
        let e3 = LayoutMath.rnd(y + fy1 * h)
        let r = Rect(x: e0, y: e1, width: e2 - e0, height: e3 - e1)
        if visibleFraction(r, vis) <= 0 {
            res[f.window.id] = Placement(id: f.window.id, cls: "float-parked", frame: r, real: nil)
            return
        }
        if !desktopUsable(deskTile, vis: vis, cfg: cfg) {
            let c = visibleFraction(r, vis) >= cfg.liveVisibleFraction - LayoutMath.tol ? "live" : "clipped"
            res[f.window.id] = Placement(
                id: f.window.id,
                cls: "float-" + c,
                frame: r,
                real: c == "live" ? r : nil
            )
            return
        }
        let real = cfg.floatNudgeIn ? nudgeInto(r, area: intersect(deskTile, vis)) : r
        let c = real == r ? "live" : "nudged"
        res[f.window.id] = Placement(id: f.window.id, cls: "float-" + c, frame: r, real: real)
    }

    // MARK: - Pinch settle

    public static func settleTarget(
        root: LayoutNode,
        cfg: LayoutConfig,
        homeSize: Size,
        cam: EdgeRect,
        pointer: Point
    ) -> NodeID {
        let slots = solveWorld(root, cfg: cfg, homeSize: homeSize)
        func area(_ e: EdgeRect) -> Double {
            e.width * homeSize.width * e.height * homeSize.height
        }
        let ca = area(cam)
        var best: (key: (Double, Int), id: NodeID)?
        for (k, en) in slots {
            if case .window = en.node, let p = en.slot.parent, case .tabs = slots[p]?.node {
                continue
            }
            let e = en.slot.world
            if !(e.x0 <= pointer.x && pointer.x <= e.x1 && e.y0 <= pointer.y && pointer.y <= e.y1) {
                continue
            }
            let key = (abs(area(e) - ca), -en.slot.depth)
            if best == nil || key.0 < best!.key.0 || (key.0 == best!.key.0 && key.1 < best!.key.1) {
                best = (key, k)
            }
        }
        return best!.id
    }
}

/// Expose WorldEntry for tests that need settle/seam.
extension LayoutSolver {
    public static func worldEntries(
        _ root: LayoutNode,
        cfg: LayoutConfig,
        homeSize: Size
    ) -> [NodeID: WorldSlot] {
        var out: [NodeID: WorldSlot] = [:]
        for (k, e) in solveWorld(root, cfg: cfg, homeSize: homeSize) {
            out[k] = e.slot
        }
        return out
    }
}
