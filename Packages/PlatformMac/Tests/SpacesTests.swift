import Testing
import Foundation
import LayoutModel
import Platform
import PlatformMac

// MARK: - Capability probe

@Test func probeSelectsNativeWhenAllSymbolsPresent() {
    let result = SpacesCapabilityProbe.probe(
        symbols: FakeSpacesSymbolTable.allRequired,
        osVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0),
        osBuild: "test-15",
        matrixFailedMajors: []
    )
    #expect(result.backend == .native)
    #expect(result.missingSymbols.isEmpty)
    #expect(result.notice == nil)
}

@Test func probeFallsBackWhenSymbolsMissing() {
    let result = SpacesCapabilityProbe.probe(
        symbols: FakeSpacesSymbolTable.queriesOnly,
        osVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0),
        osBuild: "test-15",
        matrixFailedMajors: []
    )
    #expect(result.backend == .currentSpaceOnly)
    #expect(!result.missingSymbols.isEmpty)
    #expect(result.notice != nil)
}

@Test func probeFallsBackWhenMatrixFailed() {
    let result = SpacesCapabilityProbe.probe(
        symbols: FakeSpacesSymbolTable.allRequired,
        osVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0),
        osBuild: "test-26.4",
        matrixFailedMajors: [26]
    )
    #expect(result.backend == .currentSpaceOnly)
    #expect(result.matrixFailed)
}

// MARK: - Dock swipe golden bytes

@Test func dockSwipeGoldenBytesPre27() {
    let left = DockSwipeBuilder.build(direction: .left, osMajor: 15)
    let right = DockSwipeBuilder.build(direction: .right, osMajor: 15)
    #expect(left.began.prefix(4) == Data([0x4C, 0x54, 0x53, 0x57]))
    #expect(left.began.count == 14) // no IOHID trailer
    #expect(right.began.count == 14)
    #expect(left.began != right.began)

    // Version field (UInt16 LE) at offset 4 == 1
    #expect(left.began[4] == 1)
    #expect(left.began[5] == 0)
}

@Test func dockSwipeGoldenBytes27Extended() {
    let payload = DockSwipeBuilder.build(direction: .left, osMajor: 27)
    #expect(payload.began.count == 22) // +8 IOHID trailer
    #expect(payload.began[4] == 2) // version 2
    #expect(Array(payload.began.suffix(8)) == [0x49, 0x4F, 0x48, 0x49, 0x44, 0x01, 0x00, 0x00])

    // Sign convention differs vs pre-27 for the same direction.
    let older = DockSwipeBuilder.build(direction: .left, osMajor: 15)
    let velNew = payload.began.subdata(in: 8..<12)
    let velOld = older.began.subdata(in: 8..<12)
    #expect(velNew != velOld)
}

@Test func dockSwipeDirectionsCount() {
    #expect(DockSwipeBuilder.directions(from: 0, to: 0).isEmpty)
    #expect(DockSwipeBuilder.directions(from: 0, to: 2) == [.right, .right])
    #expect(DockSwipeBuilder.directions(from: 3, to: 1) == [.left, .left])
}

@Test func dockSwipeSwitcherDryRunRecordsPayloads() async {
    let switcher = DockSwipeSwitcher(osMajor: 15, dryRun: true)
    await switcher.swipeSteps([.left, .right], stepDelayNs: 0)
    #expect(switcher.lastPayloads.count == 2)
}

// MARK: - Managed display space parsing

@Test func parseSpaceDetectsFullscreenType() {
    let user = ManagedDisplaySpaces.parseSpace(["id64": 10, "type": 0])
    let fs = ManagedDisplaySpaces.parseSpace(["id64": 11, "type": 4])
    #expect(user?.isFullscreen == false)
    #expect(fs?.isFullscreen == true)
    #expect(fs?.isBindable == false)
}

@Test func parseDisplayEntryBuildsSnapshot() {
    let entry: [String: Any] = [
        "Display Identifier": "ABC",
        "Spaces": [
            ["id64": 1, "type": 0],
            ["id64": 2, "type": 4],
        ],
        "Current Space": ["id64": 1, "type": 0],
    ]
    let snap = ManagedDisplaySpaces.parseDisplayEntry(
        entry,
        displayNamesByUUID: ["ABC": "Built-in"]
    )
    #expect(snap?.uuid == "ABC")
    #expect(snap?.nameForPatterns == "Built-in")
    #expect(snap?.spaces.count == 2)
    #expect(snap?.current == SpaceID(rawValue: 1))
}

// MARK: - Persistence

@Test func spacesBindingPersistenceRoundTrip() throws {
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent("lattice-spaces-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: temp) }

    // Point Application Support at temp by writing directly via helpers with custom URL path —
    // SpacesPersistence uses real App Support; exercise encode/decode parity here.
    let binding = WorkspaceSpaceBinding(
        binding: [1: SpaceID(rawValue: 42), 2: SpaceID(rawValue: 43)],
        ownedSpaces: [SpaceID(rawValue: 43)]
    )
    let data = try JSONEncoder().encode(binding)
    let url = temp.appendingPathComponent(SpacesPersistence.bindingFileName)
    try data.write(to: url)
    let decoded = try JSONDecoder().decode(WorkspaceSpaceBinding.self, from: Data(contentsOf: url))
    #expect(decoded == binding)
    #expect(SpacesPersistence.appSupportFolderName == "Lattice")
}

// MARK: - Controller safety net

@Test func macSpacesControllerCurrentSpaceOnlyHUD() {
    let probe = SpacesProbeResult(
        backend: .currentSpaceOnly,
        osMajor: 15,
        osBuild: "test",
        missingSymbols: ["SLSBridgedSpaceCreateOperation"],
        notice: "missing"
    )
    let controller = MacSpacesController(
        symbols: FakeSpacesSymbolTable.queriesOnly,
        probe: probe,
        dryRunSwipe: true
    )
    #expect(controller.spacesBackend == .currentSpaceOnly)
    #expect(controller.hudMessageIfUnavailable == SpacesSafetyNetCopy.hudMessage)
    #expect(controller.spacesMenuNotice == SpacesSafetyNetCopy.menuNotice)
}

@Test func spacesMatrixDocPath() {
    #expect(PlatformMacModule.spacesMatrixDoc == "docs/spaces-matrix.md")
}
