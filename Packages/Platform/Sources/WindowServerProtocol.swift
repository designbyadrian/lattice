import Foundation

/// Read / write / observe surface implemented by PlatformMac; AppCore depends only on this.
public protocol WindowServerProtocol: AnyObject, Sendable {
    var experimentalFlags: ExperimentalFlags { get set }

    // MARK: Read

    func listWindows() async -> [WindowRef]
    func listDisplays() async -> [DisplayRef]

    // MARK: Write

    /// Apply a frame using AX size → position → size order on a per-app serial queue.
    func setFrame(_ frame: CGRectCodable, for windowID: UInt32, pid: Int32) async throws

    // MARK: Observe

    func startObserving(_ handler: @escaping PlatformEventHandler)
    func stopObserving()
}

/// Marker for future input taps (P5).
public protocol InputEvents: AnyObject, Sendable {}

/// Errors from platform write paths.
public enum WindowServerError: Error, Sendable, Equatable {
    case accessibilityNotTrusted
    case windowNotFound(id: UInt32, pid: Int32)
    case axFailure(message: String)
}
