import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CorkCore

private func colourImage(_ bands: [(ColourFamily, Int)]) throws -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: 64, height: 64,
        bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CheckFailure(description: "Colour fixture") }
    context.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
    var x = 0
    for (family, width) in bands {
        let hex = UInt32(family.hex.dropFirst(), radix: 16)!
        context.setFillColor(CGColor(colorSpace: space, components: [Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255, 1])!)
        context.fill(CGRect(x: x, y: 0, width: width, height: 64)); x += width
    }
    guard let result = context.makeImage() else { throw CheckFailure(description: "Colour image") }; return result
}
private func customCollection(_ pair: [ColourFamily], accents: Bool = false) -> PhotoCollection {
    var result = PhotoCollection()
    result.themes = [.init(id: "first", name: "First", description: "First mood"), .init(id: "second", name: "Second", description: "Second mood")]
    for index in 0..<48 {
        let family = index < 20 ? pair[0] : index < 40 ? pair[1] : .green
        let profile = ImageColourProfile(coverages: accents ? [family: 0.10, .white: 0.90] : [family: 0.80, .grey: 0.20])
        result.photos.append(.init(id: "custom-\(index)", assetFile: "custom-\(index).png", title: "Metadata", description: "Photo",
            sourceURL: "https://example.com/\(index)", sourceBoard: "board-\(index % 6)", tags: [], palette: [family.hex, "#8C9296"],
            themeIDs: [index < 20 ? "first" : "second"], imageWidth: index % 3 == 0 ? 1300 : 750, imageHeight: 1000, colourProfile: profile))
    }
    return result
}
private func customBoard(_ pair: [ColourFamily], strength: ColourSelectionStrength = .strong) -> Board {
    var result = Board(), options = SceneOptions(); options.colourPair = pair.map(ColourChoice.colour); options.colourStrength = strength
    result.desktop.scenes = options; return result
}

@MainActor func colourClassificationMeasuresStrongAndWeakPixelCoverage() throws {
    let image = try colourImage([(.blue, 48), (.yellow, 10), (.violet, 6)])
    let result = try PaletteAnalysis.profile(image: image)
    try expect(result.sampleCount == 4096 && result.coverage(.blue) == 0.75 && result.coverage(.yellow) == 0.15625 && result.coverage(.violet) == 0.09375)
    try expect(result.colours.first { $0.family == .blue }?.strength == .strong)
    try expect(result.colours.first { $0.family == .yellow }?.strength == .weak)
    try expect(result == PaletteAnalysis.profile(image: image))
    for family in ColourFamily.allCases { try expect(try PaletteAnalysis.profile(image: colourImage([(family, 64)])).dominantFamily == family) }
    let clear = try PaletteAnalysis.profile(image: colourImage([]))
    try expect(clear.sampleCount == 0 && clear.colours.isEmpty)
    var invalid = result; invalid.colours[0].coverage = .nan
    try expectThrows { try invalid.validate() }
}

@MainActor func arbitraryColourPairsAndStrengthMigrateValidateAndPersist() throws {
    let old = try JSONDecoder().decode(SceneOptions.self, from: Data(#"{"matchColours":true,"matchWallpaper":true}"#.utf8))
    try expect(old.colourPair == nil && old.selectedStrength == .strong)
    for (index, first) in ColourFamily.allCases.enumerated() {
        for second in ColourFamily.allCases.dropFirst(index + 1) {
            let scheme = try ScenePalettes.pair([first, second]); try scheme.validate()
            try expect(try JSONDecoder().decode(ColourScheme.self, from: JSONEncoder().encode(scheme)) == scheme)
        }
    }
    try expectThrows { try ScenePalettes.pair([.blue, .blue]) }
    var board = customBoard([.red, .violet], strength: .strongAndAccents); try board.validate()
    try expect(try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board)) == board)
    var options = board.desktop.sceneOptions; options.paletteID = "blue-hour"; board.desktop.scenes = options
    try expectThrows { try board.validate() }
    try CorkTools.validate(name: "cork_set_desktop", arguments: ["colour_pair": .array([.string("red"), .string("violet")]), "colour_strength": .string("strong_and_accents")])
    for pair in [["blue"], ["blue", "yellow", "red"], ["blue", "unknown"]] {
        try expectThrows { try CorkTools.validate(name: "cork_set_desktop", arguments: ["colour_pair": .array(pair.map(JSONValue.string))]) }
    }
}

