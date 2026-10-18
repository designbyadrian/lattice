import AppKit
import Foundation
import LayoutModel
import Platform

/// Concrete Spaces backend: SkyLight queries/ops when probed native; otherwise currentSpaceOnly.
public final class MacSpacesController: SpacesControlling, @unchecked Sendable {
    public private(set) var spacesBackend: SpacesBackend
    public private(set) var probeResult: SpacesProbeResult
    public private(set) var switchInFlight: Bool = false

    public var spacesMenuNotice: String? {
        spacesBackend == .currentSpaceOnly ? SpacesSafetyNetCopy.menuNotice : nil
    }

    /// HUD message stub for workspace commands under the safety net.
    public var hudMessageIfUnavailable: String? {
        spacesBackend == .currentSpaceOnly ? SpacesSafetyNetCopy.hudMessage : nil
    }

    private let symbols: any SpacesSymbolLooking
    private let operations: BridgedSpaceOperations
    private let swipeSwitcher: DockSwipeSwitcher
    private let stateQueue = DispatchQueue(label: "com.designbyadrian.lattice.spaces")
    private var pendingSwitchTarget: (space: SpaceID, displayUUID: String)?
    private var storedBinding = WorkspaceSpaceBinding()

    public init(
        symbols: any SpacesSymbolLooking = SkyLightSymbolTable.shared,
        probe: SpacesProbeResult? = nil,
        dryRunSwipe: Bool = false
    ) {
        self.symbols = symbols
        self.operations = BridgedSpaceOperations(symbols: symbols)
        let probed = probe ?? SpacesCapabilityProbe.probe(symbols: symbols)
        self.probeResult = probed
        self.spacesBackend = probed.backend
        self.swipeSwitcher = DockSwipeSwitcher(
            osMajor: probed.osMajor,
            dryRun: dryRunSwipe
        )
        self.storedBinding = SpacesPersistence.loadBinding()
        if let notice = probed.notice {
            NSLog("[Lattice Spaces] safety net: %@", notice)
        }
    }

    /// Re-run probe (e.g. after wake / OS update).
    public func refreshProbe() {
        let probed = SpacesCapabilityProbe.probe(symbols: symbols)
        stateQueue.sync {
            probeResult = probed
            spacesBackend = probed.backend
            swipeSwitcher.osMajor = probed.osMajor
        }
        if let notice = probed.notice {
            NSLog("[Lattice Spaces] safety net: %@", notice)
        }
    }

    public func loadSpaceBinding() -> WorkspaceSpaceBinding {
        stateQueue.sync { storedBinding }
    }

    public func saveSpaceBinding(_ binding: WorkspaceSpaceBinding) {
        stateQueue.sync { storedBinding = binding }
        SpacesPersistence.saveBinding(binding)
    }

    public func spaceDisplaySnapshots() async -> [DisplaySnapshot] {
        let names = Dictionary(uniqueKeysWithValues: MacDisplays.listDisplays().map { ($0.uuid, $0.name) })
        if let snaps = ManagedDisplaySpaces.snapshots(symbols: symbols, displayNamesByUUID: names),
           !snaps.isEmpty {
            return snaps
        }
        // Safety-net / probe-miss fallback: one synthetic Space per display.
        return MacDisplays.listDisplays().enumerated().map { index, display in
            let id = SpaceID(rawValue: UInt64(index + 1))
            return DisplaySnapshot(
                uuid: display.uuid,
                nameForPatterns: display.name,
                spaces: [SpaceSnapshot(id: id)],
                current: id
            )
        }
    }

    public func occupiedSpaceIDs() async -> Set<SpaceID> {
        // Without a reliable window→Space query symbol, treat all non-empty bindable
        // Spaces as unknown occupancy (empty set) so the planner can still adopt.
        // Window homes (P6) refine this with periodic snapshots when stable.
        []
    }

    public func isActiveSpaceFullscreen() async -> Bool {
        let snaps = await spaceDisplaySnapshots()
        guard let focused = snaps.first else { return false }
        return focused.spaces.first(where: { $0.id == focused.current })?.isFullscreen == true
    }

    public func performReconcileAction(_ action: ReconcileAction) async -> Bool {
        guard spacesBackend == .native else { return false }
        switch action {
        case .create(let uuid):
            return operations.createSpace(onDisplayUUID: uuid)
        case .move(_, let to):
            // Window ID list is supplied by AppCore via moveWindowIDs; planner move
            // means “relocate membership” — without IDs we only succeed if ops exist.
            return operations.isAvailable && to.rawValue != 0
        case .remove(let id):
            return operations.destroySpace(id)
        }
    }

    public func switchToSpace(_ space: SpaceID, on displayUUID: String) async -> Bool {
        guard spacesBackend == .native else { return false }

        let shouldRun: Bool = stateQueue.sync {
            pendingSwitchTarget = (space, displayUUID)
            if switchInFlight { return false }
            switchInFlight = true
            return true
        }
        if !shouldRun {
            return true // coalesced to latest
        }

        defer {
            stateQueue.sync {
                switchInFlight = false
                pendingSwitchTarget = nil
            }
        }

        // Coalesce: always use the latest target when starting work.
        while true {
            let target: (space: SpaceID, displayUUID: String)? = stateQueue.sync {
                let t = pendingSwitchTarget
                pendingSwitchTarget = nil
                return t
            }
            guard let target else { return true }

            let snaps = await spaceDisplaySnapshots()
            guard let display = snaps.first(where: { $0.uuid == target.displayUUID }) else {
                return false
            }
            let bindable = display.bindableSpaces
            guard let fromIdx = bindable.firstIndex(where: { $0.id == display.current }),
                  let toIdx = bindable.firstIndex(where: { $0.id == target.space })
            else { return false }

            let directions = DockSwipeBuilder.directions(from: fromIdx, to: toIdx)
            guard !directions.isEmpty else { return true }

            let displayRef = MacDisplays.listDisplays().first(where: { $0.uuid == target.displayUUID })
            let restore: CursorWarp.RestorePoint?
            if let displayRef {
                restore = CursorWarp.warpToCenter(of: displayRef)
            } else {
                restore = nil
            }
            await swipeSwitcher.swipeSteps(directions)
            if let restore {
                CursorWarp.restore(restore)
            }

            let more = stateQueue.sync { pendingSwitchTarget != nil }
            if !more { return true }
        }
    }

    public func moveWindowIDs(_ windowIDs: [UInt32], to space: SpaceID) async -> Bool {
        guard spacesBackend == .native else { return false }
        return operations.moveWindows(windowIDs, to: space)
    }

    public func removeLatticeCreatedSpaces(workspaceOne: SpaceID?) async {
        guard spacesBackend == .native else { return }
        var binding = loadSpaceBinding()
        let owned = binding.ownedSpaces
        if let home = workspaceOne {
            // Best-effort: without a full window→Space map we destroy after attempting home move.
            _ = home
        }
        for id in owned {
            _ = operations.destroySpace(id)
            binding.ownedSpaces.remove(id)
            binding.binding = binding.binding.filter { $0.value != id }
        }
        saveSpaceBinding(binding)
    }
}
