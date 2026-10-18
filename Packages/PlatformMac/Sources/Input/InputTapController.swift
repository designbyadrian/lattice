import AppKit
import ApplicationServices
import Config
import CoreGraphics
import Foundation

/// Owns the active event tap and routes classifications to AppCore asynchronously.
/// Green-button / double-click / modifier-drag use `EventClassifier` with a cached hit.
public final class InputTapController: @unchecked Sendable {
    public private(set) var tap: ActiveEventTap?
    public private(set) var classifier: EventClassifier
    public private(set) var carbonFallback = CarbonHotkeyFallback()

    /// Latest AX hit for mouse-down classification (updated async; read on tap thread).
    private let hitLock = NSLock()
    private var cachedHit: TapHitKind = .pass
    private var cachedManagedDocked: Bool = false
    private var cachedOverApp: Bool = false
    private var dragActive: Bool = false

    public var onCommands: (([Command]) -> Void)?
    public var onGreenButton: (() -> Void)?
    public var onModifierDrag: ((CGPoint) -> Void)?
    public var onDragCancel: (() -> Void)?
    public var isDragSessionActive: (() -> Bool)?

    public init(
        config: LatticeConfig = .default,
        safetyNet: InputSafetyNetState = .full
    ) {
        self.classifier = EventClassifier(config: config, safetyNet: safetyNet)
    }

    public func update(config: LatticeConfig, safetyNet: InputSafetyNetState, mode: String) {
        classifier.config = config
        classifier.safetyNet = safetyNet
        classifier.currentMode = mode
    }

    public func setDragActive(_ active: Bool) {
        hitLock.lock()
        dragActive = active
        hitLock.unlock()
    }

    @discardableResult
    public func start() -> Bool {
        stop()
        do {
            let tap = try ActiveEventTap(mask: ActiveEventTap.defaultMask, listenOnly: false) {
                [weak self] event in
                self?.handle(event) ?? Unmanaged.passUnretained(event)
            }
            self.tap = tap
            carbonFallback.disable()
            return true
        } catch {
            carbonFallback.enable()
            return false
        }
    }

    public func stop() {
        tap?.stop()
        tap = nil
    }

    // MARK: - Tap callback (classify only)

    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let type = event.type
        hitLock.lock()
        let hit = cachedHit
        let docked = cachedManagedDocked
        let overApp = cachedOverApp
        let dragging = dragActive || (isDragSessionActive?() ?? false)
        hitLock.unlock()

        guard let shaped = CGEventBridge.classifiable(
            event,
            type: type,
            hit: hit,
            managedDocked: docked,
            dragActive: dragging,
            overAppWindow: overApp
        ) else {
            return Unmanaged.passUnretained(event)
        }

        // Kick async AX hit refresh on mouse-down (never block the tap).
        if type == .leftMouseDown {
            let loc = event.location
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                self?.refreshHit(at: loc)
            }
        }

        let result = classifier.classify(shaped)
        switch result {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            if type == .leftMouseDown, shaped.hit == .greenButton {
                DispatchQueue.main.async { [weak self] in self?.onGreenButton?() }
            }
            if type == .leftMouseDragged,
               shaped.flags.containsAtLeast(classifier.config.modifiers.frameModifier) {
                let loc = event.location
                DispatchQueue.main.async { [weak self] in
                    self?.onModifierDrag?(CGPoint(x: loc.x, y: loc.y))
                }
            }
            if type == .keyDown, shaped.key == "escape", dragging {
                DispatchQueue.main.async { [weak self] in self?.onDragCancel?() }
            }
            return nil
        case .command(let commands):
            DispatchQueue.main.async { [weak self] in self?.onCommands?(commands) }
            return nil
        }
    }

    private func refreshHit(at point: CGPoint) {
        // Best-effort AX hit-test for title bar / green button / bare desktop.
        var hit: TapHitKind = .pass
        var docked = false
        var overApp = false

        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        if err == .success, let element {
            overApp = true
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            let roleStr = role as? String
            if roleStr == (kAXButtonRole as String) {
                var subrole: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
                if (subrole as? String) == (kAXZoomButtonSubrole as String)
                    || (subrole as? String)?.lowercased().contains("fullscreen") == true {
                    hit = .greenButton
                } else {
                    hit = .titleBarControl
                }
            } else if roleStr == (kAXWindowRole as String) {
                // Rough: top band ≈ title bar.
                var pos: CFTypeRef?
                var size: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos)
                AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
                var p = CGPoint.zero
                var s = CGSize.zero
                if let pos, AXValueGetType(pos as! AXValue) == .cgPoint {
                    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
                }
                if let size, AXValueGetType(size as! AXValue) == .cgSize {
                    AXValueGetValue(size as! AXValue, .cgSize, &s)
                }
                if point.y >= p.y && point.y <= p.y + 28 {
                    hit = .titleBar
                    docked = true // refined by AppCore when handling
                } else {
                    hit = .content
                }
            } else {
                hit = .content
            }
        } else {
            hit = .bareDesktop
            overApp = false
        }

        hitLock.lock()
        cachedHit = hit
        cachedManagedDocked = docked
        cachedOverApp = overApp
        hitLock.unlock()
    }
}
