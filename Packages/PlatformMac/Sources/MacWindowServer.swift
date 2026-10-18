import AppKit
import ApplicationServices
import Config
import Foundation
import Platform

/// Concrete `WindowServerProtocol` for the menu-bar app (App wires this; AppCore never imports it).
public final class MacWindowServer: WindowServerProtocol, @unchecked Sendable {
    public var experimentalFlags: ExperimentalFlags {
        didSet { syncExperimentalSessions() }
    }
    public let permissions: MacPermissions
    public let spacesController: any SpacesControlling
    public let frameAnimator: any FrameAnimating
    public let multitouchSession: ExperimentalMultitouchSession

    private let writer: MacWindowWriter
    private let workspaceObservers = MacWorkspaceObservers()
    private var eventHandler: PlatformEventHandler?
    private var axObservers: [Int32: AXObserver] = [:]
    private let stateQueue = DispatchQueue(label: "com.designbyadrian.lattice.window-server")

    public init(
        experimentalFlags: ExperimentalFlags = .default,
        permissions: MacPermissions = MacPermissions(),
        writer: MacWindowWriter = .shared,
        spacesController: MacSpacesController? = nil,
        multitouchSession: ExperimentalMultitouchSession = ExperimentalMultitouchSession()
    ) {
        self.experimentalFlags = experimentalFlags
        self.permissions = permissions
        self.writer = writer
        self.multitouchSession = multitouchSession
        self.spacesController = spacesController ?? MacSpacesController()
        let animator = DisplayLinkAnimator { [writer] target in
            try await writer.setFrame(target.frame, for: target.windowID, pid: target.pid)
        }
        self.frameAnimator = animator
        syncExperimentalSessions()
    }

    /// Applies config-derived flags and re-syncs experimental sessions (may auto-disable).
    public func applyExperimentalConfig(_ config: ExperimentalConfig) {
        experimentalFlags = ExperimentalFlags(
            axWindowID: config.axWindowID,
            multitouch: config.multitouch
        )
    }

    private func syncExperimentalSessions() {
        var flags = experimentalFlags
        multitouchSession.sync(flags: &flags)
        if flags != experimentalFlags {
            experimentalFlags = flags
        }
    }

    public var accessibilityReduceMotion: Bool {
        ReduceMotion.isEnabled
    }

    public var macSpaces: MacSpacesController? {
        spacesController as? MacSpacesController
    }

    public func listWindows() async -> [Platform.WindowRef] {
        var flags = experimentalFlags
        let refs = MacWindowDiscovery.listManagedWindows(experimentalFlags: &flags)
        if flags != experimentalFlags {
            experimentalFlags = flags
        }
        return refs
    }

    public func listDisplays() async -> [DisplayRef] {
        MacDisplays.listDisplays()
    }

    public func setFrame(_ frame: CGRectCodable, for windowID: UInt32, pid: Int32) async throws {
        try await writer.setFrame(frame, for: windowID, pid: pid)
    }

