import Foundation
import LayoutModel

/// Selected Spaces implementation after the launch / post-update capability probe.
public enum SpacesBackend: String, Sendable, Equatable, Codable {
    /// Full native SkyLight create / bind / move / remove + Dock-swipe switching.
    case native
    /// Safety net: manage windows on the current Space only; workspace commands show a HUD.
    case currentSpaceOnly
}

/// HUD / menu copy when the safety net is active (PLAN P6).
public enum SpacesSafetyNetCopy {
    public static let hudMessage = "Workspaces unavailable on this macOS build"
    public static let menuNotice = "Native Spaces unavailable on this macOS build"
    public static let menuDetailsStub = "Details"
}

/// Platform surface for numbered workspaces backed by macOS Spaces.
/// Implemented by PlatformMac; FakePlatform stubs for AppCore tests.
public protocol SpacesControlling: AnyObject, Sendable {
    var spacesBackend: SpacesBackend { get }
    /// Persistent menu notice when `spacesBackend == .currentSpaceOnly`.
    var spacesMenuNotice: String? { get }

    func loadSpaceBinding() -> WorkspaceSpaceBinding
    func saveSpaceBinding(_ binding: WorkspaceSpaceBinding)

    func spaceDisplaySnapshots() async -> [DisplaySnapshot]
    func occupiedSpaceIDs() async -> Set<SpaceID>
    /// True when the active Space (focused display) is a full-screen Space.
    func isActiveSpaceFullscreen() async -> Bool

    /// Apply one reconcile planner action. Returns false on failure (caller rolls back binding).
    func performReconcileAction(_ action: ReconcileAction) async -> Bool

    /// Switch to `space` on `displayUUID` (cursor warp + Dock-swipe when native).
    func switchToSpace(_ space: SpaceID, on displayUUID: String) async -> Bool

    /// Move CG windows onto `space` (bridged move when native).
    func moveWindowIDs(_ windowIDs: [UInt32], to space: SpaceID) async -> Bool

    /// Uninstall path: move windows off owned Spaces onto workspace 1’s Space, then destroy owned.
    func removeLatticeCreatedSpaces(workspaceOne: SpaceID?) async

    /// Latest coalesced switch target while a switch is in flight (nil when idle).
    var switchInFlight: Bool { get }
}
