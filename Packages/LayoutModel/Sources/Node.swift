import Foundation

/// Index path from the workspace root into the layout tree.
/// An empty path refers to the root node itself.
public typealias NodePath = [Int]

/// Nested layout tree node.
public indirect enum Node: Equatable, Codable, Sendable {
    case split(SplitNode)
    case panel(PanelNode)
    case tabs(TabNode)
    /// Free area of the arrangement. A fresh workspace is just `.desktop`.
    case desktop

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum NodeType: String, Codable {
        case split
        case panel
        case tabs
        case desktop
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(NodeType.self, forKey: .type)
        switch type {
        case .split:
            self = .split(try container.decode(SplitNode.self, forKey: .payload))
        case .panel:
            self = .panel(try container.decode(PanelNode.self, forKey: .payload))
        case .tabs:
            self = .tabs(try container.decode(TabNode.self, forKey: .payload))
        case .desktop:
            self = .desktop
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .split(let value):
            try container.encode(NodeType.split, forKey: .type)
            try container.encode(value, forKey: .payload)
        case .panel(let value):
            try container.encode(NodeType.panel, forKey: .type)
            try container.encode(value, forKey: .payload)
        case .tabs(let value):
            try container.encode(NodeType.tabs, forKey: .type)
            try container.encode(value, forKey: .payload)
        case .desktop:
            try container.encode(NodeType.desktop, forKey: .type)
        }
    }
}

/// Binary-or-more split along one axis with proportional ratios.
public struct SplitNode: Equatable, Codable, Sendable {
    /// Minimum allowed ratio for any child (inclusive).
    public static let minRatio: Double = 0.05

    public var axis: Axis
    public var children: [Node]
    /// Must match `children.count`, sum to 1, each ≥ `minRatio` after normalize.
    public var ratios: [Double]

    public init(axis: Axis, children: [Node], ratios: [Double]) {
        self.axis = axis
        self.children = children
        self.ratios = ratios
    }

    /// Whether ratios are structurally valid (count match, sum ≈ 1, each ≥ min).
    public var hasValidRatios: Bool {
        guard children.count == ratios.count, !children.isEmpty else { return false }
        guard ratios.allSatisfy({ $0 >= SplitNode.minRatio - 1e-9 }) else { return false }
        let sum = ratios.reduce(0, +)
        return abs(sum - 1) < 1e-6
    }

    /// Equal-ratio split for the given children.
    public static func equal(axis: Axis, children: [Node]) -> SplitNode {
        let n = max(children.count, 1)
        let r = 1.0 / Double(n)
        return SplitNode(axis: axis, children: children, ratios: Array(repeating: r, count: children.count))
    }
}

/// Leaf that holds a single tiled window.
public struct PanelNode: Equatable, Codable, Sendable {
    public var window: WindowID

    public init(window: WindowID) {
        self.window = window
    }
}

/// Ordered tab group with a selected index.
public struct TabNode: Equatable, Codable, Sendable {
    public var windows: [WindowID]
    public var selectedIndex: Int

    public init(windows: [WindowID], selectedIndex: Int = 0) {
        self.windows = windows
        self.selectedIndex = windows.isEmpty ? 0 : min(max(0, selectedIndex), windows.count - 1)
    }

    public var selectedWindow: WindowID? {
        guard !windows.isEmpty, windows.indices.contains(selectedIndex) else { return nil }
        return windows[selectedIndex]
    }
}

// MARK: - Tree queries

extension Node {
    /// Depth of the deepest descendant (leaf = 1, empty desktop = 1).
    public var depth: Int {
        switch self {
        case .desktop, .panel, .tabs:
            return 1
        case .split(let split):
            return 1 + (split.children.map(\.depth).max() ?? 0)
        }
    }

    /// All window IDs present in the tiled tree (panels + tabs), in DFS order.
    public var tiledWindowIDs: [WindowID] {
        switch self {
        case .desktop:
            return []
        case .panel(let panel):
            return [panel.window]
        case .tabs(let tabs):
            return tabs.windows
        case .split(let split):
            return split.children.flatMap(\.tiledWindowIDs)
        }
    }

    /// Number of `.desktop` nodes in this subtree.
    public var desktopCount: Int {
        switch self {
        case .desktop:
            return 1
        case .panel, .tabs:
            return 0
        case .split(let split):
            return split.children.reduce(0) { $0 + $1.desktopCount }
        }
    }

    public func contains(_ id: WindowID) -> Bool {
        tiledWindowIDs.contains(id)
    }

    /// Node at `path`, or `nil` if the path is invalid.
    public func node(at path: NodePath) -> Node? {
        if path.isEmpty { return self }
        switch self {
        case .split(let split):
            let index = path[0]
            guard split.children.indices.contains(index) else { return nil }
            return split.children[index].node(at: Array(path.dropFirst()))
        default:
            return nil
        }
    }

    /// Path to the first occurrence of `id`, or `nil`.
    public func path(to id: WindowID) -> NodePath? {
        switch self {
        case .desktop:
            return nil
        case .panel(let panel):
            return panel.window == id ? [] : nil
        case .tabs(let tabs):
            return tabs.windows.contains(id) ? [] : nil
        case .split(let split):
            for (index, child) in split.children.enumerated() {
                if let sub = child.path(to: id) {
                    return [index] + sub
                }
            }
            return nil
        }
    }

    /// Replace the node at `path` with `replacement`. Returns `nil` if path is invalid.
    public func replacing(at path: NodePath, with replacement: Node) -> Node? {
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

    /// Collect every valid node path in DFS order (root first).
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
}
