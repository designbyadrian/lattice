import Foundation

/// Persisted layout for one physical display, keyed by display UUID string.
public struct DisplayLayout: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var displayUUID: String
    /// Workspace number → tree. Numbers are 1-based to match config.
    public var workspaces: [Int: Workspace]
    public var schemaVersion: Int
    /// Saved camera views 1…9.
    public var savedViews: [Int: Camera]

    public init(
        displayUUID: String,
        workspaces: [Int: Workspace] = [1: .empty],
        schemaVersion: Int = DisplayLayout.currentSchemaVersion,
        savedViews: [Int: Camera] = [:]
    ) {
        self.displayUUID = displayUUID
        self.workspaces = workspaces
        self.schemaVersion = schemaVersion
        self.savedViews = savedViews.filter { (1...9).contains($0.key) }
    }

    public mutating func saveView(_ index: Int, camera: Camera) {
        guard (1...9).contains(index) else { return }
        savedViews[index] = camera
    }

    public func view(_ index: Int) -> Camera? {
        guard (1...9).contains(index) else { return nil }
        return savedViews[index]
    }
}
