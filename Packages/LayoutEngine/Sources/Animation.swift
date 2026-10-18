import Foundation
import LayoutModel

/// Shared layout motion curve and duration (pure math; platform drives display-link in P7).
public enum LayoutMotion {
    /// Default duration for split / dock / close / zoom (tuned later in P7).
    public static let defaultDurationSeconds: Double = 0.36

    /// Smoothstep-style ease-in-out cubic: 3t² − 2t³ mapped through a slightly stronger ease.
    public static func easeInOut(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        // Cubic Hermite smoothstep composed with itself for a softer landing.
        let s = x * x * (3 - 2 * x)
        return s * s * (3 - 2 * s)
    }

    /// Linear progress 0…1 for elapsed/duration, then eased.
    public static func progress(elapsedSeconds: Double, durationSeconds: Double = defaultDurationSeconds) -> Double {
        guard durationSeconds > 0 else { return 1 }
        return easeInOut(elapsedSeconds / durationSeconds)
    }
}

/// Interruptible interpolation between two frame maps.
public struct FrameAnimator: Equatable, Sendable {
    public var from: [WindowID: Rect]
    public var to: [WindowID: Rect]
    public var durationSeconds: Double
    /// Elapsed seconds at the start of the current segment (usually 0 after retarget).
    public var elapsedSeconds: Double

    public init(
        from: [WindowID: Rect],
        to: [WindowID: Rect],
        durationSeconds: Double = LayoutMotion.defaultDurationSeconds,
        elapsedSeconds: Double = 0
    ) {
        self.from = from
        self.to = to
        self.durationSeconds = durationSeconds
        self.elapsedSeconds = elapsedSeconds
    }

    public var isFinished: Bool {
        elapsedSeconds >= durationSeconds
    }

    /// Advance by `dt` seconds and return the eased frames.
    public mutating func advance(by dt: Double) -> [WindowID: Rect] {
        elapsedSeconds = min(elapsedSeconds + max(0, dt), durationSeconds)
        return frames(at: elapsedSeconds)
    }

    public func frames(at elapsed: Double) -> [WindowID: Rect] {
        let t = LayoutMotion.progress(elapsedSeconds: elapsed, durationSeconds: durationSeconds)
        return Self.interpolate(from: from, to: to, t: t)
    }

    /// Retarget mid-flight: current eased position becomes the new `from`.
    public mutating func retarget(to newTarget: [WindowID: Rect], at elapsed: Double? = nil) {
        let e = elapsed ?? elapsedSeconds
        let current = frames(at: e)
        from = current
        to = newTarget
        elapsedSeconds = 0
    }

    /// Linear blend of frame maps at parameter `t` in 0…1 (pre-eased or raw).
    public static func interpolate(from: [WindowID: Rect], to: [WindowID: Rect], t: Double) -> [WindowID: Rect] {
        let u = min(max(t, 0), 1)
        let keys = Set(from.keys).union(to.keys)
        var result: [WindowID: Rect] = [:]
        result.reserveCapacity(keys.count)
        for id in keys {
            switch (from[id], to[id]) {
            case let (a?, b?):
                result[id] = Rect.lerp(a, b, t: u)
            case let (a?, nil):
                // Fade out: shrink toward center of `a` as u→1, then drop at end.
                if u >= 1 {
                    continue
                }
                let sink = Rect(x: a.midX, y: a.midY, width: 0, height: 0)
                result[id] = Rect.lerp(a, sink, t: u)
            case let (nil, b?):
                let birth = Rect(x: b.midX, y: b.midY, width: 0, height: 0)
                result[id] = Rect.lerp(birth, b, t: u)
            case (nil, nil):
                break
            }
        }
        return result
    }
}
