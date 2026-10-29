import Foundation
import CorkCore

private func image(_ title: String = "Print") -> PrintItem {
    PrintItem(assetFile: "test.png", title: title)
}

@MainActor func batchEditIsAtomicAndRejectsStaleIdentity() throws {
    var board = Board(); board.items = [image("One"), image("Two")]
    let original = board
    try expectThrows {
        try board.applying([
            ["id": .string(board.items[0].id.uuidString), "x": .number(450)],
            ["id": .string(board.items[1].id.uuidString), "width": .number(-1)]
        ])
    }
    try expect(board == original)
    try expectThrows { try board.applying([["id": .string(UUID().uuidString), "x": .number(1)]]) }
    let duplicate = ["id": JSONValue.string(board.items[0].id.uuidString)]
    try expectThrows { try board.applying([duplicate, duplicate]) }
}

@MainActor func resizingPreservesRatioAndStyleChangesRecomputeDecoration() throws {
    let item = image(); var board = Board(); board.items = [item]
    let resized = try board.applying([["id": .string(item.id.uuidString), "width": .number(item.width * 2)]])
    try expect(resized.items[0].height == item.height * 2)
    let changed = try board.applying([["id": .string(item.id.uuidString), "style": .string("polaroid")]])
    try expect(changed.items[0].height == PrintStyle.polaroid.printSize(imageWidth: item.imageWidth, imageHeight: item.imageHeight, width: item.width).1)
}

@MainActor func notesRoundTripAndCannotBecomeImageTreatments() throws {
    var note = PrintItem(assetFile: "", title: "Today", style: .sticky, kind: .note, text: "Read\nSketch\nBuild", noteColor: .sage)
    try note.validate()
    let data = try JSONEncoder().encode(note)
    try expect(try JSONDecoder().decode(PrintItem.self, from: data) == note)
    try expectThrows { try note.apply(["style": .string("frame")]) }
    var flat = PrintItem(assetFile: "", title: "", style: .flat, kind: .note)
    try flat.apply(["text": .string("Hello"), "note_color": .string("blue")])
    try expect(flat.text == "Hello" && flat.noteColor == .blue)
    try expectThrows { try flat.apply(["text": .string(String(repeating: "x", count: 20_001))]) }
    var printItem = image()
    try expectThrows { try printItem.apply(["text": .string("wrong kind")]) }
}

@MainActor func allLayoutsFitRotatedPrintsInsideTheSafeArea() throws {
    var board = Board()
    board.items = (0..<7).map { index in
        PrintItem(assetFile: "\(index).png", title: "\(index)", width: 180 + Double(index) * 10,
                  height: 230 + Double(index) * 13, rotation: 20)
    }
    let display = DisplayInfo(id: 42, name: "Test", width: 1512, height: 982)
    for layout in LayoutKind.allCases {
        let arranged = try BoardLayout.arrange(board, display: display, layout: layout)
        try expect(arranged.items.map(\.id) == board.items.map(\.id))
        for item in arranged.items {
            let radians = abs(item.rotation) * .pi / 180
            let rotatedWidth = cos(radians) * item.width + sin(radians) * item.height
            let rotatedHeight = sin(radians) * item.width + cos(radians) * item.height
            let left = item.x + item.width / 2 - rotatedWidth / 2
            let top = item.y + item.height / 2 - rotatedHeight / 2
            try expect(left >= display.safeX - 0.01 && top >= display.safeY - 0.01)
            try expect(left + rotatedWidth <= display.safeX + display.safeWidth + 0.01)
            try expect(top + rotatedHeight <= display.safeY + display.safeHeight + 0.01)
            try expect(abs(item.width / item.height - board.items.first { $0.id == item.id }!.width / board.items.first { $0.id == item.id }!.height) < 0.0001)
        }
    }
}

