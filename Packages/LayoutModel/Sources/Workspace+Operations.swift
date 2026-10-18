import Foundation

extension Workspace {
    // MARK: - WindowID bridges (AppCore)

    public func contains(_ id: WindowID) -> Bool { contains(id.nodeID) }
    public func isFloating(_ id: WindowID) -> Bool { isFloating(id.nodeID) }
    public func state(of id: WindowID) -> WindowState { state(of: id.nodeID) }
    public mutating func setState(_ state: WindowState, for id: WindowID) {
        setState(state, for: id.nodeID)
    }

    public func inserting(_ window: WindowID, at target: DropTarget) -> (Workspace, LayoutDiff) {
        // Preserve platform identity (cgWindowID / pid). `WindowLeaf(id:)` uses `.named` and drops it.
        inserting(window.nodeID, at: target, leaf: WindowLeaf(identity: window))
    }

    /// Insert a new float into the desktop area (ADDENDUM-2 B1 / ADDENDUM-3 O4).
    public func insertingFloat(
        _ window: WindowID,
        natural: Size?,
        desktopTile: Rect,
        cfg: LayoutConfig? = nil
    ) -> (Workspace, LayoutDiff) {
        var next = self
        let layoutCfg = cfg ?? next.layoutConfig
        if next.contains(window) {
            if let removed = TreeOps.remove(next.root, windowID: window.nodeID, cfg: layoutCfg) {
                next.root = removed
            }
        }
        let existing: [(Double, Double)] = next.floatWins.map {
            let t = desktopTile
            let x = t.x + $0.frac.x0 * t.width
            let y = t.y + $0.frac.y0 * t.height
            return (x, y)
        }
        let (frac, _) = TreeOps.newFloatFrac(
            deskTile: desktopTile,
            size: natural,
            existing: existing,
            cfg: layoutCfg
        )
        guard let deskLoc = TreeOps.find(next.root, target: "desktop"),
              case .desktop(var d) = deskLoc.node else {
            next.root = .desktop(DesktopArea(floats: [
                FloatWin(window: WindowLeaf(identity: window), frac: frac)
            ]))
            return (next, LayoutDiff(floated: [window.nodeID]))
        }
        d.floats.append(FloatWin(window: WindowLeaf(identity: window), frac: frac))
        next.root = TreeOps.replace(next.root, oldID: d.id, with: .desktop(d))
        return (next, LayoutDiff(floated: [window.nodeID]))
    }

    public func removing(_ window: WindowID) -> (Workspace, LayoutDiff) {
        removing(window.nodeID)
    }

    public func moving(_ window: WindowID, to target: DropTarget) -> (Workspace, LayoutDiff) {
        moving(window.nodeID, to: target)
    }

    public func tabbing(_ window: WindowID, onto target: WindowID) -> (Workspace, LayoutDiff) {
        tabbing(window.nodeID, onto: target.nodeID)
    }

    public func floating(_ window: WindowID, frame: Rect) -> (Workspace, LayoutDiff) {
        floating(window.nodeID, frame: frame)
    }

    public func docking(_ window: WindowID, at target: DropTarget) -> (Workspace, LayoutDiff) {
        docking(window.nodeID, at: target)
    }

    public func untabbing(_ window: WindowID) -> (Workspace, LayoutDiff) {
        untabbing(window.nodeID)
    }

    public func untabbing(_ window: NodeID) -> (Workspace, LayoutDiff) {
        guard let path = root.path(to: window),
              let node = root.node(at: path),
              case .tabs(let tabs) = node,
              tabs.members.contains(where: { $0.id == window }),
              tabs.members.count >= 2 else {
            return (self, .empty)
        }
        var next = self
        var remaining = tabs.members.filter { $0.id != window }
        let extracted = tabs.members.first { $0.id == window }!
        let rest: LayoutNode = remaining.count == 1
            ? .window(remaining[0])
            : .tabs(TabGroup(id: tabs.id, members: remaining, active: min(tabs.active, remaining.count - 1)))
        let split = Split.equal(axis: .horizontal, children: [.window(extracted), rest])
        if let updated = next.root.replacing(at: path, with: .split(split)) {
            next.root = updated.normalizedOrDesktop(cfg: next.layoutConfig)
        }
        return (next, LayoutDiff(moved: [window]))
    }

