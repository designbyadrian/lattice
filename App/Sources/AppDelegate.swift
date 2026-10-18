import AppKit
import AppCore
import Config
import LayoutModel
import Platform
import PlatformMac

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar = MenuBarController()
    private var coordinator: AppCoordinator?
    private var windowServer: MacWindowServer?
    private var configLoader: ConfigLoader?
    private var settingsController: SettingsWindowController?
    private var socketServer: CommandSocketServer?
    private var bordersOverlay: BordersOverlayController?
    private var tabStrip: TabStripOverlay?
    private var onboarding: OnboardingController?
    private var permissionMonitor: PermissionMonitor?
    private var inputTap: InputTapController?
    private var gettingStarted: GettingStartedCardController?
    private var inputSafetyNet: InputSafetyNetState = .full
    private var inputFeaturesDisabled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let loader = ConfigLoader()
        configLoader = loader
        let config: LatticeConfig
        do {
            config = try loader.loadOrCreateDefaults()
        } catch {
            config = .default
        }

        menuBar.install { [weak self] action in
            self?.handleMenuAction(action)
        }

        let server = MacWindowServer()
        windowServer = server
        server.applyExperimentalConfig(config.experimental)

        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let tapController = InputTapController(config: config, safetyNet: .full)
        let tapCreated = tapController.start()
        inputSafetyNet = InputSafetyNetState.from(
            tapCreated: tapCreated,
            inputMonitoringPrompted: false,
            osMajor: osMajor
        )
        tapController.update(config: config, safetyNet: inputSafetyNet, mode: DefaultBindings.modeName)
        wireInputTap(tapController)
        inputTap = tapController

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
                self.refreshMenu()
            }
        }
        coordinator.onTabGroupsChanged = { [weak self] groups in
            Task { @MainActor in
                self?.tabStrip?.update(groups: groups)
                if !groups.isEmpty {
                    _ = self?.gettingStarted?.handle(.tabGroupFormed)
                }
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
                    self?.inputTap?.update(
                        config: cfg,
                        safetyNet: self?.effectiveSafetyNet() ?? .full,
                        mode: self?.coordinator?.currentMode ?? DefaultBindings.modeName
                    )
                    self?.settingsController?.reloadFromDisk()
                }
                self?.refreshMenu()
            }
        }

        startSocketServer(coordinator: coordinator, loader: loader)

        assert(
            OnboardingStub.recordingIndicatorDisclosure.contains("recording indicator"),
            "Onboarding must disclose the Screen Recording indicator"
        )

        let monitor = PermissionMonitor()
        monitor.onChange = { [weak self] in self?.refreshMenu() }
        monitor.start()
        permissionMonitor = monitor

        let card = GettingStartedCardController(
            onSkip: { [weak self] in self?.gettingStarted?.hide() },
            onChanged: { _ in }
        )
        gettingStarted = card

        refreshMenu()
        if card.currentModel.isVisible {
            card.showAnchored(under: menuBar.latticeButtonFrame())
        }

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
        for url in urls { handleURL(url) }
    }

    // MARK: - Input tap

    private func wireInputTap(_ tap: InputTapController) {
        tap.onCommands = { [weak self] commands in
            Task { @MainActor in
                for command in commands {
                    await self?.coordinator?.execute(command, source: .binding)
                    self?.noteGettingStarted(for: command)
                }
                self?.refreshMenu()
            }
        }
        tap.onGreenButton = { [weak self] in
            Task { @MainActor in
                // Toggle dock/float for focused window (B15).
                await self?.coordinator?.execute(.layoutFloating)
                _ = self?.gettingStarted?.handle(.docked)
                self?.refreshMenu()
            }
        }
        tap.onModifierDrag = { [weak self] _ in
            Task { @MainActor in
                await self?.coordinator?.execute(.frameRect)
            }
        }
        tap.onDragCancel = { [weak self] in
            Task { @MainActor in
                await self?.coordinator?.cancelDrag()
            }
        }
        tap.isDragSessionActive = { [weak self] in
            self?.coordinator?.activeDrag != nil
        }
    }

    private func effectiveSafetyNet() -> InputSafetyNetState {
        if inputFeaturesDisabled {
            return .reduced(reason: "Input features disabled from the Lattice menu.")
        }
        return inputSafetyNet
    }

    private func noteGettingStarted(for command: Command) {
        switch command {
        case .zoom(.out, _): _ = gettingStarted?.handle(.zoomedOut)
        case .zoom(.in, _): _ = gettingStarted?.handle(.zoomedIn)
        case .zoom(.window, _), .zoom(.desktop, _):
            _ = gettingStarted?.handle(.doubleClickedFocus)
        case .dock, .dockAll:
            _ = gettingStarted?.handle(.docked)
        case .tabWith:
            _ = gettingStarted?.handle(.tabGroupFormed)
        case .resize:
            _ = gettingStarted?.handle(.seamResized)
        default:
            break
        }
    }

    // MARK: - Menu

    private func refreshMenu() {
        let front = NSWorkspace.shared.frontmostApplication?.localizedName
        let net = effectiveSafetyNet()
        let model = coordinator?.buildMenuModel(
            frontmostAppName: front,
            inputFeaturesDisabled: inputFeaturesDisabled,
            inputSafetyNetActive: net.reducedInputFeatures,
            inputSafetyNetNotice: net.notice
        ) ?? MenuModel.build(from: MenuModelState(
            inputFeaturesDisabled: inputFeaturesDisabled,
            inputSafetyNetActive: net.reducedInputFeatures,
            inputSafetyNetNotice: net.notice,
            frontmostAppName: front,
            menuBarControls: configLoader?.config.menuBarControls ?? MenuBarControl.allCases
        ))
        menuBar.update(model: model)
    }

    private func handleMenuAction(_ action: MenuAction) {
        Task { @MainActor in
            switch action {
            case .historyBack:
                await coordinator?.execute(.history(.back))
            case .historyForward:
                await coordinator?.execute(.history(.forward))
            case .zoomDesktop:
                await coordinator?.execute(.zoom(.desktop, toggle: false))
            case .zoomEverything:
                await coordinator?.execute(.zoom(.all, toggle: false))
            case .recallView(let n):
                await coordinator?.execute(.recallView(n))
            case .storeView(let n):
                await coordinator?.execute(.storeView(n))
            case .desktopAreaToggle:
                await coordinator?.execute(.desktopArea(.toggle))
            case .dockAll:
                await coordinator?.execute(.dockAll)
                _ = gettingStarted?.handle(.docked)
            case .unmanageAll:
                await coordinator?.unmanageAll()
            case .leaveAppAlone:
                appendIgnoreForFrontmost()
            case .workspace(let n):
                await coordinator?.execute(.workspace(.number(n)))
            case .spacesDetails:
                showSpacesDetails()
            case .toggleInputFeatures:
                inputFeaturesDisabled.toggle()
                inputTap?.update(
                    config: coordinator?.config ?? .default,
                    safetyNet: effectiveSafetyNet(),
                    mode: coordinator?.currentMode ?? DefaultBindings.modeName
                )
            case .openSettings:
                openSettings()
            case .quit:
                quitLattice()
            }
            refreshMenu()
        }
    }

    private func appendIgnoreForFrontmost() {
        let app = NSWorkspace.shared.frontmostApplication
        let url = configLoader?.fileURL ?? ConfigLoader.defaultFileURL()
        do {
            try ConfigAppender.appendRule(
                to: url,
                appId: app?.bundleIdentifier,
                appName: app?.localizedName,
                run: ["ignore"]
            )
            _ = configLoader?.reload()
            if let cfg = configLoader?.config {
                coordinator?.reloadConfig(cfg)
            }
        } catch {
            // Best-effort.
        }
    }

    private func showSpacesDetails() {
        let alert = NSAlert()
        alert.messageText = SpacesSafetyNetCopy.hudMessage
        alert.informativeText =
            "Lattice could not use native Spaces APIs on this macOS build. Window management stays on the current Space."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Settings / lifecycle

    private func handleURL(_ url: URL) {
        do {
            let command = try URLCommandParser.parse(url)
            Task {
                await coordinator?.execute(command, source: .binding)
                refreshMenu()
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

    @objc private func openSettings() {
        let url = configLoader?.fileURL ?? ConfigLoader.defaultFileURL()
        let controller = SettingsWindowController(
            configURL: url,
            systemPrefs: coordinator?.systemPrefsBackup,
            onReload: { [weak self] in
                _ = self?.configLoader?.reload()
                if let cfg = self?.configLoader?.config {
                    self?.coordinator?.reloadConfig(cfg)
                    if let server = self?.windowServer {
                        server.applyExperimentalConfig(cfg.experimental)
                    }
                    self?.inputTap?.update(
                        config: cfg,
                        safetyNet: self?.effectiveSafetyNet() ?? .full,
                        mode: self?.coordinator?.currentMode ?? DefaultBindings.modeName
                    )
                }
                self?.refreshMenu()
            },
            onRestartGettingStarted: { [weak self] in
                self?.gettingStarted?.restart()
                self?.gettingStarted?.showAnchored(under: self?.menuBar.latticeButtonFrame())
            },
            onOverridePrefs: { [weak self] in
                try? self?.coordinator?.systemPrefsBackup.applyOverrides(disableEdgeTiling: true)
            },
            onRestorePrefs: { [weak self] in
                try? self?.coordinator?.systemPrefsBackup.restore()
            }
        )
        settingsController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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
            inputTap?.stop()
            socketServer?.stop()
            bordersOverlay?.hideAll()
            tabStrip?.hideAll()
            permissionMonitor?.stop()
            gettingStarted?.hide()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? coordinator?.systemPrefsBackup.markCleanShutdown()
        inputTap?.stop()
        socketServer?.stop()
        coordinator?.stop()
        permissionMonitor?.stop()
    }
}
