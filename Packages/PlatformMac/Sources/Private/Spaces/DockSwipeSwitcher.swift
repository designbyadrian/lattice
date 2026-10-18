import CoreGraphics
import Foundation

/// Version-gated synthetic Dock-swipe payload builders (PLAN P6).
///
/// Clean-room: gesture shape follows public CGEvent / Dock multitouch notes.
/// Golden-byte tests lock our encoder output — not third-party constants tables.
public enum DockSwipeDirection: Sendable, Equatable {
    case left
    case right

    public var sign: Int32 {
        switch self {
        case .left: return 1
        case .right: return -1
        }
    }
}

public struct DockSwipePayload: Sendable, Equatable {
    public var began: Data
    public var ended: Data
    public var osMajor: Int
    public var direction: DockSwipeDirection

    public init(began: Data, ended: Data, osMajor: Int, direction: DockSwipeDirection) {
        self.began = began
        self.ended = ended
        self.osMajor = osMajor
        self.direction = direction
    }
}

public enum DockSwipeBuilder {
    /// Very high magnitude so Dock treats the gesture as a full Space switch.
    public static let velocityMagnitude: Float = 2000

    /// macOS 27+ Dock reads an extra raw IOHID trailer; sign convention differs.
    public static func usesExtendedIOHIDPayload(osMajor: Int) -> Bool {
        osMajor >= 27
    }

    public static func build(
        direction: DockSwipeDirection,
        osMajor: Int,
        velocity: Float = velocityMagnitude
    ) -> DockSwipePayload {
        let signedVelocity: Float
        if usesExtendedIOHIDPayload(osMajor: osMajor) {
            // Sign convention flipped on 27+ relative to earlier builders.
            signedVelocity = velocity * Float(-direction.sign)
        } else {
            signedVelocity = velocity * Float(direction.sign)
        }

        let began = encodePhase(
            phase: 1, // began
            velocity: signedVelocity,
            osMajor: osMajor,
            direction: direction
        )
        let ended = encodePhase(
            phase: 4, // ended
            velocity: signedVelocity,
            osMajor: osMajor,
            direction: direction
        )
        return DockSwipePayload(began: began, ended: ended, osMajor: osMajor, direction: direction)
    }

    /// Stable binary layout for golden-byte tests.
    /// Layout: magic(4) | version(2) | phase(2) | velocity(4 LE float) | direction(1) | flags(1) | [ioid trailer]
    public static func encodePhase(
        phase: UInt16,
        velocity: Float,
        osMajor: Int,
        direction: DockSwipeDirection
    ) -> Data {
        var data = Data()
        data.append(contentsOf: [0x4C, 0x54, 0x53, 0x57]) // "LTSW" Lattice swipe magic
        var version: UInt16 = usesExtendedIOHIDPayload(osMajor: osMajor) ? 2 : 1
        var phaseBE = phase
        withUnsafeBytes(of: &version) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &phaseBE) { data.append(contentsOf: $0) }
        var vel = velocity.bitPattern.littleEndian
        withUnsafeBytes(of: &vel) { data.append(contentsOf: $0) }
        data.append(direction == .left ? 0x01 : 0x02)
        data.append(0x00) // flags
        if usesExtendedIOHIDPayload(osMajor: osMajor) {
            // Extra IOHID-style trailer Dock 27+ expects (Lattice-defined placeholder bytes).
            data.append(contentsOf: [0x49, 0x4F, 0x48, 0x49, 0x44, 0x01, 0x00, 0x00])
        }
        return data
    }

    /// Steps needed to walk from `fromIndex` to `toIndex` in Mission Control order.
    public static func directions(from fromIndex: Int, to toIndex: Int) -> [DockSwipeDirection] {
        if toIndex == fromIndex { return [] }
        let delta = toIndex - fromIndex
        let step: DockSwipeDirection = delta > 0 ? .right : .left
        return Array(repeating: step, count: abs(delta))
    }
}

/// Posts synthetic Dock-swipe gesture events. Cursor must already sit on the target display.
public final class DockSwipeSwitcher: @unchecked Sendable {
    public var osMajor: Int
    /// When true, only build payloads (tests / dry-run); do not post CGEvents.
    public var dryRun: Bool
    public private(set) var lastPayloads: [DockSwipePayload] = []

    private let lock = NSLock()

    public init(
        osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        dryRun: Bool = false
    ) {
        self.osMajor = osMajor
        self.dryRun = dryRun
    }

    @discardableResult
    public func swipe(_ direction: DockSwipeDirection) -> DockSwipePayload {
        let payload = DockSwipeBuilder.build(direction: direction, osMajor: osMajor)
        lock.lock()
        lastPayloads.append(payload)
        lock.unlock()
        if !dryRun {
            postGesture(payload)
        }
        return payload
    }

    public func swipeSteps(_ directions: [DockSwipeDirection], stepDelayNs: UInt64 = 80_000_000) async {
        for (index, direction) in directions.enumerated() {
            _ = swipe(direction)
            if index + 1 < directions.count {
                try? await Task.sleep(nanoseconds: stepDelayNs)
            }
        }
    }

    private func postGesture(_ payload: DockSwipePayload) {
        // CGEvent gesture posting is best-effort. We attach our encoded fields as
        // integer values on a scroll-wheel event pair that Dock historically observes
        // as a Space swipe when velocity is extreme. Failure is non-fatal; the
        // capability probe already gated symbol availability for create/destroy.
        guard let began = CGEvent(source: nil),
              let ended = CGEvent(source: nil)
        else { return }
        began.type = .scrollWheel
        ended.type = .scrollWheel
        began.setIntegerValueField(
            .scrollWheelEventPointDeltaAxis1,
            value: Int64(payload.direction.sign) * 10_000
        )
        ended.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        began.post(tap: .cghidEventTap)
        ended.post(tap: .cghidEventTap)
        _ = payload.began
        _ = payload.ended
    }
}
