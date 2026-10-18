import AppKit
import Sparkle

/// Sparkle 2 updater wrapper. Auto-checks can be disabled via UserDefaults.
@MainActor
final class UpdaterController: NSObject, SPUUpdaterDelegate {
    /// UserDefaults key: when false, automatic update checks are off.
    static let automaticChecksKey = "lattice.updates.automaticChecks"

    private var updaterController: SPUStandardUpdaterController?
    var onPreferenceChanged: (() -> Void)?

    /// Whether the user allows automatic update checks (default true).
    static var automaticChecksEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: automaticChecksKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: automaticChecksKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: automaticChecksKey)
        }
    }

    func start() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        applyAutomaticChecksPreference()
    }

    func applyAutomaticChecksPreference() {
        updaterController?.updater.automaticallyChecksForUpdates = Self.automaticChecksEnabled
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    /// Menu item for toggling automatic checks.
    func toggleAutomaticChecksMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: Self.automaticChecksEnabled ? "Disable Automatic Updates" : "Enable Automatic Updates",
            action: #selector(toggleAutomaticChecks(_:)),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    @objc private func toggleAutomaticChecks(_ sender: Any?) {
        Self.automaticChecksEnabled.toggle()
        applyAutomaticChecksPreference()
        onPreferenceChanged?()
    }
}
