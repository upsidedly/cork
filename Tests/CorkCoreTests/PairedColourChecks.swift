import Foundation
import CorkCore

private func pairedCollection() -> PhotoCollection {
    var collection = PhotoCollection()
    collection.themes = [.init(id: "blue-butter", name: "Blue & butter", description: "Two colour families across different subjects")]
    for index in 0..<48 {
        let colours = index < 20 ? ["#2C6196", "#172B45", "#A9C2D1"]
            : index < 40 ? ["#D7B54A", "#F1E6C7", "#A28A3F"] : ["#B27CBC", "#DEC5E5", "#8E79C3"]
        collection.photos.append(.init(id: "pair-\(index)", assetFile: "pair-\(index).png", title: "Source metadata", description: "Mixed subjects",
            sourceURL: "https://example.com/photos/\(index)", sourceBoard: "board-\(index % 5)", tags: [], palette: colours,
            themeIDs: ["blue-butter"], imageWidth: index % 3 == 0 ? 1400 : 750, imageHeight: 1000))
    }
    return collection
}

@MainActor func pairedPalettesMigrateValidateAndPersist() throws {
    let old = Data(##"{"id":"old","name":"Old palette","colours":["#273747","#E4E2DB"]}"##.utf8)
    try expect(try JSONDecoder().decode(ColourScheme.self, from: old).majorColours == nil)
    for palette in ScenePalettes.all { try palette.validate() }
    let pairs = ScenePalettes.all.filter { $0.majorColours != nil }
    try expect(pairs.count == 8)
    for palette in pairs {
        try expect(ScenePalettes.choose(mood: palette.id, preferred: nil, anchors: []) == palette)
        try expect(try JSONDecoder().decode(ColourScheme.self, from: JSONEncoder().encode(palette)) == palette)
    }
    try expectThrows { try ColourScheme(id: "bad", name: "Same hue", colours: ["#2C6196", "#3456A0"], majorColours: ["#2C6196", "#3456A0"]).validate() }
    try expectThrows { try ColourScheme(id: "bad", name: "Missing swatch", colours: ["#2C6196"], majorColours: ["#2C6196", "#D7B54A"]).validate() }
    let scheme = pairs[0]
    try expect(ColourMatch.majorColourIndex(["#888888", "#AAAAAA"], scheme: scheme) == nil)
    try expect(ColourMatch.majorColourIndex(["#ABAAA6", "#C9CAC7", "#3B3573"], scheme: scheme) == nil)
    try expect(ColourMatch.majorColourIndex(["#B27CBC", "#DEC5E5", "#8E79C3", "#2C6196"], scheme: scheme) == nil)
}

@MainActor func pairedRollsBalanceVisibleAreaAndKeepBoardVariety() throws {
    let collection = pairedCollection(), scheme = ScenePalettes.all.first { $0.id == "blue-butter" }!
    let display = DisplayInfo(id: 1, name: "Retina", width: 1512, height: 982, scale: 2)
    for seed in UInt64(0)..<6 {
        let result = try WallRotation.roll(Board(), collection: collection, display: display, seed: seed)
        var areas: [Int: Double] = [:], boards: [String: Int] = [:]
        for image in result.items {
            guard let group = ColourMatch.majorColourIndex(image.colours ?? [], scheme: scheme),
                  let source = collection.photos.first(where: { $0.assetFile == image.assetFile }) else { throw CheckFailure(description: "Off-palette photo") }
            areas[group, default: 0] += image.width * image.height
            boards[source.sourceBoard, default: 0] += 1
            try expect(image.title.isEmpty)
        }
        let total = areas.values.reduce(0, +)
        try expect(result.items.count >= 6 && boards.count >= 3)
        try expect(min(areas[0] ?? 0, areas[1] ?? 0) / total >= 0.25)
        try expect(boards.values.allSatisfy { $0 <= Int(ceil(Double(result.items.count) * 0.4)) })
        try expect(try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(result)) == result)
    }
    var onlyBlue = collection; onlyBlue.photos.removeAll { $0.palette.first != "#2C6196" }
    try expectThrows { try WallRotation.roll(Board(), collection: onlyBlue, display: display, seed: 1) }
    try expect(try WallRotation.roll(Board(), collection: onlyBlue, display: display, seed: 1, colourAware: false).items.count >= 6)
}

@MainActor func pairedWallpapersUseAnActualFamilyAndRejectUnrelatedPink() throws {
    let blue = ["#2C6196", "#172B45", "#A9C2D1"], yellow = ["#D7B54A", "#F1E6C7", "#A28A3F"]
    let pink = ["#B0A4D5", "#D1ACDA", "#DEC5E5"]
    let scheme = ScenePalettes.all.first { $0.id == "blue-butter" }!
    let colours = Array(repeating: blue, count: 5) + Array(repeating: yellow, count: 5)
    try expect(ColourMatch.wallpaperHueAffinity(blue, imagePalettes: colours, majorColours: scheme.majorColours) > 0.9)
    try expect(ColourMatch.wallpaperHueAffinity(yellow, imagePalettes: colours, majorColours: scheme.majorColours) > 0.9)
    try expect(ColourMatch.wallpaperHueAffinity(pink, imagePalettes: colours, majorColours: scheme.majorColours) == 0)
    try expect(ColourMatch.wallpaperHueAffinity(yellow, imagePalettes: Array(repeating: blue, count: 10), majorColours: scheme.majorColours) == 0)
    var wallpapers = WallpaperCollection()
    for (id, palette) in [("pink", pink), ("blue", blue), ("yellow", yellow)] {
        wallpapers.wallpapers.append(.init(id: id, assetFile: "\(id).jpg", title: id, sourceURL: "https://example.com/\(id)",
            sourceBoard: "wallpapers", palette: palette, themeIDs: ["blue-butter"], width: 3840, height: 2400))
    }
    for seed in UInt64(0)..<4 {
        let result = try WallRotation.roll(Board(), collection: pairedCollection(), display: .init(id: 1, name: "Retina", width: 1512, height: 982, scale: 2), seed: seed, wallpapers: wallpapers)
        try expect(["blue", "yellow"].contains(result.rotation?.wallpaperID ?? "") && result.rotation?.wallpaperMatched == true)
    }
}

@MainActor func pairedFillBalancesAroundKeptImagesWithoutMovingThem() throws {
    let collection = pairedCollection(), scheme = ScenePalettes.all.first { $0.id == "blue-butter" }!
    var board = Board()
    var kept = PrintItem(assetFile: collection.photos[0].assetFile, title: "Keep", x: 45, y: 300, width: 380, height: 500,
        displayID: 1, sourceURL: collection.photos[0].sourceURL)
    kept.keepInPlace = true; kept.colours = collection.photos[0].palette
    let note = PrintItem(assetFile: "", title: "Note", style: .sticky, x: 520, y: 500, width: 170, height: 160, displayID: 1, kind: .note, text: "Keep this too")
    board.items = [kept, note]
    let result = try WallRotation.fillEmpty(board, collection: collection, display: .init(id: 1, name: "Screen", width: 1512, height: 982), seed: 42)
    try expect(Array(result.items.prefix(2)) == board.items)
    try expect(result.items.dropFirst(2).contains { ColourMatch.majorColourIndex($0.colours ?? [], scheme: scheme) == 1 })
    var history = BoardHistory(); history.record(board)
    try expect(history.undo(current: result) == board)
}
