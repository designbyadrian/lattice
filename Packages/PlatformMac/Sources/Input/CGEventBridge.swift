import AppKit
import CoreGraphics
import Foundation

/// Maps CG events into pure `ClassifiableEvent` shapes (hot path: no AX).
public enum CGEventBridge {
    public static func classifiable(
        _ event: CGEvent,
        type: CGEventType,
        hit: TapHitKind = .pass,
        managedDocked: Bool = false,
        dragActive: Bool = false,
        overAppWindow: Bool = false
    ) -> ClassifiableEvent? {
        let flags = classifierFlags(from: event.flags)
        switch type {
        case .keyDown:
            return ClassifiableEvent(
                kind: .keyDown,
                key: keyName(from: event),
                flags: flags,
                overAppWindow: overAppWindow,
                dragActive: dragActive
            )
        case .keyUp:
            return ClassifiableEvent(
                kind: .keyUp,
                key: keyName(from: event),
                flags: flags,
                overAppWindow: overAppWindow,
                dragActive: dragActive
            )
        case .flagsChanged:
            return ClassifiableEvent(kind: .flagsChanged, flags: flags)
        case .leftMouseDown:
            let click = Int(event.getIntegerValueField(.mouseEventClickState))
            return ClassifiableEvent(
                kind: .leftMouseDown,
                flags: flags,
                overAppWindow: overAppWindow,
                clickState: max(click, 1),
                hit: hit,
                managedDocked: managedDocked,
                dragActive: dragActive
            )
        case .leftMouseDragged:
            return ClassifiableEvent(
                kind: .leftMouseDragged,
                flags: flags,
                overAppWindow: overAppWindow,
                hit: hit,
                managedDocked: managedDocked,
                dragActive: dragActive
            )
        case .leftMouseUp:
            let click = Int(event.getIntegerValueField(.mouseEventClickState))
            return ClassifiableEvent(
                kind: .leftMouseUp,
                flags: flags,
                overAppWindow: overAppWindow,
                clickState: max(click, 1),
                hit: hit,
                managedDocked: managedDocked,
                dragActive: dragActive
            )
        case .mouseMoved:
            return ClassifiableEvent(kind: .mouseMoved, flags: flags, overAppWindow: overAppWindow)
        case .scrollWheel:
            return ClassifiableEvent(kind: .scrollWheel, flags: flags, overAppWindow: overAppWindow)
        default:
            // Magnify / gesture (raw 30).
            if type.rawValue == 30 {
                return ClassifiableEvent(
                    kind: .magnify,
                    flags: flags,
                    overAppWindow: overAppWindow
                )
            }
            return ClassifiableEvent(kind: .other, flags: flags)
        }
    }

    public static func classifierFlags(from flags: CGEventFlags) -> ClassifierFlags {
        var device: DeviceModifierBits = []
        // NX_DEVICEL* masks when present on the event flags raw value.
        let raw = flags.rawValue
        if raw & 0x0000_0001 != 0 { device.insert(.leftControl) }
        if raw & 0x0000_0002 != 0 { device.insert(.leftShift) }
        if raw & 0x0000_0004 != 0 { device.insert(.rightShift) }
        if raw & 0x0000_0008 != 0 { device.insert(.leftCommand) }
        if raw & 0x0000_0010 != 0 { device.insert(.rightCommand) }
        if raw & 0x0000_0020 != 0 { device.insert(.leftOption) }
        if raw & 0x0000_0040 != 0 { device.insert(.rightOption) }
        if raw & 0x0000_2000 != 0 { device.insert(.rightControl) }

        return ClassifierFlags(
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift),
            command: flags.contains(.maskCommand),
            device: device
        )
    }

    /// US-layout key name for binding match (`h`, `1`, `left-bracket`, …).
    public static func keyName(from event: CGEvent) -> String? {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        return keyName(keyCode: code)
    }

    public static func keyName(keyCode: Int64) -> String? {
        switch keyCode {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "equal"
        case 25: return "9"
        case 26: return "7"
        case 27: return "minus"
        case 28: return "8"
        case 29: return "0"
        case 30: return "right-bracket"
        case 31: return "o"
        case 32: return "u"
        case 33: return "left-bracket"
        case 34: return "i"
        case 35: return "p"
        case 36: return "enter"
        case 37: return "l"
        case 38: return "j"
        case 39: return "quote"
        case 40: return "k"
        case 41: return "semicolon"
        case 42: return "backslash"
        case 43: return "comma"
        case 44: return "slash"
        case 45: return "n"
        case 46: return "m"
        case 47: return "period"
        case 48: return "tab"
        case 49: return "space"
        case 50: return "grave"
        case 51: return "delete"
        case 53: return "escape"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        default: return nil
        }
    }
}
