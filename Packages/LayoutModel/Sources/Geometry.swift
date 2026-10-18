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

/// Axis-aligned rectangle in points.
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

    public static let zero = Rect(origin: .zero, size: .zero)
}

/// Side of a node or screen used for docking.
public enum Edge: String, Codable, Sendable, CaseIterable, Equatable {
    case left
    case right
    case top
    case bottom

    /// Axis along which a dock on this edge splits.
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

/// Split orientation.
public enum Axis: String, Codable, Sendable, CaseIterable, Equatable {
    case horizontal
    case vertical
}
