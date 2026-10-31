import Foundation
import Security
import CommonCrypto
import CryptoKit
import CSQLite
import CorkCore

public struct BrowserProfile: Identifiable, Equatable, Sendable {
    public var browser: String
    public var name: String
    public var directory: URL
    public var service: String?
    public var account: String?
    public var firefox: Bool
    public var id: String { directory.path }
    public init(browser: String, name: String, directory: URL, service: String? = nil, account: String? = nil, firefox: Bool = false) {
        self.browser = browser; self.name = name; self.directory = directory; self.service = service; self.account = account; self.firefox = firefox
    }
    public static func available(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Self] {
        let support = home.appendingPathComponent("Library/Application Support")
        var result: [Self] = []
        for (browser, folder, service, account) in [
            ("Chrome", "Google/Chrome", "Chrome Safe Storage", "Chrome"),
            ("Chromium", "Chromium", "Chromium Safe Storage", "Chromium"),
            ("Brave", "BraveSoftware/Brave-Browser", "Brave Safe Storage", "Brave"),
            ("Edge", "Microsoft Edge", "Microsoft Edge Safe Storage", "Microsoft Edge")
        ] {
            let root = support.appendingPathComponent(folder)
            let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for dir in dirs where dir.lastPathComponent == "Default" || dir.lastPathComponent.hasPrefix("Profile ") {
                if ["Cookies", "Network/Cookies"].contains(where: { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }) {
                    result.append(Self(browser: browser, name: dir.lastPathComponent, directory: dir, service: service, account: account))
                }
            }
        }
        let firefoxRoot = support.appendingPathComponent("Firefox/Profiles")
        for dir in (try? FileManager.default.contentsOfDirectory(at: firefoxRoot, includingPropertiesForKeys: nil)) ?? [] {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("cookies.sqlite").path) {
                result.append(Self(browser: "Firefox", name: dir.lastPathComponent, directory: dir, firefox: true))
            }
        }
        return result.sorted { ($0.browser, $0.name) < ($1.browser, $1.name) }
    }
}

public struct PinterestCookie: Sendable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var secure: Bool
    public var expires: Date?
    public init(name: String, value: String, domain: String, path: String = "/", secure: Bool = true, expires: Date? = nil) {
        self.name = name; self.value = value; self.domain = domain; self.path = path; self.secure = secure; self.expires = expires
    }
    public static func pinterestHost(_ host: String) -> Bool { host == "pinterest.com" || host.hasSuffix(".pinterest.com") }
    public func valid(now: Date = Date()) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return Self.pinterestHost(host) && !name.isEmpty && name.count <= 256 && value.utf8.count <= 32_768
            && !name.contains(where: { $0.isWhitespace || "=;".contains($0) })
            && !value.contains(";")
            && !(name + value).unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
            && path.hasPrefix("/") && path.count <= 2048 && (expires.map { $0 > now } ?? true)
    }
    public func applies(to url: URL) -> Bool {
        guard let host = url.host?.lowercased(), Self.pinterestHost(host), url.scheme == "https", valid() else { return false }
        let cookieHost = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let pathMatches = url.path == path || (url.path.hasPrefix(path) && (path.hasSuffix("/") || url.path.dropFirst(path.count).first == "/"))
        return (host == cookieHost || (domain.hasPrefix(".") && host.hasSuffix("." + cookieHost))) && pathMatches
    }
}

public enum ChromeCookieCrypto {
    /// Native Chromium macOS v10 format. The browser key never leaves this call's memory.
    public static func decrypt(_ encrypted: Data, password: Data, host: String, databaseVersion: Int) throws -> String {
        guard encrypted.starts(with: Data("v10".utf8)), encrypted.count >= 19, (encrypted.count - 3).isMultiple(of: 16), !password.isEmpty else { throw CorkError("This browser's cookie encryption is unsupported. Try Chrome, Chromium, Brave, Edge or Firefox.") }
        var key = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8)
        let status = password.withUnsafeBytes { pass in
            salt.withUnsafeBufferPointer { salt in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                    salt.baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
            }
        }
        guard status == kCCSuccess else { throw CorkError("Could not derive the browser cookie key.") }
        defer { for index in key.indices { key[index] = 0 } }
        let bytes = encrypted.dropFirst(3), iv = [UInt8](repeating: 32, count: 16)
        var output = [UInt8](repeating: 0, count: bytes.count + 16), written = 0
        let capacity = output.count
        let decoded = bytes.withUnsafeBytes { input in
            iv.withUnsafeBytes { iv in
                CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), key, key.count,
                    iv.baseAddress, input.baseAddress, bytes.count, &output, capacity, &written)
            }
        }
        guard decoded == kCCSuccess else { throw CorkError("The browser cookie key could not decrypt Pinterest's session. No other cookies were read.") }
        var plaintext = Data(output.prefix(written))
        defer { for index in output.indices { output[index] = 0 } }
        if databaseVersion >= 24 {
            let hash = Data(SHA256.hash(data: Data(host.utf8)))
            guard plaintext.starts(with: hash) else { throw CorkError("A Pinterest cookie failed its browser-domain integrity check.") }
            plaintext.removeFirst(32)
        }
        guard let value = String(data: plaintext, encoding: .utf8) else { throw CorkError("Pinterest's session cookie is unreadable.") }
        return value
    }
}

