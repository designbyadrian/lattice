import Foundation
import CoreGraphics
import Platform

/// The only approved constructor for Lattice event taps.
///
/// Always uses an **active** tap (`kCGEventTapOptionDefault`) at `cgSessionEventTap`
/// unless explicitly constructing a listen-only tap **without** keyboard events in the mask.
/// Listen-only + keyboard is forbidden (triggers Input Monitoring) and throws before create.
public final class ActiveEventTap: @unchecked Sendable {
    public enum TapError: Error, Equatable, CustomStringConvertible {
        case listenOnlyWithKeyboardForbidden
        case creationFailed

        public var description: String {
            switch self {
            case .listenOnlyWithKeyboardForbidden:
                return "Refusing listen-only event tap that includes keyboard events (Input Monitoring risk)."
            case .creationFailed:
                return "CGEvent.tapCreate failed."
            }
        }
    }

    /// Key-down / key-up bits that must never appear with `listenOnly == true`.
    public static let keyboardEventMask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

    /// Default Lattice mask: mouse, scroll, gesture/magnify, flagsChanged, keys.
    public static var defaultMask: CGEventMask {
        var mask: CGEventMask = 0
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved, .scrollWheel,
            .flagsChanged,
            .keyDown, .keyUp,
        ]
        for t in types {
            mask |= (1 << t.rawValue)
        }
        // Gesture / magnify (NSEvent.EventType.magnify raw 30 on modern macOS).
        mask |= (1 << 30)
        return mask
    }

    public private(set) var listenOnly: Bool
    public private(set) var mask: CGEventMask
    public private(set) var isEnabled: Bool = false
    public private(set) var timeoutDisableCount: Int = 0
    public private(set) var timeoutWindowStart: Date = .distantPast
    public private(set) var timeoutsInCurrentMinute: Int = 0

    /// Soft warning threshold (menu should show a notice above this).
    public static let timeoutWarningPerMinute = 5

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let classify: (CGEvent) -> Unmanaged<CGEvent>?
    /// When true, skip CGEvent.tapCreate (unit tests of policy / bookkeeping).
    private let dryRun: Bool

    public var showsTimeoutWarning: Bool {
        timeoutsInCurrentMinute >= Self.timeoutWarningPerMinute
    }

    /// - Parameters:
    ///   - mask: event mask
    ///   - listenOnly: must be false when mask includes keyboard (enforced)
    ///   - dryRun: validate policy only; do not call into CGEvent (for tests)
    ///   - handler: returns the event to pass, or nil to swallow. Must stay ~1 ms: classify only.
    public init(
        mask: CGEventMask = ActiveEventTap.defaultMask,
        listenOnly: Bool = false,
        dryRun: Bool = false,
        handler: @escaping (CGEvent) -> Unmanaged<CGEvent>?
    ) throws {
        // Never assert+trap here: callers (and unit tests) must get a thrown error.
        if listenOnly && Self.maskContainsKeyboard(mask) {
            throw TapError.listenOnlyWithKeyboardForbidden
        }

        self.mask = mask
        self.listenOnly = listenOnly
        self.classify = handler
        self.dryRun = dryRun

        if dryRun {
            self.isEnabled = true
            return
        }

        let options: CGEventTapOptions = listenOnly ? .listenOnly : .defaultTap
        let placement = CGEventTapPlacement.headInsertEventTap
        let location = CGEventTapLocation.cgSessionEventTap

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: location,
            place: placement,
            options: options,
            eventsOfInterest: mask,
            callback: ActiveEventTap.cgCallback,
            userInfo: userInfo
        ) else {
            throw TapError.creationFailed
        }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.isEnabled = true
    }

    deinit {
        stop()
    }

    public func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        port = nil
        runLoopSource = nil
        isEnabled = false
    }

    /// Re-enable after `tapDisabledByTimeout` / `tapDisabledByUserInput`.
    public func handleTapDisabled() {
        timeoutDisableCount += 1
        let now = Date()
        if now.timeIntervalSince(timeoutWindowStart) >= 60 {
            timeoutWindowStart = now
            timeoutsInCurrentMinute = 1
        } else {
            timeoutsInCurrentMinute += 1
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
            isEnabled = true
        } else if dryRun {
            isEnabled = true
        }
    }

    // MARK: - Policy (also used by tests without creating a tap)

    public static func maskContainsKeyboard(_ mask: CGEventMask) -> Bool {
        (mask & keyboardEventMask) != 0
    }

    /// Validates construction policy without creating a system tap.
    /// The only tap constructor (`init`) calls this invariant before `CGEvent.tapCreate`.
    public static func validate(mask: CGEventMask, listenOnly: Bool) throws {
        if listenOnly && maskContainsKeyboard(mask) {
            throw TapError.listenOnlyWithKeyboardForbidden
        }
    }

    // MARK: - Callback

    private static let cgCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let tap = Unmanaged<ActiveEventTap>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tap.handleTapDisabled()
            return Unmanaged.passUnretained(event)
        }

        // Budget: classify / return only — no AX, I/O, or locks.
        return tap.classify(event)
    }
}

// Silence unused proxy warning by referencing the callback signature only.
extension ActiveEventTap: InputEvents {}
