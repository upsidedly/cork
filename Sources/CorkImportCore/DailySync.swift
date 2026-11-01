import Foundation
import Darwin
import CorkCore

/// Only source choices and a user-approved folder bookmark; never cookies or keys.
public struct DailySyncSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var consentVersion = 0
    public var profile: BrowserProfile?
    public var bookmark: Data?
    public var username = ""
    public var boards: [PinterestBoard] = []
    public var maximumPerDay = 10
    public var hour = 9
    public var minute = 0
    public init() {}
    public func validate() throws {
        guard (1...50).contains(maximumPerDay), (0...23).contains(hour), (0...59).contains(minute),
              boards.count <= 50, Set(boards.map(\.id)).count == boards.count,
              username.count <= 200, (bookmark?.count ?? 0) <= 1_000_000,
              boards.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 && $0.name.count <= 200 &&
                  $0.path.hasPrefix("/") && !$0.path.hasPrefix("//") && $0.path.count <= 2048 }) else {
            throw CorkError("Daily sync settings are invalid. Choose at most 50 boards and 1–50 images per day.")
        }
        if enabled {
            guard consentVersion == 1, profile != nil, bookmark != nil, !username.isEmpty, !boards.isEmpty else {
                throw CorkError("Connect a profile and approve daily Pinterest-cookie access before enabling sync.")
            }
        }
        if let profile {
            let services = ["Chrome": ("Chrome Safe Storage", "Chrome"), "Chromium": ("Chromium Safe Storage", "Chromium"),
                "Brave": ("Brave Safe Storage", "Brave"), "Edge": ("Microsoft Edge Safe Storage", "Microsoft Edge")]
            let allowed = profile.browser == "Firefox" ? profile.firefox && profile.service == nil && profile.account == nil :
                !profile.firefox && services[profile.browser].map { profile.service == $0.0 && profile.account == $0.1 } == true
            guard allowed, profile.directory.isFileURL, profile.directory.path.hasPrefix("/") else { throw CorkError("Choose a supported browser profile again.") }
        }
    }
}

public struct DailySyncState: Codable, Sendable {
    public var baselineBoards: Set<String> = []
    public var seen: Set<String> = []
    public var pending: [PinterestImage] = []
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var lastMessage = "Daily sync is off."
    public var day = ""
    public var addedToday = 0
    public var attemptedToday = 0
    public var bytesToday = 0
    public var boardOffset = 0
    public init() {}
}

/// Separate from manual review/staging, so a background check cannot discard it.
public actor DailySyncStore {
    public nonisolated let root: URL
    public init(root: URL = ImportSessionStore.defaultDirectory.appendingPathComponent("Daily")) { self.root = root }
    private func read<T: Decodable>(_ name: String, fallback: T) throws -> T {
        let url = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 8_000_000 else { throw CorkError("Daily sync metadata is too large.") }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let bytes = try JSONEncoder().encode(value)
        guard bytes.count <= 8_000_000 else { throw CorkError("Daily sync metadata reached its limit. Existing images are safe.") }
        let url = root.appendingPathComponent(name)
        try bytes.write(to: url, options: [.atomic]); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func settings() throws -> DailySyncSettings {
        let value = try read("settings.json", fallback: DailySyncSettings()); try value.validate(); return value
    }
    public func save(_ value: DailySyncSettings) throws { try value.validate(); try write(value, name: "settings.json") }
    public func state() throws -> DailySyncState {
        let value = try read("state.json", fallback: DailySyncState())
        guard value.seen.count <= 100_000, value.pending.count <= 2_000, value.baselineBoards.count <= 500,
              value.pending.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 100 && $0.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) &&
                  $0.sourceURL == "https://www.pinterest.com/pin/\($0.id)/" &&
                  ImportRedirectPolicy.allowed($0.imageURL, images: true) && ImportRedirectPolicy.allowed($0.previewURL, images: true) }),
              value.lastMessage.count <= 2_000, value.addedToday >= 0, value.attemptedToday >= 0, value.bytesToday >= 0 else { throw CorkError("Daily sync progress is invalid.") }
        return value
    }
    public func save(_ value: DailySyncState) throws {
        guard value.seen.count <= 100_000, value.pending.count <= 2_000 else { throw CorkError("Daily sync history reached its bounded capacity.") }
        try write(value, name: "state.json")
    }
    public static func pinID(_ value: String) -> String { value.hasPrefix("pinterest-") ? String(value.dropFirst(10)) : value }
    public func exclusions() throws -> Set<String> { try read("excluded.json", fallback: Set<String>()) }
    public func exclude(_ ids: Set<String>, restore: Set<String> = []) throws {
        var value = try exclusions(); value.subtract(restore.map(Self.pinID)); value.formUnion(ids.map(Self.pinID))
        guard value.count <= 100_000, value.allSatisfy({ !$0.isEmpty && $0.count <= 100 && $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) }) else {
            throw CorkError("The excluded pin list is invalid or full.")
        }
        try write(value, name: "excluded.json")
    }
    func spend(_ bytes: Int) throws {
        var value = try state(); value.bytesToday += bytes
        guard (0...32_000_000).contains(value.bytesToday) else { throw CorkError("Today's image download budget is exhausted.") }
        try save(value)
    }
    public nonisolated func acquireLock() throws -> Int32 {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(root.appendingPathComponent("sync.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CorkError("Could not open the daily sync lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); throw CorkError("A Pinterest check is already running.") }
        return descriptor
    }
    public nonisolated static func releaseLock(_ descriptor: Int32) { _ = flock(descriptor, LOCK_UN); close(descriptor) }
}

