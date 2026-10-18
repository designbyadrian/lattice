import Foundation

/// One window target for animated or immediate frame application.
public struct WindowFrameTarget: Sendable, Equatable, Hashable {
    public var windowID: UInt32
    public var pid: Int32
    public var frame: CGRectCodable

    public init(windowID: UInt32, pid: Int32, frame: CGRectCodable) {
        self.windowID = windowID
        self.pid = pid
        self.frame = frame
    }
}

/// Display-refresh driven frame animation (implemented by PlatformMac; FakePlatform jumps).
public protocol FrameAnimating: AnyObject, Sendable {
    /// Animate toward `targets`. Interruptible: a new call retargets mid-flight.
    /// When `reduceMotion` is true, jumps immediately (no interpolated motion).
    func animateFrames(
        to targets: [WindowFrameTarget],
        durationSeconds: Double,
        reduceMotion: Bool
    ) async

    /// Cancel in-flight animation and leave windows at their last applied frames.
    func cancelAnimation()

    /// Whether an animation is currently in flight.
    var isAnimating: Bool { get }
}
