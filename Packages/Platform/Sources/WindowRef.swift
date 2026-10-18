import Foundation

/// Platform-facing window snapshot (CGWindowID when known).
public struct WindowRef: Hashable, Sendable, Codable {
    public var id: UInt32
    public var pid: Int32
    public var bundleID: String?
    public var appName: String?
    public var title: String
    public var frame: CGRectCodable
    public var isMinimized: Bool
    public var isFullscreen: Bool
    public var subrole: String?

    public init(
        id: UInt32,
        pid: Int32,
        bundleID: String? = nil,
        appName: String? = nil,
        title: String,
        frame: CGRectCodable,
        isMinimized: Bool = false,
        isFullscreen: Bool = false,
        subrole: String? = nil
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.subrole = subrole
    }
}

/// Physical display keyed by `CGDisplayCreateUUIDFromDisplayID` string.
public struct DisplayRef: Hashable, Sendable, Codable {
    public var uuid: String
    public var name: String
    public var frame: CGRectCodable
    public var visibleFrame: CGRectCodable

    public init(
        uuid: String,
        name: String,
        frame: CGRectCodable,
        visibleFrame: CGRectCodable? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
    }
}
