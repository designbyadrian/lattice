import Foundation

/// On-disk layout blob for one display (PLAN §7 Persistence).
public struct PersistedDisplayLayout: Equatable, Codable, Sendable {
    public var schemaVersion: Int
    public var displayUUID: String
    public var layout: DisplayLayout

    public init(schemaVersion: Int = DisplayLayout.currentSchemaVersion, displayUUID: String, layout: DisplayLayout) {
        self.schemaVersion = schemaVersion
        self.displayUUID = displayUUID
        var copy = layout
        copy.displayUUID = displayUUID
        copy.schemaVersion = schemaVersion
        self.layout = copy
    }
}

/// Atomic layout JSON I/O with schema migrations. Never uses fixed `/tmp`.
public enum LayoutPersistence {
    public static let bundleSupportFolder = "com.designbyadrian.lattice"
    public static let layoutsSubfolder = "layouts"

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(bundleSupportFolder, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func layoutsDirectory(fileManager: FileManager = .default) throws -> URL {
        let dir = try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent(layoutsSubfolder, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func fileURL(
        forDisplayUUID uuid: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let safe = uuid.replacingOccurrences(of: "/", with: "_")
        return try layoutsDirectory(fileManager: fileManager)
            .appendingPathComponent("\(safe).json", isDirectory: false)
    }

    public static func load(
        displayUUID: String,
        fileManager: FileManager = .default
    ) throws -> DisplayLayout? {
        let url = try fileURL(forDisplayUUID: displayUUID, fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decode(data: data, expectedUUID: displayUUID)
    }

    public static func decode(data: Data, expectedUUID: String? = nil) throws -> DisplayLayout {
        let decoder = JSONDecoder()
        // Prefer wrapped form; fall back to raw DisplayLayout for older fixtures.
        if let wrapped = try? decoder.decode(PersistedDisplayLayout.self, from: data) {
            var layout = try migrate(wrapped.layout, from: wrapped.schemaVersion)
            if let expectedUUID {
                layout.displayUUID = expectedUUID
            }
            return layout
        }
        var layout = try decoder.decode(DisplayLayout.self, from: data)
        layout = try migrate(layout, from: layout.schemaVersion)
        if let expectedUUID {
            layout.displayUUID = expectedUUID
        }
        return layout
    }

    public static func encode(_ layout: DisplayLayout) throws -> Data {
        var copy = layout
        copy.schemaVersion = DisplayLayout.currentSchemaVersion
        let wrapped = PersistedDisplayLayout(
            schemaVersion: DisplayLayout.currentSchemaVersion,
            displayUUID: copy.displayUUID,
            layout: copy
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(wrapped)
    }

    /// Atomic write via a sibling temp file in the same directory (not `/tmp`).
    public static func save(
        _ layout: DisplayLayout,
        fileManager: FileManager = .default
    ) throws {
        let url = try fileURL(forDisplayUUID: layout.displayUUID, fileManager: fileManager)
        let data = try encode(layout)
        let dir = url.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        try data.write(to: temp, options: [.atomic])
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: url)
        }
    }

    /// Migrate layout blobs from older schema versions up to `currentSchemaVersion`.
    public static func migrate(_ layout: DisplayLayout, from version: Int) throws -> DisplayLayout {
        var current = layout
        var v = version
        if v < 1 {
            // Pre-versioned blobs: ensure savedViews keys are clipped and schema stamped.
            current.savedViews = current.savedViews.filter { (1...9).contains($0.key) }
            v = 1
        }
        // Future migrations: while v < currentSchemaVersion { … }
        current.schemaVersion = DisplayLayout.currentSchemaVersion
        return current
    }
}

/// Rematch persisted WindowIDs to live windows after relaunch.
public enum WindowRematcher {
    /// Prefer CGWindowID, then relaunch fingerprint (bundle + title; ignores pid).
    public static func rematch(
        layout: DisplayLayout,
        live: [WindowID]
    ) -> DisplayLayout {
        var mapping: [WindowID: WindowID] = [:]
        var used = Set<WindowID>()

        func claim(_ persisted: WindowID) -> WindowID {
            if let existing = mapping[persisted] { return existing }
            // Exact CG match.
            if let cg = persisted.cgWindowID, cg != 0,
               let hit = live.first(where: { $0.cgWindowID == cg && !used.contains($0) }) {
                mapping[persisted] = hit
                used.insert(hit)
                return hit
            }
            // Relaunch fingerprint.
            if let hit = live.first(where: {
                !used.contains($0) && persisted.relaunchFingerprintMatches($0)
            }) {
                mapping[persisted] = hit
                used.insert(hit)
                return hit
            }
            mapping[persisted] = persisted
            return persisted
        }

        func remapNode(_ node: Node) -> Node {
            switch node {
            case .desktop:
                return .desktop
            case .panel(let p):
                return .panel(PanelNode(window: claim(p.window)))
            case .tabs(let t):
                return .tabs(TabNode(
                    windows: t.windows.map(claim),
                    selectedIndex: t.selectedIndex
                ))
            case .split(let s):
                return .split(SplitNode(
                    axis: s.axis,
                    children: s.children.map(remapNode),
                    ratios: s.ratios
                ))
            }
        }

        var next = layout
        var workspaces: [Int: Workspace] = [:]
        for (num, ws) in layout.workspaces {
            var copy = ws
            copy.root = remapNode(ws.root)
            copy.floating = ws.floating.map { FloatingWindow(id: claim($0.id), frame: $0.frame) }
            var states: [WindowID: WindowState] = [:]
            for (id, state) in ws.windowStates {
                states[claim(id)] = state
            }
            copy.windowStates = states
            workspaces[num] = copy
        }
        next.workspaces = workspaces
        return next
    }
}
