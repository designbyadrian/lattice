import Foundation

/// Where a window can be inserted into the layout tree.
public enum DropTarget: Equatable, Codable, Sendable {
    /// Dock beside the node at `nodePath` on the given edge.
    case edge(nodePath: NodePath, edge: Edge)
    /// Hold over center to form / join a tab group at `nodePath`.
    case center(nodePath: NodePath)
    /// Dock beside everything currently in view (preserves `.desktop`).
    case screenEdge(Edge)
}
