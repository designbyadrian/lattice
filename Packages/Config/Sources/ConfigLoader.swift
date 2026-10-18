import Foundation

/// Loads `lattice.toml`, writes first-run defaults, watches for changes, keeps last good config.
public final class ConfigLoader: @unchecked Sendable {
    public static let defaultRelativePath = "lattice/lattice.toml"

    public private(set) var config: LatticeConfig
    public private(set) var lastError: ConfigErrorList?
    public let fileURL: URL

    private let fileManager: FileManager
    private var source: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1
    private let queue = DispatchQueue(label: "com.designbyadrian.lattice.config-loader")
    private var onChange: ((Result<LatticeConfig, ConfigErrorList>) -> Void)?

    public init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        initial: LatticeConfig = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? ConfigLoader.defaultFileURL(fileManager: fileManager)
        self.config = initial
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("lattice", isDirectory: true)
            .appendingPathComponent("lattice.toml", isDirectory: false)
    }

    /// Ensure parent directory exists, write commented defaults if missing, then load.
    @discardableResult
    public func loadOrCreateDefaults() throws -> LatticeConfig {
        let dir = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: fileURL.path) {
            let data = Data(DefaultConfigText.fileContents.utf8)
            try data.write(to: fileURL, options: .atomic)
        }
        return try load()
    }

    /// Parse the file. On failure, keep the previous config and store the error.
    @discardableResult
    public func load() throws -> LatticeConfig {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let list = ConfigErrorList([ConfigError("could not read config: \(error)")])
            lastError = list
            throw list
        }
        do {
            let parsed = try ConfigParser.parse(data: data)
            config = parsed
            lastError = nil
            return parsed
        } catch let list as ConfigErrorList {
            lastError = list
            throw list
        } catch let err as ConfigError {
            let list = ConfigErrorList([err])
            lastError = list
            throw list
        } catch {
            let list = ConfigErrorList([ConfigError("\(error)")])
            lastError = list
            throw list
        }
    }

    /// Attempt a reload from disk. Returns the new config on success; keeps last good on failure.
    @discardableResult
    public func reload() -> Result<LatticeConfig, ConfigErrorList> {
        do {
            let parsed = try load()
            return .success(parsed)
        } catch let list as ConfigErrorList {
            return .failure(list)
        } catch {
            let list = ConfigErrorList([ConfigError("\(error)")])
            lastError = list
            return .failure(list)
        }
    }

    /// Start watching the config file for writes. Callback runs on the loader queue.
    public func startWatching(onChange: @escaping (Result<LatticeConfig, ConfigErrorList>) -> Void) {
        stopWatching()
        self.onChange = onChange

        let dir = fileURL.deletingLastPathComponent()
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleFilesystemEvent()
        }
        source.setCancelHandler { [weak self] in
            if let self, self.directoryFD >= 0 {
                close(self.directoryFD)
                self.directoryFD = -1
            }
        }
        self.source = source
        source.resume()
    }

    public func stopWatching() {
        source?.cancel()
        source = nil
        onChange = nil
    }

    deinit {
        stopWatching()
    }

    private func handleFilesystemEvent() {
        // Debounce briefly so editors finish atomic replace.
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let result = self.reload()
            self.onChange?(result)
        }
    }
}
