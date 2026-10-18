import Testing
import Foundation
import LayoutModel

@Test func ruleEngineFileOrderAllMatchesRun() {
    let facts = WindowFacts(
        bundleID: "com.apple.Music",
        appName: "Music",
        title: "Library",
        kind: .normal,
        resizable: true,
        fullscreenButtonEnabled: true
    )
    let rules = [
        WindowRule(appId: "com.apple.Music", run: ["layout floating"]),
        WindowRule(appName: "music", run: ["min-size 200 100"]),
        WindowRule(title: "lib", run: ["dock left --screen"]),
    ]
    let result = RuleEngine.classify(facts: facts, rules: rules, config: .default)
    #expect(result.floating)
    #expect(result.commands.contains(.minSize(width: 200, height: 100)))
    #expect(result.commands.contains(.dock(edge: .left, screen: true)))
}

@Test func ruleEngineAppIdExactVsNameRegex() {
    let facts = WindowFacts(bundleID: "Com.Example.App", appName: "MyApp", kind: .normal)
    let byId = RuleEngine.classify(
        facts: facts,
        rules: [WindowRule(appId: "com.example.app", run: ["layout floating"])],
        config: RuleClassificationConfig(defaultTiling: true)
    )
    // Exact case-sensitive app-id — should NOT match.
    #expect(!byId.floating)

    let byName = RuleEngine.classify(
        facts: facts,
        rules: [WindowRule(appName: "myapp", run: ["layout floating"])],
        config: RuleClassificationConfig(defaultTiling: true)
    )
    #expect(byName.floating)
}

@Test func ruleEngineKindFromSubroleMapping() {
    #expect(WindowKind.from(subrole: nil) == .normal)
    #expect(WindowKind.from(subrole: "AXStandardWindow") == .normal)
    #expect(WindowKind.from(subrole: "AXDialog") == .dialog)
    #expect(WindowKind.from(subrole: "AXSystemDialog") == .dialog)
    #expect(WindowKind.from(subrole: "AXSheet") == .sheet)
    #expect(WindowKind.from(subrole: "AXFloatingWindow") == .panel)
}

@Test func extensionCommandsParse() {
    #expect(LayoutCommand.parse("ignore") == .ignore)
    #expect(LayoutCommand.parse("dock right") == .dock(edge: .right, screen: false))
    #expect(LayoutCommand.parse("dock down --screen") == .dock(edge: .bottom, screen: true))
    #expect(LayoutCommand.parse("min-size 80 60") == .minSize(width: 80, height: 60))
    #expect(LayoutCommand.parse("tab-with focused") == .tabWithFocused)
    #expect(LayoutCommand.parse("tab-with com.apple.Safari") == .tabWithAppId("com.apple.Safari"))
}

@Test func sheetsAndPanelsAlwaysFloat() {
    for kind in [WindowKind.sheet, .panel] {
        let result = RuleEngine.classify(
            facts: WindowFacts(kind: kind, resizable: true, fullscreenButtonEnabled: true),
            rules: [WindowRule(run: ["layout tiling"])],
            config: .default
        )
        #expect(result.floating)
    }
}
