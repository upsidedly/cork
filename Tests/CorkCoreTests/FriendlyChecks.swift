import Foundation
import CorkCore

@MainActor func favouritesRestoreSceneAndPreserveGlobalPreferences() throws {
    var saved = Board()
    saved.items = [PrintItem(assetFile: "", title: "Saved", style: .sticky, kind: .note, text: "Remember")]
    saved.desktop.scenes = SceneOptions(); saved.desktop.scenes?.colourPair = [.colour(.blue), .colour(.yellow)]
    saved.desktop.rotationTheme = "saved-mood"
    let favourite = FavouriteBoard(board: saved, name: "Blue day", now: Date(timeIntervalSince1970: 100))
    var current = Board(); current.desktop.hideDesktopFiles = true; current.desktop.hideWidgets = true
    var schedule = RandomizationSchedule(); schedule.frequency = .hour; current.desktop.randomizationSchedule = schedule
    let restored = try favourite.restoring(into: current)
    try expect(restored.items == saved.items && restored.desktop.scenes == saved.desktop.scenes && restored.desktop.rotationTheme == "saved-mood")
    try expect(restored.desktop.hideDesktopFiles && restored.desktop.widgetsHidden && restored.desktop.randomizationSchedule == schedule)
    try expect(restored.revision == current.revision)
    try expect(try JSONDecoder().decode(FavouriteBoard.self, from: JSONEncoder().encode(favourite)) == favourite)
    try expectThrows { try FavouriteBoard(board: saved, name: "  ").validate() }
}

@MainActor func favouritesPersistRecoverAndReuseMedia() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = BoardRepository(root: root)
    try expect(!(try await repository.load().0.desktop.hideDesktopFiles))
    var board = Board(); board.items = [PrintItem(assetFile: "missing.png", title: "Missing")]
    let missing = FavouriteBoard(board: board, name: "Missing asset")
    try await expectThrowsAsync { try await repository.validateFavouriteMedia(missing) }
    board.items = [PrintItem(assetFile: "", title: "Note", style: .sticky, kind: .note)]
    var favourites = FavouriteBoards(); favourites.boards = [FavouriteBoard(board: board, name: "One")]
    try await repository.saveFavourites(favourites)
    let first = try await repository.loadFavourites(); try expect(first == favourites)
    var next = favourites; next.boards.append(FavouriteBoard(board: board, name: "Two"))
    try await repository.saveFavourites(next)
    try Data("bad".utf8).write(to: root.appendingPathComponent("favourites.json"))
    try expect(try await repository.loadFavourites() == favourites)
    let contents = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Images").path)
    try expect(contents.isEmpty)
    let mode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("favourites.previous.json").path)[.posixPermissions] as? Int
    try expect(mode == 0o600)
}

@MainActor func randomizationSchedulesValidatePersistAndCalculate() throws {
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    var schedule = RandomizationSchedule()
    try expect(!schedule.enabled && (try schedule.next(after: now)) == nil)
    schedule.frequency = .minute; try expect(try schedule.next(after: now) == now.addingTimeInterval(60))
    schedule.frequency = .hour; try expect(try schedule.next(after: now) == now.addingTimeInterval(3600))
    schedule.frequency = .custom; schedule.every = 3; schedule.unit = .weeks
    try expect(try schedule.next(after: now) == now.addingTimeInterval(3 * 604800))
    let armed = try schedule.armed(after: now)
    var board = Board(); board.desktop.randomizationSchedule = armed
    try expect(try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board)) == board)
    schedule.every = 0; try expectThrows { try schedule.validate() }
    schedule.every = 1; schedule.frequency = .morningEvening; schedule.eveningHour = schedule.hour
    try expectThrows { try schedule.validate() }
    try expect(Board().desktop.randomizationSchedule == nil)
}

@MainActor func calendarSchedulesHandleLocalTimeAndDST() throws {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    var schedule = RandomizationSchedule(); schedule.frequency = .day; schedule.hour = 2; schedule.minute = 30
    let spring = try schedule.next(after: date(2026, 3, 7, 23), calendar: calendar)!
    let parts = calendar.dateComponents([.day, .hour], from: spring)
    try expect(parts.day == 8 && parts.hour == 3)
    schedule.frequency = .week; schedule.weekday = 2; schedule.hour = 8; schedule.minute = 0
    let weekly = try schedule.next(after: date(2026, 3, 8, 10), calendar: calendar)!
    try expect(calendar.component(.weekday, from: weekly) == 2 && calendar.component(.hour, from: weekly) == 8)
    schedule.frequency = .morningEvening
    let evening = try schedule.next(after: date(2026, 3, 8, 9), calendar: calendar)!
    try expect(evening == date(2026, 3, 8, 18))
    let morning = try schedule.next(after: evening, calendar: calendar)!
    try expect(morning == date(2026, 3, 9, 8))
}

