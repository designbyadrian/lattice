import Foundation

/// Structural change produced by a pure workspace operation.
public struct LayoutDiff: Equatable, Sendable {
    public var inserted: Set<NodeID>
    public var removed: Set<NodeID>
    public var floated: Set<NodeID>
    public var docked: Set<NodeID>
    public var moved: Set<NodeID>
    public var ratiosChanged: Bool
    public var normalized: Bool

    public init(
        inserted: Set<NodeID> = [],
        removed: Set<NodeID> = [],
        floated: Set<NodeID> = [],
        docked: Set<NodeID> = [],
        moved: Set<NodeID> = [],
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