public actor BrowserCookieReader {
    private let key: @Sendable (BrowserProfile) throws -> Data
    public init(key: @escaping @Sendable (BrowserProfile) throws -> Data = BrowserCookieReader.safeStorageKey) { self.key = key }
    public nonisolated static func safeStorageKey(_ profile: BrowserProfile) throws -> Data {
        guard let service = profile.service, let account = profile.account else { throw CorkError("This browser has no supported macOS cookie key.") }
        var value: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &value)
        guard status == errSecSuccess, let secret = value as? Data, !secret.isEmpty else {
            throw CorkError("macOS did not allow access to \(profile.browser)'s Safe Storage key. No connection was saved. You can cancel or retry the browser connection.")
        }
        return secret
    }
    public func read(_ profile: BrowserProfile, approved: Bool) throws -> [PinterestCookie] {
        guard approved else { throw CorkError("Connect only after approving the Pinterest-cookie disclosure.") }
        try Task.checkCancellation()
        let candidates = profile.firefox ? ["cookies.sqlite"] : ["Network/Cookies", "Cookies"]
        guard let path = candidates.map({ profile.directory.appendingPathComponent($0).path }).first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw CorkError("This browser profile has no cookie store. Open Pinterest in that profile and sign in first.")
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw CorkError("Could not open the selected browser's cookie store read-only. Close its cookie/settings window and retry.")
        }
        defer { sqlite3_close(db) }; sqlite3_busy_timeout(db, 2000)
        let table = profile.firefox ? "moz_cookies" : "cookies"
        let host = profile.firefox ? "host" : "host_key"
        let fields = profile.firefox ? "host,name,path,isSecure,expiry,value" : "host_key,name,path,is_secure,expires_utc,value,encrypted_value"
        var columns: Set<String> = [], schema: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &schema, nil) == SQLITE_OK {
            while sqlite3_step(schema) == SQLITE_ROW { if let name = sqlite3_column_text(schema, 1) { columns.insert(String(cString: name)) } }
        }
        sqlite3_finalize(schema)
        let partition = profile.firefox ? "originAttributes" : "top_frame_site_key"
        let unpartitioned = columns.contains(partition) ? " AND \(partition)=''" : ""
        let sql = "SELECT \(fields) FROM \(table) WHERE (lower(\(host))='pinterest.com' OR lower(\(host)) LIKE '%.pinterest.com')\(unpartitioned) LIMIT 257"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw CorkError("This browser's cookie database format is unsupported.") }
        defer { sqlite3_finalize(statement) }
        func string(_ index: Int32) -> String { sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "" }
        var rows: [(String, String, String, Bool, Date?, String, Data)] = []
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            try Task.checkCancellation()
            let expiry = sqlite3_column_double(statement, 4)
            let date = expiry > 0 ? Date(timeIntervalSince1970: profile.firefox ? expiry : expiry / 1_000_000 - 11_644_473_600) : nil
            var encrypted = Data()
            if !profile.firefox, let blob = sqlite3_column_blob(statement, 6) { encrypted = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 6))) }
            rows.append((string(0), string(1), string(2), sqlite3_column_int(statement, 3) != 0, date, string(5), encrypted))
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw CorkError("The browser cookie store is busy. Try again after it finishes saving.") }
        rows.removeAll { $0.4.map { $0 < Date() } ?? false }
        guard !rows.isEmpty, rows.count <= 256 else { throw CorkError("No supported Pinterest session was found in this profile. Sign in to Pinterest in a regular browser tab, then reconnect.") }
        var version = 0, meta: OpaquePointer?
        if !profile.firefox, sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key='version'", -1, &meta, nil) == SQLITE_OK {
            if sqlite3_step(meta) == SQLITE_ROW { version = Int(sqlite3_column_int(meta, 0)) }; sqlite3_finalize(meta)
        }
        var password = Data()
        try Task.checkCancellation()
        if rows.contains(where: { !$0.6.isEmpty }) {
            password = try key(profile)
        }
        defer { password.resetBytes(in: 0..<password.count) }
        try Task.checkCancellation()
        let cookies = try rows.map { row in
            let value = row.6.isEmpty ? row.5 : try ChromeCookieCrypto.decrypt(row.6, password: password, host: row.0, databaseVersion: version)
            return PinterestCookie(name: row.1, value: value, domain: row.0, path: row.2, secure: row.3, expires: row.4)
        }.filter { $0.valid() }
        guard cookies.contains(where: { $0.name == "_pinterest_sess" && !$0.value.isEmpty }) else { throw CorkError("This profile has no unexpired Pinterest login. Sign in in your browser, then reconnect.") }
        return cookies
    }
}