@MainActor func customColoursSearchAllMoodsAndBalanceActualColourArea() throws {
    let pair: [ColourFamily] = [.red, .violet], collection = customCollection(pair)
    let display = DisplayInfo(id: 1, name: "Retina", width: 1512, height: 982, scale: 2)
    for seed in UInt64(0)..<4 {
        let result = try WallRotation.roll(customBoard(pair), collection: collection, display: display, themeID: "first", seed: seed)
        try expect(result.rotation?.scheme?.colourFamilies == pair && result.rotation?.themeName == "Red + Violet")
        var areas = [0.0, 0.0], sources: [String: Int] = [:]
        for item in result.items {
            guard let profile = item.colourProfile, let metadata = collection.photos.first(where: { $0.assetFile == item.assetFile }) else { throw CheckFailure(description: "Missing classification") }
            try expect(profile.matches(pair, strength: .strong) && item.title.isEmpty)
            for group in 0..<2 { areas[group] += item.width * item.height * profile.coverage(pair[group]) }
            sources[metadata.sourceBoard, default: 0] += 1
        }
        try expect(min(areas[0], areas[1]) / (areas[0] + areas[1]) >= 0.25 && sources.count >= 3)
        try expect(sources.values.allSatisfy { $0 <= Int(ceil(Double(result.items.count) * 0.4)) })
    }
    let weak = customCollection(pair, accents: true)
    try expectThrows { try WallRotation.roll(customBoard(pair), collection: weak, display: display, seed: 1) }
    try expect(try WallRotation.roll(customBoard(pair, strength: .strongAndAccents), collection: weak, display: display, seed: 1).items.count >= 6)
    // White paper cannot excuse a strongly green subject in a blue/white scene.
    try expect(!ImageColourProfile(coverages: [.white: 0.75, .green: 0.25]).matches([.blue, .white], strength: .strong))
    try expect(ImageColourProfile(coverages: [.white: 0.7, .blue: 0.3]).matches([.blue, .white], strength: .strong))
}

@MainActor func customColourFillPreservesAnchorsNotesAndUndo() throws {
    let pair: [ColourFamily] = [.blue, .yellow], collection = customCollection(pair)
    var board = customBoard(pair)
    var image = PrintItem(assetFile: collection.photos[0].assetFile, title: "Keep", x: 60, y: 300, width: 300, height: 400,
        displayID: 1, sourceURL: collection.photos[0].sourceURL)
    image.colourProfile = collection.photos[0].colourProfile; image.keepInPlace = true
    let note = PrintItem(assetFile: "", title: "Note", style: .sticky, x: 500, y: 500, width: 180, height: 160, displayID: 1, kind: .note, text: "Preserve")
    board.items = [image, note]
    let result = try WallRotation.fillEmpty(board, collection: collection, display: .init(id: 1, name: "Screen", width: 1512, height: 982), seed: 42)
    try expect(Array(result.items.prefix(2)) == board.items && result.items.count > 2)
    var history = BoardHistory(); history.record(board); try expect(history.undo(current: result) == board)
    try expect(try WallRotation.fillEmpty(board, collection: collection, display: .init(id: 1, name: "Screen", width: 1512, height: 982), seed: 42,
        maximumNewPhotos: 0, allowNoNewPhotos: true) == board)
}

