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
        "overview-previews",
        "default-layout",
        "gaps",
        "modifiers",
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
        "overview",
        "tabs",
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
        if let v = table["overview-previews"] {
            if let s = v as? String, let mode = OverviewPreviewsMode(rawValue: s) {
                config.overviewPreviews = mode
            } else {
                errors.append(.badType("'auto'|'live'|'snapshots'|'off'", keyPath: "overview-previews"))
            }
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
        let allowed: Set<String> = ["left", "right", "top", "bottom"]
        for key in table.keys where !allowed.contains(key) {
            throw ConfigError.unknownKey("\(path).\(key)")
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

    private static func parseModifiers(_ value: Any) throws -> ModifiersConfig {
        guard let table = value as? [String: Any] else {
            throw ConfigError.badType("table", keyPath: "modifiers")
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = [
            "alt", "ctrl", "cmd", "shift", "drag-modifier", "pinch-modifier",
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

        if let v = table["drag-modifier"] {
            if let s = v as? String {
                do { config.dragModifier = try ModifierSet.parseModifiers(s) }
                catch { errors.append(ConfigError("\(error)", keyPath: "modifiers.drag-modifier")) }
            } else {
                errors.append(.badType("string", keyPath: "modifiers.drag-modifier"))
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
