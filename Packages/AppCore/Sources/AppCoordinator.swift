import Foundation
import LayoutEngine
import LayoutModel
import Platform
import Config

/// Wires LayoutEngine ↔ Platform. Never imports PlatformMac.
public final class AppCoordinator: @unchecked Sendable {
    public private(set) var config: LatticeConfig
    public let platform: any WindowServerProtocol

    /// Display UUID → layout persistence blob.
    public private(set) var displayLayouts: [String: DisplayLayout] = [:]
    /// Active workspace number per display UUID (1-based).
    public private(set) var activeWorkspaceNumber: [String: Int] = [:]

    public var gaps: Gaps = .zero
    /// Bundle IDs that must never be tiled.
    public var globalExcludedApps: Set<BundleID> = []

    /// When true, layout hotkeys are no-ops (full-screen Space).
    public private(set) var isActiveSpaceFullscreen: Bool = false

    /// Last solved frames (for safe quit / debugging).
    public private(set) var lastFrames: [WindowID: Rect] = [:]

    /// Persisted workspace↔Space binding (mirrored from SpacesControlling).
    public private(set) var spaceBinding: WorkspaceSpaceBinding = WorkspaceSpaceBinding()

    /// Last workspace number before a switch (for `workspace-back-and-forth`).
    public private(set) var previousWorkspaceNumber: Int?

    /// HUD stub text when workspace commands are blocked by the safety net.
    public private(set) var lastHUDMessage: String?

    /// Menu notice stub when Spaces backend is `.currentSpaceOnly`.
    public var spacesMenuNotice: String? {
        platform.spacesController.spacesMenuNotice
    }

    /// Camera navigation history keyed by `"\(displayUUID)#\(workspaceNumber)"`.
    public private(set) var navigationHistories: [String: NavigationHistory] = [:]

    /// Pending frame-rect drag (screen coordinates); set when `frame-rect` opens the overlay.
    public private(set) var pendingFrameRect: Rect?

    /// Title-bar drag session (live make-room); nil when idle.
    public private(set) var activeDrag: DragSession?

    /// Continuous pinch in progress (B9).
    public private(set) var pinchActive: Bool = false

    /// Animation duration override (nil → `LayoutMotion.defaultDurationSeconds`).
    public var animationDurationSeconds: Double?

    /// Previous icon-tile ids (hysteresis) per display#workspace.
    private var previousIconTiles: [String: Set<NodeID>] = [:]

    /// AX read-back / learn generation budget for the current user action.
    private var axResolveGeneration: Int = 0

    /// Learned / rule `min-size` constraints keyed by window.
    public private(set) var minSizes: MinSizes = [:]

    /// Debounced layout persistence.
    public let layoutStore: LayoutStore

    /// Opt-in macOS prefs backup / restore.
    public let systemPrefsBackup: SystemPrefsBackup

    /// Focus-follows-mouse state (pure machine; host drives timers / AX).
    public private(set) var focusFollowsMouse: FocusFollowsMouseMachine

    /// Current binding mode name.
    public private(set) var currentMode: String = DefaultBindings.modeName

    /// Last focused managed window (for tab-with focused / dock).
    public private(set) var focusedWindowID: WindowID?

    /// When false, enable off — layout commands no-op.
    public private(set) var isEnabled: Bool = true

    /// Callback when borders / tab strip should refresh (App shell wires overlays).
    public var onFramesApplied: (([WindowID: Rect], DisplayLayout?) -> Void)?

    /// Callback to raise/focus a window from FFM.
    public var focusWindowHandler: ((WindowID) async -> Void)?

    /// Callback after tab group selection changes (tab strip).
    public var onTabGroupsChanged: (([TabGroupSnapshot]) -> Void)?

    private let queue = DispatchQueue(label: "com.designbyadrian.lattice.app-coordinator")
    private var started = false
    private var spacesReconcileDebounce: DispatchWorkItem?
    private var lastSpaceBindingBeforeFailedAction: WorkspaceSpaceBinding?
    public init(
        platform: any WindowServerProtocol,
        config: LatticeConfig = .default,
        layoutStore: LayoutStore = LayoutStore(),
        systemPrefsBackup: SystemPrefsBackup = SystemPrefsBackup()
    ) {
        self.platform = platform
        self.config = config
        self.layoutStore = layoutStore
        self.systemPrefsBackup = systemPrefsBackup
        self.focusFollowsMouse = FocusFollowsMouseMachine(config: config.focusFollowsMouse)
        self.spaceBinding = platform.spacesController.loadSpaceBinding()
        self.animationDurationSeconds = config.animations.enabled
            ? config.animations.durationSeconds
            : 0
    }

    public func reloadConfig(_ config: LatticeConfig) {
        queue.sync {
            self.config = config
            self.focusFollowsMouse.config = config.focusFollowsMouse
            self.animationDurationSeconds = config.animations.enabled
                ? config.animations.durationSeconds
                : 0
        }
        Task { await self.scheduleSpacesReconcile(immediate: true) }
    }

    // MARK: - Lifecycle

    public func start() async {
        let already: Bool = queue.sync {
            if started { return true }
            started = true
            return false
        }
        guard !already else { return }

        spaceBinding = platform.spacesController.loadSpaceBinding()
        platform.startObserving { [weak self] event in
            Task { await self?.handle(event) }
        }
        await loadPersistedLayouts()
        await reconcile()
        await runSpacesReconcile()
        await refreshFullscreenSpaceFlag()
        await runHooks(config.hooks.startup, source: .hook)
    }

    public func stop() {
        layoutStore.flushAll()
        platform.stopObserving()
        queue.sync {
            started = false
            spacesReconcileDebounce?.cancel()
            spacesReconcileDebounce = nil
        }
        try? systemPrefsBackup.markCleanShutdown()
    }

    public func setActiveSpaceFullscreen(_ value: Bool) {
        queue.sync { isActiveSpaceFullscreen = value }
    }

    /// Layout / tile hotkeys should call this; returns `false` when ignored.
    public func allowLayoutHotkey() -> Bool {
        queue.sync { !isActiveSpaceFullscreen }
    }

    // MARK: - Commands

    /// Dispatch a parsed config / binding command.
    public func execute(_ command: Command, source: ExecAndForget.Source = .binding) async {
        if case .enable(let state) = command {
            await applyEnable(state)
            return
        }
        guard isEnabled || command == .reloadConfig else { return }

        if ExecAndForget.runIfPresent(command, source: source) {
            return
        }

        switch command {
        case .workspace(let target):
            await switchWorkspace(target)
        case .workspaceBackAndForth:
            await workspaceBackAndForth()
        case .moveWindowToWorkspace(let target, let follow):
            await moveFocusedWindowToWorkspace(target, follow: follow)
        case .moveWindowToDisplay(let target, let follow):
            await moveFocusedWindowToDisplay(target, follow: follow)
        case .unmanageAll:
            await unmanageAll()
        case .zoom(let target, let toggle):
            await zoom(target, toggle: toggle)
        case .frameRect:
            await beginFrameRect()
        case .history(let direction):
            await navigateHistory(direction)
        case .recallView(let index):
            await loadSavedView(index)
        case .storeView(let index):
            await saveCurrentView(index)
        case .pan(let direction):
            await pan(direction)
        case .desktopArea(let action):
            await desktopArea(action)
        case .dockAll:
            await dockAll()
        case .splitNew(let appId):
            await splitNew(appId: appId)
        case .splitDirection(let action):
            await splitDirection(action)
        case .reloadConfig:
            break // App shell reloads file then calls reloadConfig(_:)
        case .mode(let name):
            await setMode(name)
        case .dock(let direction, let screen):
            await dockFocused(direction: direction, screen: screen)
        case .tabWith(let target):
            await tabWith(target)
        case .untab:
            await untabFocused()
        case .tab(let target):
            await tabNavigate(target)
        case .minSize(let w, let h):
            await setMinSizeForFocused(width: w, height: h)
        case .clearMinimumSizes:
            queue.sync { minSizes = [:] }
            await applySolvedFrames()
        case .ignore:
            await ignoreFocused()
        case .layoutFloating:
            await setFocusedFloating(true)
        case .layoutTiling:
            await setFocusedFloating(false)
        case .retile:
            await applySolvedFrames(animated: true, useCamera: true)
        case .joinWith(let direction):
            await joinFocused(with: direction)
        case .split(let axis):
            await splitFocused(axis: axis)
        case .focus(let direction):
            await focusNeighbor(direction)
        case .move(let direction):
            await moveFocused(direction)
        case .resize(let axis, let delta):
            await resizeFocused(axis: axis, delta: delta)
        case .balanceSizes:
            await balanceSizes()
        case .flattenWorkspaceTree:
            await flattenWorkspaceTree()
        case .layoutCycle, .list, .execAndForget, .enable:
            break
        }
    }

