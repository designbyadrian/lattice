import Darwin
import Foundation
import Platform

/// Named MultitouchSupport symbols resolved at runtime via `dlsym` (never hard-linked).
public struct MultitouchSymbolName: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let deviceCreateList = MultitouchSymbolName("MTDeviceCreateList")
    public static let deviceStart = MultitouchSymbolName("MTDeviceStart")
    public static let registerContactFrameCallback = MultitouchSymbolName("MTRegisterContactFrameCallback")

    /// Minimum set required to consider the raw multitouch path usable.
    public static let required: [MultitouchSymbolName] = [
        .deviceCreateList,
        .deviceStart,
        .registerContactFrameCallback,
    ]
}

/// Injectable lookup for multitouch capability probes and tests.
public protocol MultitouchSymbolLooking: Sendable {
    func address(for name: MultitouchSymbolName) -> UnsafeMutableRawPointer?
}

/// Loads MultitouchSupport symbols with `dlopen` / `dlsym` only.
public final class MultitouchSymbolTable: MultitouchSymbolLooking, @unchecked Sendable {
    public static let shared = MultitouchSymbolTable()

    private let handle: UnsafeMutableRawPointer?
    private let lock = NSLock()
    private var cache: [String: UnsafeMutableRawPointer?] = [:]

    public init(
        path: String = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    ) {
        handle = dlopen(path, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(path, RTLD_LAZY)
    }

    public func address(for name: MultitouchSymbolName) -> UnsafeMutableRawPointer? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name.rawValue] {
            return cached
        }
        let ptr = handle.flatMap { dlsym($0, name.rawValue) }
        cache[name.rawValue] = ptr
        return ptr
    }
}

/// Deterministic table for unit tests.
public struct FakeMultitouchSymbolTable: MultitouchSymbolLooking, Sendable {
    public var present: Set<String>

    public init(present: Set<String>) {
        self.present = present
    }

    public static var allRequired: FakeMultitouchSymbolTable {
        FakeMultitouchSymbolTable(present: Set(MultitouchSymbolName.required.map(\.rawValue)))
    }

    public static var empty: FakeMultitouchSymbolTable {
        FakeMultitouchSymbolTable(present: [])
    }

    public func address(for name: MultitouchSymbolName) -> UnsafeMutableRawPointer? {
        present.contains(name.rawValue) ? UnsafeMutableRawPointer(bitPattern: 1) : nil
    }
}

/// Raw multitouch session behind `experimental.multitouch`.
///
/// When symbols are missing (or the flag is off), this is a safe no-op.
/// Full gesture wiring is intentionally deferred; P10 only requires the gated structure.
public final class ExperimentalMultitouchSession: @unchecked Sendable {
    public private(set) var isArmed: Bool = false
    private let symbols: any MultitouchSymbolLooking
    private let lock = NSLock()

    public init(symbols: any MultitouchSymbolLooking = MultitouchSymbolTable.shared) {
        self.symbols = symbols
    }

    /// Whether all required MultitouchSupport symbols resolve.
    public static func symbolsAvailable(
        symbols: any MultitouchSymbolLooking = MultitouchSymbolTable.shared
    ) -> Bool {
        MultitouchSymbolName.required.allSatisfy { symbols.address(for: $0) != nil }
    }

    /// Syncs session state with flags. Auto-disables `flags.multitouch` when symbols are missing.
    public func sync(flags: inout ExperimentalFlags) {
        lock.lock()
        defer { lock.unlock() }

        guard flags.multitouch else {
            isArmed = false
            return
        }

        guard Self.symbolsAvailable(symbols: symbols) else {
            flags.multitouch = false
            isArmed = false
            NSLog("[Lattice Experimental] multitouch disabled: MultitouchSupport symbols unavailable")
            return
        }

        // Structure only: arm the path without registering private callbacks (safe no-op).
        isArmed = true
    }
}
