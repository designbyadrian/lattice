import Foundation

/// Codable rectangle without importing CoreGraphics into protocol clients.
public struct CGRectCodable: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public static let zero = CGRectCodable(x: 0, y: 0, width: 0, height: 0)

    /// Approximate equality for matching AX ↔ CG frames (points).
    public func isApproximatelyEqual(to other: CGRectCodable, tolerance: Double = 2.0) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
