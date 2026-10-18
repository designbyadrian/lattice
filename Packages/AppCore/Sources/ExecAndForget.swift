import Foundation
import Config

/// Runs shell commands from hooks / bindings only (never URL). Fire-and-forget.
public enum ExecAndForget {
    /// Allowed sources for `exec-and-forget`.
    public enum Source: Sendable {
        case hook
        case binding
        case cli
    }

    @discardableResult
    public static func run(_ command: String, source: Source) -> Bool {
        switch source {
        case .hook, .binding, .cli:
            break
        }
        // Avoid `/bin/sh -c` string building with interpolation of secrets; pass via argv.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    public static func runIfPresent(_ command: Command, source: Source) -> Bool {
        guard case .execAndForget(let shell) = command else { return false }
        return run(shell, source: source)
    }
}
