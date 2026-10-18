import Testing
import AppCore
import LayoutEngine
import LayoutModel
import Platform
import Config

private func tilingCoordinator(platform: FakePlatform) -> AppCoordinator {
    AppCoordinator(
        platform: platform,
        config: LatticeConfig(defaultTiling: true),
        layoutStore: .inMemory()
    )
}

@Test func zoomAllUpdatesCameraAndAppliesFrames() async throws {
    let w1 = WindowRef(
        id: 1, pid: 10, bundleID: "a.one", title: "One",
        frame: CGRectCodable(x: 0, y: 0, width: 200, height: 200)
    )
    let w2 = WindowRef(
        id: 2, pid: 11, bundleID: "a.two", title: "Two",
        frame: CGRectCodable(x: 300, y: 0, width: 200, height: 200)
    )
    let platform = FakePlatform(windows: [w1, w2])
    let coordinator = tilingCoordinator(platform: platform)
    await coordinator.start()
    platform.resetAppliedFrames()

    await coordinator.execute(.zoom(.window, toggle: false))
    let ws = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }
    #expect(ws?.camera.zoom == 1)

    await coordinator.execute(.zoom(.all, toggle: false))
    let ws2 = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }
    #expect(ws2?.camera == .showAll)
    #expect(platform.setFrameCallCount >= 1)
    coordinator.stop()
}

@Test func historyBackForwardRoundTrip() async throws {
    let w1 = WindowRef(
        id: 3, pid: 12, bundleID: "a.three", title: "Three",
        frame: CGRectCodable(x: 0, y: 0, width: 200, height: 200)
    )
    let platform = FakePlatform(windows: [w1])
    let coordinator = tilingCoordinator(platform: platform)
    await coordinator.start()

    await coordinator.execute(.zoom(.window, toggle: false))
    let zoomed = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }?.camera
    #expect(zoomed?.zoom == 1)

    await coordinator.execute(.zoom(.all, toggle: false))
    await coordinator.execute(.history(.back))
    let afterBack = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }?.camera
    #expect(afterBack?.zoom == 1)

    await coordinator.execute(.history(.forward))
    let afterForward = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }?.camera
    #expect(afterForward == .showAll)
    coordinator.stop()
}

@Test func reduceMotionJumpsWithoutLongAnimation() async throws {
    let w1 = WindowRef(
        id: 5, pid: 14, bundleID: "a.five", title: "Five",
        frame: CGRectCodable(x: 0, y: 0, width: 200, height: 200)
    )
    let platform = FakePlatform(windows: [w1], accessibilityReduceMotion: true)
    let coordinator = tilingCoordinator(platform: platform)
    await coordinator.start()
    platform.resetAppliedFrames()
    await coordinator.execute(.zoom(.all, toggle: false))
    #expect(platform.setFrameCallCount >= 1)
    #expect(!platform.frameAnimator.isAnimating)
    coordinator.stop()
}

@Test func buildOverviewTilesCollapseBelowThreshold() {
    let a = WindowID(cgWindowID: 1, processID: 1, bundleID: "app.a", titleFingerprint: "A")
    let b = WindowID(cgWindowID: 2, processID: 2, bundleID: "app.b", titleFingerprint: "B")
    let root = Node.split(.equal(axis: .horizontal, children: [
        .panel(PanelNode(window: a)),
        .panel(PanelNode(window: b)),
    ]))
    var ws = Workspace(root: root)
    ws.camera = .showAll
    // Tiny display so panels fall below window collapse threshold.
    let display = Rect(x: 0, y: 0, width: 100, height: 60)
    let engine = CameraEngine(workspace: ws, displayRect: display)
    let thresholds = CollapseThresholds(
        windowMinWidth: 120, windowMinHeight: 80,
        groupMinWidth: 160, groupMinHeight: 100
    )
    let tiles = AppCoordinator.buildOverviewTiles(engine: engine, thresholds: thresholds)
    #expect(tiles.contains(where: { $0.presentation == "windowTile" || $0.presentation == "groupTile" }))
}
