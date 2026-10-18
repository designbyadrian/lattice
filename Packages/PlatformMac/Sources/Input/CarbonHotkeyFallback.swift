import Foundation

#if canImport(Carbon)
import Carbon
#endif

/// Stub Carbon hotkey registration used when the active tap is unavailable (safety net).
/// Full registration lands when bindings are wired to AppCore; this type exists so the
/// fallback path compiles and can be unit-tested for enable/disable bookkeeping.
public final class CarbonHotkeyFallback: @unchecked Sendable {
    public private(set) var isEnabled: Bool = false
    public private(set) var registeredCount: Int = 0

    public init() {}

    /// Begin using Carbon hotkeys (no left/right modifier distinction).
    public func enable() {
        isEnabled = true
        // P5: RegisterEventHotKey stubs — real key codes wired when AppCore binds commands.
        registeredCount = 0
    }

    public func disable() {
        isEnabled = false
        registeredCount = 0
    }

    /// Placeholder: would call `RegisterEventHotKey` for each binding.
    @discardableResult
    public func registerStub(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard isEnabled else { return false }
        #if canImport(Carbon)
        // Intentionally not calling RegisterEventHotKey until command routing is live.
        _ = id
        _ = keyCode
        _ = modifiers
        #endif
        registeredCount += 1
        return true
    }
}
