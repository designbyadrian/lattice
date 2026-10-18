import Foundation

/// Which physical side of a modifier counts in bindings.
public enum ModifierSide: String, Sendable, Codable, Equatable, CaseIterable {
    case both
    case left
    case right
}

/// Modifier presence in a chord (logical, not left/right).
public struct ModifierSet: Sendable, Equatable, Hashable {
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var command: Bool

    public init(control: Bool = false, option: Bool = false, shift: Bool = false, command: Bool = false) {
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
    }

    public var isEmpty: Bool {
        !control && !option && !shift && !command
    }

    /// Parse a modifier-only chord such as `alt`, `ctrl-alt`, `cmd-shift`.
    public static func parseModifiers(_ raw: String) throws -> ModifierSet {
        let parts = raw.lowercased().split(separator: "-").map(String.init)
        guard !parts.isEmpty else {
            throw ConfigError("empty modifier chord")
        }
        var set = ModifierSet()
        for part in parts {
            switch part {
            case "ctrl", "control": set.control = true
            case "alt", "opt", "option": set.option = true
            case "shift": set.shift = true
            case "cmd", "command", "super": set.command = true
            default:
                throw ConfigError("unknown modifier '\(part)' in '\(raw)'")
            }
        }
        return set
    }
}

/// A binding chord: modifiers plus a US-layout key name (`h`, `enter`, `tab`, `1`, …).
public struct KeyChord: Sendable, Equatable, Hashable {
    public var modifiers: ModifierSet
    public var key: String

    public init(modifiers: ModifierSet, key: String) {
        self.modifiers = modifiers
        self.key = key.lowercased()
    }

    /// Parse `alt-shift-h`, `ctrl-alt-1`, `ctrl-alt-left-bracket`, etc.
    public static func parse(_ raw: String) throws -> KeyChord {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = trimmed.split(separator: "-").map(String.init)
        guard !parts.isEmpty else {
            throw ConfigError("empty key chord")
        }

        // Longest key match from the end (supports `left-bracket` / `right-bracket`).
        var key: String?
        var modifierNames: [String] = []
        for keyLen in stride(from: min(2, parts.count), through: 1, by: -1) {
            let candidate = parts.suffix(keyLen).joined(separator: "-")
            if isKnownKey(candidate) {
                key = normalizeKey(candidate)
                modifierNames = Array(parts.dropLast(keyLen))
                break
            }
        }
        guard let key else {
            throw ConfigError("unknown key in chord '\(raw)'")
        }

        var mods = ModifierSet()
        for part in modifierNames {
            switch part {
            case "ctrl", "control": mods.control = true
            case "alt", "opt", "option": mods.option = true
            case "shift": mods.shift = true
            case "cmd", "command", "super": mods.command = true
            default:
                throw ConfigError("unknown modifier '\(part)' in chord '\(raw)'")
            }
        }
        return KeyChord(modifiers: mods, key: key)
    }

    public var description: String {
        // Order matches ADDENDUM-2 B11 (`ctrl-alt-cmd-shift-…`).
        var parts: [String] = []
        if modifiers.control { parts.append("ctrl") }
        if modifiers.option { parts.append("alt") }
        if modifiers.command { parts.append("cmd") }
        if modifiers.shift { parts.append("shift") }
        parts.append(key)
        return parts.joined(separator: "-")
    }

    private static let knownKeys: Set<String> = [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "enter", "return", "tab", "space", "esc", "escape",
        "up", "down", "left", "right",
        "minus", "equal", "comma", "period", "slash", "backslash",
        "semicolon", "quote", "leftbracket", "rightbracket",
        "left-bracket", "right-bracket", "grave",
    ]

    public static func isKnownKey(_ key: String) -> Bool {
        knownKeys.contains(key.lowercased())
    }

    /// Canonical form used in bindings (`left-bracket`, not `leftbracket`).
    private static func normalizeKey(_ key: String) -> String {
        switch key.lowercased() {
        case "leftbracket": return "left-bracket"
        case "rightbracket": return "right-bracket"
        default: return key.lowercased()
        }
    }
}

/// Per-modifier side policy from `[modifiers]`.
public struct ModifiersConfig: Sendable, Equatable {
    public var alt: ModifierSide
    public var ctrl: ModifierSide
    public var cmd: ModifierSide
    public var shift: ModifierSide
    /// Lattice extension: modifier chord for frame-rect drag (default `cmd-shift`).
    public var frameModifier: ModifierSet
    /// Lattice extension: modifier chord for pinch-over-apps (default `alt`).
    public var pinchModifier: ModifierSet

    public init(
        alt: ModifierSide = .both,
        ctrl: ModifierSide = .both,
        cmd: ModifierSide = .both,
        shift: ModifierSide = .both,
        frameModifier: ModifierSet = ModifierSet(shift: true, command: true),
        pinchModifier: ModifierSet = ModifierSet(option: true)
    ) {
        self.alt = alt
        self.ctrl = ctrl
        self.cmd = cmd
        self.shift = shift
        self.frameModifier = frameModifier
        self.pinchModifier = pinchModifier
    }

    public static let `default` = ModifiersConfig()
}
