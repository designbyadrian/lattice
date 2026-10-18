import Foundation

public typealias BundleID = String

/// Legacy floating-window record (absolute frame). Prefer `FloatWin` fractions on `DesktopArea`.
public struct FloatingWindow: Equatable, Codable, Sendable {
    public var id: WindowID
    public var frame: Rect

    public init(id: WindowID, frame: Rect) {
        self.id = id
        self.frame = frame
    }

    public init(id: NodeID, frame: Rect) {
        self.id = WindowID.named(id)
        self.frame = frame
    }
}

/// Camera is a world rect `(cx0, cy0, cx1, cy1)` in the unit square (ADDENDUM-3 §1.3).
public struct Camera: Equatable, Codable, Sendable {
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double

    /// Legacy AppCore fields (ignored by the ADDENDUM-3 camera model).
    public var focusPath: NodePath
    public var zoom: Double

    public init(
        x0: Double = 0,
        y0: Double = 0,
        x1: Double = 1,
        y1: Double = 1,
        focusPath: NodePath = [],
        zoom: Double = 0
    ) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
        self.focusPath = focusPath
        self.zoom = min(max(zoom, 0), 1)
    }

    public init(_ edges: EdgeRect) {
        self.init(x0: edges.x0, y0: edges.y0, x1: edges.x1, y1: edges.y1)
    }

    public init(_ tuple: (Double, Double, Double, Double)) {
        self.init(x0: tuple.0, y0: tuple.1, x1: tuple.2, y1: tuple.3)
    }

    public static let home = Camera()
    public static let showAll = Camera()

    public var edges: EdgeRect { EdgeRect(x0: x0, y0: y0, x1: x1, y1: y1) }
    public var asTuple: (Double, Double, Double, Double) { (x0, y0, x1, y1) }
}

/// One numbered workspace: tree (floats live in DesktopArea) + camera.
public struct Workspace: Equatable, Codable, Sendable {
    public var root: LayoutNode
    public var excludedApps: Set<BundleID>
    public var camera: Camera
    /// Per-window suspension state keyed by layout node id.
    public var windowStates: [NodeID: WindowState]
    /// When the desktop area is hidden, remembered placement for show.
    public var desktopMemory: DesktopMemory?
    public var layoutConfig: LayoutConfig

    public init(
        root: LayoutNode = .desktop(DesktopArea()),
        excludedApps: Set<BundleID> = [],
        camera: Camera = .home,
        windowStates: [NodeID: WindowState] = [:],
        desktopMemory: DesktopMemory? = nil,
        layoutConfig: LayoutConfig = .default
    ) {
        self.root = root
        self.excludedApps = excludedApps
        self.camera = camera
        self.windowStates = windowStates
        self.desktopMemory = desktopMemory
        self.layoutConfig = layoutConfig
    }

    public static let empty = Workspace()

    public var desktopHidden: Bool { desktopMemory != nil }

    public func state(of id: NodeID) -> WindowState {
        windowStates[id] ?? .active
    }

    public mutating func setState(_ state: WindowState, for id: NodeID) {
        if state == .active {
            windowStates.removeValue(forKey: id)
        } else {
            windowStates[id] = state
        }
    }

    /// Floats stored on the desktop area node.
    public var floatWins: [FloatWin] {
        get {
            guard let loc = TreeOps.find(root, target: "desktop"),
                  case .desktop(let d) = loc.node else { return [] }
            return d.floats
        }
        set {
            guard let loc = TreeOps.find(root, target: "desktop"),
                  case .desktop(var d) = loc.node else { return }
            d.floats = newValue
            root = TreeOps.replace(root, oldID: d.id, with: .desktop(d))
        }
    }

    /// Legacy absolute-frame float list (derived; assign replaces desktop floats with unit fracs).
    public var floating: [FloatingWindow] {
        get {
            floatWins.map {
                FloatingWindow(
                    id: $0.window.identity,
                    frame: Rect(
                        x: $0.frac.x0 * 1000,
                        y: $0.frac.y0 * 1000,
                        width: ($0.frac.x1 - $0.frac.x0) * 1000,
                        height: ($0.frac.y1 - $0.frac.y0) * 1000
                    )
                )
            }
        }
        set {
            floatWins = newValue.map { fw in
                FloatWin(
                    window: WindowLeaf(identity: fw.id),
                    frac: (
                        fw.frame.x / 1000,
                        fw.frame.y / 1000,
                        (fw.frame.x + fw.frame.width) / 1000,
                        (fw.frame.y + fw.frame.height) / 1000
                    )
                )
            }
        }
    }

    public var allWindowIDs: [WindowID] {
        root.tiledWindowIDs + root.floatingWindowIDs
    }

    public func contains(_ id: NodeID) -> Bool {
        root.contains(id)
    }

    public func isFloating(_ id: NodeID) -> Bool {
        root.floatingWindowIDs.map(\.nodeID).contains(id)
    }
}
