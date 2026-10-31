import Foundation
import ImageIO
import UniformTypeIdentifiers
import CorkCore

public struct ImportReview: Codable, Sendable {
    public var images: [PinterestImage]
    public var removed: Set<String> = []
    public var committed: Set<String> = []
    public var warnings: [String] = []
    public init(images: [PinterestImage], warnings: [String] = []) { self.images = images; self.warnings = warnings }
    public var keepers: [PinterestImage] { images.filter { !removed.contains($0.id) } }
}

/// Contains review metadata only. Cookies and browser keys are never serialized.
public actor ImportSessionStore {
    public nonisolated let root: URL
    public static var defaultDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["CORK_IMPORT_DATA_DIR"], path.hasPrefix("/") { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cork Importer")
    }
    public init(root: URL = ImportSessionStore.defaultDirectory) { self.root = root }
    public func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
    public func load() throws -> ImportReview? {
        let url = root.appendingPathComponent("review.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 40_000_000 else { throw CorkError("The saved import review is too large.") }
        let review = try JSONDecoder().decode(ImportReview.self, from: Data(contentsOf: url))
        guard review.images.count <= PhotoCollection.maximumPhotos, Set(review.images.map(\.id)).count == review.images.count,
              review.images.allSatisfy({ ImportRedirectPolicy.allowed($0.imageURL, images: true) && ImportRedirectPolicy.allowed($0.previewURL, images: true) &&
                  $0.id.count <= 100 && !$0.id.isEmpty && $0.id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) }) else { throw CorkError("The saved review is invalid. Discard it before starting another import.") }
        return review
    }
    public func save(_ review: ImportReview) throws {
        try prepare()
        let data = try JSONEncoder().encode(review)
        guard data.count < 40_000_000 else { throw CorkError("The import review is too large.") }
        let url = root.appendingPathComponent("review.json")
        try data.write(to: url, options: [.atomic]); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func clearStaging() throws {
        let stage = root.appendingPathComponent("Staging")
        if FileManager.default.fileExists(atPath: stage.path) { try FileManager.default.removeItem(at: stage) }
    }
    public func discard() throws {
        try clearStaging()
        let url = root.appendingPathComponent("review.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    public func stage(_ image: PinterestImage, bytes: Data) throws -> (URL, [String], ImageColourProfile) {
        try Task.checkCancellation(); try prepare()
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        guard (available ?? 0) > 1_000_000_000 else { throw CorkError("Less than 1 GB of free space remains. This import is paused; your review and completed images are saved.") }
        guard bytes.count <= 32_000_000, let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double, let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0, width * height <= 100_000_000,
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) else {
            throw CorkError("A selected pin is not a supported image under 32 MB and 100 megapixels. Remove it from the review to continue.")
        }
        let palette = try PaletteAnalysis.colours(image: bitmap), profile = try PaletteAnalysis.profile(image: bitmap)
        let stage = root.appendingPathComponent("Staging")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = stage.appendingPathComponent(image.id + ".jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw CorkError("Could not stage an image for Cork.") }
        CGImageDestinationAddImage(destination, bitmap, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CorkError("Could not finish the staged image.") }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return (url, palette, profile)
    }
    public func manifest(_ value: JSONValue) throws -> URL {
        try prepare()
        let url = root.appendingPathComponent("Staging/collection.json")
        try value.data().write(to: url, options: [.atomic]); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
}

public protocol CorkImportDestination: Sendable {
    func call(_ method: String, arguments: [String: JSONValue]) async throws -> JSONValue
}
public actor NativeCorkDestination: CorkImportDestination {
    private let path: String
    public init(path: String = CorkPaths.socketPath) { self.path = path }
    public func call(_ method: String, arguments: [String: JSONValue] = [:]) throws -> JSONValue {
        let response = try LocalConnection.call(.object(["method": .string(method), "arguments": .object(arguments)]), path: path)
        let message = response["content"]?.array?.first?["text"]?.string ?? "Cork returned an unreadable response."
        if response["isError"]?.bool == true { throw CorkError(message) }
        return try JSONDecoder().decode(JSONValue.self, from: Data(message.utf8))
    }
}

public actor ImportCoordinator {
    public let store: ImportSessionStore
    private let destination: any CorkImportDestination
    private let images: any ImportHTTP
    public init(store: ImportSessionStore, destination: any CorkImportDestination = NativeCorkDestination(), images: any ImportHTTP = NativeImportHTTP()) {
        self.store = store; self.destination = destination; self.images = images
    }
    public func status() async throws -> JSONValue { try await destination.call("cork_get_collection", arguments: ["limit": .number(1)]) }
    public func transfer(_ initial: ImportReview, progress: @Sendable (ImportReview, String) async -> Void) async throws -> ImportReview {
        var review = initial
        // Any batch whose reply was lost is reconciled by stable ID/source URL before another write.
        for start in stride(from: 0, to: review.keepers.count, by: 10) {
            try Task.checkCancellation()
            let batch = Array(review.keepers.dropFirst(start).prefix(10))
            let known = try await destination.call("cork_get_collection", arguments: ["include_metadata": .bool(true),
                "ids": .array(batch.map { .string($0.collectionID) }), "source_urls": .array(batch.map { .string($0.sourceURL) })])
            let existing = Set((known["photos"]?.array ?? []).compactMap { $0["sourceURL"]?.string })
            for pin in batch where existing.contains(pin.sourceURL) { review.committed.insert(pin.id) }
            // Recheck even locally committed IDs: Cork may have been restored since the import was interrupted.
            let pending = batch.filter { !existing.contains($0.sourceURL) }
            var entries: [JSONValue] = [], usedThemes: Set<String> = []
            do {
                try await store.clearStaging()
                for pin in pending {
                    try Task.checkCancellation()
                    await progress(review, "Downloading \(pin.title.isEmpty ? "pin \(pin.id)" : pin.title)…")
                    let reply = try await images.get(pin.imageURL, headers: [:], limit: 32_000_000)
                    guard (200..<300).contains(reply.status) else { throw CorkError("A selected pin could not be downloaded (HTTP \(reply.status)). Remove it or retry later.") }
                    let (file, palette, profile) = try await store.stage(pin, bytes: reply.data)
                    let moods = Self.moods(palette: palette, profile: profile); usedThemes.formUnion(moods)
                    let tags = ["pinterest"] + profile.colours.filter { $0.coverage >= 0.04 }.map { "\($0.family.rawValue):\($0.strength.rawValue)" }
                    entries.append(.object(["id": .string(pin.collectionID), "path": .string(file.path), "title": .string(pin.title),
                        "description": .string(pin.description), "sourceURL": .string(pin.sourceURL), "sourceBoard": .string(pin.boardName), "sourceBoardID": .string("pinterest-" + pin.boardID),
                        "tags": .array(tags.map(JSONValue.string)), "palette": .array(palette.map(JSONValue.string)), "themeIDs": .array(moods.map(JSONValue.string))]))
                }
                if !entries.isEmpty {
                    let themes = usedThemes.sorted().map { id -> JSONValue in
                        if let saved = known["themes"]?.array?.first(where: { $0["id"]?.string == id }) {
                            return .object(["id": .string(id), "name": saved["name"] ?? .string(id), "description": saved["description"] ?? .string("")])
                        }
                        let preset = ScenePalettes.all.first { $0.id == id }
                        return .object(["id": .string(id), "name": .string(preset?.name ?? "Your Pinterest"),
                            "description": .string(id == "pinterest-library" ? "Your selected pins across all imported boards." : "Pins grouped by measured image colours.")])
                    }
                    let manifest = try await store.manifest(.object(["schemaVersion": .number(1), "themes": .array(themes), "photos": .array(entries)]))
                    await progress(review, "Adding \(pending.count) images to Cork…")
                    // Never automatically replay this mutation after a timeout or ambiguous failure.
                    _ = try await destination.call("cork_import_collection", arguments: ["path": .string(manifest.path)])
                    for pin in pending { review.committed.insert(pin.id) }
                }
                try await store.save(review); try await store.clearStaging()
                await progress(review, "\(review.committed.intersection(Set(review.keepers.map(\.id))).count) of \(review.keepers.count) added")
            } catch {
                try? await store.save(review); try? await store.clearStaging()
                throw error
            }
        }
        return review
    }
    public static func moods(palette: [String], profile: ImageColourProfile) -> [String] {
        let ranked = ScenePalettes.all.filter { $0.majorColours == nil }.sorted { ColourMatch.score(palette, against: $0.colours) > ColourMatch.score(palette, against: $1.colours) }
        var result = ["pinterest-library"] + ranked.prefix(2).map(\.id)
        for scheme in ScenePalettes.all where scheme.majorColours != nil && ColourMatch.majorColourIndex(palette, scheme: scheme) != nil { result.append(scheme.id) }
        return result
    }
}

/// A small, in-memory preview cache. Full-size assets are downloaded only for keepers.
public actor ImportPreviewCache {
    private let http: any ImportHTTP
    private var cache: [URL: Data] = [:]
    private var order: [URL] = []
    private var size = 0
    public init(http: any ImportHTTP = NativeImportHTTP()) { self.http = http }
    public func image(_ url: URL) async throws -> Data {
        if let value = cache[url] { return value }
        let reply = try await http.get(url, headers: [:], limit: 4_000_000)
        guard (200..<300).contains(reply.status) else { throw CorkError("Preview unavailable") }
        while size + reply.data.count > 12_000_000, let first = order.first {
            size -= cache.removeValue(forKey: first)?.count ?? 0; order.removeFirst()
        }
        cache[url] = reply.data; order.append(url); size += reply.data.count
        return reply.data
    }
    public func clear() { cache.removeAll(); order.removeAll(); size = 0 }
}
