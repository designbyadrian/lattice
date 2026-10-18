import Foundation

extension Workspace {
    // MARK: - Public operations

    /// Insert `window` at `target`. Neighbours make room. Idempotent if already present.
    public func inserting(_ window: WindowID, at target: DropTarget) -> (Workspace, LayoutDiff) {
        var next = self
        var diff = LayoutDiff()
        if next.contains(window) {
            // Move existing window to the new target.
            let (removed, removeDiff) = next.removing(window)
            next = removed
            diff.merge(removeDiff)
        }
        next.floating.removeAll { $0.id == window }

        switch target {
        case .screenEdge(let edge):
            next.root = Node.docking(window, beside: next.root, edge: edge)
            diff.inserted.insert(window)
        case .edge(let path, let edge):
            if let node = next.root.node(at: path) {
                let wrapped = Node.docking(window, beside: node, edge: edge)
                if let updated = next.root.replacing(at: path, with: wrapped) {
                    next.root = updated
                    diff.inserted.insert(window)
                }
            } else if path.isEmpty {
                next.root = Node.docking(window, beside: next.root, edge: edge)
                diff.inserted.insert(window)
            }
        case .center(let path):
            if let node = next.root.node(at: path) {
                let tabbed = node.addingToTabs(window)
                if let updated = next.root.replacing(at: path, with: tabbed) {
                    next.root = updated
                    diff.inserted.insert(window)
                }
            } else if path.isEmpty {
                next.root = next.root.addingToTabs(window)
                diff.inserted.insert(window)
            }
        }

        let (normalized, normDiff) = next.normalized()
        next = normalized
        diff.merge(normDiff)
        return (next, diff)
    }

    /// Remove `window` from the tree or floating list; siblings absorb space.
    public func removing(_ window: WindowID) -> (Workspace, LayoutDiff) {
        var next = self
        var diff = LayoutDiff()

        if let idx = next.floating.firstIndex(where: { $0.id == window }) {
            next.floating.remove(at: idx)
            next.windowStates.removeValue(forKey: window)
            diff.removed.insert(window)
            return (next, diff)
        }

        guard next.root.contains(window) else {
            return (next, .empty)
        }

        next.root = next.root.removing(window)
        next.windowStates.removeValue(forKey: window)
        diff.removed.insert(window)

        let (normalized, normDiff) = next.normalized()
        next = normalized
        diff.merge(normDiff)
        return (next, diff)
    }

    /// Move `window` to a new drop target.
    public func moving(_ window: WindowID, to target: DropTarget) -> (Workspace, LayoutDiff) {
        guard contains(window) else { return (self, .empty) }
        let (inserted, diff) = inserting(window, at: target)
        var merged = diff
        merged.moved.insert(window)
        return (inserted, merged)
    }

    /// Swap the tree/floating positions of two windows.
    public func swapping(_ a: WindowID, with b: WindowID) -> (Workspace, LayoutDiff) {
        guard a != b, contains(a), contains(b) else { return (self, .empty) }
        var next = self
        next.root = next.root.swapping(a, with: b)

        // Floating frames swap if both floating, or membership swaps.
        let aFloat = next.floating.firstIndex(where: { $0.id == a })
        let bFloat = next.floating.firstIndex(where: { $0.id == b })
        switch (aFloat, bFloat) {
        case let (ai?, bi?):
            let frameA = next.floating[ai].frame
            next.floating[ai].frame = next.floating[bi].frame
            next.floating[bi].frame = frameA
        case let (ai?, nil):
            // a floating, b tiled → put b in floating slot, a into tree where b was
            let frame = next.floating[ai].frame
            next.floating[ai] = FloatingWindow(id: b, frame: frame)
            next.root = next.root.replacingWindow(b, with: a)
        case let (nil, bi?):
            let frame = next.floating[bi].frame
            next.floating[bi] = FloatingWindow(id: a, frame: frame)
            next.root = next.root.replacingWindow(a, with: b)
        case (nil, nil):
            break
        }

        var diff = LayoutDiff(moved: [a, b])
        let (normalized, normDiff) = next.normalized()
        next = normalized
        diff.merge(normDiff)
        return (next, diff)
    }

    /// Resize at a seam inside the split at `path`.
    /// `dividerIndex` is the index of the child before the seam (0..<children.count-1).
    /// `delta` is added to that child's ratio (and subtracted from the neighbour).
    public func resizing(path: NodePath, dividerIndex: Int, delta: Double) -> (Workspace, LayoutDiff) {
        var next = self
        guard let splitNode = next.root.node(at: path),
              case .split(var split) = splitNode else {
            return (self, .empty)
        }
        guard split.children.count >= 2,
              dividerIndex >= 0,
              dividerIndex + 1 < split.children.count,
              split.ratios.count == split.children.count else {
            return (self, .empty)
        }

        let minR = SplitNode.minRatio
        var left = split.ratios[dividerIndex]
        var right = split.ratios[dividerIndex + 1]
        let combined = left + right
        left = min(max(left + delta, minR), combined - minR)
        right = combined - left
        split.ratios[dividerIndex] = left
        split.ratios[dividerIndex + 1] = right

        // Only those two ratios change — assert others untouched by reconstructing.
        if let updated = next.root.replacing(at: path, with: .split(split)) {
            next.root = updated
        }
        return (next, LayoutDiff(ratiosChanged: true))
    }

