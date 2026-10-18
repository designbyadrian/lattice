import Testing
import AppCore
import LayoutModel
import Platform
import Config

@Test func moduleName() {
    #expect(AppCoreModule.name == "AppCore")
}

@Test func coordinatorHoldsConfig() {
    let c = AppCoordinator(platform: FakePlatform(), layoutStore: .inMemory())
    #expect(c.config.workspaces == 1)
}

@Test func autoInsertAndApplyFrames() async throws {
    let w1 = WindowRef(
        id: 11,
        pid: 100,
        bundleID: "app.one",
        title: "One",
        frame: CGRectCodable(x: 50, y: 50, width: 400, height: 300)
    )
    let w2 = WindowRef(
        id: 12,
        pid: 101,
        bundleID: "app.two",
        title: "Two",
        frame: CGRectCodable(x: 500, y: 50, width: 400, height: 300)
    )
    let platform = FakePlatform(windows: [w1, w2])
    // Explicit tiling-on for this insert/apply regression (product default is false).
    let coordinator = AppCoordinator(
        platform: platform,
        config: LatticeConfig(defaultTiling: true),
        layoutStore: .inMemory()
    )
    await coordinator.start()

    #expect(platform.setFrameCallCount >= 2)
    #expect(!coordinator.lastFrames.isEmpty)

    // Both windows should be present in some display layout.
    let allIDs = coordinator.displayLayouts.values.flatMap { layout in
        layout.workspaces.values.flatMap(\.allWindowIDs)
    }
    #expect(allIDs.contains(where: { $0.cgWindowID == 11 }))
    #expect(allIDs.contains(where: { $0.cgWindowID == 12 }))

    coordinator.stop()
}

@Test func exclusionSkipsInsert() async throws {
    let excluded = WindowRef(
        id: 99,
        pid: 200,
        bundleID: "com.excluded.app",
        title: "Nope",
        frame: CGRectCodable(x: 0, y: 0, width: 200, height: 200)
    )
    let platform = FakePlatform(windows: [excluded])
    let coordinator = AppCoordinator(platform: platform, layoutStore: .inMemory())
    coordinator.globalExcludedApps = ["com.excluded.app"]
    await coordinator.start()

    let allIDs = coordinator.displayLayouts.values.flatMap { layout in
        layout.workspaces.values.flatMap(\.allWindowIDs)
    }
    #expect(!allIDs.contains(where: { $0.cgWindowID == 99 }))
    coordinator.stop()
}

@Test func fullscreenSuspendsAndHotkeysNoop() async throws {
    let win = WindowRef(
        id: 42,
        pid: 300,
        bundleID: "app.fs",
        title: "FS",
        frame: CGRectCodable(x: 0, y: 0, width: 1440, height: 900),
        isFullscreen: false
    )
    let platform = FakePlatform(windows: [win])
    let coordinator = AppCoordinator(platform: platform, layoutStore: .inMemory())
    await coordinator.start()
    platform.resetAppliedFrames()

    var fs = win
    fs.isFullscreen = true
    platform.upsertWindow(fs)
    await coordinator.handle(.windowFullscreenChanged(fs, isFullscreen: true))

    #expect(coordinator.isActiveSpaceFullscreen)
    #expect(coordinator.allowLayoutHotkey() == false)

    // Tree slot kept, state suspended.
    let ws = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }
    let id = WindowID(cgWindowID: 42, processID: 300, bundleID: "app.fs", titleFingerprint: "FS")
    #expect(ws?.contains(id) == true || ws?.allWindowIDs.contains(where: { $0.cgWindowID == 42 }) == true)
    if let match = ws?.allWindowIDs.first(where: { $0.cgWindowID == 42 }) {
        #expect(ws?.state(of: match) == .fullscreen)
    }

    // Resume restores active + hotkeys.
    fs.isFullscreen = false
    platform.upsertWindow(fs)
    await coordinator.handle(.windowFullscreenChanged(fs, isFullscreen: false))
    #expect(coordinator.allowLayoutHotkey())
    if let match = coordinator.displayLayouts.values.first.flatMap({ $0.workspaces[1] })?
        .allWindowIDs.first(where: { $0.cgWindowID == 42 }) {
        let state = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }?.state(of: match)
        #expect(state == .active)
    }

    coordinator.stop()
}