    public func listCommand(_ verb: String) async -> String {
        switch verb {
        case "list-windows":
            let windows = await platform.listWindows()
            return windows.map {
                "\($0.id)\t\($0.pid)\t\($0.bundleID ?? "-")\t\($0.title)"
            }.joined(separator: "\n")
        case "list-workspaces":
            let (count, active, binding) = queue.sync {
                (config.workspaces, activeWorkspaceNumber, spaceBinding.binding)
            }
            return (1...count).map { n in
                let mark = active.values.contains(n) ? "*" : " "
                let space = binding[n].map { String($0.rawValue) } ?? "-"
                return "\(mark) \(n)\tspace=\(space)"
            }.joined(separator: "\n")
        case "list-displays":
            let displays = await platform.listDisplays()
            return displays.map { "\($0.uuid)\t\($0.name)" }.joined(separator: "\n")
        case "list-modes":
            let modes = queue.sync { Array(config.modes.keys).sorted() }
            let current = queue.sync { currentMode }
            return modes.map { ($0 == current ? "* " : "  ") + $0 }.joined(separator: "\n")
        default:
            return ""
        }
    }

    public func unmanageAll() async {
        guard allowLayoutHotkey() else { return }
        queue.sync {
            for uuid in displayLayouts.keys {
                var layout = displayLayouts[uuid]!
                let num = activeWorkspaceNumber[uuid] ?? 1
                let ws = layout.workspaces[num] ?? .empty
                let (next, _) = ws.floatingAll()
                layout.workspaces[num] = next
                displayLayouts[uuid] = layout
            }
        }
        await applySolvedFrames()
    }

    /// - Note: Prefer `unmanageAll()` (ADDENDUM-2 §R).
    public func floatAll() async {
        await unmanageAll()
    }