    /// Insert `window` at `target` (O1/O3/O5).
    public func inserting(_ window: NodeID, at target: DropTarget, leaf: WindowLeaf? = nil) -> (Workspace, LayoutDiff) {
        var next = self
        var diff = LayoutDiff()
        let win = leaf ?? WindowLeaf(id: window)
        // Keep platform WindowID on the leaf; never rewrite via `id` setter (that uses WindowID.named).

        if next.root.contains(window) {
            if let removed = TreeOps.remove(next.root, windowID: window, cfg: next.layoutConfig) {
                next.root = removed
            }
            diff.moved.insert(window)
        }

        switch target {
        case .screenEdge(let edge):
            let inserted = TreeOps.insertAtScreenEdge(next.root, edge: edge, new: .window(win), cfg: next.layoutConfig)
            // If TreeOps preserved identity but something else didn't, surface it in debug builds.
            assert(
                inserted.tiledWindowIDs.contains(where: { $0.nodeID == window && $0.cgWindowID == win.identity.cgWindowID })
                    || win.identity.cgWindowID == nil,
                "insertAtScreenEdge dropped WindowID identity for \(window)"
            )
            next.root = inserted
            diff.inserted.insert(window)
        case .edge(let nodeID, let edge):
            next.root = TreeOps.insertAtEdge(next.root, targetID: nodeID, edge: edge, new: .window(win), cfg: next.layoutConfig)
            diff.inserted.insert(window)
        case .center(let nodeID):
            next.root = TreeOps.tabOnto(next.root, targetID: nodeID, win: win, cfg: next.layoutConfig)
            diff.inserted.insert(window)
        case .edgePath(let path, let edge):
            if let node = next.root.node(at: path) {
                next.root = TreeOps.insertAtEdge(next.root, targetID: node.id, edge: edge, new: .window(win), cfg: next.layoutConfig)
                diff.inserted.insert(window)
            }
        case .centerPath(let path):
            if let node = next.root.node(at: path) {
                next.root = TreeOps.tabOnto(next.root, targetID: node.id, win: win, cfg: next.layoutConfig)
                diff.inserted.insert(window)
            }
        }
        return (next, diff)
    }

    public func removing(_ window: NodeID) -> (Workspace, LayoutDiff) {
        var next = self
        var diff = LayoutDiff()
        guard next.contains(window) else { return (next, .empty) }
        if let removed = TreeOps.remove(next.root, windowID: window, cfg: next.layoutConfig) {
            next.root = removed
        } else {
            next.root = .desktop(DesktopArea())
        }
        next.windowStates.removeValue(forKey: window)
        diff.removed.insert(window)
        return (next, diff)
    }

    public func moving(_ window: NodeID, to target: DropTarget) -> (Workspace, LayoutDiff) {
        guard contains(window) else { return (self, .empty) }
        let (inserted, diff) = inserting(window, at: target)
        var merged = diff
        merged.moved.insert(window)
        return (inserted, merged)
    }

    public func tabbing(_ window: NodeID, onto target: NodeID) -> (Workspace, LayoutDiff) {
        guard window != target, root.contains(window), root.contains(target) else {
            return (self, .empty)
        }
        var next = self
        guard let loc = TreeOps.find(next.root, target: window), case .window(let win) = loc.node else {
            return (self, .empty)
        }
        if let removed = TreeOps.remove(next.root, windowID: window, cfg: next.layoutConfig) {
            next.root = removed
        }
        next.root = TreeOps.tabOnto(next.root, targetID: target, win: win, cfg: next.layoutConfig)
        return (next, LayoutDiff(moved: [window]))
    }

    public func floating(_ window: NodeID, frac: EdgeRect) -> (Workspace, LayoutDiff) {
        var next = self
        guard let loc = TreeOps.find(next.root, target: window), case .window(let win) = loc.node else {
            return (self, .empty)
        }
        if let removed = TreeOps.remove(next.root, windowID: window, cfg: next.layoutConfig) {
            next.root = removed
        }
        guard let deskLoc = TreeOps.find(next.root, target: "desktop"),
              case .desktop(var d) = deskLoc.node else {
            // No desktop: make workspace a desktop with this float.
            next.root = .desktop(DesktopArea(floats: [FloatWin(window: win, frac: frac)]))
            return (next, LayoutDiff(floated: [window]))
        }
        d.floats.append(FloatWin(window: win, frac: frac))
        next.root = TreeOps.replace(next.root, oldID: d.id, with: .desktop(d))
        return (next, LayoutDiff(floated: [window]))
    }

    /// Legacy absolute-frame float (converts naively to unit frac of a placeholder).
    public func floating(_ window: NodeID, frame: Rect) -> (Workspace, LayoutDiff) {
        // Without a solved desktop tile, store as fractions of a 1000×1000 placeholder.
        let frac = EdgeRect(
            x0: frame.x / 1000,
            y0: frame.y / 1000,
            x1: (frame.x + frame.width) / 1000,
            y1: (frame.y + frame.height) / 1000
        )
        return floating(window, frac: frac)
    }

