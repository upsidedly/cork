import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CorkImportCore
import CorkCore

struct Failure: Error, CustomStringConvertible { var description: String }
func check(_ value: Bool, _ message: String = "Expectation failed", line: Int = #line) throws { if !value { throw Failure(description: "Line \(line): \(message)") } }
func rejects(_ action: () async throws -> Void) async throws {
    do { try await action() } catch is CorkError { return }
    throw Failure(description: "Expected a controlled CorkError")
}
func json(_ value: JSONValue) throws -> HTTPReply { HTTPReply(data: try value.data()) }
func temp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("CorkImportChecks-" + UUID().uuidString) }
let board = PinterestBoard(id: "board1", name: "Landscapes", path: "/fixture/landscapes/", pinCount: 2)
func pin(_ id: String, host: String = "i.pinimg.com", boardID: String = "board1") -> JSONValue {
    .object(["id": .string(id), "type": .string("pin"), "board": .object(["id": .string(boardID)]), "title": .string("Pin \(id)"),
        "images": .object(["orig": .object(["url": .string("https://\(host)/originals/\(id).jpg"), "width": .number(1200), "height": .number(800)]),
            "236x": .object(["url": .string("https://\(host)/236x/\(id).jpg"), "width": .number(236), "height": .number(157)])])])
}
func feed(_ entries: [JSONValue], _ cursor: String = "-end-") -> JSONValue {
    .object(["resource_response": .object(["data": .array(entries)]), "resource": .object(["options": .object(["bookmarks": .array([.string(cursor)])])])])
}
func home(authenticated: Bool = true) throws -> HTTPReply {
    let root = JSONValue.object(["appVersion": .string("fixture"), "context": .object(["is_authenticated": .bool(authenticated),
        "user": .object(["id": .string("fixture-user"), "username": .string("fixture"), "full_name": .string("Fixture")])])])
    return HTTPReply(data: Data(("<html><script id='__PWS_DATA__' type='application/json'>" + String(decoding: try root.data(), as: UTF8.self) + "</script></html>").utf8))
}
actor FixtureHTTP: ImportHTTP {
    var replies: [HTTPReply]; var urls: [URL] = []
    init(_ replies: [HTTPReply]) { self.replies = replies }
    func get(_ url: URL, headers: [String: String], limit: Int) throws -> HTTPReply {
        urls.append(url); guard !replies.isEmpty else { throw CorkError("No fixture response") }; return replies.removeFirst()
    }
    func requests() -> [URL] { urls }
}
func sampleJPEG() throws -> Data {
    guard let context = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let data = CFDataCreateMutable(nil, 0) else { throw Failure(description: "No fixture bitmap") }
    context.setFillColor(CGColor(red: 0.12, green: 0.35, blue: 0.65, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
    guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure(description: "No fixture image") }
    CGImageDestinationAddImage(destination, image, nil); try check(CGImageDestinationFinalize(destination)); return data as Data
}
actor FixtureDestination: CorkImportDestination {
    let repository: BoardRepository; var writes = 0; var loseFirstReply: Bool
    init(root: URL, loseFirstReply: Bool = false) { repository = BoardRepository(root: root); self.loseFirstReply = loseFirstReply }
    func call(_ method: String, arguments: [String: JSONValue]) async throws -> JSONValue {
        if method == "cork_import_collection" {
            writes += 1; _ = try await repository.importCollection(at: arguments.requiredString("path"))
            if loseFirstReply { loseFirstReply = false; throw CorkError("Simulated lost commit reply") }; return .object([:])
        }
        let collection = try await repository.loadCollection().0
        let ids = arguments["ids"]?.array?.compactMap(\.string), urls = arguments["source_urls"]?.array?.compactMap(\.string)
        let filtered = collection.photos.filter { ids == nil && urls == nil || ids?.contains($0.id) == true || urls?.contains($0.sourceURL) == true }
        let offset = Int(arguments["offset"]?.number ?? 0), limit = Int(arguments["limit"]?.number ?? 500)
        let selected = Array(filtered.dropFirst(offset).prefix(limit))
        return .object(["photo_count": .number(Double(collection.photos.count)), "capacity": .number(20_000), "photos": try JSONValue.encode(selected), "themes": try JSONValue.encode(collection.themes)])
    }
    func writeCount() -> Int { writes }
    func photos() async throws -> [CollectionPhoto] { try await repository.loadCollection().0.photos }
}
@main enum ImportChecks {
    static func main() async {
        let cases: [(String, () async throws -> Void)] = [
            ("Cookie host/path/expiry scoping", cookieScoping), ("Browser SQLite consent and scoped decryption", browserSQLite),
            ("Redirect and source URL boundaries", redirectBoundaries), ("Verified authentication", authentication),
            ("Board pagination", boardPagination), ("Image pagination and deduplication", imagePagination),
            ("Incomplete All and repeated pages", incompleteCoverage), ("Rate limits do not retry", rateLimit),
            ("Private review persistence", reviewPersistence), ("Staging measures actual colours", staging),
            ("Lost commit is reconciled before retry", lostReplyRecovery), ("Removed images never download", removedImages),
            ("Daily sync consent and private persistence", dailyPrivacy), ("Daily baseline, new pins and duplicate suppression", dailyBaseline),
            ("Daily source fairness and hard daily quota", dailyFairness), ("Daily rejected pins stay excluded", dailyExclusions),
            ("Daily low storage preserves queued metadata", dailyStorage), ("Daily lost reply is reconciled", dailyAmbiguous),
            ("Daily account and concurrent-run guards", dailyGuards), ("Disabled and same-day checks do nothing", dailyDue),
            ("Daily byte budget blocks another download", dailyByteBudget)
        ]
        var failures = 0
        for (name, action) in cases {
            do { try await action(); print("PASS \(name)") } catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(cases.count - failures)/\(cases.count) importer checks passed"); if failures > 0 { exit(1) }
    }
}
func cookieScoping() async throws {
    let cookie = PinterestCookie(name: "_pinterest_sess", value: "fixture", domain: ".pinterest.com", path: "/resource")
    try check(cookie.valid() && cookie.applies(to: URL(string: "https://www.pinterest.com/resource/x")!))
    for url in ["https://evilpinterest.com/resource/x", "https://pinterest.com.evil.test/resource/x", "http://www.pinterest.com/resource/x", "https://www.pinterest.com/resources"] { try check(!cookie.applies(to: URL(string: url)!)) }
    for value in ["x\r\nCookie:bad", "x;evil=x"] { try check(!PinterestCookie(name: "a", value: value, domain: ".pinterest.com").valid()) }
    try check(!PinterestCookie(name: "a", value: "x", domain: ".pinterest.com", expires: Date(timeIntervalSince1970: 1)).valid())
}
func redirectBoundaries() async throws {
    for url in ["http://www.pinterest.com/", "https://evilpinterest.com/", "https://pinterest.com:8443/", "https://user:pass@pinterest.com/"] { try check(!ImportRedirectPolicy.allowed(URL(string: url)!, images: false)) }
    try check(ImportRedirectPolicy.allowed(URL(string: "https://www.pinterest.com/")!, images: false))
    try check(ImportRedirectPolicy.allowed(URL(string: "https://i.pinimg.com/originals/a.jpg")!, images: true))
    try check(PinterestImage.parse(pin("1", host: "evil.test"), board: board) == nil)
    let parsed = PinterestImage.parse(pin("1"), board: board)!
    try check(parsed.imageURL.path.contains("originals") && parsed.previewURL.path.contains("236x"))
}
func authentication() async throws {
    let client = PinterestClient(cookies: [], http: FixtureHTTP([try home()])); try check(try await client.connect().username == "fixture")
    let signedOut = PinterestClient(cookies: [], http: FixtureHTTP([try home(authenticated: false)])); try await rejects { _ = try await signedOut.connect() }
    try await rejects { _ = try PinterestParsing.bootstrap("<html>Sign in</html>") }
}
func boardPagination() async throws {
    let b = JSONValue.object(["id": .string("b1"), "name": .string("One"), "url": .string("/fixture/one/"), "pin_count": .number(50)])
    let second = JSONValue.object(["id": .string("b2"), "name": .string("Two"), "url": .string("/fixture/two/"), "pin_count": .number(20)])
    let http = FixtureHTTP([try home(), try json(feed([b], "next")), try json(feed([b, second]))]); let client = PinterestClient(cookies: [], http: http); _ = try await client.connect()
    try check(try await client.boards().map(\.id) == ["b1", "b2"])
    let urls = await http.requests(), query = URLComponents(url: urls.last!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "data" }?.value
    let options = try JSONDecoder().decode(JSONValue.self, from: Data(query!.utf8))["options"]
    try check(options?["bookmarks"]?.array == [.string("next")])
}
func imagePagination() async throws {
    let client = PinterestClient(cookies: [], http: FixtureHTTP([try home(), try json(feed([pin("1"), pin("2", boardID: "foreign")], "page2")), try json(feed([pin("1"), pin("3")]))])); _ = try await client.connect()
    let result = try await client.images(board: board, count: nil, capacity: 200)
    try check(result.images.map(\.id) == ["1", "3"] && result.omitted == 1 && result.complete)
}
func incompleteCoverage() async throws {
    var big = board; big.pinCount = 80
    let client = PinterestClient(cookies: [], http: FixtureHTTP([try home(), try json(feed([pin("1")]))])); _ = try await client.connect()
    let result = try await client.images(board: big, count: nil, capacity: 200); try check(!result.complete && result.warning != nil)
    let repeated = PinterestClient(cookies: [], http: FixtureHTTP([try home(), try json(feed([pin("1")], "same")), try json(feed([pin("1")], "same"))])); _ = try await repeated.connect()
    try check(try await repeated.images(board: big, count: nil, capacity: 200).warning != nil)
}
func rateLimit() async throws {
    let http = FixtureHTTP([try home(), HTTPReply(data: Data(), status: 429)])
    let actual = PinterestClient(cookies: [], http: http); _ = try await actual.connect(); try await rejects { _ = try await actual.boards() }
    try check(await http.requests().count == 2)
}
func reviewPersistence() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }; let store = ImportSessionStore(root: root)
    var review = ImportReview(images: [PinterestImage.parse(pin("1"), board: board)!]); review.removed.insert("1")
    try await store.save(review); let saved = try await store.load(); try check(saved?.removed == ["1"] && saved?.images.count == 1)
    let data = try Data(contentsOf: root.appendingPathComponent("review.json")); try check(!String(decoding: data, as: UTF8.self).contains("_pinterest_sess"))
    try check(try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int == 0o700)
    try check(try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("review.json").path)[.posixPermissions] as? Int == 0o600)
    try await store.discard(); try check(try await store.load() == nil)
}
func staging() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }; let store = ImportSessionStore(root: root), image = PinterestImage.parse(pin("1"), board: board)!
    let (url, palette, profile) = try await store.stage(image, bytes: sampleJPEG()); try check(FileManager.default.fileExists(atPath: url.path) && !palette.isEmpty && profile.coverage(.blue) > 0.8)
    try await rejects { _ = try await store.stage(image, bytes: Data("not an image".utf8)) }
    try await store.clearStaging(); try check(!FileManager.default.fileExists(atPath: url.path))
}
func lostReplyRecovery() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImportSessionStore(root: root.appendingPathComponent("import")), destination = FixtureDestination(root: root.appendingPathComponent("cork"), loseFirstReply: true)
    let http = FixtureHTTP([HTTPReply(data: try sampleJPEG())]); let coordinator = ImportCoordinator(store: store, destination: destination, images: http)
    let review = ImportReview(images: [PinterestImage.parse(pin("1"), board: board)!]); try await rejects { _ = try await coordinator.transfer(review, progress: { _, _ in }) }
    let writes = await destination.writeCount(), photos = try await destination.photos(); try check(writes == 1 && photos.count == 1)
    let resumed = try await coordinator.transfer(review, progress: { _, _ in }), finalWrites = await destination.writeCount(), requests = await http.requests()
    try check(resumed.committed == ["1"] && finalWrites == 1 && requests.count == 1)
    try check(photos[0].colourProfile != nil && photos[0].sourceBoardID == "pinterest-board1" && photos[0].sourceBoard == "Landscapes" && photos[0].themeIDs.contains("pinterest-library"))
}
func removedImages() async throws {
    let root = temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = ImportSessionStore(root: root.appendingPathComponent("import")), destination = FixtureDestination(root: root.appendingPathComponent("cork"))
    let http = FixtureHTTP([HTTPReply(data: try sampleJPEG())]); let coordinator = ImportCoordinator(store: store, destination: destination, images: http)
    var review = ImportReview(images: [PinterestImage.parse(pin("1"), board: board)!, PinterestImage.parse(pin("2"), board: board)!]); review.removed.insert("2")
    let result = try await coordinator.transfer(review, progress: { _, _ in }), photos = try await destination.photos(), requests = await http.requests()
    try check(result.committed == ["1"] && photos.count == 1 && requests.count == 1)
}
