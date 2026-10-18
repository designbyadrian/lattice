import Foundation
import LayoutModel

/// Direction used by focus / move / dock / tab-with / pan (vim + cardinal names).
public enum CommandDirection: String, Sendable, Equatable, CaseIterable {
    case left
    case down
    case up
    case right

    public var edge: Edge {
        switch self {
        case .left: return .left
        case .right: return .right
        case .up: return .top
        case .down: return .bottom
        }
    }

    public static func parse(_ raw: String) -> CommandDirection? {
        switch raw.lowercased() {
        case "left", "h": return .left
        case "down", "j": return .down
        case "up", "k": return .up
        case "right", "l": return .right
        default: return nil
        }
    }
}

public enum WorkspaceTarget: Sendable, Equatable {
    case number(Int)
    case prev
    case next
}

public enum DisplayTarget: Sendable, Equatable {
    case next
    case prev
}

public enum ResizeAxis: String, Sendable, Equatable {
    case smart
    case width
    case height
}

public enum EnableState: String, Sendable, Equatable {
    case on
    case off
    case toggle
}

public enum ZoomTarget: String, Sendable, Equatable {
    case `in`
    case out
    case all
    case window
    case desktop
}

public enum TabTarget: Sendable, Equatable {
    case next
    case prev
    case direction(CommandDirection)
    case focused
    case appId(String)
}

public enum HistoryDirection: String, Sendable, Equatable {
    case back
    case forward
}

public enum DesktopAreaAction: String, Sendable, Equatable {
    case show
    case hide
    case toggle
}

public enum SplitDirectionAction: String, Sendable, Equatable {
    case toggle
    case horizontal
    case vertical
}

/// One Lattice / Dinky command. Shared by bindings, rules, hooks, URL scheme, CLI.
public enum Command: Sendable, Equatable {
    case workspace(WorkspaceTarget)
    case workspaceBackAndForth
    case moveWindowToWorkspace(WorkspaceTarget, follow: Bool)
    case moveWindowToDisplay(DisplayTarget, follow: Bool)
    case focus(CommandDirection)
    case move(CommandDirection)
    case joinWith(CommandDirection)
    case resize(ResizeAxis, delta: Int)
    case balanceSizes
    case flattenWorkspaceTree
    case retile
    case clearMinimumSizes
    case mode(String)
    case reloadConfig
    case enable(EnableState)
    case list(String)
    case execAndForget(String)
    case layoutFloating
    case layoutTiling
    /// Toggle / cycle list preserved as ordered layout modes.
    case layoutCycle([String])
    case split(Axis)
    case dock(CommandDirection, screen: Bool)
    case dockAll
    case tabWith(TabTarget)
    case untab
    case tab(TabTarget)
    case zoom(ZoomTarget, toggle: Bool)
    case frameRect
    case history(HistoryDirection)
    case recallView(Int)
    case storeView(Int)
    case pan(CommandDirection)
    case desktopArea(DesktopAreaAction)
    case splitNew(appId: String)
    case splitDirection(SplitDirectionAction)
    case unmanageAll
    case ignore
    case minSize(width: Double, height: Double)
}
