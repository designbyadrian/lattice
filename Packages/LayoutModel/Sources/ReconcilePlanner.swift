import Foundation

/// One Space as seen by the reconcile planner (Mission Control order per display).
public struct SpaceSnapshot: Equatable, Sendable, Hashable {
    public var id: SpaceID
    public var isFullscreen: Bool

    public init(id: SpaceID, isFullscreen: Bool = false) {
        self.id = id
        self.isFullscreen = isFullscreen
    }

    /// Ordinary user Spaces only; full-screen Spaces are never bindable.
    public var isBindable: Bool { !isFullscreen }
}

/// Per-display snapshot fed into `ReconcilePlanner.step`.
public struct DisplaySnapshot: Equatable, Sendable {
    public var uuid: String
    public var nameForPatterns: String
    /// Spaces in Mission Control order (user + full-screen).
    public var spaces: [SpaceSnapshot]
    public var current: SpaceID

    public init(
        uuid: String,
        nameForPatterns: String,
        spaces: [SpaceSnapshot],
        current: SpaceID
    ) {
        self.uuid = uuid
        self.nameForPatterns = nameForPatterns
        self.spaces = spaces
        self.current = current
    }

    public var bindableSpaces: [SpaceSnapshot] {
        spaces.filter(\.isBindable)
    }
}

/// One platform operation the planner may request. Apply, re-snapshot, then `step` again.
public enum ReconcileAction: Equatable, Sendable {
    case create(displayUUID: String)
    case move(from: SpaceID, to: SpaceID)
    case remove(SpaceID)
}

/// Pure workspace↔Space reconcile planner (PLAN P6). No AppKit / SkyLight.
///
/// Invariants:
/// - Only Spaces in `owned` that are empty and unbound may be removed.
/// - Never remove the current Space, a display's last bindable Space, or a Space Lattice did not create.
/// - Windows move only into empty Spaces (destinations must not be in `occupied`).
/// - Full-screen Spaces are never bindable.
public enum ReconcilePlanner {
    public static let defaultIterationCap = 50

    /// Single reconcile step. Binding-only updates (adopt / unbind) happen inside the step;
    /// at most one platform `action` is returned.
    public static func step(
        displays: [DisplaySnapshot],
        binding: [Int: SpaceID],
        owned: Set<SpaceID>,
        occupied: Set<SpaceID>,
        plan: WorkspacePlan
    ) -> (binding: [Int: SpaceID], owned: Set<SpaceID>, action: ReconcileAction?) {
        var binding = binding
        var owned = owned

        let spaceIndex = buildSpaceIndex(displays)
        pruneInvalidBindings(
            binding: &binding,
            plan: plan,
            spaceIndex: spaceIndex
        )

        // Place workspaces 1…count in number order, display by display.
        // Removals run only after placement so a just-created owned Space can be adopted.
        var previousIndexOnDisplay: [String: Int] = [:]

        for number in 1...plan.count {
            let display = resolveDisplay(for: number, plan: plan, displays: displays)
            guard let display else { continue }

            let bindable = display.bindableSpaces
            let searchStart = (previousIndexOnDisplay[display.uuid] ?? -1) + 1

            if let existing = binding[number],
               let idx = bindable.firstIndex(where: { $0.id == existing }),
               idx >= searchStart || binding.values.filter({ $0 == existing }).count == 1 {
                // Already placed on this display in a valid slot at or after the search window,
                // or uniquely bound (first workspace may adopt current anywhere).
                if number == 1 || idx >= searchStart {
                    previousIndexOnDisplay[display.uuid] = idx
                    continue
                }
            }

            // Default for workspace 1: adopt the display's current Space when bindable.
            if number == 1,
               binding[number] == nil,
               let currentSnap = display.spaces.first(where: { $0.id == display.current }),
               currentSnap.isBindable,
               isAdoptable(currentSnap.id, binding: binding, except: number, occupied: occupied) {
                binding[number] = currentSnap.id
                if let idx = bindable.firstIndex(where: { $0.id == currentSnap.id }) {
                    previousIndexOnDisplay[display.uuid] = idx
                }
                continue
            }

            if let slot = firstFreeSlot(
                in: bindable,
                from: searchStart,
                binding: binding,
                exceptWorkspace: number,
                occupied: occupied
            ) {
                let target = bindable[slot].id
                if let from = binding[number], from != target {
                    if occupied.contains(target) {
                        // Should not happen (firstFreeSlot skips occupied); skip defensively.
                    } else if occupied.contains(from) {
                        binding[number] = target
                        previousIndexOnDisplay[display.uuid] = slot
                        return (binding, owned, .move(from: from, to: target))
                    } else {
                        binding[number] = target
                        previousIndexOnDisplay[display.uuid] = slot
                        continue
                    }
                } else {
                    binding[number] = target
                    previousIndexOnDisplay[display.uuid] = slot
                    continue
                }
            }

            // Need a new Space on this display.
            return (binding, owned, .create(displayUUID: display.uuid))
        }

        // After placement, remove owned empty unbound extras (e.g. after lowering count).
        if let removal = nextRemoval(
            displays: displays,
            binding: binding,
            owned: owned,
            occupied: occupied
        ) {
            owned.remove(removal)
            return (binding, owned, .remove(removal))
        }

        return (binding, owned, nil)
    }

