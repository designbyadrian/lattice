import Foundation

/// Double-click action from `[mouse]` (command string or `none`).
public enum MouseDoubleClickAction: Sendable, Equatable {
    case none
    case commands([Command])

    public static func parse(_ raw: String) throws -> MouseDoubleClickAction {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "none" { return .none }
        return .commands([try CommandParser.parse(trimmed)])
    }
}

/// `[mouse]` Lattice extension (ADDENDUM A1 / ADDENDUM-2 B11).
public struct MouseConfig: Sendable, Equatable {
    public var doubleClickDesktop: MouseDoubleClickAction
    public var doubleClickTitle: MouseDoubleClickAction

    public init(
        doubleClickDesktop: MouseDoubleClickAction = .commands([.zoom(.desktop, toggle: true)]),
        doubleClickTitle: MouseDoubleClickAction = .commands([.zoom(.window, toggle: true)])
    ) {
        self.doubleClickDesktop = doubleClickDesktop
        self.doubleClickTitle = doubleClickTitle
    }

    public static let `default` = MouseConfig()
}

/// Menu-bar status control identifiers (`menu-bar-controls`).
public enum MenuBarControl: String, Sendable, Equatable, CaseIterable {
    case back
    case forward
    case views
    case desktop
    case everything
}
