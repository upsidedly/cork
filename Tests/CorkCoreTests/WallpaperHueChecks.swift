import Foundation
import CorkCore

private let bluePhotoColours = ["#6D81A8", "#2B3043", "#3F4863", "#19191C", "#596A8E"]
private let pinkWallpaperColours = ["#B0A4D5", "#D1ACDA", "#DEC5E5", "#8E79C3", "#B27CBC"]

@MainActor func wallpaperMatchingRejectsPinkPurpleForDominantlyBluePhotos() throws {
    let photos = Array(repeating: bluePhotoColours, count: 12)
    try expect(ColourMatch.wallpaperHueAffinity(pinkWallpaperColours, imagePalettes: photos) == 0)
    try expect(ColourMatch.wallpaperHueAffinity(bluePhotoColours, imagePalettes: photos) > 0.9)
    try expect(ColourMatch.wallpaperHueAffinity(["#919191", "#2B2B2B"], imagePalettes: photos) > 0)
    // A small blue accent cannot excuse a mostly pink background.
    try expect(ColourMatch.wallpaperHueAffinity(Array(pinkWallpaperColours.prefix(3)) + [bluePhotoColours[0]], imagePalettes: photos) == 0)
    try expect(ColourMatch.wallpaperHueAffinity(pinkWallpaperColours, imagePalettes: Array(repeating: ["#888888"], count: 8)) == 0)
}

@MainActor func sceneWallpaperUsesActualPhotoHueEvenWithABroadPreset() throws {
    let display = DisplayInfo(id: 1, name: "Retina", width: 1512, height: 982, scale: 2)
    var collection = PhotoCollection()
    collection.themes = [.init(id: "blue-hour", name: "Night blue", description: "Blue photographs")]
    for index in 0..<32 {
        collection.photos.append(.init(id: "blue-\(index)", assetFile: "blue-\(index).png", title: "", description: "Blue",
            sourceURL: "https://www.pinterest.com/pin/\(index)/", sourceBoard: "board-\(index % 5)", tags: [],
            palette: bluePhotoColours, themeIDs: ["blue-hour"], imageWidth: index % 3 == 0 ? 1400 : 700, imageHeight: 1000))
    }
    func wallpaper(_ id: String, _ colours: [String]) -> CollectionWallpaper {
        .init(id: id, assetFile: "\(id).jpg", title: id, sourceURL: "https://www.pinterest.com/pin/\(id)/",
            sourceBoard: "Test", palette: colours, themeIDs: ["blue-hour"], width: 3840, height: 2400)
    }
    var wallpapers = WallpaperCollection()
    wallpapers.wallpapers = [wallpaper("pink", pinkWallpaperColours), wallpaper("blue", bluePhotoColours)]
    let lavender = ScenePalettes.all.first { $0.id == "lavender-dusk" }!
    // This background passed the old broad-preset score despite clashing with the actual photos.
    try expect(ColourMatch.backgroundScore(pinkWallpaperColours, against: lavender.colours) >= 0.55)
    for seed in UInt64(0)..<8 {
        let result = try WallRotation.roll(Board(), collection: collection, display: display,
            seed: seed, wallpapers: wallpapers, paletteID: "lavender-dusk")
        try expect(result.rotation?.wallpaperID == "blue" && result.rotation?.wallpaperMatched == true)
    }
    var kept = Board(); kept.desktop.wallpaper = wallpapers.wallpapers[0].settings
    var anchor = PrintItem(assetFile: collection.photos[0].assetFile, title: "", x: 70, y: 320,
        width: 190, height: 250, displayID: 1, sourceURL: collection.photos[0].sourceURL)
    anchor.colours = bluePhotoColours; kept.items = [anchor]
    let filled = try WallRotation.fillEmpty(kept, collection: collection, display: display,
        seed: 42, wallpapers: wallpapers, paletteID: "lavender-dusk")
    try expect(filled.items.contains(anchor) && filled.rotation?.wallpaperID == "blue")
    wallpapers.wallpapers[1] = wallpaper("neutral", ["#919191", "#2B2B2B", "#4F4F4F"])
    let fallback = try WallRotation.roll(Board(), collection: collection, display: display,
        seed: 42, wallpapers: wallpapers, paletteID: "lavender-dusk")
    try expect(fallback.rotation?.wallpaperID == "neutral")
}
