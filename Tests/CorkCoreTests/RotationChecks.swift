import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CorkCore

private func rotationFixture() -> PhotoCollection {
    var collection = PhotoCollection()
    collection.themes = [CollectionTheme(id: "green", name: "Open air", description: "Green and blue landscapes"),
                         CollectionTheme(id: "ink", name: "Ink and paper", description: "Monochrome drawings")]
    for index in 0..<32 {
        collection.photos.append(CollectionPhoto(id: "photo-\(index)", assetFile: "photo-\(index).png", title: "Photo \(index)", description: "Curated fixture",
            sourceURL: "https://www.pinterest.com/pin/\(1000 + index)/", sourceBoard: "test-board", tags: ["quiet", "landscape"],
            palette: ["#335544", "#BBCCDD"], themeIDs: [index < 16 ? "green" : "ink"], imageWidth: 800, imageHeight: index % 3 == 0 ? 600 : 1000))
    }
    return collection
}

@MainActor func rotationIsCoherentMixedAndCaptionFree() throws {
    let collection = rotationFixture(), display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    let result = try WallRotation.roll(Board(), collection: collection, display: display, themeID: "green", seed: 42)
    try expect((6...16).contains(result.items.count) && result.rotation?.themeID == "green")
    try expect(Set(result.items.map(\.style)) == Set(PrintStyle.imageStyles))
    try expect(result.items.allSatisfy { $0.title.isEmpty })
    try expect(Set(result.items.map(\.assetFile)).count == result.items.count)
    try expect(result.items.allSatisfy { item in collection.photos.contains { $0.assetFile == item.assetFile && $0.themeIDs.contains("green") } })
    for item in result.items {
        let radians = abs(item.rotation) * .pi / 180
        let width = cos(radians) * item.width + sin(radians) * item.height
        let height = sin(radians) * item.width + cos(radians) * item.height
        let x = item.x + item.width / 2, y = item.y + item.height / 2
        try expect(x - width / 2 >= display.safeX && x + width / 2 <= display.safeX + display.safeWidth)
        try expect(y - height / 2 >= display.safeY && y + height / 2 <= display.safeY + display.safeHeight)
        try expect(x - width / 2 >= display.safeX + display.safeWidth * 0.4 || y - height / 2 >= display.safeY + display.safeHeight * 0.2)
    }
    let repeated = try WallRotation.roll(Board(), collection: collection, display: display, themeID: "green", seed: 42)
    try expect(result.items.map(\.assetFile) == repeated.items.map(\.assetFile))
    try expect(result.items.map(\.x) == repeated.items.map(\.x) && result.items.map(\.style) == repeated.items.map(\.style))
    var small = collection; small.photos = Array(collection.photos.prefix(8))
    for seed in UInt64(0)...12 {
        let eight = try WallRotation.roll(Board(), collection: small, display: display, themeID: "green", seed: seed)
        try expect((6...8).contains(eight.items.count) && Set(eight.items.map(\.style)) == Set(PrintStyle.imageStyles))
    }
}

@MainActor func rotationPreservesNotesOtherDisplaysAndUndo() throws {
    let collection = rotationFixture(), display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    var board = Board()
    let note = PrintItem(assetFile: "", title: "Keep", style: .sticky, x: 40, y: 410, width: 220, height: 150, displayID: 1, kind: .note, text: "Stay here")
    let other = PrintItem(assetFile: "other.png", title: "Other display", displayID: 99)
    board.items = [note, other]
    board.desktop.rotationTheme = "green"
    let result = try WallRotation.roll(board, collection: collection, display: display, themeID: "green", seed: 7)
    try expect(result.items.first(where: { $0.id == note.id }) == note)
    try expect(result.items.first(where: { $0.id == other.id }) == other)
    var history = BoardHistory(); history.record(board)
    try expect(history.undo(current: result) == board)
    try expect(history.redo(current: board) == result)
    let restored = try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(result))
    try expect(restored == result && restored.desktop.rotationTheme == "green")
    try expectThrows { try WallRotation.roll(board, collection: collection, display: display, themeID: "missing", seed: 1) }
}

@MainActor func rotationAvoidsPreviousMoodAndAvailablePhotos() throws {
    let collection = rotationFixture(), display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    let first = try WallRotation.roll(Board(), collection: collection, display: display, themeID: "green", seed: 1)
    let second = try WallRotation.roll(first, collection: collection, display: display, seed: 2)
    try expect(second.rotation?.themeID == "ink")
    let third = try WallRotation.roll(first, collection: collection, display: display, themeID: "green", seed: 3)
    let firstSources = Set(first.items.compactMap(\.sourceURL)), newSources = Set(third.items.compactMap(\.sourceURL)).subtracting(firstSources)
    try expect(newSources.count >= min(3, 16 - firstSources.count)) // Freshness is preferred without sacrificing the fit.
    var invalid = collection; invalid.photos[0].palette = ["invalid"]
    try expectThrows { try invalid.validate() }
    invalid = collection; invalid.photos[0].assetFile = "../bad.png"
    try expectThrows { try invalid.validate() }
    try CorkTools.validate(name: "cork_roll_wall", arguments: ["seed": .number(42)])
    try expectThrows { try CorkTools.validate(name: "cork_roll_wall", arguments: ["seed": .number(1.2)]) }
}

@MainActor func collectionImportOwnsMediaAndMergesMetadataAtomically() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkCollection-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let imageURL = root.appendingPathComponent("source.png")
    guard let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CheckFailure(description: "Fixture image failed") }
    CGImageDestinationAddImage(destination, image, nil); try expect(CGImageDestinationFinalize(destination))
    let repository = BoardRepository(root: root.appendingPathComponent("AppData"))
    let manifestURL = root.appendingPathComponent("import.json")
    let themes: [[String: Any]] = [["id": "green", "name": "Open air", "description": "Green landscapes"]]
    func entry(_ id: String, path: String) -> [String: Any] {
        ["id": id, "path": path, "title": "A photo", "description": "Metadata stays separate from captions", "sourceURL": "https://www.pinterest.com/pin/\(id)/",
         "sourceBoard": "nature", "tags": ["quiet", "green"], "palette": ["#335544"], "themeIDs": ["green"]]
    }
    func manifest(_ photos: [[String: Any]]) throws {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "themes": themes, "photos": photos]).write(to: manifestURL)
    }
    try manifest([entry("100", path: imageURL.path)])
    let first = try await repository.importCollection(at: manifestURL.path)
    let file = first.photos[0].assetFile
    try FileManager.default.removeItem(at: imageURL)
    let merged = try await repository.importCollection(at: manifestURL.path)
    try expect(merged == first && FileManager.default.fileExists(atPath: repository.assets.appendingPathComponent(file).path))
    let bad = root.appendingPathComponent("not-an-image.png"); try Data("not an image".utf8).write(to: bad)
    let originalFiles = try FileManager.default.contentsOfDirectory(atPath: repository.assets.path)
    try manifest([entry("200", path: repository.assets.appendingPathComponent(file).path), entry("201", path: bad.path)])
    try await expectThrowsAsync { try await repository.importCollection(at: manifestURL.path) }
    try expect(try await repository.loadCollection().0 == first)
    try expect(try FileManager.default.contentsOfDirectory(atPath: repository.assets.path) == originalFiles)
    let catalog = repository.root.appendingPathComponent("collection.json")
    try Data("corrupted".utf8).write(to: catalog)
    let recovered = try await repository.loadCollection()
    try expect(recovered.0 == first && recovered.1 != nil)
}
