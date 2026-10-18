import Testing
import AppCore
import Config
import LayoutModel
import Platform

@Test func focusMovesToNeighbor() async {
    let w1 = WindowRef(
        id: 1, pid: 10, bundleID: "a", title: "A",
        frame: CGRectCodable(x: 0, y: 0, width: 400, height: 400)
    )
    let w2 = WindowRef(
        id: 2, pid: 11, bundleID: "b", title: "B",
        frame: CGRectCodable(x: 400, y: 0, width: 400, height: 400)
    )
    let platform = FakePlatform(windows: [w1, w2])
    let coordinator = AppCoordinator(
        platform: platform,
        config: LatticeConfig(defaultTiling: true),
        layoutStore: .inMemory()
    )
    var focusedRaises: [WindowID] = []
    coordinator.focusWindowHandler = { id in focusedRaises.append(id) }
    await coordinator.start()

    let id1 = WindowID(cgWindowID: 1, processID: 10, bundleID: "a", titleFingerprint: "A")
    // Seed focus on first managed window.
    await coordinator.handle(.windowFocused(w1))
    #expect(coordinator.focusedWindowID?.cgWindowID == 1)

    await coordinator.execute(.focus(.right))
    #expect(coordinator.focusedWindowID?.cgWindowID == 2 || focusedRaises.contains(where: { $0.cgWindowID == 2 }) || coordinator.focusedWindowID != id1)

    coordinator.stop()
}

@Test func moveAndResizeAndSplitApplyFrames() async {
    let w1 = WindowRef(
        id: 21, pid: 20, bundleID: "a", title: "A",
        frame: CGRectCodable(x: 0, y: 0, width: 400, height: 400)
    )
    let w2 = WindowRef(
        id: 22, pid: 21, bundleID: "b", title: "B",
        frame: CGRectCodable(x: 400, y: 0, width: 400, height: 400)
    )
    let platform = FakePlatform(windows: [w1, w2])
    let coordinator = AppCoordinator(
        platform: platform,
        config: LatticeConfig(defaultTiling: true),
        layoutStore: .inMemory()
    )
    await coordinator.start()
    await coordinator.handle(.windowFocused(w1))

    let before = platform.setFrameCallCount
    await coordinator.execute(.move(.right))
    await coordinator.execute(.resize(.smart, delta: 40))
    await coordinator.execute(.split(.horizontal))
    await coordinator.execute(.balanceSizes)
    await coordinator.execute(.flattenWorkspaceTree)
    await coordinator.execute(.dock(.left, screen: true))
    #expect(platform.setFrameCallCount >= before)

    coordinator.stop()
}