    /// Tab `window` onto `onto` (must both be in the tree).
    public func tabbing(_ window: WindowID, onto target: WindowID) -> (Workspace, LayoutDiff) {
        guard window != target, root.contains(window), root.contains(target) else {
            return (self, .empty)
        }
        var next = self
        // Remove window first, then center-insert onto target's path.
        next.root = next.root.removing(window)
        guard let path = next.root.path(to: target) else {
            return (self, .empty)
        }
        if let node = next.root.node(at: path) {
            let tabbed = node.addingToTabs(window)
            if let updated = next.root.replacing(at: path, with: tabbed) {
                next.root = updated
            }
        }
        var diff = LayoutDiff(moved: [window])
        let (normalized, normDiff) = next.normalized()
        next = normalized
        diff.merge(normDiff)
        return (next, diff)
    }

    /// Extract `window` from a tab group into a neighbouring panel (horizontal split).
    public func untabbing(_ window: WindowID) -> (Workspace, LayoutDiff) {
        guard let path = root.path(to: window),
              let node = root.node(at: path),
              case .tabs(let tabs) = node,
              tabs.windows.contains(window),
              tabs.windows.count >= 2 else {
            return (self, .empty)
        }
        var next = self
        let remaining = tabs.windows.filter { $0 != window }
        let selected = min(tabs.selectedIndex, remaining.count - 1)
        let rest: Node = remaining.count == 1
            ? .panel(PanelNode(window: remaining[0]))
            : .tabs(TabNode(windows: remaining, selectedIndex: selected))
        let split = SplitNode.equal(
            axis: .horizontal,
            children: [.panel(PanelNode(window: window)), rest]
        )
        if let updated = next.root.replacing(at: path, with: .split(split)) {
            next.root = updated
        }
        var diff = LayoutDiff(moved: [window])
        let (normalized, normDiff) = next.normalized()
        next = normalized
        diff.merge(normDiff)
        return (next, diff)
    }

    /// Move a tiled window into the floating list.
    public func floating(_ window: WindowID, frame: Rect) -> (Workspace, LayoutDiff) {
        guard root.contains(window) else {
            if let idx = floating.firstIndex(where: { $0.id == window }) {
                var next = self
                next.floating[idx].frame = frame
                return (next, .empty)
            }
            return (self, .empty)
        }
        var next = self
        next.root = next.root.removing(window)
        next.floating.append(FloatingWindow(id: window, frame: frame))
        var diff = LayoutDiff(floated: [window])
        let (normalized, normDiff) = next.normalized()
        next = normalized
        diff.merge(normDiff)
        return (next, diff)
    }

    /// Dock a floating (or new) window into the tree at `target`.
    public func docking(_ window: WindowID, at target: DropTarget) -> (Workspace, LayoutDiff) {
        var next = self
        next.floating.removeAll { $0.id == window }
        let (inserted, diff) = next.inserting(window, at: target)
        var merged = diff
        merged.docked.insert(window)
        return (inserted, merged)
    }

    /// Float every tiled window with placeholder frames.
    public func floatingAll(defaultFrame: Rect = Rect(x: 100, y: 100, width: 640, height: 480)) -> (Workspace, LayoutDiff) {
        let ids = root.tiledWindowIDs
        guard !ids.isEmpty else { return (self, .empty) }
        var next = self
        var floated = Set<WindowID>()
        for id in ids {
            next.root = next.root.removing(id)
            if !next.floating.contains(where: { $0.id == id }) {
                next.floating.append(FloatingWindow(id: id, frame: defaultFrame))
            }
            floated.insert(id)
        }
        next.root = .desktop
        var diff = LayoutDiff(floated: floated)
        let (normalized, normDiff) = next.normalized()
        next = normalized
        diff.merge(normDiff)
        return (next, diff)
    }

    /// Collapse empty / singleton containers.
    public func normalized() -> (Workspace, LayoutDiff) {
        var next = self
        let before = next.root
        next.root = next.root.normalized()
        // Ensure at most one desktop by leaving structure as-is after normalize;
        // screen-edge docks intentionally keep a desktop sibling.
        let changed = before != next.root
        return (next, LayoutDiff(normalized: changed))
    }

    /// Equalize ratios on every split in the tree (Dinky `balance-sizes`).
    public func balancingSizes() -> (Workspace, LayoutDiff) {
        var next = self
        let before = next.root
        next.root = next.root.balancingSizes()
        let changed = before != next.root
        return (next, LayoutDiff(ratiosChanged: changed))
    }

    /// Flatten nested same-axis splits via normalize (Dinky `flatten-workspace-tree`).
    public func flatteningTree() -> (Workspace, LayoutDiff) {
        normalized()
    }

