import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

extension BoardRepository {
    /// File decoding and bounded frame analysis stay on the repository actor, away from UI.
    public func importVideo(at path: String) async throws -> ImportedAsset {
        guard path.hasPrefix("/") else { throw CorkError("Choose an absolute local video path.") }
        let source = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let bytes = values.fileSize, (1...200_000_000).contains(bytes),
              ["mp4", "mov", "m4v"].contains(source.pathExtension.lowercased()) else {
            throw CorkError("Choose a local MP4, MOV or M4V video under 200 MB.")
        }
        let asset = AVURLAsset(url: source)
        let playable = try await asset.load(.isPlayable), duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard playable, !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0, duration.seconds <= 600 else {
            throw CorkError("Choose a playable video up to ten minutes long.")
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        // Five spread-out samples catch colour changes; the second is the still cover.
        let fractions = [0.05, 0.25, 0.5, 0.75, 0.95]
        var profiles: [ImageColourProfile] = []
        var poster: CGImage?
        for (index, fraction) in fractions.enumerated() {
            try Task.checkCancellation()
            let image = try await generator.image(at: CMTime(seconds: duration.seconds * fraction, preferredTimescale: 600)).image
            profiles.append(try PaletteAnalysis.profile(image: image))
            if index == 1 { poster = image }
        }
        guard let poster else { throw CorkError("Could not create a still cover for this video.") }
        // Packing balances the colour actually visible at rest. The other frame
        // profiles separately reject clips that shift outside the scene on hover.
        let profile = profiles[1]
        try profile.validate(); try Task.checkCancellation(); try prepare()
        let stem = UUID().uuidString, videoFile = stem + "." + source.pathExtension.lowercased(), coverFile = stem + ".png"
        let attachment = VideoAttachment(file: videoFile, duration: duration.seconds, posterTime: duration.seconds * 0.25, colourSamples: profiles)
        try attachment.validate()
        let copy = assets.appendingPathComponent(videoFile), cover = assets.appendingPathComponent(coverFile)
        do {
            try FileManager.default.copyItem(at: source, to: copy)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
            guard let destination = CGImageDestinationCreateWithURL(cover as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CorkError("Could not save the video cover.") }
            CGImageDestinationAddImage(destination, poster, nil)
            guard CGImageDestinationFinalize(destination) else { throw CorkError("Could not finish the video cover.") }
            try Task.checkCancellation()
            // Cover palette remains useful for existing mood matching; measured multi-frame
            // coverage and each sampled frame enforce custom colour matching separately.
            return ImportedAsset(file: coverFile, width: Double(poster.width), height: Double(poster.height),
                title: source.deletingPathExtension().lastPathComponent, colourProfile: profile, colours: try PaletteAnalysis.colours(image: poster), video: attachment)
        } catch {
            try? FileManager.default.removeItem(at: copy); try? FileManager.default.removeItem(at: cover)
            throw error
        }
    }

    public func importMedia(at path: String, maxPixelSize: Int = 4096) async throws -> ImportedAsset {
        let type = UTType(filenameExtension: URL(fileURLWithPath: path).pathExtension)
        if type?.conforms(to: .movie) == true { return try await importVideo(at: path) }
        return try importImage(at: path, maxPixelSize: maxPixelSize)
    }

    /// Roll back only this import's files, and only after confirmed saved state
    /// proves they are unreferenced. An ambiguous/corrupt save keeps its media.
    public func discardUnreferencedImports(_ imports: [ImportedAsset]) {
        guard !imports.isEmpty, let (board, boardWarning) = try? load(), boardWarning == nil,
              let (collection, collectionWarning) = try? loadCollection(), collectionWarning == nil,
              let favourites = try? loadFavourites() else { return }
        let items = board.items + favourites.boards.flatMap(\.items)
        var referenced = Set(items.map(\.assetFile) + items.compactMap { $0.video?.file })
        referenced.formUnion(collection.photos.map(\.assetFile) + collection.photos.compactMap { $0.video?.file })
        for asset in imports {
            for file in [asset.file, asset.video?.file].compactMap({ $0 }) where !referenced.contains(file) &&
                file == URL(fileURLWithPath: file).lastPathComponent && !file.hasPrefix(".") {
                try? FileManager.default.removeItem(at: assets.appendingPathComponent(file))
            }
        }
    }
}
