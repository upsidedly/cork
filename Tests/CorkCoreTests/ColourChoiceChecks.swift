import Foundation
import CorkCore

private let choiceDisplay = DisplayInfo(id: 1, name: "Retina", width: 1512, height: 982, scale: 2)
private func choiceCollection() -> PhotoCollection {
    var collection = PhotoCollection()
    collection.themes = [.init(id: "test", name: "Test", description: "Different subjects and sources")]
    for (group, family) in [ColourFamily.blue, .yellow, .red, .green].enumerated() {
        for index in 0..<24 {
            let id = "choice-\(group)-\(index)"
            collection.photos.append(.init(id: id, assetFile: id + ".png", title: "Metadata", description: "Photo",
                sourceURL: "https://example.com/\(id)", sourceBoard: "board-\(index % 6)", tags: [], palette: [family.hex, ColourFamily.grey.hex],
                themeIDs: ["test"], imageWidth: index % 3 == 0 ? 1300 : 750, imageHeight: 1000,
                colourProfile: ImageColourProfile(coverages: [family: 0.8, .grey: 0.2])))
        }
    }
    return collection
}
private func choiceBoard(_ choices: [ColourChoice]) -> Board {
    var board = Board(), options = SceneOptions(); options.colourPair = choices
    board.desktop.scenes = options; return board
}
private func choiceWallpapers() -> WallpaperCollection {
    var result = WallpaperCollection()
    for family in [ColourFamily.blue, .yellow, .red, .green] {
        result.wallpapers.append(.init(id: family.rawValue, assetFile: family.rawValue + ".jpg", title: family.name,
            sourceURL: "https://example.com/\(family.rawValue)", sourceBoard: "backgrounds", palette: [family.hex], themeIDs: [],
            width: 4000, height: 2500, colourProfile: ImageColourProfile(coverages: [family: 0.8, .grey: 0.2])))
    }
    return result
}

@MainActor func randomColourChoicesMigrateAndPersist() throws {
    let old = try JSONDecoder().decode(SceneOptions.self,
        from: Data(#"{"matchColours":true,"matchWallpaper":true,"colourPair":["blue","yellow"]}"#.utf8))
    try expect(old.colourPair == [.colour(.blue), .colour(.yellow)] && old.fixedColourPair == [.blue, .yellow])
    for choices: [ColourChoice] in [[.random, .random], [.random, .colour(.blue)], [.colour(.blue), .random]] {
        let board = choiceBoard(choices); try board.validate()
        try expect(try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board)) == board)
        let favourite = FavouriteBoard(board: board, name: "Random choices", now: Date(timeIntervalSince1970: 100))
        let loaded = try JSONDecoder().decode(FavouriteBoard.self, from: JSONEncoder().encode(favourite))
        try expect(try loaded.restoring(into: Board()).desktop.sceneOptions.colourPair == choices)
        try CorkTools.validate(name: "cork_set_desktop", arguments: ["colour_pair": .array(choices.map { .string($0.rawValue) })])
    }
    try expectThrows { try choiceBoard([.colour(.blue), .colour(.blue)]).validate() }
    try expectThrows { try choiceBoard([.random]).validate() }
    try expect(ColourChoice(rawValue: "unknown") == nil)
}

@MainActor func randomColourSlotsPreserveFixedRoles() throws {
    let collection = choiceCollection(), backgrounds = choiceWallpapers()
    for choices: [ColourChoice] in [[.random, .colour(.blue)], [.colour(.blue), .random], [.random, .random]] {
        var board = choiceBoard(choices)
        for seed in UInt64(1)..<4 {
            let previous = board.rotation?.scheme?.colourFamilies
            let result = try WallRotation.roll(board, collection: collection, display: choiceDisplay, seed: seed, wallpapers: backgrounds)
            guard let pair = result.rotation?.scheme?.colourFamilies else { throw CheckFailure(description: "Missing resolved pair") }
            try expect(pair.count == 2 && pair[0] != pair[1] && result.desktop.sceneOptions.colourPair == choices)
            for index in 0..<2 {
                if let fixed = choices[index].family { try expect(pair[index] == fixed) }
                else if let previous { try expect(pair[index] != previous[index]) }
            }
            try expect(result.rotation?.wallpaperID == pair[0].rawValue)
            let repeated = try WallRotation.roll(board, collection: collection, display: choiceDisplay, seed: seed, wallpapers: backgrounds)
            try expect(repeated.rotation == result.rotation && repeated.items.map(\.assetFile) == result.items.map(\.assetFile))
            board = result
        }
    }
}

