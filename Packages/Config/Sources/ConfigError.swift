import Foundation

/// Config load / validation failure with a Dinky-style key path when applicable.
public struct ConfigError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    public var keyPath: String?

    public init(_ message: String, keyPath: String? = nil) {
        self.message = message
        self.keyPath = keyPath
    }

    public var description: String {
        if let keyPath, !keyPath.isEmpty {
            return "\(keyPath): \(message)"
        }
        return message
    }

    public static func unknownKey(_ path: String) -> ConfigError {
        ConfigError("unknown key", keyPath: path)
    }

    public static func notSupported(_ feature: String, keyPath: String) -> ConfigError {
        ConfigError("\(feature) is not supported", keyPath: keyPath)
    }

    public static func badType(_ expected: String, keyPath: String) -> ConfigError {
        ConfigError("expected \(expected)", keyPath: keyPath)
    }
}

public struct ConfigErrorList: Error, Equatable, Sendable, CustomStringConvertible {
    public var errors: [ConfigError]

    public init(_ errors: [ConfigError]) {
        self.errors = errors
    }

    public var description: String {
        errors.map(\.description).joined(separator: "\n")
    }
}
