import Foundation
import CorkCore
import CorkImportCore

actor DailyFixtureSource: DailyPinterestSource {
    var pins: [String: [PinterestImage]]
    var connections = 0
    var username = "fixture"
    init(_ pins: [String: [PinterestImage]]) { self.pins = pins }
    func connect() -> PinterestAccount { connections += 1; return .init(username: username, name: "Fixture") }
    func recent(_ board: PinterestBoard) -> [PinterestImage] { pins[board.id] ?? [] }
    func disconnect() {}
    func set(_ value: [String: [PinterestImage]]) { pins = value }
    func setAccount(_ value: String) { username = value }
    func count() -> Int { connections }
}
func dailyPin(_ id: String, board b: PinterestBoard = board) throws -> PinterestImage {
    guard let value = PinterestImage.parse(pin(id, boardID: b.id), board: b) else { throw Failure(description: "Invalid daily fixture") }
    return value
}
func dailyConfig(_ store: DailySyncStore, boards: [PinterestBoard] = [board], limit: Int = 10) async throws {
    var settings = DailySyncSettings(); settings.enabled = true; settings.consentVersion = 1
    settings.profile = BrowserProfile(browser: "Firefox", name: "Fixture", directory: URL(fileURLWithPath: "/fixture"), firefox: true)
    settings.bookmark = Data([1]); settings.username = "fixture"; settings.boards = boards; settings.maximumPerDay = limit
    try await store.save(settings)
}
func dailyPrivacy() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DailySyncStore(root: root)
    var invalid = DailySyncSettings(); invalid.enabled = true
    try await rejects { try await store.save(invalid) }
    try await dailyConfig(store)
    try await store.exclude(["pinterest-rejected"])
    let other = DailySyncStore(root: root)
    try check(try await other.settings().enabled)
    try check(try await other.exclusions().contains("rejected"))
    let text = try String(contentsOf: root.appendingPathComponent("settings.json"), encoding: .utf8)
    try check(!text.contains("_pinterest_sess") && !text.contains("password") && !text.contains("cookies"))
    let mode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("settings.json").path)[.posixPermissions] as? Int
    try check(mode == 0o600)
}
func dailyBaseline() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DailySyncStore(root: root.appendingPathComponent("Sync")); try await dailyConfig(store)
    let destination = FixtureDestination(root: root.appendingPathComponent("Cork"))
    let source = DailyFixtureSource([board.id: [try dailyPin("old")]])
    let http = FixtureHTTP([HTTPReply(data: try sampleJPEG())])
    let worker = PinterestDailySync(store: store, destination: destination, images: http, freeBytes: { 10_000_000_000 })
    let now = Date(); let baseline = try await worker.run(source: source, now: now)
    try check(baseline.seen.contains("old") && baseline.pending.isEmpty)
    try check(await http.requests().isEmpty)
    try check(await destination.writeCount() == 0)
    await source.set([board.id: [try dailyPin("new"), try dailyPin("old")]])
    let result = try await worker.run(source: source, now: now.addingTimeInterval(86_400))
    try check(result.seen.contains("new") && result.addedToday == 1 && result.pending.isEmpty)
    try check(result.bytesToday == (try sampleJPEG()).count)
    let photos = try await destination.photos()
    try check(photos.count == 1 && photos[0].sourceBoardID == "pinterest-board1" && photos[0].colourProfile != nil)
    _ = try await worker.run(source: source, now: now.addingTimeInterval(86_400), force: true)
    try check(await destination.writeCount() == 1)
    try check(await http.requests().count == 1)
}
func dailyFairness() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let other = PinterestBoard(id: "board2", name: "Art", path: "/fixture/art/", pinCount: 10)
    let store = DailySyncStore(root: root.appendingPathComponent("Sync")); try await dailyConfig(store, boards: [board, other], limit: 3)
    let source = DailyFixtureSource([:]), destination = FixtureDestination(root: root.appendingPathComponent("Cork"))
    let http = FixtureHTTP(try (0..<4).map { _ in HTTPReply(data: try sampleJPEG()) })
    let worker = PinterestDailySync(store: store, destination: destination, images: http, freeBytes: { 10_000_000_000 })
    let now = Date(); _ = try await worker.run(source: source, now: now)
    await source.set([board.id: try [dailyPin("a"), dailyPin("b")], other.id: try [dailyPin("c", board: other), dailyPin("d", board: other)]])
    let result = try await worker.run(source: source, now: now.addingTimeInterval(86_400))
    try check(result.addedToday == 3 && result.pending.count == 1 && result.attemptedToday == 3)
    try check(try await Set(destination.photos().compactMap(\.sourceBoardID)).count == 2)
    _ = try await worker.run(source: source, now: now.addingTimeInterval(86_400), force: true)
    try check(await http.requests().count == 3)
    _ = try await worker.run(source: source, now: now.addingTimeInterval(172_800))
    try check(try await destination.photos().count == 4)
}
func dailyExclusions() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DailySyncStore(root: root.appendingPathComponent("Sync")); try await dailyConfig(store)
    let source = DailyFixtureSource([:]), destination = FixtureDestination(root: root.appendingPathComponent("Cork")), http = FixtureHTTP([])
    let worker = PinterestDailySync(store: store, destination: destination, images: http, freeBytes: { 10_000_000_000 })
    let now = Date(); _ = try await worker.run(source: source, now: now)
    try await store.exclude(["reject"])
    await source.set([board.id: [try dailyPin("reject")]])
    let result = try await worker.run(source: source, now: now.addingTimeInterval(86_400))
    try check(result.pending.isEmpty)
    try check(await http.requests().isEmpty)
    try check(await destination.writeCount() == 0)
    try await store.exclude([], restore: ["reject"]); try check(try await store.exclusions().isEmpty)
}
func dailyStorage() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DailySyncStore(root: root.appendingPathComponent("Sync")); try await dailyConfig(store)
    let source = DailyFixtureSource([:]), http = FixtureHTTP([]), destination = FixtureDestination(root: root.appendingPathComponent("Cork"))
    let worker = PinterestDailySync(store: store, destination: destination, images: http, freeBytes: { 1_000_000_000 })
    let now = Date(); _ = try await worker.run(source: source, now: now)
    await source.set([board.id: [try dailyPin("wait")]])
    try await rejects { _ = try await worker.run(source: source, now: now.addingTimeInterval(86_400)) }
    try check(try await store.state().pending.count == 1)
    try check(await http.requests().isEmpty)
    try check(await destination.writeCount() == 0)
}
func dailyAmbiguous() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DailySyncStore(root: root.appendingPathComponent("Sync")); try await dailyConfig(store)
    let source = DailyFixtureSource([:]), http = FixtureHTTP([HTTPReply(data: try sampleJPEG())])
    let destination = FixtureDestination(root: root.appendingPathComponent("Cork"), loseFirstReply: true)
    let worker = PinterestDailySync(store: store, destination: destination, images: http, freeBytes: { 10_000_000_000 })
    let now = Date(); _ = try await worker.run(source: source, now: now)
    await source.set([board.id: [try dailyPin("once")]])
    try await rejects { _ = try await worker.run(source: source, now: now.addingTimeInterval(86_400)) }
    _ = try await worker.run(source: source, now: now.addingTimeInterval(86_400), force: true)
    try check(await destination.writeCount() == 1)
    try check(await http.requests().count == 1)
    try check(try await store.state().pending.isEmpty)
}
func dailyGuards() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DailySyncStore(root: root.appendingPathComponent("Sync")); try await dailyConfig(store)
    let source = DailyFixtureSource([:]); await source.setAccount("other")
    let destination = FixtureDestination(root: root.appendingPathComponent("Cork"))
    let worker = PinterestDailySync(store: store, destination: destination, images: FixtureHTTP([]), freeBytes: { 10_000_000_000 })
    try await rejects { _ = try await worker.run(source: source) }
    let lock = try store.acquireLock(); defer { DailySyncStore.releaseLock(lock) }
    try await rejects { _ = try await worker.run(source: source, force: true) }
    try check(await destination.writeCount() == 0)
}
func dailyDue() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DailySyncStore(root: root.appendingPathComponent("Sync")), source = DailyFixtureSource([:])
    let worker = PinterestDailySync(store: store, destination: FixtureDestination(root: root.appendingPathComponent("Cork")), images: FixtureHTTP([]), freeBytes: { 10_000_000_000 })
    let now = Date(); _ = try await worker.run(source: source, now: now)
    try check(await source.count() == 0)
    try await dailyConfig(store); _ = try await worker.run(source: source, now: now)
    _ = try await worker.run(source: source, now: now)
    try check(await source.count() == 1)
}
func dailyByteBudget() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = DailySyncStore(root: root.appendingPathComponent("Sync")); try await dailyConfig(store)
    let source = DailyFixtureSource([:]), http = FixtureHTTP([]), destination = FixtureDestination(root: root.appendingPathComponent("Cork"))
    let worker = PinterestDailySync(store: store, destination: destination, images: http, freeBytes: { 10_000_000_000 })
    let now = Date(); _ = try await worker.run(source: source, now: now)
    var state = try await store.state(); state.bytesToday = 32_000_000; try await store.save(state)
    await source.set([board.id: [try dailyPin("tomorrow")]])
    try await rejects { _ = try await worker.run(source: source, now: now, force: true) }
    try check(await http.requests().isEmpty)
    try check(await destination.writeCount() == 0)
    try check(try await store.state().pending.count == 1)
    // A failed response can have transferred an unknown number of bytes. Its
    // allowance stays reserved, so Check Now cannot repeatedly spend it.
    state = try await store.state(); state.bytesToday = 0; try await store.save(state)
    try await rejects { _ = try await worker.run(source: source, now: now, force: true) }
    try check(try await store.state().bytesToday == 32_000_000)
    try await rejects { _ = try await worker.run(source: source, now: now, force: true) }
    try check(await http.requests().count == 1)
    try check(await destination.writeCount() == 0)
}
