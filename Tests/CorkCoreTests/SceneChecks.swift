import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CorkCore

private func sceneCollection() -> PhotoCollection {
    var collection = PhotoCollection()
    collection.themes = [.init(id: "golden-hour", name: "Honey & grain", description: "Warm paper, wood and olive")]
    for i in 0..<40 {
        collection.photos.append(.init(id: "s\(i)", assetFile: "s\(i).png", title: "Metadata", description: "Metadata",
            sourceURL: "https://www.pinterest.com/pin/\(i)/", sourceBoard: "board-\(i % 5)", tags: ["subject-\(i % 5)"],
            palette: i < 25 ? ["#85633C", "#C5A36B", "#EAD9B5"] : ["#0929FF", "#00A0FF", "#C0B0F0"],
            themeIDs: ["golden-hour"], imageWidth: i % 3 == 0 ? 1400 : 700, imageHeight: 1000))
    }
    return collection
}
private func sceneWallpapers() -> WallpaperCollection {
    var library = WallpaperCollection()
    library.wallpapers = [
        .init(id: "large-warm", assetFile: "large.jpg", title: "Large warm wallpaper", sourceURL: "https://www.pinterest.com/pin/100/", sourceBoard: "Test", palette: ["#85633C", "#EAD9B5"], themeIDs: ["golden-hour"], width: 3840, height: 2400),
        .init(id: "small-warm", assetFile: "small.jpg", title: "Too small", sourceURL: "https://www.pinterest.com/pin/101/", sourceBoard: "Test", palette: ["#85633C", "#EAD9B5"], themeIDs: ["golden-hour"], width: 1920, height: 1080)
    ]
    return library
}
@MainActor func sceneColoursRankCompatibleImagesAndChooseNativeWallpaper() throws {
    let palette = ScenePalettes.all.first { $0.id == "golden-hour" } ?? ScenePalettes.all[0]
    try expect(ColourMatch.score(["#85633C"], against: palette.colours) > ColourMatch.score(["#0929FF"], against: palette.colours) + 0.25)
    try expect(ColourMatch.score(["invalid"], against: palette.colours) == 0)
    let collection = sceneCollection(), display = DisplayInfo(id: 1, name: "Retina", width: 1512, height: 982, scale: 2)
    let result = try WallRotation.roll(Board(), collection: collection, display: display, seed: 42, wallpapers: sceneWallpapers(), paletteID: "golden-hour")
    try expect(result.rotation?.scheme == palette && result.rotation?.wallpaperID == "large-warm")
    try expect(result.desktop.wallpaper.assetFile == "large.jpg" && result.desktop.wallpaper.pixelWidth == 3840)
    try expect(result.items.allSatisfy { ColourMatch.score($0.colours ?? [], against: palette.colours) > 0.8 })
    try expect(Set(result.items.compactMap(\.sourceURL)).count == result.items.count)
    var manual = Board(); var options = SceneOptions(); options.matchWallpaper = false; manual.desktop.scenes = options
    let unchanged = try WallRotation.roll(manual, collection: collection, display: display, seed: 42, wallpapers: sceneWallpapers())
    try expect(unchanged.desktop.wallpaper == manual.desktop.wallpaper)
    try expectThrows { try WallRotation.roll(Board(), collection: collection, display: display, seed: 42, paletteID: "missing") }
}
@MainActor func fillEmptyPreservesEveryExistingItemAndKeptImagesSurviveRoll() throws {
    let collection = sceneCollection(), display = DisplayInfo(id: 1, name: "Retina", width: 1512, height: 982, scale: 2)
    var board = Board()
    var kept = PrintItem(assetFile: collection.photos[0].assetFile, title: "My caption", x: 70, y: 300, width: 220, height: 290, rotation: -4, displayID: 1, sourceURL: collection.photos[0].sourceURL)
    kept.keepInPlace = true; kept.colours = collection.photos[0].palette
    let photo = PrintItem(assetFile: collection.photos[1].assetFile, title: "", x: 850, y: 400, width: 210, height: 300, rotation: 3, displayID: 1)
    let note = PrintItem(assetFile: "", title: "Keep", style: .sticky, x: 400, y: 530, width: 210, height: 160, displayID: 1, kind: .note, text: "Do not move")
    let other = PrintItem(assetFile: "other.png", title: "Other screen", displayID: 99)
    board.items = [kept, photo, note, other]
    let filled = try WallRotation.fillEmpty(board, collection: collection, display: display, seed: 15, wallpapers: sceneWallpapers())
    try expect(Array(filled.items.prefix(board.items.count)) == board.items && filled.items.count > board.items.count)
    let originalIDs = Set(board.items.map(\.id))
    for image in filled.items where !originalIDs.contains(image.id) {
        let a = image.rotation * .pi / 180, w = abs(cos(a)) * image.width + abs(sin(a)) * image.height, h = abs(sin(a)) * image.width + abs(cos(a)) * image.height
        let rect = CGRect(x: image.x + (image.width - w) / 2, y: image.y + (image.height - h) / 2, width: w, height: h)
        for old in [kept, photo, note] {
            let angle = old.rotation * .pi / 180, ow = abs(cos(angle)) * old.width + abs(sin(angle)) * old.height, oh = abs(sin(angle)) * old.width + abs(cos(angle)) * old.height
            try expect(!rect.intersects(CGRect(x: old.x + (old.width - ow) / 2, y: old.y + (old.height - oh) / 2, width: ow, height: oh)))
        }
    }
    let rolled = try WallRotation.roll(board, collection: collection, display: display, seed: 12)
    try expect(rolled.items.contains(kept) && rolled.items.contains(note) && rolled.items.contains(other))
    for layout in LayoutKind.allCases { try expect(try BoardLayout.arrange(board, display: display, layout: layout).items.contains(kept)) }
    var history = BoardHistory(); history.record(board); try expect(history.undo(current: filled) == board)
    try expect(try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(filled)) == filled)
}
@MainActor func hidingWidgetsMakesTheirAreaAvailableToFill() throws {
    let display = DisplayInfo(id: 1, name: "Screen", width: 1512, height: 982)
    var board = Board()
    board.items = [
        PrintItem(assetFile: "right.png", title: "", x: display.safeX + display.safeWidth * 0.4, y: display.safeY,
            width: display.safeWidth * 0.6, height: display.safeHeight, displayID: 1),
        PrintItem(assetFile: "bottom.png", title: "", x: display.safeX, y: display.safeY + display.safeHeight * 0.2,
            width: display.safeWidth * 0.4, height: display.safeHeight * 0.8, displayID: 1)
    ]
    try expectThrows { try WallRotation.fillEmpty(board, collection: sceneCollection(), display: display, seed: 2) }
    board.desktop.hideWidgets = true
    let result = try WallRotation.fillEmpty(board, collection: sceneCollection(), display: display, seed: 2)
    try expect(result.items.count > board.items.count && Array(result.items.prefix(2)) == board.items)
    let region = CGRect(x: display.safeX, y: display.safeY, width: display.safeWidth * 0.4, height: display.safeHeight * 0.2)
    try expect(result.items.dropFirst(2).allSatisfy { region.contains(CGPoint(x: $0.x + $0.width / 2, y: $0.y + $0.height / 2)) })
}
@MainActor func scenePreferencesAndRandomizeShortcutMigrateAndPersist() throws {
    var old = Board(); old.items = [PrintItem(assetFile: "old.png", title: "Keep")]
    let restored = try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(old))
    try expect(restored.items == old.items && !restored.desktop.widgetsHidden && restored.desktop.sceneOptions.matchColours)
    try expect(restored.desktop.desktopControls.wallShortcut.shortcut.display == "⌃⌥⌘R")
    var changed = restored; changed.desktop.hideWidgets = true
    var options = SceneOptions(); options.paletteID = "print-shop"; options.matchWallpaper = false; changed.desktop.scenes = options
    var controls = changed.desktop.desktopControls; var randomize = controls.wallShortcut
    randomize.shortcut = MinimizeShortcut(keyCode: 40, modifiers: 7, keyLabel: "K"); controls.randomize = randomize; changed.desktop.controls = controls
    try changed.validate(); try expect(try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(changed)) == changed)
    try CorkTools.validate(name: "cork_fill_empty", arguments: ["colour_aware": .bool(true)])
    try CorkTools.validate(name: "cork_set_desktop", arguments: ["hide_widgets": .bool(true), "match_wallpaper": .bool(true)])
    try expectThrows { try CorkTools.validate(name: "cork_fill_empty", arguments: ["colour_aware": .string("yes")]) }
    try expectThrows { try CorkTools.validate(name: "cork_update_items", arguments: ["items": .array([.object(["id": .string(old.items[0].id.uuidString), "keep_in_place": .string("yes")])])]) }
}
@MainActor func colourAnalysisFindsRealImageColoursDeterministically() throws {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
        let red = CGColor(colorSpace: space, components: [1, 0, 0, 1]), let blue = CGColor(colorSpace: space, components: [0, 0, 1, 1]) else { throw CheckFailure(description: "Fixture context") }
    context.setFillColor(red); context.fill(CGRect(x: 0, y: 0, width: 48, height: 64))
    context.setFillColor(blue); context.fill(CGRect(x: 48, y: 0, width: 16, height: 64))
    guard let image = context.makeImage() else { throw CheckFailure(description: "Fixture image") }
    let colours = try PaletteAnalysis.colours(image: image)
    try expect(colours == PaletteAnalysis.colours(image: image))
    try expect(colours.contains("#FF0000") && colours.contains("#0000FF"))
    try expect(colours.first == "#FF0000")
    try expect(!sceneWallpapers().wallpapers[1].supports(DisplayInfo(id: 1, name: "Retina", width: 1512, height: 982, scale: 2)))
}
@MainActor func wallpaperCollectionOwnsLargeMediaAndRollsBackFailedImports() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkWallpapers-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("large.png"), manifest = root.appendingPathComponent("import.json")
    guard let context = CGContext(data: nil, width: 3200, height: 2200, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CheckFailure(description: "Large fixture") }
    CGImageDestinationAddImage(destination, image, nil); try expect(CGImageDestinationFinalize(destination))
    let repository = BoardRepository(root: root.appendingPathComponent("Data"))
    func entry(_ id: String, _ path: String, title: String = "Wallpaper") -> [String: Any] {
        ["id": id, "path": path, "title": title, "sourceURL": "https://www.pinterest.com/pin/\(id)/", "sourceBoard": "Test", "themeIDs": ["golden-hour"]]
    }
    func write(_ entries: [[String: Any]]) throws { try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "wallpapers": entries]).write(to: manifest) }
    try write([entry("100", source.path)]); let first = try await repository.importWallpapers(at: manifest.path)
    guard let wallpaper = first.wallpapers.first else { throw CheckFailure(description: "Missing import") }
    try expect(wallpaper.width == 3200 && wallpaper.height == 2200 && wallpaper.supports(DisplayInfo(id: 1, name: "Retina", width: 1512, height: 982, scale: 2)))
    let managed = repository.wallpapers.appendingPathComponent(wallpaper.assetFile)
    try FileManager.default.removeItem(at: source); try expect(FileManager.default.fileExists(atPath: managed.path))
    try write([entry("100", source.path, title: "Updated metadata")]); let updated = try await repository.importWallpapers(at: manifest.path)
    try expect(updated.wallpapers[0].assetFile == wallpaper.assetFile && updated.wallpapers[0].title == "Updated metadata")
    let files = try FileManager.default.contentsOfDirectory(atPath: repository.wallpapers.path)
    let bad = root.appendingPathComponent("bad.png"); try Data("not an image".utf8).write(to: bad)
    try write([entry("101", managed.path), entry("102", bad.path)])
    try await expectThrowsAsync { try await repository.importWallpapers(at: manifest.path) }
    try expect(try await repository.loadWallpapers().0 == updated)
    try expect(Set(try FileManager.default.contentsOfDirectory(atPath: repository.wallpapers.path)) == Set(files))
    try Data("broken".utf8).write(to: repository.root.appendingPathComponent("wallpapers.json"))
    try expect(try await repository.loadWallpapers().0 == first)
}
