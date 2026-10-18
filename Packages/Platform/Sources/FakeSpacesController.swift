import Foundation
import LayoutModel

/// In-memory Spaces controller for AppCore / Platform tests.
public final class FakeSpacesController: SpacesControlling, @unchecked Sendable {
    public private(set) var spacesBackend: SpacesBackend
    public var spacesMenuNotice: String? {
        spacesBackend == .currentSpaceOnly ? SpacesSafetyNetCopy.menuNotice : nil
    }

    public var binding = WorkspaceSpaceBinding()
    public var snapshots: [DisplaySnapshot]
    public var occupied: Set<SpaceID>
    public var switchInFlight: Bool = false
    public var activeSpaceFullscreen: Bool = false

    public private(set) var performedActions: [ReconcileAction] = []
    public private(set) var switches: [(SpaceID, String)] = []
    public private(set) var movedWindows: [(ids: [UInt32], space: SpaceID)] = []
    public var nextActionSucceeds: Bool = true

    private var nextCreatedID: UInt64 = 1000
    private let queue = DispatchQueue(label: "com.designbyadrian.lattice.fake-spaces")

    public init(
        backend: SpacesBackend = .native,
        snapshots: [DisplaySnapshot] = [
            DisplaySnapshot(
                uuid: "fake-display-1",
                nameForPatterns: "Fake",
                spaces: [SpaceSnapshot(id: SpaceID(rawValue: 1))],
                current: SpaceID(rawValue: 1)
            )
        ],
        occupied: Set<SpaceID> = [],
        binding: WorkspaceSpaceBinding = WorkspaceSpaceBinding()
    ) {
        self.spacesBackend = backend
        self.snapshots = snapshots
        self.occupied = occupied
        self.binding = binding
    }

    public func setBackend(_ backend: SpacesBackend) {
        queue.sync { spacesBackend = backend }
    }

    public func loadSpaceBinding() -> WorkspaceSpaceBinding {
        queue.sync { binding }
    }

    public func saveSpaceBinding(_ binding: WorkspaceSpaceBinding) {
        queue.sync { self.binding = binding }
    }

    public func spaceDisplaySnapshots() async -> [DisplaySnapshot] {
        await withQueue { self.snapshots }
    }

    public func occupiedSpaceIDs() async -> Set<SpaceID> {
        await withQueue { self.occupied }
    }

    public func isActiveSpaceFullscreen() async -> Bool {
        await withQueue { self.activeSpaceFullscreen }
    }

    public func performReconcileAction(_ action: ReconcileAction) async -> Bool {
        await withQueue {
            self.performedActions.append(action)
            guard self.nextActionSucceeds else { return false }
            switch action {
            case .create(let uuid):
                self.nextCreatedID += 1
                let id = SpaceID(rawValue: self.nextCreatedID)
                self.binding.ownedSpaces.insert(id)
                if let idx = self.snapshots.firstIndex(where: { $0.uuid == uuid }) {
                    var snap = self.snapshots[idx]
                    snap.spaces.append(SpaceSnapshot(id: id))
                    self.snapshots[idx] = snap
                }
            case .move(let from, let to):
                self.occupied.remove(from)
                self.occupied.insert(to)
            case .remove(let id):
                self.binding.ownedSpaces.remove(id)
                for i in self.snapshots.indices {
                    self.snapshots[i].spaces.removeAll { $0.id == id }
                }
            }
            return true
        }
    }

    public func switchToSpace(_ space: SpaceID, on displayUUID: String) async -> Bool {
        await withQueue {
            if self.spacesBackend == .currentSpaceOnly { return false }
            self.switches.append((space, displayUUID))
            if let idx = self.snapshots.firstIndex(where: { $0.uuid == displayUUID }) {
                self.snapshots[idx].current = space
            }
            return true
        }
    }

    public func moveWindowIDs(_ windowIDs: [UInt32], to space: SpaceID) async -> Bool {
        await withQueue {
            self.movedWindows.append((windowIDs, space))
            self.occupied.insert(space)
            return self.spacesBackend == .native || !windowIDs.isEmpty
        }
    }

    public func removeLatticeCreatedSpaces(workspaceOne: SpaceID?) async {
        await withQueue {
            let owned = self.binding.ownedSpaces
            if let home = workspaceOne {
                for id in owned where id != home {
                    self.occupied.remove(id)
                    self.occupied.insert(home)
                }
            }
            for id in owned {
                for i in self.snapshots.indices {
                    self.snapshots[i].spaces.removeAll { $0.id == id }
                }
            }
            self.binding.ownedSpaces.removeAll()
            self.binding.binding = self.binding.binding.filter { !owned.contains($0.value) }
        }
    }

    private func withQueue<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: body()) }
        }
    }
}
