import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import CorkCore

@MainActor private func videoFixture(at url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 96, AVVideoHeightKey: 64])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 96, kCVPixelBufferHeightKey as String: 64])
    writer.add(input)
    guard writer.startWriting() else { throw CheckFailure(description: "Could not create video fixture") }
    writer.startSession(atSourceTime: .zero)
    for index in 0..<20 {
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        guard input.isReadyForMoreMediaData else { throw CheckFailure(description: "Video writer stalled") }
        var pixel: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 96, 64, kCVPixelFormatType_32BGRA, nil, &pixel) == kCVReturnSuccess,
              let pixel else { throw CheckFailure(description: "Could not create frame") }
        CVPixelBufferLockBaseAddress(pixel, [])
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 96, height: 64, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            CVPixelBufferUnlockBaseAddress(pixel, []); throw CheckFailure(description: "Could not draw frame")
        }
        context.setFillColor(CGColor(red: index < 10 ? 1 : 0, green: 0, blue: index < 10 ? 0 : 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
        CVPixelBufferUnlockBaseAddress(pixel, [])
        guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 10)) else {
            throw CheckFailure(description: "Could not append frame")
        }
    }
    input.markAsFinished(); await writer.finishWriting()
    try expect(writer.status == .completed)
}

private func videoDescriptor(_ family: ColourFamily = .blue, motion: ColourFamily? = nil) -> VideoAttachment {
    VideoAttachment(file: "clip.mp4", duration: 2, posterTime: 0.5,
        colourSamples: [ImageColourProfile(coverages: [family: 1]), ImageColourProfile(coverages: [motion ?? family: 1])])
}

@MainActor func videosMigrateValidateAndPersistWithFavourites() throws {
    var item = PrintItem(assetFile: "cover.png", title: "", kind: .video); item.video = videoDescriptor()
    var board = Board(); board.items = [item]; try board.validate()
    try expect(try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board)) == board)
    let favourite = FavouriteBoard(board: board, name: "Motion")
    try expect(try favourite.restoring(into: Board()).items == [item])
    let legacy = PrintItem(assetFile: "photo.png", title: "Photo")
    try expect(try JSONDecoder().decode(PrintItem.self, from: JSONEncoder().encode(legacy)).video == nil)
    var bad = item; bad.video = nil; try expectThrows { try bad.validate() }
    bad = item; bad.video?.file = "../escape.mp4"; try expectThrows { try bad.validate() }
    bad = item; bad.video?.duration = .infinity; try expectThrows { try bad.validate() }
    bad = item; bad.kind = .image; try expectThrows { try bad.validate() }
    var restyled = item; try restyled.apply(["style": .string("polaroid"), "keep_in_place": .bool(true)])
    try expect(restyled.isKept && restyled.height == PrintStyle.polaroid.printSize(imageWidth: item.imageWidth, imageHeight: item.imageHeight, width: item.width).1)
    try CorkTools.validate(name: "cork_add_video", arguments: ["path": .string("/tmp/clip.mov"), "style": .string("frame")])
    try expectThrows { try CorkTools.validate(name: "cork_add_video", arguments: ["path": .string("/tmp/clip.mov"), "style": .string("sticky")]) }
}

@MainActor func videoImportOwnsCoverAndMeasuresSpreadOutFrames() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkVideo-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.mov"); try await videoFixture(at: source)
    let repository = BoardRepository(root: root.appendingPathComponent("data"))
    let asset = try await repository.importVideo(at: source.path)
    guard let video = asset.video, let profile = asset.colourProfile else { throw CheckFailure(description: "Missing video metadata") }
    try expect(asset.width == 96 && asset.height == 64 && video.colourSamples.count == 5)
    try expect(profile.coverage(.red) > 0.9 && (video.colourSamples.last?.coverage(.blue) ?? 0) > 0.9)
    try expect(video.matches([.red, .blue], strength: .strong))
    try expect(!video.matches([.red, .yellow], strength: .strong))
    let orphan = try await repository.importVideo(at: source.path)
    await repository.discardUnreferencedImports([orphan])
    try expect(!FileManager.default.fileExists(atPath: repository.assets.appendingPathComponent(orphan.file).path))
    try expect(!FileManager.default.fileExists(atPath: repository.assets.appendingPathComponent(orphan.video?.file ?? "missing").path))
    try FileManager.default.removeItem(at: source)
    try expect(FileManager.default.fileExists(atPath: repository.assets.appendingPathComponent(asset.file).path))
    try expect(FileManager.default.fileExists(atPath: repository.assets.appendingPathComponent(video.file).path))
    var item = PrintItem(assetFile: asset.file, title: "", imageWidth: asset.width, imageHeight: asset.height, kind: .video)
    item.video = video; var board = Board(); board.items = [item]; try await repository.save(board)
    await repository.discardUnreferencedImports([asset])
    try await repository.validateFavouriteMedia(FavouriteBoard(board: board, name: "Owned"))
    try expect(try await repository.load().0 == board)
    try await expectThrowsAsync { try await repository.importVideo(at: "relative.mp4") }
}

