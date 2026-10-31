import AppKit
import Observation
import ServiceManagement
import CorkCore

@MainActor @Observable
final class CorkController {
    private(set) var board = Board()
    private(set) var ready = false
    private(set) var busy = false
    private(set) var editing = false
    private(set) var collection = PhotoCollection()
    private(set) var wallpapers = WallpaperCollection()
    private(set) var classifyingColours = false
    private(set) var colourClassificationError: String?
    private(set) var widgets = WidgetRegistry()
    private(set) var favourites = FavouriteBoards()
    @ObservationIgnored let scheduleDriver = WallScheduleDriver()
    var selection: UUID?
    var errorMessage: String?
    var showsWelcome = false
    var defaultStyle: PrintStyle { board.desktop.defaultImageStyle }
    var screenAccess = CGPreflightScreenCaptureAccess()
    private(set) var loginItemState = SMAppService.mainApp.status
    var launchAtLogin: Bool { loginItemState == .enabled }
    var installed: Bool { Bundle.main.bundleURL.standardizedFileURL.path == "/Applications/Cork.app" }
    var loginStatus: String {
        switch loginItemState {
        case .enabled: "enabled"
        case .requiresApproval: "requires_approval"
        case .notRegistered: "not_registered"
        case .notFound: "not_found"
        @unknown default: "unknown"
        }
    }
    private(set) var history = BoardHistory()
    @ObservationIgnored let repository = BoardRepository()
    @ObservationIgnored let desktop = DesktopWindows(assets: CorkPaths.dataDirectory.appendingPathComponent("Images"))
    @ObservationIgnored let environment = DesktopEnvironment(wallpapers: CorkPaths.dataDirectory.appendingPathComponent("Wallpapers"))
    @ObservationIgnored let controls = DesktopControls()
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored private var colourTask: Task<Void, Never>?
    @ObservationIgnored private var colourGeneration = UUID()
    @ObservationIgnored private var displayTask: Task<Void, Never>?
    @ObservationIgnored private var observedDisplays: [DisplayInfo] = []
    @ObservationIgnored private var displayGeneration = 0
    @ObservationIgnored private var widgetSaves: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var widgetGenerations: [UUID: UUID] = [:]
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var showLibrary: (() -> Void)?

    var selectedItem: PrintItem? { board.items.first { $0.id == selection } }
    func collectionPhoto(for item: PrintItem) -> CollectionPhoto? {
        collection.photos.first { $0.assetFile == item.assetFile || (item.sourceURL != nil && $0.sourceURL == item.sourceURL) }
    }
    func displayTitle(for item: PrintItem) -> String {
        if !item.title.isEmpty { return item.title }
        if let reference = item.widget { return widgets.definition(reference)?.name ?? "Widget" }
        return collectionPhoto(for: item)?.title ?? (item.kind == .note ? "Untitled note" : "Untitled image")
    }
    var displays: [DisplayInfo] { DesktopWindows.displays }

    init() {
        desktop.controller = self
        controls.onNeedsAccessibility = { [weak self] in
            self?.errorMessage = "Enable Accessibility in Cork Settings to minimize other apps’ windows."
            self?.showLibrary?()
        }
        controls.onChange = { [weak self] in self?.onChange?() }
        controls.onRandomize = { [weak self] in
            guard let self else { return }; self.run { try await self.rollWall() }
        }
        environment.onChange = { [weak self] in
            guard let self, self.ready else { return }
            if !self.environment.loading {
                self.desktop.refresh(board: self.board, editing: self.editing, selection: self.selection, baseLevel: self.environment.printLevel)
            }
            self.onChange?()
        }
        scheduleDriver.canRun = { [weak self] in guard let self else { return false }; return self.canRollWall && !self.editing }
        scheduleDriver.onFire = { [weak self] schedule in try await self?.scheduledRoll(schedule) }
        scheduleDriver.onChange = { [weak self] in self?.onChange?() }
    }

    func start() async throws {
        let (saved, warning) = try await repository.load()
        board = saved; errorMessage = warning
        do {
            let (loaded, collectionWarning) = try await repository.loadCollection()
            collection = loaded
            if let collectionWarning { errorMessage = [warning, collectionWarning].compactMap { $0 }.joined(separator: "\n") }
        } catch { errorMessage = [warning, error.localizedDescription].compactMap { $0 }.joined(separator: "\n") }
        do {
            let (loaded, warning) = try await repository.loadWallpapers(); wallpapers = loaded
            if let warning { errorMessage = [errorMessage, warning].compactMap { $0 }.joined(separator: "\n") }
        } catch { errorMessage = [errorMessage, error.localizedDescription].compactMap { $0 }.joined(separator: "\n") }
        do { widgets = try await repository.loadWidgets() }
        catch { errorMessage = [errorMessage, error.localizedDescription].compactMap { $0 }.joined(separator: "\n") }
        do { favourites = try await repository.loadFavourites() }
        catch { errorMessage = "Cork could not read favourite boards. Your current wall is preserved. \(error.localizedDescription)" }
        showsWelcome = board.items.isEmpty && collection.photos.isEmpty && !UserDefaults.standard.bool(forKey: "CorkWelcomeComplete")
        ready = true; refresh()
        observedDisplays = board.layoutDisplays ?? []
        displaysChanged()
        classifyColours()
    }

