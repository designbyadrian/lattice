import Foundation

/// 2D point in display coordinates (points, not pixels).
public struct Point: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point(x: 0, y: 0)
}

/// 2D size in points.
public struct Size: Equatable, Hashable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Size(width: 0, height: 0)
}

/// Axis-aligned rectangle as origin + size (screen points).
public struct Rect: Equatable, Hashable, Codable, Sendable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.origin = Point(x: x, y: y)
        self.size = Size(width: width, height: height)
    }

    /// Build from `(x, y, w, h)` tuple.
    public init(xywh: (Double, Double, Double, Double)) {
        self.init(x: xywh.0, y: xywh.1, width: xywh.2, height: xywh.3)
    }

    public var x: Double {
        get { origin.x }
        set { origin.x = newValue }
    }

    public var y: Double {
        get { origin.y }
        set { origin.y = newValue }
    }

    public var width: Double {
        get { size.width }
        set { size.width = newValue }
    }

    public var height: Double {
        get { size.height }
        set { size.height = newValue }
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public var xywh: (Double, Double, Double, Double) { (x, y, width, height) }

    public static let zero = Rect(origin: .zero, size: .zero)

    public func contains(point: Point) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

/// World / camera / content rect stored as edges `(x0, y0, x1, y1)`.
/// Shared edges stay bit-identical across neighbours.
public struct EdgeRect: Equatable, Hashable, Codable, Sendable {
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double

    public init(x0: Double, y0: Double, x1: Double, y1: Double) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    public init(_ tuple: (Double, Double, Double, Double)) {
        self.init(x0: tuple.0, y0: tuple.1, x1: tuple.2, y1: tuple.3)
    }

    public static let unit = EdgeRect(x0: 0, y0: 0, x1: 1, y1: 1)

    public var width: Double { x1 - x0 }
    public var height: Double { y1 - y0 }

    public var asTuple: (Double, Double, Double, Double) { (x0, y0, x1, y1) }

    public func contains(pointX x: Double, y: Double) -> Bool {
        x0 <= x && x <= x1 && y0 <= y && y <= y1
    }
}

/// Side of a node or screen used for docking.
public enum Edge: String, Codable, Sendable, CaseIterable, Equatable {
    case left
    case right
    case top
    case bottom

    public var splitAxis: Axis {
        switch self {
        case .left, .right: return .horizontal
        case .top, .bottom: return .vertical
        }
    }

    /// Whether the new node is placed before the existing content.
    public var placesNewFirst: Bool {
        switch self {
        case .left, .top: return true
        case .right, .bottom: return false
        }
    }
}

/// Split orientation. `horizontal` = side by side (Python `'h'`), `vertical` = stacked (`'v'`).
public enum Axis: String, Codable, Sendable, CaseIterable, Equatable {
    case horizontal
    case vertical

    public var code: String {
        switch self {
        case .horizontal: return "h"
        case .vertical: return "v"
        }
    }

    public static func from(code: String) -> Axis {
        code == "v" ? .vertical : .horizontal
    }
}

public enum LayoutMath {
    public static let tol = 1e-9
    public static let inf = Double.infinity

    public static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        max(lo, min(hi, v))
    }

    /// `floor(v + 0.5)` — matches Python `rnd`.
    public static func rnd(_ v: Double) -> Double {
        floor(v + 0.5)
    }

    public static func isValidRatio(_ r: Double) -> Bool {
        r.isFinite && r > 0
    }
}
