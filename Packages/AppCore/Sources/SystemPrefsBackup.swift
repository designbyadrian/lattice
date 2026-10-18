import Foundation
import LayoutModel

/// Keys Lattice may opt-in to override (native edge tiling / WindowManager).
public enum SystemPrefsKey: String, Codable, Sendable, CaseIterable {
    case enableTilingByEdge = "EnableTilingByEdge"
    case enableTilingByEdgeWindow = "EnableTilingWindowMargin"
    case enableStageManager = "EnableStageManagerActive"

    public var domain: String { "com.apple.WindowManager" }
}

/// Snapshot of originals before Lattice writes overrides.
public struct SystemPrefsSnapshot: Equatable, Codable, Sendable {
    public var schemaVersion: Int
    public var savedAt: Date
    public var values: [String: Bool]
    /// `true` when Lattice quit cleanly after restoring (or never overrode).
    public var cleanShutdown: Bool

    public init(
        schemaVersion: Int = 1,
        savedAt: Date = Date(),
        values: [String: Bool] = [:],
        cleanShutdown: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.values = values
        self.cleanShutdown = cleanShutdown
    }
}

/// Abstraction over `UserDefaults(suiteName:)` for unit tests.
public protocol DefaultsDomain: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    func synchronize() -> Bool
}

public final class DictionaryDefaultsDomain: DefaultsDomain, @unchecked Sendable {
    private var storage: [String: Any] = [:]
    private let lock = NSLock()

    public init(storage: [String: Any] = [:]) {
        self.storage = storage
    }

    public func object(forKey key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    public func removeObject(forKey key: String) {
        set(nil, forKey: key)
    }

    @discardableResult
    public func synchronize() -> Bool { true }

    public var dictionaryRepresentation: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

/// Opt-in macOS tiling-pref override with backup / restore (PLAN §7).
public final class SystemPrefsBackup: @unchecked Sendable {
    public static let backupFileName = "system-prefs-backup.json"

    private let fileManager: FileManager
    private let domainFactory: (String) -> any DefaultsDomain
    private let queue = DispatchQueue(label: "com.designbyadrian.lattice.prefs-backup")

    public init(
        fileManager: FileManager = .default,
        domainFactory: @escaping (String) -> any DefaultsDomain = { name in
            // Production path uses real UserDefaults suite when available.
            if let suite = UserDefaults(suiteName: name) {
                return UserDefaultsDomainAdapter(suite)
            }
            return DictionaryDefaultsDomain()
        }
    ) {
        self.fileManager = fileManager
        self.domainFactory = domainFactory
    }

    public func backupFileURL() throws -> URL {
        let dir = try LayoutPersistence.applicationSupportDirectory(fileManager: fileManager)
        return dir.appendingPathComponent(Self.backupFileName, isDirectory: false)
    }

    public func loadSnapshot() -> SystemPrefsSnapshot? {
        do {
            let url = try backupFileURL()
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SystemPrefsSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    public func saveSnapshot(_ snapshot: SystemPrefsSnapshot) throws {
        let url = try backupFileURL()
        let data = try JSONEncoder().encode(snapshot)
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(Self.backupFileName).\(UUID().uuidString).tmp")
        try data.write(to: temp, options: [.atomic])
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: url)
        }
    }

    /// Record originals (once) and apply Lattice overrides. Opt-in only.
    @discardableResult
    public func applyOverrides(disableEdgeTiling: Bool = true) throws -> SystemPrefsSnapshot {
        var snapshot = loadSnapshot() ?? SystemPrefsSnapshot(cleanShutdown: false)
        let keys = SystemPrefsKey.allCases
        for key in keys {
            let domain = domainFactory(key.domain)
            if snapshot.values[key.rawValue] == nil {
                if let existing = domain.object(forKey: key.rawValue) as? Bool {
                    snapshot.values[key.rawValue] = existing
                } else if let n = domain.object(forKey: key.rawValue) as? NSNumber {
                    snapshot.values[key.rawValue] = n.boolValue
                } else {
                    snapshot.values[key.rawValue] = true // assume macOS default on
                }
            }
            if disableEdgeTiling {
                switch key {
                case .enableTilingByEdge, .enableTilingByEdgeWindow:
                    domain.set(false, forKey: key.rawValue)
                case .enableStageManager:
                    break
                }
            }
            _ = domain.synchronize()
        }
        snapshot.cleanShutdown = false
        snapshot.savedAt = Date()
        try saveSnapshot(snapshot)
        return snapshot
    }

    /// Restore originals from the backup file.
    @discardableResult
    public func restore() throws -> SystemPrefsSnapshot? {
        guard var snapshot = loadSnapshot() else { return nil }
        for key in SystemPrefsKey.allCases {
            guard let value = snapshot.values[key.rawValue] else { continue }
            let domain = domainFactory(key.domain)
            domain.set(value, forKey: key.rawValue)
            _ = domain.synchronize()
        }
        snapshot.cleanShutdown = true
        try saveSnapshot(snapshot)
        return snapshot
    }

    /// Delete backup after a confirmed clean restore (optional uninstall path).
    public func clearBackup() throws {
        let url = try backupFileURL()
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Crash recovery: backup exists and previous run did not shut down cleanly.
    public func needsCrashRecoveryOffer() -> Bool {
        guard let snapshot = loadSnapshot() else { return false }
        return !snapshot.cleanShutdown && !snapshot.values.isEmpty
    }

    public func markCleanShutdown() throws {
        guard var snapshot = loadSnapshot() else { return }
        snapshot.cleanShutdown = true
        try saveSnapshot(snapshot)
    }
}

/// Adapter so real `UserDefaults` satisfies `DefaultsDomain`.
public final class UserDefaultsDomainAdapter: DefaultsDomain {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    public func set(_ value: Any?, forKey key: String) { defaults.set(value, forKey: key) }
    public func removeObject(forKey key: String) { defaults.removeObject(forKey: key) }
    @discardableResult
    public func synchronize() -> Bool { defaults.synchronize() }
}
