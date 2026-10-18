import Foundation
import LayoutModel

/// Debounced, atomic per-display layout persistence.
public final class LayoutStore: @unchecked Sendable {
    public var debounceInterval: TimeInterval
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.designbyadrian.lattice.layout-store")
    private var pending: [String: DisplayLayout] = [:]
    private var workItems: [String: DispatchWorkItem] = [:]
    /// Injected save for tests.
    public var saveHandler: ((DisplayLayout) throws -> Void)?
    /// Injected load for tests (`nil` handler → disk). Return `nil` to skip restore.
    public var loadHandler: ((String) -> DisplayLayout?)?

    public init(
        debounceInterval: TimeInterval = 0.4,
        fileManager: FileManager = .default
    ) {
        self.debounceInterval = debounceInterval
        self.fileManager = fileManager
    }

    /// In-memory store that never touches Application Support (for unit tests).
    public static func inMemory(debounceInterval: TimeInterval = 0.05) -> LayoutStore {
        let store = LayoutStore(debounceInterval: debounceInterval)
        store.loadHandler = { _ in nil }
        store.saveHandler = { _ in }
        return store
    }

    public func load(displayUUID: String) -> DisplayLayout? {
        if let loadHandler {
            return loadHandler(displayUUID)
        }
        do {
            return try LayoutPersistence.load(displayUUID: displayUUID, fileManager: fileManager)
        } catch {
            return nil
        }
    }

    public func loadRematched(displayUUID: String, liveWindows: [WindowID]) -> DisplayLayout? {
        guard var layout = load(displayUUID: displayUUID) else { return nil }
        layout = WindowRematcher.rematch(layout: layout, live: liveWindows)
        return layout
    }

    /// Schedule a debounced save for the display.
    public func scheduleSave(_ layout: DisplayLayout) {
        let uuid = layout.displayUUID
        queue.async { [self] in
            pending[uuid] = layout
            workItems[uuid]?.cancel()
            let item = DispatchWorkItem { [self] in
                flush(uuid: uuid)
            }
            workItems[uuid] = item
            queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
        }
    }

    /// Flush all pending writes immediately.
    public func flushAll() {
        queue.sync {
            let keys = Array(pending.keys)
            for uuid in keys {
                flush(uuid: uuid)
            }
        }
    }

    private func flush(uuid: String) {
        guard let layout = pending.removeValue(forKey: uuid) else { return }
        workItems[uuid]?.cancel()
        workItems[uuid] = nil
        do {
            if let saveHandler {
                try saveHandler(layout)
            } else {
                try LayoutPersistence.save(layout, fileManager: fileManager)
            }
        } catch {
            // Best-effort; in-memory state remains authoritative.
        }
    }
}
