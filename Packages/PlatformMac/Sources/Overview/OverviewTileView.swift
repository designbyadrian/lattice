import AppKit
import LayoutEngine

/// Collapsed overview tile: app colour + icon (below CollapseThresholds).
public final class OverviewTileView: NSView {
    public var presentation: CollapsePresentation = .windowTile {
        didSet { needsDisplay = true }
    }

    public var appColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }

    public var icon: NSImage? {
        didSet { needsDisplay = true }
    }

    public var showsSplitLines: Bool = false {
        didSet { needsDisplay = true }
    }

    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds
        appColor.withAlphaComponent(0.85).setFill()
        bounds.fill()

        if showsSplitLines || presentation == .groupTile {
            NSColor.white.withAlphaComponent(0.35).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: bounds.midX, y: bounds.minY + 4))
            path.line(to: NSPoint(x: bounds.midX, y: bounds.maxY - 4))
            path.move(to: NSPoint(x: bounds.minX + 4, y: bounds.midY))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: bounds.midY))
            path.stroke()
        }

        if let icon {
            let side = min(bounds.width, bounds.height) * 0.45
            let iconRect = NSRect(
                x: bounds.midX - side / 2,
                y: bounds.midY - side / 2,
                width: side,
                height: side
            )
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
}
