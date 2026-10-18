import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Platform

/// AX frame writes: size → position → size, per-app serial queue, messaging timeout.
public final class MacWindowWriter: @unchecked Sendable {
    public static let shared = MacWindowWriter()

    private let registry = DispatchQueue(label: "com.designbyadrian.lattice.ax-registry")
    private var queues: [Int32: DispatchQueue] = [:]
    public var messagingTimeout: Float = MacWindowDiscovery.axMessagingTimeout

    public init() {}

    private func queue(for pid: Int32) -> DispatchQueue {
        registry.sync {
            if let existing = queues[pid] { return existing }
            let q = DispatchQueue(label: "com.designbyadrian.lattice.ax.\(pid)", qos: .userInitiated)
            queues[pid] = q
            return q
        }
    }

    public func setFrame(_ frame: CGRectCodable, for windowID: UInt32, pid: Int32) async throws {
        guard AXIsProcessTrusted() else {
            throw WindowServerError.accessibilityNotTrusted
        }

        let timeout = messagingTimeout
        let appQueue = queue(for: pid)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            appQueue.async {
                do {
                    try Self.applyFrameSync(
                        frame,
                        windowID: windowID,
                        pid: pid,
                        timeout: timeout
                    )
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronous AX write on the caller’s queue (used by the per-app serial queue).
    public static func applyFrameSync(
        _ frame: CGRectCodable,
        windowID: UInt32,
        pid: Int32,
        timeout: Float
    ) throws {
        guard let element = MacWindowDiscovery.axElement(windowID: windowID, pid: pid, timeout: timeout) else {
            throw WindowServerError.windowNotFound(id: windowID, pid: pid)
        }
        AXUIElementSetMessagingTimeout(element, timeout)

        let size = CGSize(width: frame.width, height: frame.height)
        let origin = CGPoint(x: frame.x, y: frame.y)

        // PLAN §6: size → position → size
        try setSize(element, size)
        try setPosition(element, origin)
        try setSize(element, size)
    }

    private static func setSize(_ element: AXUIElement, _ size: CGSize) throws {
        var value = size
        guard let ax = AXValueCreate(.cgSize, &value) else {
            throw WindowServerError.axFailure(message: "AXValueCreate size failed")
        }
        let err = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, ax)
        guard err == .success else {
            throw WindowServerError.axFailure(message: "set size \(err.rawValue)")
        }
    }

    private static func setPosition(_ element: AXUIElement, _ point: CGPoint) throws {
        var value = point
        guard let ax = AXValueCreate(.cgPoint, &value) else {
            throw WindowServerError.axFailure(message: "AXValueCreate position failed")
        }
        let err = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, ax)
        guard err == .success else {
            throw WindowServerError.axFailure(message: "set position \(err.rawValue)")
        }
    }

    /// Raise and focus a window via AX (used by `focus <dir>` / focus-follows-mouse).
    public func raise(windowID: UInt32, pid: Int32) async {
        guard AXIsProcessTrusted() else { return }
        let timeout = messagingTimeout
        let appQueue = queue(for: pid)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            appQueue.async {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.activate()
                }
                if let element = MacWindowDiscovery.axElement(
                    windowID: windowID, pid: pid, timeout: timeout
                ) {
                    AXUIElementSetMessagingTimeout(element, timeout)
                    AXUIElementPerformAction(element, kAXRaiseAction as CFString)
                    AXUIElementSetAttributeValue(
                        element,
                        kAXMainAttribute as CFString,
                        kCFBooleanTrue
                    )
                    AXUIElementSetAttributeValue(
                        element,
                        kAXFocusedAttribute as CFString,
                        kCFBooleanTrue
                    )
                }
                cont.resume()
            }
        }
    }
}
