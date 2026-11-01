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
    public func importCollection(at path: String) async throws -> PhotoCollection {
        guard path.hasPrefix("/") else { throw CorkError("Choose an absolute local collection manifest path.") }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, (1...5_000_000).contains(size) else { throw CorkError("Choose a collection JSON file under 5 MB.") }
        let manifest = try JSONDecoder().decode(CollectionImport.self, from: Data(contentsOf: url))
        let removals = Set(manifest.removeIDs ?? []), incoming = Set(manifest.photos.map(\.id))
        guard manifest.schemaVersion == 1, (1...200).contains(manifest.photos.count + removals.count),
              incoming.count == manifest.photos.count, removals.count == (manifest.removeIDs ?? []).count,
              removals.isDisjoint(with: incoming), removals.allSatisfy({ !$0.isEmpty && $0.count <= 120 }) else {
            throw CorkError("Import or exclude 1–200 unique catalogue IDs with schemaVersion 1.")
        }
        let original = try loadCollection().0
        func merge(_ entries: [(CollectionImportPhoto, ImportedAsset)], into collection: PhotoCollection) throws -> PhotoCollection {
            guard removals.isSubset(of: Set(collection.photos.map(\.id))) else { throw CorkError("A selected catalogue ID no longer exists. Inspect the collection before resuming.") }
            var next = collection
            next.photos.removeAll { removals.contains($0.id) }
            for theme in manifest.themes {
                if let index = next.themes.firstIndex(where: { $0.id == theme.id }) { next.themes[index] = theme }
                else { next.themes.append(theme) }
            }
            for (entry, asset) in entries {
                guard entry.path.hasPrefix("/"), entry.kind == nil || entry.kind == .image || entry.kind == .video else { throw CorkError("Collection paths must be absolute and kind must be image or video.") }
                if let index = next.photos.firstIndex(where: { $0.id == entry.id }) {
                    guard next.photos[index].sourceURL == entry.sourceURL else { throw CorkError("A collection ID cannot change its source URL.") }
                    next.photos[index] = entry.saved(asset: asset)
                } else { next.photos.append(entry.saved(asset: asset)) }
            }
            try next.validate(); return next
        }
        // Validate all metadata before importing any media. Real video descriptors
        // are produced by decoding the file, never trusted from the manifest.
        _ = try merge(manifest.photos.map { ($0, ImportedAsset(file: "pending.png", width: 100, height: 100, title: $0.title)) }, into: original)
        var created: [String] = [], staged: [(CollectionImportPhoto, ImportedAsset)] = []
        do {
            for entry in manifest.photos {
                try Task.checkCancellation()
                let wantsVideo = entry.kind == .video
                if let old = original.photos.first(where: { $0.id == entry.id }),
                   (old.video != nil) == wantsVideo,
                   FileManager.default.fileExists(atPath: assets.appendingPathComponent(old.assetFile).path),
                   old.video.map({ FileManager.default.fileExists(atPath: assets.appendingPathComponent($0.file).path) }) ?? true {
                    staged.append((entry, ImportedAsset(file: old.assetFile, width: old.imageWidth, height: old.imageHeight, title: entry.title,
                        colourProfile: try old.colourProfile ?? imageColourProfile(assetFile: old.assetFile), colours: old.palette, video: old.video)))
                } else {
                    let asset = wantsVideo ? try await importVideo(at: entry.path) : try importImage(at: entry.path, maxPixelSize: 2048)
                    created.append(asset.file); if let video = asset.video { created.append(video.file) }
                    staged.append((entry, asset))
                }
            }
            try Task.checkCancellation()
            // Video decoding suspends this actor. Merge into the latest catalogue
            // after staging, so another completed import/classification is retained.
            let next = try merge(staged, into: loadCollection().0)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let saved = try encoder.encode(next), target = root.appendingPathComponent("collection.json")
            if let previous = try? Data(contentsOf: target), (try? decodeCollection(previous)) != nil {
                try previous.write(to: root.appendingPathComponent("collection.previous.json"), options: [.atomic])
            }
            try saved.write(to: target, options: [.atomic])
            created.removeAll()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            return next
        } catch {
            for name in created { try? FileManager.default.removeItem(at: assets.appendingPathComponent(name)) }
            throw error
        }
    }
}
