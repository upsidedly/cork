import Foundation

public struct CollectionWallpaper: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var assetFile: String
    public var title: String
    public var sourceURL: String
    public var sourceBoard: String
    public var palette: [String]
    public var themeIDs: [String]
    public var width: Double
    public var height: Double
    public var automatic: Bool?
    public var colourProfile: ImageColourProfile?
    public init(id: String, assetFile: String, title: String, sourceURL: String, sourceBoard: String,
                palette: [String], themeIDs: [String], width: Double, height: Double, automatic: Bool? = nil, colourProfile: ImageColourProfile? = nil) {
        self.id = id; self.assetFile = assetFile; self.title = title; self.sourceURL = sourceURL; self.sourceBoard = sourceBoard
        self.palette = palette; self.themeIDs = themeIDs; self.width = width; self.height = height
        self.automatic = automatic
        self.colourProfile = colourProfile
    }
    public func supports(_ display: DisplayInfo) -> Bool {
        guard display.scale.isFinite, display.scale > 0, display.width > 0, display.height > 0 else { return false }
        let native = min(width / (display.width * display.scale), height / (display.height * display.scale))
        let sourceRatio = width / height, displayRatio = display.width / display.height
        let visible = min(sourceRatio / displayRatio, displayRatio / sourceRatio)
        return native >= 1 && visible >= 0.60
    }
    public var settings: WallpaperSettings {
        var settings = WallpaperSettings(); settings.kind = .image; settings.assetFile = assetFile
        settings.sourceName = title; settings.sourceURL = sourceURL; settings.pixelWidth = width; settings.pixelHeight = height
        return settings
    }
}
public struct WallpaperCollection: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var wallpapers: [CollectionWallpaper] = []
    public init() {}
    public func validate() throws {
        guard schemaVersion == 1, wallpapers.count <= 100, Set(wallpapers.map(\.id)).count == wallpapers.count else { throw CorkError("Invalid or duplicate wallpaper collection.") }
        for wallpaper in wallpapers {
            guard !wallpaper.id.isEmpty, wallpaper.id.count <= 120, wallpaper.title.count <= 300,
                  wallpaper.sourceBoard.count <= 200, !wallpaper.sourceBoard.isEmpty,
                  wallpaper.sourceURL.count <= 8192, let source = URL(string: wallpaper.sourceURL), source.scheme == "https", source.host != nil,
                  (1...8).contains(wallpaper.palette.count), wallpaper.palette.allSatisfy(ColourMatch.isHex),
                  wallpaper.themeIDs.count <= 50, wallpaper.themeIDs.allSatisfy({ !$0.isEmpty && $0.count <= 80 }),
                  wallpaper.width.isFinite, wallpaper.height.isFinite, wallpaper.width > 0, wallpaper.height > 0,
                  wallpaper.width * wallpaper.height <= 100_000_000 else { throw CorkError("Invalid wallpaper metadata.") }
            try wallpaper.settings.validate()
            try wallpaper.colourProfile?.validate()
        }
    }
    func choose(scheme: ColourScheme, mood: String, display: DisplayInfo, previous: String?, imagePalettes: [[String]] = [],
                imageProfiles: [ImageColourProfile] = [], random: inout WallRotation.Generator) -> CollectionWallpaper? {
        if let pair = scheme.colourFamilies, let primary = pair.first {
            let ranked = wallpapers.compactMap { item -> (CollectionWallpaper, Double)? in
                guard item.automatic != false, item.supports(display), let profile = item.colourProfile,
                      let dominant = profile.dominantFamily else { return nil }
                var affinity = 0.45
                if dominant == primary {
                    guard profile.matches(pair, strength: .strong), imageProfiles.isEmpty ||
                        imageProfiles.filter({ $0.coverage(dominant) >= 0.04 }).count >= max(1, Int(ceil(Double(imageProfiles.count) * 0.20))) else { return nil }
                    affinity = 1 + profile.coverage(dominant) * 0.12
                } else {
                    guard dominant.isNeutral else { return nil }
                    // Quiet neutral paper can carry the dominant colour as an
                    // accent. The secondary colour cannot take over the backdrop.
                    guard profile.coverage(primary) >= 0.10, profile.matches(pair, strength: .strongAndAccents),
                          imageProfiles.isEmpty || imageProfiles.filter({ $0.coverage(primary) >= 0.04 }).count >= max(1, Int(ceil(Double(imageProfiles.count) * 0.20))) else { return nil }
                    affinity = 0.88 + profile.coverage(primary) * 0.1
                }
                return (item, affinity + (item.id != previous ? 0.02 : 0))
            }.sorted { $0.1 > $1.1 }
            guard let first = ranked.first else { return nil }
            return ranked.prefix(3).filter { $0.1 >= first.1 - 0.025 }.randomElement(using: &random)?.0
        }
        let ranked = wallpapers.filter {
            $0.automatic != false && $0.supports(display) && ColourMatch.backgroundScore($0.palette, against: scheme.colours) >= 0.55
                && ColourMatch.wallpaperHueAffinity($0.palette, imagePalettes: imagePalettes, majorColours: scheme.majorColours) > 0
        }.map { item in
            (item, ColourMatch.backgroundScore(item.palette, against: scheme.colours)
                + ColourMatch.wallpaperHueAffinity(item.palette, imagePalettes: imagePalettes, majorColours: scheme.majorColours) * 0.16
                + (item.themeIDs.contains(mood) ? 0.04 : 0) + (item.id != previous ? 0.02 : 0))
        }.sorted { $0.1 > $1.1 }
        guard let first = ranked.first else { return nil }
        let choices = ranked.prefix(3).filter { $0.1 >= first.1 - 0.025 }
        return choices.randomElement(using: &random)?.0
    }
}
public struct WallpaperImport: Codable, Sendable {
    public var schemaVersion: Int
    public var wallpapers: [WallpaperImportEntry]
}
public struct WallpaperImportEntry: Codable, Sendable {
    public var id: String
    public var path: String
    public var title: String
    public var sourceURL: String
    public var sourceBoard: String
    public var themeIDs: [String]
    public var automatic: Bool?
}
