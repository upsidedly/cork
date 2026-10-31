import Foundation
import ImageIO

extension BoardRepository {
    private func readColourProfile(_ url: URL) throws -> ImageColourProfile {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 64,
                  kCGImageSourceShouldCache: false] as CFDictionary) else { throw CorkError("Could not classify colours in \(url.lastPathComponent). The saved wall is unchanged.") }
        return try PaletteAnalysis.profile(image: image)
    }
    private func checkedColourAsset(_ file: String, folder: URL) throws -> URL {
        guard !file.isEmpty, file == URL(fileURLWithPath: file).lastPathComponent, !file.hasPrefix(".") else { throw CorkError("Invalid colour-analysis asset.") }
        return folder.appendingPathComponent(file)
    }
    public func imageColourProfile(assetFile: String) throws -> ImageColourProfile {
        try readColourProfile(checkedColourAsset(assetFile, folder: assets))
    }
    public func wallpaperColourProfile(assetFile: String) throws -> ImageColourProfile {
        try readColourProfile(checkedColourAsset(assetFile, folder: wallpapers))
    }
    /// One actor-owned pass. No suspension between reading and committing a catalogue;
    /// imports cannot be overwritten by a stale classification snapshot.
    public func classifyColours() throws -> (PhotoCollection, WallpaperCollection) {
        let originalPhotos = try loadCollection().0, originalWallpapers = try loadWallpapers().0
        var photos = originalPhotos, backgrounds = originalWallpapers
        for index in photos.photos.indices where photos.photos[index].colourProfile == nil {
            try Task.checkCancellation()
            photos.photos[index].colourProfile = try imageColourProfile(assetFile: photos.photos[index].assetFile)
        }
        for index in backgrounds.wallpapers.indices where backgrounds.wallpapers[index].colourProfile == nil {
            try Task.checkCancellation()
            backgrounds.wallpapers[index].colourProfile = try wallpaperColourProfile(assetFile: backgrounds.wallpapers[index].assetFile)
        }
        try photos.validate(); try backgrounds.validate(); try Task.checkCancellation()
        try saveColourCache(photos, previous: originalPhotos, name: "collection")
        try saveColourCache(backgrounds, previous: originalWallpapers, name: "wallpapers")
        return (photos, backgrounds)
    }
    private func saveColourCache<Value: Codable & Equatable>(_ value: Value, previous: Value, name: String) throws {
        guard value != previous else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= 5_000_000 else { throw CorkError("The classified catalogue is too large.") }
        let url = root.appendingPathComponent(name + ".json"), backup = root.appendingPathComponent(name + ".previous.json")
        if let old = try? Data(contentsOf: url), (try? JSONDecoder().decode(Value.self, from: old)) == previous {
            try old.write(to: backup, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
