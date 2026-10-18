import AppKit
import CoreGraphics
import Foundation
import Platform

/// Warps the cursor to the centre of a target display (Dock swipes the display under the cursor).
public enum CursorWarp {
    public struct RestorePoint: Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public static func currentLocation() -> RestorePoint {
        let pt = NSEvent.mouseLocation
        // AppKit bottom-left → CG top-left for warp.
        let screens = NSScreen.screens
        let height = screens.map(\.frame.maxY).max() ?? pt.y
        return RestorePoint(x: Double(pt.x), y: Double(height - pt.y))
    }

    @discardableResult
    public static func warpToCenter(of display: DisplayRef) -> RestorePoint {
        let previous = currentLocation()
        let cx = CGFloat(display.frame.midX)
        let cyGlobal = CGFloat(display.frame.midY)
        // DisplayRef frames are AppKit-style from MacDisplays (bottom-left origin).
        let screens = NSScreen.screens
        let height = screens.map(\.frame.maxY).max() ?? cyGlobal
        let cgY = height - cyGlobal
        CGWarpMouseCursorPosition(CGPoint(x: cx, y: cgY))
        return previous
    }

    public static func restore(_ point: RestorePoint) {
        CGWarpMouseCursorPosition(CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
    }
}