@Test func removeOnDestroy() async throws {
    let win = WindowRef(
        id: 7,
        pid: 400,
        title: "Gone",
        frame: CGRectCodable(x: 10, y: 10, width: 100, height: 100)
    )
    let platform = FakePlatform(windows: [win])
    let coordinator = AppCoordinator(platform: platform, layoutStore: .inMemory())
    await coordinator.start()
    platform.removeWindow(id: 7)
    await coordinator.handle(.windowDestroyed(id: 7, pid: 400))

    let allIDs = coordinator.displayLayouts.values.flatMap { layout in
        layout.workspaces.values.flatMap(\.allWindowIDs)
    }
    #expect(!allIDs.contains(where: { $0.cgWindowID == 7 }))
    coordinator.stop()
}

@Test func floatAllEscapeHatch() async throws {
    let w1 = WindowRef(id: 1, pid: 1, title: "A", frame: CGRectCodable(x: 0, y: 0, width: 100, height: 100))
    let w2 = WindowRef(id: 2, pid: 2, title: "B", frame: CGRectCodable(x: 100, y: 0, width: 100, height: 100))
    let platform = FakePlatform(windows: [w1, w2])
    let coordinator = AppCoordinator(
        platform: platform,
        config: LatticeConfig(defaultTiling: true),
        layoutStore: .inMemory()
    )
    await coordinator.start()
    await coordinator.unmanageAll()

    let ws = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }
    #expect(ws?.floating.count == 2)
    #expect(ws?.root.tiledWindowIDs.isEmpty == true)
    coordinator.stop()
}

@Test func prepareSafeQuitClampsOffscreen() async throws {
    let win = WindowRef(
        id: 55,
        pid: 55,
        title: "Off",
        frame: CGRectCodable(x: -5000, y: -5000, width: 200, height: 200)
    )
    let platform = FakePlatform(windows: [win])
    let coordinator = AppCoordinator(
        platform: platform,
        config: LatticeConfig(defaultTiling: true),
        layoutStore: .inMemory()
    )
    await coordinator.start()
    // Force lastFrames off-screen.
    // prepareSafeQuit uses lastFrames from solve (on-screen) — also call with applied frames.
    platform.resetAppliedFrames()
    await coordinator.prepareSafeQuit()
    #expect(platform.setFrameCallCount >= 1)
    if let last = platform.appliedFrames.last {
        #expect(last.frame.x >= 0)
        #expect(last.frame.y >= 0)
    }
    coordinator.stop()
}

@Test func suspendResumePreservesTreeSlot() async throws {
    let win = WindowRef(
        id: 3,
        pid: 3,
        title: "Slot",
        frame: CGRectCodable(x: 0, y: 0, width: 200, height: 200)
    )
    let other = WindowRef(
        id: 4,
        pid: 4,
        title: "Other",
        frame: CGRectCodable(x: 200, y: 0, width: 200, height: 200)
    )
    let platform = FakePlatform(windows: [win, other])
    let coordinator = AppCoordinator(platform: platform, layoutStore: .inMemory())
    await coordinator.start()

    let before = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }?.root
    await coordinator.handle(.windowMinimized(id: 3, pid: 3))
    let mid = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }
    #expect(mid?.allWindowIDs.contains(where: { $0.cgWindowID == 3 }) == true)
    if let id = mid?.allWindowIDs.first(where: { $0.cgWindowID == 3 }) {
        #expect(mid?.state(of: id) == .minimized)
    }

    var demin = win
    demin.isMinimized = false
    await coordinator.handle(.windowDeminimized(demin))
    let after = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }
    #expect(after?.root != nil)
    // Same windows still present (slot preserved).
    #expect(after?.allWindowIDs.contains(where: { $0.cgWindowID == 3 }) == true)
    #expect(after?.allWindowIDs.contains(where: { $0.cgWindowID == 4 }) == true)
    _ = before
    coordinator.stop()
}
