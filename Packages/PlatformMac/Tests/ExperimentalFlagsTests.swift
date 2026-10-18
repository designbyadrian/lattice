import ApplicationServices
import Foundation
import Platform
import PlatformMac
import Testing

@Test func experimentalFlagsDefaultOffOnServer() {
    let session = ExperimentalMultitouchSession(symbols: FakeMultitouchSymbolTable.empty)
    let server = MacWindowServer(multitouchSession: session)
    #expect(server.experimentalFlags.axWindowID == false)
    #expect(server.experimentalFlags.multitouch == false)
    #expect(session.isArmed == false)
}

@Test func axWindowIDMissingSymbolAutoDisables() {
    var flags = ExperimentalFlags(axWindowID: true, multitouch: false)
    let dummy = AXUIElementCreateApplication(getpid())
    let id = AXWindowIDShortcut.cgWindowID(
        for: dummy,
        flags: &flags,
        symbols: FakeAXWindowIDSymbolTable(present: false)
    )
    #expect(id == nil)
    #expect(flags.axWindowID == false)
}

@Test func multitouchMissingSymbolsAutoDisables() {
    var flags = ExperimentalFlags(axWindowID: false, multitouch: true)
    let session = ExperimentalMultitouchSession(symbols: FakeMultitouchSymbolTable.empty)
    session.sync(flags: &flags)
    #expect(flags.multitouch == false)
    #expect(session.isArmed == false)
}

@Test func multitouchArmsWhenSymbolsPresent() {
    var flags = ExperimentalFlags(axWindowID: false, multitouch: true)
    let session = ExperimentalMultitouchSession(symbols: FakeMultitouchSymbolTable.allRequired)
    session.sync(flags: &flags)
    #expect(flags.multitouch == true)
    #expect(session.isArmed == true)
}

@Test func discoveryWorksWithAxWindowIDFlagOff() {
    let cg = [
        CGWindowInfoSnapshot(
            windowNumber: 42,
            ownerPID: 100,
            ownerName: "Test",
            name: "Hello",
            layer: 0,
            bounds: CGRectCodable(x: 0, y: 0, width: 200, height: 100),
            isOnscreen: true
        ),
    ]
    let snap = AXWindowInfoSnapshot(
        pid: 100,
        title: "Hello",
        role: "AXWindow",
        subrole: "AXStandardWindow",
        frame: CGRectCodable(x: 0, y: 0, width: 200, height: 100)
    )
    let live = AXWindowLive(element: AXUIElementCreateApplication(100), snapshot: snap)
    var flags = ExperimentalFlags.default
    #expect(flags.axWindowID == false)

    let refs = MacWindowDiscovery.discoverManagedWindows(
        cgWindows: cg,
        axLives: [live],
        experimentalFlags: &flags,
        axSymbols: FakeAXWindowIDSymbolTable(present: false)
    )
    #expect(refs.count == 1)
    #expect(refs[0].id == 42)
    #expect(refs[0].title == "Hello")
    #expect(flags.axWindowID == false)
}

@Test func discoveryFallsBackWhenShortcutSymbolsMissing() {
    let cg = [
        CGWindowInfoSnapshot(
            windowNumber: 7,
            ownerPID: 50,
            name: "Doc",
            layer: 0,
            bounds: CGRectCodable(x: 10, y: 10, width: 100, height: 80),
            isOnscreen: true
        ),
    ]
    let snap = AXWindowInfoSnapshot(
        pid: 50,
        title: "Doc",
        role: "AXWindow",
        subrole: "AXStandardWindow",
        frame: CGRectCodable(x: 10, y: 10, width: 100, height: 80)
    )
    let live = AXWindowLive(element: AXUIElementCreateApplication(50), snapshot: snap)
    var flags = ExperimentalFlags(axWindowID: true, multitouch: false)

    let refs = MacWindowDiscovery.discoverManagedWindows(
        cgWindows: cg,
        axLives: [live],
        experimentalFlags: &flags,
        axSymbols: FakeAXWindowIDSymbolTable(present: false)
    )
    #expect(refs.count == 1)
    #expect(refs[0].id == 7)
    #expect(flags.axWindowID == false)
}
