import Foundation

/// Result of locating a node by id.
public struct NodeLocation: Equatable, Sendable {
    public var node: LayoutNode
    /// Parent split or tab group, if any.
    public var parent: LayoutNode?
    public var index: Int?

    public init(node: LayoutNode, parent: LayoutNode? = nil, index: Int? = nil) {
        self.node = node
        self.parent = parent
        self.index = index
    }
}

public enum TreeOps {
    /// Return location of `target` id, or nil.
    public static func find(_ node: LayoutNode, target: NodeID, parent: LayoutNode? = nil, index: Int? = nil) -> NodeLocation? {
        if node.id == target {
            return NodeLocation(node: node, parent: parent, index: index)
        }
        switch node {
        case .tabs(let tabs):
            for (i, w) in tabs.members.enumerated() where w.id == target {
                return NodeLocation(node: .window(w), parent: node, index: i)
            }
        case .split(let split):
            for (i, c) in split.children.enumerated() {
                if let r = find(c, target: target, parent: node, index: i) {
                    return r
                }
            }
        case .desktop(let d):
            for (i, f) in d.floats.enumerated() where f.window.id == target {
                return NodeLocation(node: .window(f.window), parent: node, index: i)
            }
        case .window:
            break
        }
        return nil
    }

    public static func replace(_ root: LayoutNode, oldID: NodeID, with new: LayoutNode) -> LayoutNode {
        if root.id == oldID { return new }
        if case .split(var split) = root {
            split.children = split.children.map { replace($0, oldID: oldID, with: new) }
            return .split(split)
        }
        return root
    }

    // MARK: - O1 Insert at edge

    public static func insertAtEdge(
        _ root: LayoutNode,
        targetID: NodeID,
        edge: Edge,
        new newNode: LayoutNode,
        cfg: LayoutConfig
    ) -> LayoutNode {
        var root = root
        var newNode = newNode
        let axis = edge.splitAxis
        let before = edge.placesNewFirst

        guard var loc = find(root, target: targetID) else { return root }

        // Docking beside a tab member means beside the group.
        if case .tabs = loc.parent {
            if let groupLoc = find(root, target: loc.parent!.id) {
                loc = groupLoc
            }
        }

        let target = loc.node
        if case .window(var w) = newNode {
            w.donor = target.id
            newNode = .window(w)
        }

        let rho = LayoutMath.clamp(cfg.insertRatio, cfg.insertRatioMin, cfg.insertRatioMax)

        if case .split(var parent) = loc.parent, parent.axis == axis, let i = loc.index {
            // Sibling case — mutate parent copy, write back by id.
            let j = before ? i : i + 1
            if cfg.insertTakesFrom == .row {
                let n = parent.children.count
                parent.ratios = parent.ratios.map { $0 * Double(n) / Double(n + 1) }
                parent.ratios.insert(1.0 / Double(n + 1), at: j)
            } else {
                let rt = parent.ratios[i]
                parent.ratios[i] = rt * (1 - rho)
                parent.ratios.insert(rt * rho, at: j)
            }
            parent.children.insert(newNode, at: j)
            root = replace(root, oldID: parent.id, with: .split(parent))
        } else {
            let kids: [LayoutNode] = before ? [newNode, target] : [target, newNode]
            let rats: [Double] = before ? [rho, 1 - rho] : [1 - rho, rho]
            let wrapped = LayoutNode.split(Split(axis: axis, children: kids, ratios: rats))
            root = replace(root, oldID: target.id, with: wrapped)
        }

        return root.normalizedOrDesktop(cfg: cfg)
    }

    public static func insertAtScreenEdge(
        _ root: LayoutNode,
        edge: Edge,
        new: LayoutNode,
        cfg: LayoutConfig
    ) -> LayoutNode {
        insertAtEdge(root, targetID: root.id, edge: edge, new: new, cfg: cfg)
    }

    // MARK: - O5 Tab onto

