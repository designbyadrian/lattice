import AppKit
import Foundation
import Platform

/// NSWorkspace / screen / wake observers. Structure only — forwards `PlatformEvent`s.
public final class MacWorkspaceObservers: @unchecked Sendable {
    private var handler: PlatformEventHandler?
    private var tokens: [NSObjectProtocol] = []
    private let stateQueue = DispatchQueue(label: "com.designbyadrian.lattice.workspace-observers")

    public init() {}

    deinit {
        stop()
    }

    public func start(_ handler: @escaping PlatformEventHandler) {
        stop()
        stateQueue.sync { self.handler = handler }

        let center = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        var fresh: [NSObjectProtocol] = []

        fresh.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.emit(.applicationLaunched(pid: app?.processIdentifier ?? 0, bundleID: app?.bundleIdentifier))
        })

        fresh.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.emit(.applicationTerminated(pid: app?.processIdentifier ?? 0))
        })

        fresh.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.emit(.applicationActivated(pid: app?.processIdentifier ?? 0))
        })

        fresh.append(center.addObserver(
            forName: NSWorkspace.didHideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.emit(.applicationHidden(pid: app?.processIdentifier ?? 0))
        })

        fresh.append(center.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.emit(.applicationUnhidden(pid: app?.processIdentifier ?? 0))
        })

        fresh.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.emit(.activeSpaceDidChange)
        })

        fresh.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.emit(.didWake)
        })

        fresh.append(nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.emit(.screenParametersChanged)
        })

        stateQueue.sync { tokens = fresh }
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        let snapshot: [NSObjectProtocol] = stateQueue.sync {
            let copy = tokens
            tokens = []
            handler = nil
            return copy
        }
        for token in snapshot {
            center.removeObserver(token)
            nc.removeObserver(token)
        }
    }

    private func emit(_ event: PlatformEvent) {
        let h = stateQueue.sync { handler }
        h?(event)
    }
}
