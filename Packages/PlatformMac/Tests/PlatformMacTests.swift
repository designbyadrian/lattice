import Testing
import Foundation
import CoreGraphics
import Platform
import PlatformMac
import Config

@Test func moduleName() {
    #expect(PlatformMacModule.name == "PlatformMac")
}

@Test func macPermissionsPreflightAPIsExist() {
    let perms = MacPermissions()
    _ = perms.isAccessibilityTrusted
    _ = perms.hasScreenRecordingAccess
}

@Test func displayUUIDHelperHandlesBogusID() {
    let uuid = MacDisplays.uuidString(for: 0)
    _ = uuid
}

@Test func windowServerConforms() async {
    let server = MacWindowServer()
    #expect(server.experimentalFlags.axWindowID == false)
    let displays = await server.listDisplays()
    _ = displays
}

// MARK: - Active event tap policy

@Test func rejectsListenOnlyTapWithKeyboardInMask() throws {
    let mask = ActiveEventTap.keyboardEventMask
    #expect(throws: ActiveEventTap.TapError.listenOnlyWithKeyboardForbidden) {
        try ActiveEventTap.validate(mask: mask, listenOnly: true)
    }
    #expect(throws: ActiveEventTap.TapError.listenOnlyWithKeyboardForbidden) {
        try ActiveEventTap(
            mask: mask,
            listenOnly: true,
            dryRun: true,
            handler: { Unmanaged.passUnretained($0) }
        )
    }
}

@Test func allowsActiveTapWithKeyboard() throws {
    try ActiveEventTap.validate(mask: ActiveEventTap.defaultMask, listenOnly: false)
    let tap = try ActiveEventTap(
        mask: ActiveEventTap.defaultMask,
        listenOnly: false,
        dryRun: true,
        handler: { Unmanaged.passUnretained($0) }
    )
    #expect(tap.isEnabled)
    #expect(!tap.listenOnly)
    tap.stop()
}

@Test func allowsListenOnlyWithoutKeyboard() throws {
    let mouseOnly: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
    try ActiveEventTap.validate(mask: mouseOnly, listenOnly: true)
    let tap = try ActiveEventTap(
        mask: mouseOnly,
        listenOnly: true,
        dryRun: true,
        handler: { Unmanaged.passUnretained($0) }
    )
    #expect(tap.listenOnly)
    tap.stop()
}

@Test func timeoutReEnableIncrementsCounter() throws {
    let tap = try ActiveEventTap(
        mask: ActiveEventTap.keyboardEventMask,
        dryRun: true,
        handler: { Unmanaged.passUnretained($0) }
    )
    tap.handleTapDisabled()
    tap.handleTapDisabled()
    #expect(tap.timeoutDisableCount == 2)
    #expect(tap.timeoutsInCurrentMinute == 2)
    #expect(tap.isEnabled)
}

// MARK: - Safety net

@Test func safetyNetDisablesOnlyThreeFeatures() {
    let reduced = InputSafetyNetState.reduced(reason: "test")
    #expect(reduced.disablesModifierDrag)
    #expect(reduced.disablesPinchOverApps)
    #expect(reduced.disablesLeftRightModifiers)

    let fromFail = InputSafetyNetState.from(
        tapCreated: false,
        inputMonitoringPrompted: false,
        osMajor: 15
    )
    #expect(fromFail.reducedInputFeatures)

    let fromPrompt = InputSafetyNetState.from(
        tapCreated: true,
        inputMonitoringPrompted: true,
        osMajor: 26
    )
    #expect(fromPrompt.reducedInputFeatures)

    let full = InputSafetyNetState.from(
        tapCreated: true,
        inputMonitoringPrompted: false,
        osMajor: 14
    )
    #expect(!full.reducedInputFeatures)
}

@Test func carbonHotkeyFallbackBookkeeping() {
    let fb = CarbonHotkeyFallback()
    #expect(!fb.isEnabled)
    fb.enable()
    #expect(fb.registerStub(id: 1, keyCode: 0, modifiers: 0))
    #expect(fb.registeredCount == 1)
    fb.disable()
    #expect(!fb.registerStub(id: 2, keyCode: 0, modifiers: 0))
}

// MARK: - EventClassifier

@Test func unboundKeysAlwaysPass() {
    let c = EventClassifier()
    let event = ClassifiableEvent(
        kind: .keyDown,
        key: "a",
        flags: ClassifierFlags(option: true)
    )
    #expect(c.classify(event) == .pass)
}

