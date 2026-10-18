import Foundation

/// `lattice doctor` — validate a config file and report issues.
public enum Doctor {
    public struct Report: Sendable, Equatable {
        public var configPath: String
        public var ok: Bool
        public var errors: [String]
        public var notices: [String]

        public init(
            configPath: String,
            ok: Bool,
            errors: [String] = [],
            notices: [String] = []
        ) {
            self.configPath = configPath
            self.ok = ok
            self.errors = errors
            self.notices = notices
        }

        public var text: String {
            var lines: [String] = []
            lines.append("lattice doctor: \(configPath)")
            if ok {
                lines.append("OK")
            } else {
                lines.append("FAILED (\(errors.count) error(s))")
                for e in errors {
                    lines.append("  error: \(e)")
                }
            }
            for n in notices {
                lines.append("  notice: \(n)")
            }
            return lines.joined(separator: "\n")
        }
    }

    public static func check(configURL: URL, fileManager: FileManager = .default) -> Report {
        let path = configURL.path
        guard fileManager.fileExists(atPath: path) else {
            return Report(
                configPath: path,
                ok: false,
                errors: ["config file not found"],
                notices: ["expected \(ConfigLoader.defaultFileURL().path)"]
            )
        }
        do {
            let data = try Data(contentsOf: configURL)
            let config = try ConfigParser.parse(data: data)
            var notices: [String] = []
            if config.focusFollowsMouse.enabled {
                notices.append("focus-follows-mouse is enabled")
            }
            if config.borders.enabled {
                notices.append("borders are enabled")
            }
            if !config.hooks.startup.isEmpty {
                notices.append("startup hooks: \(config.hooks.startup.count)")
            }
            return Report(configPath: path, ok: true, notices: notices)
        } catch let list as ConfigErrorList {
            return Report(
                configPath: path,
                ok: false,
                errors: list.errors.map(\.description)
            )
        } catch {
            return Report(configPath: path, ok: false, errors: ["\(error)"])
        }
    }
}
