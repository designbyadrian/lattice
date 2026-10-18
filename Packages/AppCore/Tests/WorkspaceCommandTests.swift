import Testing
import AppCore
import Config
import LayoutModel
import Platform

@Test func workspaceCommandShowsHUDUnderSafetyNet() async {
    let spaces = FakeSpacesController(backend: .currentSpaceOnly)
    let platform = FakePlatform(spacesController: spaces)
    let coordinator = AppCoordinator(platform: platform)
    await coordinator.execute(.workspace(.number(2)))
    #expect(coordinator.lastHUDMessage == SpacesSafetyNetCopy.hudMessage)
    #expect(spaces.switches.isEmpty)
}

@Test func workspaceSwitchUsesBoundSpace() async {
    let spaces = FakeSpacesController(
        backend: .native,
        snapshots: [
            DisplaySnapshot(
                uuid: "fake-display-1",
                nameForPatterns: "Fake",
                spaces: [
                    SpaceSnapshot(id: SpaceID(rawValue: 1)),
                    SpaceSnapshot(id: SpaceID(rawValue: 2)),
                ],
                current: SpaceID(rawValue: 1)
            )
        ],
        binding: WorkspaceSpaceBinding(
            binding: [1: SpaceID(rawValue: 1), 2: SpaceID(rawValue: 2)],
            ownedSpaces: [SpaceID(rawValue: 2)]
        )
    )
    let platform = FakePlatform(spacesController: spaces)
    var config = LatticeConfig.default
    config.workspaces = 2
    let coordinator = AppCoordinator(platform: platform, config: config)
    await coordinator.start()
    await coordinator.execute(.workspace(.number(2)))
    #expect(spaces.switches.contains(where: { $0.0 == SpaceID(rawValue: 2) }))
    #expect(coordinator.activeWorkspaceNumber["fake-display-1"] == 2)
    coordinator.stop()
}

@Test func workspaceBackAndForthToggles() async {
    let spaces = FakeSpacesController(
        backend: .native,
        snapshots: [
            DisplaySnapshot(
                uuid: "fake-display-1",
                nameForPatterns: "Fake",
                spaces: [
                    SpaceSnapshot(id: SpaceID(rawValue: 1)),
                    SpaceSnapshot(id: SpaceID(rawValue: 2)),
                ],
                current: SpaceID(rawValue: 1)
            )
        ],
        binding: WorkspaceSpaceBinding(
            binding: [1: SpaceID(rawValue: 1), 2: SpaceID(rawValue: 2)],
            ownedSpaces: []
        )
    )
    let platform = FakePlatform(spacesController: spaces)
    var config = LatticeConfig.default
    config.workspaces = 2
    let coordinator = AppCoordinator(platform: platform, config: config)
    await coordinator.start()
    await coordinator.execute(.workspace(.number(2)))
    await coordinator.execute(.workspaceBackAndForth)
    #expect(coordinator.activeWorkspaceNumber["fake-display-1"] == 1)
    coordinator.stop()
}

@Test func moveWindowToWorkspaceRecordsMove() async {
    let spaces = FakeSpacesController(
        backend: .native,
        snapshots: [
            DisplaySnapshot(
                uuid: "fake-display-1",
                nameForPatterns: "Fake",
                spaces: [
                    SpaceSnapshot(id: SpaceID(rawValue: 1)),
                    SpaceSnapshot(id: SpaceID(rawValue: 2)),
                ],
                current: SpaceID(rawValue: 1)
            )
        ],
        binding: WorkspaceSpaceBinding(
            binding: [1: SpaceID(rawValue: 1), 2: SpaceID(rawValue: 2)],
            ownedSpaces: []
        )
    )
    let win = WindowRef(
        id: 9,
        pid: 9,
        title: "W",
        frame: CGRectCodable(x: 0, y: 0, width: 100, height: 100)
    )
    let platform = FakePlatform(windows: [win], spacesController: spaces)
    var config = LatticeConfig.default
    config.workspaces = 2
    let coordinator = AppCoordinator(platform: platform, config: config)
    await coordinator.start()
    await coordinator.execute(.moveWindowToWorkspace(.number(2), follow: false))
    #expect(spaces.movedWindows.contains(where: { $0.ids == [9] && $0.space.rawValue == 2 }))
    coordinator.stop()
}

@Test func spacesReconcileAdoptsCurrentOnLaunch() async {
    let spaces = FakeSpacesController(
        backend: .native,
        snapshots: [
            DisplaySnapshot(
                uuid: "fake-display-1",
                nameForPatterns: "Fake",
                spaces: [SpaceSnapshot(id: SpaceID(rawValue: 7))],
                current: SpaceID(rawValue: 7)
            )
        ]
    )
    let platform = FakePlatform(spacesController: spaces)
    let coordinator = AppCoordinator(platform: platform, config: .default)
    await coordinator.start()
    #expect(coordinator.spaceBinding.binding[1] == SpaceID(rawValue: 7))
    coordinator.stop()
}

@Test func spacesMenuNoticeExposed() {
    let spaces = FakeSpacesController(backend: .currentSpaceOnly)
    let platform = FakePlatform(spacesController: spaces)
    let coordinator = AppCoordinator(platform: platform)
    #expect(coordinator.spacesMenuNotice == SpacesSafetyNetCopy.menuNotice)
}
