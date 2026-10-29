import Foundation
import ImageIO
import UniformTypeIdentifiers

extension BoardRepository {
    private func decodeWallpapers(_ data: Data) throws -> WallpaperCollection {
        guard data.count <= 2_000_000 else { throw CorkError("The wallpaper catalogue is too large.") }
        let saved = try JSONDecoder().decode(WallpaperCollection.self, from: data); try saved.validate(); return saved
    }
    public func loadWallpapers() throws -> (WallpaperCollection, String?) {
        try prepare(); let path = root.appendingPathComponent("wallpapers.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return (WallpaperCollection(), nil) }
        do { return (try decodeWallpapers(Data(contentsOf: path)), nil) }
        catch {
            if let data = try? Data(contentsOf: root.appendingPathComponent("wallpapers.previous.json")), let recovered = try? decodeWallpapers(data) {
                return (recovered, "Recovered the previous wallpaper catalogue.")
            }
            throw CorkError("Cork could not read the wallpaper catalogue. Your current wallpaper is preserved.")
        }
    }
    public func importWallpapers(at path: String) throws -> WallpaperCollection {
        guard path.hasPrefix("/") else { throw CorkError("Use an absolute local wallpaper manifest path.") }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, let size = info.fileSize, (1...2_000_000).contains(size) else { throw CorkError("Choose a wallpaper manifest under 2 MB.") }
        let manifest = try JSONDecoder().decode(WallpaperImport.self, from: Data(contentsOf: url))
        guard manifest.schemaVersion == 1, (1...50).contains(manifest.wallpapers.count), Set(manifest.wallpapers.map(\.id)).count == manifest.wallpapers.count else { throw CorkError("Import 1–50 unique wallpapers with schemaVersion 1.") }
        var (next, _) = try loadWallpapers()
        // Validate all external metadata before copying a single asset.
        var check = next
        for entry in manifest.wallpapers {
            guard entry.path.hasPrefix("/") else { throw CorkError("Wallpaper paths must be absolute.") }
            let placeholder = CollectionWallpaper(id: entry.id, assetFile: "pending.jpg", title: entry.title, sourceURL: entry.sourceURL,
                sourceBoard: entry.sourceBoard, palette: ["#000000"], themeIDs: entry.themeIDs, width: 100, height: 100, automatic: entry.automatic)
            if let index = check.wallpapers.firstIndex(where: { $0.id == entry.id }) {
                guard check.wallpapers[index].sourceURL == entry.sourceURL else { throw CorkError("A wallpaper ID cannot change its source URL.") }
                check.wallpapers[index] = placeholder
            } else { check.wallpapers.append(placeholder) }
        }
        try check.validate()
        var created: [String] = []
        do {
            for entry in manifest.wallpapers {
                try Task.checkCancellation()
                let item: CollectionWallpaper
                if let old = next.wallpapers.first(where: { $0.id == entry.id }), FileManager.default.fileExists(atPath: wallpapers.appendingPathComponent(old.assetFile).path) {
                    item = CollectionWallpaper(id: entry.id, assetFile: old.assetFile, title: entry.title, sourceURL: entry.sourceURL,
                        sourceBoard: entry.sourceBoard, palette: old.palette, themeIDs: entry.themeIDs, width: old.width, height: old.height, automatic: entry.automatic ?? old.automatic)
                } else {
                    let sourceURL = URL(fileURLWithPath: entry.path).resolvingSymlinksInPath()
                    let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true, let bytes = values.fileSize, (1...50_000_000).contains(bytes),
                          let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
                          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let w = props[kCGImagePropertyPixelWidth] as? Double, let h = props[kCGImagePropertyPixelHeight] as? Double,
                          w > 0, h > 0, w * h <= 100_000_000,
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                              kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 8192] as CFDictionary) else {
                        throw CorkError("Choose a supported wallpaper image under 50 MB and 100 megapixels.")
                    }
                    let filename = "\(UUID().uuidString).jpg"; created.append(filename)
                    guard let destination = CGImageDestinationCreateWithURL(wallpapers.appendingPathComponent(filename) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw CorkError("Could not save the wallpaper copy.") }
                    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.96] as CFDictionary)
                    guard CGImageDestinationFinalize(destination) else { throw CorkError("Could not finish the wallpaper copy.") }
                    item = CollectionWallpaper(id: entry.id, assetFile: filename, title: entry.title, sourceURL: entry.sourceURL,
                        sourceBoard: entry.sourceBoard, palette: try PaletteAnalysis.colours(image: image), themeIDs: entry.themeIDs,
                        width: Double(image.width), height: Double(image.height), automatic: entry.automatic)
                }
                if let index = next.wallpapers.firstIndex(where: { $0.id == item.id }) { next.wallpapers[index] = item }
                else { next.wallpapers.append(item) }
            }
            try next.validate(); try Task.checkCancellation()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let target = root.appendingPathComponent("wallpapers.json")
            if let previous = try? Data(contentsOf: target), (try? decodeWallpapers(previous)) != nil {
                try previous.write(to: root.appendingPathComponent("wallpapers.previous.json"), options: [.atomic])
            }
            try encoder.encode(next).write(to: target, options: [.atomic]); created.removeAll()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            return next
        } catch {
            for filename in created { try? FileManager.default.removeItem(at: wallpapers.appendingPathComponent(filename)) }
            throw error
        }
    }
}
