import Foundation
import LayoutModel

/// Built-in `[mode.main]` bindings (implementation plan defaults).
public enum DefaultBindings {
    public static let modeName = "main"

    public static func mainMode() -> ModeConfig {
        var bindings: [KeyBinding] = []

        func bind(_ chord: String, _ command: String) {
            let c = try! KeyChord.parse(chord)
            let cmd = try! CommandParser.parse(command)
            bindings.append(KeyBinding(chord: c, commands: [cmd]))
        }

        func bindCycle(_ chord: String, _ commands: [String]) {
            let c = try! KeyChord.parse(chord)
            let cmds = commands.map { try! CommandParser.parse($0) }
            // Prefer layoutCycle when it's the layout toggle.
            if commands.count == 2,
               commands[0].hasPrefix("layout"),
               commands[1].hasPrefix("layout") {
                bindings.append(KeyBinding(chord: c, commands: [.layoutCycle(["floating", "tiling"])]))
            } else {
                bindings.append(KeyBinding(chord: c, commands: cmds))
            }
        }

        // Focus
        bind("alt-h", "focus left")
        bind("alt-j", "focus down")
        bind("alt-k", "focus up")
        bind("alt-l", "focus right")

        // Move
        bind("alt-shift-h", "move left")
        bind("alt-shift-j", "move down")
        bind("alt-shift-k", "move up")
        bind("alt-shift-l", "move right")

        // Split / zoom / overview / tabs
        bind("alt-enter", "split horizontal")
        bind("alt-v", "split vertical")
        bind("alt-f", "zoom window")
        bind("alt-shift-f", "zoom all")
        bind("alt-o", "overview")
        bind("alt-tab", "tab next")
        bind("alt-shift-tab", "tab prev")

        // Workspaces
        for n in 1...9 {
            bind("alt-\(n)", "workspace \(n)")
            bind("alt-shift-\(n)", "move-window-to-workspace \(n) --follow")
        }

        bind("alt-shift-q", "float-all")
        bind("alt-r", "retile")
        bindCycle("alt-shift-space", ["layout floating", "layout tiling"])

        // Dock
        bind("ctrl-alt-h", "dock left")
        bind("ctrl-alt-j", "dock down")
        bind("ctrl-alt-k", "dock up")
        bind("ctrl-alt-l", "dock right")

        return ModeConfig(name: modeName, bindings: bindings)
    }
}
