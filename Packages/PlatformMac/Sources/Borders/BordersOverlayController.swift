import AppKit
import AppCore
import Config
import LayoutModel

/// Click-through border rings tracking window frames (PLAN §7a `[borders]`).
@MainActor
public final class BordersOverlayController {
    private var windows: [WindowID: NSWindow] = [:]
    public var config: BordersConfig = .default
    public var increaseContrast: Bool = false

    public init() {}

    public func update(
        frames: [WindowID: Rect],
        focused: WindowID?,
        bundleIDs: [WindowID: String?]
    ) {
        guard config.enabled else {
            hideAll()
            return
        }
        let width = BorderGeometry.effectiveWidth(
            configured: config.width,
            increaseContrast: increaseContrast
        )
        let activeColor = NSColor.controlAccentColor
        let inactive: NSColor = {
            if case .hex(let hex) = config.inactiveColor,
               let rgba = try? BorderGeometry.parseHex(hex) {
                return NSColor(
                    srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a
                )
            }
            return NSColor(srgbRed: 0.29, green: 0.30, blue: 0.39, alpha: 1)
        }()

        var keep = Set<WindowID>()
        for (id, frame) in frames {
            if let bundle = bundleIDs[id] ?? id.bundleID,
               config.excludeApps.contains(bundle) {
                continue
            }
            keep.insert(id)
            let border = BorderGeometry.borderFrame(
                windowFrame: (frame.x, frame.y, frame.width, frame.height),
                width: width
            )
            let win = windows[id] ?? makeBorderWindow()
            windows[id] = win
            let isFocused = id == focused
            let color: NSColor
            if isFocused {
                if case .accent = config.activeColor {
                    color = activeColor
                } else if case .hex(let hex) = config.activeColor,
                          let rgba = try? BorderGeometry.parseHex(hex) {
                    color = NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
                } else {
                    color = activeColor
                }
            } else {
                color = inactive
            }
            win.backgroundColor = color
            win.setFrame(
                NSRect(x: border.x, y: border.y, width: border.width, height: border.height),
                display: true
            )
            win.orderFrontRegardless()
            if let content = win.contentView {
                content.wantsLayer = true
                content.layer?.borderWidth = 0
                // Hollow via mask: clear inner rect.
                let hole = BorderGeometry.innerHole(
                    borderFrame: border,
                    width: width
                )
                let outer = CGRect(x: 0, y: 0, width: border.width, height: border.height)
                let path = CGMutablePath()
                path.addRect(outer)
                path.addRect(CGRect(
                    x: hole.x - border.x,
                    y: hole.y - border.y,
                    width: hole.width,
                    height: hole.height
                ))
                let mask = CAShapeLayer()
                mask.fillRule = .evenOdd
                mask.path = path
                content.layer?.mask = mask
            }
            switch config.order {
            case .above: win.level = .floating
            case .below: win.level = .normal
            }
            win.ignoresMouseEvents = true
        }
        for id in windows.keys where !keep.contains(id) {
            windows[id]?.orderOut(nil)
            windows[id] = nil
        }
        windows = windows.filter { keep.contains($0.key) }
    }

    public func hideAll() {
        for win in windows.values {
            win.orderOut(nil)
        }
        windows.removeAll()
    }

    private func makeBorderWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.level = .normal
        return win
    }
}
