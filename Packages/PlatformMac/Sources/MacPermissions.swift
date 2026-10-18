import ApplicationServices
import Foundation
import Platform

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Accessibility + Screen Recording preflight (public APIs only).
public final class MacPermissions: PermissionsChecking, @unchecked Sendable {
    public init() {}

    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    public var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func requestAccessibilityTrust(prompt: Bool) -> Bool {
        if prompt {
            // Public key string for AXIsProcessTrustedWithOptions (avoids CFString global concurrency warning).
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrusted()
    }

    public func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
