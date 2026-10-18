import Foundation

/// `[drag]` — drop placeholder overlays.
public struct DragConfig: Sendable, Equatable {
    public var placeholders: Bool

    public init(placeholders: Bool = true) {
        self.placeholders = placeholders
    }

    public static let `default` = DragConfig()
}
