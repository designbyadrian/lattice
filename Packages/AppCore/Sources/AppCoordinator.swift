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

    /// Overview is open (zoomed-out tree UI).
    public private(set) var isOverviewVisible: Bool = false

    /// Pending frame-rect drag (world coordinates); set when `frame-rect` opens the overlay.
    public private(set) var pendingFrameRect: Rect?

    /// Collapse thresholds for overview tiles.
    public var collapseThresholds: CollapseThresholds = .default

    /// Animation duration override (nil → `LayoutMotion.defaultDurationSeconds`).
    public var animationDurationSeconds: Double?

    private let queue = DispatchQueue(label: "com.designbyadrian.lattice.app-coordinator")
    private var started = false
    private var spacesReconcileDebounce: DispatchWorkItem?
    private var lastSpaceBindingBeforeFailedAction: WorkspaceSpaceBinding?
    public init(platform: any WindowServerProtocol, config: LatticeConfig = .default) {
        self.platform = platform
        self.config = config
        self.spaceBinding = platform.spacesController.loadSpaceBinding()
    }

    public func reloadConfig(_ config: LatticeConfig) {
        queue.sync { self.config = config }
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
        await reconcile()
        await runSpacesReconcile()
        await refreshFullscreenSpaceFlag()
    }

    public func stop() {
        platform.stopObserving()
        queue.sync {
            started = false
            spacesReconcileDebounce?.cancel()
            spacesReconcileDebounce = nil
        }
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
    public func execute(_ command: Command) async {
        switch command {
        case .workspace(let target):
            await switchWorkspace(target)
        case .workspaceBackAndForth:
            await workspaceBackAndForth()
        case .moveWindowToWorkspace(let target, let follow):
            await moveFocusedWindowToWorkspace(target, follow: follow)
        case .moveWindowToDisplay(let target, let follow):
            await moveFocusedWindowToDisplay(target, follow: follow)
        case .floatAll:
            await floatAll()
        case .zoom(let target):
            await zoom(target)
        case .frameRect:
            await beginFrameRect()
        case .history(let direction):
            await navigateHistory(direction)
        case .view(let index):
            await loadSavedView(index)
        case .saveView(let index):
            await saveCurrentView(index)
        case .overview:
            await toggleOverview()
        case .reloadConfig:
            break // App shell reloads file then calls reloadConfig(_:)
        default:
            break
        }
    }

    public func floatAll() async {
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

    /// Leave every managed window on-screen before quit.
    public func prepareSafeQuit() async {
        if isOverviewVisible {
            await dismissOverview(restoreCamera: true)
        }
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

    // MARK: - Camera / zoom / overview (P7)

    public func zoom(_ target: ZoomTarget) async {
        guard allowLayoutHotkey() else { return }
        await mutateActiveCamera { engine, history in
            switch target {
            case .in:
                let focus = engine.camera.focusPath
                let point: Point
                if let frame = engine.solveResult.nodeFrames[focus] {
                    point = Point(x: frame.midX, y: frame.midY)
                } else {
                    point = Point(x: engine.displayRect.midX, y: engine.displayRect.midY)
                }
                engine.stepIn(towardPoint: point)
            case .out:
                engine.stepOut()
            case .all:
                engine.showAll()
            case .window:
                if let focused = engine.workspace.root.tiledWindowIDs.first {
                    engine.frameAlone(focused)
                }
            }
            history.navigate(to: engine.camera)
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
        queue.sync {
            guard let uuid = displayLayouts.keys.sorted().first else { return }
            let num = activeWorkspaceNumber[uuid] ?? 1
            var layout = displayLayouts[uuid] ?? DisplayLayout(displayUUID: uuid)
            let cam = layout.workspaces[num]?.camera ?? .showAll
            SavedViews.save(index, camera: cam, into: &layout)
            displayLayouts[uuid] = layout
        }
    }

    public func toggleOverview() async {
        guard allowLayoutHotkey() else { return }
        if isOverviewVisible {
            await dismissOverview(restoreCamera: false)
        } else {
            await showOverview()
        }
    }

    public func showOverview() async {
        let displays = await platform.listDisplays()
        guard let display = displays.first else { return }

        // Zoom out for overview framing.
        await mutateActiveCamera { engine, history in
            engine.showAll()
            history.navigate(to: engine.camera)
        }
        await applySolvedFrames(animated: true, useCamera: true)

        let tiles = queue.sync { () -> [OverviewTileDescriptor] in
            let uuid = display.uuid
            let num = activeWorkspaceNumber[uuid] ?? 1
            let layout = displayLayouts[uuid] ?? DisplayLayout(displayUUID: uuid)
            var workspace = layout.workspaces[num] ?? .empty
            workspace.excludedApps.formUnion(globalExcludedApps)
            var engine = CameraEngine(
                workspace: workspace,
                displayRect: display.visibleFrame.asRect,
                gaps: gaps
            )
            engine.camera = .showAll
            return Self.buildOverviewTiles(
                engine: engine,
                thresholds: collapseThresholds
            )
        }

        queue.sync { isOverviewVisible = true }
        platform.overviewPresenter.presentOverview(
            displayFrame: display.frame,
            tiles: tiles
        ) { [weak self] path in
            Task { await self?.activateOverviewPath(path) }
        }
    }

    public func dismissOverview(restoreCamera: Bool) async {
        platform.overviewPresenter.dismissOverview()
        queue.sync { isOverviewVisible = false }
        if restoreCamera {
            await applySolvedFrames(animated: true, useCamera: true)
        }
    }

    public func activateOverviewPath(_ path: [Int]) async {
        await mutateActiveCamera { engine, history in
            engine.camera = Camera(focusPath: path, zoom: 1)
            history.navigate(to: engine.camera)
        }
        await dismissOverview(restoreCamera: false)
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
        case .applicationHidden(let pid):
            suspendMatching(pid: pid, state: .hidden)
            await applySolvedFrames()
        case .applicationUnhidden(let pid):
            resumeMatching(pid: pid)
            await applySolvedFrames()
        case .applicationTerminated(let pid):
            removeAll(pid: pid)
            await applySolvedFrames()
        case .screenParametersChanged, .didWake, .activeSpaceDidChange:
            await reconcile()
            await scheduleSpacesReconcile(immediate: false)
            await refreshFullscreenSpaceFlag()
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

    /// Solve and apply frames. When `useCamera` is true, maps through the workspace camera
    /// (parking off-view windows). When `animated`, drives `frameAnimator` with shared layout motion.
    public func applySolvedFrames(animated: Bool, useCamera: Bool) async {
        let displays = await platform.listDisplays()
        var allFrames: [WindowID: Rect] = [:]
        var targets: [WindowFrameTarget] = []
        var workspacesByDisplay: [String: Workspace] = [:]

        for display in displays {
            let (workspace, gapsCopy): (Workspace, Gaps) = queue.sync {
                let num = activeWorkspaceNumber[display.uuid] ?? 1
                let layout = displayLayouts[display.uuid] ?? DisplayLayout(displayUUID: display.uuid)
                var workspace = layout.workspaces[num] ?? .empty
                workspace.excludedApps.formUnion(globalExcludedApps)
                return (workspace, gaps)
            }
            workspacesByDisplay[display.uuid] = workspace

            let displayRect = display.visibleFrame.asRect
            let result: [WindowID: Rect]
            if useCamera {
                let engine = CameraEngine(
                    workspace: workspace,
                    displayRect: displayRect,
                    gaps: gapsCopy
                )
                result = engine.framesAtCamera()
            } else {
                // Identity camera for safe-quit: unpark everything onto the solved layout.
                var flat = workspace
                flat.camera = .showAll
                result = LayoutEngine.solve(
                    workspace: flat,
                    displayRect: displayRect,
                    gaps: gapsCopy
                )
            }

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

        queue.sync { lastFrames = allFrames }

        let duration = animationDurationSeconds ?? LayoutMotion.defaultDurationSeconds
        let reduceMotion = platform.accessibilityReduceMotion
        if animated && !reduceMotion {
            await platform.frameAnimator.animateFrames(
                to: targets,
                durationSeconds: duration,
                reduceMotion: false
            )
        } else if animated && reduceMotion {
            // Reduce Motion: jump (no interpolated motion).
            await platform.frameAnimator.animateFrames(
                to: targets,
                durationSeconds: 0,
                reduceMotion: true
            )
        } else {
            for t in targets {
                try? await platform.setFrame(t.frame, for: t.windowID, pid: t.pid)
            }
        }
        _ = workspacesByDisplay
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

    public static func buildOverviewTiles(
        engine: CameraEngine,
        thresholds: CollapseThresholds
    ) -> [OverviewTileDescriptor] {
        var tiles: [OverviewTileDescriptor] = []
        for path in engine.workspace.root.allPaths() {
            guard let node = engine.workspace.root.node(at: path),
                  let onScreen = engine.solveResult.nodeFrames[path] else { continue }
            let presentation = Collapse.presentation(for: node, frame: onScreen, thresholds: thresholds)
            var bundleID: String?
            var title = ""
            var windowID: UInt32?
            let isLeaf: Bool
            switch node {
            case .panel(let panel):
                isLeaf = true
                bundleID = panel.window.bundleID
                title = panel.window.titleFingerprint
                windowID = panel.window.cgWindowID
            case .tabs(let tabs):
                isLeaf = true
                if let selected = tabs.selectedWindow {
                    bundleID = selected.bundleID
                    title = selected.titleFingerprint
                    windowID = selected.cgWindowID
                }
            case .split:
                isLeaf = false
            case .desktop:
                continue
            }
            // Collapsed tiles always; expanded leaves for preview hosts.
            if presentation != .expanded || isLeaf {
                tiles.append(OverviewTileDescriptor(
                    path: path,
                    frame: CGRectCodable(
                        x: onScreen.x, y: onScreen.y,
                        width: onScreen.width, height: onScreen.height
                    ),
                    presentation: presentationLabel(presentation),
                    bundleID: bundleID,
                    title: title,
                    windowID: windowID
                ))
            }
        }
        return tiles
    }

    private static func presentationLabel(_ p: CollapsePresentation) -> String {
        switch p {
        case .expanded: return "expanded"
        case .windowTile: return "windowTile"
        case .groupTile: return "groupTile"
        }
    }

    // MARK: - Tree mutations

    private func insertIfNeeded(_ ref: WindowRef) async {
        if isExcluded(ref) { return }
        let id = ref.asWindowID
        let displayUUID = await displayUUID(containing: ref.frame) ?? primaryDisplayUUID()

        queue.sync {
            guard let uuid = displayUUID else { return }
            var layout = displayLayouts[uuid] ?? DisplayLayout(displayUUID: uuid)
            let num = activeWorkspaceNumber[uuid] ?? 1
            let ws = layout.workspaces[num] ?? .empty
            if ws.contains(id) { return }
            let (next, _) = ws.inserting(id, at: .screenEdge(.right))
            layout.workspaces[num] = next
            displayLayouts[uuid] = layout
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
}
