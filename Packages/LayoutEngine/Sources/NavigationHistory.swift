import Foundation
import LayoutModel

/// Back/forward stack of camera states for one workspace.
public struct NavigationHistory: Equatable, Codable, Sendable {
    public private(set) var backStack: [Camera]
    public private(set) var forwardStack: [Camera]
    public private(set) var current: Camera

    public init(current: Camera = .showAll) {
        self.backStack = []
        self.forwardStack = []
        self.current = current
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    /// Record a new camera state (clears forward stack). No-op if identical to current.
    public mutating func navigate(to camera: Camera) {
        guard camera != current else { return }
        backStack.append(current)
        current = camera
        forwardStack.removeAll(keepingCapacity: true)
    }

    /// Replace current without pushing history (e.g. live pinch scrub).
    public mutating func replaceCurrent(with camera: Camera) {
        current = camera
    }

    @discardableResult
    public mutating func back() -> Camera? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return current
    }

    @discardableResult
    public mutating func forward() -> Camera? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return current
    }
}

/// Helpers for saved views 1…9 on a `DisplayLayout`.
public enum SavedViews {
    public static let validIndices = 1...9

    public static func save(_ index: Int, camera: Camera, into layout: inout DisplayLayout) {
        layout.saveView(index, camera: camera)
    }

    public static func load(_ index: Int, from layout: DisplayLayout) -> Camera? {
        layout.view(index)
    }

    /// Apply a saved view onto a navigation history (pushes history).
    public static func apply(
        _ index: Int,
        from layout: DisplayLayout,
        history: inout NavigationHistory
    ) -> Camera? {
        guard let camera = load(index, from: layout) else { return nil }
        history.navigate(to: camera)
        return camera
    }
}
