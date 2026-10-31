import AppKit
import SwiftUI
import CorkCore

@main enum CorkApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.environment["CORK_APPEARANCE"] == "light" { app.appearance = NSAppearance(named: .aqua) }
        if ProcessInfo.processInfo.environment["CORK_APPEARANCE"] == "dark" { app.appearance = NSAppearance(named: .darkAqua) }
        if let index = CommandLine.arguments.firstIndex(of: "--render-showcase"), CommandLine.arguments.count > index + 1 {
            do { try Showcase.export(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
            return
        }
        let delegate = CorkAppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class CorkAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let model = CorkController()
    private let server = LocalServer()
    private var status: NSStatusItem?
    private var library: NSWindowController?
    private var startup: Task<Void, Never>?
    private var termination: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = CorkIcon.menuBarImage(); item.button?.toolTip = "Cork"
        item.button?.setAccessibilityLabel("Cork"); status = item
        model.onChange = { [weak self] in self?.updateMenu(); self?.updateLibraryLevel() }
        model.showLibrary = { [weak self] in self?.openLibrary() }
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleTimeChanged), name: .NSSystemTimeZoneDidChange, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, selector) in [
            (NSWorkspace.screensDidSleepNotification, #selector(screensSleep)),
            (NSWorkspace.screensDidWakeNotification, #selector(screensWake)),
            (NSWorkspace.sessionDidResignActiveNotification, #selector(sessionInactive)),
            (NSWorkspace.sessionDidBecomeActiveNotification, #selector(sessionActive)),
            (NSWorkspace.didActivateApplicationNotification, #selector(activationChanged)),
            (NSWorkspace.activeSpaceDidChangeNotification, #selector(widgetsChanged)),
            (NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, #selector(motionChanged))
        ] { workspace.addObserver(self, selector: selector, name: name, object: nil) }
        startup = Task {
            do {
                try server.start { [weak self] request in
                    guard let self else { return .toolError("Cork has quit.") }
                    return await self.model.handle(request)
                }
                try await model.start()
                updateMenu()
                if model.board.items.isEmpty && !CommandLine.arguments.contains("--background") { openLibrary() }
            } catch { model.errorMessage = error.localizedDescription; updateMenu(); openLibrary() }
        }
        updateMenu()
    }
    func applicationWillTerminate(_ notification: Notification) {
        startup?.cancel(); server.stop(); model.stop(); NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.hasPendingWork else { return .terminateNow }
        if termination == nil {
            termination = Task { await model.finishPendingWork(); NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openLibrary(); return true }
    func applicationDidBecomeActive(_ notification: Notification) { model.screenAccess = CGPreflightScreenCaptureAccess(); model.refreshLoginState(); model.controls.refreshAccess() }
    @objc private func displaysChanged() { model.displaysChanged() }
    @objc private func screensSleep() { model.environment.setDisplayAwake(false); model.controls.setDisplayAwake(false); model.desktop.pauseWidgets(true) }
    @objc private func screensWake() { model.environment.setDisplayAwake(true); model.controls.setDisplayAwake(true); model.desktop.pauseWidgets(false); model.scheduleDriver.wake() }
    @objc private func sessionInactive() { model.environment.setSessionActive(false); model.controls.setSessionActive(false); model.desktop.pauseWidgets(true) }
    @objc private func sessionActive() { model.environment.setSessionActive(true); model.controls.setSessionActive(true); model.desktop.pauseWidgets(false) }
    @objc private func activationChanged() { model.controls.refreshAccess(); model.environment.refreshWidgets() }
    @objc private func widgetsChanged() { model.environment.refreshWidgets() }
    @objc private func motionChanged() { model.environment.updateMotionPreference() }
    @objc private func scheduleTimeChanged() { model.scheduleTimeChanged() }

    func openLibrary() {
        if library == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 740, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Cork"; window.titlebarAppearsTransparent = false; window.toolbarStyle = .unifiedCompact
            window.minSize = CGSize(width: 660, height: 480); window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("CorkLibrary"); window.center()
            window.contentViewController = NSHostingController(rootView: CorkLibraryView(model: model))
            window.setContentSize(CGSize(width: 760, height: 600))
            library = NSWindowController(window: window)
        }
        updateLibraryLevel()
        library?.showWindow(nil); library?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func updateLibraryLevel() {
        // Editing raises the desktop prints temporarily. Keep their inspector
        // above them even after selecting a print or refreshing the arrangement.
        let level = model.editing ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1) : .normal
        if let window = library?.window, window.level != level { window.level = level }
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    private func updateMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("Open Cork…", #selector(showLibrary)))
        menu.addItem(menuItem("Minimize All Windows", #selector(minimizeAllWindows)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Add Images…", #selector(addImages), key: "o"))
        menu.addItem(menuItem("Import from Pinterest…", #selector(importPinterest)))
        menu.addItem(menuItem("New Note", #selector(addNote), key: "n"))
        let roll = menuItem("Roll Wall", #selector(rollWall), key: "r"); roll.isEnabled = model.canRollWall; menu.addItem(roll)
        let fill = menuItem("Fill Empty", #selector(fillEmpty)); fill.isEnabled = model.canRollWall; menu.addItem(fill)
        menu.addItem(menuItem("Paste Image", #selector(pasteImage)))
        let wallpaper = NSMenuItem(title: "Wallpaper", action: nil, keyEquivalent: "")
        let wallpapers = NSMenu()
        wallpapers.addItem(menuItem("Choose Image…", #selector(imageWallpaper)))
        wallpapers.addItem(menuItem("Choose Video…", #selector(videoWallpaper)))
        let system = menuItem("Use System Wallpaper", #selector(systemWallpaper))
        system.state = model.board.desktop.wallpaper.kind == .system ? .on : .off; wallpapers.addItem(system)
        if model.board.desktop.wallpaper.kind == .video {
            wallpapers.addItem(menuItem(model.board.desktop.wallpaper.paused ? "Resume Video" : "Pause Video", #selector(toggleVideo)))
        }
        wallpaper.submenu = wallpapers; menu.addItem(wallpaper)
        let hide = menuItem("Hide Desktop Files", #selector(toggleDesktopFiles))
        hide.state = model.board.desktop.hideDesktopFiles ? .on : .off; menu.addItem(hide)
        let edit = menuItem(model.editing ? "Finish Editing Desktop" : "Edit Desktop", #selector(toggleEditing))
        edit.state = model.editing ? .on : .off; menu.addItem(edit)
        let arrange = NSMenuItem(title: "Arrange", action: nil, keyEquivalent: "")
        let layouts = NSMenu()
        for kind in LayoutKind.allCases {
            let item = menuItem(kind.title, #selector(arrangeItems(_:)))
            item.representedObject = kind.rawValue; layouts.addItem(item)
        }
        arrange.submenu = layouts; menu.addItem(arrange)
        menu.addItem(menuItem(model.board.hidden ? "Show Wall" : "Hide Wall", #selector(toggleHidden)))
        let undo = menuItem("Undo", #selector(undoBoard)); undo.isEnabled = model.history.canUndo && !model.busy; menu.addItem(undo)
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Cork", #selector(quit), key: "q"))
        menu.autoenablesItems = false; status?.menu = menu
    }
    private func installMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu(); appMenu.addItem(menuItem("About Cork", #selector(about)))
        appMenu.addItem(.separator()); appMenu.addItem(menuItem("Quit Cork", #selector(quit), key: "q"))
        let app = NSMenuItem(); app.submenu = appMenu; main.addItem(app)
        let fileMenu = NSMenu(); fileMenu.addItem(menuItem("Open Cork…", #selector(showLibrary), key: "l"))
        fileMenu.addItem(menuItem("Add Images…", #selector(addImages), key: "o"))
        fileMenu.addItem(menuItem("Import from Pinterest…", #selector(importPinterest)))
        fileMenu.addItem(menuItem("New Note", #selector(addNote), key: "n"))
        fileMenu.addItem(menuItem("Roll Wall", #selector(rollWall), key: "r"))
        fileMenu.addItem(menuItem("Fill Empty", #selector(fillEmpty)))
        let close = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"); fileMenu.addItem(close)
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); file.submenu = fileMenu; main.addItem(file)
        let editMenu = NSMenu()
        for (title, selector, key) in [("Undo", #selector(undo(_:)), "z"), ("Redo", #selector(redo(_:)), "Z"),
                                      ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                                      ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            if selector == #selector(undo(_:)) || selector == #selector(redo(_:)) { item.target = self }
            editMenu.addItem(item)
        }
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); edit.submenu = editMenu; main.addItem(edit)
        let helpMenu = NSMenu(), help = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpMenu.addItem(menuItem("Welcome to Cork", #selector(showWelcome))); help.submenu = helpMenu; main.addItem(help)
        NSApp.mainMenu = main
    }
    @objc private func showLibrary() { openLibrary() }
    @objc private func minimizeAllWindows() { model.controls.requestMinimize() }
    @objc private func addImages() { openLibrary(); model.addImages() }
    @objc private func importPinterest() { model.run { try await self.model.launchImporter() } }
    @objc private func showWelcome() { model.showsWelcome = true; openLibrary() }
    @objc private func addNote() { openLibrary(); model.addNote() }
    @objc private func rollWall() { model.run { try await self.model.rollWall() } }
    @objc private func fillEmpty() { model.run { try await self.model.rollWall(fillEmpty: true) } }
    @objc private func pasteImage() { model.pasteImage() }
    @objc private func imageWallpaper() { model.chooseWallpaper(.image) }
    @objc private func videoWallpaper() { model.chooseWallpaper(.video) }
    @objc private func systemWallpaper() { model.run { try await self.model.setDesktop(kind: .system) } }
    @objc private func toggleVideo() { model.run { try await self.model.setDesktop(paused: !self.model.board.desktop.wallpaper.paused) } }
    @objc private func toggleDesktopFiles() { model.run { try await self.model.setDesktop(hideFiles: !self.model.board.desktop.hideDesktopFiles) } }
    @objc private func toggleEditing() { model.setEditing(!model.editing) }
    @objc private func toggleHidden() { model.toggleHidden() }
    @objc private func undoBoard() { model.run { try await self.model.undo() } }
    @objc func undo(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.undoManager?.canUndo == true { text.undoManager?.undo() }
        else { undoBoard() }
    }
    @objc func redo(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.undoManager?.canRedo == true { text.undoManager?.redo() }
        else { model.run { try await self.model.undo(redo: true) } }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(rollWall) { return model.canRollWall }
        if menuItem.action == #selector(undo(_:)) {
            return (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.canUndo == true || (model.history.canUndo && !model.busy)
        }
        if menuItem.action == #selector(redo(_:)) {
            return (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.canRedo == true || (model.history.canRedo && !model.busy)
        }
        return true
    }
    @objc private func arrangeItems(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let layout = LayoutKind(rawValue: raw) { model.run { try await self.model.arrange(layout, gap: layout == .greedy ? 16 : 28) } }
    }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Cork", .applicationVersion: "0.8.0", .credits: NSAttributedString(string: "Images and notes on your desktop. A sibling to Tuck and Snap.")]); NSApp.activate(ignoringOtherApps: true) }
    @objc private func quit() { NSApp.terminate(nil) }
}
