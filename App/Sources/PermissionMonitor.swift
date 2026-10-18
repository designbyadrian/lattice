import AppKit
import PlatformMac

/// Re-checks Accessibility (and optional Screen Recording) on wake/launch; drives menu warning.
@MainActor
final class PermissionMonitor {
    private let permissions = MacPermissions()
    private var observers: [NSObjectProtocol] = []

    /// True when Accessibility was trusted but is now revoked.
    private(set) var accessibilityRevoked: Bool = false

    var onChange: (() -> Void)?

    func start() {
        recheck()
        let center = NSWorkspace.shared.notificationCenter
        let wake = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheck() }
        }
        let active = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheck() }
        }
        observers = [wake, active]
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for obs in observers {
            center.removeObserver(obs)
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()
    }

    func recheck() {
        let trusted = permissions.isAccessibilityTrusted
        let wasCompleted = OnboardingController.isCompleted
        let previouslyRevoked = accessibilityRevoked
        accessibilityRevoked = wasCompleted && !trusted
        if accessibilityRevoked != previouslyRevoked {
            onChange?()
        } else if !trusted && wasCompleted {
            onChange?()
        }
    }

    var menuWarningTitle: String? {
        guard accessibilityRevoked else { return nil }
        return "Accessibility permission revoked — open Settings"
    }
}
