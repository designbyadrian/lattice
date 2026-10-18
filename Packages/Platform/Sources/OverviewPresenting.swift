import Foundation

/// Descriptor for one overview tile (AppCore → platform UI).
public struct OverviewTileDescriptor: Sendable, Equatable {
    public var path: [Int]
    public var frame: CGRectCodable
    /// `expanded` | `windowTile` | `groupTile`
    public var presentation: String
    public var bundleID: String?
    public var title: String
    public var windowID: UInt32?

    public init(
        path: [Int],
        frame: CGRectCodable,
        presentation: String,
        bundleID: String? = nil,
        title: String = "",
        windowID: UInt32? = nil
    ) {
        self.path = path
        self.frame = frame
        self.presentation = presentation
        self.bundleID = bundleID
        self.title = title
        self.windowID = windowID
    }
}

/// Non-activating overview panel surface (PlatformMac implements; Fake no-ops).
public protocol OverviewPresenting: AnyObject, Sendable {
    var isOverviewVisible: Bool { get }

    func presentOverview(
        displayFrame: CGRectCodable,
        tiles: [OverviewTileDescriptor],
        onActivatePath: @escaping @Sendable ([Int]) -> Void
    )

    func updateOverviewTiles(_ tiles: [OverviewTileDescriptor])
    func dismissOverview()
}

/// No-op overview for unit tests.
public final class FakeOverviewPresenter: OverviewPresenting, @unchecked Sendable {
    public private(set) var isOverviewVisible = false
    public private(set) var lastTiles: [OverviewTileDescriptor] = []
    public var onActivatePath: (@Sendable ([Int]) -> Void)?

    public init() {}

    public func presentOverview(
        displayFrame: CGRectCodable,
        tiles: [OverviewTileDescriptor],
        onActivatePath: @escaping @Sendable ([Int]) -> Void
    ) {
        _ = displayFrame
        lastTiles = tiles
        self.onActivatePath = onActivatePath
        isOverviewVisible = true
    }

    public func updateOverviewTiles(_ tiles: [OverviewTileDescriptor]) {
        lastTiles = tiles
    }

    public func dismissOverview() {
        isOverviewVisible = false
    }

    public func simulateActivate(path: [Int]) {
        onActivatePath?(path)
    }
}