public protocol DailyPinterestSource: Sendable {
    func connect() async throws -> PinterestAccount
    func recent(_ board: PinterestBoard) async throws -> [PinterestImage]
    func disconnect() async
}
extension PinterestClient: DailyPinterestSource {
    public func recent(_ board: PinterestBoard) async throws -> [PinterestImage] {
        let result = try await images(board: board, count: 100, capacity: 100)
        if let warning = result.warning { throw CorkError(warning) }
        return result.images
    }
}

private actor DailyImageBudget: ImportHTTP {
    let http: any ImportHTTP
    let store: DailySyncStore
    let freeBytes: @Sendable () throws -> Int64
    init(http: any ImportHTTP, store: DailySyncStore, freeBytes: @escaping @Sendable () throws -> Int64) {
        self.http = http; self.store = store; self.freeBytes = freeBytes
    }
    func get(_ url: URL, headers: [String: String], limit: Int) async throws -> HTTPReply {
        guard try await store.settings().enabled else { throw CancellationError() }
        guard try freeBytes() >= 2_000_000_000 else { throw CorkError("Daily sync paused: keep at least 2 GB free.") }
        let remaining = 32_000_000 - (try await store.state().bytesToday)
        guard remaining > 0 else { throw CorkError("Today's 32 MB download budget is used. Remaining pins wait for another day.") }
        let reserved = min(limit, remaining)
        // Persist the allowance before I/O. A failed or interrupted response may
        // already have consumed bytes, so it keeps its conservative reservation.
        try await store.spend(reserved)
        let reply = try await http.get(url, headers: headers, limit: reserved)
        guard reply.data.count <= reserved else { throw CorkError("The image exceeds today's download budget.") }
        try await store.spend(reply.data.count - reserved)
        return reply
    }
    func close() async { await http.close() }
}

