import Foundation
import Testing
import Platform

private struct DiscoveryFixture: Codable {
    var cgWindows: [CGWindowInfoSnapshot]
    var axWindows: [AXWindowInfoSnapshot]
}

private func loadFixture(_ name: String) throws -> DiscoveryFixture {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
    )
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(DiscoveryFixture.self, from: data)
}

@Test func cgFilterKeepsLayerZeroOnscreenOnly() throws {
    let fixture = try loadFixture("discovery-mixed")
    let filtered = WindowDiscoveryFilter.filterCGWindows(fixture.cgWindows)
    let ids = Set(filtered.map(\.windowNumber))
    #expect(ids.contains(101))
    #expect(ids.contains(102))
    #expect(ids.contains(300))
    #expect(!ids.contains(200)) // menu extra layer 25
    #expect(!ids.contains(201)) // spotlight layer 20
    #expect(!ids.contains(301)) // offscreen
}

@Test func axFilterKeepsStandardWindowsOnly() throws {
    let fixture = try loadFixture("discovery-mixed")
    let filtered = WindowDiscoveryFilter.filterAXWindows(fixture.axWindows)
    let titles = Set(filtered.map(\.title))
    #expect(titles == ["Apple", "bash — 80x24"])
    #expect(!titles.contains("Save As"))
    #expect(!titles.contains("Popover"))
    #expect(!titles.contains("Sheet"))
}

@Test func discoverMatchesPidFrameTitle() throws {
    let fixture = try loadFixture("discovery-mixed")
    let refs = WindowDiscoveryFilter.discoverWindows(
        cgWindows: fixture.cgWindows,
        axWindows: fixture.axWindows,
        bundleIDForPID: { pid in
            switch pid {
            case 4242: return "com.apple.Safari"
            case 5151: return "com.apple.Terminal"
            default: return nil
            }
        }
    )
    #expect(refs.count == 2)
    let byTitle = Dictionary(uniqueKeysWithValues: refs.map { ($0.title, $0) })
    #expect(byTitle["Apple"]?.id == 101)
    #expect(byTitle["Apple"]?.bundleID == "com.apple.Safari")
    #expect(byTitle["bash — 80x24"]?.id == 300)
}

@Test func discoverIgnoresElectronFloatingChrome() throws {
    let fixture = try loadFixture("discovery-electronish")
    let refs = WindowDiscoveryFilter.discoverWindows(
        cgWindows: fixture.cgWindows,
        axWindows: fixture.axWindows
    )
    #expect(refs.count == 1)
    #expect(refs[0].id == 9001)
    #expect(refs[0].title == "main.ts — lattice")
}

@Test func experimentalAxWindowIDStubOff() {
    #expect(ExperimentalAXWindowID.cgWindowIDIfEnabled(flags: .default) == nil)
    var flags = ExperimentalFlags()
    flags.axWindowID = true
    #expect(ExperimentalAXWindowID.cgWindowIDIfEnabled(flags: flags) == nil)
}

@Test func fakePlatformRecordsFrames() async throws {
    let platform = FakePlatform(windows: [
        WindowRef(
            id: 1,
            pid: 10,
            title: "A",
            frame: CGRectCodable(x: 0, y: 0, width: 100, height: 100)
        )
    ])
    let frame = CGRectCodable(x: 10, y: 20, width: 300, height: 200)
    try await platform.setFrame(frame, for: 1, pid: 10)
    #expect(platform.setFrameCallCount == 1)
    #expect(platform.windows[0].frame == frame)

    final class Flag: @unchecked Sendable {
        var value = false
    }
    let sawWake = Flag()
    platform.startObserving { event in
        if case .didWake = event { sawWake.value = true }
    }
    platform.emit(.didWake)
    #expect(sawWake.value)
}
