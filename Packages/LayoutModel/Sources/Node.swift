import Foundation

/// Layout tree node identity (matches refimpl string ids: `"A"`, `"desktop"`, `"s1"`, …).
public typealias NodeID = String

/// Index path from the workspace root into the layout tree (legacy helper for AppCore).
public typealias NodePath = [Int]

/// Nested layout tree node (ADDENDUM-3).
public indirect enum LayoutNode: Equatable, Codable, Sendable {
    case split(Split)
    case window(WindowLeaf)
    case tabs(TabGroup)
    case desktop(DesktopArea)

    public var id: NodeID {
        switch self {
        case .split(let s): return s.id
        case .window(let w): return w.id
        case .tabs(let t): return t.id
        case .desktop(let d): return d.id
        }
    }
}

/// Binary-or-more split along one axis with proportional ratios.
public struct Split: Equatable, Codable, Sendable {
    public var axis: Axis
    public var children: [LayoutNode]
    /// Stored preferences; sum to 1 after normalize; each ≥ min-ratio.
    public var ratios: [Double]
    public var id: NodeID

    public init(axis: Axis, children: [LayoutNode], ratios: [Double], id: NodeID = Split.makeID()) {
        self.axis = axis
        self.children = children
        self.ratios = ratios
        self.id = id
    }

    public static func makeID() -> NodeID {
        SplitIDCounter.next()
    }

    /// Reset auto-ids (tests).
    public static func resetIDCounter(to value: Int = 1) {
        SplitIDCounter.reset(to: value)
    }
}

private final class SplitIDCounter: @unchecked Sendable {
    static let shared = SplitIDCounter()
    private let lock = NSLock()
    private var value = 1

    static func next() -> NodeID {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        let n = shared.value
        shared.value += 1
        return "s\(n)"
    }

    static func reset(to value: Int) {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        shared.value = value
    }
}

extension Split {
    public var hasValidRatios: Bool {
        guard children.count == ratios.count, children.count >= 2 else { return false }
        guard ratios.allSatisfy({ $0 >= 0 }) else { return false }
        return abs(ratios.reduce(0, +) - 1) < 1e-6
    }

    public static func equal(axis: Axis, children: [LayoutNode], id: NodeID? = nil) -> Split {
        let n = max(children.count, 1)
        let r = 1.0 / Double(n)
        return Split(
            axis: axis,
            children: children,
            ratios: Array(repeating: r, count: children.count),
            id: id ?? makeID()
        )
    }
}

/// Helpers matching Python `H(...)` / `V(...)`.
public enum SplitBuilder {
    public static func H(_ kids: LayoutNode..., ratios: [Double]? = nil, id: NodeID? = nil) -> LayoutNode {
        h(Array(kids), ratios: ratios, id: id)
    }

    public static func V(_ kids: LayoutNode..., ratios: [Double]? = nil, id: NodeID? = nil) -> LayoutNode {
        v(Array(kids), ratios: ratios, id: id)
    }

    public static func h(_ kids: [LayoutNode], ratios: [Double]? = nil, id: NodeID? = nil) -> LayoutNode {
        let r = ratios ?? Array(repeating: 1.0 / Double(kids.count), count: kids.count)
        return .split(Split(axis: .horizontal, children: kids, ratios: r, id: id ?? Split.makeID()))
    }

    public static func v(_ kids: [LayoutNode], ratios: [Double]? = nil, id: NodeID? = nil) -> LayoutNode {
        let r = ratios ?? Array(repeating: 1.0 / Double(kids.count), count: kids.count)
        return .split(Split(axis: .vertical, children: kids, ratios: r, id: id ?? Split.makeID()))
    }
}

/// Leaf that holds a single tiled window.
public struct WindowLeaf: Equatable, Codable, Sendable {
    /// Stable app / golden identity. Layout key is `identity.nodeID`.
    public var identity: WindowID
    /// App/learned/rule minimum (points).
    public var appMin: Size?
    public var appMax: Size?
    public var natural: Size?
    /// Node whose space this window took when docked.
    public var donor: NodeID?

    public var id: NodeID {
        get { identity.nodeID }
        set { identity = WindowID.named(newValue) }
    }

    public init(
        identity: WindowID,
        appMin: Size? = nil,
        appMax: Size? = nil,
        natural: Size? = nil,
        donor: NodeID? = nil
    ) {
        self.identity = identity
        self.appMin = appMin
        self.appMax = appMax
        self.natural = natural
        self.donor = donor
    }

    public init(
        id: NodeID,
        appMin: Size? = nil,
        appMax: Size? = nil,
        natural: Size? = nil,
        donor: NodeID? = nil
    ) {
        self.init(identity: WindowID.named(id), appMin: appMin, appMax: appMax, natural: natural, donor: donor)
    }

    public static func win(_ id: NodeID, min: Size? = nil, max: Size? = nil, natural: Size? = nil) -> LayoutNode {
        .window(WindowLeaf(id: id, appMin: min, appMax: max, natural: natural))
    }
}

/// Ordered tab group with an active member index.
public struct TabGroup: Equatable, Codable, Sendable {
    public var id: NodeID
    public var members: [WindowLeaf]
    public var active: Int

    public init(id: NodeID, members: [WindowLeaf], active: Int = 0) {
        self.id = id
        self.members = members
        self.active = members.isEmpty ? 0 : min(max(0, active), members.count - 1)
    }

