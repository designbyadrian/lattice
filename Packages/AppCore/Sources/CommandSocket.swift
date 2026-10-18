import Foundation
import Config
import LayoutModel

/// Line-oriented JSON protocol over a Unix domain socket (not fixed `/tmp`).
public enum CommandSocketProtocol {
    public struct Request: Codable, Sendable, Equatable {
        public var command: String
        public var args: [String]

        public init(command: String, args: [String] = []) {
            self.command = command
            self.args = args
        }
    }

    public struct Response: Codable, Sendable, Equatable {
        public var ok: Bool
        public var output: String
        public var error: String?

        public init(ok: Bool, output: String = "", error: String? = nil) {
            self.ok = ok
            self.output = output
            self.error = error
        }
    }

    /// Preferred socket URL: Caches/`com.designbyadrian.lattice`/lattice.sock (falls back to TMPDIR).
    public static func socketURL(fileManager: FileManager = .default) -> URL {
        if let caches = try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            let dir = caches.appendingPathComponent("com.designbyadrian.lattice", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("lattice.sock", isDirectory: false)
        }
        let tmp = fileManager.temporaryDirectory
            .appendingPathComponent("com.designbyadrian.lattice", isDirectory: true)
        try? fileManager.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp.appendingPathComponent("lattice.sock", isDirectory: false)
    }

    public static func encodeRequest(_ request: Request) throws -> Data {
        var data = try JSONEncoder().encode(request)
        data.append(contentsOf: [0x0A]) // newline-delimited
        return data
    }

    public static func decodeRequest(_ data: Data) throws -> Request {
        let trimmed = data.prefix { $0 != 0x0A }
        return try JSONDecoder().decode(Request.self, from: Data(trimmed))
    }

    public static func encodeResponse(_ response: Response) throws -> Data {
        var data = try JSONEncoder().encode(response)
        data.append(contentsOf: [0x0A])
        return data
    }

    public static func decodeResponse(_ data: Data) throws -> Response {
        let trimmed = data.prefix { $0 != 0x0A }
        return try JSONDecoder().decode(Response.self, from: Data(trimmed))
    }
}

/// Handles CLI requests against an `AppCoordinator` (or pure doctor without one).
public enum CommandSocketHandler {
    public static func handle(
        request: CommandSocketProtocol.Request,
        coordinator: AppCoordinator?,
        configURL: URL = ConfigLoader.defaultFileURL()
    ) async -> CommandSocketProtocol.Response {
        let verb = request.command.lowercased()
        switch verb {
        case "doctor":
            let path = request.args.first.map { URL(fileURLWithPath: $0) } ?? configURL
            let report = Doctor.check(configURL: path)
            return .init(ok: report.ok, output: report.text, error: report.ok ? nil : report.errors.joined(separator: "; "))
        case "list-windows", "list-workspaces", "list-displays", "list-modes":
            guard let coordinator else {
                return .init(ok: false, error: "Lattice app is not running")
            }
            let output = await coordinator.listCommand(verb)
            return .init(ok: true, output: output)
        case "run":
            guard let coordinator else {
                return .init(ok: false, error: "Lattice app is not running")
            }
            let joined = request.args.joined(separator: " ")
            guard !joined.isEmpty else {
                return .init(ok: false, error: "run requires a command string")
            }
            do {
                let command = try CommandParser.parse(joined)
                await coordinator.execute(command)
                return .init(ok: true, output: "ok")
            } catch {
                return .init(ok: false, error: "\(error)")
            }
        default:
            // Treat unknown verb as a Lattice command string.
            guard let coordinator else {
                return .init(ok: false, error: "Lattice app is not running")
            }
            let joined = ([request.command] + request.args).joined(separator: " ")
            do {
                let command = try CommandParser.parse(joined)
                await coordinator.execute(command)
                return .init(ok: true, output: "ok")
            } catch {
                return .init(ok: false, error: "unknown command '\(request.command)': \(error)")
            }
        }
    }
}

