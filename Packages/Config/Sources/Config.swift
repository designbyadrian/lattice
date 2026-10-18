import Foundation

/// Config package marker. Full TOML loader lands in P5.
public enum ConfigModule {
    public static let name = "Config"
}

public struct LatticeConfig: Sendable, Equatable {
    public var startAtLogin: Bool
    public var workspaces: Int
    public var defaultTiling: Bool
    public var followAppActivation: Bool
    public var floatWindowsWithoutFullscreen: Bool
    public var overviewPreviews: OverviewPreviewsMode

    public init(
        startAtLogin: Bool = true,
        workspaces: Int = 1,
        defaultTiling: Bool = true,
        followAppActivation: Bool = true,
        floatWindowsWithoutFullscreen: Bool = true,
        overviewPreviews: OverviewPreviewsMode = .auto
    ) {
        self.startAtLogin = startAtLogin
        self.workspaces = workspaces
        self.defaultTiling = defaultTiling
        self.followAppActivation = followAppActivation
        self.floatWindowsWithoutFullscreen = floatWindowsWithoutFullscreen
        self.overviewPreviews = overviewPreviews
    }

    public static let `default` = LatticeConfig()
}

public enum OverviewPreviewsMode: String, Sendable, Codable, Equatable {
    case auto
    case live
    case snapshots
    case off
}
