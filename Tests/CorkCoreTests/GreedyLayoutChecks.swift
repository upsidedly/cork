import Foundation
import CoreGraphics
import CorkCore

private func footprint(_ item: PrintItem) -> CGRect {
    let a = item.rotation * .pi / 180
    let w = abs(cos(a)) * item.width + abs(sin(a)) * item.height
    let h = abs(sin(a)) * item.width + abs(cos(a)) * item.height
    return CGRect(x: item.x + (item.width - w) / 2, y: item.y + (item.height - h) / 2, width: w, height: h)
}

/// Independent sweep over obstacle edges, not the packer's rectangle subtraction.
private func largestEmptyRectangle(in safe: CGRect, obstacles: [CGRect]) -> Double {
    let clipped = obstacles.map { $0.intersection(safe) }.filter { !$0.isNull }
    let xs = Array(Set([safe.minX, safe.maxX] + clipped.flatMap { [$0.minX, $0.maxX] })).sorted()
    var largest = 0.0
    for (offset, left) in xs.enumerated() {
        for right in xs.dropFirst(offset + 1) where right - left >= 80 {
            let intervals = clipped.filter { $0.minX < right - 0.01 && $0.maxX > left + 0.01 }.sorted { $0.minY < $1.minY }
            var y = safe.minY
            for rect in intervals {
                largest = max(largest, (right - left) * max(0, rect.minY - y))
                y = max(y, rect.maxY)
            }
            largest = max(largest, (right - left) * max(0, safe.maxY - y))
        }
    }
    return largest
}
private func usable(_ display: DisplayInfo) -> CGRect {
    CGRect(x: display.safeX, y: display.safeY, width: display.safeWidth, height: display.safeHeight)
}
private func widgetArea(_ display: DisplayInfo) -> CGRect {
    CGRect(x: display.safeX, y: display.safeY, width: display.safeWidth * 0.4, height: display.safeHeight * 0.2)
}
private func verifyPacking(_ board: Board, display: DisplayInfo) throws {
    let prints = board.items.filter { $0.kind == .image && $0.displayID == display.id }
    let safe = usable(display)
    for (offset, item) in prints.enumerated() {
        let box = footprint(item)
        try expect(safe.insetBy(dx: -0.01, dy: -0.01).contains(box))
        try expect(!box.intersects(widgetArea(display)))
        for other in prints.dropFirst(offset + 1) { try expect(!box.intersects(footprint(other))) }
        for note in board.items where note.kind == .note && (note.displayID == display.id || note.displayID == 0) {
            try expect(!box.intersects(footprint(note)))
        }
    }
}

@MainActor func greedyLayoutFillsLargeHolesAndPreservesIdentity() throws {
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982, safeX: 28, safeY: 62, safeWidth: 1456, safeHeight: 892)
    var board = Board()
    // This portrait-heavy eight-print wall previously left a whole empty row.
    for (offset, ratio) in [1.37, 0.70, 1.88, 1.49, 1.59, 1.32, 1.48, 1.75].enumerated() {
        board.items.append(PrintItem(assetFile: "\(offset).png", title: "", style: PrintStyle.imageStyles[offset % 4],
            x: 100 + Double(offset) * 80, y: 500, width: 210, height: 210 * ratio, displayID: 1))
    }
    let safe = usable(display)
    let before = largestEmptyRectangle(in: safe, obstacles: board.items.map(footprint) + [widgetArea(display)])
    let result = try BoardLayout.arrange(board, display: display, layout: .greedy, gap: 16)
    try verifyPacking(result, display: display)
    try expect(result.items.map(\.id) == board.items.map(\.id))
    for (old, new) in zip(board.items, result.items) {
        try expect(old.assetFile == new.assetFile && old.style == new.style && old.title == new.title)
        try expect(abs(old.width / old.height - new.width / new.height) < 0.00001)
    }
    let coverage = result.items.reduce(0) { $0 + $1.width * $1.height } / (safe.width * safe.height)
    let largest = largestEmptyRectangle(in: safe, obstacles: result.items.map(footprint) + [widgetArea(display)])
    try expect(coverage >= 0.65)
    try expect(largest < before * 0.3 && largest / (safe.width * safe.height) < 0.06)
    let repeated = try BoardLayout.arrange(board, display: display, layout: .greedy, gap: 16)
    try expect(repeated == result)
    var history = BoardHistory(); history.record(board)
    try expect(history.undo(current: result) == board)
}

@MainActor func greedyLayoutPreservesObstaclesAndRejectsImpossibleSpace() throws {
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    let note = PrintItem(assetFile: "", title: "Keep", style: .sticky, x: 60, y: 380, width: 190, height: 170,
                         rotation: 8, displayID: 1, kind: .note, text: "Do not move")
    let other = PrintItem(assetFile: "other.png", title: "Other display", displayID: 99)
    var board = Board(); board.items = [note, other] + (0..<7).map {
        PrintItem(assetFile: "\($0).png", title: "", style: .polaroid, width: 200, height: 270, displayID: 1)
    }
    let result = try BoardLayout.arrange(board, display: display, layout: .greedy, gap: 16)
    try verifyPacking(result, display: display)
    try expect(result.items[0] == note && result.items[1] == other)
    var blocked = board
    blocked.items[0].x = display.safeX; blocked.items[0].y = display.safeY
    blocked.items[0].width = display.safeWidth; blocked.items[0].height = display.safeHeight; blocked.items[0].rotation = 0
    try expectThrows { try BoardLayout.arrange(blocked, display: display, layout: .greedy) }
    try expect(board.items[0] == note)
    try expectThrows { try BoardLayout.arrange(board, display: DisplayInfo(id: 1, name: "Bad", width: .infinity, height: 900), layout: .greedy) }
    try CorkTools.validate(name: "cork_arrange", arguments: ["layout": .string("greedy")])
}

