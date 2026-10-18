import AppKit
import AppCore
import Config
import LayoutModel
import Platform
import PlatformMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var coordinator: AppCoordinator?
    private var windowServer: MacWindowServer?
    private var configLoader: ConfigLoader?
    private var settingsController: SettingsWindowController?
    private var socketServer: CommandSocketServer?
    private var bordersOverlay: BordersOverlayController?
    private var tabStrip: TabStripOverlay?
    private var onboarding: OnboardingController?
    private var permissionMonitor: PermissionMonitor?
    private var inputSafetyNet: InputSafetyNetState = .full

    func applicationDidFinishLaunching(_ notification: Notification) {
        let loader = ConfigLoader()
        configLoader = loader
        let config: LatticeConfig
        do {
            config = try loader.loadOrCreateDefaults()
        } catch {
            config = .default
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.split.3x1",
                accessibilityDescription: "Lattice"
            )
            button.image?.isTemplate = true
        }
        statusItem = item

        let server = MacWindowServer()
        windowServer = server
        server.applyExperimentalConfig(config.experimental)

        // Derive input safety net from P5a matrix outcome (pending → full until FAIL signed).
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        inputSafetyNet = InputSafetyNetState.from(
            tapCreated: true,
            inputMonitoringPrompted: false,
            osMajor: osMajor
        )

        let coordinator = AppCoordinator(platform: server, config: config)
        self.coordinator = coordinator
        coordinator.focusWindowHandler = { id in
            guard let cgID = id.cgWindowID else { return }
            await MacWindowWriter.shared.raise(windowID: cgID, pid: id.processID)
        }

        let borders = BordersOverlayController()
        borders.config = config.borders
        borders.increaseContrast = VisualAccessibility.increaseContrast
        bordersOverlay = borders

        let tabs = TabStripOverlay()
        tabs.onSelect = { [weak self] _, index in
            Task {
                if index >= 0 {
                    await self?.coordinator?.execute(.tab(.next))
                }
            }
        }
        tabStrip = tabs

        coordinator.onFramesApplied = { [weak self] frames, _ in
            Task { @MainActor in
                guard let self else { return }
                self.bordersOverlay?.config = self.coordinator?.config.borders ?? .default
                self.bordersOverlay?.increaseContrast = VisualAccessibility.increaseContrast
                let focused = self.coordinator?.focusedWindowID
                var bundles: [WindowID: String?] = [:]
                for id in frames.keys {
                    bundles[id] = id.bundleID
                }
                self.bordersOverlay?.update(frames: frames, focused: focused, bundleIDs: bundles)
            }
        }
        coordinator.onTabGroupsChanged = { [weak self] groups in
            Task { @MainActor in
                self?.tabStrip?.update(groups: groups)
            }
        }

        loader.startWatching { [weak self] result in
            Task { @MainActor in
                if case .success(let cfg) = result {
                    self?.coordinator?.reloadConfig(cfg)
                    self?.bordersOverlay?.config = cfg.borders
                    if let server = self?.windowServer {
                        server.applyExperimentalConfig(cfg.experimental)
                    }
                }
                self?.rebuildMenu()
            }
        }

        startSocketServer(coordinator: coordinator, loader: loader)

        assert(
            OnboardingStub.recordingIndicatorDisclosure.contains("recording indicator"),
            "Onboarding must disclose the Screen Recording indicator"
        )

        let monitor = PermissionMonitor()
        monitor.onChange = { [weak self] in self?.rebuildMenu() }
        monitor.start()
        permissionMonitor = monitor

        rebuildMenu()

        if coordinator.systemPrefsBackup.needsCrashRecoveryOffer() {
            offerPrefsRestore()
        }

        if !OnboardingController.isCompleted {
            let flow = OnboardingController(inputSafetyNet: inputSafetyNet) { [weak self] in
                Task { await self?.coordinator?.start() }
            }
            onboarding = flow
            flow.present()
        } else {
            Task {
                await coordinator.start()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        do {
            let command = try URLCommandParser.parse(url)
            Task {
                await coordinator?.execute(command, source: .binding)
            }
        } catch {
            // Reject unknown params / exec-and-forget.
        }
    }

    private func startSocketServer(coordinator: AppCoordinator, loader: ConfigLoader) {
        let server = CommandSocketServer()
        server.handler = { [weak coordinator, weak loader] request in
            await CommandSocketHandler.handle(
                request: request,
                coordinator: coordinator,
                configURL: loader?.fileURL ?? ConfigLoader.defaultFileURL()
            )
        }
        do {
            try server.start()
            socketServer = server
        } catch {
            // CLI unavailable this session.
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Lattice", action: nil, keyEquivalent: ""))
        if let warning = permissionMonitor?.menuWarningTitle {
            let item = NSMenuItem(
                title: warning,
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }
        if inputSafetyNet.reducedInputFeatures, let notice = inputSafetyNet.notice {
            menu.addItem(NSMenuItem(title: notice, action: nil, keyEquivalent: ""))
        }
        if let err = configLoader?.lastError {
            let item = NSMenuItem(
                title: "Config error: \(err.errors.first?.description ?? "unknown")",
                action: #selector(openSettings),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }
        if let spacesNotice = coordinator?.spacesMenuNotice {
            menu.addItem(NSMenuItem(title: spacesNotice, action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(openSettings), ","))
        menu.addItem(menuItem("About Lattice…", #selector(showAbout)))
        menu.addItem(menuItem("Dock all windows", #selector(dockAll)))
        menu.addItem(menuItem("Float every window", #selector(unmanageAll)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Override macOS tiling…", #selector(overrideTiling)))
        menu.addItem(menuItem("Restore macOS settings & quit", #selector(restorePrefsAndQuit)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Lattice", #selector(quitLattice), "q"))
        return menu
    }

    private func rebuildMenu() {
        statusItem?.menu = buildMenu()
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url { NSWorkspace.shared.open(url) }
    }

    @objc private func openSettings() {
        let url = configLoader?.fileURL ?? ConfigLoader.defaultFileURL()
        let controller = SettingsWindowController(
            configURL: url,
            onAppendRule: { [weak self] in
                self?.appendRuleForFrontmost()
            },
            onReload: { [weak self] in
                _ = self?.configLoader?.reload()
                if let cfg = self?.configLoader?.config {
                    self?.coordinator?.reloadConfig(cfg)
                    if let server = self?.windowServer {
                        server.applyExperimentalConfig(cfg.experimental)
                    }
                }
            }
        )
        settingsController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
        let alert = NSAlert()
        alert.messageText = "Lattice \(version)"
        alert.informativeText = """
            Config format compatible with Dinky by Mikkel Malmberg (MIT).

            Optional [experimental] flags in lattice.toml (ax-window-id, multitouch) are off by default. If a private symbol is missing or a call fails, Lattice auto-disables that flag and keeps the public path.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func appendRuleForFrontmost() {
        let app = NSWorkspace.shared.frontmostApplication
        let url = configLoader?.fileURL ?? ConfigLoader.defaultFileURL()
        do {
            try ConfigAppender.appendRule(
                to: url,
                appId: app?.bundleIdentifier,
                appName: app?.localizedName
            )
            _ = configLoader?.reload()
            if let cfg = configLoader?.config {
                coordinator?.reloadConfig(cfg)
            }
        } catch {
            // Best-effort.
        }
    }

    @objc private func dockAll() {
        Task { await coordinator?.execute(.dockAll) }
    }

    @objc private func unmanageAll() {
        Task { await coordinator?.unmanageAll() }
    }

    @objc private func overrideTiling() {
        let alert = NSAlert()
        alert.messageText = "Disable macOS edge tiling?"
        alert.informativeText =
            "Lattice can turn off native edge tiling so it does not fight managed layouts. Originals are backed up and can be restored from the menu."
        alert.addButton(withTitle: "Disable & Backup")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? coordinator?.systemPrefsBackup.applyOverrides(disableEdgeTiling: true)
    }

    @objc private func restorePrefsAndQuit() {
        try? coordinator?.systemPrefsBackup.restore()
        Task { @MainActor in
            await coordinator?.prepareSafeQuit()
            coordinator?.stop()
            socketServer?.stop()
            NSApp.terminate(nil)
        }
    }

    private func offerPrefsRestore() {
        let alert = NSAlert()
        alert.messageText = "Restore macOS window settings?"
        alert.informativeText =
            "Lattice did not shut down cleanly and may have left overridden tiling preferences. Restore the backed-up values?"
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Keep")
        if alert.runModal() == .alertFirstButtonReturn {
            try? coordinator?.systemPrefsBackup.restore()
        }
    }

    @objc private func quitLattice() {
        Task { @MainActor in
            await coordinator?.prepareSafeQuit()
            coordinator?.stop()
            socketServer?.stop()
            bordersOverlay?.hideAll()
            tabStrip?.hideAll()
            permissionMonitor?.stop()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? coordinator?.systemPrefsBackup.markCleanShutdown()
        socketServer?.stop()
        coordinator?.stop()
        permissionMonitor?.stop()
    }
}
