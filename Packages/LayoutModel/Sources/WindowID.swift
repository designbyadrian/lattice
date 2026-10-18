import Foundation

/// Stable app-level window identity.
///
/// Prefers `cgWindowID` when present; falls back to a pid / bundle-id / title
/// fingerprint so a window can be re-matched after relaunch.
public struct WindowID: Hashable, Codable, Sendable, Equatable {
    public var cgWindowID: UInt32?
    public var processID: Int32
    public var bundleID: String?
    public var titleFingerprint: String

    public init(
        cgWindowID: UInt32? = nil,
        processID: Int32,
        bundleID: String? = nil,
        titleFingerprint: String = ""
    ) {
        self.cgWindowID = cgWindowID
        self.processID = processID
        self.bundleID = bundleID
        self.titleFingerprint = titleFingerprint
    }

    /// Convenience factory for tests and fixtures.
    public static func stub(_ tag: Int, bundleID: String? = "test.app") -> WindowID {
        precondition(tag >= 0, "stub tag must be non-negative")
        return WindowID(
            cgWindowID: UInt32(tag),
            processID: Int32(1_000 + tag),
            bundleID: bundleID,
            titleFingerprint: "win-\(tag)"
        )
    }

    /// Loose match used when rematching within the same process session (ignores cgWindowID).
    public func fingerprintMatches(_ other: WindowID) -> Bool {
        processID == other.processID
            && bundleID == other.bundleID
            && titleFingerprint == other.titleFingerprint
    }

    /// Match across relaunch: bundle ID + title fingerprint (pid and cgWindowID change).
    public func relaunchFingerprintMatches(_ other: WindowID) -> Bool {
        guard let bundle = bundleID, let otherBundle = other.bundleID, bundle == otherBundle else {
            return false
        }
        return titleFingerprint == other.titleFingerprint
    }

    /// Layout-tree node id for this window (stable within a session).
    /// Layout-only / golden ids (`WindowID.named`) use the title fingerprint as the node id.
    public var nodeID: NodeID {
        if processID == 0, bundleID == nil, cgWindowID == nil, !titleFingerprint.isEmpty {
            return titleFingerprint
        }
        if let cg = cgWindowID {
            return "cg:\(cg)"
        }
        return "fp:\(processID):\(bundleID ?? ""):\(titleFingerprint)"
    }

    /// Build a WindowID whose `nodeID` equals `id` (goldens / fixtures).
    public static func named(_ id: NodeID) -> WindowID {
        WindowID(cgWindowID: nil, processID: 0, bundleID: nil, titleFingerprint: id)
    }
}
