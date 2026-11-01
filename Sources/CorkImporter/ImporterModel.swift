import AppKit
import Foundation
import Observation
import CorkCore
import CorkImportCore

@MainActor @Observable final class ImporterModel {
    enum Step { case connect, boards, review, complete }
    var step = Step.connect
    var profiles: [BrowserProfile] = []
    var profileID = "" { didSet { if profileID != oldValue { consent = false; dailyConsent = false } } }
    var consent = false
    var account: PinterestAccount?
    var boards: [PinterestBoard] = []
    var selected: Set<String> = []
    var quotas: [String: Int] = [:]
    var review = ImportReview(images: [])
    var resumable: ImportReview?
    var busy = false
    var status = ""
    var error: String?
    var capacity = PhotoCollection.maximumPhotos
    var createCollage = false
    var showRemoved = false
    var filterBoard = ""
    var completionNote: String?
    var dailySettings = DailySyncSettings()
    var dailyState = DailySyncState()
    var dailyConsent = false
    var showsDailySync = false
    var changingDailySchedule = false
    @ObservationIgnored let store = ImportSessionStore()
    @ObservationIgnored let dailyStore: DailySyncStore
    @ObservationIgnored let previews = ImportPreviewCache()
    @ObservationIgnored private var client: PinterestClient?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var coordinator: ImportCoordinator?
    @ObservationIgnored private var scopedDirectory: URL?
    init(dailyStore: DailySyncStore = DailySyncStore()) { self.dailyStore = dailyStore }
    var quotaTotal: Int { boards.filter { selected.contains($0.id) }.reduce(0) { $0 + ((quotas[$1.id] ?? 20) == 0 ? $1.pinCount : min(quotas[$1.id] ?? 20, $1.pinCount)) } }
    var visibleImages: [PinterestImage] { review.images.filter { (showRemoved || !review.removed.contains($0.id)) && (filterBoard.isEmpty || $0.boardID == filterBoard) } }
    var importedCount: Int { review.committed.intersection(Set(review.keepers.map(\.id))).count }
    var dailyTime: Date {
        get { Calendar.current.date(bySettingHour: dailySettings.hour, minute: dailySettings.minute, second: 0, of: Date()) ?? Date() }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            dailySettings.hour = parts.hour ?? 9; dailySettings.minute = parts.minute ?? 0
        }
    }
    var dailyStatus: String {
        if dailyState.lastMessage == "Checking Pinterest…", let date = dailyState.lastAttempt, Date().timeIntervalSince(date) > 310 {
            return "The last check was interrupted. Confirmed imports are safe; check again or wait for tomorrow."
        }
        return dailyState.lastMessage
    }

    func start() {
        profiles = BrowserProfile.available(); profileID = profiles.first?.id ?? ""
        perform {
            self.resumable = try await self.store.load()
            try await self.store.clearStaging()
            self.dailySettings = try await self.dailyStore.settings()
            self.dailyState = try await self.dailyStore.state()
        }
    }
    func perform(_ work: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; error = nil; generation = UUID(); let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            do { try await work(); try Task.checkCancellation() }
            catch is CancellationError { self.status = "Stopped. Existing reviews and completed imports are kept." }
            catch { self.error = error.localizedDescription }
            if self.generation == token { self.busy = false; self.task = nil }
        }
    }
    func connect() {
        guard consent, let profile = profiles.first(where: { $0.id == profileID }) else { return }
        perform {
            self.status = "Connecting to Pinterest…"
            let cookies = try await BrowserCookieReader().read(profile, approved: self.consent)
            try Task.checkCancellation()
            let client = PinterestClient(cookies: cookies)
            do {
                let account = try await client.connect(); try Task.checkCancellation()
                let boards = try await client.boards(); try Task.checkCancellation()
                self.client = client; self.account = account; self.boards = boards
                self.selected = []; self.quotas = [:]; self.step = .boards; self.status = ""
            } catch { await client.disconnect(); throw error }
        }
    }
    func chooseProfile(browser: String) {
        guard !busy else { return }
        let folders = ["Chrome": "Google/Chrome", "Chromium": "Chromium", "Brave": "BraveSoftware/Brave-Browser", "Edge": "Microsoft Edge", "Firefox": "Firefox/Profiles"]
        guard let folder = folders[browser] else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "Use Profile"
        panel.message = "Choose \(browser)'s profile folder (Default, Profile 1, or a Firefox profile). Only Pinterest cookies will be read, after you choose Connect."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/" + folder)
        panel.begin { [weak self] response in
            guard response == .OK, let self, let directory = panel.url else { return }
            self.scopedDirectory?.stopAccessingSecurityScopedResource()
            _ = directory.startAccessingSecurityScopedResource(); self.scopedDirectory = directory
            let services = ["Chrome": ("Chrome Safe Storage", "Chrome"), "Chromium": ("Chromium Safe Storage", "Chromium"),
                "Brave": ("Brave Safe Storage", "Brave"), "Edge": ("Microsoft Edge Safe Storage", "Microsoft Edge")]
            let candidates = browser == "Firefox" ? ["cookies.sqlite"] : ["Cookies", "Network/Cookies"]
            guard candidates.contains(where: { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) else {
                self.error = "Choose a profile folder containing \(browser == "Firefox" ? "cookies.sqlite" : "Cookies or Network/Cookies"). If macOS asks for browser-data access, you can decline."
                return
            }
            let profile = BrowserProfile(browser: browser, name: directory.lastPathComponent, directory: directory,
                service: services[browser]?.0, account: services[browser]?.1, firefox: browser == "Firefox")
            self.profiles.removeAll { $0.id == profile.id }; self.profiles.append(profile); self.profileID = profile.id; self.error = nil
        }
    }
    func disconnect() {
        perform {
            try await self.updateDaily(enabled: false, forget: true)
            await self.client?.disconnect(); self.client = nil; self.account = nil; self.consent = false
            if !self.review.images.isEmpty { self.resumable = self.review }
            self.boards = []; self.selected = []; self.step = .connect; self.status = "Disconnected. The in-memory browser session was cleared."
        }
    }
    func startAnother() {
        review = ImportReview(images: []); resumable = nil; completionNote = nil
        filterBoard = ""; showRemoved = false; step = .connect; consent = false; dailyConsent = false; status = ""
    }
    func fetch() {
        guard let client, !selected.isEmpty else { return }
        guard resumable == nil else { error = "Resume or discard the unfinished review before starting another."; return }
        perform {
            self.status = "Preparing the review…"
            var result: [PinterestImage] = [], seen: Set<String> = [], warnings: [String] = []
            for board in self.boards where self.selected.contains(board.id) {
                try Task.checkCancellation()
                guard result.count < PhotoCollection.maximumPhotos else { warnings.append("Review capacity reached. Remaining boards were not fetched."); break }
                let quota = self.quotas[board.id] ?? 20
                let fetched = try await client.images(board: board, count: quota == 0 ? nil : quota,
                    capacity: PhotoCollection.maximumPhotos - result.count) { [weak self] count in
                        await MainActor.run { self?.status = "\(board.name): \(count) images found" }
                    }
                for image in fetched.images where seen.insert(image.id).inserted { result.append(image) }
                if let warning = fetched.warning { warnings.append(warning) }
                if fetched.omitted > 0 { warnings.append("\(board.name): \(fetched.omitted) video, unsupported or unrelated pins skipped.") }
            }
            guard !result.isEmpty else { throw CorkError("No supported images were returned from those boards. Try another board or reconnect.") }
            self.review = ImportReview(images: result, warnings: warnings); try await self.store.save(self.review)
            self.resumable = nil; self.step = .review; self.status = ""
        }
    }
    func resume() {
        guard let value = resumable else { return }
        review = value; resumable = nil; step = .review; error = nil
    }
    func toggle(_ id: String) {
        if review.removed.contains(id) { review.removed.remove(id) } else { review.removed.insert(id) }
        saveReview()
    }
    func setAll(keep: Bool) {
        let ids = Set(review.images.filter { filterBoard.isEmpty || $0.boardID == filterBoard }.map(\.id))
        if keep { review.removed.subtract(ids) } else { review.removed.formUnion(ids) }
        saveReview()
    }
    private func saveReview() {
        saveTask?.cancel(); let snapshot = review
        saveTask = Task { [weak self, store] in
            do {
                try await Task.sleep(for: .milliseconds(200)); try await store.save(snapshot)
                try await self?.dailyStore.exclude(snapshot.removed, restore: Set(snapshot.images.map(\.id)).subtracting(snapshot.removed))
            }
            catch is CancellationError {} catch { self?.error = "Could not save the review: \(error.localizedDescription)" }
        }
    }
    func addToCork() {
        guard !review.keepers.isEmpty else { return }
        perform {
            await self.saveTask?.value
            try await self.openCork(activate: false)
            let coordinator = ImportCoordinator(store: self.store); self.coordinator = coordinator
            let status = try await coordinator.status()
            let remaining = Int(status["capacity"]?.number ?? Double(PhotoCollection.maximumPhotos)) - Int(status["photo_count"]?.number ?? 0)
            // Existing pins are reconciled in each batch, so a resumed review can exceed remaining capacity.
            if self.review.keepers.count > remaining && self.review.committed.isEmpty {
                self.status = "Existing pins will be reused; new images stop at Cork's 20,000-image capacity."
            }
            self.review = try await coordinator.transfer(self.review) { [weak self] review, message in
                await MainActor.run { self?.review = review; self?.status = message }
            }
            try Task.checkCancellation()
            if self.createCollage {
                do { _ = try await NativeCorkDestination().call("cork_roll_wall", arguments: ["theme": .string("pinterest-library")]) }
                catch { self.completionNote = "Images were added. Cork could not create a collage yet: \(error.localizedDescription)" }
            }
            try await self.store.discard(); self.coordinator = nil; self.step = .complete
            self.status = "\(self.importedCount) images are in Cork."
            await self.client?.disconnect(); self.client = nil; self.account = nil
        }
    }
    func discardReview() {
        perform {
            await self.saveTask?.value; try await self.store.discard()
            self.review = ImportReview(images: []); self.resumable = nil; self.error = nil
            self.step = self.account == nil ? .connect : .boards
        }
    }
    func stop() { task?.cancel() }
    func finish() async {
        task?.cancel(); await task?.value; await saveTask?.value
        await client?.disconnect(); client = nil; try? await store.clearStaging(); await previews.clear()
        scopedDirectory?.stopAccessingSecurityScopedResource(); scopedDirectory = nil
    }
    func openCork(activate: Bool) async throws {
        let embeddedParent = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = embeddedParent.pathExtension == "app" && embeddedParent.lastPathComponent == "Cork.app" ? embeddedParent : URL(fileURLWithPath: "/Applications/Cork.app")
        guard FileManager.default.fileExists(atPath: path.path) else { throw CorkError("Install Cork in Applications, then open it before adding your images.") }
        let config = NSWorkspace.OpenConfiguration(); config.activates = activate; config.arguments = activate ? [] : ["--background"]
        config.environment = ProcessInfo.processInfo.environment.filter { ["CORK_DATA_DIR", "CORK_SOCKET", "CORK_IMPORT_DATA_DIR"].contains($0.key) }
        _ = try await NSWorkspace.shared.openApplication(at: path, configuration: config)
        // Bounded read-only startup wait. No mutation is retried.
        for attempt in 0..<20 {
            do { _ = try await NativeCorkDestination().call("cork_get_collection", arguments: ["limit": .number(1)]); return }
            catch { if attempt == 19 { throw error }; try await Task.sleep(for: .milliseconds(250)) }
        }
    }
    func openPinterest() { if let url = URL(string: "https://www.pinterest.com/") { NSWorkspace.shared.open(url) } }

    func enableDaily() {
        guard dailyConsent, let client, let account,
              let profile = profiles.first(where: { $0.id == profileID }), !selected.isEmpty else { return }
        perform {
            let previous = try await self.dailyStore.settings()
            var settings = self.dailySettings
            settings.enabled = true; settings.consentVersion = 1; settings.profile = profile; settings.username = account.username
            settings.boards = self.boards.filter { self.selected.contains($0.id) }
            settings.bookmark = try profile.directory.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            try settings.validate()
            guard let executable = Bundle.main.executableURL else { throw CorkError("Importer executable is missing.") }
            // Validate the installed location before storing any daily consent.
            _ = try DailySyncAgent.definition(executable: executable, settings: settings)
            try await self.dailyStore.save(settings)
            do {
                self.status = "Recording today's board baseline; older pins won't be downloaded…"
                try await self.openCork(activate: false)
                self.dailyState = try await PinterestDailySync(store: self.dailyStore).run(source: client, force: true)
                try Task.checkCancellation(); self.changingDailySchedule = true
                try await DailySyncAgent.set(settings, executable: executable)
                self.dailySettings = settings; self.dailyConsent = false; self.showsDailySync = true
                self.client = nil; self.account = nil; self.consent = false; self.step = .connect
                self.status = "Daily sync is enabled. New pins will be added within your storage limits."
                self.changingDailySchedule = false
            } catch {
                self.changingDailySchedule = false
                try await self.dailyStore.save(previous)
                self.client = nil; self.account = nil; self.consent = false; self.step = .connect
                throw error
            }
        }
    }
    private func updateDaily(enabled: Bool, forget: Bool = false) async throws {
        let previous = try await dailyStore.settings()
        var next = previous; next.enabled = enabled
        if forget { next.profile = nil; next.bookmark = nil; next.consentVersion = 0; next.username = "" }
        if previous == next { dailySettings = next; return }
        guard let executable = Bundle.main.executableURL else { throw CorkError("Importer executable is missing.") }
        try await dailyStore.save(next)
        do { try await DailySyncAgent.set(next, executable: executable); dailySettings = next }
        catch { try await dailyStore.save(previous); throw error }
    }
    func setDailyEnabled(_ enabled: Bool) {
        perform {
            self.changingDailySchedule = true
            defer { self.changingDailySchedule = false }
            try await self.updateDaily(enabled: enabled)
            self.status = enabled ? "Daily sync resumed." : "Daily sync paused."
        }
    }
    func forgetDaily() {
        perform {
            self.changingDailySchedule = true
            defer { self.changingDailySchedule = false }
            try await self.updateDaily(enabled: false, forget: true)
            self.dailyConsent = false
            self.status = "Daily connection removed. Imported images and exclusions are kept."
        }
    }
    func checkDaily() {
        perform {
            self.status = "Checking for new Pinterest pins…"
            do { try await DailySyncCommand.checkNow() }
            catch { self.dailyState = try await self.dailyStore.state(); throw error }
            self.dailyState = try await self.dailyStore.state(); self.status = self.dailyState.lastMessage
        }
    }
    func chooseDailyBoards() { showsDailySync = false; step = account == nil ? .connect : .boards }
    func reloadDaily() async {
        do { dailySettings = try await dailyStore.settings(); dailyState = try await dailyStore.state() }
        catch { self.error = error.localizedDescription }
    }
}
