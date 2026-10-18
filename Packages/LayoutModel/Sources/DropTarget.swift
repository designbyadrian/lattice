import Foundation

/// Where a window can be inserted into the layout tree.
public enum DropTarget: Equatable, Codable, Sendable {
    /// Dock beside the node with `nodeID` on the given edge.
    case edge(nodeID: NodeID, edge: Edge)
    /// Hold over center to form / join a tab group.
    case center(nodeID: NodeID)
    /// Dock beside the visible root (screen-edge band).
    case screenEdge(Edge)
    /// Path-based edge (resolved against the current tree).
    case edgePath(nodePath: NodePath, edge: Edge)
    case centerPath(nodePath: NodePath)

    /// Convenience matching older `nodePath:` call sites.
    public static func edge(nodePath: NodePath, edge: Edge) -> DropTarget {
        .edgePath(nodePath: nodePath, edge: edge)
    }

    public static func center(nodePath: NodePath) -> DropTarget {
        .centerPath(nodePath: nodePath)
    }
}
