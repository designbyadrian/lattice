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
            errors.append(contentsOf: stubTableKeys(
                v, path: "animations", allowed: ["enabled", "duration-ms"]
            ))
        }
        if let v = table["drag"] {
            errors.append(contentsOf: stubTableKeys(v, path: "drag", allowed: ["placeholders"]))
        }
        if let v = table["hooks"] {
            errors.append(contentsOf: stubTableKeys(
                v,
                path: "hooks",
                allowed: [
                    "startup", "workspace-changing", "workspace-changed",
                    "focus-changed", "mode-changed",
                ]
            ))
        }
        if let v = table["workspace"] {
            errors.append(contentsOf: parseWorkspaceTables(v))
        }
        if let v = table["display"] {
            // Pattern tables deferred; reject unknown nested keys lightly.
            if !(v is [String: Any]) {
                errors.append(.badType("table", keyPath: "display"))
            }
        }
        if let v = table["rules"] {
            if !(v is [[String: Any]]) && !(v is [Any]) {
                errors.append(.badType("array of tables", keyPath: "rules"))
            }
        }

        if !errors.isEmpty {
            throw ConfigErrorList(errors)
        }
        return config
    }

    // MARK: - Sections

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

    private static func parseWorkspaceTables(_ value: Any) -> [ConfigError] {
        guard let table = value as? [String: Any] else {
            return [.badType("table", keyPath: "workspace")]
        }
        var errors: [ConfigError] = []
        let allowed: Set<String> = ["tiling"]
        let unsupported: Set<String> = ["layout", "columns", "rows", "expand"]
        for (name, raw) in table {
            guard let inner = raw as? [String: Any] else {
                errors.append(.badType("table", keyPath: "workspace.\(name)"))
                continue
            }
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
        }
        return errors
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

    private static func stubTableKeys(
        _ value: Any,
        path: String,
        allowed: Set<String>?
    ) -> [ConfigError] {
        guard let table = value as? [String: Any] else {
            return [.badType("table", keyPath: path)]
        }
        guard let allowed else { return [] }
        return table.keys.filter { !allowed.contains($0) }.map { .unknownKey("\(path).\($0)") }
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
