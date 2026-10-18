import Foundation

/// Value written by the format-preserving editor.
public enum TOMLCSTValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case float(Double)
    case string(String)
    case stringArray([String])
    case intPair(Int, Int)

    public var rendered: String {
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .int(let n): return String(n)
        case .float(let f):
            if f.rounded() == f { return String(format: "%.1f", f) }
            return String(f)
        case .string(let s): return "'\(Self.escape(s))'"
        case .stringArray(let arr):
            let inner = arr.map { "'\(Self.escape($0))'" }.joined(separator: ", ")
            return "[\(inner)]"
        case .intPair(let a, let b): return "[\(a), \(b)]"
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }
}

/// Format-preserving TOML editor (CST subset): edit in place, keep comments / blanks / order.
public enum TOMLCSTEditor {
    public enum EditError: Error, Equatable, CustomStringConvertible {
        case validationFailed(String)
        case emptyDocument

        public var description: String {
            switch self {
            case .validationFailed(let m): return m
            case .emptyDocument: return "empty document"
            }
        }
    }

    /// Set a key inside an optional table path (nil = root). Creates the table/key if missing.
    /// - Parameters:
    ///   - text: full file contents
    ///   - table: dotted table header without brackets (`gaps`, `borders`, `mode.main`, `focus-follows-mouse`)
    ///   - key: key name inside that table (or root)
    ///   - value: new value
    public static func set(
        in text: String,
        table: String?,
        key: String,
        value: TOMLCSTValue
    ) throws -> String {
        let newline = detectNewline(text)
        var lines = splitLines(text)
        let rendered = "\(key) = \(value.rendered)"

        if let table {
            guard let range = findTableRange(lines: lines, header: table) else {
                // Append new table + key at end.
                if let last = lines.last, !last.isEmpty { lines.append("") }
                lines.append("[\(table)]")
                lines.append(rendered)
                return join(lines, newline: newline, trailingNewline: text.hasSuffix("\n") || text.hasSuffix("\r\n"))
            }
            if let keyIndex = findKeyIndex(lines: lines, range: range, key: key) {
                lines[keyIndex] = replaceKeyLine(lines[keyIndex], with: rendered)
            } else {
                // Insert before end of table (before next header or EOF).
                let insertAt = range.upperBound
                lines.insert(rendered, at: insertAt)
            }
        } else {
            let rootEnd = rootTableEnd(lines: lines)
            if let keyIndex = findKeyIndex(lines: lines, range: 0..<rootEnd, key: key) {
                lines[keyIndex] = replaceKeyLine(lines[keyIndex], with: rendered)
            } else {
                lines.insert(rendered, at: rootEnd)
            }
        }
        return join(lines, newline: newline, trailingNewline: text.hasSuffix("\n") || text.hasSuffix("\r\n"))
    }

    /// Append a `[[rules]]` block (never rewrites earlier content).
    public static func appendRulesArrayOfTables(
        in text: String,
        block: String
    ) -> String {
        var body = text
        let nl = detectNewline(text)
        if !body.isEmpty, !body.hasSuffix("\n"), !body.hasSuffix("\r\n") {
            body += nl
        }
        var fragment = block
        if !fragment.hasSuffix("\n") { fragment += nl }
        return body + fragment
    }

    /// Read → patch → validate with `ConfigParser` → return new text (or throw, write nothing).
    public static func applyValidated(
        text: String,
        patch: (String) throws -> String
    ) throws -> String {
        let patched = try patch(text)
        do {
            _ = try ConfigParser.parse(text: patched)
        } catch let list as ConfigErrorList {
            throw EditError.validationFailed(list.errors.first?.description ?? "invalid config")
        } catch let err as ConfigError {
            throw EditError.validationFailed(err.description)
        } catch {
            throw EditError.validationFailed("\(error)")
        }
        return patched
    }

    /// Atomic write helper used by Settings.
    public static func writeAtomically(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Line helpers

    private static func detectNewline(_ text: String) -> String {
        if text.contains("\r\n") { return "\r\n" }
        return "\n"
    }

    private static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines: [String] = []
        text.enumerateLines { line, _ in lines.append(line) }
        // enumerateLines drops a trailing empty line after final newline; restore if needed.
        if text.hasSuffix("\n") || text.hasSuffix("\r\n") {
            // Last content line already included; trailing blank represented by empty last only
            // when file ends with blank line after content — enumerateLines includes empty lines mid-file.
        }
        return lines
    }

