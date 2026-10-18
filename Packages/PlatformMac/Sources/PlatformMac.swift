import AppKit
import Foundation
import Platform

public enum PlatformMacModule {
    public static let name = "PlatformMac"
}

public final class MacPermissions: PermissionsChecking, @unchecked Sendable {
    public init() {}

    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    public var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }
}
