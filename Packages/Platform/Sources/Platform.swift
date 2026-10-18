import Foundation

/// Protocol-only platform boundary. Implementations live in PlatformMac.
public protocol WindowServerProtocol: AnyObject, Sendable {
    func listWindows() async -> [WindowRef]
    func listDisplays() async -> [DisplayRef]
}

public struct WindowRef: Hashable, Sendable, Codable {
    public var id: UInt32
    public var pid: Int32
    public var bundleID: String?
    public var title: String
    public var frame: CGRectCodable

    public init(
        id: UInt32,
        pid: Int32,
        bundleID: String? = nil,
        title: String,
        frame: CGRectCodable
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
    }
}

public struct DisplayRef: Hashable, Sendable, Codable {
    public var uuid: String
    public var name: String
    public var frame: CGRectCodable

    public init(uuid: String, name: String, frame: CGRectCodable) {
        self.uuid = uuid
        self.name = name
        self.frame = frame
    }
}

/// Codable CGRect without importing CoreGraphics into pure model code via AppKit.
public struct CGRectCodable: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public protocol InputEvents: AnyObject, Sendable {}

public protocol PermissionsChecking: Sendable {
    var isAccessibilityTrusted: Bool { get }
    var hasScreenRecordingAccess: Bool { get }
}
