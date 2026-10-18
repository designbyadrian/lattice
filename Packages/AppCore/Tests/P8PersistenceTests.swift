import Testing
import Foundation
import AppCore
import LayoutModel
import Config

@Test func layoutPersistenceRoundTripAndMigration() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lattice-layouts-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // Point LayoutPersistence at a custom tree by saving via encode + manual path.
    var layout = DisplayLayout(displayUUID: "TEST-UUID", schemaVersion: 1)
    layout.saveView(3, camera: Camera(focusPath: [0], zoom: 0.5))
    let data = try LayoutPersistence.encode(layout)
    let decoded = try LayoutPersistence.decode(data: data, expectedUUID: "TEST-UUID")
    #expect(decoded.view(3)?.zoom == 0.5)
    #expect(decoded.schemaVersion == DisplayLayout.currentSchemaVersion)

    // Pre-v1 blob (schemaVersion 0) migrates.
    var old = layout
    old.schemaVersion = 0
    let migrated = try LayoutPersistence.migrate(old, from: 0)
    #expect(migrated.schemaVersion == DisplayLayout.currentSchemaVersion)
}

@Test func layoutStoreDebouncedSave() async throws {
    let store = LayoutStore(debounceInterval: 0.05)
    var saved: [DisplayLayout] = []
    store.saveHandler = { layout in
        saved.append(layout)
    }
    var layout = DisplayLayout(displayUUID: "A")
    layout.saveView(1, camera: .showAll)
    store.scheduleSave(layout)
    layout.saveView(2, camera: Camera(focusPath: [], zoom: 1))
    store.scheduleSave(layout)
    try await Task.sleep(nanoseconds: 120_000_000)
    store.flushAll()
    #expect(saved.count >= 1)
    #expect(saved.last?.view(2) != nil)
}

@Test func windowRematcherUsesRelaunchFingerprint() {
    let old = WindowID(cgWindowID: 1, processID: 100, bundleID: "com.app", titleFingerprint: "Doc")
    let live = WindowID(cgWindowID: 99, processID: 200, bundleID: "com.app", titleFingerprint: "Doc")
    var layout = DisplayLayout(displayUUID: "D")
    var ws = Workspace.empty
    ws.root = .panel(PanelNode(window: old))
    layout.workspaces[1] = ws
    let rematched = WindowRematcher.rematch(layout: layout, live: [live])
    #expect(rematched.workspaces[1]?.root.tiledWindowIDs.first?.cgWindowID == 99)
    #expect(old.relaunchFingerprintMatches(live))
}

@Test func focusFollowsMouseStateMachine() {
    var m = FocusFollowsMouseMachine(config: FocusFollowsMouseConfig(enabled: true, delayMs: 50))
    #expect(m.notePointer(over: "a") == .armTimer(windowKey: "a", delayMs: 50))
    #expect(m.noteTimerFired(for: "a") == .focus(windowKey: "a"))

    _ = m.noteButtonDown()
    #expect(m.notePointer(over: "b") == .cancelTimer)

    _ = m.noteButtonUp()
    _ = m.noteActivationOrSpaceChange()
    #expect(m.notePointer(over: "c") == .none) // still suppressed until different window
    #expect(m.notePointer(over: "d") == .armTimer(windowKey: "d", delayMs: 50))

    m.config.excludeApps = ["com.skip"]
    #expect(m.isExcluded(bundleID: "com.skip"))
}

@Test func borderGeometryContrastAndFrames() throws {
    let rgba = try BorderGeometry.parseHex("#ff0000aa")
    #expect(rgba.r == 1)
    #expect(rgba.a == Double(0xaa) / 255.0)
    #expect(try BorderGeometry.resolve(.accent).b > 0)

    let w = BorderGeometry.effectiveWidth(configured: 4, increaseContrast: true)
    #expect(w >= 6)

    let border = BorderGeometry.borderFrame(windowFrame: (10, 20, 100, 50), width: 4)
    #expect(border.x == 6)
    #expect(border.width == 108)
    let hole = BorderGeometry.innerHole(borderFrame: border, width: 4)
    #expect(hole.width == 100)
}

@Test func systemPrefsBackupRestoreAgainstFakeDomain() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lattice-prefs-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let fake = DictionaryDefaultsDomain(storage: [
        SystemPrefsKey.enableTilingByEdge.rawValue: true,
        SystemPrefsKey.enableTilingByEdgeWindow.rawValue: true,
    ])
    // Use a backup that writes into a temp Application Support by swapping fileManager home — 
    // SystemPrefsBackup uses LayoutPersistence.applicationSupportDirectory.
    // For unit isolation, exercise DictionaryDefaultsDomain round-trip directly via apply/restore
    // with a custom domain factory and real temp support dir via HOME override is heavy;
    // instead verify snapshot encode + domain writes.

    let domains: [String: DictionaryDefaultsDomain] = [
        "com.apple.WindowManager": fake,
    ]
    let backup = SystemPrefsBackup(fileManager: .default) { name in
        domains[name] ?? DictionaryDefaultsDomain()
    }

    // May write into real App Support — clean up after.
    let snap = try backup.applyOverrides(disableEdgeTiling: true)
    #expect(snap.values[SystemPrefsKey.enableTilingByEdge.rawValue] == true)
    #expect(fake.object(forKey: SystemPrefsKey.enableTilingByEdge.rawValue) as? Bool == false)

    let restored = try backup.restore()
    #expect(restored?.cleanShutdown == true)
    #expect(fake.object(forKey: SystemPrefsKey.enableTilingByEdge.rawValue) as? Bool == true)

    try backup.clearBackup()
}

@Test func commandSocketProtocolRoundTrip() throws {
    let req = CommandSocketProtocol.Request(command: "doctor", args: [])
    let data = try CommandSocketProtocol.encodeRequest(req)
    let decoded = try CommandSocketProtocol.decodeRequest(data)
    #expect(decoded == req)

    let resp = CommandSocketProtocol.Response(ok: true, output: "OK")
    let rdata = try CommandSocketProtocol.encodeResponse(resp)
    #expect(try CommandSocketProtocol.decodeResponse(rdata) == resp)
}

@Test func socketURLAvoidsFixedTmp() {
    let url = CommandSocketProtocol.socketURL()
    #expect(!url.path.hasPrefix("/tmp/lattice"))
    #expect(url.path.contains("com.designbyadrian.lattice"))
}
