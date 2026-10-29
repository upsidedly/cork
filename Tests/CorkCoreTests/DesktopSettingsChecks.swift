import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CorkCore

@MainActor func legacyBoardMigrationPreservesTheWall() async throws {
    var original = Board()
    original.items = [PrintItem(assetFile: "photo.png", title: "Existing print", x: 330, y: 240, rotation: -4,
                                sourceURL: "https://www.pinterest.com/pin/123/")]
    original.revision = 17
    var object = try JSONValue.encode(original).object ?? [:]
    object.removeValue(forKey: "desktop")
    let legacyData = try JSONValue.object(object).data()
    let migrated = try JSONDecoder().decode(Board.self, from: legacyData)
    try migrated.validate()
    try expect(migrated.items == original.items && migrated.revision == 17)
    try expect(migrated.desktop.hideDesktopFiles && migrated.desktop.wallpaper.kind == .system)

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkMigration-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try legacyData.write(to: root.appendingPathComponent("board.json"))
    let repository = BoardRepository(root: root)
    let loaded = try await repository.load().0
    try expect(loaded == migrated)
    try await repository.save(loaded)
    try expect(try await repository.load().0 == migrated)
    let backup = try JSONDecoder().decode(Board.self, from: Data(contentsOf: root.appendingPathComponent("board.previous.json")))
    try expect(backup.items == original.items)
}

@MainActor func wallpaperSettingsSurviveSaveAndReload() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkSettings-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = BoardRepository(root: root)
    var board = Board()
    board.items = [PrintItem(assetFile: "keep.png", title: "Keep this")]
    board.desktop.hideDesktopFiles = false; board.desktop.defaultImageStyle = .frame
    board.desktop.wallpaper.kind = .video; board.desktop.wallpaper.assetFile = "clip.mp4"
    board.desktop.wallpaper.posterFile = "preview.png"; board.desktop.wallpaper.sourceName = "Original video.mp4"
    board.desktop.wallpaper.paused = true
    try await repository.save(board)
    try expect(try await repository.load().0 == board)
    try expect(board.items.first?.assetFile == "keep.png")
    var broken = board; broken.desktop.wallpaper.assetFile = "../clip.mp4"
    try expectThrows { try broken.validate() }
    broken = board; broken.desktop.wallpaper.posterFile = nil
    try expectThrows { try broken.validate() }
    broken = board; broken.desktop.defaultImageStyle = .sticky
    try expectThrows { try broken.validate() }
    broken = board; broken.desktop.wallpaper.kind = .system
    try expectThrows { try broken.validate() }
}

@MainActor func wallpaperImportOwnsItsCopy() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkWallpaper-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("chosen.png")
    guard let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CheckFailure(description: "Could not make the image fixture")
    }
    CGImageDestinationAddImage(destination, image, nil)
    try expect(CGImageDestinationFinalize(destination))
    let repository = BoardRepository(root: root.appendingPathComponent("AppData"))
    let wallpaper = try await repository.importWallpaperImage(at: source.path)
    try wallpaper.validate()
    try expect(wallpaper.kind == .image && wallpaper.sourceName == "chosen.png")
    guard let filename = wallpaper.assetFile else { throw CheckFailure(description: "Missing wallpaper copy") }
    let copy = repository.wallpapers.appendingPathComponent(filename)
    try expect(FileManager.default.fileExists(atPath: source.path))
    try FileManager.default.removeItem(at: source)
    try expect(FileManager.default.fileExists(atPath: copy.path))
    try expect(!FileManager.default.fileExists(atPath: repository.assets.appendingPathComponent(filename).path))
    let empty = root.appendingPathComponent("empty.mp4"); try Data().write(to: empty)
    try await expectThrowsAsync { try await repository.importWallpaperVideo(at: empty.path) }
    try await expectThrowsAsync { try await repository.importWallpaperVideo(at: "relative.mp4") }
}

@MainActor func desktopToolSchemasRejectAmbiguousInputs() throws {
    try CorkTools.validate(name: "cork_set_desktop", arguments: ["hide_files": .bool(true), "wallpaper_kind": .string("video"), "path": .string("/tmp/clip.mp4")])
    try CorkTools.validate(name: "cork_set_login_item", arguments: ["enabled": .bool(true)])
    try expectThrows { try CorkTools.validate(name: "cork_set_desktop", arguments: ["hide_files": .string("true")]) }
    try expectThrows { try CorkTools.validate(name: "cork_set_desktop", arguments: ["wallpaper_kind": .string("web")]) }
    try expectThrows { try CorkTools.validate(name: "cork_set_desktop", arguments: ["default_image_style": .string("sticky")]) }
    try expectThrows { try CorkTools.validate(name: "cork_set_login_item", arguments: [:]) }
}
