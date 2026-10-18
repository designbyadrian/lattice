import Foundation

/// AX-derived window kind (coarser than full subrole).
public enum WindowKind: String, Codable, Sendable, Equatable, CaseIterable {
    case normal
    case dialog
    case sheet
    case panel
}

/// Observable facts about a window used for rule matching.
public struct WindowFacts: Equatable, Sendable {
    public var bundleID: String?
    public var appName: String
    public var title: String
    public var kind: WindowKind
    public var resizable: Bool
    public var fullscreenButtonEnabled: Bool
    public var closeButtonEnabled: Bool

    public init(
        bundleID: String? = nil,
        appName: String = "",
        title: String = "",
        kind: WindowKind = .normal,
        resizable: Bool = true,
        fullscreenButtonEnabled: Bool = true,
        closeButtonEnabled: Bool = true
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.kind = kind
        self.resizable = resizable
        self.fullscreenButtonEnabled = fullscreenButtonEnabled
        self.closeButtonEnabled = closeButtonEnabled
    }
}

/// One `[[rules]]` entry. Matching semantics follow PLAN §7a.
public struct WindowRule: Equatable, Sendable {
    /// Bundle ID, exact, case-sensitive.
    public var appId: String?
    /// Case-insensitive regex matched anywhere in the app name.
    public var appName: String?
    /// Case-insensitive regex matched anywhere in the title.
    public var title: String?
    public var kind: WindowKind?
    /// Required command strings (`layout floating`, etc.).
    public var run: [String]

    public init(
        appId: String? = nil,
        appName: String? = nil,
        title: String? = nil,
        kind: WindowKind? = nil,
        run: [String]
    ) {
        self.appId = appId
        self.appName = appName
        self.title = title
        self.kind = kind
        self.run = run
    }
}

/// Parsed rule / binding command (subset needed for classification; full grammar in Config/P5).
public enum LayoutCommand: Equatable, Sendable, Codable {
    case layoutFloating
    case layoutTiling
    case ignore
    case moveWindowToWorkspace(Int)
    case dock(edge: Edge, screen: Bool)
    case minSize(width: Double, height: Double)
    case tabWithFocused
    case tabWithAppId(String)
    case other(String)

    /// Parse a single command string. Unknown verbs become `.other`.
    public static func parse(_ raw: String) -> LayoutCommand {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let verb = parts.first?.lowercased() else { return .other(trimmed) }

        switch verb {
        case "layout":
            let arg = parts.dropFirst().first?.lowercased()
            if arg == "floating" { return .layoutFloating }
            if arg == "tiling" { return .layoutTiling }
            return .other(trimmed)
        case "ignore":
            return .ignore
        case "move-window-to-workspace":
            if let n = parts.dropFirst().first, let value = Int(n) {
                return .moveWindowToWorkspace(value)
            }
            return .other(trimmed)
        case "dock":
            let edgeName = parts.dropFirst().first?.lowercased()
            let edge: Edge?
            switch edgeName {
            case "left": edge = .left
            case "right": edge = .right
            case "up", "top": edge = .top
            case "down", "bottom": edge = .bottom
            default: edge = nil
            }
            let screen = parts.contains("--screen")
            if let edge {
                return .dock(edge: edge, screen: screen)
            }
            return .other(trimmed)
        case "min-size":
            if parts.count >= 3,
               let w = Double(parts[1]),
               let h = Double(parts[2]) {
                return .minSize(width: w, height: h)
            }
            return .other(trimmed)
        case "tab-with":
            let target = parts.dropFirst().first?.lowercased()
            if target == "focused" { return .tabWithFocused }
            if let rawTarget = parts.dropFirst().first {
                return .tabWithAppId(rawTarget)
            }
            return .other(trimmed)
        default:
            return .other(trimmed)
        }
    }
}

/// Minimal config surface for pure rule classification (avoids depending on Config).
public struct RuleClassificationConfig: Equatable, Sendable {
    public var defaultTiling: Bool
    public var floatWindowsWithoutFullscreen: Bool
    /// Bundle IDs exempt from the fullscreen-button float heuristic (terminals/editors).
    public var fullscreenButtonExemptions: Set<String>

    public init(
        defaultTiling: Bool = true,
        floatWindowsWithoutFullscreen: Bool = true,
        fullscreenButtonExemptions: Set<String> = RuleClassificationConfig.defaultExemptions
    ) {
        self.defaultTiling = defaultTiling
        self.floatWindowsWithoutFullscreen = floatWindowsWithoutFullscreen
        self.fullscreenButtonExemptions = fullscreenButtonExemptions
    }

    public static let `default` = RuleClassificationConfig()

    /// Apps whose title bar can be hidden; keep tiling despite missing fullscreen button.
    public static let defaultExemptions: Set<String> = [
        // Terminals / editors often hide the title bar chrome.
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode",
    ]
}

/// Result of classifying a new window against rules.
public struct RuleClassification: Equatable, Sendable {
    public var floating: Bool
    /// `true` when a rule commanded `ignore` (never track).
    public var ignore: Bool
    /// Post-placement commands (everything except layout floating/tiling/ignore).
    public var commands: [LayoutCommand]

    public init(floating: Bool, ignore: Bool = false, commands: [LayoutCommand] = []) {
        self.floating = floating
        self.ignore = ignore
        self.commands = commands
    }
}
