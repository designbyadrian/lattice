import Testing
import Foundation
import Config
import LayoutModel

@Test func moduleName() {
    #expect(ConfigModule.name == "Config")
}

@Test func defaultConfig() {
    let c = LatticeConfig.default
    #expect(c.workspaces == 1)
    #expect(c.defaultTiling == false)
    #expect(c.gaps.inner == .uniform(10))
    #expect(c.gaps.outer == .uniform(10))
    #expect(c.animations.durationMs == 450)
    #expect(c.borders.enabled == false)
    #expect(c.focusFollowsMouse.enabled == false)
    #expect(c.modifiers.frameModifier.command == true && c.modifiers.frameModifier.shift == true)
    #expect(c.modifiers.pinchModifier.option == true && !c.modifiers.pinchModifier.control)
    #expect(c.menuBarControls == [.back, .forward, .views, .desktop, .everything])
    #expect(c.mouse.doubleClickDesktop == .commands([.zoom(.desktop, toggle: true)]))
    #expect(c.mouse.doubleClickTitle == .commands([.zoom(.window, toggle: true)]))
    #expect(c.layout.insertTakesFrom == .target)
    #expect(c.zoom.groupTileBelow == 100)
    #expect(c.tabs.tabBarHeight == 28)
    #expect(c.desktopArea.floatNudgeIn == true)
    #expect(c.windowSizing.axRetries == 3)
    #expect(c.modes["main"] != nil)
    #expect(c.modes["main"]!.bindings.count >= 40)
    #expect(c.experimental.axWindowID == false)
    #expect(c.experimental.multitouch == false)
}

@Test func defaultFileParses() throws {
    let config = try ConfigParser.parse(text: DefaultConfigText.fileContents)
    #expect(config.startAtLogin == true)
    #expect(config.workspaces == 1)
    #expect(config.defaultTiling == false)
    #expect(config.gaps.inner == .uniform(10))
    #expect(config.animations.durationMs == 450)
    #expect(config.modes["main"]?.bindings.isEmpty == false)
    #expect(config.experimental.axWindowID == false)
    #expect(config.experimental.multitouch == false)

    let chords = Set(config.modes["main"]!.bindings.map(\.chord.description))
    #expect(chords.contains("ctrl-alt-space"))
    #expect(chords.contains("ctrl-alt-left-bracket"))
    #expect(chords.contains("ctrl-alt-cmd-1"))
    #expect(chords.contains("ctrl-alt-cmd-shift-9"))
    #expect(!chords.contains("alt-h"))
}

@Test func experimentalSectionParses() throws {
    let text = """
    [experimental]
    ax-window-id = true
    multitouch = true
    """
    let config = try ConfigParser.parse(text: text)
    #expect(config.experimental.axWindowID == true)
    #expect(config.experimental.multitouch == true)
}

@Test func unknownKeyErrorsWithPath() {
    let text = """
    workspaces = 2
    not-a-real-key = true
    """
    do {
        _ = try ConfigParser.parse(text: text)
        Issue.record("expected error")
    } catch let list as ConfigErrorList {
        #expect(list.errors.contains { $0.keyPath == "not-a-real-key" })
    } catch {
        Issue.record("unexpected \(error)")
    }
}

@Test func defaultLayoutRejected() {
    let text = "default-layout = 'tall'"
    do {
        _ = try ConfigParser.parse(text: text)
        Issue.record("expected error")
    } catch let list as ConfigErrorList {
        #expect(list.errors.contains { $0.keyPath == "default-layout" })
        #expect(list.description.contains("single tree layout"))
    } catch {
        Issue.record("unexpected \(error)")
    }
}

@Test func scrollingAndAccordionNotSupported() {
    let text = """
    [scrolling]
    [accordion]
    """
    do {
        _ = try ConfigParser.parse(text: text)
        Issue.record("expected error")
    } catch let list as ConfigErrorList {
        #expect(list.errors.contains { $0.keyPath == "scrolling" })
        #expect(list.errors.contains { $0.keyPath == "accordion" })
    } catch {
        Issue.record("unexpected \(error)")
    }
}

@Test func gapsNumberAndPerSide() throws {
    let text = """
    [gaps]
    inner = 8
    outer = { left = 1, right = 2, top = 3, bottom = 4 }
    """
    let c = try ConfigParser.parse(text: text)
    #expect(c.gaps.inner == .uniform(8))
    #expect(c.gaps.outer == .perSide(GapInsetsConfig(left: 1, right: 2, top: 3, bottom: 4)))
}

@Test func modifiersSidesAndExtensions() throws {
    let text = """
    [modifiers]
    alt = 'left'
    ctrl = 'right'
    frame-modifier = 'cmd-shift'
    pinch-modifier = 'alt'
    """
    let c = try ConfigParser.parse(text: text)
    #expect(c.modifiers.alt == .left)
    #expect(c.modifiers.ctrl == .right)
    #expect(c.modifiers.frameModifier == ModifierSet(shift: true, command: true))
    #expect(c.modifiers.pinchModifier == ModifierSet(option: true))
}

