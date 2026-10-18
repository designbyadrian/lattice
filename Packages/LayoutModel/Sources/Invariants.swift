import Foundation

/// Structural invariants asserted by tests (and available to callers).
public enum LayoutInvariants: Sendable {
    public static func check(_ workspace: Workspace) -> [String] {
        var violations: [String] = []
        let tiled = workspace.root.tiledWindowIDs
        let floating = workspace.floating.map(\.id)
        let all = tiled + floating

        var seen = Set<WindowID>()
        for id in all {
            if seen.contains(id) {
                violations.append("window \(id) appears more than once")
            }
            seen.insert(id)
        }

        violations.append(contentsOf: checkRatios(workspace.root))

        if hasEmptySplit(workspace.root) {
            violations.append("empty split present (normalize required)")
        }

        if hasSingleChildSplit(workspace.root) {
            violations.append("single-child split present (normalize required)")
        }

        return violations
    }

    public static func holds(_ workspace: Workspace) -> Bool {
        check(workspace).isEmpty
    }

    private static func checkRatios(_ node: Node) -> [String] {
        switch node {
        case .desktop, .panel, .tabs:
            return []
        case .split(let split):
            var v: [String] = []
            if !split.hasValidRatios {
                v.append("invalid ratios \(split.ratios) for \(split.children.count) children")
            }
            for child in split.children {
                v.append(contentsOf: checkRatios(child))
            }
            return v
        }
    }

    private static func hasEmptySplit(_ node: Node) -> Bool {
        switch node {
        case .split(let split):
            if split.children.isEmpty { return true }
            return split.children.contains(where: hasEmptySplit)
        default:
            return false
        }
    }

    private static func hasSingleChildSplit(_ node: Node) -> Bool {
        switch node {
        case .split(let split):
            if split.children.count < 2 { return true }
            return split.children.contains(where: hasSingleChildSplit)
        default:
            return false
        }
    }
}
