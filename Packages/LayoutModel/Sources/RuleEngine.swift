import Foundation

/// Pure rule classifier following PLAN §7a semantics.
public enum RuleEngine: Sendable {
    /// Classify a new window. Every matching rule runs in file order; the last
    /// `layout floating` / `layout tiling` wins. Dialogs, sheets, panels and
    /// non-resizable windows always float. With `floatWindowsWithoutFullscreen`,
    /// a normal window whose fullscreen button is missing/disabled floats unless
    /// a `layout tiling` rule overrides (unless the bundle is exempt).
    public static func classify(
        facts: WindowFacts,
        rules: [WindowRule],
        config: RuleClassificationConfig = .default
    ) -> RuleClassification {
        var floating = !config.defaultTiling
        var ignore = false
        var postCommands: [LayoutCommand] = []
        var sawLayoutCommand = false

        // Intrinsic floaters.
        if facts.kind == .dialog || facts.kind == .sheet || facts.kind == .panel || !facts.resizable {
            floating = true
        }

        // Fullscreen-button heuristic (AeroSpace-style), overridable by tiling rule.
        var heuristicFloat = false
        if config.floatWindowsWithoutFullscreen,
           facts.kind == .normal,
           facts.resizable,
           !facts.fullscreenButtonEnabled {
            let exempt: Bool
            if let bundle = facts.bundleID {
                exempt = config.fullscreenButtonExemptions.contains(bundle)
            } else {
                exempt = false
            }
            if !exempt {
                heuristicFloat = true
                floating = true
            }
        }

        for rule in rules {
            guard matches(facts: facts, rule: rule) else { continue }
            for raw in rule.run {
                let command = LayoutCommand.parse(raw)
                switch command {
                case .layoutFloating:
                    floating = true
                    sawLayoutCommand = true
                case .layoutTiling:
                    floating = false
                    sawLayoutCommand = true
                    heuristicFloat = false
                case .ignore:
                    ignore = true
                default:
                    postCommands.append(command)
                }
            }
        }

        // Heuristic still applies when no explicit layout command ran.
        if heuristicFloat && !sawLayoutCommand {
            floating = true
        }

        // Intrinsic kinds cannot be forced to tile via rules.
        if facts.kind == .dialog || facts.kind == .sheet || facts.kind == .panel || !facts.resizable {
            floating = true
        }

        return RuleClassification(floating: floating, ignore: ignore, commands: postCommands)
    }

    public static func matches(facts: WindowFacts, rule: WindowRule) -> Bool {
        if let appId = rule.appId {
            guard facts.bundleID == appId else { return false }
        }
        if let kind = rule.kind {
            guard facts.kind == kind else { return false }
        }
        if let pattern = rule.appName {
            guard regex(pattern, matches: facts.appName) else { return false }
        }
        if let pattern = rule.title {
            guard regex(pattern, matches: facts.title) else { return false }
        }
        return true
    }

    private static func regex(_ pattern: String, matches text: String) -> Bool {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, options: [], range: range) != nil
    }
}