    public static func tabOnto(
        _ root: LayoutNode,
        targetID: NodeID,
        win: WindowLeaf,
        cfg: LayoutConfig
    ) -> LayoutNode {
        guard let loc = find(root, target: targetID) else { return root }
        var target = loc.node
        if case .tabs = loc.parent {
            target = loc.parent!
        }
        if case .tabs(var g) = target {
            g.members.append(win)
            g.active = g.members.count - 1
            return replace(root, oldID: g.id, with: .tabs(g))
        }
        // Target is a window leaf (or other): wrap into tab group.
        if case .window(let w) = target {
            let g = TabGroup(id: "g-\(w.id)", members: [w, win], active: 1)
            return replace(root, oldID: w.id, with: .tabs(g)).normalizedOrDesktop(cfg: cfg)
        }
        return root
    }

    // MARK: - O6 Remove

    public static func remove(_ root: LayoutNode, windowID: NodeID, cfg: LayoutConfig) -> LayoutNode? {
        guard let loc = find(root, target: windowID) else { return root }
        guard let parentNode = loc.parent, let i = loc.index else {
            return nil
        }

        if case .tabs(var tabs) = parentNode {
            tabs.members.remove(at: i)
            if i < tabs.active {
                tabs.active -= 1
            } else if i == tabs.active {
                tabs.active = min(i, max(0, tabs.members.count - 1))
            }
            let updated: LayoutNode = .tabs(tabs)
            let newRoot = replace(root, oldID: tabs.id, with: updated)
            return newRoot.normalized(cfg: cfg)
        }

        if case .desktop(var desk) = parentNode {
            desk.floats.remove(at: i)
            return replace(root, oldID: desk.id, with: .desktop(desk)).normalized(cfg: cfg)
        }

        guard case .split(var parent) = parentNode else { return root }
        let removedNode = loc.node
        let r = parent.ratios.remove(at: i)
        parent.children.remove(at: i)

        if !parent.children.isEmpty && cfg.closeGivesTo == .donor {
            let donor: NodeID?
            if case .window(let w) = removedNode {
                donor = w.donor
            } else {
                donor = nil
            }
            // old left / right neighbour
            for k in [i - 1, i] {
                if k >= 0, k < parent.children.count, let donor,
                   find(parent.children[k], target: donor) != nil {
                    parent.ratios[k] += r
                    break
                }
            }
        } else if !parent.children.isEmpty && cfg.closeGivesTo == .neighbour {
            let k = i < parent.children.count ? i : i - 1
            if parent.ratios.indices.contains(k) {
                parent.ratios[k] += r
            }
        }
        // 'row': proportional renormalisation happens in normalize()

        let newRoot = root.id == parent.id ? LayoutNode.split(parent) : replace(root, oldID: parent.id, with: .split(parent))
        return newRoot.normalized(cfg: cfg)
    }

    // MARK: - O7 Seam resize

    /// Move the seam between children `i` and `i+1` of `splitID` by `delta` points
    /// (in the split's own points). Caller supplies world solve slots.
    public static func seamResize(
        _ root: LayoutNode,
        slots: [NodeID: WorldSlot],
        splitID: NodeID,
        index i: Int,
        delta: Double,
        cfg: LayoutConfig
    ) -> LayoutNode {
        guard let loc = find(root, target: splitID), case .split(var sp) = loc.node else {
            return root
        }
        guard let en = slots[splitID] else { return root }
        let ax = sp.axis == .horizontal ? 0 : 1
        let T = ax == 0 ? en.vsize.width : en.vsize.height
        let world = en.world
        let worldSpan = ax == 0 ? world.width : world.height

        var p: [Double] = sp.children.map { c in
            guard let ce = slots[c.id] else { return 0 }
            let childSpan = ax == 0 ? ce.world.width : ce.world.height
            return childSpan / worldSpan * T
        }
        let lo: [Double] = sp.children.map { c in
            let req = LayoutRequirements.requirement(c, cfg: cfg)
            let m = ax == 0 ? req.width : req.height
            return max(m, cfg.minRatio * T)
        }
        let pair = p[i] + p[i + 1]
        let a = LayoutMath.clamp(p[i] + delta, lo[i], pair - lo[i + 1])
        p[i] = a
        p[i + 1] = pair - a
        sp.ratios = p.map { $0 / T }
        return root.id == sp.id ? .split(sp) : replace(root, oldID: sp.id, with: .split(sp))
    }

