import Foundation

/// One key binding inside `[mode.<name>]`.
public struct KeyBinding: Sendable, Equatable {
    public var chord: KeyChord
    public var commands: [Command]

    public init(chord: KeyChord, commands: [Command]) {
        self.chord = chord
        self.commands = commands
    }
}

public struct ModeConfig: Sendable, Equatable {
    public var name: String
    public var bindings: [KeyBinding]

    public init(name: String, bindings: [KeyBinding] = []) {
        self.name = name
        self.bindings = bindings
    }
}
