import Foundation

extension LayoutNode {
    /// S1 Normalise (ADDENDUM-3). Returns `nil` when the node should be deleted.
    public func normalized(cfg: LayoutConfig = .default) -> LayoutNode? {
        LayoutNormalize.normalize(self, cfg: cfg)
    }

    /// Normalize, falling back to an empty desktop if the tree collapses.
    public func normalizedOrDesktop(cfg: LayoutConfig = .default) -> LayoutNode {
        normalized(cfg: cfg) ?? .desktop(DesktopArea())
    }
}

public enum LayoutNormalize {
    public static func normalize(_ node: LayoutNode, cfg: LayoutConfig) -> LayoutNode? {
        switch node {
        case .window, .desktop:
            return node
        case .tabs(var tabs):
            if tabs.members.isEmpty { return nil }
            if tabs.members.count == 1 { return .window(tabs.members[0]) }
            tabs.active = max(0, min(tabs.active, tabs.members.count - 1))
            return .tabs(tabs)
        case .split(var split):
            var kids: [LayoutNode] = []
            var rats: [Double] = []
            for (c, r) in zip(split.children, split.ratios) {
                guard let c2 = normalize(c, cfg: cfg) else { continue }
                kids.append(c2)
                rats.append(LayoutMath.isValidRatio(r) ? r : cfg.minRatio)
            }
            if kids.isEmpty { return nil }
            if kids.count == 1 { return kids[0] }

            var flatK: [LayoutNode] = []
            var flatR: [Double] = []
            for (c, r) in zip(kids, rats) {
                if case .split(let inner) = c, inner.axis == split.axis {
                    let g = inner.ratios.reduce(0, +)
                    for (gc, gr) in zip(inner.children, inner.ratios) {
                        flatK.append(gc)
                        flatR.append(r * gr / g)
                    }
                } else {
                    flatK.append(c)
                    flatR.append(r)
                }
            }
            split.children = flatK
            split.ratios = renorm(flatR, floor: cfg.minRatio)
            return .split(split)
        }
    }

    /// Scale to sum 1, then lift anything below `floor` and rescale the rest.
    public static func renorm(_ ratios: [Double], floor: Double) -> [Double] {
        let n = ratios.count
        if n == 0 { return [] }
        let s = ratios.reduce(0, +)
        var r = ratios.map { $0 / s }
        if floor * Double(n) >= 1 {
            return Array(repeating: 1.0 / Double(n), count: n)
        }
        var fixed = Array(repeating: false, count: n)
        for _ in 0..<n {
            let low = (0..<n).filter { !fixed[$0] && r[$0] < floor - LayoutMath.tol }
            if low.isEmpty { break }
            for i in low {
                fixed[i] = true
                r[i] = floor
            }
            let fixedCount = fixed.filter { $0 }.count
            let rest = 1 - floor * Double(fixedCount)
            let freeSum = (0..<n).filter { !fixed[$0] }.map { r[$0] }.reduce(0, +)
            for i in 0..<n where !fixed[i] {
                r[i] = r[i] * rest / freeSum
            }
        }
        return r
    }
}
