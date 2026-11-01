import AppKit
import Foundation
import CorkCore
import CorkImportCore

private actor BookmarkedPinterestSource: DailyPinterestSource {
    let settings: DailySyncSettings
    private var directory: URL?
    private var scoped = false
    private var client: PinterestClient?
    init(settings: DailySyncSettings) { self.settings = settings }
    func connect() async throws -> PinterestAccount {
        guard let bookmark = settings.bookmark, var profile = settings.profile else { throw CorkError("Reconnect a browser profile in Cork Importer.") }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, url.isFileURL else { throw CorkError("The saved profile permission changed. Reconnect in Cork Importer.") }
        directory = url; scoped = url.startAccessingSecurityScopedResource(); profile.directory = url
        let reader = BrowserCookieReader(key: { try BrowserCookieReader.safeStorageKey($0, allowInteraction: false) })
        let cookies = try await reader.read(profile, approved: settings.consentVersion == 1)
        let client = PinterestClient(cookies: cookies); self.client = client
        return try await client.connect()
    }
    func recent(_ board: PinterestBoard) async throws -> [PinterestImage] {
        guard let client else { throw CorkError("Reconnect Pinterest before checking for new pins.") }
        return try await client.recent(board)
    }
    func disconnect() async {
        await client?.disconnect(); client = nil
        if scoped { directory?.stopAccessingSecurityScopedResource() }; directory = nil; scoped = false
    }
}

enum DailySyncAgent {
    static let label = "dev.upsided.cork-importer.daily"
    static var location: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static func definition(executable: URL, settings: DailySyncSettings) throws -> Data {
        guard executable.path.hasPrefix("/Applications/"), executable.lastPathComponent == "cork-importer" else {
            throw CorkError("Install Cork or Cork Importer in Applications before enabling daily sync.")
        }
        let value: [String: Any] = ["Label": label, "ProgramArguments": [executable.path, "--daily-sync"],
            "StartCalendarInterval": ["Hour": settings.hour, "Minute": settings.minute], "RunAtLoad": true,
            "ProcessType": "Background", "LowPriorityIO": true, "ThrottleInterval": 60, "ExitTimeOut": 10,
            "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null", "Umask": 0o077]
        return try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }
    private static func launchctl(_ arguments: [String]) async throws -> Int32 {
        try await Task.detached(priority: .utility) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = arguments; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            if process.isRunning { process.terminate(); throw CorkError("macOS did not finish updating the daily job. Try again from Daily Sync.") }
            return process.terminationStatus
        }.value
    }
    static func set(_ settings: DailySyncSettings, executable: URL) async throws {
        let domain = "gui/\(getuid())", target = "\(domain)/\(label)"
        if !settings.enabled {
            let status = try await launchctl(["bootout", target])
            // 3/113 mean there was no registered job; removing our own plist is still correct.
            guard [0, 3, 113].contains(status) else { throw CorkError("macOS could not stop daily sync (\(status)).") }
            if FileManager.default.fileExists(atPath: location.path) { try FileManager.default.removeItem(at: location) }
            return
        }
        let data = try definition(executable: executable, settings: settings)
        let previous = try? Data(contentsOf: location)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try await launchctl(["bootout", target])
        try data.write(to: location, options: [.atomic]); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
        let status = try await launchctl(["bootstrap", domain, location.path])
        guard status == 0 else {
            if let previous {
                try previous.write(to: location, options: [.atomic]); _ = try await launchctl(["bootstrap", domain, location.path])
            } else { try FileManager.default.removeItem(at: location) }
            throw CorkError("macOS could not register daily sync (\(status)). Your previous settings were retained.")
        }
    }
}

@MainActor enum DailySyncCommand {
    static func ensureCork() async throws {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = parent.pathExtension == "app" && parent.lastPathComponent == "Cork.app" ? parent : URL(fileURLWithPath: "/Applications/Cork.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw CorkError("Install Cork in Applications to receive imported images.") }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false; configuration.arguments = ["--background"]
        configuration.environment = ProcessInfo.processInfo.environment.filter { ["CORK_DATA_DIR", "CORK_SOCKET"].contains($0.key) }
        _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        for attempt in 0..<20 {
            do { _ = try await NativeCorkDestination().call("cork_get_collection", arguments: ["limit": .number(1)]); return }
            catch { if attempt == 19 { throw error }; try await Task.sleep(for: .milliseconds(250)) }
        }
    }
    static func run(_ arguments: [String]) async -> Int32 {
        let store = DailySyncStore()
        do {
            if arguments.contains("--daily-status") {
                let settings = try await store.settings(), state = try await store.state()
                let value = JSONValue.object(["enabled": .bool(settings.enabled), "boards": .number(Double(settings.boards.count)),
                    "pending": .number(Double(state.pending.count)), "added_today": .number(Double(state.addedToday)),
                    "status": .string(state.lastMessage)])
                print(String(decoding: try value.data(), as: UTF8.self)); return 0
            }
            if arguments.contains("--exclude-pin") {
                var ids: Set<String> = []
                for index in arguments.indices where arguments[index] == "--exclude-pin" {
                    guard index + 1 < arguments.count else { throw CorkError("Pass a pin ID after --exclude-pin.") }
                    ids.insert(arguments[index + 1])
                }
                try await store.exclude(ids); print("Excluded \(ids.count) pins from daily sync."); return 0
            }
            let settings = try await store.settings(), state = try await store.state()
            guard settings.enabled, arguments.contains("--daily-now") || PinterestDailySync.due(state, now: Date()) else { return 0 }
            try await ensureCork()
            let result = try await PinterestDailySync(store: store).run(source: BookmarkedPinterestSource(settings: settings), force: arguments.contains("--daily-now"))
            print(result.lastMessage); return 0
        } catch {
            print("Daily sync paused. Open Cork Importer for connection or storage details."); return 1
        }
    }
    static func checkNow() async throws {
        guard let executable = Bundle.main.executableURL else { throw CorkError("Cork Importer's executable is missing.") }
        let task = Task.detached(priority: .utility) {
            let process = Process(); process.executableURL = executable; process.arguments = ["--daily-now"]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            defer { if process.isRunning { process.terminate() } }
            let deadline = Date().addingTimeInterval(310)
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
            if process.isRunning { process.terminate(); throw CorkError("The Pinterest check did not finish. Saved imports are safe.") }
            return process.terminationStatus
        }
        let code = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard code == 0 else { throw CorkError("Daily sync paused. See its status below before reconnecting or retrying.") }
    }
}
