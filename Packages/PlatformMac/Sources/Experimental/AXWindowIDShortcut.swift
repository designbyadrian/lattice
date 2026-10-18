import ApplicationServices
import Darwin
import Foundation
import Platform

/// Injectable lookup for `_AXUIElementGetWindow` (tests can force missing symbols).
public protocol AXWindowIDSymbolLooking: Sendable {
    func axUIElementGetWindowAddress() -> UnsafeMutableRawPointer?
}

/// Resolves `_AXUIElementGetWindow` via `dlsym` (never hard-linked).
public final class AXWindowIDSymbolTable: AXWindowIDSymbolLooking, @unchecked Sendable {
    public static let shared = AXWindowIDSymbolTable()

    public static let symbolName = "_AXUIElementGetWindow"

    private let lock = NSLock()
    private var cached: UnsafeMutableRawPointer??

    public init() {}

    public func axUIElementGetWindowAddress() -> UnsafeMutableRawPointer? {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        // Prefer the already-loaded ApplicationServices / HIServices image (RTLD_DEFAULT).
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        let ptr =
            defaultHandle.flatMap { dlsym($0, Self.symbolName) }
            ?? defaultHandle.flatMap { dlsym($0, "AXUIElementGetWindow") }
        cached = .some(ptr)
        return ptr
    }
}

/// Deterministic table for unit tests.
public struct FakeAXWindowIDSymbolTable: AXWindowIDSymbolLooking, Sendable {
    public var present: Bool

    public init(present: Bool) {
        self.present = present
    }

    public func axUIElementGetWindowAddress() -> UnsafeMutableRawPointer? {
        present ? UnsafeMutableRawPointer(bitPattern: 1) : nil
    }
}

private typealias AXUIElementGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

/// Optional private AX → CGWindowID shortcut behind `experimental.axWindowID`.
public enum AXWindowIDShortcut {
    /// Attempts `_AXUIElementGetWindow` when the flag is on.
    /// On missing symbol or call failure: clears `flags.axWindowID`, logs, returns nil.
    public static func cgWindowID(
        for element: AXUIElement,
        flags: inout ExperimentalFlags,
        symbols: any AXWindowIDSymbolLooking = AXWindowIDSymbolTable.shared
    ) -> UInt32? {
        guard flags.axWindowID else { return nil }

        guard let address = symbols.addressOrNil() else {
            disable(&flags, reason: "\(AXWindowIDSymbolTable.symbolName) unavailable")
            return nil
        }

        // Fake tables return a non-callable sentinel; treat as "present but unused".
        if address == UnsafeMutableRawPointer(bitPattern: 1) {
            return nil
        }

        let fn = unsafeBitCast(address, to: AXUIElementGetWindowFn.self)
        var windowID: CGWindowID = 0
        let err = fn(element, &windowID)
        guard err == .success else {
            disable(&flags, reason: "call failed (AXError \(err.rawValue))")
            return nil
        }
        return windowID
    }

    /// Probe-only: whether the private symbol appears to be present (does not mutate flags).
    public static func symbolAvailable(
        symbols: any AXWindowIDSymbolLooking = AXWindowIDSymbolTable.shared
    ) -> Bool {
        symbols.addressOrNil() != nil
    }

    private static func disable(_ flags: inout ExperimentalFlags, reason: String) {
        flags.axWindowID = false
        NSLog("[Lattice Experimental] ax-window-id disabled: %@", reason)
    }
}

private extension AXWindowIDSymbolLooking {
    func addressOrNil() -> UnsafeMutableRawPointer? {
        axUIElementGetWindowAddress()
    }
}
