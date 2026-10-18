import Foundation

/// Structural change produced by a pure workspace operation.
public struct LayoutDiff: Equatable, Sendable {
    public var inserted: Set<WindowID>
    public var removed: Set<WindowID>
    public var floated: Set<WindowID>
    public var docked: Set<WindowID>
    public var moved: Set<WindowID>
    public var ratiosChanged: Bool
    public var normalized: Bool

    public init(
        inserted: Set<WindowID> = [],
        removed: Set<WindowID> = [],
        floated: Set<WindowID> = [],
        docked: Set<WindowID> = [],
        moved: Set<WindowID> = [],
        ratiosChanged: Bool = false,
        normalized: Bool = false
    ) {
        self.inserted = inserted
        self.removed = removed
        self.floated = floated
        self.docked = docked
        self.moved = moved
        self.ratiosChanged = ratiosChanged
        self.normalized = normalized
    }

    public static let empty = LayoutDiff()

    public var isEmpty: Bool {
        inserted.isEmpty
            && removed.isEmpty
            && floated.isEmpty
            && docked.isEmpty
            && moved.isEmpty
            && !ratiosChanged
            && !normalized
    }

    public mutating func merge(_ other: LayoutDiff) {
        inserted.formUnion(other.inserted)
        removed.formUnion(other.removed)
        floated.formUnion(other.floated)
        docked.formUnion(other.docked)
        moved.formUnion(other.moved)
        ratiosChanged = ratiosChanged || other.ratiosChanged
        normalized = normalized || other.normalized
    }
}
