import Foundation
import Config

/// Device-dependent modifier side bits (same values as NX_DEVICE*KEYMASK).
public struct DeviceModifierBits: OptionSet, Sendable, Equatable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let leftControl = DeviceModifierBits(rawValue: 0x0000_0001)
    public static let leftShift = DeviceModifierBits(rawValue: 0x0000_0002)
    public static let rightShift = DeviceModifierBits(rawValue: 0x0000_0004)
    public static let leftCommand = DeviceModifierBits(rawValue: 0x0000_0008)
    public static let rightCommand = DeviceModifierBits(rawValue: 0x0000_0010)
    public static let leftOption = DeviceModifierBits(rawValue: 0x0000_0020)
    public static let rightOption = DeviceModifierBits(rawValue: 0x0000_0040)
    public static let rightControl = DeviceModifierBits(rawValue: 0x0000_2000)
}

/// Logical modifier flags independent of AppKit (for pure classification).
public struct ClassifierFlags: Sendable, Equatable {
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var command: Bool
    public var device: DeviceModifierBits

    public init(
        control: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        command: Bool = false,
        device: DeviceModifierBits = []
    ) {
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
        self.device = device
    }

    public var asModifierSet: ModifierSet {
        ModifierSet(control: control, option: option, shift: shift, command: command)
    }

    public func matches(_ required: ModifierSet) -> Bool {
        control == required.control
            && option == required.option
            && shift == required.shift
            && command == required.command
    }

    /// Whether held modifiers satisfy a required set (extras allowed = false for chords).
    public func containsExact(_ required: ModifierSet) -> Bool {
        matches(required)
    }

    public func containsAtLeast(_ required: ModifierSet) -> Bool {
        (!required.control || control)
            && (!required.option || option)
            && (!required.shift || shift)
            && (!required.command || command)
    }
}

public enum ClassifiableEventKind: Sendable, Equatable {
    case keyDown
    case keyUp
    case flagsChanged
    case leftMouseDown
    case leftMouseDragged
    case leftMouseUp
    case mouseMoved
    case scrollWheel
    case magnify
    case other
}

/// Hit result from the pure tap classifier (AX resolved async after swallow decisions).
public enum TapHitKind: String, Sendable, Equatable {
    case pass
    case bareDesktop
    case titleBar
    case titleBarControl
    case greenButton
    case content
}

/// Pure event shape for `EventClassifier` (no CGEvent in the hot path of tests).
public struct ClassifiableEvent: Sendable, Equatable {
    public var kind: ClassifiableEventKind
    /// US-layout key name when kind is keyDown/keyUp (`h`, `enter`, `1`, …).
    public var key: String?
    public var flags: ClassifierFlags
    /// True when the pointer is over a foreign app window (for modifier-drag / pinch).
    public var overAppWindow: Bool
    /// `kCGMouseEventClickState` (1 = single, 2 = double, …).
    public var clickState: Int
    /// Cached hit classification for mouse-down (desktop / title / green / …).
    public var hit: TapHitKind
    /// True when the window under the pointer is managed and docked (tiled).
    public var managedDocked: Bool
    /// True while a Lattice drag is active (Esc cancel).
    public var dragActive: Bool

    public init(
        kind: ClassifiableEventKind,
        key: String? = nil,
        flags: ClassifierFlags = ClassifierFlags(),
        overAppWindow: Bool = false,
        clickState: Int = 1,
        hit: TapHitKind = .pass,
        managedDocked: Bool = false,
        dragActive: Bool = false
    ) {
        self.kind = kind
        self.key = key?.lowercased()
        self.flags = flags
        self.overAppWindow = overAppWindow
        self.clickState = clickState
        self.hit = hit
        self.managedDocked = managedDocked
        self.dragActive = dragActive
    }
}