@MainActor func dominantColourControlsImageAreaAndWallpaper() throws {
    let collection = choiceCollection()
    for pair: [ColourFamily] in [[.blue, .yellow], [.yellow, .blue]] {
        for seed in UInt64(1)..<4 {
            let result = try WallRotation.roll(choiceBoard(pair.map(ColourChoice.colour)), collection: collection,
                display: choiceDisplay, seed: seed, wallpapers: choiceWallpapers())
            var areas = [0.0, 0.0]
            for item in result.items {
                for index in 0..<2 { areas[index] += item.width * item.height * (item.colourProfile?.coverage(pair[index]) ?? 0) }
            }
            let share = areas[0] / areas.reduce(0, +)
            try expect(share > 0.5 && share < 0.82)
            try expect(result.rotation?.wallpaperID == pair[0].rawValue && result.rotation?.wallpaperMatched == true)
        }
    }
    var secondaryOnly = choiceWallpapers(); secondaryOnly.wallpapers.removeAll { $0.id != "yellow" }
    let rejected = try WallRotation.roll(choiceBoard([.colour(.blue), .colour(.yellow)]), collection: collection,
        display: choiceDisplay, seed: 1, wallpapers: secondaryOnly)
    try expect(rejected.rotation?.wallpaperMatched == false && rejected.desktop.wallpaper.kind == .system)
}

@MainActor func randomColourFillsAndDisplayRefitsRetainTheScene() throws {
    let choices: [ColourChoice] = [.random, .colour(.blue)], collection = choiceCollection()
    var board = try WallRotation.roll(choiceBoard(choices), collection: collection, display: choiceDisplay, seed: 1, wallpapers: choiceWallpapers())
    let pair = board.rotation?.scheme?.colourFamilies
    board.items.removeLast()
    let saved = board.items
    let filled = try WallRotation.fillEmpty(board, collection: collection, display: choiceDisplay, seed: 9,
        wallpapers: choiceWallpapers(), maximumNewPhotos: 1, allowNoNewPhotos: true)
    try expect(Array(filled.items.prefix(saved.count)) == saved && filled.rotation?.scheme?.colourFamilies == pair)
    try expect(filled.desktop.sceneOptions.colourPair == choices)
    board = filled; board.layoutDisplays = [choiceDisplay]
    let bigger = DisplayInfo(id: 1, name: "Retina", width: 1800, height: 1169, scale: 2)
    let grown = try DisplayAdaptation.fit(board, displays: [bigger], collection: collection, wallpapers: choiceWallpapers())
    try expect(grown.rotation?.scheme?.colourFamilies == pair && grown.desktop.sceneOptions.colourPair == choices)
    var history = BoardHistory(); history.record(board)
    try expect(history.undo(current: grown) == board)
}

@MainActor func randomColoursPreferAvailableNativeWallpapers() throws {
    let collection = choiceCollection()
    var backgrounds = choiceWallpapers(); backgrounds.wallpapers.removeAll { $0.id != "yellow" && $0.id != "red" }
    backgrounds.wallpapers[1].width = 1000
    // Exactly one primary family has a large enough matching backdrop.
    let native = backgrounds.wallpapers.first { $0.supports(choiceDisplay) }!.id
    let board = choiceBoard([.random, .colour(.blue)])
    for seed in UInt64(1)..<3 {
        let result = try WallRotation.roll(board, collection: collection, display: choiceDisplay, seed: seed, wallpapers: backgrounds)
        try expect(result.rotation?.scheme?.colourFamilies?.first?.rawValue == native && result.rotation?.wallpaperID == native)
    }
    try expectThrows { try WallRotation.roll(choiceBoard([.colour(.violet), .random]), collection: collection, display: choiceDisplay, seed: 1) }
    let available = ColourPairSelection.availablePairs(choices: [.random, .colour(.blue)], profiles: collection.photos.compactMap(\.colourProfile), strength: .strong)
    try expect(!available.isEmpty && available.allSatisfy { $0[0] != .blue && $0[0] != .grey && $0[1] == .blue })
}