@MainActor func scheduleDriverDefersCatchesUpOnceAndCancels() async throws {
    let driver = WallScheduleDriver(); defer { driver.stop() }
    var allowed = false, fires = 0
    driver.canRun = { allowed }
    var past = RandomizationSchedule(); past.frequency = .minute; past.nextRun = Date().addingTimeInterval(-86_400)
    driver.onFire = { value in
        fires += 1
        // Saving the next deadline must not cancel the roll performing that save.
        driver.apply(try value.armed(after: Date()))
        try Task.checkCancellation()
    }
    driver.apply(past)
    for _ in 0..<100 { await Task.yield() }
    try expect(fires == 0 && driver.problem != nil)
    allowed = true; driver.wake()
    for _ in 0..<200 { await Task.yield() }
    try expect(fires == 1 && !driver.running)
    driver.wake()
    for _ in 0..<100 { await Task.yield() }
    try expect(fires == 1)
    driver.apply(RandomizationSchedule())
    driver.apply(past); driver.stop()
    for _ in 0..<100 { await Task.yield() }
    try expect(fires == 1)
}

@MainActor func largeLibraryRemainsSeededAndSourceDiverse() throws {
    var collection = PhotoCollection(); collection.themes = [CollectionTheme(id: "library", name: "Library", description: "Fixture")]
    for index in 0..<1200 {
        collection.photos.append(CollectionPhoto(id: "large-\(index)", assetFile: "large-\(index).png", title: "", description: "", sourceURL: "https://www.pinterest.com/pin/\(index)/",
            sourceBoard: "board-\(index % 12)", tags: ["fixture"], palette: ["#335544", "#BBCCDD"], themeIDs: ["library"], imageWidth: 800, imageHeight: [500.0, 800, 1200][index % 3]))
    }
    try collection.validate()
    let display = DisplayInfo(id: 1, name: "Test", width: 1512, height: 982)
    let first = try WallRotation.roll(Board(), collection: collection, display: display, themeID: "library", seed: 73)
    let again = try WallRotation.roll(Board(), collection: collection, display: display, themeID: "library", seed: 73)
    try expect(first.items.map(\.sourceURL) == again.items.map(\.sourceURL))
    let sources = Set(first.items.compactMap { item in collection.photos.first(where: { $0.sourceURL == item.sourceURL })?.sourceBoard })
    try expect(first.items.count >= 6 && sources.count >= 3)
    let different = try WallRotation.roll(Board(), collection: collection, display: display, themeID: "library", seed: 74)
    try expect(Set(first.items.compactMap(\.sourceURL)) != Set(different.items.compactMap(\.sourceURL)))
    for index in collection.photos.indices { collection.photos[index].sourceBoard = "board-\(index % 2)" }
    let pair = try WallRotation.roll(Board(), collection: collection, display: display, themeID: "library", seed: 75)
    let counts = Dictionary(grouping: pair.items.compactMap { item in collection.photos.first(where: { $0.sourceURL == item.sourceURL })?.sourceBoard }, by: { $0 }).mapValues(\.count)
    try expect(counts.count == 2 && counts.values.allSatisfy { $0 <= Int(ceil(Double(pair.items.count) * 0.6)) })
    for index in collection.photos.indices {
        collection.photos[index].sourceBoardID = "stable-\(index % 2)"
        collection.photos[index].sourceBoard = "Renamed label \(index)"
    }
    let renamed = try WallRotation.roll(Board(), collection: collection, display: display, themeID: "library", seed: 75)
    let stableCounts = Dictionary(grouping: renamed.items.compactMap { item in collection.photos.first(where: { $0.sourceURL == item.sourceURL })?.sourceIdentity }, by: { $0 }).mapValues(\.count)
    try expect(stableCounts.count == 2 && stableCounts.values.allSatisfy { $0 <= Int(ceil(Double(renamed.items.count) * 0.6)) })
    for index in collection.photos.indices {
        let family: ColourFamily = index < 1196 ? .blue : .yellow
        collection.photos[index].palette = [family.hex]
        collection.photos[index].colourProfile = ImageColourProfile(coverages: [family: 1])
        collection.photos[index].sourceBoard = "board-\(index % 5)"
        collection.photos[index].sourceBoardID = nil
    }
    var custom = Board(); custom.desktop.scenes = SceneOptions(); custom.desktop.scenes?.colourPair = [.colour(.blue), .colour(.yellow)]
    let rare = try WallRotation.roll(custom, collection: collection, display: display, seed: 76)
    let yellowArea = rare.items.filter { $0.colourProfile?.coverage(.yellow) == 1 }.reduce(0) { $0 + $1.width * $1.height }
    let totalArea = rare.items.reduce(0) { $0 + $1.width * $1.height }
    try expect(yellowArea / totalArea >= 0.25)
}
