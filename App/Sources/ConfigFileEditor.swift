import Foundation
import Config

/// Settings-facing wrapper: read → CST patch → validate → atomic write.
@MainActor
final class ConfigFileEditor {
    let fileURL: URL
    private(set) var text: String
    private(set) var config: LatticeConfig?
    private(set) var loadError: ConfigErrorList?
    var isReadOnly: Bool { loadError != nil }

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        reloadFromDisk()
    }

    func reloadFromDisk() {
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
            config = try ConfigParser.parse(text: text)
            loadError = nil
        } catch let list as ConfigErrorList {
            loadError = list
            // Keep last good config if any; otherwise nil.
        } catch let err as ConfigError {
            loadError = ConfigErrorList([err])
        } catch {
            loadError = ConfigErrorList([ConfigError("\(error)")])
        }
    }

    @discardableResult
    func set(table: String?, key: String, value: TOMLCSTValue) throws -> LatticeConfig {
        guard !isReadOnly else {
            throw TOMLCSTEditor.EditError.validationFailed(
                loadError?.description ?? "config invalid"
            )
        }
        let patched = try TOMLCSTEditor.applyValidated(text: text) { current in
            try TOMLCSTEditor.set(in: current, table: table, key: key, value: value)
        }
        try TOMLCSTEditor.writeAtomically(patched, to: fileURL)
        text = patched
        let parsed = try ConfigParser.parse(text: patched)
        config = parsed
        return parsed
    }

    @discardableResult
    func appendIgnoreRule(appId: String?, appName: String?) throws -> LatticeConfig {
        guard !isReadOnly else {
            throw TOMLCSTEditor.EditError.validationFailed(
                loadError?.description ?? "config invalid"
            )
        }
        let block = ConfigAppender.ruleBlock(appId: appId, appName: appName, run: ["ignore"])
        let patched = try TOMLCSTEditor.applyValidated(text: text) { current in
            TOMLCSTEditor.appendRulesArrayOfTables(in: current, block: block)
        }
        try TOMLCSTEditor.writeAtomically(patched, to: fileURL)
        text = patched
        let parsed = try ConfigParser.parse(text: patched)
        config = parsed
        return parsed
    }
}
