import Foundation
import Config

/// Result of classifying a single input event.
public enum EventClassification: Sendable, Equatable {
    /// Deliver the event to the application.
    case pass
    /// Swallow without emitting a command (e.g. matching keyUp, modifier-drag).
    case swallow
    /// Swallow and enqueue commands asynchronously (never run work in the tap callback).
    case command([Command])
}

/// Pure classifier: event + flags + config (+ safety net) → pass / swallow / command.
/// Tap callback must only call this and return; all side effects happen async.
public struct EventClassifier: Sendable {
    public var config: LatticeConfig
    public var safetyNet: InputSafetyNetState
    public var currentMode: String

    public init(
        config: LatticeConfig = .default,
        safetyNet: InputSafetyNetState = .full,
        currentMode: String = DefaultBindings.modeName
    ) {
        self.config = config
        self.safetyNet = safetyNet
        self.currentMode = currentMode
    }

    public func classify(_ event: ClassifiableEvent) -> EventClassification {
        switch event.kind {
        case .keyDown:
            return classifyKeyDown(event)
        case .keyUp:
            return classifyKeyUp(event)
        case .leftMouseDown, .leftMouseDragged:
            return classifyModifierDrag(event)
        case .leftMouseUp:
            // Swallow mouse-up only if we would have swallowed the drag (pair with modifier).
            if !safetyNet.disablesModifierDrag,
               event.flags.containsAtLeast(config.modifiers.frameModifier),
               config.modifiers.frameModifier.isEmpty == false {
                return .swallow
            }
            return .pass
        case .magnify:
            return classifyPinch(event)
        case .flagsChanged, .mouseMoved, .scrollWheel, .other:
            return .pass
        }
    }

    // MARK: - Keys

    private func classifyKeyDown(_ event: ClassifiableEvent) -> EventClassification {
        guard let key = event.key else { return .pass }
        guard let binding = matchBinding(key: key, flags: event.flags) else {
            return .pass
        }
        return .command(binding.commands)
    }

    private func classifyKeyUp(_ event: ClassifiableEvent) -> EventClassification {
        guard let key = event.key else { return .pass }
        // Swallow keyUps for bound chords so apps never see a half-consumed shortcut.
        if matchBinding(key: key, flags: event.flags) != nil {
            return .swallow
        }
        return .pass
    }

    private func matchBinding(key: String, flags: ClassifierFlags) -> KeyBinding? {
        guard let mode = config.modes[currentMode] else { return nil }
        for binding in mode.bindings {
            guard binding.chord.key == key else { continue }
            guard flags.containsExact(binding.chord.modifiers) else { continue }
            if !safetyNet.disablesLeftRightModifiers {
                guard sidesMatch(flags: flags, required: binding.chord.modifiers) else { continue }
            }
            return binding
        }
        return nil
    }

    private func sidesMatch(flags: ClassifierFlags, required: ModifierSet) -> Bool {
        let policy = config.modifiers
        if required.option {
            guard sideOK(
                policy: policy.alt,
                left: flags.device.contains(.leftOption),
                right: flags.device.contains(.rightOption),
                logical: flags.option
            ) else { return false }
        }
        if required.control {
            guard sideOK(
                policy: policy.ctrl,
                left: flags.device.contains(.leftControl),
                right: flags.device.contains(.rightControl),
                logical: flags.control
            ) else { return false }
        }
        if required.shift {
            guard sideOK(
                policy: policy.shift,
                left: flags.device.contains(.leftShift),
                right: flags.device.contains(.rightShift),
                logical: flags.shift
            ) else { return false }
        }
        if required.command {
            guard sideOK(
                policy: policy.cmd,
                left: flags.device.contains(.leftCommand),
                right: flags.device.contains(.rightCommand),
                logical: flags.command
            ) else { return false }
        }
        return true
    }

    private func sideOK(policy: ModifierSide, left: Bool, right: Bool, logical: Bool) -> Bool {
        guard logical else { return false }
        switch policy {
        case .both:
            return true
        case .left:
            // If device bits missing, accept logical (some events omit them).
            if !left && !right { return true }
            return left
        case .right:
            if !left && !right { return true }
            return right
        }
    }

    // MARK: - Mouse / pinch

    private func classifyModifierDrag(_ event: ClassifiableEvent) -> EventClassification {
        if safetyNet.disablesModifierDrag { return .pass }
        let required = config.modifiers.frameModifier
        guard !required.isEmpty else { return .pass }
        // Frame-rect swallows with the modifier held over apps or desktop (ADDENDUM-2 B4).
        guard event.flags.containsAtLeast(required) else { return .pass }
        return .swallow
    }

    private func classifyPinch(_ event: ClassifiableEvent) -> EventClassification {
        if safetyNet.disablesPinchOverApps { return .pass }
        let required = config.modifiers.pinchModifier
        guard !required.isEmpty else { return .pass }
        // With pinch-modifier held over any window → swallow.
        if event.overAppWindow && event.flags.containsAtLeast(required) {
            return .swallow
        }
        return .pass
    }
}
