import Foundation

public struct CollectionTheme: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public init(id: String, name: String, description: String) { self.id = id; self.name = name; self.description = description }
}

/// Metadata is retained separately from wall captions, which are blank on a new roll.
public struct CollectionPhoto: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var assetFile: String
    public var title: String
    public var description: String
    public var sourceURL: String
    public var sourceBoard: String
    public var sourceBoardID: String?
    public var sourceIdentity: String { sourceBoardID ?? sourceBoard }
    public var tags: [String]
    public var palette: [String]
    public var themeIDs: [String]
    public var imageWidth: Double
    public var imageHeight: Double
    public var colourProfile: ImageColourProfile?
    public init(id: String, assetFile: String, title: String, description: String, sourceURL: String, sourceBoard: String,
                tags: [String], palette: [String], themeIDs: [String], imageWidth: Double, imageHeight: Double, colourProfile: ImageColourProfile? = nil, sourceBoardID: String? = nil) {
        self.id = id; self.assetFile = assetFile; self.title = title; self.description = description
        self.sourceURL = sourceURL; self.sourceBoard = sourceBoard; self.tags = tags; self.palette = palette; self.themeIDs = themeIDs
        self.imageWidth = imageWidth; self.imageHeight = imageHeight
        self.colourProfile = colourProfile
        self.sourceBoardID = sourceBoardID
    }
}

public struct PhotoCollection: Codable, Equatable, Sendable {
    public static let maximumPhotos = 20_000
    public var schemaVersion = 1
    public var themes: [CollectionTheme] = []
    public var photos: [CollectionPhoto] = []
    public init() {}
    public var eligibleThemes: [CollectionTheme] { themes.filter { theme in photos.filter { $0.themeIDs.contains(theme.id) }.count >= 8 } }
    public func validate() throws {
        guard schemaVersion == 1, photos.count <= Self.maximumPhotos, themes.count <= 50,
              Set(photos.map(\.id)).count == photos.count, Set(themes.map(\.id)).count == themes.count else { throw CorkError("Invalid or duplicate rotation collection entries.") }
        for theme in themes {
            guard !theme.id.isEmpty, theme.id.count <= 80, theme.name.count <= 120, theme.description.count <= 1000 else { throw CorkError("Invalid collection theme.") }
        }
        let themeIDs = Set(themes.map(\.id))
        for photo in photos {
            guard !photo.id.isEmpty, photo.id.count <= 120, photo.title.count <= 300, photo.description.count <= 2000,
                  !photo.sourceBoard.isEmpty, photo.sourceBoard.count <= 200, photo.tags.count <= 30,
                  photo.sourceBoardID.map({ !$0.isEmpty && $0.count <= 200 }) ?? true,
                  photo.tags.allSatisfy({ !$0.isEmpty && $0.count <= 100 }),
                  !photo.themeIDs.isEmpty, Set(photo.themeIDs).isSubset(of: themeIDs),
                  (1...8).contains(photo.palette.count), photo.palette.allSatisfy({ $0.count == 7 && $0.first == "#" && $0.dropFirst().allSatisfy(\.isHexDigit) }),
                  let source = URL(string: photo.sourceURL), source.scheme == "https", source.host != nil else { throw CorkError("Invalid source, palette, tags, or theme metadata for \(photo.id).") }
            try PrintItem(assetFile: photo.assetFile, title: photo.title, imageWidth: photo.imageWidth, imageHeight: photo.imageHeight).validate()
            try photo.colourProfile?.validate()
        }
    }
}

public struct CollectionImport: Codable, Sendable {
    public var schemaVersion: Int
    public var themes: [CollectionTheme]
    public var photos: [CollectionImportPhoto]
}

public struct CollectionImportPhoto: Codable, Sendable {
    public var id: String
    public var path: String
    public var title: String
    public var description: String
    public var sourceURL: String
    public var sourceBoard: String
    public var sourceBoardID: String?
    public var tags: [String]
    public var palette: [String]
    public var themeIDs: [String]
    public func saved(asset: ImportedAsset) -> CollectionPhoto {
        CollectionPhoto(id: id, assetFile: asset.file, title: title, description: description, sourceURL: sourceURL,
                        sourceBoard: sourceBoard, tags: tags, palette: palette, themeIDs: themeIDs, imageWidth: asset.width, imageHeight: asset.height, colourProfile: asset.colourProfile, sourceBoardID: sourceBoardID)
    }
}

public struct WallRotationState: Codable, Equatable, Sendable {
    public var themeID: String
    public var themeName: String
    public var seed: UInt64
    public var scheme: ColourScheme? = nil
    public var wallpaperID: String? = nil
    public var filled: Bool? = nil
    public var wallpaperMatched: Bool? = nil
}

