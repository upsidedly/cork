import Foundation
import CorkCore

public struct HTTPReply: Sendable {
    public var data: Data
    public var status: Int
    public init(data: Data, status: Int = 200) { self.data = data; self.status = status }
}
public protocol ImportHTTP: Sendable {
    func get(_ url: URL, headers: [String: String], limit: Int) async throws -> HTTPReply
    func close() async
}
public extension ImportHTTP { func close() async {} }

/// Ephemeral, cache-free sessions. Redirects never carry Pinterest credentials to another service.
public final class ImportRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    private let cookies: [PinterestCookie]
    public init(cookies: [PinterestCookie] = []) { self.cookies = cookies }
    public static func allowed(_ url: URL, images: Bool) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return images ? (host == "pinimg.com" || host.hasSuffix(".pinimg.com")) : PinterestCookie.pinterestHost(host)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url,
              Self.allowed(target, images: original.host?.hasSuffix("pinimg.com") == true) else { completionHandler(nil); return }
        var next = request
        next.setValue(nil, forHTTPHeaderField: "Cookie")
        if PinterestCookie.pinterestHost(target.host ?? "") {
            let value = cookies.filter { $0.applies(to: target) }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            if !value.isEmpty { next.setValue(value, forHTTPHeaderField: "Cookie") }
        }
        completionHandler(next)
    }
}

public struct NativeImportHTTP: ImportHTTP {
    private let session: URLSession
    private let cookies: [PinterestCookie]
    public init(cookies: [PinterestCookie] = []) {
        self.cookies = cookies
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData; config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90; config.httpMaximumConnectionsPerHost = 3
        session = URLSession(configuration: config, delegate: ImportRedirectPolicy(cookies: cookies), delegateQueue: nil)
    }
    public func get(_ url: URL, headers: [String: String] = [:], limit: Int) async throws -> HTTPReply {
        let images = url.host?.hasSuffix("pinimg.com") == true
        guard ImportRedirectPolicy.allowed(url, images: images) else { throw CorkError("The import source is outside Pinterest's supported hosts.") }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers where key.lowercased() != "cookie" { request.setValue(value, forHTTPHeaderField: key) }
        if !images {
            request.setValue(cookies.filter { $0.applies(to: url) }.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw CorkError("Pinterest returned an unreadable response.") }
        guard response.expectedContentLength <= Int64(limit) else { throw CorkError("Pinterest returned a file larger than the import limit.") }
        var data = Data(); data.reserveCapacity(min(limit, max(0, Int(response.expectedContentLength))))
        for try await byte in stream {
            if data.count.isMultiple(of: 65_536) { try Task.checkCancellation() }
            guard data.count < limit else { throw CorkError("Pinterest returned a file larger than the import limit.") }
            data.append(byte)
        }
        return HTTPReply(data: data, status: response.statusCode)
    }
    public func close() { session.invalidateAndCancel() }
}

public struct PinterestAccount: Sendable, Equatable {
    public var username: String
    public var name: String
    public init(username: String, name: String) { self.username = username; self.name = name }
}
public struct PinterestBoard: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var path: String
    public var pinCount: Int
    public init(id: String, name: String, path: String, pinCount: Int) { self.id = id; self.name = name; self.path = path; self.pinCount = pinCount }
}
public struct PinterestImage: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var boardID: String
    public var boardName: String
    public var title: String
    public var description: String
    public var sourceURL: String
    public var imageURL: URL
    public var previewURL: URL
    public var width: Int
    public var height: Int
    public var collectionID: String { "pinterest-" + id }
    public static func parse(_ value: JSONValue, board: PinterestBoard) -> Self? {
        guard let id = value["id"]?.string, !id.isEmpty, id.count <= 100, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }),
              value["type"]?.string == nil || value["type"]?.string == "pin", value["is_video"]?.bool != true,
              value["videos"] == nil || value["videos"] == .null,
              let variants = value["images"]?.object else { return nil }
        let images = variants.values.compactMap { variant -> (URL, Int, Int)? in
            guard let text = variant["url"]?.string, let url = URL(string: text), ImportRedirectPolicy.allowed(url, images: true),
                  let w = variant["width"]?.number, let h = variant["height"]?.number,
                  (80...50_000).contains(w), (80...50_000).contains(h) else { return nil }
            return (url, Int(w), Int(h))
        }.sorted { $0.1 * $0.2 < $1.1 * $1.2 }
        guard let largest = images.last else { return nil }
        let preview = images.first(where: { $0.1 >= 236 }) ?? largest
        let title = [value["grid_title"]?.string, value["title"]?.string, value["auto_alt_text"]?.string, value["description"]?.string]
            .compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        let description = [value["description"]?.string, value["auto_alt_text"]?.string].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        return Self(id: id, boardID: board.id, boardName: String(board.name.prefix(200)), title: String(title.prefix(300)),
            description: String(description.prefix(2000)),
            sourceURL: "https://www.pinterest.com/pin/\(id)/", imageURL: largest.0, previewURL: preview.0, width: largest.1, height: largest.2)
    }
}
public struct PinterestFetch: Sendable {
    public var images: [PinterestImage]
    public var scanned: Int
    public var omitted: Int
    public var complete: Bool
    public var warning: String?
}