@Test func boundFocusIsCommand() {
    let c = EventClassifier()
    let event = ClassifiableEvent(
        kind: .keyDown,
        key: "h",
        flags: ClassifierFlags(option: true, device: .leftOption)
    )
    let result = c.classify(event)
    guard case .command(let cmds) = result else {
        Issue.record("expected command, got \(result)")
        return
    }
    #expect(cmds == [.focus(.left)])
}

@Test func boundKeyUpIsSwallowed() {
    let c = EventClassifier()
    let event = ClassifiableEvent(
        kind: .keyUp,
        key: "h",
        flags: ClassifierFlags(option: true)
    )
    #expect(c.classify(event) == .swallow)
}

@Test func leftRightModifierPolicy() {
    var config = LatticeConfig.default
    config.modifiers.alt = .left
    let c = EventClassifier(config: config)

    let rightOnly = ClassifiableEvent(
        kind: .keyDown,
        key: "h",
        flags: ClassifierFlags(option: true, device: .rightOption)
    )
    #expect(c.classify(rightOnly) == .pass)

    let left = ClassifiableEvent(
        kind: .keyDown,
        key: "h",
        flags: ClassifierFlags(option: true, device: .leftOption)
    )
    guard case .command = c.classify(left) else {
        Issue.record("left alt should match")
        return
    }
}

@Test func safetyNetIgnoresLeftRightDistinction() {
    var config = LatticeConfig.default
    config.modifiers.alt = .left
    let c = EventClassifier(
        config: config,
        safetyNet: .reduced(reason: "test")
    )
    let rightOnly = ClassifiableEvent(
        kind: .keyDown,
        key: "h",
        flags: ClassifierFlags(option: true, device: .rightOption)
    )
    guard case .command = c.classify(rightOnly) else {
        Issue.record("safety net should ignore side")
        return
    }
}

@Test func modifierDragSwallowsOverAppWindow() {
    let c = EventClassifier()
    let down = ClassifiableEvent(
        kind: .leftMouseDown,
        flags: ClassifierFlags(option: true),
        overAppWindow: true
    )
    #expect(c.classify(down) == .swallow)

    let noMod = ClassifiableEvent(
        kind: .leftMouseDown,
        flags: ClassifierFlags(),
        overAppWindow: true
    )
    #expect(c.classify(noMod) == .pass)

    let notOver = ClassifiableEvent(
        kind: .leftMouseDown,
        flags: ClassifierFlags(option: true),
        overAppWindow: false
    )
    #expect(c.classify(notOver) == .pass)
}

@Test func safetyNetPassesModifierDrag() {
    let c = EventClassifier(safetyNet: .reduced(reason: "test"))
    let down = ClassifiableEvent(
        kind: .leftMouseDown,
        flags: ClassifierFlags(option: true),
        overAppWindow: true
    )
    #expect(c.classify(down) == .pass)
}

@Test func pinchWithModifierOverAppSwallows() {
    let c = EventClassifier()
    let pinch = ClassifiableEvent(
        kind: .magnify,
        flags: ClassifierFlags(control: true, option: true),
        overAppWindow: true
    )
    #expect(c.classify(pinch) == .swallow)

    let noMod = ClassifiableEvent(
        kind: .magnify,
        flags: ClassifierFlags(),
        overAppWindow: true
    )
    #expect(c.classify(noMod) == .pass)
}

@Test func workspaceAndDockBindings() {
    let c = EventClassifier()
    let ws = ClassifiableEvent(
        kind: .keyDown,
        key: "3",
        flags: ClassifierFlags(option: true)
    )
    guard case .command(let wsCmds) = c.classify(ws) else {
        Issue.record("workspace binding missing")
        return
    }
    #expect(wsCmds == [.workspace(.number(3))])

    let moveFollow = ClassifiableEvent(
        kind: .keyDown,
        key: "3",
        flags: ClassifierFlags(option: true, shift: true)
    )
    guard case .command(let mv) = c.classify(moveFollow) else {
        Issue.record("move-to-workspace binding missing")
        return
    }
    #expect(mv == [.moveWindowToWorkspace(.number(3), follow: true)])

    let dock = ClassifiableEvent(
        kind: .keyDown,
        key: "l",
        flags: ClassifierFlags(control: true, option: true)
    )
    guard case .command(let dockCmds) = c.classify(dock) else {
        Issue.record("dock binding missing")
        return
    }
    #expect(dockCmds == [.dock(.right, screen: false)])
}

@Test func layoutToggleBinding() {
    let c = EventClassifier()
    let event = ClassifiableEvent(
        kind: .keyDown,
        key: "space",
        flags: ClassifierFlags(option: true, shift: true)
    )
    guard case .command(let cmds) = c.classify(event) else {
        Issue.record("layout toggle missing")
        return
    }
    #expect(cmds == [.layoutCycle(["floating", "tiling"])])
}
