import AppKit

@MainActor private final class FakeWallpaperAccess: SystemWallpaperAccess {
    var images: [UInt32: SystemWallpaperImage]
    var displayIDs: [UInt32]
    var writes = 0
    var beforeWrite: ((SystemWallpaperImage, UInt32) throws -> Void)?
    var afterWrite: (() throws -> Void)?
    init(_ images: [UInt32: SystemWallpaperImage]) { self.images = images; displayIDs = images.keys.sorted() }
    func image(for displayID: UInt32) -> SystemWallpaperImage? { images[displayID] }
    func setImage(_ image: SystemWallpaperImage, for displayID: UInt32) throws {
        try beforeWrite?(image, displayID)
        images[displayID] = image; writes += 1
        try afterWrite?()
    }
}

@main @MainActor enum WallpaperSyncChecks {
    static func check(_ condition: Bool, _ message: String = "Expectation failed") throws {
        if !condition { throw SystemWallpaperSync.failure(message) }
    }
    static func rejects(_ body: () throws -> Void) throws {
        do { try body() } catch { return }
        throw SystemWallpaperSync.failure("Expected a wallpaper failure")
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-wallpaper-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = SystemWallpaperImage(url: URL(fileURLWithPath: "/original.heic"), scaling: 2, clipping: false, fill: [0.2, 0.3, 0.4, 1])
        let other = SystemWallpaperImage(url: URL(fileURLWithPath: "/other.jpg"), scaling: nil, clipping: nil, fill: nil)
        let a = URL(fileURLWithPath: "/cork-a.jpg"), b = URL(fileURLWithPath: "/cork-b.jpg")
        var passed = 0
        func run(_ name: String, _ body: (URL) throws -> Void) throws {
            try body(root.appendingPathComponent("\(passed).json")); passed += 1
            print("PASS", name)
        }
        try run("Native image changes once and preserves exact original options") { file in
            let access = FakeWallpaperAccess([1: original]), sync = SystemWallpaperSync(journalURL: file, access: access)
            try sync.apply(a, displays: [1]); try sync.apply(a, displays: [1])
            try check(access.writes == 1 && sync.synchronized)
            try sync.apply(b, displays: [1]); try sync.restore()
            try check(access.images[1] == original && !FileManager.default.fileExists(atPath: file.path))
        }
        try run("Original is journaled before the first native change") { file in
            let access = FakeWallpaperAccess([1: original]), sync = SystemWallpaperSync(journalURL: file, access: access)
            access.beforeWrite = { _, _ in
                let text = try String(contentsOf: file, encoding: .utf8)
                try check(text.contains("original.heic") && text.contains("cork-a.jpg") && text.contains("pending"))
                let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
                try check(mode == 0o600)
            }
            try sync.apply(a, displays: [1])
        }
        try run("Restart retains the real original across subsequent rolls") { file in
            let access = FakeWallpaperAccess([1: original])
            try SystemWallpaperSync(journalURL: file, access: access).apply(a, displays: [1])
            let reopened = SystemWallpaperSync(journalURL: file, access: access)
            try reopened.apply(b, displays: [1]); try reopened.restore()
            try check(access.images[1] == original)
        }
        try run("An external wallpaper change wins on quit") { file in
            let access = FakeWallpaperAccess([1: original]), sync = SystemWallpaperSync(journalURL: file, access: access)
            try sync.apply(a, displays: [1]); access.images[1] = other
            try sync.restore(); try check(access.images[1] == other && access.writes == 1)
        }
        try run("An external change becomes the next restoration target") { file in
            let access = FakeWallpaperAccess([1: original]), sync = SystemWallpaperSync(journalURL: file, access: access)
            try sync.apply(a, displays: [1]); access.images[1] = other
            try sync.apply(b, displays: [1]); try sync.restore(); try check(access.images[1] == other)
        }
        try run("Crash after native change recovers the pending image") { file in
            let access = FakeWallpaperAccess([1: original])
            access.afterWrite = { throw SystemWallpaperSync.failure("Interrupted after native write") }
            try rejects { try SystemWallpaperSync(journalURL: file, access: access).apply(a, displays: [1]) }
            try check(access.images[1] == .cover(a)); access.afterWrite = nil
            try SystemWallpaperSync(journalURL: file, access: access).restore()
            try check(access.images[1] == original)
        }
        try run("A failed native update preserves the original") { file in
            let access = FakeWallpaperAccess([1: original]), sync = SystemWallpaperSync(journalURL: file, access: access)
            access.beforeWrite = { _, _ in throw SystemWallpaperSync.failure("Native setter failed") }
            try rejects { try sync.apply(a, displays: [1]) }
            try check(access.images[1] == original && !sync.synchronized)
            access.beforeWrite = nil; try sync.restore(); try check(access.writes == 0)
        }
        try run("A failed restore retains recovery data for the next launch") { file in
            let access = FakeWallpaperAccess([1: original]), sync = SystemWallpaperSync(journalURL: file, access: access)
            try sync.apply(a, displays: [1])
            access.beforeWrite = { _, _ in throw SystemWallpaperSync.failure("Restore temporarily failed") }
            try rejects { try sync.restore() }; try check(FileManager.default.fileExists(atPath: file.path))
            access.beforeWrite = nil; try SystemWallpaperSync(journalURL: file, access: access).restore()
            try check(access.images[1] == original)
        }
        try run("Disconnected displays retain their independent originals") { file in
            let access = FakeWallpaperAccess([1: original, 2: other]), sync = SystemWallpaperSync(journalURL: file, access: access)
            try sync.apply(a, displays: [1, 2]); access.displayIDs = [1]
            try sync.restore(); try check(access.images[1] == original && access.images[2] == .cover(a))
            access.displayIDs = [1, 2]
            try SystemWallpaperSync(journalURL: file, access: access).restore(); try check(access.images[2] == other)
        }
        try run("Invalid or unwritable recovery storage prevents native mutation") { file in
            try Data("corrupt".utf8).write(to: file)
            let access = FakeWallpaperAccess([1: original])
            try rejects { try SystemWallpaperSync(journalURL: file, access: access).apply(a, displays: [1]) }
            let blocked = file.appendingPathComponent("journal.json")
            try rejects { try SystemWallpaperSync(journalURL: blocked, access: access).apply(a, displays: [1]) }
            try check(access.writes == 0 && access.images[1] == original)
        }
        try run("Repeated rolls keep a bounded recovery record") { file in
            let access = FakeWallpaperAccess([1: original]), sync = SystemWallpaperSync(journalURL: file, access: access)
            for index in 0..<12 { try sync.apply(index.isMultiple(of: 2) ? a : b, displays: [1]) }
            try check(try Data(contentsOf: file).count < 2048)
            try sync.restore(); try check(access.images[1] == original)
        }
        print("\(passed)/\(passed) wallpaper synchronization checks passed")
    }
}