@MainActor func videoCollectionImportsAreAtomicAndReuseOwnedMedia() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkVideoCollection-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.mov"); try await videoFixture(at: source)
    let repository = BoardRepository(root: root.appendingPathComponent("data"))
    let manifest = root.appendingPathComponent("collection.json")
    func write(_ paths: [String]) throws {
        let photos = paths.enumerated().map { index, path in
            ["id": "video-\(index)", "kind": "video", "path": path, "title": "Test", "description": "Source",
             "sourceURL": "https://www.tiktok.com/@fixture/video/\(123450 + index)", "sourceBoard": "TikTok · fixture",
             "tags": ["nature"], "palette": ["#00FF00"], "themeIDs": ["air"]] as [String: Any]
        }
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "themes": [["id": "air", "name": "Air", "description": "Outdoors"]], "photos": photos]).write(to: manifest)
    }
    try write([source.path, root.appendingPathComponent("missing.mov").path])
    do { _ = try await repository.importCollection(at: manifest.path); throw CheckFailure(description: "Bad batch committed") }
    catch is CheckFailure { throw CheckFailure(description: "Bad batch committed") } catch {}
    try expect(try await repository.loadCollection().0.photos.isEmpty)
    try expect(try FileManager.default.contentsOfDirectory(atPath: repository.assets.path).isEmpty)
    try write([source.path]); let first = try await repository.importCollection(at: manifest.path)
    let files = try FileManager.default.contentsOfDirectory(atPath: repository.assets.path).sorted()
    try FileManager.default.removeItem(at: source)
    let second = try await repository.importCollection(at: manifest.path)
    try expect(first == second && second.photos[0].video != nil && (second.photos[0].colourProfile?.coverage(.red) ?? 0) > 0.9)
    try expect(second.photos[0].palette != ["#00FF00"])
    try expect(try FileManager.default.contentsOfDirectory(atPath: repository.assets.path).sorted() == files)
    var board = Board()
    let saved = second.photos[0]
    var item = PrintItem(assetFile: saved.assetFile, title: "", kind: .video); item.video = saved.video
    board.items = [item]; try await repository.save(board)
    try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "themes": [], "photos": [], "removeIDs": [saved.id]]).write(to: manifest)
    let excluded = try await repository.importCollection(at: manifest.path)
    try expect(excluded.photos.isEmpty && excluded.themes == second.themes)
    try expect(try await repository.load().0 == board)
    try expect(try FileManager.default.contentsOfDirectory(atPath: repository.assets.path).sorted() == files)
    do { _ = try await repository.importCollection(at: manifest.path); throw CheckFailure(description: "Unknown removal committed") }
    catch is CheckFailure { throw CheckFailure(description: "Unknown removal committed") } catch {}
    try expect(try await repository.loadCollection().0 == excluded)
}

private func videoCollection() -> PhotoCollection {
    var result = PhotoCollection(); result.themes = [.init(id: "air", name: "Air", description: "Outdoors")]
    for index in 0..<36 {
        let family: ColourFamily = index % 2 == 0 ? .blue : .yellow
        let id = "clip-\(index)"
        result.photos.append(.init(id: id, assetFile: id + ".png", title: "Metadata", description: "Source",
            sourceURL: "https://example.com/\(id)", sourceBoard: "source-\(index % 5)", tags: [], palette: [family.hex], themeIDs: ["air"],
            imageWidth: index % 3 == 0 ? 1200 : 700, imageHeight: 1000, colourProfile: .init(coverages: [family: 1]),
            video: index % 3 == 0 ? nil : videoDescriptor(family)))
    }
    return result
}

