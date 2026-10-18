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

@Test func safetyNetDisablesP5aGatedFeatures() {
    let reduced = InputSafetyNetState.reduced(reason: "test")
    #expect(reduced.disablesModifierDrag)
    #expect(reduced.disablesPinchOverApps)
    #expect(reduced.disablesLeftRightModifiers)
    #expect(reduced.disablesDoubleClickGestures)
    #expect(reduced.disablesGreenButton)

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

@Test func boundZoomAllIsCommand() {
    let c = EventClassifier()
    let event = ClassifiableEvent(
        kind: .keyDown,
        key: "space",
        flags: ClassifierFlags(control: true, option: true, device: [.leftControl, .leftOption])
    )
    let result = c.classify(event)
    guard case .command(let cmds) = result else {
        Issue.record("expected command, got \(result)")
        return
    }
    #expect(cmds == [.zoom(.all, toggle: false)])
}

@Test func boundKeyUpIsSwallowed() {
    let c = EventClassifier()
    let event = ClassifiableEvent(
        kind: .keyUp,
        key: "space",
        flags: ClassifierFlags(control: true, option: true)
    )
    #expect(c.classify(event) == .swallow)
}

@Test func leftRightModifierPolicy() {
    var config = LatticeConfig.default
    config.modifiers.alt = .left
    let c = EventClassifier(config: config)

    let rightOnly = ClassifiableEvent(
        kind: .keyDown,
        key: "space",
        flags: ClassifierFlags(control: true, option: true, device: [.leftControl, .rightOption])
    )
    #expect(c.classify(rightOnly) == .pass)

    let left = ClassifiableEvent(
        kind: .keyDown,
        key: "space",
        flags: ClassifierFlags(control: true, option: true, device: [.leftControl, .leftOption])
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
        key: "space",
        flags: ClassifierFlags(control: true, option: true, device: [.leftControl, .rightOption])
    )
    guard case .command = c.classify(rightOnly) else {
        Issue.record("safety net should ignore side")
        return
    }
}

@Test func frameModifierDragSwallows() {
    let c = EventClassifier()
    let down = ClassifiableEvent(
        kind: .leftMouseDown,
        flags: ClassifierFlags(shift: true, command: true),
        overAppWindow: true
    )
    #expect(c.classify(down) == .swallow)

    let overDesktop = ClassifiableEvent(
        kind: .leftMouseDown,
        flags: ClassifierFlags(shift: true, command: true),
        overAppWindow: false
    )
    #expect(c.classify(overDesktop) == .swallow)

    let noMod = ClassifiableEvent(
        kind: .leftMouseDown,
        flags: ClassifierFlags(),
        overAppWindow: true
    )
    #expect(c.classify(noMod) == .pass)
}

@Test func safetyNetPassesFrameModifierDrag() {
    let c = EventClassifier(safetyNet: .reduced(reason: "test"))
    let down = ClassifiableEvent(
        kind: .leftMouseDown,
        flags: ClassifierFlags(shift: true, command: true),
        overAppWindow: true
    )
    #expect(c.classify(down) == .pass)
}

@Test func pinchWithModifierOverAppSwallows() {
    let c = EventClassifier()
    let pinch = ClassifiableEvent(
        kind: .magnify,
        flags: ClassifierFlags(option: true),
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

@Test func workspaceAndViewBindings() {
    let c = EventClassifier()
    let ws = ClassifiableEvent(
        kind: .keyDown,
        key: "3",
        flags: ClassifierFlags(control: true, option: true, command: true)
    )
    guard case .command(let wsCmds) = c.classify(ws) else {
        Issue.record("workspace binding missing")
        return
    }
    #expect(wsCmds == [.workspace(.number(3))])

    let move = ClassifiableEvent(
        kind: .keyDown,
        key: "3",
        flags: ClassifierFlags(control: true, option: true, shift: true, command: true)
    )
    guard case .command(let mv) = c.classify(move) else {
        Issue.record("move-to-workspace binding missing")
        return
    }
    #expect(mv == [.moveWindowToWorkspace(.number(3), follow: false)])

    let recall = ClassifiableEvent(
        kind: .keyDown,
        key: "3",
        flags: ClassifierFlags(control: true, option: true)
    )
    guard case .command(let recallCmds) = c.classify(recall) else {
        Issue.record("recall-view binding missing")
        return
    }
    #expect(recallCmds == [.recallView(3)])
}

@Test func zoomAllBinding() {
    let c = EventClassifier()
    let event = ClassifiableEvent(
        kind: .keyDown,
        key: "space",
        flags: ClassifierFlags(control: true, option: true)
    )
    guard case .command(let cmds) = c.classify(event) else {
        Issue.record("zoom all binding missing")
        return
    }
    #expect(cmds == [.zoom(.all, toggle: false)])
}
