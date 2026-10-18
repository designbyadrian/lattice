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

/// Legacy overview preview mode (kept for PlatformMac overview capture helpers; not a config key).
public enum OverviewPreviewsMode: String, Sendable, Codable, Equatable {
    case auto
    case live
    case snapshots
    case off
}

/// Per-workspace tiling override from `[workspace.<n>]`.
public struct WorkspaceConfig: Sendable, Equatable {
    public var tiling: Bool?

    public init(tiling: Bool? = nil) {
        self.tiling = tiling
    }
}

/// Typed Lattice configuration (all keys optional in the file; missing → defaults).
public struct LatticeConfig: Sendable, Equatable {
    public var startAtLogin: Bool
    public var workspaces: Int
    public var defaultTiling: Bool
    public var followAppActivation: Bool
    public var floatWindowsWithoutFullscreen: Bool
    public var menuBarControls: [MenuBarControl]
    public var gaps: GapsConfig
    public var modifiers: ModifiersConfig
    public var mouse: MouseConfig
    public var modes: [String: ModeConfig]
    public var borders: BordersConfig
    public var focusFollowsMouse: FocusFollowsMouseConfig
    /// `[workspace-to-display]` patterns (unlisted → main).
    public var workspaceToDisplay: [Int: [DisplayPattern]]
    /// `[workspace.<n>]` tiling overrides (1-based keys).
    public var workspaceConfigs: [Int: WorkspaceConfig]
    /// `[display.<pattern>]` gap overrides.
    public var displayGaps: [DisplayPatternGaps]
    public var animations: AnimationsConfig
    public var drag: DragConfig
    public var hooks: HooksConfig
    public var layout: LayoutGeometryConfig
    public var zoom: ZoomConfig
    public var tabs: TabsConfig
    public var desktopArea: DesktopAreaConfig
    public var windowSizing: WindowSizingConfig
    /// Parsed `[[rules]]` in file order.
    public var rules: [WindowRule]
    /// Lattice extension: `[experimental]` private-API flags (off by default).
    public var experimental: ExperimentalConfig

    public init(
        startAtLogin: Bool = true,
        workspaces: Int = 1,
        defaultTiling: Bool = false,
        followAppActivation: Bool = true,
        floatWindowsWithoutFullscreen: Bool = true,
        menuBarControls: [MenuBarControl] = [.back, .forward, .views, .desktop, .everything],
        gaps: GapsConfig = .default,
        modifiers: ModifiersConfig = .default,
        mouse: MouseConfig = .default,
        modes: [String: ModeConfig]? = nil,
        borders: BordersConfig = .default,
        focusFollowsMouse: FocusFollowsMouseConfig = .default,
        workspaceToDisplay: [Int: [DisplayPattern]] = [:],
        workspaceConfigs: [Int: WorkspaceConfig] = [:],
        displayGaps: [DisplayPatternGaps] = [],
        animations: AnimationsConfig = .default,
        drag: DragConfig = .default,
        hooks: HooksConfig = .default,
        layout: LayoutGeometryConfig = .default,
        zoom: ZoomConfig = .default,
        tabs: TabsConfig = .default,
        desktopArea: DesktopAreaConfig = .default,
        windowSizing: WindowSizingConfig = .default,
        rules: [WindowRule] = [],
        experimental: ExperimentalConfig = .default
    ) {
        self.startAtLogin = startAtLogin
        self.workspaces = workspaces
        self.defaultTiling = defaultTiling
        self.followAppActivation = followAppActivation
        self.floatWindowsWithoutFullscreen = floatWindowsWithoutFullscreen
        self.menuBarControls = menuBarControls
        self.gaps = gaps
        self.modifiers = modifiers
        self.mouse = mouse
        self.modes = modes ?? [DefaultBindings.modeName: DefaultBindings.mainMode()]
        self.borders = borders
        self.focusFollowsMouse = focusFollowsMouse
        self.workspaceToDisplay = workspaceToDisplay
        self.workspaceConfigs = workspaceConfigs
        self.displayGaps = displayGaps
        self.animations = animations
        self.drag = drag
        self.hooks = hooks
        self.layout = layout
        self.zoom = zoom
        self.tabs = tabs
        self.desktopArea = desktopArea
        self.windowSizing = windowSizing
        self.rules = rules
        self.experimental = experimental
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

    /// Config surface for `RuleEngine.classify`.
    public var ruleClassificationConfig: RuleClassificationConfig {
        RuleClassificationConfig(
            defaultTiling: defaultTiling,
            floatWindowsWithoutFullscreen: floatWindowsWithoutFullscreen
        )
    }
}
