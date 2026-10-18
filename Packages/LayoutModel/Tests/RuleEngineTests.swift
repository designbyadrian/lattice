import Foundation
import Testing
import LayoutModel

@Test func ruleEngineDialogsAlwaysFloat() {
    let facts = WindowFacts(kind: .dialog, resizable: true, fullscreenButtonEnabled: true)
    let result = RuleEngine.classify(
        facts: facts,
        rules: [WindowRule(run: ["layout tiling"])],
        config: .default
    )
    #expect(result.floating)
}

@Test func ruleEngineNonResizableAlwaysFloats() {
    let facts = WindowFacts(kind: .normal, resizable: false, fullscreenButtonEnabled: true)
    let result = RuleEngine.classify(facts: facts, rules: [], config: .default)
    #expect(result.floating)
}

@Test func ruleEngineLastLayoutCommandWins() {
    let facts = WindowFacts(
        bundleID: "com.apple.Music",
        appName: "Music",
        kind: .normal,
        resizable: true,
        fullscreenButtonEnabled: true
    )
    let rules = [
        WindowRule(appId: "com.apple.Music", run: ["layout floating"]),
        WindowRule(appId: "com.apple.Music", run: ["layout tiling", "move-window-to-workspace 2"]),
    ]
    let result = RuleEngine.classify(facts: facts, rules: rules, config: .default)
    #expect(!result.floating)
    #expect(result.commands == [.moveWindowToWorkspace(2)])
}

@Test func ruleEngineAppNameRegexCaseInsensitive() {
    let facts = WindowFacts(appName: "Visual Studio Code", kind: .normal)
    let rules = [WindowRule(appName: "visual.*code", run: ["layout floating"])]
    let result = RuleEngine.classify(facts: facts, rules: rules, config: RuleClassificationConfig(defaultTiling: true))
    #expect(result.floating)
}

@Test func ruleEngineFullscreenHeuristic() {
    let facts = WindowFacts(
        bundleID: "com.example.App",
        kind: .normal,
        resizable: true,
        fullscreenButtonEnabled: false
    )
    let config = RuleClassificationConfig(floatWindowsWithoutFullscreen: true)
    let floated = RuleEngine.classify(facts: facts, rules: [], config: config)
    #expect(floated.floating)

    let tiled = RuleEngine.classify(
        facts: facts,
        rules: [WindowRule(run: ["layout tiling"])],
        config: config
    )
    #expect(!tiled.floating)
}

@Test func ruleEngineExemptionSkipsHeuristic() {
    let facts = WindowFacts(
        bundleID: "com.apple.Terminal",
        kind: .normal,
        resizable: true,
        fullscreenButtonEnabled: false
    )
    let result = RuleEngine.classify(facts: facts, rules: [], config: .default)
    #expect(!result.floating)
}

@Test func ruleEngineIgnoreFlag() {
    let facts = WindowFacts(bundleID: "com.example.Skip", kind: .normal)
    let result = RuleEngine.classify(
        facts: facts,
        rules: [WindowRule(appId: "com.example.Skip", run: ["ignore"])],
        config: .default
    )
    #expect(result.ignore)
}

@Test func ruleEngineKindFilter() {
    let facts = WindowFacts(kind: .sheet)
    let rules = [WindowRule(kind: .normal, run: ["layout tiling"])]
    // Sheet won't match normal rule; intrinsic float still applies.
    let result = RuleEngine.classify(facts: facts, rules: rules, config: .default)
    #expect(result.floating)
}

@Test func layoutCommandParsing() {
    #expect(LayoutCommand.parse("layout floating") == .layoutFloating)
    #expect(LayoutCommand.parse("layout tiling") == .layoutTiling)
    #expect(LayoutCommand.parse("ignore") == .ignore)
    #expect(LayoutCommand.parse("dock left --screen") == .dock(edge: .left, screen: true))
    #expect(LayoutCommand.parse("min-size 100 200") == .minSize(width: 100, height: 200))
    #expect(LayoutCommand.parse("tab-with focused") == .tabWithFocused)
}

@Test func workspaceBindingCodable() throws {
    let plan = WorkspacePlan(
        count: 3,
        workspaceToDisplay: [
            1: [.main],
            2: [.secondary, .nameSubstring("Dell")],
        ]
    )
    let binding = WorkspaceSpaceBinding(
        binding: [1: SpaceID(rawValue: 42)],
        ownedSpaces: [SpaceID(rawValue: 42)]
    )
    let planData = try JSONEncoder().encode(plan)
    let bindingData = try JSONEncoder().encode(binding)
    #expect(try JSONDecoder().decode(WorkspacePlan.self, from: planData) == plan)
    #expect(try JSONDecoder().decode(WorkspaceSpaceBinding.self, from: bindingData) == binding)
}

@Test func moduleName() {
    #expect(LayoutModelModule.name == "LayoutModel")
}

@Test func windowStateSuspensionFlag() {
    #expect(WindowState.active.participatesInSolve)
    #expect(WindowState.minimized.isSuspended)
    #expect(WindowState.fullscreen.isSuspended)
    #expect(WindowState.hidden.isSuspended)
}