    public func docking(_ window: NodeID, at target: DropTarget) -> (Workspace, LayoutDiff) {
        let (inserted, diff) = inserting(window, at: target)
        var merged = diff
        merged.docked.insert(window)
        return (inserted, merged)
    }

    public func normalized() -> (Workspace, LayoutDiff) {
        var next = self
        let before = next.root
        next.root = next.root.normalizedOrDesktop(cfg: next.layoutConfig)
        return (next, LayoutDiff(normalized: before != next.root))
    }

    public func balancingSizes() -> (Workspace, LayoutDiff) {
        var next = self
        let before = next.root
        next.root = balance(next.root)
        return (next, LayoutDiff(ratiosChanged: before != next.root))
    }

    public func flatteningTree() -> (Workspace, LayoutDiff) {
        normalized()
    }

    public func hidingDesktop() -> (Workspace, LayoutDiff) {
        var next = self
        let (root, mem) = TreeOps.desktopAreaHide(next.root, cfg: next.layoutConfig)
        next.root = root
        next.desktopMemory = mem
        return (next, LayoutDiff(ratiosChanged: true))
    }

    public func showingDesktop(side: Edge = .right) -> (Workspace, LayoutDiff) {
        var next = self
        next.root = TreeOps.desktopAreaShow(next.root, memory: next.desktopMemory, cfg: next.layoutConfig, side: side)
        next.desktopMemory = nil
        return (next, LayoutDiff(ratiosChanged: true))
    }

    public func resizing(path: NodePath, dividerIndex: Int, delta: Double) -> (Workspace, LayoutDiff) {
        var next = self
        guard let splitNode = next.root.node(at: path),
              case .split(var split) = splitNode,
              split.children.count >= 2,
              dividerIndex >= 0,
              dividerIndex + 1 < split.children.count else {
            return (self, .empty)
        }
        let minR = next.layoutConfig.minRatio
        var left = split.ratios[dividerIndex]
        var right = split.ratios[dividerIndex + 1]
        let combined = left + right
        left = min(max(left + delta, minR), combined - minR)
        right = combined - left
        split.ratios[dividerIndex] = left
        split.ratios[dividerIndex + 1] = right
        if let updated = next.root.replacing(at: path, with: .split(split)) {
            next.root = updated
        }
        return (next, LayoutDiff(ratiosChanged: true))
    }

    public func splitting(_ window: WindowID, axis: Axis) -> (Workspace, LayoutDiff) {
        splitting(window.nodeID, axis: axis)
    }

    public func splitting(_ window: NodeID, axis: Axis) -> (Workspace, LayoutDiff) {
        guard let path = root.path(to: window),
              let node = root.node(at: path) else {
            return (self, .empty)
        }
        var next = self
        let split = Split.equal(axis: axis, children: [node, .desktop(DesktopArea())])
        if let updated = next.root.replacing(at: path, with: .split(split)) {
            next.root = updated.normalizedOrDesktop(cfg: next.layoutConfig)
        }
        return (next, LayoutDiff(ratiosChanged: true))
    }

    public func floatingAll(defaultFrame: Rect = Rect(x: 100, y: 100, width: 640, height: 480)) -> (Workspace, LayoutDiff) {
        let ids = root.tiledWindowIDs
        guard !ids.isEmpty else { return (self, .empty) }
        var next = self
        var floated = Set<NodeID>()
        var floats: [FloatWin] = next.floatWins
        var cascade = 0.0
        for id in ids {
            if let removed = TreeOps.remove(next.root, windowID: id.nodeID, cfg: next.layoutConfig) {
                next.root = removed
            }
            let x = (defaultFrame.x + cascade) / 1000
            let y = (defaultFrame.y + cascade) / 1000
            floats.append(FloatWin(
                window: WindowLeaf(identity: id),
                frac: (
                    x,
                    y,
                    x + defaultFrame.width / 1000,
                    y + defaultFrame.height / 1000
                )
            ))
            floated.insert(id.nodeID)
            cascade += Double(next.layoutConfig.floatCascade)
        }
        next.root = .desktop(DesktopArea(floats: floats))
        return (next, LayoutDiff(floated: floated))
    }

    private func balance(_ node: LayoutNode) -> LayoutNode {
        switch node {
        case .desktop, .window, .tabs:
            return node
        case .split(var split):
            split.children = split.children.map { balance($0) }
            let n = split.children.count
            if n > 0 {
                split.ratios = Array(repeating: 1.0 / Double(n), count: n)
            }
            return .split(split)
        }
    }
}
