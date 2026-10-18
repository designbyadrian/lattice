import Foundation

/// Parses `lattice://` URLs into `Command` values (PLAN §7 / ADDENDUM-2 §R).
public enum URLCommandParser {
    public enum URLCommandError: Error, Equatable, CustomStringConvertible {
        case invalidURL
        case unsupportedScheme(String)
        case unknownPath(String)
        case missingCommand
        case unknownQueryParameter(String)
        case execAndForgetRejected
        case parseFailed(String)

        public var description: String {
            switch self {
            case .invalidURL: return "invalid URL"
            case .unsupportedScheme(let s): return "unsupported scheme '\(s)'"
            case .unknownPath(let p): return "unknown path '\(p)'"
            case .missingCommand: return "missing cmd parameter"
            case .unknownQueryParameter(let k): return "unknown query parameter '\(k)'"
            case .execAndForgetRejected: return "exec-and-forget is not allowed via URL"
            case .parseFailed(let m): return m
            }
        }
    }

    /// Allowed query keys for `lattice://run`.
    public static let allowedRunQueryKeys: Set<String> = ["cmd"]

    public static func parse(_ url: URL) throws -> Command {
        guard let scheme = url.scheme?.lowercased() else {
            throw URLCommandError.invalidURL
        }
        guard scheme == "lattice" else {
            throw URLCommandError.unsupportedScheme(scheme)
        }

        let host = (url.host ?? "").lowercased()
        let pathParts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        // Short aliases: lattice://workspace/2, …
        if !host.isEmpty && host != "run" {
            return try parseAlias(host: host, pathParts: pathParts, url: url)
        }

        if host == "run" || (host.isEmpty && pathParts.first == "run") {
            return try parseRun(url: url, pathParts: pathParts)
        }

        if host.isEmpty, let first = pathParts.first {
            return try parseAlias(host: first, pathParts: Array(pathParts.dropFirst()), url: url)
        }

        throw URLCommandError.unknownPath(url.path.isEmpty ? host : url.path)
    }

    public static func parse(_ string: String) throws -> Command {
        guard let url = URL(string: string) else {
            throw URLCommandError.invalidURL
        }
        return try parse(url)
    }

    // MARK: - Private

    private static func parseRun(url: URL, pathParts: [String]) throws -> Command {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for item in items {
            guard allowedRunQueryKeys.contains(item.name) else {
                throw URLCommandError.unknownQueryParameter(item.name)
            }
        }
        guard let cmd = items.first(where: { $0.name == "cmd" })?.value,
              !cmd.isEmpty else {
            throw URLCommandError.missingCommand
        }
        _ = pathParts
        return try parseCommandString(cmd)
    }

    private static func parseAlias(host: String, pathParts: [String], url: URL) throws -> Command {
        // Reject any query params on aliases.
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           !items.isEmpty {
            throw URLCommandError.unknownQueryParameter(items[0].name)
        }

        switch host {
        case "workspace":
            guard let raw = pathParts.first else {
                throw URLCommandError.parseFailed("workspace alias requires a number")
            }
            return try CommandParser.parse("workspace \(raw)")
        case "reload-config":
            return .reloadConfig
        case "unmanage-all":
            return .unmanageAll
        case "dock-all":
            return .dockAll
        case "retile":
            return .retile
        case "enable":
            guard let raw = pathParts.first else {
                throw URLCommandError.parseFailed("enable alias requires on|off|toggle")
            }
            return try CommandParser.parse("enable \(raw)")
        case "mode":
            guard let raw = pathParts.first else {
                throw URLCommandError.parseFailed("mode alias requires a name")
            }
            return try CommandParser.parse("mode \(raw)")
        case "recall-view":
            guard let raw = pathParts.first else {
                throw URLCommandError.parseFailed("recall-view alias requires 1-9")
            }
            return try CommandParser.parse("recall-view \(raw)")
        case "store-view":
            guard let raw = pathParts.first else {
                throw URLCommandError.parseFailed("store-view alias requires 1-9")
            }
            return try CommandParser.parse("store-view \(raw)")
        case "focus":
            guard let raw = pathParts.first else {
                throw URLCommandError.parseFailed("focus alias requires a direction")
            }
            return try CommandParser.parse("focus \(raw)")
        case "pan":
            guard let raw = pathParts.first else {
                throw URLCommandError.parseFailed("pan alias requires a direction")
            }
            return try CommandParser.parse("pan \(raw)")
        case "desktop-area":
            guard let raw = pathParts.first else {
                throw URLCommandError.parseFailed("desktop-area alias requires show|hide|toggle")
            }
            return try CommandParser.parse("desktop-area \(raw)")
        default:
            throw URLCommandError.unknownPath(host)
        }
    }

    private static func parseCommandString(_ raw: String) throws -> Command {
        let command: Command
        do {
            command = try CommandParser.parse(raw)
        } catch {
            throw URLCommandError.parseFailed("\(error)")
        }
        if case .execAndForget = command {
            throw URLCommandError.execAndForgetRejected
        }
        return command
    }
}
