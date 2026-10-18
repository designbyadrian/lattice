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

    /// Stub until P6 Space-type detection: when true, layout hotkeys are no-ops.
    public private(set) var isActiveSpaceFullscreen: Bool = false

    /// Last solved frames (for safe quit / debugging).
    public private(set) var lastFrames: [WindowID: Rect] = [:]

    private let queue = DispatchQueue(label: "com.designbyadrian.lattice.app-coordinator")
    private var started = false

    public init(platform: any WindowServerProtocol, config: LatticeConfig = .default) {
        self.platform = platform
        self.config = config
    }

    public func reloadConfig(_ config: LatticeConfig) {
        queue.sync { self.config = config }
    }

    // MARK: - Lifecycle

    public func start() async {
        let already: Bool = queue.sync {
            if started { return true }
            started = true
            return false
        }
        guard !already else { return }

        platform.startObserving { [weak self] event in
            Task { await self?.handle(event) }
        }
        await reconcile()
    }

    public func stop() {
        platform.stopObserving()
        queue.sync { started = false }
    }

    /// Mark / clear the fullscreen-space stub (P6 replaces with Space type query).
    public func setActiveSpaceFullscreen(_ value: Bool) {
        queue.sync { isActiveSpaceFullscreen = value }
    }

    /// Layout / tile hotkeys should call this; returns `false` when ignored.
    public func allowLayoutHotkey() -> Bool {
        queue.sync { !isActiveSpaceFullscreen }
    }

    // MARK: - Public commands

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
        let displays = await platform.listDisplays()
        let union = displays.map(\.visibleFrame.asRect).reduce(Rect.zero) { acc, r in
            if acc.width == 0 && acc.height == 0 { return r }
            let minX = min(acc.minX, r.minX)
            let minY = min(acc.minY, r.minY)
            let maxX = max(acc.maxX, r.maxX)
            let maxY = max(acc.maxY, r.maxY)
            return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        let frames = queue.sync { lastFrames }

        for (id, frame) in frames {
            guard let cgID = id.cgWindowID else { continue }
            let clamped = clampOnScreen(frame, within: union)
            try? await platform.setFrame(clamped.asCGRectCodable, for: cgID, pid: id.processID)
        }
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
                await refreshFullscreenSpaceStub()
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
            await refreshFullscreenSpaceStub()
        default:
            break
        }
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
        let displays = await platform.listDisplays()
        var allFrames: [WindowID: Rect] = [:]

        for display in displays {
            let (workspace, gapsCopy): (Workspace, Gaps) = queue.sync {
                let num = activeWorkspaceNumber[display.uuid] ?? 1
                let layout = displayLayouts[display.uuid] ?? DisplayLayout(displayUUID: display.uuid)
                var workspace = layout.workspaces[num] ?? .empty
                workspace.excludedApps.formUnion(globalExcludedApps)
                return (workspace, gaps)
            }

            let result = LayoutEngine.solve(
                workspace: workspace,
                displayRect: display.visibleFrame.asRect,
                gaps: gapsCopy
            )

            for (id, rect) in result {
                allFrames[id] = rect
                guard let cgID = id.cgWindowID, cgID != 0 else { continue }
                if workspace.state(of: id).isSuspended { continue }
                try? await platform.setFrame(rect.asCGRectCodable, for: cgID, pid: id.processID)
            }
        }

        queue.sync { lastFrames = allFrames }
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

    private func refreshFullscreenSpaceStub() async {
        let windows = await platform.listWindows()
        let anyFS = windows.contains(where: \.isFullscreen)
        setActiveSpaceFullscreen(anyFS)
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