public enum WallRotation {
    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var value = state
            value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
            value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
            return value ^ (value >> 31)
        }
    }

    public static func roll(_ board: Board, collection: PhotoCollection, display: DisplayInfo, themeID: String? = nil,
                            seed: UInt64, wallpapers: WallpaperCollection = WallpaperCollection(), paletteID: String? = nil,
                            colourAware: Bool? = nil) throws -> Board {
        try compose(board, collection: collection, display: display, themeID: themeID, seed: seed, wallpapers: wallpapers,
                    paletteID: paletteID, colourAware: colourAware, fillEmpty: false)
    }
    /// Existing items stay fixed. Participating items reserve space; overlay notes allow photos behind them.
    public static func fillEmpty(_ board: Board, collection: PhotoCollection, display: DisplayInfo, themeID: String? = nil,
                                 seed: UInt64, wallpapers: WallpaperCollection = WallpaperCollection(), paletteID: String? = nil,
                                 colourAware: Bool? = nil, maximumNewPhotos: Int = 20, allowNoNewPhotos: Bool = false) throws -> Board {
        try compose(board, collection: collection, display: display, themeID: themeID, seed: seed, wallpapers: wallpapers,
                    paletteID: paletteID, colourAware: colourAware, fillEmpty: true, maximumNewPhotos: maximumNewPhotos, allowNoNewPhotos: allowNoNewPhotos)
    }
    private static func compose(_ board: Board, collection: PhotoCollection, display: DisplayInfo, themeID: String?, seed: UInt64,
                                wallpapers: WallpaperCollection, paletteID: String?, colourAware: Bool?, fillEmpty: Bool,
                                maximumNewPhotos: Int = 20, allowNoNewPhotos: Bool = false) throws -> Board {
        try collection.validate(); try wallpapers.validate()
        if fillEmpty && maximumNewPhotos == 0 && allowNoNewPhotos { return board }
        if let paletteID, paletteID != "auto", !ScenePalettes.all.contains(where: { $0.id == paletteID }) { throw CorkError("Unknown colour palette.") }
        var random = Generator(state: seed)
        let options = board.desktop.sceneOptions, matchColours = colourAware ?? options.matchColours
        try options.validate()
        let customFamilies = matchColours && paletteID == nil ? options.colourPair : nil
        let retained = board.items.filter { fillEmpty || $0.kind != .image || $0.isHidden || $0.isKept || ($0.displayID != display.id && $0.displayID != 0) }
        let anchors = retained.filter { $0.kind == .image && !$0.isHidden && ($0.displayID == display.id || $0.displayID == 0) }
        func metadata(_ item: PrintItem) -> CollectionPhoto? {
            collection.photos.first { $0.assetFile == item.assetFile || (item.sourceURL != nil && $0.sourceURL == item.sourceURL) }
        }
        let anchorColours = anchors.compactMap { $0.colours ?? metadata($0)?.palette }
        let theme: CollectionTheme, scheme: ColourScheme
        if let customFamilies {
            scheme = try ScenePalettes.pair(customFamilies)
            theme = CollectionTheme(id: scheme.id, name: scheme.name, description: "Selected colours across the whole collection")
        } else {
            var themes = collection.eligibleThemes
            let requested = themeID == "auto" ? nil : themeID
            if let requested { themes = themes.filter { $0.id == requested } }
            else if fillEmpty, let current = board.rotation?.themeID, themes.contains(where: { $0.id == current }) { themes = themes.filter { $0.id == current } }
            else if themes.count > 1 && anchors.isEmpty { themes.removeAll { $0.id == board.rotation?.themeID } }
            guard let chosen = themes.randomElement(using: &random) else { throw CorkError("This mood needs at least eight photos. Import a rotation collection or choose another mood.") }
            theme = chosen
            scheme = ScenePalettes.choose(mood: theme.id, preferred: paletteID == "auto" ? nil : paletteID ?? options.paletteID,
                anchors: matchColours ? anchorColours : [], variation: random.next())
        }
        // Select the native-resolution backdrop before fitting photos to the same palette.
        var wallpaper = options.matchWallpaper ? wallpapers.choose(scheme: scheme, mood: theme.id, display: display,
                                                                   previous: board.rotation?.wallpaperID, random: &random) : nil
        let free = try GreedyPacking.spaces(display: display, obstacles: retained, gap: 16, hideWidgets: board.desktop.widgetsHidden)
        let onWall = Set(board.items.compactMap(\.sourceURL)), retainedAssets = Set(retained.map(\.assetFile))
        let retainedSources = Set(retained.compactMap(\.sourceURL))
        let raw = collection.photos.filter { (customFamilies != nil || $0.themeIDs.contains(theme.id)) && !retainedAssets.contains($0.assetFile) && !retainedSources.contains($0.sourceURL) }
        let matches = raw.filter { ColourMatch.score($0.palette, against: scheme.colours) >= 0.50 }
        let neededBoards = min(4, Set(raw.map(\.sourceIdentity)).count)
        let paired = matchColours && scheme.majorColours != nil
        var pool = matchColours && matches.count >= min(8, raw.count) && Set(matches.map(\.sourceIdentity)).count >= neededBoards ? matches : raw
        if let customFamilies {
            guard raw.allSatisfy({ $0.colourProfile != nil }) else { throw CorkError("Cork is still classifying the collection's colours. Try again when analysis finishes.") }
            pool = raw.filter { $0.colourProfile?.matches(customFamilies, strength: options.selectedStrength) == true }
            let profiles = pool.compactMap(\.colourProfile) + anchors.compactMap { $0.colourProfile ?? metadata($0)?.colourProfile }
            guard customFamilies.allSatisfy({ family in profiles.contains { $0.coverage(family) >= options.selectedStrength.minimumCoverage } }) else {
                throw CorkError("Not enough matching photos in both selected colours. Include accents or choose another combination.")
            }
        } else if paired {
            pool = raw.filter { ColourMatch.majorColourIndex($0.palette, scheme: scheme) != nil }
            let groups = Set((pool.map(\.palette) + anchorColours).compactMap { ColourMatch.majorColourIndex($0, scheme: scheme) })
            guard groups.count == 2 else { throw CorkError("This mood needs photos in both palette colours. Choose another mood or turn off Match image colours.") }
        }
        // A bounded, source-balanced sample keeps a large imported library responsive.
        // Shuffle before sampling so every photo remains eligible on later rolls.
        let shuffled = pool.shuffled(using: &random)
        let photos: [CollectionPhoto]
        if shuffled.count > 360 {
            var buckets = Dictionary(grouping: shuffled) { photo in
                let aspect = photo.imageWidth / photo.imageHeight < 0.8 ? "portrait" : photo.imageWidth / photo.imageHeight > 1.25 ? "wide" : "square"
                let group: Int?
                if let customFamilies, let profile = photo.colourProfile {
                    group = profile.coverage(customFamilies[0]) >= profile.coverage(customFamilies[1]) ? 0 : 1
                } else { group = paired ? ColourMatch.majorColourIndex(photo.palette, scheme: scheme) : nil }
                return photo.sourceIdentity + "|" + aspect + "|" + (group.map(String.init) ?? "all")
            }
            let keys = buckets.keys.sorted().shuffled(using: &random)
            var sample: [CollectionPhoto] = []
            while sample.count < 360 {
                var added = false
                for key in keys where sample.count < 360 {
                    if let photo = buckets[key]?.popLast() { sample.append(photo); added = true }
                }
                if !added { break }
            }
            photos = sample
        } else { photos = shuffled }
        let usable = max(0, GreedyPacking.availableArea(free))
        let target = min(max(0, maximumNewPhotos), photos.count, max(fillEmpty ? 1 : 8, min(20, Int((usable / 78_000).rounded()))))
        let initialSources = Dictionary(grouping: anchors.compactMap { metadata($0)?.sourceIdentity }, by: { $0 }).mapValues(\.count)
        let sourceCount = Set(photos.map(\.sourceIdentity)).count
        var initialColourAreas: [Int: Double] = [:]
        for anchor in anchors {
            if let customFamilies, let profile = anchor.colourProfile ?? metadata(anchor)?.colourProfile {
                for group in 0..<2 { initialColourAreas[group, default: 0] += GreedyPacking.bounds(anchor).area * profile.coverage(customFamilies[group]) }
            } else if let group = ColourMatch.majorColourIndex(anchor.colours ?? metadata(anchor)?.palette ?? [], scheme: scheme) {
                initialColourAreas[group, default: 0] += GreedyPacking.bounds(anchor).area
            }
        }
        func compositionScore(_ result: GreedyPacking.Result) -> Double {
            guard paired else { return result.score }
            var areas = initialColourAreas
            for placement in result.placements {
                if let weights = placement.candidate.effectiveColourWeights {
                    for group in 0..<2 { areas[group, default: 0] += placement.box.area * weights[group] }
                }
            }
            let total = areas.values.reduce(0, +)
            return result.score + usable * 0.35 * min(areas[0] ?? 0, areas[1] ?? 0) / max(1, total)
        }
        var best: GreedyPacking.Result?
        if usable >= 12_000 && target > 0 {
            for variant in 0..<6 {
                try Task.checkCancellation()
                var candidates: [GreedyPacking.Candidate] = []
                for (index, photo) in photos.enumerated() {
                    for style in PrintStyle.imageStyles.shuffled(using: &random) {
                        let ratio = style.printSize(imageWidth: photo.imageWidth, imageHeight: photo.imageHeight, width: 1000).1 / 1000
                        candidates.append(.init(index: index, ratio: ratio, style: style,
                            angle: Double.random(in: -3.5...3.5, using: &random), fresh: !onWall.contains(photo.sourceURL), source: photo.sourceIdentity,
                            affinity: matchColours ? ColourMatch.score(photo.palette, against: scheme.colours) : 0,
                            colourGroup: paired && customFamilies == nil ? ColourMatch.majorColourIndex(photo.palette, scheme: scheme) : nil,
                            colourWeights: customFamilies.flatMap { photo.colourProfile?.weights(for: $0) }))
                    }
                }
                let total = target + anchors.count
                var limit: Int? = sourceCount > 1 ? (sourceCount >= 3 ? max(2, total / 3) : max(2, Int(ceil(Double(total) * 0.6)))) : nil
                for _ in 0..<3 {
                    let result = GreedyPacking.pack(candidates: candidates, free: free, target: target, gap: 16,
                        availableArea: max(1, usable), variant: variant, mixStyles: true, sourceLimit: limit, initialSources: initialSources,
                        balanceColours: paired, initialColourAreas: initialColourAreas)
                    var counts = initialSources
                    for placement in result.placements { counts[placement.candidate.source, default: 0] += 1 }
                    let balanced = max(1, Int(ceil(Double(result.placements.count + anchors.count) * (sourceCount >= 3 ? 0.4 : 0.6))))
                    if sourceCount >= 2, counts.contains(where: { $0.value > max(balanced, initialSources[$0.key] ?? 0) }) {
                        limit = balanced; continue
                    }
                    let minimumNew = fillEmpty || !anchors.isEmpty ? 1 : min(6, target)
                    let minimumBoards = fillEmpty || !anchors.isEmpty ? 1 : min(3, sourceCount)
                    if result.placements.count >= minimumNew, counts.count >= minimumBoards,
                       best.map({ compositionScore(result) > compositionScore($0) }) ?? true { best = result }
                    break
                }
            }
        }
        if best == nil {
            if fillEmpty && !allowNoNewPhotos { throw CorkError("There is no empty space large enough for another print. Move or resize an item, then fill again.") }
            if !fillEmpty && anchors.isEmpty { throw CorkError("Cork could not fit a varied wall from this mood. Choose another mood or free some space around the notes.") }
        }
        var next = board; next.items = retained
        for placement in best?.placements ?? [] {
            let photo = photos[placement.candidate.index]
            var item = PrintItem(assetFile: photo.assetFile, title: "", style: placement.candidate.style,
                x: placement.x, y: placement.y, width: placement.width, height: placement.height,
                rotation: placement.candidate.angle, displayID: display.id,
                zIndex: (next.items.map(\.zIndex).max() ?? -1) + 1, sourceURL: photo.sourceURL,
                imageWidth: photo.imageWidth, imageHeight: photo.imageHeight)
            item.colours = photo.palette; item.colourProfile = photo.colourProfile; next.items.append(item)
        }
        if options.matchWallpaper {
            let visiblePalettes = next.items.filter { $0.kind == .image && !$0.isHidden && ($0.displayID == display.id || $0.displayID == 0) }
                .compactMap { $0.colours ?? metadata($0)?.palette }
            wallpaper = wallpapers.choose(scheme: scheme, mood: theme.id, display: display,
                previous: board.rotation?.wallpaperID, imagePalettes: visiblePalettes,
                imageProfiles: next.items.filter { $0.kind == .image && !$0.isHidden && ($0.displayID == display.id || $0.displayID == 0) }
                    .compactMap { $0.colourProfile ?? metadata($0)?.colourProfile }, random: &random)
        }
        if let wallpaper { next.desktop.wallpaper = wallpaper.settings }
        next.rotation = WallRotationState(themeID: theme.id, themeName: theme.name, seed: seed, scheme: scheme,
            wallpaperID: wallpaper?.id ?? board.rotation?.wallpaperID, filled: fillEmpty,
            wallpaperMatched: options.matchWallpaper ? wallpaper != nil : nil)
        next = NoteColours.refresh(next, displayID: display.id)
        try next.validate(); return next
    }
}
