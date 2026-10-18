import Foundation
import LayoutModel

extension Rect {
    /// Integral pixel rounding: origin floored, max edges ceiled (deterministic, no sub-pixel gaps).
    public func integralized() -> Rect {
        let x0 = self.x.rounded(.down)
        let y0 = self.y.rounded(.down)
        let x1 = self.maxX.rounded(.up)
        let y1 = self.maxY.rounded(.up)
        return Rect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    public var area: Double { max(0, width) * max(0, height) }

    public func contains(point: Point) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    public func intersects(_ other: Rect) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }

    public func union(_ other: Rect) -> Rect {
        let x0 = min(minX, other.minX)
        let y0 = min(minY, other.minY)
        let x1 = max(maxX, other.maxX)
        let y1 = max(maxY, other.maxY)
        return Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Linear interpolation of origin and size.
    public static func lerp(_ a: Rect, _ b: Rect, t: Double) -> Rect {
        Rect(
            x: a.x + (b.x - a.x) * t,
            y: a.y + (b.y - a.y) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }
}

enum PixelSplit {
    /// Split `total` into `weights.count` non-negative integer lengths summing to `total`.
    /// Uses the largest-remainder method for deterministic, gap-free division.
    static func distribute(total: Int, weights: [Double]) -> [Int] {
        precondition(total >= 0)
        guard !weights.isEmpty else { return [] }
        let sumW = weights.reduce(0, +)
        if sumW <= 0 || total == 0 {
            var equal = Array(repeating: total / weights.count, count: weights.count)
            let rem = total - equal.reduce(0, +)
            for i in 0..<rem { equal[i] += 1 }
            return equal
        }
        var floors: [Int] = []
        var remainders: [(Int, Double)] = []
        var used = 0
        for (i, w) in weights.enumerated() {
            let exact = Double(total) * (w / sumW)
            let f = Int(exact.rounded(.down))
            floors.append(f)
            used += f
            remainders.append((i, exact - Double(f)))
        }
        var leftover = total - used
        remainders.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0 < rhs.0
        }
        var result = floors
        var idx = 0
        while leftover > 0 {
            result[remainders[idx % remainders.count].0] += 1
            leftover -= 1
            idx += 1
        }
        return result
    }
}
