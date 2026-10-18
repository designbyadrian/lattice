import Darwin
import Foundation

/// Named SkyLight / Dock-related symbols resolved at runtime via `dlsym` (never hard-linked).
public struct SpacesSymbolName: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let mainConnectionID = SpacesSymbolName("SLSMainConnectionID")
    public static let copyManagedDisplaySpaces = SpacesSymbolName("SLSCopyManagedDisplaySpaces")
    public static let bridgedSpaceCreate = SpacesSymbolName("SLSBridgedSpaceCreateOperation")
    public static let bridgedSpaceDestroy = SpacesSymbolName("SLSBridgedSpaceDestroyOperation")
    public static let bridgedMoveWindows = SpacesSymbolName("SLSBridgedMoveWindowsToManagedSpaceOperation")
    public static let bridgedPerformSync = SpacesSymbolName("SLSDoBridgedSpaceOperation")
    public static let bridgedPerformAsync = SpacesSymbolName("SLSPerformBridgedSpaceOperation")

    public static let requiredQuery: [SpacesSymbolName] = [
        .mainConnectionID,
        .copyManagedDisplaySpaces,
    ]

    public static let requiredOperations: [SpacesSymbolName] = [
        .bridgedSpaceCreate,
        .bridgedSpaceDestroy,
        .bridgedMoveWindows,
    ]
}

/// Injectable lookup for capability probes and tests (fake symbol tables).
public protocol SpacesSymbolLooking: Sendable {
    func address(for name: SpacesSymbolName) -> UnsafeMutableRawPointer?
}

/// Loads private SkyLight symbols with `dlopen` / `dlsym` only.
public final class SkyLightSymbolTable: SpacesSymbolLooking, @unchecked Sendable {
    public static let shared = SkyLightSymbolTable()

    private let handle: UnsafeMutableRawPointer?
    private let lock = NSLock()
    private var cache: [String: UnsafeMutableRawPointer?] = [:]

    public init(path: String = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight") {
        handle = dlopen(path, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(path, RTLD_LAZY)
    }

    public func address(for name: SpacesSymbolName) -> UnsafeMutableRawPointer? {
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
public struct FakeSpacesSymbolTable: SpacesSymbolLooking, Sendable {
    public var present: Set<String>

    public init(present: Set<String>) {
        self.present = present
    }

    public static var allRequired: FakeSpacesSymbolTable {
        var names = Set(SpacesSymbolName.requiredQuery.map(\.rawValue))
        names.formUnion(SpacesSymbolName.requiredOperations.map(\.rawValue))
        names.insert(SpacesSymbolName.bridgedPerformSync.rawValue)
        return FakeSpacesSymbolTable(present: names)
    }

    public static var queriesOnly: FakeSpacesSymbolTable {
        FakeSpacesSymbolTable(present: Set(SpacesSymbolName.requiredQuery.map(\.rawValue)))
    }

    public func address(for name: SpacesSymbolName) -> UnsafeMutableRawPointer? {
        // Non-nil sentinel: probes only check presence, never call through fake pointers.
        present.contains(name.rawValue) ? UnsafeMutableRawPointer(bitPattern: 1) : nil
    }
}
