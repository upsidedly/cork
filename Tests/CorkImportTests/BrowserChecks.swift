import Foundation
import CryptoKit
import CommonCrypto
import CSQLite
import CorkImportCore
import CorkCore

private func encrypt(_ value: String, password: Data, host: String, version: Int) throws -> Data {
    var key = [UInt8](repeating: 0, count: 16), salt = Array("saltysalt".utf8)
    let derived = password.withUnsafeBytes { pass in CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress?.assumingMemoryBound(to: Int8.self), password.count, &salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, 16) }; try check(derived == kCCSuccess)
    var plaintext = version >= 24 ? Data(SHA256.hash(data: Data(host.utf8))) : Data(); plaintext.append(Data(value.utf8))
    var encrypted = [UInt8](repeating: 0, count: plaintext.count + 16), length = 0
    let capacity = encrypted.count, iv = [UInt8](repeating: 32, count: 16)
    let status = plaintext.withUnsafeBytes { input in CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), key, 16, iv, input.baseAddress, plaintext.count, &encrypted, capacity, &length) }
    try check(status == kCCSuccess); return Data("v10".utf8) + Data(encrypted.prefix(length))
}
private func execute(_ db: OpaquePointer, _ sql: String) throws { try check(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "Fixture SQL failed") }
func browserSQLite() async throws {
    let root = temp(); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("cookies.sqlite"); var handle: OpaquePointer?
    try check(sqlite3_open(file.path, &handle) == SQLITE_OK); let db = handle!; defer { sqlite3_close(db) }
    try execute(db, "CREATE TABLE moz_cookies(host TEXT,name TEXT,path TEXT,isSecure INTEGER,expiry INTEGER,value TEXT,originAttributes TEXT); INSERT INTO moz_cookies VALUES('.pinterest.com','_pinterest_sess','/',1,4000000000,'fixture',''),('.other.test','secret','/',1,4000000000,'do-not-read',''),('.pinterest.com','container','/',1,4000000000,'skip','userContextId=2')")
    let before = try Data(contentsOf: file), profile = BrowserProfile(browser: "Firefox", name: "Fixture", directory: root, firefox: true)
    let reader = BrowserCookieReader(key: { _ in throw CorkError("Keychain must not be used for Firefox") })
    try await rejects { _ = try await reader.read(profile, approved: false) }
    let cookies = try await reader.read(profile, approved: true); try check(cookies.count == 1 && cookies[0].name == "_pinterest_sess" && cookies[0].value == "fixture")
    try check(try Data(contentsOf: file) == before)
    let password = Data("fixture-key".utf8), encrypted = try encrypt("session", password: password, host: ".pinterest.com", version: 24)
    try check(try ChromeCookieCrypto.decrypt(encrypted, password: password, host: ".pinterest.com", databaseVersion: 24) == "session")
    try await rejects { _ = try ChromeCookieCrypto.decrypt(encrypted, password: password, host: ".other.test", databaseVersion: 24) }
    try await rejects { _ = try ChromeCookieCrypto.decrypt(Data("v20fake".utf8), password: password, host: ".pinterest.com", databaseVersion: 24) }
    let legacy = try encrypt("legacy", password: password, host: ".pinterest.com", version: 23)
    try check(try ChromeCookieCrypto.decrypt(legacy, password: password, host: ".pinterest.com", databaseVersion: 23) == "legacy")
    var chromeHandle: OpaquePointer?; try check(sqlite3_open(root.appendingPathComponent("Cookies").path, &chromeHandle) == SQLITE_OK); let chrome = chromeHandle!; defer { sqlite3_close(chrome) }
    try execute(chrome, "CREATE TABLE cookies(host_key TEXT,name TEXT,path TEXT,is_secure INTEGER,expires_utc INTEGER,value TEXT,encrypted_value BLOB,top_frame_site_key TEXT); CREATE TABLE meta(key TEXT,value TEXT); INSERT INTO meta VALUES('version','24')")
    let hex = encrypted.map { String(format: "%02x", $0) }.joined()
    try execute(chrome, "INSERT INTO cookies VALUES('.pinterest.com','_pinterest_sess','/',1,0,'',X'\(hex)',''),('.other.test','secret','/',1,0,'',X'000000','')")
    let chromeProfile = BrowserProfile(browser: "Chrome", name: "Fixture", directory: root, service: "test", account: "test"), chromeReader = BrowserCookieReader(key: { _ in password })
    try check(try await chromeReader.read(chromeProfile, approved: true).first?.value == "session")
    let denied = BrowserCookieReader(key: { _ in throw CorkError("Denied fixture") }); try await rejects { _ = try await denied.read(chromeProfile, approved: true) }
}
