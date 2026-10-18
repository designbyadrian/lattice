import Foundation

public enum BorderOrder: String, Sendable, Codable, Equatable {
    case below
    case above
}

public enum BorderColor: Sendable, Equatable {
    /// Lattice extension: system accent colour.
    case accent
    /// `#rrggbb` or `#rrggbbaa`.
    case hex(String)

    public static func parse(_ raw: String) throws -> BorderColor {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased() == "accent" { return .accent }
        guard s.hasPrefix("#") else {
            throw ConfigError("border colour must be '#rrggbb', '#rrggbbaa', or 'accent'")
        }
        let hex = String(s.dropFirst())
        guard hex.count == 6 || hex.count == 8,
              hex.allSatisfy(\.isHexDigit) else {
            throw ConfigError("border colour must be '#rrggbb', '#rrggbbaa', or 'accent'")
        }
        return .hex("#" + hex.lowercased())
    }
}

/// `[borders]` defaults (Lattice: enabled false).
public struct BordersConfig: Sendable, Equatable {
    public var enabled: Bool
    public var width: Double
    public var activeColor: BorderColor
    public var inactiveColor: BorderColor
    public var order: BorderOrder
    public var excludeApps: [String]

    public init(
        enabled: Bool = false,
        width: Double = 4,
        activeColor: BorderColor = .accent,
        inactiveColor: BorderColor = .hex("#494d64"),
        order: BorderOrder = .below,
        excludeApps: [String] = []
    ) {
        self.enabled = enabled
        self.width = width
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.order = order
        self.excludeApps = excludeApps
    }

    public static let `default` = BordersConfig()
}