    // MARK: - O8 Set axis

    public static func setAxis(
        _ root: LayoutNode,
        splitID: NodeID,
        axis: Axis?,
        cfg: LayoutConfig
    ) -> LayoutNode {
        guard let loc = find(root, target: splitID), case .split(var sp) = loc.node else {
            return root
        }
        if let axis {
            sp.axis = axis
        } else {
            sp.axis = sp.axis == .horizontal ? .vertical : .horizontal
        }
        let updated = root.id == sp.id ? LayoutNode.split(sp) : replace(root, oldID: sp.id, with: .split(sp))
        return updated.normalizedOrDesktop(cfg: cfg)
    }

    // MARK: - O9/O10 Desktop hide/show

    public static func desktopAreaHide(
        _ root: LayoutNode,
        cfg: LayoutConfig
    ) -> (LayoutNode, DesktopMemory?) {
        guard let loc = find(root, target: "desktop") else { return (root, nil) }
        guard case .desktop(let d) = loc.node else { return (root, nil) }
        guard case .split(var parent) = loc.parent, let i = loc.index else {
            return (root, nil) // desktop is the whole workspace
        }
        let mem = DesktopMemory(
            ratio: parent.ratios[i],
            axis: parent.axis,
            parent: parent.id,
            index: i,
            neighbours: parent.children.compactMap { $0.id == d.id ? nil : $0.id },
            desk: d
        )
        parent.children.remove(at: i)
        parent.ratios.remove(at: i)
        let newRoot = root.id == parent.id ? LayoutNode.split(parent) : replace(root, oldID: parent.id, with: .split(parent))
        return (newRoot.normalizedOrDesktop(cfg: cfg), mem)
    }

    public static func desktopAreaShow(
        _ root: LayoutNode,
        memory mem: DesktopMemory?,
        cfg: LayoutConfig,
        side: Edge = .right
    ) -> LayoutNode {
        let d = mem?.desk ?? DesktopArea()
        if let mem, let parentID = mem.parent, find(root, target: parentID) != nil,
           case .split(var sp) = find(root, target: parentID)!.node {
            let r = mem.ratio
            sp.ratios = sp.ratios.map { $0 * (1 - r) }
            let j = min(mem.index, sp.children.count)
            sp.children.insert(.desktop(d), at: j)
            sp.ratios.insert(r, at: j)
            let updated = root.id == sp.id ? LayoutNode.split(sp) : replace(root, oldID: sp.id, with: .split(sp))
            return updated.normalizedOrDesktop(cfg: cfg)
        }
        if let mem {
            let alive = mem.neighbours.filter { find(root, target: $0) != nil }
            if mem.neighbours.count == 1, let first = alive.first,
               let nb = find(root, target: first)?.node {
                let r = mem.ratio
                let kids: [LayoutNode]
                let rats: [Double]
                if mem.index == 0 {
                    kids = [.desktop(d), nb]
                    rats = [r, 1 - r]
                } else {
                    kids = [nb, .desktop(d)]
                    rats = [1 - r, r]
                }
                let wrapped = LayoutNode.split(Split(axis: mem.axis, children: kids, ratios: rats))
                return replace(root, oldID: nb.id, with: wrapped).normalizedOrDesktop(cfg: cfg)
            }
        }
        let r = cfg.desktopReshowRatio
        let kids: [LayoutNode]
        let rats: [Double]
        if side == .right {
            kids = [root, .desktop(d)]
            rats = [1 - r, r]
        } else {
            kids = [.desktop(d), root]
            rats = [r, 1 - r]
        }
        return LayoutNode.split(Split(axis: .horizontal, children: kids, ratios: rats))
            .normalizedOrDesktop(cfg: cfg)
    }

