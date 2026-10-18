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
    await coordinator.handle(.windowFocused(w1))
    platform.resetAppliedFrames()

    await coordinator.execute(.zoom(.window, toggle: false))
    let ws = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }
    // Framed window: camera is that leaf's world rect (not home).
    #expect(ws?.camera != .home)
    #expect(ws?.camera.edges.width ?? 1 < 1)

    await coordinator.execute(.zoom(.all, toggle: false))
    let ws2 = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }
    #expect(ws2?.camera == .home || ws2?.camera == .showAll)
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
    await coordinator.handle(.windowFocused(w1))

    await coordinator.execute(.zoom(.window, toggle: false))
    let zoomed = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }?.camera
    #expect(zoomed != .home)

    await coordinator.execute(.zoom(.all, toggle: false))
    await coordinator.execute(.history(.back))
    let afterBack = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }?.camera
    #expect(afterBack == zoomed)

    await coordinator.execute(.history(.forward))
    let afterForward = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }?.camera
    #expect(afterForward == .home || afterForward == .showAll)
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

@Test func floatFirstDoesNotTileOnLaunch() async throws {
    let w1 = WindowRef(
        id: 8, pid: 18, bundleID: "a.eight", title: "Eight",
        frame: CGRectCodable(x: 40, y: 40, width: 300, height: 200)
    )
    let platform = FakePlatform(windows: [w1])
    let coordinator = AppCoordinator(
        platform: platform,
        config: LatticeConfig(defaultTiling: false),
        layoutStore: .inMemory()
    )
    await coordinator.start()
    let ws = coordinator.displayLayouts.values.first.flatMap { $0.workspaces[1] }
    #expect(ws?.root.tiledWindowIDs.isEmpty == true)
    #expect(ws?.floatWins.count == 1)
    #expect(ws?.floatWins.first?.window.identity.cgWindowID == 8)
    coordinator.stop()
}