public enum PinterestParsing {
    public static func bootstrap(_ html: String) throws -> JSONValue {
        let pattern = #"<script\b[^>]*\bid=["']__PWS_DATA__["'][^>]*>([\s\S]*?)</script>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let range = Range(match.range(at: 1), in: html) else {
            throw CorkError("Pinterest's sign-in page changed or the browser session expired. Sign in in your browser and reconnect.")
        }
        return try JSONDecoder().decode(JSONValue.self, from: Data(html[range].utf8))
    }
    public static func bookmarks(_ response: JSONValue) -> [String] {
        (response["resource"]?["options"]?["bookmarks"]?.array ?? response["resource_response"]?["bookmark"]?.array ?? []).compactMap(\.string)
    }
}

public actor PinterestClient {
    private let http: any ImportHTTP
    private var appVersion: String?
    private var account: PinterestAccount?
    private let csrf: String?
    public init(cookies: [PinterestCookie], http: (any ImportHTTP)? = nil) {
        self.http = http ?? NativeImportHTTP(cookies: cookies)
        csrf = cookies.first { $0.name == "csrftoken" }?.value
    }
    public func connect() async throws -> PinterestAccount {
        guard let home = URL(string: "https://www.pinterest.com/") else { throw CorkError("Pinterest's address is unavailable.") }
        let reply = try await http.get(home, headers: [:], limit: 15_000_000)
        try check(reply)
        let root = try PinterestParsing.bootstrap(String(decoding: reply.data, as: UTF8.self))
        let context = root["context"] ?? root["initialReduxState"]?["context"] ?? .null
        guard context["is_authenticated"]?.bool == true,
              let user = context["user"], user["id"]?.string?.isEmpty == false, let username = user["username"]?.string, !username.isEmpty,
              username.count <= 200, username.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }) else {
            throw CorkError("Pinterest did not confirm a signed-in account. Sign in to Pinterest in the selected profile, then reconnect.")
        }
        appVersion = root["appVersion"]?.string ?? context["app_version"]?.string
        let result = PinterestAccount(username: username, name: user["full_name"]?.string ?? username)
        account = result; return result
    }
    public func disconnect() async { account = nil; await http.close() }
    public func boards() async throws -> [PinterestBoard] {
        guard let account else { throw CorkError("Connect your Pinterest account first.") }
        var result: [PinterestBoard] = [], cursor: [String] = [], seen: Set<String> = []
        for _ in 0..<200 {
            let reply = try await resource("Boards", path: "/\(account.username)/", options: ["username": .string(account.username), "page_size": .number(25),
                "field_set_key": .string("profile_grid_item"), "sort": .string("last_pinned_to"), "include_archived": .bool(false), "bookmarks": .array(cursor.map(JSONValue.string))])
            guard let entries = reply["resource_response"]?["data"]?.array else { throw CorkError("Pinterest's board list is unavailable. Reconnect or try again later.") }
            for entry in entries {
                guard let id = entry["id"]?.string, !result.contains(where: { $0.id == id }), let name = entry["name"]?.string,
                      let path = entry["url"]?.string, path.hasPrefix("/"), !path.hasPrefix("//"), path.count <= 2048 else { continue }
                result.append(PinterestBoard(id: id, name: String(name.prefix(200)), path: path, pinCount: Int(min(1_000_000, max(0, entry["pin_count"]?.number ?? 0)))))
            }
            let next = PinterestParsing.bookmarks(reply)
            if entries.isEmpty || next.isEmpty || next.contains("-end-") { return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
            guard seen.insert(next.joined(separator: "\n")).inserted else { throw CorkError("Pinterest repeated a board-list page. Reconnect and retry; the list was not silently truncated.") }
            cursor = next; try await Task.sleep(for: .milliseconds(350))
        }
        throw CorkError("Pinterest returned more than 5,000 boards. Import a smaller account or try again after archiving unused boards.")
    }
    public func images(board: PinterestBoard, count: Int?, capacity: Int,
                       progress: @Sendable (Int) async -> Void = { _ in }) async throws -> PinterestFetch {
        guard account != nil else { throw CorkError("Connect Pinterest first.") }
        guard capacity > 0, count == nil || [20, 50, 100, 150, 200].contains(count ?? 0) else { throw CorkError("Choose a supported board quota.") }
        let target = min(count ?? capacity, capacity)
        var images: [PinterestImage] = [], cursor: [String] = [], seenPages: Set<String> = [], seenPins: Set<String> = [], scanned = 0, omitted = 0
        for _ in 0..<400 {
            try Task.checkCancellation()
            let response = try await resource("BoardFeed", path: board.path, options: ["board_id": .string(board.id), "page_size": .number(100),
                "field_set_key": .string("react_grid_pin"), "bookmarks": .array(cursor.map(JSONValue.string))])
            guard let entries = response["resource_response"]?["data"]?.array else { throw CorkError("Pinterest's image feed changed. Your existing Cork library is untouched.") }
            var fresh = 0
            for value in entries {
                guard let id = value["id"]?.string, seenPins.insert(id).inserted else { continue }
                scanned += 1; fresh += 1
                if let owner = value["board"]?["id"]?.string, owner != board.id { omitted += 1; continue }
                guard let image = PinterestImage.parse(value, board: board) else { omitted += 1; continue }
                if images.count < target { images.append(image) }
            }
            await progress(images.count)
            let next = PinterestParsing.bookmarks(response)
            let end = entries.isEmpty || next.isEmpty || next.contains("-end-")
            if end || images.count >= target {
                let truncated = count == nil && (!end || scanned < board.pinCount)
                return PinterestFetch(images: images, scanned: scanned, omitted: omitted, complete: !truncated,
                    warning: truncated ? "\(board.name): \(scanned) of \(board.pinCount) pins were available before the feed ended or capacity was reached. All was not fully imported." : nil)
            }
            if fresh == 0 || !seenPages.insert(next.joined(separator: "\n")).inserted {
                return PinterestFetch(images: images, scanned: scanned, omitted: omitted, complete: false,
                    warning: "\(board.name): Pinterest repeated a page. Review these \(images.count) images; the remainder was not available.")
            }
            cursor = next; try await Task.sleep(for: .milliseconds(350))
        }
        return PinterestFetch(images: images, scanned: scanned, omitted: omitted, complete: false, warning: "\(board.name): Pinterest stopped responding before the whole board was available.")
    }
    private func resource(_ name: String, path: String, options: [String: JSONValue]) async throws -> JSONValue {
        let payload = try JSONValue.object(["options": .object(options), "context": .object([:])]).data()
        var parts = URLComponents(); parts.scheme = "https"; parts.host = "www.pinterest.com"; parts.path = "/resource/\(name)Resource/get/"
        parts.queryItems = [URLQueryItem(name: "source_url", value: path), URLQueryItem(name: "data", value: String(decoding: payload, as: UTF8.self))]
        guard let url = parts.url else { throw CorkError("Could not form a Pinterest request.") }
        var headers = ["Accept": "application/json", "X-Requested-With": "XMLHttpRequest", "X-Pinterest-AppState": "active", "Referer": "https://www.pinterest.com\(path)"]
        headers["x-pinterest-pws-handler"] = "www/[username]/[slug].js"; headers["x-pinterest-source-url"] = path
        if let appVersion { headers["X-APP-VERSION"] = appVersion }; if let csrf { headers["X-CSRFToken"] = csrf }
        let reply = try await http.get(url, headers: headers, limit: 15_000_000); try check(reply)
        let value = try JSONDecoder().decode(JSONValue.self, from: reply.data)
        if value["resource_response"]?["status"]?.string == "failure" || value["resource_response"]?["error"]?.object != nil {
            throw CorkError("Pinterest declined this request. Reconnect if your session expired, or try again later.")
        }
        return value
    }
    private func check(_ reply: HTTPReply) throws {
        switch reply.status {
        case 200..<300: return
        case 401, 403: throw CorkError("Pinterest needs you to sign in or complete its browser check. Open Pinterest in your browser, then reconnect.")
        case 429: throw CorkError("Pinterest is limiting requests. Wait before reconnecting; Cork will not bypass that limit.")
        default: throw CorkError("Pinterest is unavailable (HTTP \(reply.status)). Try again later.")
        }
    }
}
