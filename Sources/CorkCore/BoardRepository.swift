import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin
import AVFoundation

public struct ImportedAsset: Sendable {
    public let file: String
    public let width: Double
    public let height: Double
    public let title: String
    public let colourProfile: ImageColourProfile?
    public let colours: [String]?
    public let video: VideoAttachment?
    public init(file: String, width: Double, height: Double, title: String, colourProfile: ImageColourProfile? = nil, colours: [String]? = nil, video: VideoAttachment? = nil) {
        self.file = file; self.width = width; self.height = height; self.title = title; self.colourProfile = colourProfile
        self.colours = colours; self.video = video
    }
}

public actor BoardRepository {
    public nonisolated let root: URL
    public nonisolated var assets: URL { root.appendingPathComponent("Images", isDirectory: true) }
    public nonisolated var wallpapers: URL { root.appendingPathComponent("Wallpapers", isDirectory: true) }
    public init(root: URL = CorkPaths.dataDirectory) { self.root = root }

    public func prepare() throws {
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try FileManager.default.createDirectory(at: wallpapers, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    public func load() throws -> (Board, String?) {
        try prepare()
        let url = root.appendingPathComponent("board.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            var fresh = Board(); fresh.desktop.hideDesktopFiles = false
            return (fresh, nil)
        }
        do { return (try decode(Data(contentsOf: url)), nil) }
        catch {
            let originalError = error.localizedDescription
            let backup = root.appendingPathComponent("board.previous.json")
            do { return (try decode(Data(contentsOf: backup)), "Recovered the previous saved board. The latest board could not be read: \(originalError)") }
            catch { throw CorkError("Cork could not read its saved board. Your files are still in \(root.path). \(originalError)") }
        }
    }

    private func decode(_ data: Data) throws -> Board {
        guard data.count <= 4_000_000 else { throw CorkError("The saved board is too large.") }
        let board = try JSONDecoder().decode(Board.self, from: data)
        try board.validate(); return board
    }

    public func save(_ board: Board) throws {
        try board.validate(); try prepare()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(board)
        let url = root.appendingPathComponent("board.json")
        if let previous = try? Data(contentsOf: url), (try? decode(previous)) != nil {
            try previous.write(to: root.appendingPathComponent("board.previous.json"), options: [.atomic])
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func importImage(at path: String, maxPixelSize: Int = 4096) throws -> ImportedAsset {
        guard (512...4096).contains(maxPixelSize) else { throw CorkError("Invalid image copy size.") }
        guard path.hasPrefix("/") else { throw CorkError("path must be an absolute local image path. Download Pinterest images through the Pinterest plugin first.") }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let count = values.fileSize, count > 0, count <= 50_000_000 else { throw CorkError("Choose a regular image file under 50 MB.") }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0, width * height <= 100_000_000 else { throw CorkError("This file is not a supported image, or exceeds 100 megapixels.") }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw CorkError("Could not decode the image.") }
        let colourProfile = try PaletteAnalysis.profile(image: image)
        try prepare()
        let filename = "\(UUID().uuidString).png"
        let destinationURL = assets.appendingPathComponent(filename)
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CorkError("Could not create an image copy.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CorkError("Could not save the image copy.") }
        return ImportedAsset(file: filename, width: Double(image.width), height: Double(image.height), title: url.deletingPathExtension().lastPathComponent,
            colourProfile: colourProfile)
    }

    public func importWallpaperImage(at path: String) throws -> WallpaperSettings {
        let asset = try importImage(at: path)
        try FileManager.default.moveItem(at: assets.appendingPathComponent(asset.file), to: wallpapers.appendingPathComponent(asset.file))
        var settings = WallpaperSettings(); settings.kind = .image; settings.assetFile = asset.file
        settings.sourceName = String(URL(fileURLWithPath: path).lastPathComponent.prefix(500))
        return settings
    }

    public func importWallpaperVideo(at path: String) async throws -> WallpaperSettings {
        guard path.hasPrefix("/") else { throw CorkError("Choose an absolute local video path.") }
        let source = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let count = values.fileSize, count > 0, count <= 2_000_000_000 else { throw CorkError("Choose a regular video file under 2 GB.") }
        let asset = AVURLAsset(url: source)
        let playable = try await asset.load(.isPlayable)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        guard playable, !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else { throw CorkError("This file does not contain a playable video.") }
        let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 3840, height: 2160)
        let preview = try await generator.image(at: .zero).image
        try Task.checkCancellation(); try prepare()
        let stem = UUID().uuidString
        let suffix = source.pathExtension.lowercased()
        guard !suffix.isEmpty, suffix.count < 12, suffix.allSatisfy({ $0.isLetter || $0.isNumber }) else { throw CorkError("The video needs a valid file extension, such as .mp4 or .mov.") }
        let filename = "\(stem).\(suffix)", poster = "\(stem).png"
        let copy = wallpapers.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: source, to: copy)
        do {
            let url = wallpapers.appendingPathComponent(poster)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CorkError("Could not save the video preview.") }
            CGImageDestinationAddImage(destination, preview, nil)
            guard CGImageDestinationFinalize(destination) else { throw CorkError("Could not finish the video preview.") }
        } catch { try? FileManager.default.removeItem(at: copy); throw error }
        var settings = WallpaperSettings(); settings.kind = .video; settings.assetFile = filename; settings.posterFile = poster
        settings.sourceName = String(source.lastPathComponent.prefix(500))
        return settings
    }
}

public enum CorkPaths {
    public static var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CORK_DATA_DIR"], override.hasPrefix("/") { return URL(fileURLWithPath: override, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cork", isDirectory: true)
    }
    public static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["CORK_SOCKET"], override.hasPrefix("/") { return override }
        return dataDirectory.appendingPathComponent("control.sock").path
    }
}
