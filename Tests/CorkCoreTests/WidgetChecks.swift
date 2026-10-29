import Foundation
import CorkCore

private func widgetManifest(entry: String = "index.html") -> [String: Any] {
    ["schemaVersion": 1, "id": "test.toys", "name": "Test toys", "version": "1", "widgets": [
        ["id": "spinner", "name": "Spinner", "description": "A local toy", "entry": entry, "width": 260, "height": 220]
    ]]
}
@MainActor func widgetRegistrationOwnsResourcesAndPersistsMetadata() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkWidgets-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Source"), data = root.appendingPathComponent("Data")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("<html><body>Local toy</body></html>".utf8).write(to: source.appendingPathComponent("index.html"))
    let manifest = source.appendingPathComponent("manifest.json")
    try JSONSerialization.data(withJSONObject: widgetManifest()).write(to: manifest)
    let repository = BoardRepository(root: data), reference = WidgetReference(provider: "test.toys", widget: "spinner")
    let registered = try await repository.registerWidgets(at: manifest.path)
    try expect(registered.definition(reference)?.name == "Spinner" && registered.entryURL(reference, root: data) != nil)
    try FileManager.default.removeItem(at: source)
    try expect(registered.entryURL(reference, root: data) != nil)
    try expect(try await repository.loadWidgets() == registered)
}
@MainActor func widgetPackagesRejectTraversalLinksAndKeepPreviousRegistry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkWidgetValidation-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Source"), data = root.appendingPathComponent("Data")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let manifest = source.appendingPathComponent("manifest.json")
    try Data("<html>Safe</html>".utf8).write(to: source.appendingPathComponent("index.html"))
    try JSONSerialization.data(withJSONObject: widgetManifest()).write(to: manifest)
    let repository = BoardRepository(root: data), previous = try await repository.registerWidgets(at: manifest.path)
    try JSONSerialization.data(withJSONObject: widgetManifest(entry: "../outside.html")).write(to: manifest)
    try await expectThrowsAsync { try await repository.registerWidgets(at: manifest.path) }
    try expect(try await repository.loadWidgets() == previous)
    try JSONSerialization.data(withJSONObject: widgetManifest()).write(to: manifest)
    try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("escape.js"), withDestinationURL: root.appendingPathComponent("outside.js"))
    try await expectThrowsAsync { try await repository.registerWidgets(at: manifest.path) }
    try expect(try await repository.loadWidgets() == previous)
}
@MainActor func widgetItemsPersistAndValidateStateWithoutBecomingPhotos() throws {
    var widget = PrintItem(assetFile: "", title: "Spinner", style: .flat, x: 80, y: 320, width: 260, height: 220, displayID: 1, kind: .widget)
    widget.widget = WidgetReference(provider: "test.toys", widget: "spinner"); widget.widgetState = .object(["angle": .number(2)])
    try widget.validate(); try expect(widget.isKept)
    var board = Board(); board.items = [widget]
    try expect(try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board)) == board)
    let changed = try board.applying([["id": .string(widget.id.uuidString), "widget_state": .object(["angle": .number(3)]), "hidden": .bool(true)]])
    try expect(changed.items[0].isHidden && changed.items[0].widgetState?["angle"]?.number == 3)
    try expectThrows { try board.applying([["id": .string(widget.id.uuidString), "rotation": .number(20)]]) }
    try expectThrows { try board.applying([["id": .string(widget.id.uuidString), "widget_state": .object(["large": .string(String(repeating: "x", count: 65_000))])]]) }
    try CorkTools.validate(name: "cork_register_widgets", arguments: ["path": .string("/Applications/Test.app/manifest.json")])
    try CorkTools.validate(name: "cork_add_widget", arguments: ["provider": .string("test.toys"), "widget": .string("spinner")])
}

@MainActor func newWidgetsChooseSeparateSpaceAroundFixedItems() throws {
    let display = DisplayInfo(id: 1, name: "Test", width: 1200, height: 850)
    var board = Board(); board.desktop.hideWidgets = true
    var first = PrintItem(assetFile: "", title: "First", style: .flat, x: 24, y: 48, width: 260, height: 230, displayID: 1, kind: .widget)
    first.widget = WidgetReference(provider: "test.toys", widget: "spinner")
    let note = PrintItem(assetFile: "", title: "Fixed note", style: .sticky, x: 304, y: 48, width: 260, height: 230, displayID: 1, kind: .note)
    var overlay = PrintItem(assetFile: "", title: "Overlay", style: .flat, x: 0, y: 0, width: 1200, height: 850, displayID: 1, kind: .note, includeInLayout: false)
    overlay.hidden = false
    let photo = PrintItem(assetFile: "sample.png", title: "Movable photo", x: 0, y: 0, width: 1200, height: 850, displayID: 1)
    board.items = [first, note, overlay, photo]
    func overlaps(_ a: PrintItem, _ b: PrintItem) -> Bool {
        a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y
    }
    for _ in 0..<3 {
        let point = try WidgetPlacement.position(in: board, display: display, width: 260, height: 230)
        var added = first; added.id = UUID(); added.x = point.x; added.y = point.y
        try expect(!board.items.filter { $0.kind == .widget || $0.id == note.id }.contains { overlaps(added, $0) })
        try expect(added.x >= display.safeX && added.y >= display.safeY && added.x + added.width <= display.safeX + display.safeWidth && added.y + added.height <= display.safeY + display.safeHeight)
        board.items.append(added)
    }
    var filled = Board(); var covering = note; covering.width = 1200; covering.height = 850; covering.x = 0; covering.y = 0; filled.items = [covering]
    try expectThrows { try WidgetPlacement.position(in: filled, display: display, width: 260, height: 230) }
    let explicit = try WidgetPlacement.position(in: filled, display: display, width: 260, height: 230, x: 70, y: 80)
    try expect(explicit.x == 70 && explicit.y == 80)
}
