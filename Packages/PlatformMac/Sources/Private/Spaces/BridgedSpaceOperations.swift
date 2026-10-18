import CoreFoundation
import Foundation
import LayoutModel

/// Opaque bridged-operation function shapes. Signatures follow public reverse-engineering
/// notes for SkyLight; all entry points are resolved with `dlsym` and nil-checked.
///
/// Clean-room: we never hard-link these symbols. If a call fails or a symbol is missing,
/// the caller treats the action as failed and does not half-apply a plan.
private typealias BridgedCreateProc = @convention(c) (Int32, CFString?) -> UnsafeMutableRawPointer?
private typealias BridgedDestroyProc = @convention(c) (Int32, UInt64) -> UnsafeMutableRawPointer?
private typealias BridgedMoveProc = @convention(c) (Int32, CFArray, UInt64) -> UnsafeMutableRawPointer?
private typealias BridgedPerformProc = @convention(c) (UnsafeMutableRawPointer?) -> Int32

public struct BridgedSpaceOperations: Sendable {
    public var symbols: any SpacesSymbolLooking

    public init(symbols: any SpacesSymbolLooking = SkyLightSymbolTable.shared) {
        self.symbols = symbols
    }

    public var isAvailable: Bool {
        SpacesSymbolName.requiredOperations.allSatisfy { symbols.address(for: $0) != nil }
            && (symbols.address(for: .bridgedPerformSync) != nil
                || symbols.address(for: .bridgedPerformAsync) != nil)
    }

    /// Create a user Space on the display identified by UUID string. Returns success.
    public func createSpace(onDisplayUUID uuid: String) -> Bool {
        guard let cid = ManagedDisplaySpaces.connectionID(symbols: symbols),
              let createPtr = symbols.address(for: .bridgedSpaceCreate),
              let perform = performProc()
        else { return false }
        let create = unsafeBitCast(createPtr, to: BridgedCreateProc.self)
        let op = create(cid, uuid as CFString)
        guard op != nil else { return false }
        return perform(op) == 0
    }

    /// Destroy an owned user Space. Returns success.
    public func destroySpace(_ space: SpaceID) -> Bool {
        guard let cid = ManagedDisplaySpaces.connectionID(symbols: symbols),
              let destroyPtr = symbols.address(for: .bridgedSpaceDestroy),
              let perform = performProc()
        else { return false }
        let destroy = unsafeBitCast(destroyPtr, to: BridgedDestroyProc.self)
        let op = destroy(cid, space.rawValue)
        guard op != nil else { return false }
        return perform(op) == 0
    }

    /// Move CG window IDs onto `space`.
    public func moveWindows(_ windowIDs: [UInt32], to space: SpaceID) -> Bool {
        guard !windowIDs.isEmpty else { return true }
        guard let cid = ManagedDisplaySpaces.connectionID(symbols: symbols),
              let movePtr = symbols.address(for: .bridgedMoveWindows),
              let perform = performProc()
        else { return false }
        let cfIDs = windowIDs.map { NSNumber(value: $0) } as CFArray
        let move = unsafeBitCast(movePtr, to: BridgedMoveProc.self)
        let op = move(cid, cfIDs, space.rawValue)
        guard op != nil else { return false }
        return perform(op) == 0
    }

    private func performProc() -> BridgedPerformProc? {
        if let ptr = symbols.address(for: .bridgedPerformSync) {
            return unsafeBitCast(ptr, to: BridgedPerformProc.self)
        }
        if let ptr = symbols.address(for: .bridgedPerformAsync) {
            return unsafeBitCast(ptr, to: BridgedPerformProc.self)
        }
        return nil
    }
}
