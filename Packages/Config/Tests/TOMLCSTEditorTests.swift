import Testing
import Foundation
import Config

@Test func tomlCSTPreservesCommentsAndOrder() throws {
    let original = """
    # keep me
    start-at-login = true
    workspaces = 1

    [gaps]
    # inner comment
    inner = 10
    outer = 10
    """
    let patched = try TOMLCSTEditor.set(
        in: original,
        table: "gaps",
        key: "inner",
        value: .int(14)
    )
    #expect(patched.contains("# keep me"))
    #expect(patched.contains("# inner comment"))
    #expect(patched.contains("inner = 14"))
    #expect(patched.contains("outer = 10"))
    #expect(patched.contains("start-at-login = true"))
    // Key order: start-at-login before workspaces; gaps.inner before outer.
    let startIdx = patched.range(of: "start-at-login")!.lowerBound
    let wsIdx = patched.range(of: "workspaces")!.lowerBound
    #expect(startIdx < wsIdx)
}

@Test func tomlCSTInsertsMissingKeyIntoTable() throws {
    let original = """
    [borders]
    enabled = false
    """
    let patched = try TOMLCSTEditor.set(
        in: original,
        table: "borders",
        key: "width",
        value: .float(6)
    )
    #expect(patched.contains("enabled = false"))
    #expect(patched.contains("width = 6.0"))
}

@Test func tomlCSTCreatesMissingTable() throws {
    let original = "workspaces = 1\n"
    let patched = try TOMLCSTEditor.set(
        in: original,
        table: "animations",
        key: "duration-ms",
        value: .int(300)
    )
    #expect(patched.contains("[animations]"))
    #expect(patched.contains("duration-ms = 300"))
    #expect(patched.contains("workspaces = 1"))
}

@Test func tomlCSTStringArrayAndRootKey() throws {
    let original = "menu-bar-controls = ['back', 'forward']\n"
    let patched = try TOMLCSTEditor.set(
        in: original,
        table: nil,
        key: "menu-bar-controls",
        value: .stringArray(["desktop", "everything"])
    )
    #expect(patched.contains("menu-bar-controls = ['desktop', 'everything']"))
}

@Test func tomlCSTCRLFPreserved() throws {
    let original = "workspaces = 1\r\n[gaps]\r\ninner = 8\r\n"
    let patched = try TOMLCSTEditor.set(
        in: original,
        table: "gaps",
        key: "inner",
        value: .int(12)
    )
    #expect(patched.contains("\r\n"))
    #expect(patched.contains("inner = 12"))
}

@Test func tomlCSTInlineTableArrayOfTablesAppend() throws {
    let original = """
    workspaces = 1

    [[rules]]
    app-id = 'com.a'
    run = 'layout floating'
    """
    let block = ConfigAppender.ruleBlock(appId: "com.b", appName: nil, run: ["ignore"])
    let patched = TOMLCSTEditor.appendRulesArrayOfTables(in: original, block: block)
    #expect(patched.contains("app-id = 'com.a'"))
    #expect(patched.contains("app-id = 'com.b'"))
    #expect(patched.contains("run = 'ignore'"))
}

@Test func tomlCSTValidatedWriteBlocksInvalid() throws {
    let original = "workspaces = 1\n"
    #expect(throws: TOMLCSTEditor.EditError.self) {
        try TOMLCSTEditor.applyValidated(text: original) { text in
            // Invalid: unknown menu-bar control.
            try TOMLCSTEditor.set(
                in: text,
                table: nil,
                key: "menu-bar-controls",
                value: .stringArray(["not-a-control"])
            )
        }
    }
}

@Test func tomlCSTRoundTripDefaultConfig() throws {
    let text = DefaultConfigText.fileContents
    let patched = try TOMLCSTEditor.applyValidated(text: text) { current in
        try TOMLCSTEditor.set(
            in: current,
            table: nil,
            key: "workspaces",
            value: .int(2)
        )
    }
    let config = try ConfigParser.parse(text: patched)
    #expect(config.workspaces == 2)
    #expect(patched.contains("# Lattice configuration"))
    #expect(patched.contains("menu-bar-controls"))
}

@Test func shortcutConflictDetectorFindsDuplicatesAndSystem() throws {
    var mode = DefaultBindings.mainMode()
    let chord = try KeyChord.parse("ctrl-alt-1")
    mode.bindings.append(KeyBinding(chord: chord, commands: [.recallView(1)]))
    let conflicts = ShortcutConflictDetector.conflicts(in: mode)
    #expect(conflicts.contains { $0.reason.contains("duplicates") })

    let system = ShortcutConflictDetector.conflicts(
        in: ModeConfig(name: "main"),
        candidate: try KeyChord.parse("cmd-c")
    )
    #expect(system.contains { $0.reason.contains("system") })
}
