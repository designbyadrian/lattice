import Foundation

/// High-level platform events forwarded to AppCore.
public enum PlatformEvent: Sendable, Equatable {
    case applicationLaunched(pid: Int32, bundleID: String?)
    case applicationTerminated(pid: Int32)
    case applicationActivated(pid: Int32)
    case applicationHidden(pid: Int32)
    case applicationUnhidden(pid: Int32)
    case activeSpaceDidChange
    case didWake
    case screenParametersChanged
    case windowCreated(WindowRef)
    case windowDestroyed(id: UInt32, pid: Int32)
    case windowMoved(WindowRef)
    case windowResized(WindowRef)
    case windowMinimized(id: UInt32, pid: Int32)
    case windowDeminimized(WindowRef)
    case windowFocused(WindowRef)
    case windowTitleChanged(WindowRef)
    case windowFullscreenChanged(WindowRef, isFullscreen: Bool)
}

public typealias PlatformEventHandler = @Sendable (PlatformEvent) -> Void
