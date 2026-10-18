import Foundation

/// Opaque native Space identifier (filled by PlatformMac in P6).
public struct SpaceID: Hashable, Codable, Sendable, Equatable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

/// How a workspace number maps onto a display pattern (config `[workspace-to-display]`).
public enum DisplayPattern: Equatable, Codable, Sendable {
    case main
    case secondary
    case nameSubstring(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum PatternType: String, Codable {
        case main
        case secondary
        case nameSubstring
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(PatternType.self, forKey: .type)
        switch type {
        case .main:
            self = .main
        case .secondary:
            self = .secondary
        case .nameSubstring:
            self = .nameSubstring(try c.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .main:
            try c.encode(PatternType.main, forKey: .type)
        case .secondary:
            try c.encode(PatternType.secondary, forKey: .type)
        case .nameSubstring(let s):
            try c.encode(PatternType.nameSubstring, forKey: .type)
            try c.encode(s, forKey: .value)
        }
    }
}

/// Declared workspace count and workspace→display patterns (config plan).
public struct WorkspacePlan: Equatable, Codable, Sendable {
    public var count: Int
    /// Workspace number → ordered display patterns to try.
    public var workspaceToDisplay: [Int: [DisplayPattern]]

    public init(count: Int = 1, workspaceToDisplay: [Int: [DisplayPattern]] = [:]) {
        self.count = max(1, count)
        self.workspaceToDisplay = workspaceToDisplay
    }
}

/// Runtime binding of workspace numbers to native Spaces Lattice created / tracks.
public struct WorkspaceSpaceBinding: Equatable, Codable, Sendable {
    public var binding: [Int: SpaceID]
    public var ownedSpaces: Set<SpaceID>

    public init(binding: [Int: SpaceID] = [:], ownedSpaces: Set<SpaceID> = []) {
        self.binding = binding
        self.ownedSpaces = ownedSpaces
    }
}
