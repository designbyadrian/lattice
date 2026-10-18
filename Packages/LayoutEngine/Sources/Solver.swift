import Foundation
import LayoutModel

/// Minimum size request for a window (points).
public typealias MinSizes = [WindowID: Size]

/// Result of solving a workspace tree into frames.
public struct SolveResult: Equatable, Sendable {
    /// Tiled + floating window frames (integral). Desktop contributes no entry.
    public var frames: [WindowID: Rect]
    /// Allocated rect for every node path (including desktop / splits).
    public var nodeFrames: [NodePath: Rect]
    /// Windows forced to float because min sizes could not be satisfied by shrinking siblings.
    public var forcedFloating: Set<WindowID>

    public init(
        frames: [WindowID: Rect] = [:],
        nodeFrames: [NodePath: Rect] = [:],
        forcedFloating: Set<WindowID> = []
    ) {
        self.frames = frames
        self.nodeFrames = nodeFrames
        self.forcedFloating = forcedFloating
    }
}

/// Pure layout solver: tree → frames.
public enum LayoutSolver {
    /// Deterministic solve. Suspended windows keep their slot but take no space.
    /// Min-size overflow: shrink siblings first; if still impossible, float the offender.
    public static func solve(
        workspace: Workspace,
        displayRect: Rect,
        gaps: Gaps = .zero,
        minSizes: MinSizes = [:]
    ) -> SolveResult {
        let content = gaps.contentRect(in: displayRect).integralized()
        var forcedFloating = Set<WindowID>()
        var exclude = Set<WindowID>()

        // Iteratively float windows that cannot fit under min-size constraints.
        var frames: [WindowID: Rect] = [:]
        var nodeFrames: [NodePath: Rect] = [:]
        for _ in 0..<workspace.root.tiledWindowIDs.count + 1 {
            let pass = allocate(
                node: workspace.root,
                path: [],
                rect: content,
                workspace: workspace,
                gaps: gaps,
                minSizes: minSizes,
                excluded: exclude
            )
            frames = pass.frames
            nodeFrames = pass.nodeFrames
            if pass.unsatisfiable.isEmpty { break }
            // Float the largest min-area offender first for determinism.
            let next = pass.unsatisfiable.sorted { a, b in
                let aa = (minSizes[a] ?? Size.zero).width * (minSizes[a] ?? Size.zero).height
                let bb = (minSizes[b] ?? Size.zero).width * (minSizes[b] ?? Size.zero).height
                if aa != bb { return aa > bb }
                return stableKey(a) < stableKey(b)
            }.first!
            forcedFloating.insert(next)
            exclude.insert(next)
        }

        // Floating windows (configured + forced) keep/get frames.
        for fw in workspace.floating {
            guard workspace.state(of: fw.id).participatesInSolve else { continue }
            frames[fw.id] = fw.frame.integralized()
        }
        for id in forcedFloating where frames[id] == nil {
            guard workspace.state(of: id).participatesInSolve else { continue }
            let minimum = minSizes[id] ?? Size(width: 200, height: 150)
            let w = Swift.min(minimum.width, content.width)
            let h = Swift.min(minimum.height, content.height)
            frames[id] = Rect(x: content.x, y: content.y, width: w, height: h).integralized()
        }

        return SolveResult(frames: frames, nodeFrames: nodeFrames, forcedFloating: forcedFloating)
    }

    /// Convenience: window frames only.
    public static func solveFrames(
        workspace: Workspace,
        displayRect: Rect,
        gaps: Gaps = .zero,
        minSizes: MinSizes = [:]
    ) -> [WindowID: Rect] {
        solve(workspace: workspace, displayRect: displayRect, gaps: gaps, minSizes: minSizes).frames
    }
}

// MARK: - Allocation

private struct AllocPass {
    var frames: [WindowID: Rect]
    var nodeFrames: [NodePath: Rect]
    var unsatisfiable: Set<WindowID>
}

