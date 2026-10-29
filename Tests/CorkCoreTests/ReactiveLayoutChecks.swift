import Foundation
import CoreGraphics
import CorkCore

private func reactiveCollection() -> PhotoCollection {
    var collection = PhotoCollection(); collection.themes = [.init(id: "blue-hour", name: "Blue", description: "Blue fixture")]
    for index in 0..<70 {
        collection.photos.append(.init(id: "r\(index)", assetFile: "r\(index).png", title: "", description: "Blue",
            sourceURL: "https://www.pinterest.com/pin/\(index)/", sourceBoard: "board-\(index % 6)", tags: [],
            palette: ["#6D81A8", "#2B3043", "#AFB4BF"], themeIDs: ["blue-hour"], imageWidth: index % 3 == 0 ? 1400 : 700, imageHeight: 1000))
    }
    return collection
}
private func reactiveBounds(_ item: PrintItem) -> CGRect {
    let a = item.rotation * .pi / 180, w = abs(cos(a)) * item.width + abs(sin(a)) * item.height, h = abs(sin(a)) * item.width + abs(cos(a)) * item.height
    return CGRect(x: item.x + (item.width - w) / 2, y: item.y + (item.height - h) / 2, width: w, height: h)
}
private func reactiveBoard() -> Board {
    var board = Board(); board.desktop.hideWidgets = true
    board.items = (0..<6).map { PrintItem(assetFile: "p\($0).png", title: "", width: 180, height: 240, rotation: Double($0) - 2, displayID: 1) }
    board.items.append(PrintItem(assetFile: "", title: "Keep", style: .sticky, x: 700, y: 300, width: 200, height: 160, displayID: 1, kind: .note, text: "My text"))
    return board
}
@MainActor func coordinateEditsAnchorItemsAndReflowTheSamePhotos() throws {
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    let board = reactiveBoard(), note = board.items.last!
    let moved = try BoardLayout.applyingCoordinateEdits(board, patches: [["id": .string(note.id.uuidString), "x": .number(330), "y": .number(370)]], displays: [display])
    try expect(moved.items.last?.x == 330 && moved.items.last?.y == 370 && moved.items.last?.text == note.text)
    for (old, new) in zip(board.items.dropLast(), moved.items.dropLast()) {
        try expect(old.id == new.id && old.assetFile == new.assetFile && old.style == new.style && old.rotation == new.rotation)
        try expect(abs(old.width / old.height - new.width / new.height) < 0.0001)
        try expect(!reactiveBounds(new).intersects(reactiveBounds(moved.items.last!)))
    }
    let image = moved.items[0]
    let movedImage = try BoardLayout.applyingCoordinateEdits(moved, patches: [["id": .string(image.id.uuidString), "x": .number(70), "y": .number(90)]], displays: [display])
    try expect(movedImage.items[0].x == 70 && movedImage.items[0].y == 90)
    try expect(movedImage.items.map(\.id) == board.items.map(\.id) && movedImage.items.last == moved.items.last)
    var history = BoardHistory(); history.record(moved); try expect(history.undo(current: movedImage) == moved)
}
@MainActor func overlayMovesAndUnchangedCoordinatesDoNotReflowPhotos() throws {
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    var board = reactiveBoard(); board.items[6].includeInLayout = false
    let note = board.items[6]
    let moved = try BoardLayout.applyingCoordinateEdits(board, patches: [["id": .string(note.id.uuidString), "x": .number(460)]], displays: [display])
    try expect(Array(moved.items.prefix(6)) == Array(board.items.prefix(6)) && moved.items[6].x == 460)
    let noop = try BoardLayout.applyingCoordinateEdits(board, patches: [["id": .string(board.items[0].id.uuidString), "x": .number(board.items[0].x)]], displays: [display])
    try expect(noop == board)
}
@MainActor func hiddenItemsReleaseSpaceAndSurviveRollsAndUndo() throws {
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    let board = reactiveBoard(), first = board.items[0]
    let hidden = try BoardLayout.applyingCoordinateEdits(board, patches: [["id": .string(first.id.uuidString), "hidden": .bool(true)]], displays: [display])
    try expect(hidden.items.count == board.items.count && hidden.items[0].isHidden && !hidden.itemsBackToFront.contains(where: { $0.id == first.id }))
    let rolled = try WallRotation.roll(hidden, collection: reactiveCollection(), display: display, seed: 42)
    try expect(rolled.items.contains(hidden.items[0]))
    let shown = try BoardLayout.applyingCoordinateEdits(hidden, patches: [["id": .string(first.id.uuidString), "hidden": .bool(false), "x": .number(60), "y": .number(80)]], displays: [display])
    try expect(!shown.items[0].isHidden && shown.items[0].x == 60 && shown.items[0].y == 80)
    try expect(try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(hidden)) == hidden)
    var history = BoardHistory(); history.record(board); try expect(history.undo(current: hidden) == board)
}
@MainActor func displayChangesFillMoreSpaceAndRefitSmallerCanvases() throws {
    let small = DisplayInfo(id: 1, name: "Test", width: 1280, height: 800), large = DisplayInfo(id: 1, name: "Test", width: 1920, height: 1240)
    let collection = reactiveCollection()
    var board = try WallRotation.roll(Board(), collection: collection, display: small, seed: 42)
    board.layoutDisplays = [small]
    let grown = try DisplayAdaptation.fit(board, displays: [large], collection: collection, wallpapers: WallpaperCollection())
    try expect(grown.items.count > board.items.count && Set(board.items.map(\.id)).isSubset(of: Set(grown.items.map(\.id))))
    let shrunk = try DisplayAdaptation.fit(grown, displays: [small], collection: collection, wallpapers: WallpaperCollection())
    let area = CGRect(x: small.safeX, y: small.safeY, width: small.safeWidth, height: small.safeHeight).insetBy(dx: -0.01, dy: -0.01)
    try expect(shrunk.items.filter { $0.kind == .image }.allSatisfy { area.contains(reactiveBounds($0)) })
    let again = try DisplayAdaptation.fit(shrunk, displays: [large], collection: collection, wallpapers: WallpaperCollection())
    let desired = max(8, Int((large.safeWidth * large.safeHeight / 78_000).rounded()))
    try expect(again.items.count <= desired && again.layoutDisplays == [large])
    try expect(try DisplayAdaptation.fit(again, displays: [large], collection: collection, wallpapers: WallpaperCollection()) == again)
}
@MainActor func automaticNotePaperMatchesPhotosAndRetainsTheManualColour() throws {
    var board = reactiveBoard(); board.items[0].colours = ["#6D81A8", "#2B3043"]
    let note = board.items[6]
    let matched = try BoardLayout.applyingCoordinateEdits(board, patches: [["id": .string(note.id.uuidString), "match_scene_colours": .bool(true)]], displays: [])
    let tinted = matched.items[6]; let rgb = UInt32((tinted.matchedNoteColour ?? "").dropFirst(), radix: 16) ?? 0
    try expect(tinted.matchSceneColours == true && rgb & 255 > (rgb >> 16) & 255)
    try expect(tinted.noteColor == note.noteColor && tinted.text == note.text && tinted.x == note.x)
    let manual = try BoardLayout.applyingCoordinateEdits(matched, patches: [["id": .string(note.id.uuidString), "match_scene_colours": .bool(false)]], displays: [])
    try expect(manual.items[6].noteColor == note.noteColor && manual.items[6].matchSceneColours == false)
}