    public func startObserving(_ handler: @escaping PlatformEventHandler) {
        stateQueue.sync { eventHandler = handler }

        workspaceObservers.start { [weak self] event in
            self?.forward(event)
            self?.handleWorkspaceSideEffect(event)
        }

        // Attach AX observers for currently running apps (best-effort).
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            attachAXObserver(pid: app.processIdentifier)
        }
    }

    public func stopObserving() {
        workspaceObservers.stop()
        stateQueue.sync {
            eventHandler = nil
            axObservers.removeAll()
        }
    }

    // MARK: - Internals

    private func forward(_ event: PlatformEvent) {
        let h = stateQueue.sync { eventHandler }
        h?(event)
    }

    private func handleWorkspaceSideEffect(_ event: PlatformEvent) {
        switch event {
        case .applicationLaunched(let pid, _):
            attachAXObserver(pid: pid)
        case .applicationTerminated(let pid):
            stateQueue.sync { _ = axObservers.removeValue(forKey: pid) }
        case .screenParametersChanged, .didWake, .activeSpaceDidChange:
            // AppCore re-lists displays / re-checks fullscreen on these.
            break
        default:
            break
        }
    }

    private func attachAXObserver(pid: Int32) {
        guard pid > 0, permissions.isAccessibilityTrusted else { return }

        let alreadyAttached = stateQueue.sync { axObservers[pid] != nil }
        if alreadyAttached { return }

        var observer: AXObserver?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let server = Unmanaged<MacWindowServer>.fromOpaque(refcon).takeUnretainedValue()
            server.handleAXNotification(element: element, notification: notification as String)
        }

        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, MacWindowDiscovery.axMessagingTimeout)

        let notifications: [CFString] = [
            kAXCreatedNotification as CFString,
            kAXUIElementDestroyedNotification as CFString,
            kAXMovedNotification as CFString,
            kAXResizedNotification as CFString,
            kAXWindowMiniaturizedNotification as CFString,
            kAXWindowDeminiaturizedNotification as CFString,
            kAXFocusedWindowChangedNotification as CFString,
            kAXTitleChangedNotification as CFString,
        ]

        for name in notifications {
            AXObserverAddNotification(observer, app, name, selfPtr)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        stateQueue.sync { axObservers[pid] = observer }
    }

    private func handleAXNotification(element: AXUIElement, notification: String) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        // Compare against public AX notification name strings.
        switch notification {
        case "AXCreated":
            if let snap = MacWindowDiscovery.snapshot(window: element, pid: pid),
               WindowDiscoveryFilter.isManageableAXWindow(snap) {
                // Re-discover to obtain CGWindowID via public matching.
                Task {
                    let windows = await listWindows()
                    if let match = windows.first(where: {
                        $0.pid == pid && $0.title == snap.title
                            && $0.frame.isApproximatelyEqual(to: snap.frame)
                    }) {
                        self.forward(.windowCreated(match))
                    }
                }
            }
        case "AXUIElementDestroyed":
            // Without a stable id on destroy, AppCore reconciles via listWindows.
            forward(.windowDestroyed(id: 0, pid: pid))
        case "AXWindowMiniaturized":
            forward(.windowMinimized(id: 0, pid: pid))
        case "AXWindowDeminiaturized":
            if let snap = MacWindowDiscovery.snapshot(window: element, pid: pid) {
                let ref = Platform.WindowRef(
                    id: 0,
                    pid: pid,
                    title: snap.title,
                    frame: snap.frame,
                    isMinimized: false,
                    isFullscreen: snap.isFullscreen,
                    subrole: snap.subrole
                )
                forward(.windowDeminimized(ref))
            }
        case "AXMoved":
            emitMovedOrResized(element: element, pid: pid, resized: false)
        case "AXResized":
            emitMovedOrResized(element: element, pid: pid, resized: true)
        case "AXTitleChanged":
            if let snap = MacWindowDiscovery.snapshot(window: element, pid: pid) {
                forward(.windowTitleChanged(Platform.WindowRef(
                    id: 0, pid: pid, title: snap.title, frame: snap.frame,
                    isFullscreen: snap.isFullscreen, subrole: snap.subrole
                )))
            }
        case "AXFocusedWindowChanged":
            if let snap = MacWindowDiscovery.snapshot(window: element, pid: pid) {
                forward(.windowFocused(Platform.WindowRef(
                    id: 0, pid: pid, title: snap.title, frame: snap.frame,
                    isFullscreen: snap.isFullscreen, subrole: snap.subrole
                )))
            }
        default:
            // Re-check AXFullScreen on generic notifications.
            if let snap = MacWindowDiscovery.snapshot(window: element, pid: pid) {
                let ref = Platform.WindowRef(
                    id: 0, pid: pid, title: snap.title, frame: snap.frame,
                    isFullscreen: snap.isFullscreen, subrole: snap.subrole
                )
                forward(.windowFullscreenChanged(ref, isFullscreen: snap.isFullscreen))
            }
        }
    }

    private func emitMovedOrResized(element: AXUIElement, pid: pid_t, resized: Bool) {
        guard let snap = MacWindowDiscovery.snapshot(window: element, pid: pid) else { return }
        let ref = Platform.WindowRef(
            id: 0,
            pid: pid,
            title: snap.title,
            frame: snap.frame,
            isMinimized: snap.isMinimized,
            isFullscreen: snap.isFullscreen,
            subrole: snap.subrole
        )
        if resized {
            forward(.windowResized(ref))
        } else {
            forward(.windowMoved(ref))
        }
        // Full-screen often surfaces as a resize.
        forward(.windowFullscreenChanged(ref, isFullscreen: snap.isFullscreen))
    }
}
