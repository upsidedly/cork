import Foundation
import CorkCore

@main
enum CorkMCP {
    static func main() {
        if CommandLine.arguments.contains("--help") {
            FileHandle.standardError.write(Data("Cork MCP 0.9.0 — newline-delimited JSON-RPC over stdio. CORK_DATA_DIR and CORK_SOCKET override the local board/socket.\n".utf8))
            return
        }
        var dispatcher = MCPDispatcher()
        var pending = Data()
        while true {
            let chunk = FileHandle.standardInput.availableData
            if chunk.isEmpty { break }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                let line = pending[..<newline]
                pending.removeSubrange(...newline)
                if line.isEmpty { continue }
                let reply: JSONValue?
                do {
                    guard line.count <= LocalConnection.maximumRequestBytes else { throw CorkError("Request too large.") }
                    let message = try JSONDecoder().decode(JSONValue.self, from: Data(line))
                    reply = dispatcher.respond(message) { name, arguments in
                        try callApp(name: name, arguments: arguments)
                    }
                } catch {
                    reply = .object(["jsonrpc": .string("2.0"), "id": .null,
                                     "error": .object(["code": .number(-32700), "message": .string("Invalid JSON or oversized message.")])])
                }
                if let reply, let data = try? reply.data() { FileHandle.standardOutput.write(data + Data([10])) }
            }
            if pending.count > LocalConnection.maximumRequestBytes {
                FileHandle.standardError.write(Data("Cork MCP: unterminated message exceeded 1 MB; closing input.\n".utf8))
                return
            }
        }
    }

    static func callApp(name: String, arguments: [String: JSONValue]) throws -> JSONValue {
        let request = JSONValue.object(["method": .string(name), "arguments": .object(arguments)])
        do { return try LocalConnection.call(request) }
        catch let error as CorkNotRunning {
            // Only a bundled bridge can locate its app without guessing another installation.
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            let bundled = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            guard bundled.pathExtension == "app", ProcessInfo.processInfo.environment["CORK_DATA_DIR"] == nil,
                  ProcessInfo.processInfo.environment["CORK_SOCKET"] == nil else { throw error }
            let installed = URL(fileURLWithPath: "/Applications/Cork.app")
            let app = Bundle(url: installed)?.bundleIdentifier == "dev.upsided.cork" ? installed : bundled
            let launch = Process(); launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            launch.arguments = ["-g", app.path, "--args", "--background"]
            launch.standardOutput = FileHandle.standardError; launch.standardError = FileHandle.standardError
            try launch.run(); launch.waitUntilExit()
            guard launch.terminationStatus == 0 else { throw CorkError("Could not open Cork.app.") }
            // Bounded startup recovery; no launch or polling happens during initialize/tools/list.
            for _ in 0..<30 {
                Thread.sleep(forTimeInterval: 0.1)
                do { return try LocalConnection.call(request) }
                catch is CorkNotRunning { continue }
            }
            throw CorkError("Cork did not become available within 3 seconds. Open Cork.app to inspect the error.")
        }
    }
}