    // MARK: - O12 Dock all

    public static func dockAll(
        _ root: LayoutNode,
        floatsInXOrder: [WindowLeaf],
        cfg: LayoutConfig
    ) -> LayoutNode {
        var rowCfg = cfg
        rowCfg.insertTakesFrom = .row
        var root = root
        for w in floatsInXOrder {
            // Remove from desktop floats if present, then dock left of desktop.
            if let removed = remove(root, windowID: w.id, cfg: cfg) {
                root = removed
            }
            root = insertAtEdge(root, targetID: "desktop", edge: .left, new: .window(w), cfg: rowCfg)
        }
        return root
    }

    // MARK: - O13 Unmanage all

    public static func unmanageAll(
        _ root: LayoutNode,
        placements: [NodeID: PlacementFrame],
        screen: ScreenGeometry,
        cfg: LayoutConfig
    ) -> LayoutNode {
        let old = find(root, target: "desktop")
        var d = DesktopArea(floats: [])
        if case .desktop(let desk) = old?.node {
            d.floats = desk.floats
        }
        // Full-desktop tile for clamping.
        let tileSolve = PlacementFrame.desktopOnlyTile(screen: screen, cfg: cfg)
        let tx = tileSolve.x, ty = tileSolve.y, tw = tileSolve.width, th = tileSolve.height

        func leaves(_ n: LayoutNode) -> [WindowLeaf] {
            switch n {
            case .window(let w): return [w]
            case .tabs(let t): return t.members
            case .split(let s): return s.children.flatMap(leaves)
            case .desktop: return []
            }
        }

        for w in leaves(root) {
            guard let p = placements[w.id] else { continue }
            var x = p.real?.x ?? p.frame.x
            var y = p.real?.y ?? p.frame.y
            var ww = p.real?.width ?? p.frame.width
            var hh = p.real?.height ?? p.frame.height
            if p.cls != "live" {
                x = p.frame.x; y = p.frame.y; ww = p.frame.width; hh = p.frame.height
            }
            ww = min(ww, tw)
            hh = min(hh, th)
            x = LayoutMath.clamp(x, tx, tx + tw - ww)
            y = LayoutMath.clamp(y, ty, ty + th - hh)
            d.floats.append(FloatWin(
                window: w,
                frac: (
                    (x - tx) / tw,
                    (y - ty) / th,
                    (x + ww - tx) / tw,
                    (y + hh - ty) / th
                )
            ))
        }
        return .desktop(d)
    }

    // MARK: - Float reflow (O14 helper)

    public static func reflowFloats(
        oldTile: Rect,
        newTile: Rect,
        floats: [FloatWin],
        cfg: LayoutConfig
    ) -> [FloatWin] {
        let ox = oldTile.x, oy = oldTile.y, ow = oldTile.width, oh = oldTile.height
        let nx = newTile.x, ny = newTile.y, nw = newTile.width, nh = newTile.height
        let m = Double(cfg.floatMargin)
        var out: [FloatWin] = []
        for f in floats {
            let x0 = f.frac.x0, y0 = f.frac.y0, x1 = f.frac.x1, y1 = f.frac.y1
            let ex0 = LayoutMath.rnd(ox + x0 * ow)
            let ey0 = LayoutMath.rnd(oy + y0 * oh)
            let ex1 = LayoutMath.rnd(ox + x1 * ow)
            let ey1 = LayoutMath.rnd(oy + y1 * oh)
            var w = ex1 - ex0
            var h = ey1 - ey0
            let cx = ((ex0 + ex1) / 2 - ox) / ow
            let cy = ((ey0 + ey1) / 2 - oy) / oh
            w = min(w, nw - 2 * m)
            h = min(h, nh - 2 * m)
            var x = LayoutMath.clamp(nx + cx * nw - w / 2, nx + m, nx + nw - m - w)
            var y = LayoutMath.clamp(ny + cy * nh - h / 2, ny + m, ny + nh - m - h)
            x = LayoutMath.rnd(x)
            y = LayoutMath.rnd(y)
            w = LayoutMath.rnd(w)
            h = LayoutMath.rnd(h)
            out.append(FloatWin(
                window: f.window,
                frac: (
                    (x - nx) / nw,
                    (y - ny) / nh,
                    (x + w - nx) / nw,
                    (y + h - ny) / nh
                )
            ))
        }
        return out
    }

