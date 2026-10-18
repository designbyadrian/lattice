import Foundation
import LayoutModel

/// Parses Dinky command-string grammar plus Lattice extensions (PLAN §7a / ADDENDUM-2 §R).
public enum CommandParser {
    /// Parse a single command string.
    public static func parse(_ raw: String) throws -> Command {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConfigError("empty command")
        }

        let tokens = tokenize(trimmed)
        guard let verb = tokens.first?.lowercased() else {
            throw ConfigError("empty command")
        }
        let args = Array(tokens.dropFirst())
        let flags = Set(args.filter { $0.hasPrefix("--") }.map { $0.lowercased() })
        let positional = args.filter { !$0.hasPrefix("--") }

        switch verb {
        case "workspace":
            return .workspace(try parseWorkspaceTarget(positional, verb: verb))
        case "workspace-back-and-forth":
            return .workspaceBackAndForth
        case "move-window-to-workspace":
            let target = try parseWorkspaceTarget(positional, verb: verb)
            return .moveWindowToWorkspace(target, follow: flags.contains("--follow"))
        case "move-window-to-display":
            let target = try parseDisplayTarget(positional, verb: verb)
            return .moveWindowToDisplay(target, follow: flags.contains("--follow"))
        case "focus":
            return .focus(try parseDirection(positional, verb: verb))
        case "move":
            return .move(try parseDirection(positional, verb: verb))
        case "join-with":
            return .joinWith(try parseDirection(positional, verb: verb))
        case "resize":
            return try parseResize(positional)
        case "balance-sizes":
            return .balanceSizes
        case "flatten-workspace-tree":
            return .flattenWorkspaceTree
        case "retile":
            return .retile
        case "clear-minimum-sizes":
            return .clearMinimumSizes
        case "mode":
            guard let name = positional.first, !name.isEmpty else {
                throw ConfigError("mode requires a name")
            }
            return .mode(name)
        case "reload-config":
            return .reloadConfig
        case "enable":
            guard let rawState = positional.first?.lowercased(),
                  let state = EnableState(rawValue: rawState) else {
                throw ConfigError("enable requires on|off|toggle")
            }
            return .enable(state)
        case let v where v.hasPrefix("list-"):
            return .list(String(v.dropFirst("list-".count)))
        case "exec-and-forget":
            let shell = positional.joined(separator: " ")
            guard !shell.isEmpty else {
                throw ConfigError("exec-and-forget requires a shell command")
            }
            return .execAndForget(shell)
        case "layout":
            return try parseLayout(positional)
        case "split":
            return .split(try parseAxis(positional, verb: verb))
        case "dock":
            let dir = try parseDirection(positional, verb: verb)
            return .dock(dir, screen: flags.contains("--screen"))
        case "dock-all":
            return .dockAll
        case "tab-with":
            return .tabWith(try parseTabWithTarget(positional))
        case "untab":
            return .untab
        case "tab":
            return .tab(try parseTabNav(positional))
        case "zoom":
            return .zoom(try parseZoom(positional), toggle: flags.contains("--toggle"))
        case "fullscreen":
            // Dinky alias of zoom window.
            return .zoom(.window, toggle: false)
        case "frame-rect":
            return .frameRect
        case "history":
            guard let rawDir = positional.first?.lowercased(),
                  let dir = HistoryDirection(rawValue: rawDir) else {
                throw ConfigError("history requires back|forward")
            }
            return .history(dir)
        case "recall-view":
            return .recallView(try parseViewIndex(positional, verb: verb))
        case "store-view":
            return .storeView(try parseViewIndex(positional, verb: verb))
        case "pan":
            return .pan(try parseDirection(positional, verb: verb))
        case "desktop-area":
            guard let raw = positional.first?.lowercased(),
                  let action = DesktopAreaAction(rawValue: raw) else {
                throw ConfigError("desktop-area requires show|hide|toggle")
            }
            return .desktopArea(action)
        case "split-new":
            guard let appId = positional.first, !appId.isEmpty else {
                throw ConfigError("split-new requires an app id")
            }
            return .splitNew(appId: appId)
        case "split-direction":
            guard let raw = positional.first?.lowercased(),
                  let action = SplitDirectionAction(rawValue: raw) else {
                throw ConfigError("split-direction requires toggle|horizontal|vertical")
            }
            return .splitDirection(action)
        case "unmanage-all":
            return .unmanageAll
        case "ignore":
            return .ignore
        case "min-size":
            guard positional.count >= 2,
                  let w = Double(positional[0]),
                  let h = Double(positional[1]) else {
                throw ConfigError("min-size requires <w> <h>")
            }
            return .minSize(width: w, height: h)
        default:
            throw ConfigError("unknown command '\(verb)'")
        }
    }

    /// Parse a binding value: a string or a list of strings (toggle/cycle).
    public static func parseBindingValue(_ value: Any, keyPath: String) throws -> [Command] {
        if let s = value as? String {
            return [try parse(s)]
        }
        if let list = value as? [Any] {
            var commands: [Command] = []
            for (i, item) in list.enumerated() {
                guard let s = item as? String else {
                    throw ConfigError.badType("string", keyPath: "\(keyPath)[\(i)]")
                }
                commands.append(try parse(s))
            }
            if commands.count >= 2, commands.allSatisfy({
                if case .layoutFloating = $0 { return true }
                if case .layoutTiling = $0 { return true }
                return false
            }) {
                // Preserve cycle form for layout floating tiling.
                let names = list.compactMap { $0 as? String }.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return [.layoutCycle(names)]
            }
            return commands
        }
        throw ConfigError.badType("string or array of strings", keyPath: keyPath)
    }

    // MARK: - Helpers

    private static func tokenize(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        for ch in raw {
            if ch == "'" && !inDouble {
                inSingle.toggle()
                continue
            }
            if ch == "\"" && !inSingle {
                inDouble.toggle()
                continue
            }
            if ch.isWhitespace && !inSingle && !inDouble {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func parseWorkspaceTarget(_ positional: [String], verb: String) throws -> WorkspaceTarget {
        guard let first = positional.first?.lowercased() else {
            throw ConfigError("\(verb) requires <n|prev|next>")
        }
        switch first {
        case "prev": return .prev
        case "next": return .next
        default:
            guard let n = Int(first), n >= 1 else {
                throw ConfigError("\(verb) workspace must be a positive integer, prev, or next")
            }
            return .number(n)
        }
    }

    private static func parseDisplayTarget(_ positional: [String], verb: String) throws -> DisplayTarget {
        guard let first = positional.first?.lowercased() else {
            throw ConfigError("\(verb) requires next|prev")
        }
        switch first {
        case "next": return .next
        case "prev": return .prev
        default:
            throw ConfigError("\(verb) requires next|prev")
        }
    }

    private static func parseDirection(_ positional: [String], verb: String) throws -> CommandDirection {
        guard let first = positional.first, let dir = CommandDirection.parse(first) else {
            throw ConfigError("\(verb) requires left|down|up|right")
        }
        return dir
    }

    private static func parseAxis(_ positional: [String], verb: String) throws -> Axis {
        guard let first = positional.first?.lowercased() else {
            throw ConfigError("\(verb) requires horizontal|vertical")
        }
        switch first {
        case "horizontal", "h": return .horizontal
        case "vertical", "v": return .vertical
        default:
            throw ConfigError("\(verb) requires horizontal|vertical")
        }
    }

    private static func parseResize(_ positional: [String]) throws -> Command {
        guard positional.count >= 2,
              let axis = ResizeAxis(rawValue: positional[0].lowercased()),
              let delta = Int(positional[1].replacingOccurrences(of: "+", with: "")) else {
            throw ConfigError("resize requires <smart|width|height> <±n>")
        }
        return .resize(axis, delta: delta)
    }

    private static func parseLayout(_ positional: [String]) throws -> Command {
        if positional.isEmpty {
            throw ConfigError("layout requires floating|tiling")
        }
        if positional.count == 1 {
            switch positional[0].lowercased() {
            case "floating": return .layoutFloating
            case "tiling": return .layoutTiling
            default:
                throw ConfigError(
                    "layout '\(positional[0])' is not supported (Lattice has floating|tiling only)"
                )
            }
        }
        // `layout floating tiling` → cycle
        let names = positional.map { $0.lowercased() }
        for name in names where name != "floating" && name != "tiling" {
            throw ConfigError(
                "layout '\(name)' is not supported (Lattice has floating|tiling only)"
            )
        }
        return .layoutCycle(names)
    }

    private static func parseTabWithTarget(_ positional: [String]) throws -> TabTarget {
        guard let first = positional.first else {
            throw ConfigError("tab-with requires <dir|focused|app-id>")
        }
        let lower = first.lowercased()
        if lower == "focused" { return .focused }
        if let dir = CommandDirection.parse(lower) { return .direction(dir) }
        return .appId(first)
    }

    private static func parseTabNav(_ positional: [String]) throws -> TabTarget {
        guard let first = positional.first?.lowercased() else {
            throw ConfigError("tab requires next|prev")
        }
        switch first {
        case "next": return .next
        case "prev": return .prev
        default:
            throw ConfigError("tab requires next|prev")
        }
    }

    private static func parseZoom(_ positional: [String]) throws -> ZoomTarget {
        guard let first = positional.first?.lowercased() else {
            throw ConfigError("zoom requires in|out|all|window|desktop")
        }
        guard let target = ZoomTarget(rawValue: first) else {
            throw ConfigError("zoom requires in|out|all|window|desktop")
        }
        return target
    }

    private static func parseViewIndex(_ positional: [String], verb: String) throws -> Int {
        guard let first = positional.first, let n = Int(first), (1...9).contains(n) else {
            throw ConfigError("\(verb) requires 1-9")
        }
        return n
    }
}
