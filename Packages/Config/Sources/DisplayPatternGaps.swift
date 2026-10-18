import Foundation

/// Gaps override for one `[display.<pattern>]` table.
public struct DisplayPatternGaps: Sendable, Equatable {
    public var pattern: String
    public var gaps: GapsConfig

    public init(pattern: String, gaps: GapsConfig) {
        self.pattern = pattern
        self.gaps = gaps
    }

    /// Prefer name patterns over `main`/`secondary`; longer pattern beats shorter.
    public static func resolve(
        displayName: String,
        isMain: Bool,
        isSecondary: Bool,
        overrides: [DisplayPatternGaps],
        fallback: GapsConfig
    ) -> GapsConfig {
        var best: (score: Int, gaps: GapsConfig)?
        for item in overrides {
            let key = item.pattern.lowercased()
            let match: Bool
            let score: Int
            switch key {
            case "main":
                match = isMain
                score = 1
            case "secondary":
                match = isSecondary
                score = 1
            default:
                match = displayName.localizedCaseInsensitiveContains(item.pattern)
                score = 10 + item.pattern.count
            }
            guard match else { continue }
            if best == nil || score > best!.score {
                best = (score, item.gaps)
            }
        }
        return best?.gaps ?? fallback
    }
}
