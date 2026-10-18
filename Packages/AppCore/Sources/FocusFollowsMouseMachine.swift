import Foundation
import Config

/// Pure focus-follows-mouse state machine (PLAN §7a). Drive with synthetic events in tests.
public struct FocusFollowsMouseMachine: Sendable, Equatable {
    public enum SuppressionReason: Sendable, Equatable {
        case buttonDown
        case menuOpen
        case postActivation
    }

    public enum Action: Sendable, Equatable {
        case none
        /// Start / restart the settle timer for this window key.
        case armTimer(windowKey: String, delayMs: Int)
        case cancelTimer
        /// Focus the window identified by `windowKey` after the delay elapsed.
        case focus(windowKey: String)
    }

    public var config: FocusFollowsMouseConfig
    public var buttonDown: Bool = false
    public var menuOpen: Bool = false
    /// After Cmd-Tab / Space change until the pointer moves to a *different* window.
    public var postActivationSuppressed: Bool = false
    public var lastArmedKey: String?
    public var pendingKey: String?

    public init(config: FocusFollowsMouseConfig = .default) {
        self.config = config
    }

    public mutating func setEnabled(_ enabled: Bool) {
        config.enabled = enabled
        if !enabled {
            lastArmedKey = nil
            pendingKey = nil
        }
    }

    public mutating func noteButtonDown() -> Action {
        buttonDown = true
        pendingKey = nil
        lastArmedKey = nil
        return .cancelTimer
    }

    public mutating func noteButtonUp() -> Action {
        buttonDown = false
        return .none
    }

    public mutating func noteMenuOpen(_ open: Bool) -> Action {
        menuOpen = open
        if open {
            pendingKey = nil
            lastArmedKey = nil
            return .cancelTimer
        }
        return .none
    }

    /// Call after Cmd-Tab or Space change.
    public mutating func noteActivationOrSpaceChange() -> Action {
        postActivationSuppressed = true
        pendingKey = nil
        lastArmedKey = nil
        return .cancelTimer
    }

    /// Pointer moved over `windowKey` (nil = empty / unmanaged / excluded).
    public mutating func notePointer(over windowKey: String?) -> Action {
        guard config.enabled else { return .none }

        if postActivationSuppressed {
            if let windowKey, windowKey != lastArmedKey {
                // Leaving the post-activation window (or first move onto a different one) clears suppression.
                if lastArmedKey == nil {
                    lastArmedKey = windowKey
                    return .none
                }
                if windowKey != lastArmedKey {
                    postActivationSuppressed = false
                } else {
                    return .none
                }
            } else if windowKey == nil {
                postActivationSuppressed = false
            } else {
                return .none
            }
        }

        if buttonDown || menuOpen {
            return .cancelTimer
        }

        guard let windowKey else {
            pendingKey = nil
            return .cancelTimer
        }

        if windowKey == pendingKey {
            return .none
        }
        pendingKey = windowKey
        lastArmedKey = windowKey
        return .armTimer(windowKey: windowKey, delayMs: config.delayMs)
    }

    /// Timer fired for `windowKey`.
    public mutating func noteTimerFired(for windowKey: String) -> Action {
        guard config.enabled, !buttonDown, !menuOpen, !postActivationSuppressed else {
            return .none
        }
        guard pendingKey == windowKey else { return .none }
        pendingKey = nil
        return .focus(windowKey: windowKey)
    }

    public func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return config.excludeApps.contains(bundleID)
    }
}
