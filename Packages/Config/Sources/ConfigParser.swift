import Foundation
import LayoutModel
import enum Deserializer.TOMLDeserializer

/// Parses TOML into `LatticeConfig` with unknown-key and unsupported-feature errors.
public enum ConfigParser {
    private static let topLevelKeys: Set<String> = [
        "start-at-login",
        "workspaces",
        "default-tiling",
        "follow-app-activation",
        "float-windows-without-fullscreen",
        "menu-bar-controls",
        "default-layout",
        "gaps",
        "modifiers",
        "mouse",
        "borders",
        "focus-follows-mouse",
        "mode",
        "scrolling",
        "accordion",
        // Recognized Dinky tables (stubbed / deferred; known keys only).
        "workspace-to-display",
        "animations",
        "drag",
        "hooks",
        "rules",
        "workspace",
        "display",
        "layout",
        "zoom",
        "tabs",
        "desktop-area",
        "window-sizing",
        "experimental",
    ]

    public static func parse(text: String) throws -> LatticeConfig {
        let table: [String: Any]
        do {
            table = try TOMLDeserializer.tomlTable(with: text)
        } catch {
            throw ConfigError("invalid TOML: \(error)")
        }
        return try parse(table: table)
    }

    public static func parse(data: Data) throws -> LatticeConfig {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigError("config file is not valid UTF-8")
        }
        return try parse(text: text)
    }

    public static func parse(table: [String: Any]) throws -> LatticeConfig {
        var errors: [ConfigError] = []
        var config = LatticeConfig.default

        for key in table.keys {
            if !topLevelKeys.contains(key) {
                errors.append(.unknownKey(key))
            }
        }

        if table["default-layout"] != nil {
            errors.append(ConfigError(
                "Lattice has a single tree layout",
                keyPath: "default-layout"
            ))
        }
        if table["scrolling"] != nil {
            errors.append(.notSupported("[scrolling]", keyPath: "scrolling"))
        }
        if table["accordion"] != nil {
            errors.append(.notSupported("[accordion]", keyPath: "accordion"))
        }

        if let v = table["start-at-login"] {
            if let b = v as? Bool { config.startAtLogin = b }
            else { errors.append(.badType("bool", keyPath: "start-at-login")) }
        }
        if let v = table["workspaces"] {
            if let n = intValue(v), n >= 1 { config.workspaces = n }
            else { errors.append(.badType("positive integer", keyPath: "workspaces")) }
        }
        if let v = table["default-tiling"] {
            if let b = v as? Bool { config.defaultTiling = b }
            else { errors.append(.badType("bool", keyPath: "default-tiling")) }
        }
        if let v = table["follow-app-activation"] {
            if let b = v as? Bool { config.followAppActivation = b }
            else { errors.append(.badType("bool", keyPath: "follow-app-activation")) }
        }
        if let v = table["float-windows-without-fullscreen"] {
            if let b = v as? Bool { config.floatWindowsWithoutFullscreen = b }
            else { errors.append(.badType("bool", keyPath: "float-windows-without-fullscreen")) }
        }
        if let v = table["menu-bar-controls"] {
            do { config.menuBarControls = try parseMenuBarControls(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }

        if let gaps = table["gaps"] {
            do { config.gaps = try parseGaps(gaps) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }

        if let modifiers = table["modifiers"] {
            do { config.modifiers = try parseModifiers(modifiers) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }

        if let mouse = table["mouse"] {
            do { config.mouse = try parseMouse(mouse) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }

        if let borders = table["borders"] {
            do { config.borders = try parseBorders(borders) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }

        if let ffm = table["focus-follows-mouse"] {
            do { config.focusFollowsMouse = try parseFocusFollowsMouse(ffm) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }

        if let modeTable = table["mode"] {
            do { config.modes = try parseModes(modeTable) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }

        if let v = table["workspace-to-display"] {
            do { config.workspaceToDisplay = try parseWorkspaceToDisplay(v, workspaces: config.workspaces) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["animations"] {
            do { config.animations = try parseAnimations(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["drag"] {
            do { config.drag = try parseDrag(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["hooks"] {
            do { config.hooks = try parseHooks(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["workspace"] {
            do { config.workspaceConfigs = try parseWorkspaceTables(v, workspaces: config.workspaces) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["display"] {
            do { config.displayGaps = try parseDisplayTables(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["rules"] {
            do { config.rules = try parseRules(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["layout"] {
            do { config.layout = try parseLayoutGeometry(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["zoom"] {
            do { config.zoom = try parseZoomConfig(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["tabs"] {
            do { config.tabs = try parseTabsConfig(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["desktop-area"] {
            do { config.desktopArea = try parseDesktopAreaConfig(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["window-sizing"] {
            do { config.windowSizing = try parseWindowSizingConfig(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }
        if let v = table["experimental"] {
            do { config.experimental = try parseExperimental(v) }
            catch let e as ConfigError { errors.append(e) }
            catch let e as ConfigErrorList { errors.append(contentsOf: e.errors) }
        }

        if !errors.isEmpty {
            throw ConfigErrorList(errors)
        }
        return config
    }

    // MARK: - Sections

    private static func parseExperimental(_ value: Any) throws -> ExperimentalConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "experimental")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = ["ax-window-id", "multitouch"]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("experimental.\(key)"))
        }
        var config = ExperimentalConfig.default
        if let v = table["ax-window-id"] {
            if let b = v as? Bool { config.axWindowID = b }
            else { errors.append(.badType("bool", keyPath: "experimental.ax-window-id")) }
        }
        if let v = table["multitouch"] {
            if let b = v as? Bool { config.multitouch = b }
            else { errors.append(.badType("bool", keyPath: "experimental.multitouch")) }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseGaps(_ value: Any) throws -> GapsConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "gaps")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = ["inner", "outer"]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("gaps.\(key)"))
        }
        var gaps = GapsConfig.default
        if let inner = table["inner"] {
            do { gaps.inner = try parseGapValue(inner, path: "gaps.inner") }
            catch let e as ConfigError { errors.append(e) }
        }
        if let outer = table["outer"] {
            do { gaps.outer = try parseGapValue(outer, path: "gaps.outer") }
            catch let e as ConfigError { errors.append(e) }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return gaps
    }

    private static func parseGapValue(_ value: Any, path: String) throws -> GapValue {
        if let n = doubleValue(value) {
            return .uniform(n)
        }
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("number or per-side table", keyPath: path)
        }
        let axisKeys: Set<String> = ["horizontal", "vertical"]
        let sideKeys: Set<String> = ["left", "right", "top", "bottom"]
        let allowed = axisKeys.union(sideKeys)
        for key in table.keys where !allowed.contains(key) {
            throw ConfigError.unknownKey("\(path).\(key)")
        }
        if table.keys.contains(where: { axisKeys.contains($0) }) {
            func axis(_ name: String) throws -> Double {
                guard let v = table[name] else { return 0 }
                guard let n = doubleValue(v) else {
                    throw ConfigError.badType("number", keyPath: "\(path).\(name)")
                }
                return n
            }
            let h = try axis("horizontal")
            let v = try axis("vertical")
            return .perSide(GapInsetsConfig(left: h, right: h, top: v, bottom: v))
        }
        func side(_ name: String) throws -> Double {
            guard let v = table[name] else { return 0 }
            guard let n = doubleValue(v) else {
                throw ConfigError.badType("number", keyPath: "\(path).\(name)")
            }
            return n
        }
        return .perSide(GapInsetsConfig(
            left: try side("left"),
            right: try side("right"),
            top: try side("top"),
            bottom: try side("bottom")
        ))
    }

    private static func parseMenuBarControls(_ value: Any) throws -> [MenuBarControl] {
        let list: [String]
        if let typed = value as? [String] {
            list = typed
        } else if let anyList = value as? [Any], let strings = anyList as? [String] {
            list = strings
        } else {
            throw ConfigError.badType("array of strings", keyPath: "menu-bar-controls")
        }
        var result: [MenuBarControl] = []
        for (i, raw) in list.enumerated() {
            guard let control = MenuBarControl(rawValue: raw) else {
                throw ConfigError(
                    "unknown menu-bar control '\(raw)'",
                    keyPath: "menu-bar-controls[\(i)]"
                )
            }
            result.append(control)
        }
        return result
    }

    private static func parseModifiers(_ value: Any) throws -> ModifiersConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "modifiers")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = [
            "alt", "ctrl", "cmd", "shift", "frame-modifier", "pinch-modifier",
        ]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("modifiers.\(key)"))
        }
        var config = ModifiersConfig.default
        func side(_ name: String) {
            guard let v = table[name] else { return }
            guard let s = v as? String, let side = ModifierSide(rawValue: s) else {
                errors.append(.badType("'both'|'left'|'right'", keyPath: "modifiers.\(name)"))
                return
            }
            switch name {
            case "alt": config.alt = side
            case "ctrl": config.ctrl = side
            case "cmd": config.cmd = side
            case "shift": config.shift = side
            default: break
            }
        }
        side("alt"); side("ctrl"); side("cmd"); side("shift")

        if let v = table["frame-modifier"] {
            if let s = v as? String {
                do { config.frameModifier = try ModifierSet.parseModifiers(s) }
                catch { errors.append(ConfigError("\(error)", keyPath: "modifiers.frame-modifier")) }
            } else {
                errors.append(.badType("string", keyPath: "modifiers.frame-modifier"))
            }
        }
        if let v = table["pinch-modifier"] {
            if let s = v as? String {
                do { config.pinchModifier = try ModifierSet.parseModifiers(s) }
                catch { errors.append(ConfigError("\(error)", keyPath: "modifiers.pinch-modifier")) }
            } else {
                errors.append(.badType("string", keyPath: "modifiers.pinch-modifier"))
            }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseMouse(_ value: Any) throws -> MouseConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "mouse")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = ["double-click-desktop", "double-click-title"]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("mouse.\(key)"))
        }
        var config = MouseConfig.default
        if let v = table["double-click-desktop"] {
            if let s = v as? String {
                do { config.doubleClickDesktop = try MouseDoubleClickAction.parse(s) }
                catch { errors.append(ConfigError("\(error)", keyPath: "mouse.double-click-desktop")) }
            } else {
                errors.append(.badType("string", keyPath: "mouse.double-click-desktop"))
            }
        }
        if let v = table["double-click-title"] {
            if let s = v as? String {
                do { config.doubleClickTitle = try MouseDoubleClickAction.parse(s) }
                catch { errors.append(ConfigError("\(error)", keyPath: "mouse.double-click-title")) }
            } else {
                errors.append(.badType("string", keyPath: "mouse.double-click-title"))
            }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseBorders(_ value: Any) throws -> BordersConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "borders")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = [
            "enabled", "width", "active-color", "inactive-color", "order", "exclude-apps",
        ]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("borders.\(key)"))
        }
        var config = BordersConfig.default
        if let v = table["enabled"] {
            if let b = v as? Bool { config.enabled = b }
            else { errors.append(.badType("bool", keyPath: "borders.enabled")) }
        }
        if let v = table["width"] {
            if let n = doubleValue(v) { config.width = n }
            else { errors.append(.badType("number", keyPath: "borders.width")) }
        }
        if let v = table["active-color"] {
            if let s = v as? String {
                do { config.activeColor = try BorderColor.parse(s) }
                catch { errors.append(ConfigError("\(error)", keyPath: "borders.active-color")) }
            } else {
                errors.append(.badType("string", keyPath: "borders.active-color"))
            }
        }
        if let v = table["inactive-color"] {
            if let s = v as? String {
                do { config.inactiveColor = try BorderColor.parse(s) }
                catch { errors.append(ConfigError("\(error)", keyPath: "borders.inactive-color")) }
            } else {
                errors.append(.badType("string", keyPath: "borders.inactive-color"))
            }
        }
        if let v = table["order"] {
            if let s = v as? String, let order = BorderOrder(rawValue: s) {
                config.order = order
            } else {
                errors.append(.badType("'below'|'above'", keyPath: "borders.order"))
            }
        }
        if let v = table["exclude-apps"] {
            if let list = v as? [Any], let apps = list as? [String] {
                config.excludeApps = apps
            } else if let list = v as? [String] {
                config.excludeApps = list
            } else {
                errors.append(.badType("array of strings", keyPath: "borders.exclude-apps"))
            }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseFocusFollowsMouse(_ value: Any) throws -> FocusFollowsMouseConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "focus-follows-mouse")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = ["enabled", "delay-ms", "accordion-edges", "exclude-apps"]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("focus-follows-mouse.\(key)"))
        }
        var config = FocusFollowsMouseConfig.default
        if let v = table["enabled"] {
            if let b = v as? Bool { config.enabled = b }
            else { errors.append(.badType("bool", keyPath: "focus-follows-mouse.enabled")) }
        }
        if let v = table["delay-ms"] {
            if let n = intValue(v) { config.delayMs = n }
            else { errors.append(.badType("integer", keyPath: "focus-follows-mouse.delay-ms")) }
        }
        if let v = table["accordion-edges"] {
            if let b = v as? Bool { config.accordionEdges = b }
            else { errors.append(.badType("bool", keyPath: "focus-follows-mouse.accordion-edges")) }
        }
        if let v = table["exclude-apps"] {
            if let list = v as? [String] {
                config.excludeApps = list
            } else if let list = v as? [Any], let apps = list as? [String] {
                config.excludeApps = apps
            } else {
                errors.append(.badType("array of strings", keyPath: "focus-follows-mouse.exclude-apps"))
            }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseModes(_ value: Any) throws -> [String: ModeConfig] {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "mode")
        }
        var errors: [ConfigError] = []
        var modes: [String: ModeConfig] = [:]
        for (name, raw) in table {
            guard let bindingsTable = raw as? [String: Any] else {
                errors.append(.badType("table", keyPath: "mode.\(name)"))
                continue
            }
            var bindings: [KeyBinding] = []
            for (chordRaw, bindingValue) in bindingsTable {
                let path = "mode.\(name).\(chordRaw)"
                do {
                    let chord = try KeyChord.parse(chordRaw)
                    let commands = try CommandParser.parseBindingValue(bindingValue, keyPath: path)
                    bindings.append(KeyBinding(chord: chord, commands: commands))
                } catch let e as ConfigError {
                    var err = e
                    if err.keyPath == nil { err.keyPath = path }
                    errors.append(err)
                } catch {
                    errors.append(ConfigError("\(error)", keyPath: path))
                }
            }
            modes[name] = ModeConfig(name: name, bindings: bindings)
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        if modes.isEmpty {
            return [DefaultBindings.modeName: DefaultBindings.mainMode()]
        }
        return modes
    }

    private static func parseWorkspaceTables(
        _ value: Any,
        workspaces: Int
    ) throws -> [Int: WorkspaceConfig] {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "workspace")
        }
        var errors: [ConfigError] = []
        var result: [Int: WorkspaceConfig] = [:]
        let allowed: Set<String> = ["tiling"]
        let unsupported: Set<String> = ["layout", "columns", "rows", "expand"]
        for (name, raw) in table {
            guard let number = Int(name), number >= 1, number <= workspaces else {
                errors.append(ConfigError(
                    "workspace number must be in 1…\(workspaces)",
                    keyPath: "workspace.\(name)"
                ))
                continue
            }
            guard let inner = raw as? [String: Any] else {
                errors.append(.badType("table", keyPath: "workspace.\(name)"))
                continue
            }
            var wc = WorkspaceConfig()
            for key in inner.keys {
                if unsupported.contains(key) {
                    errors.append(.notSupported(
                        "workspace.\(name).\(key)",
                        keyPath: "workspace.\(name).\(key)"
                    ))
                } else if !allowed.contains(key) {
                    errors.append(.unknownKey("workspace.\(name).\(key)"))
                }
            }
            if let v = inner["tiling"] {
                if let b = v as? Bool {
                    wc.tiling = b
                } else {
                    errors.append(.badType("bool", keyPath: "workspace.\(name).tiling"))
                }
            }
            result[number] = wc
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return result
    }

    private static func parseDisplayTables(_ value: Any) throws -> [DisplayPatternGaps] {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "display")
        }
        var errors: [ConfigError] = []
        var result: [DisplayPatternGaps] = []
        let allowed: Set<String> = ["inner", "outer"]
        for (pattern, raw) in table {
            guard let inner = raw as? [String: Any] else {
                errors.append(.badType("table", keyPath: "display.\(pattern)"))
                continue
            }
            for key in inner.keys where !allowed.contains(key) {
                errors.append(.unknownKey("display.\(pattern).\(key)"))
            }
            do {
                let gaps = try parseGapsTable(inner, path: "display.\(pattern)")
                result.append(DisplayPatternGaps(pattern: pattern, gaps: gaps))
            } catch let e as ConfigError {
                errors.append(e)
            } catch let e as ConfigErrorList {
                errors.append(contentsOf: e.errors)
            }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return result
    }

    private static func parseGapsTable(_ table: [String: Any], path: String) throws -> GapsConfig {
        var gaps = GapsConfig.default
        if let inner = table["inner"] {
            gaps.inner = try parseGapValue(inner, path: "\(path).inner")
        }
        if let outer = table["outer"] {
            gaps.outer = try parseGapValue(outer, path: "\(path).outer")
        }
        return gaps
    }

    private static func parseAnimations(_ value: Any) throws -> AnimationsConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "animations")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = ["enabled", "duration-ms"]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("animations.\(key)"))
        }
        var config = AnimationsConfig.default
        if let v = table["enabled"] {
            if let b = v as? Bool { config.enabled = b }
            else { errors.append(.badType("bool", keyPath: "animations.enabled")) }
        }
        if let v = table["duration-ms"] {
            if let n = intValue(v), n >= 0 { config.durationMs = n }
            else { errors.append(.badType("non-negative integer", keyPath: "animations.duration-ms")) }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseDrag(_ value: Any) throws -> DragConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "drag")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = ["placeholders"]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("drag.\(key)"))
        }
        var config = DragConfig.default
        if let v = table["placeholders"] {
            if let b = v as? Bool { config.placeholders = b }
            else { errors.append(.badType("bool", keyPath: "drag.placeholders")) }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseHooks(_ value: Any) throws -> HooksConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "hooks")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = [
            "startup", "workspace-changing", "workspace-changed",
            "focus-changed", "mode-changed",
        ]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("hooks.\(key)"))
        }
        var config = HooksConfig.default
        func hook(_ name: String) -> [Command] {
            guard let raw = table[name] else { return [] }
            do {
                return try CommandParser.parseBindingValue(raw, keyPath: "hooks.\(name)")
            } catch let e as ConfigError {
                errors.append(e)
                return []
            } catch {
                errors.append(ConfigError("\(error)", keyPath: "hooks.\(name)"))
                return []
            }
        }
        config.startup = hook("startup")
        config.workspaceChanging = hook("workspace-changing")
        config.workspaceChanged = hook("workspace-changed")
        config.focusChanged = hook("focus-changed")
        config.modeChanged = hook("mode-changed")
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseRules(_ value: Any) throws -> [WindowRule] {
        let rows: [[String: Any]]
        if let typed = value as? [[String: Any]] {
            rows = typed
        } else if let anyList = value as? [Any] {
            rows = try anyList.enumerated().map { index, item in
                guard let table = item as? [String: Any] else {
                    throw ConfigError.badType("table", keyPath: "rules[\(index)]")
                }
                return table
            }
        } else {
            throw ConfigError.badType("array of tables", keyPath: "rules")
        }

        var errors: [ConfigError] = []
        var rules: [WindowRule] = []
        let allowed: Set<String> = ["app-id", "app-name", "title", "kind", "run"]

        for (index, table) in rows.enumerated() {
            let path = "rules[\(index)]"
            for key in table.keys where !allowed.contains(key) {
                errors.append(.unknownKey("\(path).\(key)"))
            }
            var rule = WindowRule(run: [])
            if let v = table["app-id"] {
                if let s = v as? String { rule.appId = s }
                else { errors.append(.badType("string", keyPath: "\(path).app-id")) }
            }
            if let v = table["app-name"] {
                if let s = v as? String {
                    if (try? NSRegularExpression(pattern: s, options: [.caseInsensitive])) == nil {
                        errors.append(ConfigError("invalid regex", keyPath: "\(path).app-name"))
                    } else {
                        rule.appName = s
                    }
                } else {
                    errors.append(.badType("string", keyPath: "\(path).app-name"))
                }
            }
            if let v = table["title"] {
                if let s = v as? String {
                    if (try? NSRegularExpression(pattern: s, options: [.caseInsensitive])) == nil {
                        errors.append(ConfigError("invalid regex", keyPath: "\(path).title"))
                    } else {
                        rule.title = s
                    }
                } else {
                    errors.append(.badType("string", keyPath: "\(path).title"))
                }
            }
            if let v = table["kind"] {
                if let s = v as? String, let kind = WindowKind(rawValue: s) {
                    rule.kind = kind
                } else {
                    errors.append(.badType("'normal'|'dialog'|'sheet'|'panel'", keyPath: "\(path).kind"))
                }
            }
            if let v = table["run"] {
                if let s = v as? String {
                    rule.run = [s]
                } else if let list = v as? [Any], let strings = list as? [String] {
                    rule.run = strings
                } else if let list = v as? [String] {
                    rule.run = list
                } else {
                    errors.append(.badType("string or array of strings", keyPath: "\(path).run"))
                }
            } else {
                errors.append(ConfigError("run is required", keyPath: "\(path).run"))
            }
            // Skip commands that fail to parse (PLAN §7a); keep the strings for LayoutCommand.parse.
            rules.append(rule)
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return rules
    }

    private static func parseWorkspaceToDisplay(
        _ value: Any,
        workspaces: Int
    ) throws -> [Int: [DisplayPattern]] {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "workspace-to-display")
        }
        var result: [Int: [DisplayPattern]] = [:]
        var errors: [ConfigError] = []
        for (key, raw) in table {
            guard let number = Int(key), number >= 1, number <= workspaces else {
                errors.append(ConfigError(
                    "workspace number must be in 1…\(workspaces)",
                    keyPath: "workspace-to-display.\(key)"
                ))
                continue
            }
            do {
                result[number] = try parseDisplayPatterns(raw, keyPath: "workspace-to-display.\(key)")
            } catch let e as ConfigError {
                errors.append(e)
            }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return result
    }

    private static func parseDisplayPatterns(_ value: Any, keyPath: String) throws -> [DisplayPattern] {
        if let s = value as? String {
            return [try parseOneDisplayPattern(s, keyPath: keyPath)]
        }
        if let arr = value as? [Any] {
            return try arr.map { item in
                guard let s = item as? String else {
                    throw ConfigError.badType("string", keyPath: keyPath)
                }
                return try parseOneDisplayPattern(s, keyPath: keyPath)
            }
        }
        throw ConfigError.badType("string or array of strings", keyPath: keyPath)
    }

    private static func parseOneDisplayPattern(_ raw: String, keyPath: String) throws -> DisplayPattern {
        switch raw.lowercased() {
        case "main": return .main
        case "secondary": return .secondary
        default:
            guard !raw.isEmpty else {
                throw ConfigError("empty display pattern", keyPath: keyPath)
            }
            return .nameSubstring(raw)
        }
    }

    // MARK: - Lattice extension tables (ADDENDUM-3 §9)

    private static func parseLayoutGeometry(_ value: Any) throws -> LayoutGeometryConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "layout")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = [
            "insert-takes-from", "insert-ratio", "close-gives-to", "live-visible-fraction",
            "min-ratio", "shrink-past-app-minimum", "tile-floor", "fallback-min-size",
            "drop-edge-fraction", "screen-edge-band",
        ]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("layout.\(key)"))
        }
        var config = LayoutGeometryConfig.default
        if let v = table["insert-takes-from"] {
            if let s = v as? String, let mode = InsertTakesFrom(rawValue: s) {
                config.insertTakesFrom = mode
            } else {
                errors.append(.badType("'target'|'row'", keyPath: "layout.insert-takes-from"))
            }
        }
        if let v = table["insert-ratio"] {
            if let n = doubleValue(v), (0.15...0.85).contains(n) { config.insertRatio = n }
            else { errors.append(.badType("float 0.15–0.85", keyPath: "layout.insert-ratio")) }
        }
        if let v = table["close-gives-to"] {
            if let s = v as? String, let mode = CloseGivesTo(rawValue: s) {
                config.closeGivesTo = mode
            } else {
                errors.append(.badType("'donor'|'row'|'neighbour'", keyPath: "layout.close-gives-to"))
            }
        }
        if let v = table["live-visible-fraction"] {
            if let n = doubleValue(v), (0.5...1).contains(n) { config.liveVisibleFraction = n }
            else { errors.append(.badType("float 0.5–1", keyPath: "layout.live-visible-fraction")) }
        }
        if let v = table["min-ratio"] {
            if let n = doubleValue(v), (0.005...0.2).contains(n) { config.minRatio = n }
            else { errors.append(.badType("float 0.005–0.2", keyPath: "layout.min-ratio")) }
        }
        if let v = table["shrink-past-app-minimum"] {
            if let b = v as? Bool { config.shrinkPastAppMinimum = b }
            else { errors.append(.badType("bool", keyPath: "layout.shrink-past-app-minimum")) }
        }
        if let v = table["tile-floor"] {
            do { config.tileFloor = try parseSizePair(v, path: "layout.tile-floor") }
            catch let e as ConfigError { errors.append(e) }
        }
        if let v = table["fallback-min-size"] {
            do { config.fallbackMinSize = try parseSizePair(v, path: "layout.fallback-min-size") }
            catch let e as ConfigError { errors.append(e) }
        }
        if let v = table["drop-edge-fraction"] {
            if let n = doubleValue(v), (0.1...0.45).contains(n) { config.dropEdgeFraction = n }
            else { errors.append(.badType("float 0.1–0.45", keyPath: "layout.drop-edge-fraction")) }
        }
        if let v = table["screen-edge-band"] {
            if let n = intValue(v) { config.screenEdgeBand = n }
            else { errors.append(.badType("integer", keyPath: "layout.screen-edge-band")) }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseZoomConfig(_ value: Any) throws -> ZoomConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "zoom")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = [
            "icon-tile-slack", "group-tile-below", "group-tile-above", "still-timeout-ms",
        ]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("zoom.\(key)"))
        }
        var config = ZoomConfig.default
        if let v = table["icon-tile-slack"] {
            if let n = intValue(v) { config.iconTileSlack = n }
            else { errors.append(.badType("integer", keyPath: "zoom.icon-tile-slack")) }
        }
        if let v = table["group-tile-below"] {
            if let n = intValue(v) { config.groupTileBelow = n }
            else { errors.append(.badType("integer", keyPath: "zoom.group-tile-below")) }
        }
        if let v = table["group-tile-above"] {
            if let n = intValue(v) { config.groupTileAbove = n }
            else { errors.append(.badType("integer", keyPath: "zoom.group-tile-above")) }
        }
        if let v = table["still-timeout-ms"] {
            if let n = intValue(v) { config.stillTimeoutMs = n }
            else { errors.append(.badType("integer", keyPath: "zoom.still-timeout-ms")) }
        }
        if config.groupTileAbove <= config.groupTileBelow {
            errors.append(ConfigError(
                "group-tile-above must be greater than group-tile-below",
                keyPath: "zoom.group-tile-above"
            ))
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseTabsConfig(_ value: Any) throws -> TabsConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "tabs")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = [
            "tab-bar-height", "tab-bar-ref-size", "tab-bar-min-scale", "tab-bar-hide-below",
        ]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("tabs.\(key)"))
        }
        var config = TabsConfig.default
        if let v = table["tab-bar-height"] {
            if let n = intValue(v) { config.tabBarHeight = n }
            else { errors.append(.badType("integer", keyPath: "tabs.tab-bar-height")) }
        }
        if let v = table["tab-bar-ref-size"] {
            do { config.tabBarRefSize = try parseSizePair(v, path: "tabs.tab-bar-ref-size") }
            catch let e as ConfigError { errors.append(e) }
        }
        if let v = table["tab-bar-min-scale"] {
            if let n = doubleValue(v) { config.tabBarMinScale = n }
            else { errors.append(.badType("number", keyPath: "tabs.tab-bar-min-scale")) }
        }
        if let v = table["tab-bar-hide-below"] {
            if let n = intValue(v) { config.tabBarHideBelow = n }
            else { errors.append(.badType("integer", keyPath: "tabs.tab-bar-hide-below")) }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseDesktopAreaConfig(_ value: Any) throws -> DesktopAreaConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "desktop-area")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = [
            "min-size", "reshow-ratio", "drop-edge-fraction", "drop-edge-max",
            "float-max-fraction", "float-margin", "float-cascade",
            "sole-float-fills", "float-nudge-in",
        ]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("desktop-area.\(key)"))
        }
        var config = DesktopAreaConfig.default
        if let v = table["min-size"] {
            do { config.minSize = try parseSizePair(v, path: "desktop-area.min-size") }
            catch let e as ConfigError { errors.append(e) }
        }
        if let v = table["reshow-ratio"] {
            if let n = doubleValue(v) { config.reshowRatio = n }
            else { errors.append(.badType("number", keyPath: "desktop-area.reshow-ratio")) }
        }
        if let v = table["drop-edge-fraction"] {
            if let n = doubleValue(v) { config.dropEdgeFraction = n }
            else { errors.append(.badType("number", keyPath: "desktop-area.drop-edge-fraction")) }
        }
        if let v = table["drop-edge-max"] {
            if let n = intValue(v) { config.dropEdgeMax = n }
            else { errors.append(.badType("integer", keyPath: "desktop-area.drop-edge-max")) }
        }
        if let v = table["float-max-fraction"] {
            if let n = doubleValue(v), (0.3...1).contains(n) { config.floatMaxFraction = n }
            else { errors.append(.badType("float 0.3–1", keyPath: "desktop-area.float-max-fraction")) }
        }
        if let v = table["float-margin"] {
            if let n = intValue(v) { config.floatMargin = n }
            else { errors.append(.badType("integer", keyPath: "desktop-area.float-margin")) }
        }
        if let v = table["float-cascade"] {
            if let n = intValue(v) { config.floatCascade = n }
            else { errors.append(.badType("integer", keyPath: "desktop-area.float-cascade")) }
        }
        if let v = table["sole-float-fills"] {
            if let b = v as? Bool { config.soleFloatFills = b }
            else { errors.append(.badType("bool", keyPath: "desktop-area.sole-float-fills")) }
        }
        if let v = table["float-nudge-in"] {
            if let b = v as? Bool { config.floatNudgeIn = b }
            else { errors.append(.badType("bool", keyPath: "desktop-area.float-nudge-in")) }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseWindowSizingConfig(_ value: Any) throws -> WindowSizingConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "window-sizing")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = [
            "ax-retries", "ax-readback-delay-ms", "ax-retry-interval-ms", "ax-retry-window-ms",
            "ax-size-tolerance", "ax-max-resolves", "learn-minimums",
        ]
        for key in table.keys where !allowed.contains(key) {
            errors.append(.unknownKey("window-sizing.\(key)"))
        }
        var config = WindowSizingConfig.default
        if let v = table["ax-retries"] {
            if let n = intValue(v), (1...5).contains(n) { config.axRetries = n }
            else { errors.append(.badType("integer 1–5", keyPath: "window-sizing.ax-retries")) }
        }
        if let v = table["ax-readback-delay-ms"] {
            if let n = intValue(v) { config.axReadbackDelayMs = n }
            else { errors.append(.badType("integer", keyPath: "window-sizing.ax-readback-delay-ms")) }
        }
        if let v = table["ax-retry-interval-ms"] {
            if let n = intValue(v) { config.axRetryIntervalMs = n }
            else { errors.append(.badType("integer", keyPath: "window-sizing.ax-retry-interval-ms")) }
        }
        if let v = table["ax-retry-window-ms"] {
            if let n = intValue(v) { config.axRetryWindowMs = n }
            else { errors.append(.badType("integer", keyPath: "window-sizing.ax-retry-window-ms")) }
        }
        if let v = table["ax-size-tolerance"] {
            if let n = intValue(v) { config.axSizeTolerance = n }
            else { errors.append(.badType("integer", keyPath: "window-sizing.ax-size-tolerance")) }
        }
        if let v = table["ax-max-resolves"] {
            if let n = intValue(v), (0...5).contains(n) { config.axMaxResolves = n }
            else { errors.append(.badType("integer 0–5", keyPath: "window-sizing.ax-max-resolves")) }
        }
        if let v = table["learn-minimums"] {
            if let b = v as? Bool { config.learnMinimums = b }
            else { errors.append(.badType("bool", keyPath: "window-sizing.learn-minimums")) }
        }
        if !errors.isEmpty { throw ConfigErrorList(errors) }
        return config
    }

    private static func parseSizePair(_ value: Any, path: String) throws -> (width: Double, height: Double) {
        let list: [Any]
        if let typed = value as? [Any] {
            list = typed
        } else {
            throw ConfigError.badType("[w, h]", keyPath: path)
        }
        guard list.count == 2,
              let w = doubleValue(list[0]),
              let h = doubleValue(list[1]) else {
            throw ConfigError.badType("[w, h]", keyPath: path)
        }
        return (w, h)
    }

    // MARK: - Numbers

    private static func intValue(_ value: Any) -> Int? {
        if let i = value as? Int { return i }
        if let i64 = value as? Int64 { return Int(i64) }
        if let d = value as? Double { return Int(d) }
        return nil
    }

    private static func doubleValue(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let i64 = value as? Int64 { return Double(i64) }
        return nil
    }
}
