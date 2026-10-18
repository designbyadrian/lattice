import Foundation

/// `[hooks]` — command lists fired on lifecycle events. May include `exec-and-forget`.
public struct HooksConfig: Sendable, Equatable {
    public var startup: [Command]
    public var workspaceChanging: [Command]
    public var workspaceChanged: [Command]
    public var focusChanged: [Command]
    public var modeChanged: [Command]

    public init(
        startup: [Command] = [],
        workspaceChanging: [Command] = [],
        workspaceChanged: [Command] = [],
        focusChanged: [Command] = [],
        modeChanged: [Command] = []
    ) {
        self.startup = startup
        self.workspaceChanging = workspaceChanging
        self.workspaceChanged = workspaceChanged
        self.focusChanged = focusChanged
        self.modeChanged = modeChanged
    }

    public static let `default` = HooksConfig()
}
