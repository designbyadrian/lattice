import Foundation

/// Appends `[[rules]]` blocks to the TOML file without rewriting existing content.
public enum ConfigAppender {
    /// Build a TOML `[[rules]]` fragment for the given app (bundle id preferred).
    public static func ruleBlock(
        appId: String?,
        appName: String?,
        run: [String] = ["layout floating"]
    ) -> String {
        var lines: [String] = ["", "[[rules]]"]
        if let appId, !appId.isEmpty {
            lines.append("app-id = '\(escapeTOMLString(appId))'")
        } else if let appName, !appName.isEmpty {
            lines.append("app-name = '\(escapeTOMLString(NSRegularExpression.escapedPattern(for: appName)))'")
        }
        if run.count == 1 {
            lines.append("run = '\(escapeTOMLString(run[0]))'")
        } else {
            let quoted = run.map { "'\(escapeTOMLString($0))'" }.joined(separator: ", ")
            lines.append("run = [\(quoted)]")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Append a rule block to the file at `url`. Never rewrites the whole file.
    public static func appendRule(
        to url: URL,
        appId: String?,
        appName: String?,
        run: [String] = ["layout floating"],
        fileManager: FileManager = .default
    ) throws {
        let block = ruleBlock(appId: appId, appName: appName, run: run)
        if !fileManager.fileExists(atPath: url.path) {
            let dir = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(block.utf8).write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = block.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private static func escapeTOMLString(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}
