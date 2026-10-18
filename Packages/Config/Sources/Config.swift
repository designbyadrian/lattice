import Foundation
import LayoutModel

/// Config package: Dinky-compatible TOML schema, Lattice-owned parser.
public enum ConfigModule {
    public static let name = "Config"

    /// Bundled JSON Schema for `lattice.toml` (`#:schema` / editor tooling).
    public static var schemaURL: URL? {
        Bundle.module.url(
            forResource: "lattice.schema",
            withExtension: "json",
            subdirectory: "Resources"
        )
            ?? Bundle.module.url(forResource: "lattice.schema", withExtension: "json")
            ?? Bundle.module.url(forResource: "lattice", withExtension: "schema.json")
    }
}

public enum OverviewPreviewsMode: String, Sendable, Codable, Equatable {
    case auto
    case live
    case snapshots
    case off
}

/// Typed Lattice configuration (all keys optional in the file; missing → defaults).
public struct LatticeConfig: Sendable, Equatable {
    public var startAtLogin: Bool
    public var workspaces: Int
    public var defaultTiling: Bool
    public var followAppActivation: Bool
    public var floatWindowsWithoutFullscreen: Bool
    public var overviewPreviews: OverviewPreviewsMode
    public var gaps: GapsConfig
    public var modifiers: ModifiersConfig
    public var modes: [String: ModeConfig]
    public var borders: BordersConfig
    public var focusFollowsMouse: FocusFollowsMouseConfig
    /// `[workspace-to-display]` patterns (unlisted → main).
    public var workspaceToDisplay: [Int: [DisplayPattern]]

    public init(
        startAtLogin: Bool = true,
        workspaces: Int = 1,
        defaultTiling: Bool = true,
        followAppActivation: Bool = true,
        floatWindowsWithoutFullscreen: Bool = true,
        overviewPreviews: OverviewPreviewsMode = .auto,
        gaps: GapsConfig = .default,
        modifiers: ModifiersConfig = .default,
        modes: [String: ModeConfig]? = nil,
        borders: BordersConfig = .default,
        focusFollowsMouse: FocusFollowsMouseConfig = .default,
        workspaceToDisplay: [Int: [DisplayPattern]] = [:]
    ) {
        self.startAtLogin = startAtLogin
        self.workspaces = workspaces
        self.defaultTiling = defaultTiling
        self.followAppActivation = followAppActivation
        self.floatWindowsWithoutFullscreen = floatWindowsWithoutFullscreen
        self.overviewPreviews = overviewPreviews
        self.gaps = gaps
        self.modifiers = modifiers
        self.modes = modes ?? [DefaultBindings.modeName: DefaultBindings.mainMode()]
        self.borders = borders
        self.focusFollowsMouse = focusFollowsMouse
        self.workspaceToDisplay = workspaceToDisplay
    }

    public static let `default` = LatticeConfig()

    /// Bindings for the named mode (defaults to `main`).
    public func mode(named name: String = DefaultBindings.modeName) -> ModeConfig? {
        modes[name]
    }

    /// Plan consumed by the P6 reconcile planner.
    public var workspacePlan: WorkspacePlan {
        WorkspacePlan(count: workspaces, workspaceToDisplay: workspaceToDisplay)
    }
}