@MainActor func videoLayoutsRespectColoursAnchorsVisibilityAndDisplayChanges() throws {
    var collection = videoCollection(), board = Board(), options = SceneOptions()
    options.colourPair = [.colour(.blue), .colour(.yellow)]; board.desktop.scenes = options
    var rejected = collection.photos[0]; rejected.id = "pink-motion"; rejected.assetFile = "pink-motion.png"
    rejected.sourceURL = "https://example.com/pink-motion"; rejected.video = videoDescriptor(.blue, motion: .pink)
    collection.photos.append(rejected)
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    let rolled = try WallRotation.roll(board, collection: collection, display: display, seed: 42)
    try expect(rolled.items.contains { $0.kind == .video } && rolled.items.allSatisfy { $0.assetFile != rejected.assetFile && $0.title.isEmpty })
    try expect(rolled.items.allSatisfy { $0.video?.matches([.blue, .yellow], strength: .strong) ?? true })
    var placed = rolled; placed.items = Array(rolled.items.prefix(2)); placed.items[0].keepInPlace = true
    let filled = try WallRotation.fillEmpty(placed, collection: collection, display: display, seed: 43)
    try expect(placed.items.allSatisfy { anchor in filled.items.contains(anchor) })
    let moved = try BoardLayout.applyingCoordinateEdits(filled, patches: [["id": .string(filled.items[0].id.uuidString), "x": .number(filled.items[0].x + 4)]], displays: [display])
    try expect(Set(moved.items.map(\.id)) == Set(filled.items.map(\.id)))
    for item in moved.items { try expect(item.video == filled.items.first(where: { $0.id == item.id })?.video) }
    var hidden = moved; hidden.items[0].hidden = true
    let rerolled = try WallRotation.roll(hidden, collection: collection, display: display, seed: 44)
    try expect(rerolled.items.contains(hidden.items[0]))
    var fitting = filled; fitting.layoutDisplays = [display]
    let smaller = DisplayInfo(id: 1, name: "Test", width: 1280, height: 900)
    let fitted = try DisplayAdaptation.fit(fitting, displays: [smaller], collection: collection, wallpapers: WallpaperCollection())
    try expect(Set(fitted.items.map(\.id)) == Set(filled.items.map(\.id)))
    for item in fitted.items { try expect(item.video == filled.items.first(where: { $0.id == item.id })?.video) }
}

@MainActor func randomPairsRejectVideosWhoseMotionNeedsAnotherColour() throws {
    var collection = videoCollection()
    for index in collection.photos.indices {
        let family: ColourFamily = index % 2 == 0 ? .yellow : .green
        collection.photos[index].palette = [family.hex]
        collection.photos[index].colourProfile = .init(coverages: [family: 1]); collection.photos[index].video = nil
    }
    for index in 0..<20 {
        var photo = collection.photos[index]; photo.id = "bad-\(index)"; photo.assetFile = "bad-\(index).png"
        photo.sourceURL = "https://example.com/bad-\(index)"; photo.palette = [ColourFamily.blue.hex]
        photo.colourProfile = .init(coverages: [.blue: 1]); photo.video = videoDescriptor(.blue, motion: .pink)
        collection.photos.append(photo)
    }
    let choices: [ColourChoice] = [.colour(.yellow), .random]
    let pairs = ColourPairSelection.availablePairs(choices: choices, candidates: collection.photos.compactMap(\.colourCandidate), strength: .strong)
    try expect(pairs == [[.yellow, .green]])
    var board = Board(), options = SceneOptions(); options.colourPair = choices; board.desktop.scenes = options
    for seed in UInt64(1)...4 {
        let rolled = try WallRotation.roll(board, collection: collection, display: DisplayInfo(id: 1, name: "Test", width: 1512, height: 982), seed: seed)
        try expect(rolled.rotation?.scheme?.colourFamilies == [.yellow, .green])
    }
}
