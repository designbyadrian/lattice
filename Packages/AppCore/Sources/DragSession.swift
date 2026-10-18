import Foundation
import LayoutModel

/// In-flight title-bar / tab-strip drag (ADDENDUM-2 B3 / B5).
public struct DragSession: Equatable, Sendable {
    public var window: WindowID
    public var originFrame: Rect
    public var currentPoint: Point
    /// Live make-room preview target; nil when cancelled / over undock.
    public var previewTarget: DropTarget?
    /// Centre hold started at (for ~400 ms tab gesture).
    public var centerHoldStarted: Date?
    public var isTabStripDrag: Bool

    public init(
        window: WindowID,
        originFrame: Rect,
        currentPoint: Point,
        previewTarget: DropTarget? = nil,
        centerHoldStarted: Date? = nil,
        isTabStripDrag: Bool = false
    ) {
        self.window = window
        self.originFrame = originFrame
        self.currentPoint = currentPoint
        self.previewTarget = previewTarget
        self.centerHoldStarted = centerHoldStarted
        self.isTabStripDrag = isTabStripDrag
    }

    public static let tabHoldSeconds: TimeInterval = 0.4
}