@MainActor func customWallpaperMatchingUsesMeasuredFamiliesAndNativeDimensions() throws {
    let pair: [ColourFamily] = [.blue, .yellow]
    var backgrounds = WallpaperCollection()
    for (id, family, width) in [("wrong-pink", ColourFamily.pink, 3840), ("blue", .blue, 3840), ("too-small", .yellow, 1000)] {
        backgrounds.wallpapers.append(.init(id: id, assetFile: id + ".jpg", title: id, sourceURL: "https://example.com/" + id,
            sourceBoard: "wallpapers", palette: [ColourFamily.blue.hex, ColourFamily.yellow.hex], themeIDs: [], width: Double(width), height: 2400,
            colourProfile: ImageColourProfile(coverages: [family: 0.8, .grey: 0.2])))
    }
    let result = try WallRotation.roll(customBoard(pair), collection: customCollection(pair), display: .init(id: 1, name: "Retina", width: 1512, height: 982, scale: 2), seed: 42, wallpapers: backgrounds)
    try expect(result.rotation?.wallpaperID == "blue" && result.rotation?.wallpaperMatched == true)
    backgrounds.wallpapers.removeAll { $0.id != "wrong-pink" }
    backgrounds.wallpapers.append(.init(id: "dark-blue", assetFile: "dark-blue.jpg", title: "Quiet blue", sourceURL: "https://example.com/dark",
        sourceBoard: "wallpapers", palette: [ColourFamily.black.hex, ColourFamily.blue.hex], themeIDs: [], width: 3840, height: 2400,
        colourProfile: ImageColourProfile(coverages: [.black: 0.80, .blue: 0.20])))
    let quiet = try WallRotation.roll(customBoard(pair), collection: customCollection(pair), display: .init(id: 1, name: "Retina", width: 1512, height: 982, scale: 2), seed: 42, wallpapers: backgrounds)
    try expect(quiet.rotation?.wallpaperID == "dark-blue" && quiet.rotation?.wallpaperMatched == true)
}

@MainActor func colourCacheBackfillsAtomicallyAndReusesAllMedia() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkColourChecks-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = BoardRepository(root: root); try await repository.prepare()
    let file = root.appendingPathComponent("source.png")
    let image = try colourImage([(.blue, 48), (.yellow, 16)])
    let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil); try expect(CGImageDestinationFinalize(destination))
    let imported = try await repository.importImage(at: file.path)
    try expect(imported.colourProfile?.coverage(.blue) == 0.75)
    var legacy = PhotoCollection(); legacy.themes = [.init(id: "legacy", name: "Legacy", description: "Keep metadata")]
    legacy.photos = [.init(id: "original", assetFile: imported.file, title: "Original", description: "Description", sourceURL: "https://example.com/original",
        sourceBoard: "Original board", tags: ["keep"], palette: ["#123456"], themeIDs: ["legacy"], imageWidth: 64, imageHeight: 64)]
    let url = root.appendingPathComponent("collection.json"), oldData = try JSONEncoder().encode(legacy)
    try oldData.write(to: url)
    let beforeFiles = try FileManager.default.contentsOfDirectory(atPath: repository.assets.path)
    let result = try await repository.classifyColours().0
    try expect(result.photos[0].colourProfile?.coverage(.blue) == 0.75)
    var stripped = result; stripped.photos[0].colourProfile = nil; try expect(stripped == legacy)
    let cached = try Data(contentsOf: url)
    try expect(try Data(contentsOf: root.appendingPathComponent("collection.previous.json")) == oldData)
    try expect(try await repository.classifyColours().0 == result)
    try expect(try Data(contentsOf: url) == cached)
    try expect(try FileManager.default.contentsOfDirectory(atPath: repository.assets.path) == beforeFiles)
    try oldData.write(to: url); try FileManager.default.removeItem(at: repository.assets.appendingPathComponent(imported.file))
    try await expectThrowsAsync { try await repository.classifyColours() }
    try expect(try Data(contentsOf: url) == oldData)
}
