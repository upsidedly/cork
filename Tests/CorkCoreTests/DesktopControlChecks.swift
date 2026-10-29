import Foundation
import CorkCore

private let anchors = [TrackpadContact(id: 1, x: 0.25, y: 0.3), TrackpadContact(id: 2, x: 0.65, y: 0.3)]
private func third(_ y: Double, x: Double = 0.45) -> [TrackpadContact] { anchors + [TrackpadContact(id: 3, x: x, y: y)] }
private func armed() -> AnchoredSwipeDetector {
    var detector = AnchoredSwipeDetector()
    _ = detector.process(device: 1, contacts: anchors, time: 0)
    _ = detector.process(device: 1, contacts: anchors, time: 0.16)
    return detector
}

@MainActor func desktopControlSettingsMigrateAndPersist() async throws {
    var board = Board(); board.items = [PrintItem(assetFile: "keep.png", title: "Keep", x: 200, y: 400)]
    let legacy = try JSONValue.encode(board).data()
    let loaded = try JSONDecoder().decode(Board.self, from: legacy)
    try expect(loaded.desktop.controls == nil && loaded.desktop.desktopControls.shortcut.display == "⌃⌥⌘M")
    var settings = DesktopControlSettings(); settings.shortcut = MinimizeShortcut(keyCode: 40, modifiers: 7, keyLabel: "K")
    settings.anchoredSwipeEnabled = false; board.desktop.controls = settings
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkControls-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = BoardRepository(root: root); try await repository.save(board)
    let restored = try await repository.load().0
    try expect(restored == board && restored.desktop.desktopControls.shortcut.display == "⌃⌥⌘K")
    try expect(restored.items == loaded.items)
    try expectThrows { try MinimizeShortcut(keyCode: 200).validate() }
    try expectThrows { try MinimizeShortcut(modifiers: 8).validate() }
    try expectThrows { try MinimizeShortcut(modifiers: 32).validate() }
    try expectThrows { try MinimizeShortcut(keyLabel: "\n").validate() }
    try CorkTools.validate(name: "cork_minimize_all_windows", arguments: [:])
    try expectThrows { try CorkTools.validate(name: "cork_minimize_all_windows", arguments: ["restore": .bool(true)]) }
}

@MainActor func anchoredThirdFingerSwipeFiresOnce() throws {
    var detector = armed()
    try expect(!detector.process(device: 1, contacts: third(0.8), time: 0.2))
    try expect(detector.process(device: 1, contacts: third(0.61), time: 0.35))
    try expect(!detector.process(device: 1, contacts: third(0.4), time: 0.4))
    try expect(!detector.process(device: 1, contacts: anchors, time: 0.45))
    try expect(!detector.process(device: 1, contacts: third(0.7), time: 0.5))
    try expect(!detector.process(device: 1, contacts: third(0.4), time: 0.6))
    try expect(!detector.process(device: 1, contacts: [], time: 0.7))
    try expect(!detector.process(device: 1, contacts: anchors, time: 0.8))
    try expect(!detector.process(device: 1, contacts: anchors, time: 1.0))
    try expect(!detector.process(device: 1, contacts: third(0.8), time: 1.1))
    try expect(detector.process(device: 1, contacts: third(0.6), time: 1.3))
    var resting = armed()
    try expect(!resting.process(device: 1, contacts: third(0.8), time: 5))
    try expect(resting.process(device: 1, contacts: third(0.6), time: 5.2))
}

@MainActor func anchoredSwipeRejectsNormalGestures() throws {
    var ordinary = AnchoredSwipeDetector()
    try expect(!ordinary.process(device: 1, contacts: third(0.8), time: 0))
    try expect(!ordinary.process(device: 1, contacts: third(0.5), time: 0.3))
    var moving = armed(); _ = moving.process(device: 1, contacts: third(0.8), time: 0.2)
    let moved = [TrackpadContact(id: 1, x: 0.25, y: 0.2), anchors[1], TrackpadContact(id: 3, x: 0.45, y: 0.5)]
    try expect(!moving.process(device: 1, contacts: moved, time: 0.4))
    var scrolling = armed()
    for n in 1...5 {
        let points = anchors.map { TrackpadContact(id: $0.id, x: $0.x, y: $0.y + Double(n) * 0.05) }
        try expect(!scrolling.process(device: 1, contacts: points, time: 0.2 + Double(n) * 0.1))
    }
    var sideways = armed(); _ = sideways.process(device: 1, contacts: third(0.8), time: 0.2)
    try expect(!sideways.process(device: 1, contacts: third(0.6, x: 0.7), time: 0.4))
    var upwards = armed(); _ = upwards.process(device: 1, contacts: third(0.7), time: 0.2)
    try expect(!upwards.process(device: 1, contacts: third(0.9), time: 0.4))
    var slow = armed(); _ = slow.process(device: 1, contacts: third(0.8), time: 0.2)
    try expect(!slow.process(device: 1, contacts: third(0.5), time: 1.2))
    var fourth = armed(); _ = fourth.process(device: 1, contacts: third(0.8), time: 0.2)
    try expect(!fourth.process(device: 1, contacts: third(0.5) + [TrackpadContact(id: 4, x: 0.9, y: 0.5)], time: 0.4))
}

@MainActor func anchoredSwipeResetsInvalidAndDisconnectedInput() throws {
    var detector = armed(); _ = detector.process(device: 1, contacts: third(0.8), time: 0.2)
    try expect(!detector.process(device: 2, contacts: third(0.5), time: 0.4))
    detector = armed(); _ = detector.process(device: 1, contacts: third(0.8), time: 0.2)
    try expect(!detector.process(device: 1, contacts: third(.nan), time: 0.3))
    try expect(!detector.process(device: 1, contacts: third(0.5), time: 0.4))
    detector = armed(); _ = detector.process(device: 1, contacts: third(0.8), time: 0.2)
    try expect(!detector.process(device: 1, contacts: third(0.5), time: 0.1))
    detector = armed(); try expect(!detector.process(device: 1, contacts: [anchors[0], anchors[0]], time: 0.3))
    try expect(!detector.process(device: 1, contacts: third(0.5), time: 0.4))
    detector.reset(); try expect(!detector.process(device: 1, contacts: third(0.5), time: 1))
}