private func allocate(
    node: Node,
    path: NodePath,
    rect: Rect,
    workspace: Workspace,
    gaps: Gaps,
    minSizes: MinSizes,
    excluded: Set<WindowID>
) -> AllocPass {
    var frames: [WindowID: Rect] = [:]
    var nodeFrames: [NodePath: Rect] = [path: rect]
    var unsatisfiable = Set<WindowID>()

    switch node {
    case .desktop:
        return AllocPass(frames: frames, nodeFrames: nodeFrames, unsatisfiable: unsatisfiable)

    case .panel(let panel):
        if excluded.contains(panel.window) { return AllocPass(frames: frames, nodeFrames: nodeFrames, unsatisfiable: unsatisfiable) }
        guard workspace.state(of: panel.window).participatesInSolve else {
            return AllocPass(frames: frames, nodeFrames: nodeFrames, unsatisfiable: unsatisfiable)
        }
        let min = minSizes[panel.window] ?? Size.zero
        if rect.width + 0.5 < min.width || rect.height + 0.5 < min.height {
            unsatisfiable.insert(panel.window)
        } else {
            frames[panel.window] = rect.integralized()
        }
        return AllocPass(frames: frames, nodeFrames: nodeFrames, unsatisfiable: unsatisfiable)

    case .tabs(let tabs):
        // Only the selected active window occupies the slot.
        if let selected = tabs.selectedWindow,
           !excluded.contains(selected),
           workspace.state(of: selected).participatesInSolve {
            let min = minSizes[selected] ?? Size.zero
            if rect.width + 0.5 < min.width || rect.height + 0.5 < min.height {
                unsatisfiable.insert(selected)
            } else {
                frames[selected] = rect.integralized()
            }
        }
        return AllocPass(frames: frames, nodeFrames: nodeFrames, unsatisfiable: unsatisfiable)

    case .split(let split):
        let childMeta = split.children.enumerated().map { index, child -> (Int, Node, Double, Bool) in
            let active = participates(child, workspace: workspace, excluded: excluded)
            return (index, child, split.ratios[index], active)
        }
        let active = childMeta.filter(\.3)
        if active.isEmpty {
            // All children suspended/excluded — still record child frames as empty slices.
            for (index, child, _, _) in childMeta {
                let childPath = path + [index]
                let childPass = allocate(
                    node: child,
                    path: childPath,
                    rect: Rect(x: rect.x, y: rect.y, width: 0, height: 0),
                    workspace: workspace,
                    gaps: gaps,
                    minSizes: minSizes,
                    excluded: excluded
                )
                frames.merge(childPass.frames) { _, n in n }
                nodeFrames.merge(childPass.nodeFrames) { _, n in n }
                unsatisfiable.formUnion(childPass.unsatisfiable)
            }
            return AllocPass(frames: frames, nodeFrames: nodeFrames, unsatisfiable: unsatisfiable)
        }

        // Redistribute ratios among active children only.
        let activeWeightSum = active.map(\.2).reduce(0, +)
        let weights: [Double] = active.map { activeWeightSum > 0 ? $0.2 / activeWeightSum : 1.0 / Double(active.count) }

        let gapCount = max(active.count - 1, 0)
        let innerTotal = gaps.inner * Double(gapCount)

        let alongHorizontal = split.axis == .horizontal
        let primary = alongHorizontal ? Int(rect.width.rounded(.down)) : Int(rect.height.rounded(.down))
        let available = max(0, primary - Int(innerTotal.rounded(.down)))
        var lengths = PixelSplit.distribute(total: available, weights: weights)

        // Enforce min sizes along the split axis by shrinking siblings.
        let mins: [Int] = active.map { entry in
            let child = entry.1
            let m = aggregateMin(child, workspace: workspace, minSizes: minSizes, excluded: excluded)
            let v = alongHorizontal ? m.width : m.height
            return Int(v.rounded(.up))
        }
        let minSum = mins.reduce(0, +)
        if minSum > available {
            // Cannot satisfy all mins even by shrinking siblings — float offenders.
            for entry in active {
                for id in leafWindows(entry.1, workspace: workspace, excluded: excluded) {
                    let m = minSizes[id] ?? .zero
                    let need = Int((alongHorizontal ? m.width : m.height).rounded(.up))
                    if need > 0 {
                        unsatisfiable.insert(id)
                    }
                }
            }
        } else {
            enforceMins(lengths: &lengths, mins: mins)
            // Keep the strip pixel-exact after min enforcement.
            let sum = lengths.reduce(0, +)
            if sum != available, !lengths.isEmpty {
                lengths[lengths.count - 1] += available - sum
            }
        }

        // Place active children; suspended get zero-size rects at the seam.
        var cursor = alongHorizontal ? Int(rect.x.rounded(.down)) : Int(rect.y.rounded(.down))
        let crossOrigin = alongHorizontal ? rect.y : rect.x
        let crossSize = alongHorizontal ? rect.height : rect.width
        var activeIndex = 0
        let gapPx = Int(gaps.inner.rounded(.down))

        for (index, child, _, isActive) in childMeta {
            let childPath = path + [index]
            let childRect: Rect
            if isActive {
                let len = lengths[activeIndex]
                if alongHorizontal {
                    childRect = Rect(x: Double(cursor), y: crossOrigin, width: Double(len), height: crossSize)
                } else {
                    childRect = Rect(x: crossOrigin, y: Double(cursor), width: crossSize, height: Double(len))
                }
                cursor += len
                activeIndex += 1
                if activeIndex < active.count {
                    cursor += gapPx
                }
            } else {
                if alongHorizontal {
                    childRect = Rect(x: Double(cursor), y: crossOrigin, width: 0, height: crossSize)
                } else {
                    childRect = Rect(x: crossOrigin, y: Double(cursor), width: crossSize, height: 0)
                }
            }

            let childPass = allocate(
                node: child,
                path: childPath,
                rect: childRect,
                workspace: workspace,
                gaps: gaps,
                minSizes: minSizes,
                excluded: excluded
            )
            frames.merge(childPass.frames) { _, n in n }
            nodeFrames.merge(childPass.nodeFrames) { _, n in n }
            unsatisfiable.formUnion(childPass.unsatisfiable)
        }
        return AllocPass(frames: frames, nodeFrames: nodeFrames, unsatisfiable: unsatisfiable)
    }
}

