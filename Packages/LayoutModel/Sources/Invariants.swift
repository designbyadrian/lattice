import Foundation

/// Structural invariants asserted by tests (and available to callers).
public enum LayoutInvariants: Sendable {
    public static func check(_ workspace: Workspace, cfg: LayoutConfig? = nil) -> [String] {
        let cfg = cfg ?? workspace.layoutConfig
        var violations: [String] = []
        let tiled = workspace.root.tiledWindowIDs
        let floating = workspace.root.floatingWindowIDs
        let all = tiled + floating

        var seen = Set<WindowID>()
        for id in all {
            if seen.contains(id) {
                violations.append("window \(id.nodeID) appears more than once")
            }
            seen.insert(id)
        }

        violations.append(contentsOf: checkRatios(workspace.root, minRatio: cfg.minRatio))

        if hasEmptySplit(workspace.root) {
            violations.append("empty split present (normalize required)")
        }

        if hasSingleChildSplit(workspace.root) {
            violations.append("single-child split present (normalize required)")
        }

        if hasSameAxisNesting(workspace.root) {
            violations.append("same-axis nested split present (normalize required)")
        }

        return violations
    }

    public static func holds(_ workspace: Workspace) -> Bool {
        check(workspace).isEmpty
    }

    private static func checkRatios(_ node: LayoutNode, minRatio: Double) -> [String] {
        switch node {
        case .desktop, .window, .tabs:
            return []
        case .split(let split):
            var v: [String] = []
            if split.children.count != split.ratios.count {
                v.append("ratio count mismatch")
            }
            if abs(split.ratios.reduce(0, +) - 1) > 1e-9 {
                v.append("ratios sum \(split.ratios.reduce(0, +))")
            }
            if let m = split.ratios.min(), m < minRatio - 1e-12 {
                v.append("ratio below min \(m)")
            }
            for child in split.children {
                v.append(contentsOf: checkRatios(child, minRatio: minRatio))
            }
            return v
        }
    }

    private static func hasEmptySplit(_ node: LayoutNode) -> Bool {
        switch node {
        case .split(let split):
            if split.children.isEmpty { return true }
            return split.children.contains(where: hasEmptySplit)
        default:
            return false
        }
    }

    private static func hasSingleChildSplit(_ node: LayoutNode) -> Bool {
        switch node {
        case .split(let split):
            if split.children.count < 2 { return true }
            return split.children.contains(where: hasSingleChildSplit)
        default:
            return false
        }
    }

    private static func hasSameAxisNesting(_ node: LayoutNode) -> Bool {
        switch node {
        case .split(let split):
            for child in split.children {
                if case .split(let inner) = child, inner.axis == split.axis {
                    return true
                }
                if hasSameAxisNesting(child) { return true }
            }
            return false
        default:
            return false
        }
    }
}