@MainActor func greedyRotationMatchesAspectsWithoutLargeEmptyRectangles() throws {
    var collection = PhotoCollection()
    collection.themes = [.init(id: "coherent", name: "Coherent", description: "One curated palette")]
    for index in 0..<32 {
        let ratio = [0.60, 0.72, 0.85, 1.0, 1.5, 2.6, 0.54, 0.68][index % 8]
        collection.photos.append(.init(id: "p\(index)", assetFile: "p\(index).png", title: "Metadata", description: "Metadata",
            sourceURL: "https://www.pinterest.com/pin/\(index)/", sourceBoard: "test", tags: ["quiet"], palette: ["#334455"],
            themeIDs: ["coherent"], imageWidth: 1000 * ratio, imageHeight: 1000))
    }
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    for seed in UInt64(0)...11 {
        let result = try WallRotation.roll(Board(), collection: collection, display: display, seed: seed)
        try verifyPacking(result, display: display)
        try expect(Set(result.items.map(\.style)) == Set(PrintStyle.imageStyles))
        try expect(result.items.allSatisfy { $0.title.isEmpty })
        try expect(Set(result.items.map(\.assetFile)).count == result.items.count)
        let safe = usable(display), occupied = result.items.map(footprint) + [widgetArea(display)]
        try expect(result.items.reduce(0) { $0 + $1.width * $1.height } / (safe.width * safe.height) > 0.65)
        try expect(largestEmptyRectangle(in: safe, obstacles: occupied) / (safe.width * safe.height) < 0.07)
        try expect(result.items.contains { $0.imageWidth / $0.imageHeight > 1.4 })
        try expect(result.items.contains { $0.imageWidth / $0.imageHeight < 0.8 })
        for item in result.items {
            let ratio = item.style.printSize(imageWidth: item.imageWidth, imageHeight: item.imageHeight, width: 1000).1 / 1000
            try expect(abs(item.height / item.width - ratio) < 0.00001)
        }
    }
}

@MainActor func rotationMixesBoardsWithinOneVisualMood() throws {
    var collection = PhotoCollection()
    collection.themes = [.init(id: "moss-paper", name: "Moss & paper", description: "A visual feel spanning unrelated boards")]
    let boards = ["nature", "interiors", "drawings", "instruments", "cars"]
    // An intentionally unbalanced pool must not become a wall dominated by its largest board.
    for index in 0..<48 {
        let board = index < 24 ? boards[0] : boards[1 + (index - 24) % 4]
        collection.photos.append(.init(id: "v\(index)", assetFile: "v\(index).png", title: "Metadata", description: "Metadata",
            sourceURL: "https://www.pinterest.com/pin/\(index)/", sourceBoard: board, tags: ["subject:\(board)"], palette: ["#334433", "#E7E0CF"],
            themeIDs: ["moss-paper"], imageWidth: index % 4 == 0 ? 1400 : 700, imageHeight: 1000))
    }
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    let lookup = Dictionary(uniqueKeysWithValues: collection.photos.map { ($0.assetFile, $0.sourceBoard) })
    for seed in UInt64(0)...11 {
        let result = try WallRotation.roll(Board(), collection: collection, display: display, seed: seed)
        let sources = result.items.compactMap { lookup[$0.assetFile] }
        let counts = Dictionary(grouping: sources, by: { $0 }).mapValues(\.count)
        try expect(counts.count >= 4)
        try expect((counts.values.max() ?? 0) <= Int(ceil(Double(sources.count) * 0.4)))
        try verifyPacking(result, display: display)
        try expect(Set(result.items.map(\.style)) == Set(PrintStyle.imageStyles))
        try expect(result.items.allSatisfy { $0.title.isEmpty })
    }
    // Collections with fewer source boards remain usable, without claiming extra variety.
    var two = collection
    for index in two.photos.indices { two.photos[index].sourceBoard = boards[index % 2] }
    let result = try WallRotation.roll(Board(), collection: two, display: display, seed: 1)
    let twoLookup = Dictionary(uniqueKeysWithValues: two.photos.map { ($0.assetFile, $0.sourceBoard) })
    try expect(Set(result.items.compactMap { twoLookup[$0.assetFile] }).count == 2)
}

@MainActor func greedyLayoutHandlesOverlappingAndOffscreenNotes() throws {
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    var board = Board()
    board.items = (0..<8).map { index in
        PrintItem(assetFile: "", title: "Keep \(index)", style: .sticky, x: 60, y: 450,
                  width: 400, height: 280, displayID: 1, kind: .note, text: "Overlapping notes")
    }
    board.items.append(PrintItem(assetFile: "", title: "Offscreen", style: .flat, x: 20_000, y: 20_000,
        width: 3000, height: 4000, displayID: 1, kind: .note, text: "Keep saved position"))
    board.items += (0..<7).map { PrintItem(assetFile: "i\($0).png", title: "", width: 200, height: 280, displayID: 1) }
    let result = try BoardLayout.arrange(board, display: display, layout: .greedy, gap: 16)
    try expect(Array(result.items.prefix(9)) == Array(board.items.prefix(9)))
    try verifyPacking(result, display: display)
    try expect(result.items.count == board.items.count)
}