public actor PinterestDailySync {
    public let store: DailySyncStore
    private let destination: any CorkImportDestination
    private let images: any ImportHTTP
    private let freeBytes: @Sendable () throws -> Int64
    public init(store: DailySyncStore, destination: any CorkImportDestination = NativeCorkDestination(),
                images: any ImportHTTP = NativeImportHTTP(), freeBytes: @escaping @Sendable () throws -> Int64 = {
                    let values = try ImportSessionStore.defaultDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    return values.volumeAvailableCapacityForImportantUsage ?? 0
                }) {
        self.store = store; self.destination = destination; self.images = images; self.freeBytes = freeBytes
    }
    public static func day(_ now: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    public static func due(_ state: DailySyncState, now: Date) -> Bool {
        state.lastAttempt.map { day($0) != day(now) } ?? true
    }
    private func inventory() async throws -> (Set<String>, Int) {
        var seen: Set<String> = [], offset = 0, count = 0
        for _ in 0..<40 {
            let page = try await destination.call("cork_get_collection", arguments: ["include_metadata": .bool(true), "offset": .number(Double(offset)), "limit": .number(500)])
            count = Int(page["photo_count"]?.number ?? 0)
            for photo in page["photos"]?.array ?? [] {
                guard let text = photo["sourceURL"]?.string, let url = URL(string: text), PinterestCookie.pinterestHost(url.host ?? "") else { continue }
                let parts = url.path.split(separator: "/")
                if parts.count == 2 && parts[0] == "pin" { seen.insert(String(parts[1])) }
            }
            guard page["has_more"]?.bool == true else { return (seen, count) }
            offset += 500
        }
        throw CorkError("Cork's collection inventory exceeded the supported capacity.")
    }
    /// First use baselines the latest 100 pins per board; it never backfills old boards.
    public func run(source: any DailyPinterestSource, now: Date = Date(), force: Bool = false) async throws -> DailySyncState {
        let lock = try store.acquireLock(); defer { DailySyncStore.releaseLock(lock) }
        let settings = try await store.settings()
        guard settings.enabled else { return try await store.state() }
        var state = try await store.state()
        guard force || Self.due(state, now: now) else { return state }
        if state.day != Self.day(now) { state.day = Self.day(now); state.addedToday = 0; state.attemptedToday = 0; state.bytesToday = 0 }
        state.lastAttempt = now; state.lastMessage = "Checking Pinterest…"; try await store.save(state)
        do {
            let account = try await source.connect()
            guard account.username.caseInsensitiveCompare(settings.username) == .orderedSame else { throw CorkError("The browser's Pinterest account changed. Reconnect before syncing.") }
            let (known, count) = try await inventory()
            state.seen.formUnion(known)
            let excluded = try await store.exclusions()
            state.pending.removeAll { pin in known.contains(pin.id) || excluded.contains(pin.id) || !settings.boards.contains(where: { $0.id == pin.boardID }) }
            var pendingIDs = Set(state.pending.map(\.id))
            var queueFull = false
            for board in settings.boards {
                try Task.checkCancellation()
                guard try await store.settings().enabled else { throw CancellationError() }
                let fresh = try await source.recent(board)
                if state.baselineBoards.insert(board.id).inserted {
                    state.seen.formUnion(fresh.map(\.id)); continue
                }
                for pin in fresh where !state.seen.contains(pin.id) && !excluded.contains(pin.id) && pendingIDs.insert(pin.id).inserted {
                    if state.pending.count >= 2_000 { queueFull = true; break }
                    state.pending.append(pin)
                }
                if queueFull { break }
            }
            guard state.seen.count <= 100_000 else { throw CorkError("Daily pin history is full. Reconnect to start a new baseline.") }
            try await store.save(state)
            let capacity = max(0, PhotoCollection.maximumPhotos - count)
            let quota = min(capacity, max(0, settings.maximumPerDay - state.attemptedToday))
            var selected: [PinterestImage] = []
            let boards = settings.boards
            var groups = Dictionary(grouping: state.pending, by: \.boardID)
            for round in 0..<quota {
                let before = selected.count
                for shift in 0..<boards.count {
                    let board = boards[(state.boardOffset + shift) % boards.count]
                    if groups[board.id]?.isEmpty == false, let pin = groups[board.id]?.removeFirst() { selected.append(pin) }
                    if selected.count >= quota { break }
                }
                if selected.count >= quota || selected.count == before || round >= 49 { break }
            }
            if !selected.isEmpty {
                guard try freeBytes() >= 2_000_000_000 else { throw CorkError("Daily sync paused: keep at least 2 GB free.") }
                state.attemptedToday += selected.count; try await store.save(state)
                let transferStore = ImportSessionStore(root: store.root.appendingPathComponent("Transfer"))
                let budget = DailyImageBudget(http: images, store: store, freeBytes: freeBytes)
                let coordinator = ImportCoordinator(store: transferStore, destination: destination, images: budget)
                let review = try await coordinator.transfer(ImportReview(images: selected)) { _, _ in }
                state = try await store.state()
                let committed = review.committed
                state.seen.formUnion(committed); state.pending.removeAll { committed.contains($0.id) }
                state.addedToday += committed.count
                try await transferStore.discard()
            }
            state.boardOffset = boards.isEmpty ? 0 : (state.boardOffset + 1) % boards.count
            state.lastSuccess = now
            state.lastMessage = capacity == 0 ? "Cork's collection is full. New pins are waiting." :
                "\(selected.count) new images added.\(state.pending.isEmpty ? "" : " \(state.pending.count) waiting within the daily limit.")"
            try await store.save(state); await source.disconnect(); await images.close(); return state
        } catch {
            // A later check reconciles stable source URLs before any new import.
            var failed = try await store.state(); failed.lastMessage = String(error.localizedDescription.prefix(2_000)); try await store.save(failed)
            await source.disconnect(); await images.close(); throw error
        }
    }
}
