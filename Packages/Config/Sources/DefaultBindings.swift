import Foundation
import LayoutModel

/// Built-in `[mode.main]` bindings (ADDENDUM-2 B11 Control-Option set).
public enum DefaultBindings {
    public static let modeName = "main"

    public static func mainMode() -> ModeConfig {
        var bindings: [KeyBinding] = []

        func bind(_ chord: String, _ command: String) {
            let c = try! KeyChord.parse(chord)
            let cmd = try! CommandParser.parse(command)
            bindings.append(KeyBinding(chord: c, commands: [cmd]))
        }

        bind("ctrl-alt-space", "zoom all")
        bind("ctrl-alt-up", "zoom out")
        bind("ctrl-alt-down", "zoom in")
        bind("ctrl-alt-left", "pan left")
        bind("ctrl-alt-right", "pan right")
        bind("ctrl-alt-shift-up", "pan up")
        bind("ctrl-alt-shift-down", "pan down")
        bind("ctrl-alt-left-bracket", "history back")
        bind("ctrl-alt-right-bracket", "history forward")
        bind("ctrl-alt-enter", "zoom window --toggle")
        bind("ctrl-alt-d", "desktop-area toggle")
        bind("ctrl-alt-n", "split-new com.apple.finder")

        for n in 1...9 {
            bind("ctrl-alt-shift-\(n)", "store-view \(n)")
            bind("ctrl-alt-\(n)", "recall-view \(n)")
            bind("ctrl-alt-cmd-\(n)", "workspace \(n)")
            bind("ctrl-alt-cmd-shift-\(n)", "move-window-to-workspace \(n)")
        }

        return ModeConfig(name: modeName, bindings: bindings)
    }
}