    public static func newFloatFrac(
        deskTile: Rect,
        size: Size?,
        existing: [(Double, Double)],
        cfg: LayoutConfig
    ) -> (EdgeRect, Rect) {
        let x = deskTile.x, y = deskTile.y, w = deskTile.width, h = deskTile.height
        let pad = Double(cfg.floatMargin)
        let cw = cfg.floatMaxFraction * w
        let ch = cfg.floatMaxFraction * h
        var sw: Double
        var sh: Double
        if let size {
            sw = size.width
            sh = size.height
        } else {
            sw = 0.55 * w
            sh = 0.55 * h
        }
        let k = min(1.0, cw / sw, ch / sh)
        sw = LayoutMath.rnd(sw * k)
        sh = LayoutMath.rnd(sh * k)
        var fx = x + (w - sw) / 2
        var fy = y + (h - sh) / 2
        var taken = Set(existing.map { (LayoutMath.rnd($0.0), LayoutMath.rnd($0.1)) }.map { "\($0.0),\($0.1)" })
        while taken.contains("\(LayoutMath.rnd(fx)),\(LayoutMath.rnd(fy))") {
            fx += Double(cfg.floatCascade)
            fy += Double(cfg.floatCascade)
        }
        fx = LayoutMath.clamp(fx, x + pad, x + w - pad - sw)
        fy = LayoutMath.clamp(fy, y + pad, y + h - pad - sh)
        fx = LayoutMath.rnd(fx)
        fy = LayoutMath.rnd(fy)
        let frac = EdgeRect(
            x0: (fx - x) / w,
            y0: (fy - y) / h,
            x1: (fx + sw - x) / w,
            y1: (fy + sh - y) / h
        )
        return (frac, Rect(x: fx, y: fy, width: sw, height: sh))
    }
}

/// World-solve slot used by seam resize (defined here so LayoutModel ops compile;
/// LayoutEngine fills these).
public struct WorldSlot: Equatable, Sendable {
    public var world: EdgeRect
    public var vsize: Size
    public var scale: Double
    public var depth: Int
    public var parent: NodeID?

    public init(world: EdgeRect, vsize: Size, scale: Double, depth: Int, parent: NodeID?) {
        self.world = world
        self.vsize = vsize
        self.scale = scale
        self.depth = depth
        self.parent = parent
    }
}

/// Lightweight placement frame for O13 (full Placement lives in LayoutEngine).
public struct PlacementFrame: Equatable, Sendable {
    public var cls: String
    public var frame: Rect
    public var real: Rect?

    public init(cls: String, frame: Rect, real: Rect? = nil) {
        self.cls = cls
        self.frame = frame
        self.real = real
    }

    /// Desktop-only tile on a screen (used by unmanage-all).
    public static func desktopOnlyTile(screen: ScreenGeometry, cfg: LayoutConfig) -> Rect {
        // Content edges → home camera tile of unit square.
        let C = screen.contentEdges(cfg: cfg)
        let hl = cfg.gapInnerX / 2
        let hr = cfg.gapInnerX - hl
        let ht = cfg.gapInnerY / 2
        let hb = cfg.gapInnerY - ht
        let x0 = LayoutMath.rnd(C.x0)
        let y0 = LayoutMath.rnd(C.y0)
        let x1 = LayoutMath.rnd(C.x1)
        let y1 = LayoutMath.rnd(C.y1)
        let tx0 = x0 + Double(hl)
        let ty0 = y0 + Double(ht)
        let tx1 = max(x1 - Double(hr), tx0)
        let ty1 = max(y1 - Double(hb), ty0)
        return Rect(x: tx0, y: ty0, width: tx1 - tx0, height: ty1 - ty0)
    }
}