@MainActor func selectionLayoutLeavesOtherDisplaysUntouched() throws {
    var board = Board(); board.items = [image("One"), image("Two")]
    let arranged = try BoardLayout.arrange(board, ids: [board.items[0].id], display: DisplayInfo(id: 9, name: "Screen", width: 1000, height: 800), layout: .gallery)
    try expect(arranged.items[1] == board.items[1])
    try expect(arranged.items[0].displayID == 9)
    try expectThrows { try BoardLayout.arrange(board, display: DisplayInfo(id: 9, name: "Tiny", width: 100, height: 100), layout: .grid) }
}

@MainActor func invalidAssetsAndUnboundedGeometryAreRejected() throws {
    for path in ["../image.png", "/tmp/image.png", "image.jpg", ".hidden.png"] {
        try expectThrows { try PrintItem(assetFile: path, title: "").validate() }
    }
    var item = image(); item.x = .infinity
    try expectThrows { try item.validate() }
}

@MainActor func undoRedoKeepsStableItemsAndBoundsHistory() throws {
    var history = BoardHistory(); var board = Board(); let first = board
    history.record(board); board.items = [image()]
    let populated = board
    try expect(history.undo(current: board) == first)
    try expect(history.redo(current: first) == populated)
    history.record(board)
    try expect(!history.canRedo)
    for _ in 0..<75 { history.record(board) }
    var count = 0
    while history.undo(current: board) != nil { count += 1 }
    try expect(count == 50)
}

@MainActor func persistenceRecoversThePreviousCompleteBoard() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = BoardRepository(root: root)
    var board = Board(); board.items = [image()]
    try await repository.save(board)
    var newer = board; newer.revision = 1; newer.items[0].x = 400
    try await repository.save(newer)
    try expect(try await repository.load().0 == newer)
    try Data("interrupted/corrupt".utf8).write(to: root.appendingPathComponent("board.json"))
    let recovered = try await repository.load()
    try expect(recovered.0 == board && recovered.1 != nil)
    var invalid = board; invalid.schemaVersion = 99
    try await expectThrowsAsync { try await repository.save(invalid) }
    try expect(try await repository.load().0 == board)
}

@MainActor func imageImportRejectsRelativeAndNonImageFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkImport-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = BoardRepository(root: root)
    try await expectThrowsAsync { try await repository.importImage(at: "relative.png") }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("fake.png"); try Data("not an image".utf8).write(to: file)
    try await expectThrowsAsync { try await repository.importImage(at: file.path) }
}

@MainActor func mcpLifecycleNotificationsAndToolErrors() throws {
    var dispatcher = MCPDispatcher()
    let call: (String, [String: JSONValue]) throws -> JSONValue = { _, _ in throw CorkError("App unavailable") }
    let list: JSONValue = .object(["jsonrpc": .string("2.0"), "id": .number(1), "method": .string("tools/list")])
    try expect(dispatcher.respond(list, call: call)?["error"]?["code"] == .number(-32002))
    let initRequest: JSONValue = .object(["jsonrpc": .string("2.0"), "id": .number(2), "method": .string("initialize"), "params": .object(["protocolVersion": .string("2025-11-25")])])
    try expect(dispatcher.respond(initRequest, call: call)?["result"]?["serverInfo"]?["name"] == .string("Cork"))
    try expect(dispatcher.respond(.object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]), call: call) == nil)
    try expect(dispatcher.respond(list, call: call)?["result"]?["tools"]?.array?.count == 22)
    let request: JSONValue = .object(["jsonrpc": .string("2.0"), "id": .number(3), "method": .string("tools/call"), "params": .object(["name": .string("cork_get_board")])])
    try expect(dispatcher.respond(request, call: call)?["result"]?["isError"] == .bool(true))
}

@MainActor func localSocketRoundTripAndPermissions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-socket-\(UUID().uuidString.prefix(8))")
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("c.sock").path
    let server = LocalServer(path: path)
    try server.start { request in request }
    defer { server.stop() }
    let request: JSONValue = .object(["hello": .string("Cork"), "array": .array([.number(1), .bool(true)])])
    let reply = try await Task.detached { try LocalConnection.call(request, path: path) }.value
    if reply != request { print("Socket reply: \(reply)") }
    try expect(reply == request)
    let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
    try expect(permissions == 0o600)
}
