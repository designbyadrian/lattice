import Foundation

extension Node {
    /// Collapse single-child splits, drop empty tabs/splits, convert singleton tabs to panels.
    public func normalized() -> Node {
        switch self {
        case .desktop:
            return .desktop
        case .panel:
            return self
        case .tabs(var tabs):
            if tabs.windows.isEmpty {
                return .desktop
            }
            if tabs.windows.count == 1 {
                return .panel(PanelNode(window: tabs.windows[0]))
            }
            tabs.selectedIndex = min(max(0, tabs.selectedIndex), tabs.windows.count - 1)
            return .tabs(tabs)
        case .split(var split):
            split.children = split.children.map { $0.normalized() }
            // Drop empty desktop-only? Keep desktops. Drop truly empty (shouldn't happen).
            // Remove children that became empty tabs normalized to desktop only if multiple desktops?
            // Keep one desktop max is enforced at workspace level separately.

            // Zip ratios with children, drop nothing yet.
            synchronizeRatios(&split)

            if split.children.isEmpty {
                return .desktop
            }
            if split.children.count == 1 {
                return split.children[0]
            }

            // Flatten same-axis nested splits.
            var flatChildren: [Node] = []
            var flatRatios: [Double] = []
            for (child, ratio) in zip(split.children, split.ratios) {
                if case .split(let inner) = child, inner.axis == split.axis {
                    for (innerChild, innerRatio) in zip(inner.children, inner.ratios) {
                        flatChildren.append(innerChild)
                        flatRatios.append(ratio * innerRatio)
                    }
                } else {
                    flatChildren.append(child)
                    flatRatios.append(ratio)
                }
            }
            split.children = flatChildren
            split.ratios = flatRatios
            synchronizeRatios(&split)

            if split.children.count == 1 {
                return split.children[0]
            }
            return .split(split)
        }
    }
}

/// Ensure ratios count matches children and sums to 1 with each ≥ minRatio when possible.
func synchronizeRatios(_ split: inout SplitNode) {
    let count = split.children.count
    guard count > 0 else {
        split.ratios = []
        return
    }
    if split.ratios.count != count {
        split.ratios = Array(repeating: 1.0 / Double(count), count: count)
        return
    }
    var ratios = split.ratios.map { max($0, 0) }
    let sum = ratios.reduce(0, +)
    if sum <= 0 {
        ratios = Array(repeating: 1.0 / Double(count), count: count)
    } else {
        ratios = ratios.map { $0 / sum }
    }
    // Clamp to minRatio when feasible.
    let minR = SplitNode.minRatio
    if Double(count) * minR <= 1.0 + 1e-9 {
        var clamped = ratios.map { max($0, minR) }
        // Redistribute excess from those above min.
        let total = clamped.reduce(0, +)
        if total > 1 {
            var overflow = total - 1
            for i in clamped.indices.reversed() {
                let reducible = clamped[i] - minR
                if reducible <= 0 { continue }
                let take = min(reducible, overflow)
                clamped[i] -= take
                overflow -= take
                if overflow <= 1e-12 { break }
            }
        } else if total < 1 {
            let deficit = 1 - total
            // Give to the largest slot.
            if let idx = clamped.indices.max(by: { clamped[$0] < clamped[$1] }) {
                clamped[idx] += deficit
            }
        }
        // Final normalize.
        let s = clamped.reduce(0, +)
        if s > 0 {
            clamped = clamped.map { $0 / s }
        }
        ratios = clamped
    }
    split.ratios = ratios
}

/// Redistribute `removedRatio` among remaining ratios proportionally.
func absorbRatio(removing index: Int, from ratios: [Double]) -> [Double] {
    guard ratios.indices.contains(index) else { return ratios }
    var remaining = ratios
    let removed = remaining.remove(at: index)
    guard !remaining.isEmpty else { return [] }
    let sum = remaining.reduce(0, +)
    if sum <= 0 {
        return Array(repeating: 1.0 / Double(remaining.count), count: remaining.count)
    }
    // Distribute removed proportionally.
    return remaining.map { $0 + removed * ($0 / sum) }
}