/// Display geometry for ops that need a screen (O11/O13).
public struct ScreenGeometry: Equatable, Sendable {
    /// Visible frame `(x, y, w, h)`.
    public var visible: Rect
    /// Full display frame.
    public var frame: Rect

    public init(visible: Rect, frame: Rect) {
        self.visible = visible
        self.frame = frame
    }

    public static let golden = ScreenGeometry(
        visible: Rect(x: 0, y: 25, width: 1440, height: 875),
        frame: Rect(x: 0, y: 0, width: 1440, height: 900)
    )

    public func contentEdges(cfg: LayoutConfig) -> EdgeRect {
        let vx = visible.x, vy = visible.y, vw = visible.width, vh = visible.height
        let ol = Double(cfg.gapOuter.left), ot = Double(cfg.gapOuter.top)
        let orr = Double(cfg.gapOuter.right), ob = Double(cfg.gapOuter.bottom)
        let hl = Double(cfg.gapInnerX / 2)
        let hr = Double(cfg.gapInnerX - cfg.gapInnerX / 2)
        let ht = Double(cfg.gapInnerY / 2)
        let hb = Double(cfg.gapInnerY - cfg.gapInnerY / 2)
        return EdgeRect(
            x0: vx + ol - hl,
            y0: vy + ot - ht,
            x1: vx + vw - orr + hr,
            y1: vy + vh - ob + hb
        )
    }
}

/// Remembered desktop-area placement for hide/show.
public struct DesktopMemory: Equatable, Codable, Sendable {
    public var ratio: Double
    public var axis: Axis
    public var parent: NodeID?
    public var index: Int
    public var neighbours: [NodeID]
    public var desk: DesktopArea

    public init(
        ratio: Double,
        axis: Axis,
        parent: NodeID?,
        index: Int,
        neighbours: [NodeID],
        desk: DesktopArea
    ) {
        self.ratio = ratio
        self.axis = axis
        self.parent = parent
        self.index = index
        self.neighbours = neighbours
        self.desk = desk
    }
}

/// Requirement helpers used by seam resize (full measure lives in LayoutEngine too).
public enum LayoutRequirements {
    public static func distMin(_ w: WindowLeaf, cfg: LayoutConfig) -> Size {
        let f = cfg.tileFloor
        if cfg.shrinkPastAppMinimum { return f }
        let k = w.appMin ?? cfg.fallbackMinSize
        return Size(width: max(f.width, k.width), height: max(f.height, k.height))
    }

    public static func requirement(_ node: LayoutNode, cfg: LayoutConfig) -> Size {
        let gx = Double(cfg.gapInnerX), gy = Double(cfg.gapInnerY)
        switch node {
        case .window(let w):
            let m = distMin(w, cfg: cfg)
            return Size(width: m.width + gx, height: m.height + gy)
        case .tabs(let t):
            let ms = t.members.map { distMin($0, cfg: cfg) }
            let mw = ms.map(\.width).max() ?? 0
            let mh = ms.map(\.height).max() ?? 0
            return Size(width: mw + gx, height: mh + Double(cfg.tabBarHeight) + gy)
        case .desktop:
            return Size(
                width: cfg.desktopMinSize.width + gx,
                height: cfg.desktopMinSize.height + gy
            )
        case .split(let s):
            let reqs = s.children.map { requirement($0, cfg: cfg) }
            if s.axis == .horizontal {
                return Size(
                    width: reqs.map(\.width).reduce(0, +),
                    height: reqs.map(\.height).max() ?? 0
                )
            }
            return Size(
                width: reqs.map(\.width).max() ?? 0,
                height: reqs.map(\.height).reduce(0, +)
            )
        }
    }
}
