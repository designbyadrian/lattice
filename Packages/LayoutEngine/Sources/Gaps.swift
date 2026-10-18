import Foundation
import LayoutModel

/// Per-side outer inset around the tiling area (legacy AppCore helper).
public struct GapInsets: Equatable, Hashable, Codable, Sendable {
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

    public static let zero = GapInsets()
}

/// Inner gap between tiled siblings and outer insets from the display edge.
public struct Gaps: Equatable, Hashable, Codable, Sendable {
    public var inner: Double
    public var outer: GapInsets

    public init(inner: Double = 0, outer: GapInsets = .zero) {
        self.inner = max(0, inner)
        self.outer = GapInsets(
            left: max(0, outer.left),
            right: max(0, outer.right),
            top: max(0, outer.top),
            bottom: max(0, outer.bottom)
        )
    }

    public static let zero = Gaps()

    public func contentRect(in displayRect: Rect) -> Rect {
        let x = displayRect.x + outer.left
        let y = displayRect.y + outer.top
        let width = max(0, displayRect.width - outer.left - outer.right)
        let height = max(0, displayRect.height - outer.top - outer.bottom)
        return Rect(x: x, y: y, width: width, height: height)
    }
}