    public var activeMember: WindowLeaf? {
        guard !members.isEmpty, members.indices.contains(active) else { return nil }
        return members[active]
    }
}

/// Floating window frame as edge fractions of the desktop area's tile.
public struct FloatWin: Equatable, Codable, Sendable {
    public var window: WindowLeaf
    /// `(x0, y0, x1, y1)` fractions of the desktop tile.
    public var frac: EdgeRect

    public init(window: WindowLeaf, frac: EdgeRect) {
        self.window = window
        self.frac = frac
    }

    public init(window: WindowLeaf, frac: (Double, Double, Double, Double)) {
        self.window = window
        self.frac = EdgeRect(frac)
    }
}

/// Free area of the arrangement. Exactly one per workspace (possibly hidden).
public struct DesktopArea: Equatable, Codable, Sendable {
    public var id: NodeID
    public var floats: [FloatWin]

    public init(id: NodeID = "desktop", floats: [FloatWin] = []) {
        self.id = id
        self.floats = floats
    }

    public static let empty = DesktopArea()
}

// MARK: - Tree queries

extension LayoutNode {
    public var depth: Int {
        switch self {
        case .desktop, .window, .tabs:
            return 1
        case .split(let split):
            return 1 + (split.children.map(\.depth).max() ?? 0)
        }
    }

    /// All tiled window identities (panels + tab members), DFS order.
    public var tiledWindowIDs: [WindowID] {
        switch self {
        case .desktop:
            return []
        case .window(let w):
            return [w.identity]
        case .tabs(let t):
            return t.members.map(\.identity)
        case .split(let split):
            return split.children.flatMap(\.tiledWindowIDs)
        }
    }

    public var tiledNodeIDs: [NodeID] {
        tiledWindowIDs.map(\.nodeID)
    }

    public var floatingWindowIDs: [WindowID] {
        switch self {
        case .desktop(let d):
            return d.floats.map(\.window.identity)
        case .window, .tabs:
            return []
        case .split(let split):
            return split.children.flatMap(\.floatingWindowIDs)
        }
    }

    public var desktopCount: Int {
        switch self {
        case .desktop: return 1
        case .window, .tabs: return 0
        case .split(let split):
            return split.children.reduce(0) { $0 + $1.desktopCount }
        }
    }

    public func contains(_ id: NodeID) -> Bool {
        tiledNodeIDs.contains(id)
            || floatingWindowIDs.map(\.nodeID).contains(id)
            || self.id == id
    }

    public func node(at path: NodePath) -> LayoutNode? {
        if path.isEmpty { return self }
        guard case .split(let split) = self else { return nil }
        let index = path[0]
        guard split.children.indices.contains(index) else { return nil }
        return split.children[index].node(at: Array(path.dropFirst()))
    }

    public func path(to id: NodeID) -> NodePath? {
        if self.id == id { return [] }
        switch self {
        case .desktop, .window:
            return nil
        case .tabs(let t):
            return t.members.contains(where: { $0.id == id }) ? [] : nil
        case .split(let split):
            for (index, child) in split.children.enumerated() {
                if let sub = child.path(to: id) {
                    return [index] + sub
                }
            }
            return nil
        }
    }

    public func path(to id: WindowID) -> NodePath? {
        path(to: id.nodeID)
    }

    public func contains(_ id: WindowID) -> Bool {
        contains(id.nodeID)
    }

    public func replacing(at path: NodePath, with replacement: LayoutNode) -> LayoutNode? {
        if path.isEmpty { return replacement }
        guard case .split(var split) = self else { return nil }
        let index = path[0]
        guard split.children.indices.contains(index) else { return nil }
        guard let newChild = split.children[index].replacing(at: Array(path.dropFirst()), with: replacement) else {
            return nil
        }
        split.children[index] = newChild
        return .split(split)
    }

    public func allPaths() -> [NodePath] {
        var result: [NodePath] = [[]]
        if case .split(let split) = self {
            for (index, child) in split.children.enumerated() {
                for sub in child.allPaths() {
                    result.append([index] + sub)
                }
            }
        }
        return result
    }

    /// Deep copy (structs are already value types; kept for API parity with Python `deepcopy`).
    public func copy() -> LayoutNode { self }
}

// MARK: - Legacy aliases (AppCore / older tests)

/// PLAN names retired by ADDENDUM-3 — kept as aliases so dependents compile.
public typealias Node = LayoutNode
public typealias SplitNode = Split
public typealias PanelNode = WindowLeaf
public typealias TabNode = TabGroup

extension WindowLeaf {
    public init(window: WindowID) {
        self.init(identity: window)
    }

    public var window: WindowID {
        get { identity }
        set { identity = newValue }
    }
}

extension TabGroup {
    public init(windows: [WindowID], selectedIndex: Int = 0) {
        self.init(
            id: "g-\(windows.first?.nodeID ?? "empty")",
            members: windows.map { WindowLeaf(identity: $0) },
            active: selectedIndex
        )
    }

    public var windows: [WindowID] {
        get { members.map(\.identity) }
        set { members = newValue.map { WindowLeaf(identity: $0) } }
    }

    public var selectedIndex: Int {
        get { active }
        set { active = newValue }
    }

    public var selectedWindow: WindowID? {
        activeMember?.identity
    }
}

extension LayoutNode {
    public static func panel(_ leaf: WindowLeaf) -> LayoutNode { .window(leaf) }
    /// Empty desktop area.
    public static var emptyDesktop: LayoutNode { .desktop(DesktopArea()) }
}