private final class ResponseBox: @unchecked Sendable {
    var value: CommandSocketProtocol.Response?
}

/// Lightweight Unix-domain socket server (accept loop on a background queue).
public final class CommandSocketServer: @unchecked Sendable {
    public private(set) var socketURL: URL
    private var fd: Int32 = -1
    private let queue = DispatchQueue(label: "com.designbyadrian.lattice.command-socket")
    private var source: DispatchSourceRead?
    public var handler: ((CommandSocketProtocol.Request) async -> CommandSocketProtocol.Response)?

    public init(socketURL: URL = CommandSocketProtocol.socketURL()) {
        self.socketURL = socketURL
    }

    public func start() throws {
        stop()
        let path = socketURL.path
        try? FileManager.default.removeItem(at: socketURL)
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EPERM) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        let pathBytes = Array(path.utf8.prefix(maxLen)) + [0]
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: pathBytes.count) { dest in
                for (i, b) in pathBytes.enumerated() { dest[i] = b }
            }
        }

        let addrLen = socklen_t(
            MemoryLayout<sockaddr_un>.stride
        )
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            close(fd); fd = -1
            throw POSIXError(.EADDRINUSE)
        }
        guard listen(fd, 8) == 0 else {
            close(fd); fd = -1
            throw POSIXError(.ECONNREFUSED)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptOne()
        }
        source.setCancelHandler { [weak self] in
            if let self, self.fd >= 0 {
                close(self.fd)
                self.fd = -1
            }
            try? FileManager.default.removeItem(at: self?.socketURL ?? URL(fileURLWithPath: "/"))
        }
        self.source = source
        source.resume()
    }

    public func stop() {
        source?.cancel()
        source = nil
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        try? FileManager.default.removeItem(at: socketURL)
    }

    deinit { stop() }

    private func acceptOne() {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        queue.async {
            defer { close(client) }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let n = read(client, &buffer, buffer.count)
            guard n > 0 else { return }
            let data = Data(buffer.prefix(n))
            guard let request = try? CommandSocketProtocol.decodeRequest(data) else {
                let err = CommandSocketProtocol.Response(ok: false, error: "invalid request")
                if let out = try? CommandSocketProtocol.encodeResponse(err) {
                    _ = out.withUnsafeBytes { write(client, $0.baseAddress, out.count) }
                }
                return
            }
            let handler = self.handler
            let box = ResponseBox()
            let sem = DispatchSemaphore(value: 0)
            Task {
                let result: CommandSocketProtocol.Response
                if let handler {
                    result = await handler(request)
                } else {
                    result = CommandSocketProtocol.Response(ok: false, error: "no handler")
                }
                box.value = result
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 10)
            let response = box.value
                ?? CommandSocketProtocol.Response(ok: false, error: "timeout")
            if let out = try? CommandSocketProtocol.encodeResponse(response) {
                _ = out.withUnsafeBytes { write(client, $0.baseAddress, out.count) }
            }
        }
    }
}

/// Client used by `lattice-cli`.
public enum CommandSocketClient {
    public static func send(
        _ request: CommandSocketProtocol.Request,
        socketURL: URL = CommandSocketProtocol.socketURL()
    ) throws -> CommandSocketProtocol.Response {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EPERM) }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        let pathBytes = Array(path.utf8.prefix(maxLen)) + [0]
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: pathBytes.count) { dest in
                for (i, b) in pathBytes.enumerated() { dest[i] = b }
            }
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.stride)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, addrLen)
            }
        }
        guard connected == 0 else {
            throw POSIXError(.ECONNREFUSED)
        }
        let payload = try CommandSocketProtocol.encodeRequest(request)
        _ = payload.withUnsafeBytes { write(fd, $0.baseAddress, payload.count) }

        var buffer = [UInt8](repeating: 0, count: 65_536)
        let n = read(fd, &buffer, buffer.count)
        guard n > 0 else { throw POSIXError(.EIO) }
        return try CommandSocketProtocol.decodeResponse(Data(buffer.prefix(n)))
    }
}