    /// Loop `step` with a synthetic apply callback until nil or the iteration cap.
    public static func run(
        displays: [DisplaySnapshot],
        binding: [Int: SpaceID],
        owned: Set<SpaceID>,
        occupied: Set<SpaceID>,
        plan: WorkspacePlan,
        maxIterations: Int = defaultIterationCap,
        apply: (ReconcileAction, inout [DisplaySnapshot], inout Set<SpaceID>, inout Set<SpaceID>) -> Void
    ) -> (binding: [Int: SpaceID], owned: Set<SpaceID>, iterations: Int, capped: Bool) {
        var binding = binding
        var owned = owned
        var displays = displays
        var occupied = occupied
        var iterations = 0

        while iterations < maxIterations {
            let result = step(
                displays: displays,
                binding: binding,
                owned: owned,
                occupied: occupied,
                plan: plan
            )
            binding = result.binding
            owned = result.owned
            guard let action = result.action else {
                return (binding, owned, iterations, false)
            }
            apply(action, &displays, &owned, &occupied)
            iterations += 1
        }
        return (binding, owned, iterations, true)
    }

    // MARK: - Display resolution

    public static func resolveDisplay(
        for workspace: Int,
        plan: WorkspacePlan,
        displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        guard !displays.isEmpty else { return nil }
        let patterns = plan.workspaceToDisplay[workspace] ?? [.main]
        for pattern in patterns {
            if let match = matchDisplay(pattern, in: displays) {
                return match
            }
        }
        return matchDisplay(.main, in: displays) ?? displays[0]
    }

    public static func matchDisplay(
        _ pattern: DisplayPattern,
        in displays: [DisplaySnapshot]
    ) -> DisplaySnapshot? {
        switch pattern {
        case .main:
            return displays.first
        case .secondary:
            return displays.count > 1 ? displays[1] : nil
        case .nameSubstring(let needle):
            let lower = needle.lowercased()
            return displays.first { $0.nameForPatterns.lowercased().contains(lower) }
        }
    }

    // MARK: - Internals

    private static func buildSpaceIndex(
        _ displays: [DisplaySnapshot]
    ) -> [SpaceID: (displayUUID: String, snapshot: SpaceSnapshot)] {
        var index: [SpaceID: (String, SpaceSnapshot)] = [:]
        for display in displays {
            for space in display.spaces {
                index[space.id] = (display.uuid, space)
            }
        }
        return index
    }

    private static func pruneInvalidBindings(
        binding: inout [Int: SpaceID],
        plan: WorkspacePlan,
        spaceIndex: [SpaceID: (displayUUID: String, snapshot: SpaceSnapshot)]
    ) {
        for key in binding.keys where key < 1 || key > plan.count {
            binding.removeValue(forKey: key)
        }
        for (number, spaceID) in binding {
            guard let entry = spaceIndex[spaceID], entry.snapshot.isBindable else {
                binding.removeValue(forKey: number)
                continue
            }
        }
    }

    private static func isAdoptable(
        _ spaceID: SpaceID,
        binding: [Int: SpaceID],
        except: Int,
        occupied: Set<SpaceID>
    ) -> Bool {
        if let owner = binding.first(where: { $0.value == spaceID && $0.key != except }) {
            _ = owner
            return false
        }
        // Occupied spaces may still be adopted when already bound to `except`, or when
        // empty of *other* workspaces — but we never place a *new* workspace onto an
        // occupied unbound Space (would mix windows).
        if occupied.contains(spaceID), binding[except] != spaceID {
            // Allow adopting current for workspace 1 even if it has windows (those windows
            // already live on that Space / workspace).
            if except == 1 { return true }
            return false
        }
        return true
    }

    private static func firstFreeSlot(
        in bindable: [SpaceSnapshot],
        from searchStart: Int,
        binding: [Int: SpaceID],
        exceptWorkspace: Int,
        occupied: Set<SpaceID>
    ) -> Int? {
        guard searchStart <= bindable.count else { return nil }
        let start = max(0, searchStart)
        for idx in start..<bindable.count {
            let id = bindable[idx].id
            if let bound = binding[exceptWorkspace], bound == id {
                return idx
            }
            let takenByOther = binding.contains { $0.key != exceptWorkspace && $0.value == id }
            if takenByOther { continue }
            if occupied.contains(id), binding[exceptWorkspace] != id {
                continue
            }
            return idx
        }
        return nil
    }

    private static func nextRemoval(
        displays: [DisplaySnapshot],
        binding: [Int: SpaceID],
        owned: Set<SpaceID>,
        occupied: Set<SpaceID>
    ) -> SpaceID? {
        let boundIDs = Set(binding.values)
        for display in displays {
            let bindable = display.bindableSpaces
            guard bindable.count > 1 else { continue }
            for space in bindable {
                let id = space.id
                guard owned.contains(id) else { continue }
                guard !boundIDs.contains(id) else { continue }
                guard !occupied.contains(id) else { continue }
                guard id != display.current else { continue }
                return id
            }
        }
        return nil
    }
}