    /// Wrap `window`'s leaf in a split along `axis` with a desktop sibling (pending next insert).
    public func splitting(_ window: WindowID, axis: Axis) -> (Workspace, LayoutDiff) {
        guard let path = root.path(to: window),
              let node = root.node(at: path) else {
            return (self, .empty)
        }
        var next = self
        let split = SplitNode.equal(axis: axis, children: [node, .desktop])
        if let updated = next.root.replacing(at: path, with: .split(split)) {
            next.root = updated
        }
        var diff = LayoutDiff(ratiosChanged: true)
        let (normalized, normDiff) = next.normalized()
        next = normalized
        diff.merge(normDiff)
        return (next, diff)
    }
}

extension Node {
    /// Recursively equalize split ratios.
    func balancingSizes() -> Node {
        switch self {
        case .desktop, .panel:
            return self
        case .tabs:
            return self
        case .split(var split):
            split.children = split.children.map { $0.balancingSizes() }
            let n = split.children.count
            if n > 0 {
                split.ratios = Array(repeating: 1.0 / Double(n), count: n)
            }
            return .split(split)
        }
    }
}

// MARK: - Node helpers used by operations

extension Node {
    /// Dock `window` beside `existing` on `edge`, sharing space 50/50.
    static func docking(_ window: WindowID, beside existing: Node, edge: Edge) -> Node {
        let panel = Node.panel(PanelNode(window: window))
        // Replacing a lone desktop with a panel-only tree when docking "onto" desktop
        // via non-screen path still keeps desktop if we split with it.
        let children: [Node]
        if edge.placesNewFirst {
            children = [panel, existing]
        } else {
            children = [existing, panel]
        }
        return .split(SplitNode.equal(axis: edge.splitAxis, children: children))
    }

    fileprivate func addingToTabs(_ window: WindowID) -> Node {
        switch self {
        case .desktop:
            return .panel(PanelNode(window: window))
        case .panel(let panel):
            if panel.window == window { return self }
            return .tabs(TabNode(windows: [panel.window, window], selectedIndex: 1))
        case .tabs(var tabs):
            if tabs.windows.contains(window) { return self }
            tabs.windows.append(window)
            tabs.selectedIndex = tabs.windows.count - 1
            return .tabs(tabs)
        case .split:
            // Center on a group: wrap as sibling tab by converting to tabs of leaves + new.
            // Prefer inserting as a new tab group replacing the split's first panel path —
            // simplest useful behaviour: split beside as edge-right equivalent.
            return Node.docking(window, beside: self, edge: .right)
        }
    }

    fileprivate func removing(_ window: WindowID) -> Node {
        switch self {
        case .desktop:
            return .desktop
        case .panel(let panel):
            return panel.window == window ? .desktop : self
        case .tabs(var tabs):
            guard let idx = tabs.windows.firstIndex(of: window) else { return self }
            tabs.windows.remove(at: idx)
            if tabs.windows.isEmpty { return .desktop }
            if tabs.windows.count == 1 {
                return .panel(PanelNode(window: tabs.windows[0]))
            }
            if tabs.selectedIndex >= tabs.windows.count {
                tabs.selectedIndex = tabs.windows.count - 1
            } else if idx < tabs.selectedIndex {
                tabs.selectedIndex -= 1
            }
            return .tabs(tabs)
        case .split(var split):
            var children = split.children
            var ratios = split.ratios
            var i = 0
            while i < children.count {
                let before = children[i]
                let updated = before.removing(window)
                let beforeWasDesktop = {
                    if case .desktop = before { return true }
                    return false
                }()
                if case .desktop = updated, !beforeWasDesktop {
                    // Window leaf became empty — drop slot; siblings absorb.
                    ratios = absorbRatio(removing: i, from: ratios)
                    children.remove(at: i)
                    continue
                }
                children[i] = updated
                i += 1
            }
            if children.isEmpty { return .desktop }
            if children.count == 1 { return children[0] }
            split.children = children
            split.ratios = ratios
            synchronizeRatios(&split)
            return .split(split)
        }
    }

    fileprivate func swapping(_ a: WindowID, with b: WindowID) -> Node {
        let sentinel = WindowID(
            cgWindowID: nil,
            processID: -1,
            bundleID: "__lattice.swap.sentinel__",
            titleFingerprint: "swap-sentinel"
        )
        return replacingWindow(a, with: sentinel)
            .replacingWindow(b, with: a)
            .replacingWindow(sentinel, with: b)
    }

    fileprivate func replacingWindow(_ from: WindowID, with to: WindowID) -> Node {
        switch self {
        case .desktop:
            return self
        case .panel(var panel):
            if panel.window == from {
                panel.window = to
            }
            return .panel(panel)
        case .tabs(var tabs):
            tabs.windows = tabs.windows.map { $0 == from ? to : $0 }
            return .tabs(tabs)
        case .split(var split):
            split.children = split.children.map { $0.replacingWindow(from, with: to) }
            return .split(split)
        }
    }
}
