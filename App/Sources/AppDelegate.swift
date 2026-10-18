import AppKit
import AppCore
import Config
import Platform
import PlatformMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var coordinator: AppCoordinator?
    private var windowServer: MacWindowServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.split.3x1",
                accessibilityDescription: "Lattice"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Lattice",
            action: nil,
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Float All",
            action: #selector(floatAll),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Lattice",
            action: #selector(quitLattice),
            keyEquivalent: "q"
        ))
        item.menu = menu
        statusItem = item

        let server = MacWindowServer()
        windowServer = server
        let coordinator = AppCoordinator(platform: server, config: .default)
        self.coordinator = coordinator

        Task {
            await coordinator.start()
        }
    }

    @objc private func floatAll() {
        Task {
            await coordinator?.floatAll()
        }
    }

    @objc private func quitLattice() {
        Task { @MainActor in
            await coordinator?.prepareSafeQuit()
            coordinator?.stop()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
