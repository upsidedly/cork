import Foundation

extension BoardRepository {
    private func decodeCollection(_ data: Data) throws -> PhotoCollection {
        guard data.count <= 64_000_000 else { throw CorkError("The rotation collection is too large.") }
        let result = try JSONDecoder().decode(PhotoCollection.self, from: data)
        try result.validate(); return result
    }

    public func loadCollection() throws -> (PhotoCollection, String?) {
        try prepare()
        let url = root.appendingPathComponent("collection.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return (PhotoCollection(), nil) }
        do { return (try decodeCollection(Data(contentsOf: url)), nil) }
        catch {
            let original = error.localizedDescription
            do { return (try decodeCollection(Data(contentsOf: root.appendingPathComponent("collection.previous.json"))), "Recovered the previous rotation collection. \(original)") }
            catch { throw CorkError("Cork could not read its rotation collection. Your current wall is preserved. \(original)") }
        }
    }

    /// Imports are merged by stable source ID. Existing copies are reused; no source is fetched.
    public func importCollection(at path: String) throws -> PhotoCollection {
        guard path.hasPrefix("/") else { throw CorkError("Choose an absolute local collection manifest path.") }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, (1...5_000_000).contains(size) else { throw CorkError("Choose a collection JSON file under 5 MB.") }
        let manifest = try JSONDecoder().decode(CollectionImport.self, from: Data(contentsOf: url))
        guard manifest.schemaVersion == 1, (1...200).contains(manifest.photos.count),
              Set(manifest.photos.map(\.id)).count == manifest.photos.count else { throw CorkError("Import 1–200 unique photos with schemaVersion 1.") }
        var (next, _) = try loadCollection()
        for theme in manifest.themes {
            if let index = next.themes.firstIndex(where: { $0.id == theme.id }) { next.themes[index] = theme }
            else { next.themes.append(theme) }
        }
        var validation = next
        for entry in manifest.photos {
            guard entry.path.hasPrefix("/") else { throw CorkError("Collection photo paths must be absolute.") }
            let placeholder = entry.saved(asset: ImportedAsset(file: "pending.png", width: 100, height: 100, title: entry.title))
            if let index = validation.photos.firstIndex(where: { $0.id == entry.id }) {
                guard validation.photos[index].sourceURL == entry.sourceURL else { throw CorkError("A collection ID cannot change its source URL.") }
                validation.photos[index] = placeholder
            } else { validation.photos.append(placeholder) }
        }
        try validation.validate()
        var created: [String] = []
        do {
            for entry in manifest.photos {
                try Task.checkCancellation()
                if let index = next.photos.firstIndex(where: { $0.id == entry.id }),
                   FileManager.default.fileExists(atPath: assets.appendingPathComponent(next.photos[index].assetFile).path) {
                    let old = next.photos[index]
                    next.photos[index] = entry.saved(asset: ImportedAsset(file: old.assetFile, width: old.imageWidth, height: old.imageHeight, title: entry.title,
                        colourProfile: try old.colourProfile ?? imageColourProfile(assetFile: old.assetFile)))
                } else {
                    let asset = try importImage(at: entry.path, maxPixelSize: 2048); created.append(asset.file)
                    let photo = entry.saved(asset: asset)
                    if let index = next.photos.firstIndex(where: { $0.id == entry.id }) { next.photos[index] = photo }
                    else { next.photos.append(photo) }
                }
            }
            try next.validate(); try Task.checkCancellation()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let saved = try encoder.encode(next), target = root.appendingPathComponent("collection.json")
            if let previous = try? Data(contentsOf: target), (try? decodeCollection(previous)) != nil {
                try previous.write(to: root.appendingPathComponent("collection.previous.json"), options: [.atomic])
            }
            try saved.write(to: target, options: [.atomic])
            // A committed collection must retain its media even if applying permissions fails.
            created.removeAll()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            return next
        } catch {
            for name in created { try? FileManager.default.removeItem(at: assets.appendingPathComponent(name)) }
            throw error
        }
    }
}