    func classifyColours() {
        colourTask?.cancel(); colourGeneration = UUID()
        let generation = colourGeneration
        colourClassificationError = nil
        guard collection.photos.contains(where: { $0.colourProfile == nil }) || wallpapers.wallpapers.contains(where: { $0.colourProfile == nil }) else {
            classifyingColours = false; colourTask = nil; return
        }
        classifyingColours = true
        colourTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.colourGeneration == generation { self.classifyingColours = false; self.colourTask = nil; self.onChange?() }
            }
            do {
                let result = try await self.repository.classifyColours()
                try Task.checkCancellation()
                guard self.colourGeneration == generation else { return }
                self.collection = result.0; self.wallpapers = result.1
            } catch is CancellationError { }
            catch { if self.colourGeneration == generation { self.colourClassificationError = error.localizedDescription } }
        }
    }
    private func cancelColourClassification() {
        colourTask?.cancel(); colourGeneration = UUID(); classifyingColours = false
    }
    func matchingColourPhotos() -> [CollectionPhoto] {
        guard let pair = board.desktop.sceneOptions.colourPair else { return [] }
        return collection.photos.filter { $0.colourProfile?.matches(pair, strength: board.desktop.sceneOptions.selectedStrength) == true }
    }

    func refresh() {
        environment.apply(board.desktop)
        controls.apply(board.desktop.desktopControls)
        scheduleDriver.apply(board.desktop.randomizationSchedule ?? RandomizationSchedule())
        if !environment.loading { desktop.refresh(board: board, editing: editing, selection: selection, baseLevel: environment.printLevel) }
        onChange?()
    }
    func select(_ id: UUID?) { selection = id; refresh() }
    func setEditing(_ enabled: Bool) {
        editing = enabled; refresh()
        if enabled { showLibrary?() }
    }
    func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard actionTask == nil else { return }
        actionTask = Task { [weak self] in
            guard let self else { return }
            do { try await operation() }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription; refresh() }
            actionTask = nil
        }
    }
    var hasPendingWork: Bool { busy || actionTask != nil || colourTask != nil || displayTask != nil || !widgetSaves.isEmpty || controls.minimizing || scheduleDriver.running }
    func finishPendingWork() async {
        colourTask?.cancel(); await colourTask?.value
        await actionTask?.value
        await displayTask?.value
        for task in Array(widgetSaves.values) { await task.value }
        if busy { await withCheckedContinuation { idleWaiters.append($0) } }
        await controls.finish()
        await scheduleDriver.finish()
    }
    private func finishedSaving() {
        busy = false
        let waiters = idleWaiters; idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        onChange?()
    }
    func stop() { scheduleDriver.stop(); colourTask?.cancel(); actionTask?.cancel(); displayTask?.cancel(); for task in widgetSaves.values { task.cancel() }; controls.stop(); desktop.close(); environment.stop() }

    @discardableResult func saveFavourite(name: String, expectedRevision: Int? = nil) async throws -> FavouriteBoard {
        guard ready, !busy else { throw CorkError("Wait for the current save to finish.") }
        if let expectedRevision, expectedRevision != board.revision { throw CorkError("The wall changed. Refresh before saving it.") }
        let value = FavouriteBoard(board: board, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        try value.validate(); var next = favourites; next.boards.append(value)
        busy = true; defer { finishedSaving() }
        try await repository.saveFavourites(next); favourites = next; return value
    }
    func removeFavourite(_ id: UUID) async throws {
        guard ready, !busy else { throw CorkError("Wait for the current save to finish.") }
        var next = favourites; next.boards.removeAll { $0.id == id }
        busy = true; defer { finishedSaving() }
        try await repository.saveFavourites(next); favourites = next
    }
    func loadFavourite(_ id: UUID, expectedRevision: Int? = nil) async throws {
        guard let value = favourites.boards.first(where: { $0.id == id }) else { throw CorkError("This favourite no longer exists.") }
        try await transact(expectedRevision: expectedRevision) {
            let restored = try value.restoring(into: self.board), displays = self.displays
            try await self.repository.validateFavouriteMedia(value)
            let collection = self.collection, wallpapers = self.wallpapers
            let work = Task.detached(priority: .userInitiated) { try DisplayAdaptation.fit(restored, displays: displays, collection: collection, wallpapers: wallpapers) }
            return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        }
    }
    func setSchedule(_ value: RandomizationSchedule, expectedRevision: Int? = nil) async throws {
        let armed = try value.armed(after: Date())
        try await transact(expectedRevision: expectedRevision) { var next = self.board; next.desktop.randomizationSchedule = armed; return next }
    }
    func completeWelcome(hideFiles: Bool, login: Bool, importPinterest: Bool) async throws {
        try await setDesktop(hideFiles: hideFiles)
        if login { try registerLogin(true) }
        UserDefaults.standard.set(true, forKey: "CorkWelcomeComplete"); showsWelcome = false
        if importPinterest { try await launchImporter() }
    }
    func launchImporter() async throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Cork Importer.app")
        guard FileManager.default.fileExists(atPath: url.path) else { throw CorkError("Cork Importer is missing from this build. Install the complete Cork release or rebuild with scripts/build.sh.") }
        let config = NSWorkspace.OpenConfiguration()
        config.environment = ProcessInfo.processInfo.environment.filter { ["CORK_DATA_DIR", "CORK_SOCKET", "CORK_IMPORT_DATA_DIR"].contains($0.key) }
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
    func scheduleTimeChanged() {
        guard let schedule = board.desktop.randomizationSchedule, schedule.enabled else { return }
        if [.day, .week, .morningEvening].contains(schedule.frequency) {
            run { try await self.setSchedule(schedule) }
        } else { scheduleDriver.wake() }
    }
    private func scheduledRoll(_ expected: RandomizationSchedule) async throws {
        guard board.desktop.randomizationSchedule == expected else { return }
        do { try await rollWall(scheduled: true) }
        catch {
            let problem = error
            if !busy && board.desktop.randomizationSchedule == expected {
                try await transact(recordHistory: false) {
                    var next = self.board; next.desktop.randomizationSchedule = try expected.armed(after: Date()); return next
                }
            }
            throw problem
        }
    }

    func persistWidgetState(_ id: UUID, state: JSONValue) {
        guard let item = board.items.first(where: { $0.id == id }), item.widgetState != state else { return }
        widgetSaves[id]?.cancel()
        let generation = UUID(); widgetGenerations[id] = generation
        widgetSaves[id] = Task { [weak self] in
            guard let self else { return }
            defer { if self.widgetGenerations[id] == generation { self.widgetSaves[id] = nil; self.widgetGenerations[id] = nil } }
            do {
                try await Task.sleep(for: .milliseconds(150))
                await self.actionTask?.value
                if self.busy { await withCheckedContinuation { self.idleWaiters.append($0) } }
                try Task.checkCancellation()
                guard self.board.items.contains(where: { $0.id == id }) else { return }
                try await self.updateItems([["id": .string(id.uuidString), "widget_state": state]], recordHistory: false)
            } catch is CancellationError { }
            catch { self.errorMessage = error.localizedDescription; self.onChange?() }
        }
    }
    func chooseWidgetProvider() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "Choose the widget manifest supplied by an app."; panel.prompt = "Register"
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            self.run { try await self.registerWidgets(at: url.path) }
        }
    }
    func registerWidgets(at path: String) async throws {
        guard ready, !busy else { throw CorkError("Wait for the current operation to finish.") }
        busy = true; defer { finishedSaving() }
        widgets = try await repository.registerWidgets(at: path); desktop.reloadWidgets(); refresh()
    }
    func addWidget(_ reference: WidgetReference, x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil, displayID: UInt32? = nil, expectedRevision: Int? = nil, initialState: JSONValue? = nil) async throws {
        guard let definition = widgets.definition(reference), let display = displays.first(where: { $0.id == displayID }) ?? (displayID == nil ? displays.first : nil) else { throw CorkError("Register this widget provider first and choose an available display.") }
        try await transact(expectedRevision: expectedRevision) {
            var next = self.board
            let size = (width: width ?? definition.width, height: height ?? definition.height)
            let point = try WidgetPlacement.position(in: next, display: display, width: size.width, height: size.height, x: x, y: y)
            var item = PrintItem(assetFile: "", title: definition.name, style: .flat, x: point.x, y: point.y,
                width: size.width, height: size.height, displayID: display.id,
                zIndex: (next.items.map(\.zIndex).max() ?? -1) + 1, kind: .widget)
            item.widget = reference; item.widgetState = initialState ?? .object([:]); next.items.append(item); try next.validate()
            let proposed = next
            let task = Task.detached(priority: .userInitiated) { try BoardLayout.reflow(proposed, display: display) }
            return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        }
    }

    func displaysChanged() {
        refresh()
        let current = displays
        guard ready, current != observedDisplays else { return }
        observedDisplays = current; displayGeneration += 1
        let generation = displayGeneration
        displayTask?.cancel()
        displayTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.displayGeneration == generation { self.displayTask = nil } }
            do {
                try await Task.sleep(for: .milliseconds(120))
                if self.board.desktop.sceneOptions.colourPair != nil { await self.colourTask?.value }
                await self.actionTask?.value
                if self.busy { await withCheckedContinuation { self.idleWaiters.append($0) } }
                try Task.checkCancellation()
                guard generation == self.displayGeneration else { return }
                try await self.transact {
                    let board = self.board, collection = self.collection, wallpapers = self.wallpapers
                    let task = Task.detached(priority: .userInitiated) {
                        try DisplayAdaptation.fit(board, displays: current, collection: collection, wallpapers: wallpapers)
                    }
                    return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                }
            } catch is CancellationError { }
            catch { self.errorMessage = "Cork could not refit this display: \(error.localizedDescription)"; self.refresh() }
        }
    }

    func setDesktopControls(_ settings: DesktopControlSettings, expectedRevision: Int? = nil) async throws {
        guard ready, !busy else { throw CorkError("Wait for the current save to finish.") }
        if let expectedRevision, expectedRevision != board.revision { throw CorkError("The board changed. Refresh before changing the shortcut.") }
        try settings.validate(); try controls.prepare(settings)
        do {
            try await transact(expectedRevision: expectedRevision) { var next = self.board; next.desktop.controls = settings; return next }
            controls.finishConfiguration(board.desktop.desktopControls)
        }
        catch { controls.finishConfiguration(board.desktop.desktopControls, committed: false); throw error }
    }
    func changeControlOptions(shortcutEnabled: Bool? = nil, gestureEnabled: Bool? = nil, randomizeEnabled: Bool? = nil) {
        run {
            var next = self.board.desktop.desktopControls
            if let shortcutEnabled { next.shortcutEnabled = shortcutEnabled }
            if let gestureEnabled { next.anchoredSwipeEnabled = gestureEnabled }
            if let randomizeEnabled { var value = next.wallShortcut; value.enabled = randomizeEnabled; next.randomize = value }
            try await self.setDesktopControls(next)
        }
    }
    func finishShortcutRecording(_ shortcut: MinimizeShortcut?, randomize: Bool = false) {
        guard let shortcut else { controls.endRecording(); return }
        guard !hasPendingWork else { controls.endRecording(); errorMessage = "Wait for the current operation, then record the shortcut again."; return }
        run {
            defer { self.controls.endRecording() }
            var next = self.board.desktop.desktopControls
            if randomize { var value = next.wallShortcut; value.shortcut = shortcut; value.enabled = true; next.randomize = value }
            else { next.shortcut = shortcut; next.shortcutEnabled = true }
            try await self.setDesktopControls(next)
        }
    }

    private func transact(expectedRevision: Int? = nil, recordHistory: Bool = true, makeBoard: () async throws -> Board) async throws {
        guard ready else { throw CorkError("Cork's saved board is not loaded.") }
        guard !busy else { throw CorkError("Cork is saving another change. Refresh the board and try again.") }
        if let expectedRevision, expectedRevision != board.revision { throw CorkError("The board changed since revision \(expectedRevision). Refresh before arranging it again.") }
        busy = true; defer { finishedSaving() }
        let previous = board
        var next = try await makeBoard()
        try Task.checkCancellation()
        guard next != previous else { return }
        // Toy-local state must not interrupt a desktop drag or bury layout Undo.
        next.revision = previous.revision + (recordHistory ? 1 : 0)
        try await repository.save(next)
        if recordHistory { history.record(previous) }; board = next
        if let selection, !next.items.contains(where: { $0.id == selection }) { self.selection = nil }
        refresh()
    }

    func importImages(_ urls: [URL]) async throws {
        guard let display = displays.first else { throw CorkError("No display is available.") }
        try await transact {
            guard board.items.count + urls.count <= 500 else { throw CorkError("A board can hold up to 500 prints.") }
            var next = board
            for (offset, url) in urls.enumerated() {
                let asset = try await repository.importImage(at: url.path)
                let width = min(280, display.safeWidth * 0.4)
                let size = defaultStyle.printSize(imageWidth: asset.width, imageHeight: asset.height, width: width)
                let displacement = Double((next.items.count + offset) % 8) * 25
                var item = PrintItem(assetFile: asset.file, title: asset.title, style: defaultStyle,
                    x: display.safeX + 40 + displacement, y: display.safeY + 35 + displacement,
                    width: size.0, height: size.1, displayID: display.id,
                    zIndex: (next.items.map(\.zIndex).max() ?? -1) + 1, imageWidth: asset.width, imageHeight: asset.height)
                item.colourProfile = asset.colourProfile; next.items.append(item)
            }
            return next
        }
        selection = board.items.last?.id; refresh()
    }

    func addImages() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.prompt = "Add to Wall"; panel.message = "Cork keeps its own copy of each image."
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            self.run { try await self.importImages(panel.urls) }
        }
    }

    var canRollWall: Bool {
        guard ready, !busy else { return false }
        if let pair = board.desktop.sceneOptions.colourPair, board.desktop.sceneOptions.matchColours {
            guard !classifyingColours else { return false }
            let matches = matchingColourPhotos()
            return matches.count >= 6 && pair.allSatisfy { family in matches.contains { ($0.colourProfile?.coverage(family) ?? 0) >= board.desktop.sceneOptions.selectedStrength.minimumCoverage } }
        }
        return !collection.eligibleThemes.isEmpty
    }
    func importCollection(at path: String) async throws {
        guard ready, !busy else { throw CorkError("Wait for the current save to finish.") }
        cancelColourClassification()
        busy = true; defer { finishedSaving(); classifyColours() }
        collection = try await repository.importCollection(at: path)
        refresh()
    }
    func chooseCollection() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.prompt = "Import Collection"; panel.message = "Add a local photo collection with its source, palette, tags, and moods."
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            self.run { try await self.importCollection(at: url.path) }
        }
    }
    func setRotationTheme(_ id: String) async throws {
        try await setDesktop(rotationTheme: id)
    }
    func rollWall(themeID: String? = nil, seed: UInt64? = nil, displayID: UInt32? = nil, expectedRevision: Int? = nil,
                  fillEmpty: Bool = false, paletteID: String? = nil, colourAware: Bool? = nil, scheduled: Bool = false) async throws {
        guard let display = displays.first(where: { $0.id == displayID }) ?? (displayID == nil ? displays.first : nil) else { throw CorkError("This display is not available.") }
        let requested = themeID ?? board.desktop.rotationTheme
        let selected = requested == "auto" ? nil : requested
        let seed = seed ?? UInt64.random(in: 0...UInt64(Int32.max))
        if classifyingColours && board.desktop.sceneOptions.colourPair != nil && paletteID == nil && (colourAware ?? board.desktop.sceneOptions.matchColours) {
            throw CorkError("Cork is classifying the saved images. Wait for colour analysis to finish, then roll again.")
        }
        try await transact(expectedRevision: expectedRevision) {
            var board = self.board
            let collection = self.collection, wallpapers = self.wallpapers
            if colourAware ?? board.desktop.sceneOptions.matchColours {
                for index in board.items.indices where board.items[index].kind == .image && (fillEmpty || board.items[index].isKept) && board.items[index].colours == nil {
                    let item = board.items[index]
                    if !collection.photos.contains(where: { $0.assetFile == item.assetFile || (item.sourceURL != nil && item.sourceURL == $0.sourceURL) }) {
                        board.items[index].colours = try await self.repository.imageColours(assetFile: item.assetFile)
                    }
                }
                if board.desktop.sceneOptions.colourPair != nil {
                    for index in board.items.indices where board.items[index].kind == .image && (fillEmpty || board.items[index].isKept) && board.items[index].colourProfile == nil {
                        let item = board.items[index]
                        if self.collectionPhoto(for: item)?.colourProfile == nil { board.items[index].colourProfile = try await self.repository.imageColourProfile(assetFile: item.assetFile) }
                    }
                }
            }
            let snapshot = board
            let packing = Task.detached(priority: .userInitiated) {
                if fillEmpty { return try WallRotation.fillEmpty(snapshot, collection: collection, display: display, themeID: selected,
                    seed: seed, wallpapers: wallpapers, paletteID: paletteID, colourAware: colourAware) }
                return try WallRotation.roll(snapshot, collection: collection, display: display, themeID: selected,
                    seed: seed, wallpapers: wallpapers, paletteID: paletteID, colourAware: colourAware)
            }
            var result = try await withTaskCancellationHandler { try await packing.value } onCancel: { packing.cancel() }
            if scheduled, let schedule = result.desktop.randomizationSchedule { result.desktop.randomizationSchedule = try schedule.armed(after: Date()) }
            return result
        }
        editing = false; selection = nil; refresh()
    }
    func importWallpapers(at path: String) async throws {
        guard ready, !busy else { throw CorkError("Wait for the current save to finish.") }
        cancelColourClassification()
        busy = true; defer { finishedSaving(); classifyColours() }
        wallpapers = try await repository.importWallpapers(at: path); refresh()
    }
    func chooseWallpapers() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.prompt = "Import Wallpapers"; panel.message = "Add selected local wallpapers and their Pinterest source metadata."
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            self.run { try await self.importWallpapers(at: url.path) }
        }
    }
    func wallpaperDescription(includeMetadata: Bool = true) throws -> JSONValue {
        var value: [String: JSONValue] = ["wallpaper_count": .number(Double(wallpapers.wallpapers.count)),
            "ready_for_display": .number(Double(wallpapers.wallpapers.filter { item in displays.contains(where: item.supports) }.count)),
            "active_palette": try board.rotation?.scheme.map(JSONValue.encode) ?? .null]
        if includeMetadata { value["wallpapers"] = try JSONValue.encode(wallpapers.wallpapers); value["palettes"] = try JSONValue.encode(ScenePalettes.all); value["colour_families"] = colourFamiliesDescription() }
        return .object(value)
    }
    func collectionDescription(includeMetadata: Bool = false, offset: Int = 0, limit: Int = 500, ids: [String]? = nil, sourceURLs: [String]? = nil) throws -> JSONValue {
        guard offset >= 0, (1...500).contains(limit), (ids?.count ?? 0) <= 200, (sourceURLs?.count ?? 0) <= 200 else { throw CorkError("Collection pages use offset ≥ 0, limit 1–500, and up to 200 IDs or source URLs.") }
        let selected = collection.photos.filter { photo in
            (ids == nil && sourceURLs == nil) || ids?.contains(photo.id) == true || sourceURLs?.contains(photo.sourceURL) == true
        }
        var value: [String: JSONValue] = [
            "photo_count": .number(Double(collection.photos.count)),
            "capacity": .number(Double(PhotoCollection.maximumPhotos)),
            "matched_ids": .array(selected.dropFirst(offset).prefix(limit).map { .string($0.id) }),
            "offset": .number(Double(offset)), "has_more": .bool(offset < selected.count && selected.count - offset > limit),
            "themes": .array(collection.themes.map { theme in
                .object(["id": .string(theme.id), "name": .string(theme.name), "description": .string(theme.description),
                         "photo_count": .number(Double(collection.photos.filter { $0.themeIDs.contains(theme.id) }.count)),
                         "available": .bool(collection.eligibleThemes.contains(where: { $0.id == theme.id }))])
            }),
            "metadata_path": .string(repository.root.appendingPathComponent("collection.json").path),
            "colour_families": colourFamiliesDescription(),
            "colour_classification": .object(["running": .bool(classifyingColours),
                "classified_photos": .number(Double(collection.photos.filter { $0.colourProfile != nil }.count)),
                "classified_wallpapers": .number(Double(wallpapers.wallpapers.filter { $0.colourProfile != nil }.count)),
                "error": colourClassificationError.map(JSONValue.string) ?? .null])
        ]
        if includeMetadata { value["photos"] = try JSONValue.encode(Array(selected.dropFirst(offset).prefix(limit))) }
        return .object(value)
    }
    private func colourFamiliesDescription() -> JSONValue {
        .array(ColourFamily.allCases.map { family in
            let strong = collection.photos.filter { ($0.colourProfile?.coverage(family) ?? 0) >= 0.18 }.count
            let weak = collection.photos.filter { let value = $0.colourProfile?.coverage(family) ?? 0; return value >= 0.04 && value < 0.18 }.count
            return .object(["id": .string(family.rawValue), "name": .string(family.name), "hex": .string(family.hex),
                "strong_photos": .number(Double(strong)), "accent_photos": .number(Double(weak))])
        })
    }

    func addNote() {
        run {
            guard let display = self.displays.first else { throw CorkError("No display is available.") }
            try await self.transact {
                var next = self.board
                next.items.append(PrintItem(assetFile: "", title: "", style: .sticky,
                    x: display.safeX + 60, y: display.safeY + 60, width: 260, height: 240,
                    displayID: display.id, zIndex: (next.items.map(\.zIndex).max() ?? -1) + 1, kind: .note))
                return next
            }
            self.selection = self.board.items.last?.id; self.refresh(); self.showLibrary?()
        }
    }

    func pasteImage() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            run { try await self.importImages(urls) }; return
        }
        guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            errorMessage = "Copy an image or an image file, then choose Paste Image."; return
        }
        run {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Cork Clipboard \(UUID().uuidString).png")
            try await Task.detached { try data.write(to: url, options: [.atomic]) }.value
            defer { try? FileManager.default.removeItem(at: url) }
            try await self.importImages([url])
        }
    }

    func updateFromUI(_ patch: [String: JSONValue], revision: Int? = nil) {
        run {
            do { try await self.updateItems([patch], expectedRevision: revision) }
            catch { self.refresh(); throw error }
        }
    }
    func updateItems(_ patches: [[String: JSONValue]], expectedRevision: Int? = nil, recordHistory: Bool = true) async throws {
        try await transact(expectedRevision: expectedRevision, recordHistory: recordHistory) {
            let board = self.board, displays = self.displays
            let packing = Task.detached(priority: .userInitiated) {
                try BoardLayout.applyingCoordinateEdits(board, patches: patches, displays: displays)
            }
            return try await withTaskCancellationHandler { try await packing.value } onCancel: { packing.cancel() }
        }
    }
    func removeFromUI(_ id: UUID) { run { try await self.remove([id]) } }
    func remove(_ ids: [UUID], expectedRevision: Int? = nil) async throws {
        guard ids.allSatisfy({ id in board.items.contains { $0.id == id } }) else { throw CorkError("One of these prints no longer exists.") }
        let set = Set(ids)
        try await transact(expectedRevision: expectedRevision) { var next = self.board; next.items.removeAll { set.contains($0.id) }; return next }
    }
    func arrange(_ layout: LayoutKind, ids: [UUID]? = nil, displayID: UInt32? = nil, gap: Double = 28, expectedRevision: Int? = nil) async throws {
        guard let display = displays.first(where: { $0.id == displayID }) ?? (displayID == nil ? displays.first : nil) else { throw CorkError("Display unavailable. Refresh the board for current display IDs.") }
        try await transact(expectedRevision: expectedRevision) {
            let board = self.board
            let packing = Task.detached(priority: .userInitiated) { try BoardLayout.arrange(board, ids: ids, display: display, layout: layout, gap: gap) }
            return try await withTaskCancellationHandler { try await packing.value } onCancel: { packing.cancel() }
        }
    }
    func undo(redo: Bool = false, expectedRevision: Int? = nil) async throws {
        guard !busy, ready else { throw CorkError("Wait for the current save to finish.") }
        if let expectedRevision, expectedRevision != board.revision { throw CorkError("The board changed. Refresh before undoing.") }
        var nextHistory = history
        guard var previous = redo ? nextHistory.redo(current: board) : nextHistory.undo(current: board) else { throw CorkError(redo ? "Nothing to redo." : "Nothing to undo.") }
        for index in previous.items.indices where previous.items[index].kind == .widget {
            if let current = board.items.first(where: { $0.id == previous.items[index].id && $0.widget == previous.items[index].widget }) {
                previous.items[index].widgetState = current.widgetState
            }
        }
        busy = true; defer { finishedSaving() }
        previous.revision = board.revision + 1
        try await repository.save(previous)
        board = previous; history = nextHistory; refresh()
    }
    func toggleHidden() { run { try await self.transact { var next = self.board; next.hidden.toggle(); return next } } }
    func setLogin(_ enabled: Bool) {
        do { try registerLogin(enabled) }
        catch { errorMessage = error.localizedDescription }
    }
    func registerLogin(_ enabled: Bool) throws {
        defer { refreshLoginState() }
        guard installed else { throw CorkError("Install Cork in /Applications before enabling Open at Login.") }
        if enabled && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        else if !enabled && SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
        onChange?()
    }
    func refreshLoginState() { loginItemState = SMAppService.mainApp.status }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    func chooseWallpaper(_ kind: WallpaperKind) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = kind == .video ? [.movie] : [.image]
        panel.prompt = "Use Wallpaper"; panel.message = kind == .video ? "Cork keeps a local copy and loops the video without sound." : "Cork keeps a local copy of your wallpaper."
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            self.run { try await self.setDesktop(kind: kind, path: url.path) }
        }
    }
    func setDesktop(hideFiles: Bool? = nil, kind: WallpaperKind? = nil, path: String? = nil,
                    paused: Bool? = nil, defaultStyle: PrintStyle? = nil, rotationTheme: String? = nil, expectedRevision: Int? = nil,
                    hideWidgets: Bool? = nil, matchColours: Bool? = nil, matchWallpaper: Bool? = nil, paletteID: String? = nil,
                    colourPair: [ColourFamily]? = nil, colourStrength: ColourSelectionStrength? = nil) async throws {
        if path != nil && (kind == nil || kind == .system) { throw CorkError("Choose image or video when importing a wallpaper path.") }
        if colourPair != nil && paletteID != nil { throw CorkError("Choose a palette or two colours, not both.") }
        if let rotationTheme, rotationTheme != "auto", !collection.eligibleThemes.contains(where: { $0.id == rotationTheme }) {
            throw CorkError("Choose an available mood with at least eight photos.")
        }
        try await transact(expectedRevision: expectedRevision) {
            var next = self.board
            if let hideFiles { next.desktop.hideDesktopFiles = hideFiles }
            if let hideWidgets { next.desktop.hideWidgets = hideWidgets }
            if kind != nil || matchColours != nil || matchWallpaper != nil || paletteID != nil || colourPair != nil || colourStrength != nil {
                var options = next.desktop.sceneOptions
                if let matchColours { options.matchColours = matchColours }
                if let matchWallpaper { options.matchWallpaper = matchWallpaper }
                if let paletteID { options.paletteID = paletteID == "auto" ? nil : paletteID; options.colourPair = nil }
                if let colourPair { options.colourPair = colourPair; options.paletteID = nil; options.matchColours = true }
                if let colourStrength { options.colourStrength = colourStrength }
                if kind != nil { options.matchWallpaper = false }
                next.desktop.scenes = options
            }
            if let defaultStyle { next.desktop.defaultImageStyle = defaultStyle }
            if let rotationTheme { next.desktop.rotationTheme = rotationTheme == "auto" ? nil : rotationTheme }
            if let kind {
                switch kind {
                case .system: next.desktop.wallpaper = WallpaperSettings()
                case .image:
                    guard let path else { throw CorkError("An image wallpaper needs a local path.") }
                    next.desktop.wallpaper = try await self.repository.importWallpaperImage(at: path)
                case .video:
                    guard let path else { throw CorkError("A video wallpaper needs a local path.") }
                    next.desktop.wallpaper = try await self.repository.importWallpaperVideo(at: path)
                }
            }
            if let paused {
                guard next.desktop.wallpaper.kind == .video else { throw CorkError("Select a video wallpaper before changing playback.") }
                next.desktop.wallpaper.paused = paused
            }
            try next.validate(); return next
        }
    }
    func requestScreenAccess() { screenAccess = CGRequestScreenCaptureAccess(); onChange?() }
    func openScreenSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }

    func boardDescription() throws -> JSONValue {
        refreshLoginState()
        var result = try JSONValue.encode(board).object ?? [:]
        result["displays"] = try JSONValue.encode(displays)
        result["editing"] = .bool(editing); result["ready"] = .bool(ready); result["saving"] = .bool(busy)
        result["screen_recording_allowed"] = .bool(CGPreflightScreenCaptureAccess())
        result["coordinates"] = .string("Upper-left of each full display, in logical points. Width/height include decoration; rotation is clockwise. Display safe areas leave room for the menu bar and Dock.")
        result["data_directory"] = .string(repository.root.path)
        result["app_path"] = .string(Bundle.main.bundleURL.path)
        result["login_item"] = .string(loginStatus)
        result["desktop_controls"] = try controls.description()
        result["collection"] = try collectionDescription()
        result["wallpaper_collection"] = try wallpaperDescription(includeMetadata: false)
        result["widget_provider_count"] = .number(Double(widgets.providers.count))
        result["desktop_runtime"] = .object([
            "icons_hidden": .bool(environment.iconsCovered), "loading_wallpaper": .bool(environment.loading),
            "widgets_hidden": .bool(environment.widgetsCovered), "detected_widgets": .number(Double(environment.detectedWidgets)),
            "widget_cover_windows": .number(Double(environment.widgetCoverCount)),
            "menu_bar_wallpaper_synced": .bool(environment.menuBarSynchronized),
            "video_playing": .bool(environment.isVideoPlaying), "video_time": .number(environment.videoTime), "video_loops": .number(Double(environment.videoLoops)),
            "wallpaper_error": environment.problem.map(JSONValue.string) ?? .null
        ])
        return .object(result)
    }

    func handle(_ request: JSONValue) async -> JSONValue {
        do {
            guard let method = request["method"]?.string, let args = request["arguments"]?.object else { throw CorkError("Invalid local command.") }
            let name = method.hasPrefix("cork_") ? method : "cork_" + method
            try CorkTools.validate(name: name, arguments: args)
            if !ready { throw CorkError("Cork is still loading or its saved board could not be read. Open the library for details.") }
            let revision: Int?
            if let value = args["expected_revision"] {
                guard let number = value.number, number >= 0, number <= Double(Int32.max), number.rounded() == number else { throw CorkError("Invalid expected_revision.") }
                revision = Int(number)
            } else { revision = nil }
            switch name {
            case "cork_get_board": break
            case "cork_get_favourites": return try .toolResult(JSONValue.encode(favourites))
            case "cork_save_favourite": return try .toolResult(JSONValue.encode(try await saveFavourite(name: args.requiredString("name"), expectedRevision: revision)))
            case "cork_load_favourite", "cork_remove_favourite":
                guard let id = UUID(uuidString: try args.requiredString("id")) else { throw CorkError("Choose a valid favourite-board ID.") }
                if name == "cork_load_favourite" { try await loadFavourite(id, expectedRevision: revision) }
                else { try await removeFavourite(id) }
            case "cork_set_schedule":
                guard let value = args["schedule"] else { throw CorkError("Provide a randomization schedule.") }
                let schedule = try JSONDecoder().decode(RandomizationSchedule.self, from: value.data())
                try await setSchedule(schedule, expectedRevision: revision)
            case "cork_get_widgets": return try .toolResult(JSONValue.encode(widgets))
            case "cork_register_widgets": try await registerWidgets(at: args.requiredString("path"))
            case "cork_add_widget":
                let reference = WidgetReference(provider: try args.requiredString("provider"), widget: try args.requiredString("widget"))
                let display = try resolveDisplay(args)
                try await addWidget(reference, x: args["x"]?.number, y: args["y"]?.number, width: args["width"]?.number, height: args["height"]?.number, displayID: display.id, expectedRevision: revision, initialState: args["widget_state"])
            case "cork_minimize_all_windows": return try .toolResult(JSONValue.encode(try await controls.minimizeAll()))
            case "cork_set_desktop_controls":
                var next = board.desktop.desktopControls
                if let enabled = args["shortcut_enabled"]?.bool { next.shortcutEnabled = enabled }
                if let enabled = args["gesture_enabled"]?.bool { next.anchoredSwipeEnabled = enabled }
                if args["key_code"] != nil || args["modifiers"] != nil || args["key_label"] != nil {
                    guard let code = args["key_code"]?.number, (0...127).contains(code),
                          let modifiers = args["modifiers"]?.number, (0...15).contains(modifiers), let label = args["key_label"]?.string else {
                        throw CorkError("Provide key_code, modifiers and key_label together.")
                    }
                    next.shortcut = MinimizeShortcut(keyCode: UInt32(code), modifiers: UInt32(modifiers), keyLabel: label)
                }
                if args["randomize_enabled"] != nil || args["randomize_key_code"] != nil || args["randomize_modifiers"] != nil || args["randomize_key_label"] != nil {
                    var value = next.wallShortcut
                    if let enabled = args["randomize_enabled"]?.bool { value.enabled = enabled }
                    if args["randomize_key_code"] != nil || args["randomize_modifiers"] != nil || args["randomize_key_label"] != nil {
                        guard let code = args["randomize_key_code"]?.number, (0...127).contains(code),
                              let modifiers = args["randomize_modifiers"]?.number, (0...15).contains(modifiers),
                              let label = args["randomize_key_label"]?.string else { throw CorkError("Provide all three randomize key fields together.") }
                        value.shortcut = MinimizeShortcut(keyCode: UInt32(code), modifiers: UInt32(modifiers), keyLabel: label)
                    }
                    next.randomize = value
                }
                try await setDesktopControls(next, expectedRevision: revision)
                // The randomize binding has its own saved key and enable switch.
            case "cork_get_collection":
                let offset = args["offset"]?.number ?? 0, limit = args["limit"]?.number ?? 500
                guard (0...Double(PhotoCollection.maximumPhotos)).contains(offset), (1...500).contains(limit) else { throw CorkError("Use a valid collection offset and a limit from 1–500.") }
                return try .toolResult(collectionDescription(includeMetadata: args["include_metadata"]?.bool ?? false,
                    offset: Int(offset), limit: Int(limit), ids: args["ids"]?.array?.compactMap(\.string), sourceURLs: args["source_urls"]?.array?.compactMap(\.string)))
            case "cork_import_collection": try await importCollection(at: args.requiredString("path"))
            case "cork_get_wallpapers": return try .toolResult(wallpaperDescription())
            case "cork_import_wallpapers": try await importWallpapers(at: args.requiredString("path"))
            case "cork_roll_wall", "cork_fill_empty":
                let seed: UInt64?
                if let value = args["seed"]?.number {
                    guard value >= 0, value <= Double(Int32.max) else { throw CorkError("seed must be 0…2147483647.") }
                    seed = UInt64(value)
                } else { seed = nil }
                let target = try resolveDisplay(args)
                try await rollWall(themeID: args["theme"]?.string, seed: seed, displayID: target.id, expectedRevision: revision,
                    fillEmpty: name == "cork_fill_empty", paletteID: args["palette"]?.string, colourAware: args["colour_aware"]?.bool)
            case "cork_add_image":
                let path = try args.requiredString("path")
                guard let style = PrintStyle(rawValue: args["style"]?.string ?? defaultStyle.rawValue), PrintStyle.imageStyles.contains(style) else { throw CorkError("Unknown image style.") }
                let display = try resolveDisplay(args)
                let width = try args.optionalNumber("width", fallback: 280)
                guard (64...4000).contains(width) else { throw CorkError("width must be 64…4000 points.") }
                try await transact {
                    guard self.board.items.count < 500 else { throw CorkError("This board already has 500 prints.") }
                    let asset = try await self.repository.importImage(at: path)
                    let size = style.printSize(imageWidth: asset.width, imageHeight: asset.height, width: width)
                    var item = PrintItem(assetFile: asset.file, title: args["title"]?.string ?? asset.title, style: style,
                        x: try args.optionalNumber("x", fallback: display.safeX + 40), y: try args.optionalNumber("y", fallback: display.safeY + 40),
                        width: size.0, height: size.1, rotation: try args.optionalNumber("rotation", fallback: 0), displayID: display.id,
                        zIndex: (self.board.items.map(\.zIndex).max() ?? -1) + 1, sourceURL: args["source_url"]?.string,
                        imageWidth: asset.width, imageHeight: asset.height)
                    item.colourProfile = asset.colourProfile
                    try item.validate(); var next = self.board; next.items.append(item); return next
                }
            case "cork_update_items":
                guard let entries = args["items"]?.array else { throw CorkError("items must be an array.") }
                let patches = try entries.map { value -> [String: JSONValue] in guard let patch = value.object else { throw CorkError("Each update must be an object.") }; return patch }
                let currentDisplays = Set(displays.map(\.id))
                for patch in patches where patch["display_id"] != nil {
                    let display = try resolveDisplay(patch); guard currentDisplays.contains(display.id) else { throw CorkError("Display unavailable.") }
                }
                try await updateItems(patches, expectedRevision: revision)
            case "cork_add_note":
                let text = args["text"]?.string ?? ""
                guard args["text"]?.string != nil else { throw CorkError("text must be a string.") }
                let display = try resolveDisplay(args)
                guard let style = PrintStyle(rawValue: args["style"]?.string ?? "sticky"), PrintStyle.noteStyles.contains(style),
                      let color = NoteColor(rawValue: args["note_color"]?.string ?? "yellow") else { throw CorkError("Unknown note style or color.") }
                try await transact {
                    var next = self.board
                    var note = PrintItem(assetFile: "", title: args["title"]?.string ?? "", style: style,
                        x: try args.optionalNumber("x", fallback: display.safeX + 60), y: try args.optionalNumber("y", fallback: display.safeY + 60),
                        width: try args.optionalNumber("width", fallback: 260), height: try args.optionalNumber("height", fallback: 240),
                        rotation: try args.optionalNumber("rotation", fallback: 0), displayID: display.id,
                        zIndex: (next.items.map(\.zIndex).max() ?? -1) + 1, kind: .note, text: text, noteColor: color,
                        includeInLayout: args["include_in_layout"]?.bool)
                    note.matchSceneColours = args["match_scene_colours"]?.bool; next.items.append(note)
                    next = NoteColours.refresh(next)
                    try next.validate(); return next
                }
            case "cork_arrange":
                guard let layout = LayoutKind(rawValue: try args.requiredString("layout")) else { throw CorkError("Unknown layout.") }
                try await arrange(layout, ids: args["ids"] == nil ? nil : try args.identifiers(), displayID: try resolveDisplay(args).id,
                                  gap: try args.optionalNumber("gap", fallback: layout == .greedy ? 16 : 28), expectedRevision: revision)
            case "cork_remove_items": try await remove(try args.identifiers(), expectedRevision: revision)
            case "cork_undo": try await undo(expectedRevision: revision)
            case "cork_set_edit_mode":
                guard let enabled = args["enabled"]?.bool else { throw CorkError("enabled must be true or false.") }
                editing = enabled; refresh() // agent commands never activate the library
            case "cork_set_desktop":
                let kind = args["wallpaper_kind"]?.string.flatMap(WallpaperKind.init(rawValue:))
                let style = args["default_image_style"]?.string.flatMap(PrintStyle.init(rawValue:))
                try await setDesktop(hideFiles: args["hide_files"]?.bool, kind: kind, path: args["path"]?.string,
                                     paused: args["paused"]?.bool, defaultStyle: style, rotationTheme: args["rotation_theme"]?.string, expectedRevision: revision,
                                     hideWidgets: args["hide_widgets"]?.bool, matchColours: args["match_colours"]?.bool,
                                     matchWallpaper: args["match_wallpaper"]?.bool, paletteID: args["palette"]?.string,
                                     colourPair: try args["colour_pair"].map { value in
                                         guard let names = value.array, names.count == 2 else { throw CorkError("Choose two colour families.") }
                                         return try names.map { name in guard let raw = name.string, let family = ColourFamily(rawValue: raw) else { throw CorkError("Unknown colour family.") }; return family }
                                     }, colourStrength: args["colour_strength"]?.string.flatMap(ColourSelectionStrength.init(rawValue:)))
            case "cork_set_login_item":
                guard let enabled = args["enabled"]?.bool else { throw CorkError("enabled must be true or false.") }
                try registerLogin(enabled)
            case "cork_screenshot_desktop":
                let display = try resolveDisplay(args)
                let mode = args["mode"]?.string ?? "desktop"
                guard ["desktop", "visible"].contains(mode) else { throw CorkError("mode must be desktop or visible.") }
                let width = try args.optionalNumber("max_width", fallback: 1600)
                guard (320...2560).contains(width) else { throw CorkError("max_width must be 320…2560 pixels.") }
                return try await DesktopCapture.capture(display: display, mode: mode, maxWidth: Int(width), printWindows: desktop.windowNumbers.union(environment.windowNumbers), root: repository.root)
            default: throw CorkError("Unknown tool.")
            }
            return try .toolResult(boardDescription())
        } catch { return .toolError(error.localizedDescription) }
    }
    private func resolveDisplay(_ args: [String: JSONValue]) throws -> DisplayInfo {
        guard let value = args["display_id"] else {
            guard let first = displays.first else { throw CorkError("No display is available.") }; return first
        }
        guard let number = value.number, number >= 0, number <= Double(UInt32.max), number.rounded() == number,
              let display = displays.first(where: { $0.id == UInt32(number) }) else { throw CorkError("Unknown display_id. Inspect cork_get_board.") }
        return display
    }
}
