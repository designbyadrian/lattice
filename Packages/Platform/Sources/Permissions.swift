import Foundation

/// Accessibility and optional Screen Recording preflight.
public protocol PermissionsChecking: Sendable {
    var isAccessibilityTrusted: Bool { get }
    var hasScreenRecordingAccess: Bool { get }

    /// Prompt the user for Accessibility if not already trusted.
    func requestAccessibilityTrust(prompt: Bool) -> Bool

    /// Request Screen Recording access (may require relaunch after grant).
    func requestScreenRecordingAccess() -> Bool
}
