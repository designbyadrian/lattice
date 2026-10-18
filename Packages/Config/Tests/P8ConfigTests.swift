import Testing
import Foundation
import Config
import LayoutModel

@Test func animationsDragHooksParse() throws {
    let text = """
    [animations]
    enabled = false
    duration-ms = 450

    [drag]
    placeholders = false

    [hooks]
    startup = 'exec-and-forget echo hi'
    workspace-changed = ['retile']
    """
    let c = try ConfigParser.parse(text: text)
    #expect(c.animations.enabled == false)
    #expect(c.animations.durationMs == 450)
    #expect(c.drag.placeholders == false)
    #expect(c.hooks.startup == [.execAndForget("echo hi")])
    #expect(c.hooks.workspaceChanged == [.retile])
}

@Test func workspaceAndDisplayTables() throws {
    let text = """
    workspaces = 3

    [workspace.1]
    tiling = false

    [workspace.2]
    tiling = true

    [display.Dell]
    inner = 8
    outer = 4

    [display.main]
    inner = 2
    """
    let c = try ConfigParser.parse(text: text)
    #expect(c.workspaceConfigs[1]?.tiling == false)
    #expect(c.workspaceConfigs[2]?.tiling == true)
    #expect(c.displayGaps.count == 2)
    let resolved = DisplayPatternGaps.resolve(
        displayName: "Dell UltraSharp",
        isMain: true,
        isSecondary: false,
        overrides: c.displayGaps,
        fallback: .default
    )
    // Name pattern beats main; longer/name score wins.
    #expect(resolved.inner == .uniform(8))
}

@Test func rulesParseAndValidate() throws {
    let text = """
    [[rules]]
    app-id = 'com.apple.Music'
    run = ['layout floating', 'move-window-to-workspace 2']

    [[rules]]
    app-name = 'code'
    kind = 'normal'
    run = 'layout tiling'
    """
    let c = try ConfigParser.parse(text: text)
    #expect(c.rules.count == 2)
    #expect(c.rules[0].appId == "com.apple.Music")
    #expect(c.rules[1].appName == "code")
}

@Test func rulesMissingRunRejected() {
    let text = """
    [[rules]]
    app-id = 'x'
    """
    do {
        _ = try ConfigParser.parse(text: text)
        Issue.record("expected error")
    } catch let list as ConfigErrorList {
        #expect(list.errors.contains { $0.keyPath == "rules[0].run" })
    } catch {
        Issue.record("unexpected \(error)")
    }
}

@Test func rulesInvalidRegexRejected() {
    let text = """
    [[rules]]
    app-name = '(unclosed'
    run = 'ignore'
    """
    do {
        _ = try ConfigParser.parse(text: text)
        Issue.record("expected error")
    } catch let list as ConfigErrorList {
        #expect(list.errors.contains { $0.keyPath == "rules[0].app-name" })
    } catch {
        Issue.record("unexpected \(error)")
    }
}

@Test func dinkyGoldenRulesSection() throws {
    // Written from the documented Dinky-compatible format (not copied from Dinky source).
    let text = """
    workspaces = 2
    default-tiling = true

    [workspace-to-display]
    1 = 'main'
    2 = ['secondary', 'Dell']

    [gaps]
    inner = 10
    outer = { left = 5, right = 5, top = 5, bottom = 5 }

    [[rules]]
    app-id = 'com.apple.Music'
    run = ['layout floating', 'move-window-to-workspace 2']

    [[rules]]
    kind = 'dialog'
    run = 'layout floating'
    """
    let c = try ConfigParser.parse(text: text)
    #expect(c.workspaces == 2)
    #expect(c.workspaceToDisplay[2]?.count == 2)
    #expect(c.rules.count == 2)
}

@Test func configAppenderOnlyAppends() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lattice-append-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("lattice.toml")
    let header = "# keep me\nworkspaces = 1\n"
    try Data(header.utf8).write(to: url)
    try ConfigAppender.appendRule(to: url, appId: "com.example.App", appName: nil)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.hasPrefix("# keep me"))
    #expect(text.contains("[[rules]]"))
    #expect(text.contains("app-id = 'com.example.App'"))
}

@Test func urlSchemeParsesAndRejectsExec() throws {
    let cmd = try URLCommandParser.parse("lattice://run?cmd=workspace%202")
    #expect(cmd == .workspace(.number(2)))

    let alias = try URLCommandParser.parse("lattice://workspace/3")
    #expect(alias == .workspace(.number(3)))

    do {
        _ = try URLCommandParser.parse("lattice://run?cmd=exec-and-forget%20rm%20-rf%20/")
        Issue.record("expected reject")
    } catch let e as URLCommandParser.URLCommandError {
        #expect(e == .execAndForgetRejected)
    }

    do {
        _ = try URLCommandParser.parse("lattice://run?cmd=workspace%201&evil=1")
        Issue.record("expected reject")
    } catch let e as URLCommandParser.URLCommandError {
        #expect(e == .unknownQueryParameter("evil"))
    }
}

@Test func urlSchemeFuzzInvalid() {
    let bad = [
        "http://run?cmd=workspace%201",
        "lattice://unknown/thing",
        "lattice://run",
        "not a url at all%%%",
    ]
    for s in bad {
        #expect(throws: (any Error).self) {
            _ = try URLCommandParser.parse(s)
        }
    }
}

@Test func doctorReportsBrokenConfig() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lattice-doctor-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("bad.toml")
    try Data("not-a-real-key = true\n".utf8).write(to: url)
    let report = Doctor.check(configURL: url)
    #expect(!report.ok)
    #expect(!report.errors.isEmpty)
}

@Test func borderColorParsing() throws {
    #expect(try BorderColor.parse("accent") == .accent)
    #expect(try BorderColor.parse("#aabbcc") == .hex("#aabbcc"))
    #expect(try BorderColor.parse("#aabbccdd") == .hex("#aabbccdd"))
    #expect(throws: (any Error).self) {
        _ = try BorderColor.parse("red")
    }
    #expect(throws: (any Error).self) {
        _ = try BorderColor.parse("#xyz")
    }
}