    /// Leave every managed window on-screen before quit.
    public func prepareSafeQuit() async {
        platform.frameAnimator.cancelAnimation()

        let displays = await platform.listDisplays()
        let union = displays.map(\.visibleFrame.asRect).reduce(Rect.zero) { acc, r in
            if acc.width == 0 && acc.height == 0 { return r }
            let minX = min(acc.minX, r.minX)
            let minY = min(acc.minY, r.minY)
            let maxX = max(acc.maxX, r.maxX)
            let maxY = max(acc.maxY, r.maxY)
            return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        // Apply un-zoomed solve frames so nothing stays parked off-screen.
        await applySolvedFrames(animated: false, useCamera: false)

        let frames = queue.sync { lastFrames }
        for (id, frame) in frames {
            guard let cgID = id.cgWindowID else { continue }
            let clamped = clampOnScreen(frame, within: union)
            try? await platform.setFrame(clamped.asCGRectCodable, for: cgID, pid: id.processID)
        }
    }

    // MARK: - Camera / zoom (P5 / P7, ADDENDUM-2 B6/B10)

    public func zoom(_ target: ZoomTarget, toggle: Bool = false) async {
        guard allowLayoutHotkey() else { return }
        let focused = queue.sync { focusedWindowID }
        await mutateActiveCamera { engine, history in
            switch target {
            case .in:
                let point = Point(x: engine.displayRect.midX, y: engine.displayRect.midY)
                engine.stepIn(towardPoint: point)
                history.navigate(to: engine.camera)
            case .out:
                engine.stepOut()
                history.navigate(to: engine.camera)
            case .all:
                engine.showAll()
                history.navigate(to: engine.camera)
            case .window:
                let id = focused ?? engine.workspace.root.tiledWindowIDs.first
                if let id {
                    if toggle {
                        engine.toggleFrame(target: id.nodeID, history: &history)
                    } else {
                        engine.frameAlone(id)
                        history.navigate(to: engine.camera)
                    }
                }
            case .desktop:
                if toggle {
                    engine.toggleFrame(target: "desktop", history: &history)
                } else {
                    engine.frameDesktop()
                    history.navigate(to: engine.camera)
                }
            }
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    /// Open frame-rect mode: next `commitFrameRect` zooms to the dragged world rect.
    public func beginFrameRect() async {
        guard allowLayoutHotkey() else { return }
        queue.sync { pendingFrameRect = nil }
    }

    public func commitFrameRect(_ rect: Rect) async {
        guard allowLayoutHotkey() else { return }
        await mutateActiveCamera { engine, history in
            engine.frameRect(rect)
            history.navigate(to: engine.camera)
        }
        queue.sync { pendingFrameRect = nil }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    public func navigateHistory(_ direction: HistoryDirection) async {
        guard allowLayoutHotkey() else { return }
        await mutateActiveCamera { engine, history in
            let cam: Camera?
            switch direction {
            case .back: cam = history.back()
            case .forward: cam = history.forward()
            }
            if let cam {
                engine.camera = cam
            }
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    public func loadSavedView(_ index: Int) async {
        guard allowLayoutHotkey() else { return }
        await mutateActiveCamera { engine, history, layout in
            if let cam = SavedViews.apply(index, from: layout, history: &history) {
                engine.camera = cam
            }
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    public func saveCurrentView(_ index: Int) async {
        guard allowLayoutHotkey() else { return }
        var saved: DisplayLayout?
        queue.sync {
            guard let uuid = displayLayouts.keys.sorted().first else { return }
            let num = activeWorkspaceNumber[uuid] ?? 1
            var layout = displayLayouts[uuid] ?? DisplayLayout(displayUUID: uuid)
            let cam = layout.workspaces[num]?.camera ?? .showAll
            SavedViews.save(index, camera: cam, into: &layout)
            displayLayouts[uuid] = layout
            saved = layout
        }
        if let saved {
            layoutStore.scheduleSave(saved)
        }
    }

    public func pan(_ direction: CommandDirection) async {
        guard allowLayoutHotkey() else { return }
        var moved = false
        await mutateActiveCamera { engine, history in
            moved = engine.pan(direction.edge)
            if moved {
                history.navigate(to: engine.camera)
            }
        }
        if moved {
            await applySolvedFrames(animated: true, useCamera: true)
        }
    }

    public func desktopArea(_ action: DesktopAreaAction) async {
        guard allowLayoutHotkey() else { return }
        queue.sync {
            for (uuid, var layout) in displayLayouts {
                let num = activeWorkspaceNumber[uuid] ?? 1
                var ws = layout.workspaces[num] ?? .empty
                switch action {
                case .show:
                    let (next, _) = ws.showingDesktop()
                    ws = next
                case .hide:
                    let (next, _) = ws.hidingDesktop()
                    ws = next
                case .toggle:
                    if ws.desktopHidden {
                        let (next, _) = ws.showingDesktop()
                        ws = next
                    } else {
                        let (next, _) = ws.hidingDesktop()
                        ws = next
                    }
                }
                layout.workspaces[num] = ws
                displayLayouts[uuid] = layout
            }
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    public func dockAll() async {
        guard allowLayoutHotkey() else { return }
        let displays = await platform.listDisplays()
        queue.sync {
            for display in displays {
                let uuid = display.uuid
                let num = activeWorkspaceNumber[uuid] ?? 1
                var layout = displayLayouts[uuid] ?? DisplayLayout(displayUUID: uuid)
                var ws = layout.workspaces[num] ?? .empty
                let floats = ws.floatWins.sorted { a, b in
                    if a.frac.x0 != b.frac.x0 { return a.frac.x0 < b.frac.x0 }
                    return a.frac.y0 < b.frac.y0
                }.map(\.window)
                ws.root = TreeOps.dockAll(ws.root, floatsInXOrder: floats, cfg: ws.layoutConfig)
                layout.workspaces[num] = ws
                displayLayouts[uuid] = layout
            }
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    private func splitNew(appId: String) async {
        // Launch is App-shell concern; here we only dock a matching existing window if present.
        guard let id = await findWindow(bundleID: appId) else {
            queue.sync { lastHUDMessage = "No window for \(appId)" }
            return
        }
        queue.sync { focusedWindowID = id }
        await dockFocused(direction: .right, screen: false)
    }

    private func splitDirection(_ action: SplitDirectionAction) async {
        guard allowLayoutHotkey() else { return }
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        mutateWorkspaceContaining(id) { ws in
            guard let path = ws.root.path(to: id), path.count >= 1 else { return ws }
            let parentPath = Array(path.dropLast())
            guard case .split(var split) = ws.root.node(at: parentPath) else { return ws }
            switch action {
            case .toggle:
                split.axis = split.axis == .horizontal ? .vertical : .horizontal
            case .horizontal:
                split.axis = .horizontal
            case .vertical:
                split.axis = .vertical
            }
            var next = ws
            if let updated = next.root.replacing(at: parentPath, with: .split(split)) {
                next.root = updated.normalizedOrDesktop(cfg: next.layoutConfig)
            }
            return next
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    // MARK: - Events

    public func handle(_ event: PlatformEvent) async {
        switch event {
        case .windowCreated(let ref):
            await insertIfNeeded(ref)
            await applySolvedFrames()
        case .windowDestroyed(_, let pid):
            await removeMissing(pidHint: pid)
            await applySolvedFrames()
        case .windowMinimized(_, let pid):
            suspendMatching(pid: pid, state: .minimized)
            await applySolvedFrames()
        case .windowDeminimized(let ref):
            resume(ref, to: .active)
            await applySolvedFrames()
        case .windowFullscreenChanged(let ref, let isFullscreen):
            if isFullscreen {
                suspend(ref, state: .fullscreen)
                setActiveSpaceFullscreen(true)
            } else {
                resume(ref, to: .active)
                await refreshFullscreenSpaceFlag()
            }
            await applySolvedFrames()
        case .windowFocused(let ref):
            queue.sync { focusedWindowID = ref.asWindowID }
            await runHooks(config.hooks.focusChanged, source: .hook)
            publishTabGroups()
        case .applicationHidden(let pid):
            suspendMatching(pid: pid, state: .hidden)
            await applySolvedFrames()
        case .applicationUnhidden(let pid):
            resumeMatching(pid: pid)
            await applySolvedFrames()
        case .applicationTerminated(let pid):
            removeAll(pid: pid)
            await applySolvedFrames()
        case .activeSpaceDidChange:
            _ = queue.sync { focusFollowsMouse.noteActivationOrSpaceChange() }
            await reconcile()
            await scheduleSpacesReconcile(immediate: false)
            await refreshFullscreenSpaceFlag()
        case .screenParametersChanged, .didWake:
            await reconcile()
            await scheduleSpacesReconcile(immediate: false)
            await refreshFullscreenSpaceFlag()
        case .applicationActivated:
            _ = queue.sync { focusFollowsMouse.noteActivationOrSpaceChange() }
        default:
            break
        }
    }

    // MARK: - Workspace commands (P6)

    public func switchWorkspace(_ target: WorkspaceTarget) async {
        if platform.spacesController.spacesBackend == .currentSpaceOnly {
            queue.sync { lastHUDMessage = SpacesSafetyNetCopy.hudMessage }
            return
        }
        guard let number = await resolveWorkspaceNumber(target) else { return }
        await activateWorkspace(number, followWindow: nil)
    }

    public func workspaceBackAndForth() async {
        if platform.spacesController.spacesBackend == .currentSpaceOnly {
            queue.sync { lastHUDMessage = SpacesSafetyNetCopy.hudMessage }
            return
        }
        let prev = queue.sync { previousWorkspaceNumber }
        guard let prev else { return }
        await activateWorkspace(prev, followWindow: nil)
    }

    public func moveFocusedWindowToWorkspace(_ target: WorkspaceTarget, follow: Bool) async {
        if platform.spacesController.spacesBackend == .currentSpaceOnly {
            queue.sync { lastHUDMessage = SpacesSafetyNetCopy.hudMessage }
            return
        }
        guard let number = await resolveWorkspaceNumber(target) else { return }
        guard let space = queue.sync(execute: { spaceBinding.binding[number] }) else { return }
        let windows = await platform.listWindows()
        // Focused ≈ frontmost managed window on the active display (AX focus arrives via events).
        guard let focused = windows.first else { return }
        _ = await platform.spacesController.moveWindowIDs([focused.id], to: space)
        if follow {
            await activateWorkspace(number, followWindow: focused)
        }
    }

    public func moveFocusedWindowToDisplay(_ target: DisplayTarget, follow: Bool) async {
        if platform.spacesController.spacesBackend == .currentSpaceOnly {
            queue.sync { lastHUDMessage = SpacesSafetyNetCopy.hudMessage }
            return
        }
        let displays = await platform.listDisplays()
        guard displays.count > 1 else { return }
        let snaps = await platform.spacesController.spaceDisplaySnapshots()
        let currentUUID = await focusedDisplayUUID() ?? displays[0].uuid
        guard let idx = displays.firstIndex(where: { $0.uuid == currentUUID }) else { return }
        let nextIdx: Int
        switch target {
        case .next: nextIdx = (idx + 1) % displays.count
        case .prev: nextIdx = (idx - 1 + displays.count) % displays.count
        }
        let dest = displays[nextIdx]
        let destSnap = snaps.first(where: { $0.uuid == dest.uuid })
        let destSpace = destSnap?.current
        let windows = await platform.listWindows()
        guard let focused = windows.first, let destSpace else { return }
        _ = await platform.spacesController.moveWindowIDs([focused.id], to: destSpace)
        if follow {
            _ = await platform.spacesController.switchToSpace(destSpace, on: dest.uuid)
            if let wsNum = queue.sync(execute: {
                spaceBinding.binding.first(where: { $0.value == destSpace })?.key
            }) {
                queue.sync { activeWorkspaceNumber[dest.uuid] = wsNum }
            }
        }
        await reconcile()
    }

    // MARK: - Spaces reconcile

    public func scheduleSpacesReconcile(immediate: Bool) async {
        if platform.spacesController.switchInFlight { return }
        if immediate {
            queue.sync {
                spacesReconcileDebounce?.cancel()
                spacesReconcileDebounce = nil
            }
            await runSpacesReconcile()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            Task { await self?.runSpacesReconcile() }
        }
        queue.sync {
            spacesReconcileDebounce?.cancel()
            spacesReconcileDebounce = work
        }
        queue.asyncAfter(deadline: .now() + .seconds(1), execute: work)
    }

    /// Apply the pure planner until nil / cap. Skips while a Space switch is in flight.
    public func runSpacesReconcile() async {
        if platform.spacesController.switchInFlight { return }
        let plan = queue.sync { config.workspacePlan }
        var binding = queue.sync { spaceBinding.binding }
        var owned = queue.sync { spaceBinding.ownedSpaces }
        var iterations = 0

        while iterations < ReconcilePlanner.defaultIterationCap {
            let displays = await platform.spacesController.spaceDisplaySnapshots()
            let occupied = await platform.spacesController.occupiedSpaceIDs()
            let step = ReconcilePlanner.step(
                displays: displays,
                binding: binding,
                owned: owned,
                occupied: occupied,
                plan: plan
            )
            binding = step.binding
            owned = step.owned
            persistBinding(binding: binding, owned: owned)

            guard let action = step.action else { break }

            lastSpaceBindingBeforeFailedAction = WorkspaceSpaceBinding(binding: binding, ownedSpaces: owned)
            let ok = await platform.spacesController.performReconcileAction(action)
            if !ok {
                // Roll back binding and wait for the next trigger.
                if let rolled = lastSpaceBindingBeforeFailedAction {
                    // Keep pre-action binding from disk/memory; drop speculative adopt only on create failure.
                    _ = rolled
                }
                break
            }
            if case .create = action {
                // Newly created Space is owned by Lattice.
                let after = await platform.spacesController.spaceDisplaySnapshots()
                let beforeIDs = Set(displays.flatMap { $0.spaces.map(\.id) })
                let newIDs = Set(after.flatMap { $0.spaces.map(\.id) }).subtracting(beforeIDs)
                owned.formUnion(newIDs)
                persistBinding(binding: binding, owned: owned)
            }
            iterations += 1
        }

        await syncActiveWorkspaceNumbersFromCurrentSpaces()
    }

    // MARK: - Reconcile / solve

    public func reconcile() async {
        let displays = await platform.listDisplays()
        let windows = await platform.listWindows()

        queue.sync {
            for display in displays {
                if displayLayouts[display.uuid] == nil {
                    displayLayouts[display.uuid] = DisplayLayout(displayUUID: display.uuid)
                }
                if activeWorkspaceNumber[display.uuid] == nil {
                    activeWorkspaceNumber[display.uuid] = 1
                }
            }
        }

        for window in windows {
            await insertIfNeeded(window)
            if window.isFullscreen {
                suspend(window, state: .fullscreen)
            } else if window.isMinimized {
                suspend(window, state: .minimized)
            }
        }
        await removeMissing(pidHint: nil)
        await applySolvedFrames()
    }

    public func applySolvedFrames() async {
        await applySolvedFrames(animated: false, useCamera: true)
    }

    /// Solve and apply frames. Camera maps through world rect; settle writes AX once
    /// in park → shrink → grow order (ADDENDUM-3 §5.1). Reduce Motion jumps.
    public func applySolvedFrames(animated: Bool, useCamera: Bool) async {
        let displays = await platform.listDisplays()
        var allFrames: [WindowID: Rect] = [:]
        var targets: [WindowFrameTarget] = []
        let previousFrames = queue.sync { lastFrames }

        for display in displays {
            let (workspace, gapsCopy): (Workspace, Gaps) = queue.sync {
                let num = activeWorkspaceNumber[display.uuid] ?? 1
                let layout = displayLayouts[display.uuid] ?? DisplayLayout(displayUUID: display.uuid)
                var workspace = layout.workspaces[num] ?? .empty
                workspace.excludedApps.formUnion(globalExcludedApps)
                workspace.root = Self.applyMinSizes(workspace.root, sizes: minSizes)
                return (workspace, gaps)
            }

            let displayRect = display.visibleFrame.asRect
            let sizes = queue.sync { minSizes }
            var ws = workspace
            if !useCamera {
                ws.camera = .home
            }
            let result = LayoutEngine.solve(
                workspace: ws,
                displayRect: displayRect,
                gaps: gapsCopy,
                minSizes: sizes
            )

            for (id, rect) in result {
                allFrames[id] = rect
                guard let cgID = id.cgWindowID, cgID != 0 else { continue }
                if workspace.state(of: id).isSuspended { continue }
                targets.append(WindowFrameTarget(
                    windowID: cgID,
                    pid: id.processID,
                    frame: rect.asCGRectCodable
                ))
            }
        }

        targets = Self.orderedSettleTargets(targets, previous: previousFrames)

        let layoutSnapshot: DisplayLayout? = queue.sync {
            lastFrames = allFrames
            let uuid = displayLayouts.keys.sorted().first
            return uuid.flatMap { displayLayouts[$0] }
        }

        let duration = animationDurationSeconds ?? LayoutMotion.defaultDurationSeconds
        let reduceMotion = platform.accessibilityReduceMotion
        let animEnabled = queue.sync { config.animations.enabled }
        // B12: still proxies elsewhere; AX applied once at settle (animator finals / jump).
        if animated && animEnabled && !reduceMotion {
            await platform.frameAnimator.animateFrames(
                to: targets,
                durationSeconds: duration,
                reduceMotion: false
            )
        } else {
            await platform.frameAnimator.animateFrames(
                to: targets,
                durationSeconds: 0,
                reduceMotion: true
            )
        }

        await readBackAndLearn(targets: targets)
        onFramesApplied?(allFrames, layoutSnapshot)
        publishTabGroups()
        persistAllLayouts()
    }

    static func orderedSettleTargets(
        _ targets: [WindowFrameTarget],
        previous: [WindowID: Rect]
    ) -> [WindowFrameTarget] {
        func area(_ t: WindowFrameTarget) -> Double { t.frame.width * t.frame.height }
        func prevArea(_ t: WindowFrameTarget) -> Double {
            if let p = previous.first(where: {
                $0.key.cgWindowID == t.windowID && $0.key.processID == t.pid
            })?.value {
                return p.width * p.height
            }
            return area(t)
        }
        let isPark: (WindowFrameTarget) -> Bool = { t in
            t.frame.x < -50 || t.frame.y < -50 || t.frame.x > 8_000 || t.frame.y > 8_000
        }
        let parked = targets.filter(isPark)
        let rest = targets.filter { !isPark($0) }
        let shrink = rest.filter { area($0) + 1 < prevArea($0) }
        let grow = rest.filter { area($0) + 1 >= prevArea($0) }
        return parked + shrink + grow
    }

    static func applyMinSizes(_ root: LayoutNode, sizes: MinSizes) -> LayoutNode {
        func leaf(_ w: WindowLeaf) -> WindowLeaf {
            var copy = w
            if let s = sizes[w.identity] ?? sizes.first(where: { $0.key.nodeID == w.id })?.value {
                copy.appMin = s
            }
            return copy
        }
        switch root {
        case .window(let w): return .window(leaf(w))
        case .tabs(var t):
            t.members = t.members.map(leaf)
            return .tabs(t)
        case .desktop(var d):
            d.floats = d.floats.map { FloatWin(window: leaf($0.window), frac: $0.frac) }
            return .desktop(d)
        case .split(var s):
            s.children = s.children.map { applyMinSizes($0, sizes: sizes) }
            return .split(s)
        }
    }

    private func readBackAndLearn(targets: [WindowFrameTarget]) async {
        let learn = queue.sync { config.windowSizing.learnMinimums }
        guard learn else { return }
        let live = await platform.listWindows()
        let tol = Double(queue.sync { config.windowSizing.axSizeTolerance })
        queue.sync {
            for t in targets {
                guard let ref = live.first(where: { $0.id == t.windowID && $0.pid == t.pid }) else { continue }
                let got = ref.frame
                let want = t.frame
                let id = ref.asWindowID
                if got.width > want.width + tol {
                    let prevH = minSizes[id]?.height ?? got.height
                    minSizes[id] = Size(width: got.width, height: prevH)
                }
                if got.height > want.height + tol {
                    let prevW = minSizes[id]?.width ?? got.width
                    minSizes[id] = Size(width: prevW, height: got.height)
                }
                if let learned = minSizes[id],
                   got.width < learned.width - tol || got.height < learned.height - tol {
                    minSizes[id] = Size(
                        width: min(learned.width, got.width),
                        height: min(learned.height, got.height)
                    )
                }
            }
        }
    }

    // MARK: - Camera helpers

    private func historyKey(displayUUID: String, workspace: Int) -> String {
        "\(displayUUID)#\(workspace)"
    }

    private func mutateActiveCamera(
        _ body: (inout CameraEngine, inout NavigationHistory) -> Void
    ) async {
        let displays = await platform.listDisplays()
        guard let display = displays.first else { return }
        queue.sync {
            let num = activeWorkspaceNumber[display.uuid] ?? 1
            var layout = displayLayouts[display.uuid] ?? DisplayLayout(displayUUID: display.uuid)
            var workspace = layout.workspaces[num] ?? .empty
            workspace.excludedApps.formUnion(globalExcludedApps)
            var engine = CameraEngine(
                workspace: workspace,
                displayRect: display.visibleFrame.asRect,
                gaps: gaps
            )
            let key = historyKey(displayUUID: display.uuid, workspace: num)
            var history = navigationHistories[key] ?? NavigationHistory(current: engine.camera)
            body(&engine, &history)
            layout.workspaces[num] = engine.workspace
            displayLayouts[display.uuid] = layout
            navigationHistories[key] = history
        }
    }

    private func mutateActiveCamera(
        _ body: (inout CameraEngine, inout NavigationHistory, DisplayLayout) -> Void
    ) async {
        let displays = await platform.listDisplays()
        guard let display = displays.first else { return }
        queue.sync {
            let num = activeWorkspaceNumber[display.uuid] ?? 1
            var layout = displayLayouts[display.uuid] ?? DisplayLayout(displayUUID: display.uuid)
            var workspace = layout.workspaces[num] ?? .empty
            workspace.excludedApps.formUnion(globalExcludedApps)
            var engine = CameraEngine(
                workspace: workspace,
                displayRect: display.visibleFrame.asRect,
                gaps: gaps
            )
            let key = historyKey(displayUUID: display.uuid, workspace: num)
            var history = navigationHistories[key] ?? NavigationHistory(current: engine.camera)
            body(&engine, &history, layout)
            layout.workspaces[num] = engine.workspace
            displayLayouts[display.uuid] = layout
            navigationHistories[key] = history
        }
    }

    // MARK: - Tree mutations

    private func insertIfNeeded(_ ref: WindowRef) async {
        if isExcluded(ref) { return }
        let id = ref.asWindowID
        let displayUUID = await displayUUID(containing: ref.frame) ?? primaryDisplayUUID()
        let displays = await platform.listDisplays()
        let displayRect = displays.first(where: { $0.uuid == displayUUID })?.visibleFrame.asRect
            ?? displays.first?.visibleFrame.asRect
            ?? Rect(x: 0, y: 0, width: 1440, height: 900)

        let (cfg, rules) = queue.sync { (config.ruleClassificationConfig, config.rules) }
        let facts = ref.asWindowFacts(
            resizable: true,
            fullscreenButtonEnabled: true,
            closeButtonEnabled: true
        )
        let classification = RuleEngine.classify(facts: facts, rules: rules, config: cfg)

        if classification.ignore {
            queue.sync {
                if let bundle = ref.bundleID {
                    globalExcludedApps.insert(bundle)
                }
            }
            return
        }

        let postCommands = classification.commands
        var dockTarget: DropTarget?
        var tabTarget: WindowID?
        var pendingMin: Size?

        for command in postCommands {
            switch command {
            case .dock(let edge, _):
                dockTarget = .screenEdge(edge)
            case .tabWithFocused:
                tabTarget = queue.sync { focusedWindowID }
            case .tabWithAppId(let appId):
                tabTarget = await findWindow(bundleID: appId)
            case .minSize(let w, let h):
                pendingMin = Size(width: w, height: h)
            default:
                break
            }
        }

        queue.sync {
            guard let uuid = displayUUID else { return }
            var layout = displayLayouts[uuid] ?? DisplayLayout(displayUUID: uuid)
            let num = activeWorkspaceNumber[uuid] ?? 1
            var ws = layout.workspaces[num] ?? .empty
            if ws.contains(id) { return }

            // B1 float-first: default and layout-floating → DesktopArea float at natural frame.
            if classification.floating {
                let natural = Size(width: ref.frame.width, height: ref.frame.height)
                // Desktop tile ≈ content rect when the area is the whole workspace.
                let cfg = ws.layoutConfig
                let screen = ScreenGeometry(visible: displayRect, frame: displayRect)
                let tile: Rect
                if case .desktop = ws.root {
                    let C = screen.contentEdges(cfg: cfg)
                    tile = Rect(x: C.x0, y: C.y0, width: C.width, height: C.height)
                } else if let desk = TreeOps.find(ws.root, target: "desktop"),
                          let solved = LayoutSolver.solve(
                            workspace: ws, displayRect: displayRect
                          ).placements[desk.node.id]?.frame {
                    tile = solved
                } else {
                    let C = screen.contentEdges(cfg: cfg)
                    tile = Rect(x: C.x0, y: C.y0, width: C.width, height: C.height)
                }
                let (next, _) = ws.insertingFloat(id, natural: natural, desktopTile: tile, cfg: cfg)
                ws = next
            } else if let tabTarget, ws.contains(tabTarget) {
                let (inserted, _) = ws.inserting(id, at: .screenEdge(.right))
                ws = inserted
                let (tabbed, _) = ws.tabbing(id, onto: tabTarget)
                ws = tabbed
            } else {
                let target = dockTarget ?? .screenEdge(.left)
                let (next, _) = ws.inserting(id, at: target)
                ws = next
            }
            layout.workspaces[num] = ws
            displayLayouts[uuid] = layout
            if let pendingMin {
                minSizes[id] = pendingMin
            }
        }

        for command in postCommands {
            switch command {
            case .moveWindowToWorkspace(let n):
                await moveWindow(id, toWorkspace: n, follow: false)
            case .dock, .tabWithFocused, .tabWithAppId, .minSize, .layoutFloating, .layoutTiling, .ignore:
                break
            case .other(let raw):
                if let parsed = try? CommandParser.parse(raw) {
                    await execute(parsed, source: .binding)
                }
            }
        }
    }

    private func removeMissing(pidHint: Int32?) async {
        let live = await platform.listWindows()

        queue.sync {
            for (uuid, var layout) in displayLayouts {
                let num = activeWorkspaceNumber[uuid] ?? 1
                var ws = layout.workspaces[num] ?? .empty
                for id in ws.allWindowIDs {
                    if let hint = pidHint, id.processID != hint { continue }
                    if live.contains(where: { id.matches($0) }) { continue }
                    let (next, _) = ws.removing(id)
                    ws = next
                }
                layout.workspaces[num] = ws
                displayLayouts[uuid] = layout
            }
        }
    }

    private func removeAll(pid: Int32) {
        queue.sync {
            for (uuid, var layout) in displayLayouts {
                let num = activeWorkspaceNumber[uuid] ?? 1
                var ws = layout.workspaces[num] ?? .empty
                for id in ws.allWindowIDs where id.processID == pid {
                    let (next, _) = ws.removing(id)
                    ws = next
                }
                layout.workspaces[num] = ws
                displayLayouts[uuid] = layout
            }
        }
    }

    private func suspend(_ ref: WindowRef, state: WindowState) {
        let id = ref.asWindowID
        mutateWorkspaceContaining(id) { ws in
            var next = ws
            if !next.contains(id) {
                let (inserted, _) = next.inserting(id, at: .screenEdge(.right))
                next = inserted
            }
            next.setState(state, for: id)
            return next
        }
    }

    private func suspendMatching(pid: Int32, state: WindowState) {
        queue.sync {
            for (uuid, var layout) in displayLayouts {
                let num = activeWorkspaceNumber[uuid] ?? 1
                var ws = layout.workspaces[num] ?? .empty
                for id in ws.allWindowIDs where id.processID == pid {
                    ws.setState(state, for: id)
                }
                layout.workspaces[num] = ws
                displayLayouts[uuid] = layout
            }
        }
    }

    private func resume(_ ref: WindowRef, to state: WindowState) {
        let id = ref.asWindowID
        mutateWorkspaceContaining(id) { ws in
            var next = ws
            next.setState(state, for: id)
            return next
        }
    }

    private func resumeMatching(pid: Int32) {
        queue.sync {
            for (uuid, var layout) in displayLayouts {
                let num = activeWorkspaceNumber[uuid] ?? 1
                var ws = layout.workspaces[num] ?? .empty
                for id in ws.allWindowIDs where id.processID == pid {
                    ws.setState(.active, for: id)
                }
                layout.workspaces[num] = ws
                displayLayouts[uuid] = layout
            }
        }
    }

    private func mutateWorkspaceContaining(_ id: WindowID, _ body: (Workspace) -> Workspace) {
        queue.sync {
            let preferred = displayLayouts.first(where: {
                let num = activeWorkspaceNumber[$0.key] ?? 1
                return ($0.value.workspaces[num] ?? .empty).contains(id)
            })?.key ?? displayLayouts.keys.sorted().first

            guard let uuid = preferred, var layout = displayLayouts[uuid] else { return }
            let num = activeWorkspaceNumber[uuid] ?? 1
            var ws = layout.workspaces[num] ?? .empty
            ws = body(ws)
            layout.workspaces[num] = ws
            displayLayouts[uuid] = layout
        }
    }

    private func refreshFullscreenSpaceFlag() async {
        if await platform.spacesController.isActiveSpaceFullscreen() {
            setActiveSpaceFullscreen(true)
            return
        }
        let windows = await platform.listWindows()
        let anyFS = windows.contains(where: \.isFullscreen)
        setActiveSpaceFullscreen(anyFS)
    }

    private func activateWorkspace(_ number: Int, followWindow: WindowRef?) async {
        let (binding, previous): ([Int: SpaceID], Int?) = queue.sync {
            let current = activeWorkspaceNumber.values.first
            return (spaceBinding.binding, current)
        }
        guard let space = binding[number] else { return }
        let snaps = await platform.spacesController.spaceDisplaySnapshots()
        let displayUUID = snaps.first(where: { snap in
            snap.spaces.contains(where: { $0.id == space })
        })?.uuid ?? snaps.first?.uuid
        guard let displayUUID else { return }

        await runHooks(config.hooks.workspaceChanging, source: .hook)

        queue.sync {
            if let previous, previous != number {
                previousWorkspaceNumber = previous
            }
            activeWorkspaceNumber[displayUUID] = number
            lastHUDMessage = nil
        }

        _ = await platform.spacesController.switchToSpace(space, on: displayUUID)
        if let followWindow {
            _ = await platform.spacesController.moveWindowIDs([followWindow.id], to: space)
        }
        await reconcile()
        await runHooks(config.hooks.workspaceChanged, source: .hook)
    }

    private func resolveWorkspaceNumber(_ target: WorkspaceTarget) async -> Int? {
        let (count, current): (Int, Int) = queue.sync {
            let cur = activeWorkspaceNumber.values.first ?? 1
            return (config.workspaces, cur)
        }
        switch target {
        case .number(let n):
            return (1...count).contains(n) ? n : nil
        case .next:
            return current >= count ? 1 : current + 1
        case .prev:
            return current <= 1 ? count : current - 1
        }
    }

    private func persistBinding(binding: [Int: SpaceID], owned: Set<SpaceID>) {
        let value = WorkspaceSpaceBinding(binding: binding, ownedSpaces: owned)
        queue.sync { spaceBinding = value }
        platform.spacesController.saveSpaceBinding(value)
    }

    private func syncActiveWorkspaceNumbersFromCurrentSpaces() async {
        let snaps = await platform.spacesController.spaceDisplaySnapshots()
        let binding = queue.sync { spaceBinding.binding }
        queue.sync {
            for snap in snaps {
                if let number = binding.first(where: { $0.value == snap.current })?.key {
                    activeWorkspaceNumber[snap.uuid] = number
                }
            }
        }
    }

    private func focusedDisplayUUID() async -> String? {
        let windows = await platform.listWindows()
        guard let focused = windows.first else {
            return await platform.listDisplays().first?.uuid
        }
        return await displayUUID(containing: focused.frame)
    }

    private func isExcluded(_ ref: WindowRef) -> Bool {
        guard let bundle = ref.bundleID else { return false }
        if globalExcludedApps.contains(bundle) { return true }
        return queue.sync {
            for layout in displayLayouts.values {
                for ws in layout.workspaces.values where ws.excludedApps.contains(bundle) {
                    return true
                }
            }
            return false
        }
    }

    private func displayUUID(containing frame: CGRectCodable) async -> String? {
        let displays = await platform.listDisplays()
        let point = (frame.midX, frame.midY)
        for d in displays {
            let f = d.frame
            if point.0 >= f.minX && point.0 <= f.maxX && point.1 >= f.minY && point.1 <= f.maxY {
                return d.uuid
            }
        }
        return displays.first?.uuid
    }

    private func primaryDisplayUUID() -> String? {
        queue.sync { displayLayouts.keys.sorted().first }
    }

    private func clampOnScreen(_ frame: Rect, within union: Rect) -> Rect {
        guard union.width > 0, union.height > 0 else { return frame }
        var f = frame
        if f.width > union.width { f.width = union.width }
        if f.height > union.height { f.height = union.height }
        if f.maxX > union.maxX { f.x = union.maxX - f.width }
        if f.maxY > union.maxY { f.y = union.maxY - f.height }
        if f.x < union.minX { f.x = union.minX }
        if f.y < union.minY { f.y = union.minY }
        return f
    }

    // MARK: - Persistence / rules helpers

    private func loadPersistedLayouts() async {
        let displays = await platform.listDisplays()
        let live = await platform.listWindows().map(\.asWindowID)
        queue.sync {
            for d in displays {
                if let layout = layoutStore.loadRematched(displayUUID: d.uuid, liveWindows: live) {
                    displayLayouts[d.uuid] = layout
                } else if displayLayouts[d.uuid] == nil {
                    displayLayouts[d.uuid] = DisplayLayout(displayUUID: d.uuid)
                }
            }
        }
    }

    private func persistAllLayouts() {
        let layouts = queue.sync { Array(displayLayouts.values) }
        for layout in layouts {
            layoutStore.scheduleSave(layout)
        }
    }

    private func runHooks(_ commands: [Command], source: ExecAndForget.Source) async {
        for command in commands {
            await execute(command, source: source)
        }
    }

    private func applyEnable(_ state: EnableState) async {
        queue.sync {
            switch state {
            case .on: isEnabled = true
            case .off: isEnabled = false
            case .toggle: isEnabled.toggle()
            }
        }
    }

    private func setMode(_ name: String) async {
        let ok = queue.sync { config.modes[name] != nil }
        guard ok else { return }
        queue.sync { currentMode = name }
        await runHooks(config.hooks.modeChanged, source: .hook)
    }

    private func dockFocused(direction: CommandDirection, screen: Bool) async {
        guard allowLayoutHotkey() else { return }
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        let target: DropTarget = queue.sync {
            if screen {
                return .screenEdge(direction.edge)
            }
            if let other = neighbour(of: id, direction: direction),
               let path = path(to: other) {
                return .edge(nodePath: path, edge: direction.edge)
            }
            return .screenEdge(direction.edge)
        }
        mutateWorkspaceContaining(id) { ws in
            let (next, _) = ws.docking(id, at: target)
            return next
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    private func focusNeighbor(_ direction: CommandDirection) async {
        guard allowLayoutHotkey() else { return }
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        guard let next = queue.sync(execute: { neighbour(of: id, direction: direction) }) else { return }
        queue.sync { focusedWindowID = next }
        if let handler = focusWindowHandler {
            await handler(next)
        }
        publishTabGroups()
        await runHooks(config.hooks.focusChanged, source: .hook)
    }

    private func moveFocused(_ direction: CommandDirection) async {
        guard allowLayoutHotkey() else { return }
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        let target: DropTarget = queue.sync {
            if let other = neighbour(of: id, direction: direction),
               let path = path(to: other) {
                return .edge(nodePath: path, edge: direction.edge)
            }
            return .screenEdge(direction.edge)
        }
        mutateWorkspaceContaining(id) { ws in
            let (next, _) = ws.moving(id, to: target)
            return next
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    private func resizeFocused(axis: ResizeAxis, delta: Int) async {
        guard allowLayoutHotkey() else { return }
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        // Map point delta to a small ratio step (~2% per 10 points).
        let step = Double(delta) / 500.0
        mutateWorkspaceContaining(id) { ws in
            guard let path = ws.root.path(to: id), path.count >= 1 else { return ws }
            let parentPath = Array(path.dropLast())
            let childIndex = path.last!
            guard case .split(let split) = ws.root.node(at: parentPath) else { return ws }

            let axisMatches: Bool
            switch axis {
            case .smart:
                axisMatches = true
            case .width:
                axisMatches = split.axis == .horizontal
            case .height:
                axisMatches = split.axis == .vertical
            }
            guard axisMatches else { return ws }

            let dividerIndex: Int
            if childIndex + 1 < split.children.count {
                dividerIndex = childIndex
            } else if childIndex > 0 {
                dividerIndex = childIndex - 1
            } else {
                return ws
            }
            let signed: Double
            if childIndex + 1 < split.children.count {
                signed = step
            } else {
                signed = -step
            }
            let (next, _) = ws.resizing(path: parentPath, dividerIndex: dividerIndex, delta: signed)
            return next
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    private func balanceSizes() async {
        guard allowLayoutHotkey() else { return }
        queue.sync {
            for (uuid, var layout) in displayLayouts {
                let num = activeWorkspaceNumber[uuid] ?? 1
                let ws = layout.workspaces[num] ?? .empty
                let (next, _) = ws.balancingSizes()
                layout.workspaces[num] = next
                displayLayouts[uuid] = layout
            }
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    private func flattenWorkspaceTree() async {
        guard allowLayoutHotkey() else { return }
        queue.sync {
            for (uuid, var layout) in displayLayouts {
                let num = activeWorkspaceNumber[uuid] ?? 1
                let ws = layout.workspaces[num] ?? .empty
                let (next, _) = ws.flatteningTree()
                layout.workspaces[num] = next
                displayLayouts[uuid] = layout
            }
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    private func path(to id: WindowID) -> NodePath? {
        for layout in displayLayouts.values {
            for ws in layout.workspaces.values {
                if let path = ws.root.path(to: id) { return path }
            }
        }
        return nil
    }

    private func tabWith(_ target: TabTarget) async {
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        let onto: WindowID?
        switch target {
        case .focused:
            onto = nil // no-op without a second window
        case .appId(let appId):
            onto = await findWindow(bundleID: appId)
        case .direction(let dir):
            onto = queue.sync {
                neighbour(of: id, direction: dir)
            }
        case .next, .prev:
            onto = nil
        }
        guard let onto, onto != id else { return }
        mutateWorkspaceContaining(id) { ws in
            let (next, _) = ws.tabbing(id, onto: onto)
            return next
        }
        await applySolvedFrames(animated: true, useCamera: true)
        publishTabGroups()
    }

    private func untabFocused() async {
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        mutateWorkspaceContaining(id) { ws in
            let (next, _) = ws.untabbing(id)
            return next
        }
        await applySolvedFrames(animated: true, useCamera: true)
        publishTabGroups()
    }

    private func tabNavigate(_ target: TabTarget) async {
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        mutateWorkspaceContaining(id) { ws in
            var next = ws
            guard let path = next.root.path(to: id),
                  var node = next.root.node(at: path),
                  case .tabs(var tabs) = node else { return ws }
            switch target {
            case .next:
                tabs.selectedIndex = (tabs.selectedIndex + 1) % max(tabs.windows.count, 1)
            case .prev:
                tabs.selectedIndex = (tabs.selectedIndex - 1 + tabs.windows.count) % max(tabs.windows.count, 1)
            default:
                return ws
            }
            node = .tabs(tabs)
            if let updated = next.root.replacing(at: path, with: node) {
                next.root = updated
            }
            return next
        }
        await applySolvedFrames()
        publishTabGroups()
    }

    private func setMinSizeForFocused(width: Double, height: Double) async {
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        queue.sync { minSizes[id] = Size(width: width, height: height) }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    private func ignoreFocused() async {
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        if let bundle = id.bundleID {
            queue.sync { globalExcludedApps.insert(bundle) }
        }
        mutateWorkspaceContaining(id) { ws in
            let (next, _) = ws.removing(id)
            return next
        }
        await applySolvedFrames()
    }

    private func setFocusedFloating(_ floating: Bool) async {
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        if floating {
            let frame = queue.sync { lastFrames[id] } ?? Rect(x: 100, y: 100, width: 640, height: 480)
            mutateWorkspaceContaining(id) { ws in
                let (next, _) = ws.floating(id, frame: frame)
                return next
            }
        } else {
            mutateWorkspaceContaining(id) { ws in
                let (next, _) = ws.docking(id, at: .screenEdge(.right))
                return next
            }
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    private func joinFocused(with direction: CommandDirection) async {
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        guard let other = queue.sync(execute: { neighbour(of: id, direction: direction) }) else { return }
        mutateWorkspaceContaining(id) { ws in
            // join-with: make a split container with the neighbour via docking beside it.
            let (next, _) = ws.moving(
                id,
                to: .edge(nodePath: ws.root.path(to: other) ?? [], edge: direction.edge)
            )
            return next
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    private func splitFocused(axis: Axis) async {
        guard allowLayoutHotkey() else { return }
        guard let id = queue.sync(execute: { focusedWindowID }) else { return }
        mutateWorkspaceContaining(id) { ws in
            let (next, _) = ws.splitting(id, axis: axis)
            return next
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    private func findWindow(bundleID: String) async -> WindowID? {
        let windows = await platform.listWindows()
        return windows.first { $0.bundleID == bundleID }?.asWindowID
    }

    private func neighbour(of id: WindowID, direction: CommandDirection) -> WindowID? {
        for layout in displayLayouts.values {
            for ws in layout.workspaces.values {
                guard let path = ws.root.path(to: id) else { continue }
                // Prefer sibling in the same split along the requested edge; skip desktop/empty.
                if path.count >= 1 {
                    let parentPath = Array(path.dropLast())
                    let index = path.last!
                    if case .split(let split) = ws.root.node(at: parentPath) {
                        let delta: Int
                        switch (split.axis, direction) {
                        case (.horizontal, .left), (.vertical, .up): delta = -1
                        case (.horizontal, .right), (.vertical, .down): delta = 1
                        default: delta = 0
                        }
                        if delta != 0 {
                            var ni = index + delta
                            while split.children.indices.contains(ni) {
                                if let hit = split.children[ni].tiledWindowIDs.first {
                                    return hit
                                }
                                ni += delta
                            }
                        }
                    }
                }
                // Geometric fallback: next tiled window in DFS order.
                let tiled = ws.root.tiledWindowIDs
                if let idx = tiled.firstIndex(where: { $0 == id }) {
                    if direction == .right || direction == .down {
                        if idx + 1 < tiled.count { return tiled[idx + 1] }
                    } else if idx > 0 {
                        return tiled[idx - 1]
                    }
                }
                return tiled.first { $0 != id }
            }
        }
        return nil
    }

    private func moveWindow(_ id: WindowID, toWorkspace number: Int, follow: Bool) async {
        // Cross-workspace move: remove from current, insert into target workspace on same display.
        var moved = false
        queue.sync {
            for (uuid, var layout) in displayLayouts {
                let num = activeWorkspaceNumber[uuid] ?? 1
                var ws = layout.workspaces[num] ?? .empty
                guard ws.contains(id) else { continue }
                let (removed, _) = ws.removing(id)
                layout.workspaces[num] = removed
                var dest = layout.workspaces[number] ?? .empty
                let (inserted, _) = dest.inserting(id, at: .screenEdge(.right))
                layout.workspaces[number] = inserted
                displayLayouts[uuid] = layout
                if follow {
                    activeWorkspaceNumber[uuid] = number
                }
                moved = true
                break
            }
        }
        if moved {
            await applySolvedFrames()
        }
    }

    private func publishTabGroups() {
        let snapshots: [TabGroupSnapshot] = queue.sync {
            var result: [TabGroupSnapshot] = []
            for (uuid, layout) in displayLayouts {
                let num = activeWorkspaceNumber[uuid] ?? 1
                let ws = layout.workspaces[num] ?? .empty
                for path in ws.root.allPaths() {
                    guard case .tabs(let tabs) = ws.root.node(at: path) else { continue }
                    let frame = lastFrames[tabs.selectedWindow ?? tabs.windows.first ?? WindowID.stub(0)]
                    result.append(TabGroupSnapshot(
                        displayUUID: uuid,
                        path: path,
                        titles: tabs.windows.map(\.titleFingerprint),
                        selectedIndex: tabs.selectedIndex,
                        frame: frame
                    ))
                }
            }
            return result
        }
        onTabGroupsChanged?(snapshots)
    }

    /// Drive FFM from a pointer hit-test key (`bundleID#title` or similar).
    public func focusFollowsMousePointer(over windowKey: String?, bundleID: String?) -> FocusFollowsMouseMachine.Action {
        queue.sync {
            if focusFollowsMouse.isExcluded(bundleID: bundleID) {
                return focusFollowsMouse.notePointer(over: nil)
            }
            return focusFollowsMouse.notePointer(over: windowKey)
        }
    }

    public func focusFollowsMouseTimerFired(for windowKey: String) -> FocusFollowsMouseMachine.Action {
        queue.sync { focusFollowsMouse.noteTimerFired(for: windowKey) }
    }

    // MARK: - Input gestures (B3–B5, B9, B14, B15)

    /// Green button: docked → float; floating → dock (P5a-gated by caller).
    public func handleGreenButton(for ref: WindowRef) async {
        guard allowLayoutHotkey() else { return }
        let id = ref.asWindowID
        let floating = queue.sync {
            displayLayouts.values.contains { layout in
                layout.workspaces.values.contains { $0.isFloating(id) }
            }
        }
        if floating {
            mutateWorkspaceContaining(id) { ws in
                let (next, _) = ws.docking(id, at: .screenEdge(.left))
                return next
            }
        } else {
            let frame = ref.frame.asRect
            mutateWorkspaceContaining(id) { ws in
                let (next, _) = ws.floating(id, frame: frame)
                return next
            }
        }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    /// Double-click desktop / title via `[mouse]` commands (ADDENDUM A1 / B14).
    public func handleDoubleClick(kind: DoubleClickKind) async {
        let action: MouseDoubleClickAction = queue.sync {
            switch kind {
            case .desktop: return config.mouse.doubleClickDesktop
            case .title: return config.mouse.doubleClickTitle
            }
        }
        guard case .commands(let commands) = action else { return }
        for command in commands {
            await execute(command, source: .binding)
        }
    }

    public enum DoubleClickKind: Sendable {
        case desktop
        case title
    }

    /// Begin title-bar drag (live make-room). Esc cancels via `cancelDrag()`.
    public func beginDrag(window: WindowID, at point: Point, isTabStrip: Bool = false) {
        let frame = queue.sync { lastFrames[window] } ?? Rect.zero
        queue.sync {
            activeDrag = DragSession(
                window: window,
                originFrame: frame,
                currentPoint: point,
                isTabStripDrag: isTabStrip
            )
        }
    }

    public func updateDrag(to point: Point, proposed: DropTarget?) async {
        var shouldPreview = false
        queue.sync {
            guard var drag = activeDrag else { return }
            drag.currentPoint = point
            if case .center = proposed {
                if drag.centerHoldStarted == nil {
                    drag.centerHoldStarted = Date()
                } else if let start = drag.centerHoldStarted,
                          Date().timeIntervalSince(start) >= DragSession.tabHoldSeconds {
                    drag.previewTarget = proposed
                    shouldPreview = true
                }
            } else {
                drag.centerHoldStarted = nil
                drag.previewTarget = proposed
                shouldPreview = proposed != nil
            }
            activeDrag = drag
        }
        if shouldPreview {
            // Live make-room: re-solve with a ghost insert for stills (AX only on commit).
            await applySolvedFrames(animated: true, useCamera: true)
        }
    }

    public func commitDrag() async {
        let session = queue.sync { () -> DragSession? in
            let s = activeDrag
            activeDrag = nil
            return s
        }
        guard let session else { return }
        guard let target = session.previewTarget else {
            // Cancel / elsewhere → restore (no tree change).
            await applySolvedFrames(animated: true, useCamera: true)
            return
        }
        if case .center(let nodeID) = target {
            mutateWorkspaceContaining(session.window) { ws in
                // Tab onto the node under the pointer.
                if let win = ws.root.tiledWindowIDs.first(where: { $0.nodeID == nodeID })
                    ?? ws.root.tiledWindowIDs.first {
                    let (next, _) = ws.tabbing(session.window, onto: win)
                    return next
                }
                return ws
            }
        } else {
            mutateWorkspaceContaining(session.window) { ws in
                let (next, _) = ws.moving(session.window, to: target)
                return next
            }
        }
        await applySolvedFrames(animated: true, useCamera: true)
        publishTabGroups()
    }

    public func cancelDrag() async {
        queue.sync { activeDrag = nil }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    /// Continuous pinch (B9). Call `endPinch` on release to settle.
    public func updatePinch(factor: Double, about point: Point) async {
        queue.sync { pinchActive = true }
        await mutateActiveCamera { engine, history in
            engine.pinchScale(factor: factor, aboutScreenPoint: point)
            history.replaceCurrent(with: engine.camera)
        }
        // Stills only during pinch — skip AX until settle.
    }

    public func endPinch(about point: Point) async {
        await mutateActiveCamera { engine, history in
            engine.settlePinch(aboutScreenPoint: point)
            history.navigate(to: engine.camera)
        }
        queue.sync { pinchActive = false }
        await applySolvedFrames(animated: true, useCamera: true)
    }

    /// Tear a tab out of its group (B5).
    public func tearOffTab(_ window: WindowID) async {
        mutateWorkspaceContaining(window) { ws in
            let (next, _) = ws.untabbing(window)
            return next
        }
        await applySolvedFrames(animated: true, useCamera: true)
        publishTabGroups()
    }

    /// Activate a tab in its group.
    public func selectTab(_ window: WindowID) async {
        mutateWorkspaceContaining(window) { ws in
            var next = ws
            guard let loc = TreeOps.find(next.root, target: window.nodeID),
                  case .tabs(var tabs) = loc.parent,
                  let idx = tabs.members.firstIndex(where: { $0.id == window.nodeID }) else {
                return ws
            }
            tabs.active = idx
            next.root = TreeOps.replace(next.root, oldID: tabs.id, with: .tabs(tabs))
            return next
        }
        await applySolvedFrames(animated: false, useCamera: true)
        publishTabGroups()
    }
}

/// Snapshot of a tab group for the tab-strip overlay.
public struct TabGroupSnapshot: Sendable, Equatable {
    public var displayUUID: String
    public var path: NodePath
    public var titles: [String]
    public var selectedIndex: Int
    public var frame: Rect?

    public init(
        displayUUID: String,
        path: NodePath,
        titles: [String],
        selectedIndex: Int,
        frame: Rect? = nil
    ) {
        self.displayUUID = displayUUID
        self.path = path
        self.titles = titles
        self.selectedIndex = selectedIndex
        self.frame = frame
    }
}
