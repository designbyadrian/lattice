import Foundation
import LayoutModel

/// Legibility thresholds for overview / zoomed-out tiles (math only).
public struct CollapseThresholds: Equatable, Hashable, Codable, Sendable {
    /// Below this size a single window becomes an app-colour + icon tile.
    public var windowMinWidth: Double
    public var windowMinHeight: Double
    /// Below this size a group becomes one tile (split lines drawn inside).
    public var groupMinWidth: Double
    public var groupMinHeight: Double

    public init(
        windowMinWidth: Double = 120,
        windowMinHeight: Double = 80,
        groupMinWidth: Double = 160,
        groupMinHeight: Double = 100
    ) {
        self.windowMinWidth = windowMinWidth
        self.windowMinHeight = windowMinHeight
        self.groupMinWidth = groupMinWidth
        self.groupMinHeight = groupMinHeight
    }

    public static let `default` = CollapseThresholds()
}

/// How a node should render in the overview at the given frame size.
public enum CollapsePresentation: Equatable, Sendable {
    /// Full content / live preview eligible.
    case expanded
    /// Single-window tile (app colour + icon).
    case windowTile
    /// Group collapsed to one tile with split-line decoration.
    case groupTile
}

public enum Collapse {
    /// Classify a node given its on-screen frame (after camera transform).
    public static func presentation(
        for node: Node,
        frame: Rect,
        thresholds: CollapseThresholds = .default
    ) -> CollapsePresentation {
        switch node {
        case .desktop:
            return .expanded
        case .panel:
            if frame.width < thresholds.windowMinWidth || frame.height < thresholds.windowMinHeight {
                return .windowTile
            }
            return .expanded
        case .tabs:
            if frame.width < thresholds.windowMinWidth || frame.height < thresholds.windowMinHeight {
                return .windowTile
            }
            return .expanded
        case .split:
            if frame.width < thresholds.groupMinWidth || frame.height < thresholds.groupMinHeight {
                return .groupTile
            }
            return .expanded
        }
    }

    /// True when activating the tile should `stepIn` rather than focus a window.
    public static func activatesStepIn(_ presentation: CollapsePresentation) -> Bool {
        presentation == .groupTile || presentation == .windowTile
    }
}