@Test func badTypeKeyPath() {
    let text = "workspaces = 'nope'"
    do {
        _ = try ConfigParser.parse(text: text)
        Issue.record("expected error")
    } catch let list as ConfigErrorList {
        #expect(list.errors.contains { $0.keyPath == "workspaces" })
    } catch {
        Issue.record("unexpected \(error)")
    }
}

@Test func lastGoodKeptOnBrokenReload() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lattice-config-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let url = dir.appendingPathComponent("lattice.toml")
    try Data("workspaces = 3\n".utf8).write(to: url)

    let loader = ConfigLoader(fileURL: url)
    let good = try loader.load()
    #expect(good.workspaces == 3)

    try Data("workspaces = 'bad'\n".utf8).write(to: url)
    let result = loader.reload()
    guard case .failure = result else {
        Issue.record("expected failure")
        return
    }
    #expect(loader.config.workspaces == 3)
    #expect(loader.lastError != nil)
}

@Test func firstRunWritesDefaults() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lattice-config-first-\(UUID().uuidString)", isDirectory: true)
    let url = dir.appendingPathComponent("lattice.toml")
    defer { try? FileManager.default.removeItem(at: dir) }

    let loader = ConfigLoader(fileURL: url)
    let config = try loader.loadOrCreateDefaults()
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(config.workspaces == 1)
    let text = try String(contentsOf: url, encoding: .utf8)
    #expect(text.contains("#:schema"))
    #expect(text.contains("Lattice configuration"))
    #expect(text.contains("default-tiling = false"))
    #expect(text.contains("ctrl-alt-space"))
}

// MARK: - Commands

@Test func commandParserDinkyAndExtensions() throws {
    #expect(try CommandParser.parse("focus left") == .focus(.left))
    #expect(try CommandParser.parse("move down") == .move(.down))
    #expect(try CommandParser.parse("split horizontal") == .split(.horizontal))
    #expect(try CommandParser.parse("split vertical") == .split(.vertical))
    #expect(try CommandParser.parse("zoom window") == .zoom(.window, toggle: false))
    #expect(try CommandParser.parse("zoom all") == .zoom(.all, toggle: false))
    #expect(try CommandParser.parse("zoom desktop --toggle") == .zoom(.desktop, toggle: true))
    #expect(try CommandParser.parse("zoom window --toggle") == .zoom(.window, toggle: true))
    #expect(try CommandParser.parse("fullscreen") == .zoom(.window, toggle: false))
    #expect(try CommandParser.parse("tab next") == .tab(.next))
    #expect(try CommandParser.parse("workspace 3") == .workspace(.number(3)))
    #expect(
        try CommandParser.parse("move-window-to-workspace 2 --follow")
            == .moveWindowToWorkspace(.number(2), follow: true)
    )
    #expect(try CommandParser.parse("unmanage-all") == .unmanageAll)
    #expect(try CommandParser.parse("dock-all") == .dockAll)
    #expect(try CommandParser.parse("pan left") == .pan(.left))
    #expect(try CommandParser.parse("desktop-area toggle") == .desktopArea(.toggle))
    #expect(try CommandParser.parse("split-new com.apple.finder") == .splitNew(appId: "com.apple.finder"))
    #expect(try CommandParser.parse("split-direction toggle") == .splitDirection(.toggle))
    #expect(try CommandParser.parse("recall-view 3") == .recallView(3))
    #expect(try CommandParser.parse("store-view 7") == .storeView(7))
    #expect(try CommandParser.parse("frame-rect") == .frameRect)
    #expect(try CommandParser.parse("retile") == .retile)
    #expect(try CommandParser.parse("layout floating tiling") == .layoutCycle(["floating", "tiling"]))
    #expect(try CommandParser.parse("dock left") == .dock(.left, screen: false))
    #expect(try CommandParser.parse("dock up --screen") == .dock(.up, screen: true))
    #expect(try CommandParser.parse("ignore") == .ignore)
    #expect(try CommandParser.parse("min-size 200 100") == .minSize(width: 200, height: 100))
}

@Test func commandParserRejectsRemovedCommands() {
    for cmd in ["overview", "float-all", "view 1", "save-view 1"] {
        do {
            _ = try CommandParser.parse(cmd)
            Issue.record("expected error for \(cmd)")
        } catch is ConfigError {
            // expected
        } catch {
            Issue.record("unexpected \(error) for \(cmd)")
        }
    }
}

@Test func commandParserRejectsUnsupportedLayout() {
    do {
        _ = try CommandParser.parse("layout accordion")
        Issue.record("expected error")
    } catch let e as ConfigError {
        #expect(e.message.contains("not supported"))
    } catch {
        Issue.record("unexpected \(error)")
    }
}

@Test func keyChordParsing() throws {
    let c = try KeyChord.parse("alt-shift-h")
    #expect(c.modifiers.option && c.modifiers.shift && !c.modifiers.control)
    #expect(c.key == "h")
    #expect(try KeyChord.parse("ctrl-alt-1").key == "1")
    #expect(try KeyChord.parse("alt-enter").key == "enter")
    let bracket = try KeyChord.parse("ctrl-alt-left-bracket")
    #expect(bracket.key == "left-bracket")
    #expect(bracket.modifiers.control && bracket.modifiers.option)
}

@Test func schemaResourceExists() throws {
    #expect(ConfigModule.schemaURL != nil)
}