private func participates(_ node: Node, workspace: Workspace, excluded: Set<WindowID>) -> Bool {
    switch node {
    case .desktop:
        // Desktop still occupies space in the tree.
        return true
    case .panel(let p):
        return !excluded.contains(p.window) && workspace.state(of: p.window).participatesInSolve
    case .tabs(let t):
        guard let s = t.selectedWindow else { return false }
        return !excluded.contains(s) && workspace.state(of: s).participatesInSolve
    case .split(let s):
        return s.children.contains { participates($0, workspace: workspace, excluded: excluded) }
    }
}

private func aggregateMin(
    _ node: Node,
    workspace: Workspace,
    minSizes: MinSizes,
    excluded: Set<WindowID>
) -> Size {
    switch node {
    case .desktop:
        return Size.zero
    case .panel(let p):
        guard participates(node, workspace: workspace, excluded: excluded) else { return .zero }
        return minSizes[p.window] ?? .zero
    case .tabs(let t):
        guard let s = t.selectedWindow, participates(node, workspace: workspace, excluded: excluded) else {
            return .zero
        }
        return minSizes[s] ?? .zero
    case .split(let s):
        let active = s.children.filter { participates($0, workspace: workspace, excluded: excluded) }
        guard !active.isEmpty else { return .zero }
        let mins = active.map { aggregateMin($0, workspace: workspace, minSizes: minSizes, excluded: excluded) }
        switch s.axis {
        case .horizontal:
            return Size(
                width: mins.map(\.width).reduce(0, +),
                height: mins.map(\.height).max() ?? 0
            )
        case .vertical:
            return Size(
                width: mins.map(\.width).max() ?? 0,
                height: mins.map(\.height).reduce(0, +)
            )
        }
    }
}

private func leafWindows(_ node: Node, workspace: Workspace, excluded: Set<WindowID>) -> [WindowID] {
    switch node {
    case .desktop:
        return []
    case .panel(let p):
        return participates(node, workspace: workspace, excluded: excluded) ? [p.window] : []
    case .tabs(let t):
        guard let s = t.selectedWindow, participates(node, workspace: workspace, excluded: excluded) else {
            return []
        }
        return [s]
    case .split(let s):
        return s.children.flatMap { leafWindows($0, workspace: workspace, excluded: excluded) }
    }
}

/// Grow under-min slices by shrinking over-min siblings. Mutates `lengths` in place.
private func enforceMins(lengths: inout [Int], mins: [Int]) {
    guard lengths.count == mins.count, !lengths.isEmpty else { return }
    // Multiple passes for cascading constraints.
    for _ in 0..<lengths.count {
        var deficit = 0
        var surplusIndices: [Int] = []
        for i in lengths.indices {
            if lengths[i] < mins[i] {
                deficit += mins[i] - lengths[i]
                lengths[i] = mins[i]
            } else if lengths[i] > mins[i] {
                surplusIndices.append(i)
            }
        }
        if deficit == 0 { return }
        let totalSurplus = surplusIndices.reduce(0) { $0 + (lengths[$1] - mins[$1]) }
        if totalSurplus <= 0 { return }
        var remaining = min(deficit, totalSurplus)
        // Deterministic: shrink from the end.
        for i in surplusIndices.reversed() {
            guard remaining > 0 else { break }
            let canTake = lengths[i] - mins[i]
            let take = min(canTake, remaining)
            lengths[i] -= take
            remaining -= take
        }
    }
}
