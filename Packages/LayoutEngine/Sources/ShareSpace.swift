import Foundation
import LayoutModel

/// S4 space sharing (refimpl `share_space`).
public enum ShareSpace {
    /// Share `total` by ratios under per-child [min, max] bounds.
    public static func share(
        total: Double,
        ratios: [Double],
        mins: [Double],
        maxes: [Double]
    ) -> [Double] {
        let n = ratios.count
        let tol = LayoutMath.tol
        let sumMax = maxes.reduce(0, +)
        if sumMax <= total + tol {
            let rest = total - sumMax
            let s = ratios.reduce(0, +)
            return (0..<n).map { maxes[$0] + rest * ratios[$0] / s }
        }
        let sumMin = mins.reduce(0, +)
        if sumMin >= total - tol {
            return mins
        }

        func sizeAt(_ L: Double) -> [Double] {
            (0..<n).map { min(maxes[$0], max(mins[$0], L * ratios[$0])) }
        }

        var pts: Set<Double> = [0]
        for i in 0..<n {
            pts.insert(mins[i] / ratios[i])
            if maxes[i] < LayoutMath.inf {
                pts.insert(maxes[i] / ratios[i])
            }
        }
        let sorted = pts.sorted()
        var lo = 0.0
        var hit = false
        for L in sorted {
            if sizeAt(L).reduce(0, +) >= total - tol {
                hit = true
                break
            }
            lo = L
        }
        _ = hit

        let free = (0..<n).filter {
            mins[$0] <= lo * ratios[$0] + tol && (lo * ratios[$0] < maxes[$0] - tol)
        }
        let atLo = sizeAt(lo)
        let fixed = (0..<n).filter { !free.contains($0) }.map { atLo[$0] }.reduce(0, +)
        let rs = free.map { ratios[$0] }.reduce(0, +)
        let Lx = rs > 0 ? (total - fixed) / rs : lo
        var out = sizeAt(Lx)
        let err = total - out.reduce(0, +)
        if !free.isEmpty, abs(err) > 0 {
            let k = free.max(by: { out[$0] < out[$1] })!
            out[k] += err
        }
        return out
    }
}
