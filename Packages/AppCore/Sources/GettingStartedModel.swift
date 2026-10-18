import Foundation

/// Getting-started card steps (ADDENDUM-2 B18). Advances only on real model events.
public enum GettingStartedStep: Int, Sendable, Equatable, CaseIterable {
    case dockWindow = 0
    case resizeSeam
    case zoomOut
    case zoomIn
    case doubleClickFocus
    case makeTabGroup

    public var title: String {
        switch self {
        case .dockWindow: return "Dock a window"
        case .resizeSeam: return "Resize at a seam"
        case .zoomOut: return "Zoom out"
        case .zoomIn: return "Zoom in"
        case .doubleClickFocus: return "Double-click to focus"
        case .makeTabGroup: return "Make a tab group"
        }
    }

    public var body: String {
        switch self {
        case .dockWindow:
            return "Drag a floating window to a screen or tile edge to dock it."
        case .resizeSeam:
            return "Drag the seam between two docked windows to resize them."
        case .zoomOut:
            return "Pinch out or use Zoom out to see more of the arrangement."
        case .zoomIn:
            return "Pinch in or use Zoom in to frame a window."
        case .doubleClickFocus:
            return "Double-click a docked window’s title bar to frame it."
        case .makeTabGroup:
            return "Hold a window over another’s centre to make a tab group."
        }
    }

    public var next: GettingStartedStep? {
        GettingStartedStep(rawValue: rawValue + 1)
    }
}

/// Events that can advance the getting-started card.
public enum GettingStartedEvent: Sendable, Equatable {
    case docked
    case seamResized
    case zoomedOut
    case zoomedIn
    case doubleClickedFocus
    case tabGroupFormed
}

/// Pure progress tracker (UserDefaults persistence lives in the App shell).
public struct GettingStartedModel: Sendable, Equatable {
    public var current: GettingStartedStep?
    public var skipped: Bool
    public var completed: Bool

    public init(
        current: GettingStartedStep? = .dockWindow,
        skipped: Bool = false,
        completed: Bool = false
    ) {
        self.current = current
        self.skipped = skipped
        self.completed = completed
    }

    public static let fresh = GettingStartedModel()

    public var isVisible: Bool {
        !skipped && !completed && current != nil
    }

    public mutating func skip() {
        skipped = true
        current = nil
    }

    public mutating func restart() {
        skipped = false
        completed = false
        current = .dockWindow
    }

    /// Advance only when the event matches the current step.
    @discardableResult
    public mutating func handle(_ event: GettingStartedEvent) -> Bool {
        guard isVisible, let step = current else { return false }
        let matches: Bool
        switch (step, event) {
        case (.dockWindow, .docked),
             (.resizeSeam, .seamResized),
             (.zoomOut, .zoomedOut),
             (.zoomIn, .zoomedIn),
             (.doubleClickFocus, .doubleClickedFocus),
             (.makeTabGroup, .tabGroupFormed):
            matches = true
        default:
            matches = false
        }
        guard matches else { return false }
        if let next = step.next {
            current = next
        } else {
            current = nil
            completed = true
        }
        return true
    }
}

/// UserDefaults keys for getting-started UI state (PLAN §7 app/UI state).
public enum GettingStartedDefaults {
    public static let skippedKey = "lattice.getting-started.skipped"
    public static let completedKey = "lattice.getting-started.completed"
    public static let stepKey = "lattice.getting-started.step"

    public static func load(from defaults: UserDefaults = .standard) -> GettingStartedModel {
        if defaults.bool(forKey: skippedKey) {
            return GettingStartedModel(current: nil, skipped: true, completed: false)
        }
        if defaults.bool(forKey: completedKey) {
            return GettingStartedModel(current: nil, skipped: false, completed: true)
        }
        let raw = defaults.object(forKey: stepKey) as? Int ?? 0
        let step = GettingStartedStep(rawValue: raw) ?? .dockWindow
        return GettingStartedModel(current: step, skipped: false, completed: false)
    }

    public static func save(_ model: GettingStartedModel, to defaults: UserDefaults = .standard) {
        defaults.set(model.skipped, forKey: skippedKey)
        defaults.set(model.completed, forKey: completedKey)
        if let step = model.current {
            defaults.set(step.rawValue, forKey: stepKey)
        } else {
            defaults.removeObject(forKey: stepKey)
        }
    }
}
