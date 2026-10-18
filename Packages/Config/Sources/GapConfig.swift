import Foundation

/// Per-side gap values (points).
public struct GapInsetsConfig: Sendable, Equatable {
    public var left: Double
    public var right: Double
    public var top: Double
    public var bottom: Double

    public init(left: Double = 0, right: Double = 0, top: Double = 0, bottom: Double = 0) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public init(all: Double) {
        self.init(left: all, right: all, top: all, bottom: all)
    }

    public static let zero = GapInsetsConfig()
}

/// Number or per-side table for `[gaps]`.
public enum GapValue: Sendable, Equatable {
    case uniform(Double)
    case perSide(GapInsetsConfig)

    public var asInsets: GapInsetsConfig {
        switch self {
        case .uniform(let n): return GapInsetsConfig(all: n)
        case .perSide(let insets): return insets
        }
    }

    /// Single number for engine inner gap (average when per-side).
    public var asUniform: Double {
        switch self {
        case .uniform(let n): return n
        case .perSide(let i):
            return (i.left + i.right + i.top + i.bottom) / 4
        }
    }
}

public struct GapsConfig: Sendable, Equatable {
    public var inner: GapValue
    public var outer: GapValue

    public init(inner: GapValue = .uniform(10), outer: GapValue = .uniform(10)) {
        self.inner = inner
        self.outer = outer
    }

    public static let `default` = GapsConfig()
}
