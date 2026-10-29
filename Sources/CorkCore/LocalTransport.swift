import Foundation
import Darwin

public struct CorkNotRunning: Error, LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { "Cork is not running or its local control is unavailable. Open Cork.app and try again." }
}

/// A private, newline-delimited Unix socket. Blocking work stays off the UI actor.
public enum LocalConnection {
    public static let maximumRequestBytes = 1_048_576
    public static let maximumReplyBytes = 32_000_000

    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw CorkError("Cork's socket path is too long. Set CORK_SOCKET to a shorter absolute path.") }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
        return address
    }

    static func configure(_ descriptor: Int32, seconds: Int = 30) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        var yes: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
    }

    static func isListening(path: String) -> Bool {
        guard var address = try? address(path) else { return false }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
        }
    }

    public static func call(_ request: JSONValue, path: String = CorkPaths.socketPath) throws -> JSONValue {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CorkError("Could not create a Cork connection.") }
        defer { Darwin.close(descriptor) }
        configure(descriptor)
        var address = try address(path)
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard status == 0 else { throw CorkNotRunning() }
        try writeLine(try request.data(), to: descriptor)
        let data = try readLine(from: descriptor, limit: maximumReplyBytes)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func readLine(from descriptor: Int32, limit: Int) throws -> Data {
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw CorkError("Cork's local connection closed or timed out (\(count == 0 ? "end of stream" : String(cString: strerror(errno)))).") }
            if let newline = buffer.prefix(count).firstIndex(of: 10) {
                data.append(contentsOf: buffer[..<newline])
                guard data.count <= limit else { throw CorkError("Local message is too large.") }
                return data
            }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= limit else { throw CorkError("Local message is too large.") }
        }
    }

    static func writeLine(_ data: Data, to descriptor: Int32) throws {
        let message = data + Data([10])
        try message.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: sent), bytes.count - sent)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw CorkError("Could not send Cork's local message: \(String(cString: strerror(errno))).") }
                sent += count
            }
        }
    }

    // Construct Dispatch callbacks outside MainActor. A callback created in the
    // UI owner's method can inherit its isolation even though Dispatch runs it
    // on a worker queue, which Swift 6 correctly traps at runtime.
    static func installHandlers(on source: any DispatchSourceRead, descriptor: Int32,
                                handler: @escaping @MainActor @Sendable (JSONValue) async -> JSONValue) {
        let capacity = DispatchSemaphore(value: 8)
        source.setEventHandler {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            guard capacity.wait(timeout: .now()) == .success else { Darwin.close(client); return }
            // Darwin inherits O_NONBLOCK from the listener. Accepted requests
            // need bounded blocking I/O while the client finishes sending.
            let flags = fcntl(client, F_GETFL)
            _ = fcntl(client, F_SETFL, flags & ~O_NONBLOCK)
            configure(client, seconds: 10)
            Task.detached(priority: .userInitiated) {
                defer { Darwin.close(client); capacity.signal() }
                do {
                    let data = try readLine(from: client, limit: maximumRequestBytes)
                    let request = try JSONDecoder().decode(JSONValue.self, from: data)
                    let reply = await handler(request)
                    try writeLine(try reply.data(), to: client)
                } catch {
                    if let data = try? JSONValue.toolError(error.localizedDescription).data() {
                        try? writeLine(data, to: client)
                    }
                }
            }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
    }
}

@MainActor
public final class LocalServer {
    private var source: (any DispatchSourceRead)?
    private let path: String
    public init(path: String = CorkPaths.socketPath) { self.path = path }

    public func start(handler: @escaping @MainActor @Sendable (JSONValue) async -> JSONValue) throws {
        guard source == nil else { return }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: path) {
            // Never unlink a socket owned by another active instance.
            if LocalConnection.isListening(path: path) {
                throw CorkError("Another Cork instance is already using this board.")
            }
            guard unlink(path) == 0 else { throw CorkError("Could not remove an old Cork socket.") }
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CorkError("Could not create Cork's local socket.") }
        do {
            var address = try LocalConnection.address(path)
            let status = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard status == 0 else { throw CorkError("Could not bind Cork's local socket.") }
            guard chmod(path, 0o600) == 0, listen(descriptor, 8) == 0 else { throw CorkError("Could not protect or listen on Cork's local socket.") }
            _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .global(qos: .userInitiated))
            LocalConnection.installHandlers(on: source, descriptor: descriptor, handler: handler)
            self.source = source
            source.resume()
        } catch { Darwin.close(descriptor); unlink(path); throw error }
    }

    public func stop() { source?.cancel(); source = nil; unlink(path) }
}
