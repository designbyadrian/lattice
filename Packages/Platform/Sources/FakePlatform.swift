import Foundation

/// In-memory platform for AppCore / Platform unit tests.
public final class FakePlatform: WindowServerProtocol, PermissionsChecking, @unchecked Sendable {
    public var experimentalFlags: ExperimentalFlags
    public var windows: [WindowRef]
    public var displays: [DisplayRef]
    public var isAccessibilityTrusted: Bool
    public var hasScreenRecordingAccess: Bool
    public let spacesController: any SpacesControlling

    /// Recorded `setFrame` calls in order.
    public private(set) var appliedFrames: [(id: UInt32, pid: Int32, frame: CGRectCodable)] = []
    public private(set) var setFrameCallCount: Int = 0

    private var handler: PlatformEventHandler?
    private let queue = DispatchQueue(label: "com.designbyadrian.lattice.fake-platform")

    public init(
        windows: [WindowRef] = [],
        displays: [DisplayRef] = [
            DisplayRef(
                uuid: "fake-display-1",
                name: "Fake",
                frame: CGRectCodable(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRectCodable(x: 0, y: 0, width: 1440, height: 860)
            )
        ],
        experimentalFlags: ExperimentalFlags = .default,
        isAccessibilityTrusted: Bool = true,
        hasScreenRecordingAccess: Bool = false,
        spacesController: FakeSpacesController? = nil
    ) {
        self.windows = windows
        self.displays = displays
        self.experimentalFlags = experimentalFlags
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.hasScreenRecordingAccess = hasScreenRecordingAccess
        self.spacesController = spacesController ?? FakeSpacesController()
    }

    public var fakeSpaces: FakeSpacesController {
        spacesController as! FakeSpacesController
    }

    public func requestAccessibilityTrust(prompt: Bool) -> Bool {
        if prompt { isAccessibilityTrusted = true }
        return isAccessibilityTrusted
    }

    public func requestScreenRecordingAccess() -> Bool {
        hasScreenRecordingAccess = true
        return hasScreenRecordingAccess
    }

    public func listWindows() async -> [WindowRef] {
        await withQueue { self.windows }
    }

    public func listDisplays() async -> [DisplayRef] {
        await withQueue { self.displays }
    }

    public func setFrame(_ frame: CGRectCodable, for windowID: UInt32, pid: Int32) async throws {
        try await withQueueThrowing {
            guard self.isAccessibilityTrusted else { throw WindowServerError.accessibilityNotTrusted }
            guard let idx = self.windows.firstIndex(where: { $0.id == windowID && $0.pid == pid }) else {
                throw WindowServerError.windowNotFound(id: windowID, pid: pid)
            }
            self.windows[idx].frame = frame
            self.appliedFrames.append((id: windowID, pid: pid, frame: frame))
            self.setFrameCallCount += 1
        }
    }

    public func startObserving(_ handler: @escaping PlatformEventHandler) {
        queue.sync { self.handler = handler }
    }

    public func stopObserving() {
        queue.sync { self.handler = nil }
    }

    /// Test helper: emit an event to the registered handler.
    public func emit(_ event: PlatformEvent) {
        let h = queue.sync { handler }
        h?(event)
    }

    public func upsertWindow(_ window: WindowRef) {
        queue.sync {
            if let idx = windows.firstIndex(where: { $0.id == window.id }) {
                windows[idx] = window
            } else {
                windows.append(window)
            }
        }
    }

    public func removeWindow(id: UInt32) {
        queue.sync { windows.removeAll { $0.id == id } }
    }

    public func resetAppliedFrames() {
        queue.sync {
            appliedFrames = []
            setFrameCallCount = 0
        }
    }

    private func withQueue<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.async {
                cont.resume(returning: body())
            }
        }
    }

    private func withQueueThrowing(_ body: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try body()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
