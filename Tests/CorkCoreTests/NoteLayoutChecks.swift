import Foundation
import CorkCore

@MainActor func noteLayoutChoiceMigratesPersistsAndValidates() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkNoteLayout-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = BoardRepository(root: root)
    var board = Board()
    let note = PrintItem(assetFile: "", title: "Keep", style: .sticky, kind: .note, text: "My note")
    board.items = [note]
    let legacy = try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board))
    try expect(legacy.items[0].includeInLayout == nil && !legacy.items[0].isOverlayNote)
    let patch: [String: JSONValue] = ["id": .string(note.id.uuidString), "include_in_layout": .bool(false)]
    let changed = try board.applying([patch])
    try expect(changed.items[0].isOverlayNote && changed.items[0].text == note.text)
    try await repository.save(changed)
    try expect(try await repository.load().0 == changed)
    var history = BoardHistory(); history.record(board)
    try expect(history.undo(current: changed) == board)
    let restored = try changed.applying([["id": .string(note.id.uuidString), "include_in_layout": .bool(true)]])
    try expect(!restored.items[0].isOverlayNote)
    try expectThrows { try board.applying([["id": .string(note.id.uuidString), "include_in_layout": .string("false")]]) }
    var image = PrintItem(assetFile: "image.png", title: "")
    try expectThrows { try image.apply(["include_in_layout": .bool(false)]) }
    try CorkTools.validate(name: "cork_add_note", arguments: ["text": .string("Keep"), "include_in_layout": .bool(false)])
    try CorkTools.validate(name: "cork_update_items", arguments: ["items": .array([.object(patch)])])
    try expectThrows { try CorkTools.validate(name: "cork_add_note", arguments: ["text": .string("Keep"), "include_in_layout": .string("false")]) }
}

@MainActor func overlayNotesReleaseSpaceWithoutMovingOrDeletingNotes() throws {
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    var board = Board(); board.desktop.hideWidgets = true
    let note = PrintItem(assetFile: "", title: "Keep", style: .sticky,
        x: display.safeX, y: display.safeY, width: display.safeWidth, height: display.safeHeight,
        displayID: 1, kind: .note, text: "Fixed position")
    board.items = [note] + (0..<6).map { PrintItem(assetFile: "p\($0).png", title: "", width: 180, height: 240, displayID: 1) }
    try expectThrows { try BoardLayout.arrange(board, display: display, layout: .greedy) }
    let overlay = try board.applying([["id": .string(note.id.uuidString), "include_in_layout": .bool(false)]])
    for layout in LayoutKind.allCases {
        let arranged = try BoardLayout.arrange(overlay, display: display, layout: layout)
        try expect(arranged.items[0] == overlay.items[0] && arranged.items.count == board.items.count)
        try expect(arranged.items.dropFirst().allSatisfy { $0.displayID == display.id })
        try expect(try BoardLayout.arrange(overlay, ids: [note.id], display: display, layout: layout) == overlay)
    }
    var collection = PhotoCollection()
    collection.themes = [.init(id: "golden-hour", name: "Warm", description: "Coherent fixture")]
    for index in 0..<32 {
        collection.photos.append(.init(id: "n\(index)", assetFile: "n\(index).png", title: "", description: "Test",
            sourceURL: "https://www.pinterest.com/pin/\(index)/", sourceBoard: "board-\(index % 5)",
            tags: [], palette: ["#85633C", "#EAD9B5"], themeIDs: ["golden-hour"],
            imageWidth: index % 3 == 0 ? 1400 : 700, imageHeight: 1000))
    }
    var onlyNote = board; onlyNote.items = [note]
    try expectThrows { try WallRotation.roll(onlyNote, collection: collection, display: display, seed: 42) }
    try expectThrows { try WallRotation.fillEmpty(onlyNote, collection: collection, display: display, seed: 42) }
    onlyNote.items[0].includeInLayout = false
    for result in [try WallRotation.roll(onlyNote, collection: collection, display: display, seed: 42),
                   try WallRotation.fillEmpty(onlyNote, collection: collection, display: display, seed: 42)] {
        try expect(result.items.count > 6 && result.items[0] == onlyNote.items[0])
        try expect(result.itemsBackToFront.last == onlyNote.items[0])
    }
    var flat = onlyNote; flat.items[0].style = .flat
    let filled = try WallRotation.fillEmpty(flat, collection: collection, display: display, seed: 42)
    try expect(filled.items[0] == flat.items[0] && filled.items.count > 6)
}

@MainActor func overlayNotesStayAboveNewerPhotosAndKeepTheirOwnOrder() throws {
    let ordinary = PrintItem(assetFile: "", title: "In layout", style: .sticky, zIndex: -500, kind: .note)
    let first = PrintItem(assetFile: "", title: "Overlay", style: .sticky, zIndex: -100, kind: .note, includeInLayout: false)
    let second = PrintItem(assetFile: "", title: "Flat overlay", style: .flat, zIndex: -50, kind: .note, includeInLayout: false)
    let image = PrintItem(assetFile: "new.png", title: "New photo", zIndex: 99_999)
    var board = Board(); board.items = [second, first, image, ordinary]
    try expect(board.itemsBackToFront.map(\.id) == [ordinary.id, image.id, first.id, second.id])
    let included = try board.applying([["id": .string(first.id.uuidString), "include_in_layout": .bool(true)]])
    try expect(included.itemsBackToFront.map(\.id) == [ordinary.id, first.id, image.id, second.id])
}