    private static func join(_ lines: [String], newline: String, trailingNewline: Bool) -> String {
        var out = lines.joined(separator: newline)
        if trailingNewline, !out.hasSuffix(newline) {
            out += newline
        }
        return out
    }

    /// Index after the last root-level key (before first `[table]`).
    private static func rootTableEnd(lines: [String]) -> Int {
        for (i, line) in lines.enumerated() {
            if isTableHeader(line) { return i }
        }
        return lines.count
    }

    private static func findTableRange(lines: [String], header: String) -> Range<Int>? {
        let wanted = "[\(header)]"
        guard let start = lines.firstIndex(where: { normalizeHeader($0) == wanted }) else {
            return nil
        }
        var end = start + 1
        while end < lines.count {
            if isTableHeader(lines[end]) { break }
            end += 1
        }
        return start..<end
    }

    private static func findKeyIndex(lines: [String], range: Range<Int>, key: String) -> Int? {
        for i in range {
            if keyName(of: lines[i]) == key { return i }
        }
        return nil
    }

    private static func keyName(of line: String) -> String? {
        let trimmed = stripInlineComment(line).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !isTableHeader(trimmed) else { return nil }
        guard let eq = trimmed.firstIndex(of: "=") else { return nil }
        let name = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func replaceKeyLine(_ original: String, with rendered: String) -> String {
        // Preserve indentation and trailing inline comment when present after value.
        let indent = original.prefix(while: { $0 == " " || $0 == "\t" })
        if let hash = original.firstIndex(of: "#"),
           let eq = original.firstIndex(of: "="),
           hash > eq {
            // Keep comment only if it was an inline comment after the value.
            let afterEq = original[original.index(after: eq)...]
            if let commentStart = afterEq.firstIndex(of: "#") {
                let comment = original[commentStart...]
                return "\(indent)\(rendered) \(comment)"
            }
        }
        return "\(indent)\(rendered)"
    }

    private static func stripInlineComment(_ line: String) -> String {
        // Naive: ignore # inside quotes by scanning.
        var inSingle = false
        var inDouble = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "'" && !inDouble { inSingle.toggle() }
            else if c == "\"" && !inSingle { inDouble.toggle() }
            else if c == "#" && !inSingle && !inDouble {
                return String(line[..<i])
            }
            i = line.index(after: i)
        }
        return line
    }

    private static func isTableHeader(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("[") && t.hasSuffix("]") && !t.hasPrefix("[[")
    }

    private static func normalizeHeader(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }
}

/// Detect binding conflicts within a mode and against a small system-shortcut denylist.
public enum ShortcutConflictDetector {
    public struct Conflict: Sendable, Equatable {
        public var chord: String
        public var reason: String
    }

    /// Known system shortcuts we warn about (not exhaustive).
    public static let systemDenylist: Set<String> = [
        "cmd-c", "cmd-v", "cmd-x", "cmd-z", "cmd-a", "cmd-q", "cmd-w",
        "cmd-tab", "cmd-space", "ctrl-space", "cmd-shift-3", "cmd-shift-4",
    ]

    public static func conflicts(in mode: ModeConfig, candidate: KeyChord? = nil) -> [Conflict] {
        var seen: [String: Int] = [:]
        var result: [Conflict] = []
        for (index, binding) in mode.bindings.enumerated() {
            let desc = binding.chord.description
            if let prev = seen[desc] {
                result.append(Conflict(chord: desc, reason: "duplicates binding at index \(prev)"))
            } else {
                seen[desc] = index
            }
            if Self.systemDenylist.contains(desc) {
                result.append(Conflict(chord: desc, reason: "conflicts with a known system shortcut"))
            }
        }
        if let candidate {
            let desc = candidate.description
            if seen[desc] != nil {
                result.append(Conflict(chord: desc, reason: "already bound in this mode"))
            }
            if Self.systemDenylist.contains(desc) {
                result.append(Conflict(chord: desc, reason: "conflicts with a known system shortcut"))
            }
        }
        return result
    }
}
