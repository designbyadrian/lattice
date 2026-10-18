import Foundation

public typealias BundleID = String

/// Floating window with an absolute frame over the desktop area.
public struct FloatingWindow: Equatable, Codable, Sendable {
    public var id: WindowID
    public var frame: Rect

    public init(id: WindowID, frame: Rect) {
        self.id = id
        self.frame = frame
    }
}

/// Zoom / focus camera into the layout tree.
public struct Camera: Equatable, Codable, Sendable {
    public var focusPath: NodePath
    /// 0 = show all, 1 = focused node fills the display.
    public var zoom: Double

    public init(focusPath: NodePath = [], zoom: Double = 0) {
        self.focusPath = focusPath
        self.zoom = min(max(zoom, 0), 1)
    }

    public static let showAll = Camera(focusPath: [], zoom: 0)
}

/// One numbered workspace: tree + floating windows + camera.
public struct Workspace: Equatable, Codable, Sendable {
    public var root: Node
    public var floating: [FloatingWindow]
    public var excludedApps: Set<BundleID>
    public var camera: Camera
    /// Per-window suspension state. Missing entries default to `.active`.
    public var windowStates: [WindowID: WindowState]
    /// When true the desktop area is not drawn / not droppable (slot kept).
    public var desktopHidden: Bool

    public init(
        root: Node = .desktop,
        floating: [FloatingWindow] = [],
        excludedApps: Set<BundleID> = [],
        camera: Camera = .showAll,
        windowStates: [WindowID: WindowState] = [:],
        desktopHidden: Bool = false
    ) {
        self.root = root
        self.floating = floating
        self.excludedApps = excludedApps
        self.camera = camera
        self.windowStates = windowStates
        self.desktopHidden = desktopHidden
    }

    public static let empty = Workspace()

    public func state(of id: WindowID) -> WindowState {
        windowStates[id] ?? .active
    }

    public mutating func setState(_ state: WindowState, for id: WindowID) {
        if state == .active {
            windowStates.removeValue(forKey: id)
        } else {
            windowStates[id] = state
        }
    }

    /// All window IDs in the tiled tree plus floating list.
    public var allWindowIDs: [WindowID] {
        root.tiledWindowIDs + floating.map(\.id)
    }

    public func contains(_ id: WindowID) -> Bool {
        root.contains(id) || floating.contains(where: { $0.id == id })
    }

    public func isFloating(_ id: WindowID) -> Bool {
        floating.contains(where: { $0.id == id })
    }
}
