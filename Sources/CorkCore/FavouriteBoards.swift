import Foundation

public struct FavouriteBoard: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var items: [PrintItem]
    public var wallpaper: WallpaperSettings
    public var scenes: SceneOptions
    public var rotation: WallRotationState?
    public var rotationTheme: String?
    public var displays: [DisplayInfo]?
    public init(board: Board, name: String, now: Date = Date()) {
        id = UUID(); self.name = name; createdAt = now; items = board.items
        wallpaper = board.desktop.wallpaper; scenes = board.desktop.sceneOptions
        rotation = board.rotation; rotationTheme = board.desktop.rotationTheme; displays = board.layoutDisplays
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120, createdAt.timeIntervalSince1970.isFinite else { throw CorkError("Give this board a name under 120 characters.") }
        var snapshot = Board(); snapshot.items = items; snapshot.desktop.wallpaper = wallpaper
        snapshot.desktop.scenes = scenes; snapshot.desktop.rotationTheme = rotationTheme; snapshot.rotation = rotation; snapshot.layoutDisplays = displays
        try snapshot.validate()
    }
    public func restoring(into current: Board) throws -> Board {
        try validate()
        var result = current
        result.items = items; result.desktop.wallpaper = wallpaper; result.desktop.scenes = scenes
        result.rotation = rotation; result.desktop.rotationTheme = rotationTheme; result.layoutDisplays = displays
        // Keyboard, schedule and visibility preferences belong to the person, not a saved collage.
        try result.validate(); return result
    }
}

public struct FavouriteBoards: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var boards: [FavouriteBoard] = []
    public init() {}
    public func validate() throws {
        guard schemaVersion == 1, boards.count <= 100, Set(boards.map(\.id)).count == boards.count else { throw CorkError("Keep up to 100 unique favourite boards.") }
        for board in boards { try board.validate() }
    }
}

extension BoardRepository {
    public func validateFavouriteMedia(_ favourite: FavouriteBoard) throws {
        for item in favourite.items where item.isVisualPrint {
            guard FileManager.default.fileExists(atPath: assets.appendingPathComponent(item.assetFile).path) else { throw CorkError("This favourite references a missing image. The current wall was preserved.") }
            if let video = item.video {
                guard FileManager.default.fileExists(atPath: assets.appendingPathComponent(video.file).path) else { throw CorkError("This favourite references a missing video. The current wall was preserved.") }
            }
        }
        for file in [favourite.wallpaper.assetFile, favourite.wallpaper.posterFile].compactMap({ $0 }) {
            guard FileManager.default.fileExists(atPath: wallpapers.appendingPathComponent(file).path) else { throw CorkError("This favourite's wallpaper is missing. The current wall was preserved.") }
        }
    }
    public func loadFavourites() throws -> FavouriteBoards {
        try prepare()
        let url = root.appendingPathComponent("favourites.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return FavouriteBoards() }
        func decode(_ url: URL) throws -> FavouriteBoards {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 25_000_000 else { throw CorkError("The favourite-board catalogue is too large.") }
            let value = try JSONDecoder().decode(FavouriteBoards.self, from: Data(contentsOf: url)); try value.validate(); return value
        }
        do { return try decode(url) }
        catch { return try decode(root.appendingPathComponent("favourites.previous.json")) }
    }
    public func saveFavourites(_ value: FavouriteBoards) throws {
        try value.validate(); try prepare()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= 25_000_000 else { throw CorkError("The favourite-board catalogue is full. Remove an older favourite first.") }
        let url = root.appendingPathComponent("favourites.json"), backup = root.appendingPathComponent("favourites.previous.json")
        if let old = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(FavouriteBoards.self, from: old), (try? decoded.validate()) != nil {
            try old.write(to: backup, options: [.atomic]); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try data.write(to: url, options: [.atomic]); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
