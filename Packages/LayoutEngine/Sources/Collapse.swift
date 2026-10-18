import Foundation
import LayoutModel

/// Legibility thresholds for overview / zoomed-out tiles (math only).
public struct CollapseThresholds: Equatable, Hashable, Codable, Sendable {
    public var windowMinWidth: Double
    public var windowMinHeight: Double
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
    case expanded
    case windowTile
    case groupTile
}

public enum Collapse {
    public static func presentation(
        for node: LayoutNode,
        frame: Rect,
        thresholds: CollapseThresholds = .default
    ) -> CollapsePresentation {
        switch node {
        case .desktop:
            return .expanded
        case .window, .tabs:
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

    public static func activatesStepIn(_ presentation: CollapsePresentation) -> Bool {
        presentation == .groupTile || presentation == .windowTile
    }
}
