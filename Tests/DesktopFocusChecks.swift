import AppKit
import ImageIO
import CorkCore

@MainActor enum DesktopWindows {
    static func screen(for id: UInt32) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
    }
}

@MainActor final class DesktopCommandTarget: NSObject, NSMenuItemValidation {
    var rolls = 0
    var libraries = 0
    var enabled = true
    @objc func roll(_ sender: Any?) { rolls += 1 }
    @objc func open(_ sender: Any?) { libraries += 1 }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { enabled }
}

@MainActor final class FocusWallpaperAccess: SystemWallpaperAccess {
    var images: [UInt32: SystemWallpaperImage]
    var displayIDs: [UInt32] { Array(images.keys) }
    init(images: [UInt32: SystemWallpaperImage]) { self.images = images }
    func image(for displayID: UInt32) -> SystemWallpaperImage? { images[displayID] }
    func setImage(_ image: SystemWallpaperImage, for displayID: UInt32) throws { images[displayID] = image }
}

@main @MainActor enum DesktopFocusChecks {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CorkError(message) }
    }
    static func main() async {
        do { try await run() } catch { print("FAIL desktop focus: \(error.localizedDescription)"); exit(1) }
    }
    static func run() async throws {
        let app = NSApplication.shared, previous = NSApplication.shared.mainMenu
        let wasActive = app.isActive
        let target = DesktopCommandTarget()
        let main = NSMenu(), file = NSMenu(), fileItem = NSMenuItem()
        let roll = NSMenuItem(title: "Roll Wall", action: #selector(DesktopCommandTarget.roll(_:)), keyEquivalent: "r")
        roll.target = target; file.addItem(roll); fileItem.submenu = file; main.addItem(fileItem); app.mainMenu = main
        let library = NSMenuItem(title: "Open Cork", action: #selector(DesktopCommandTarget.open(_:)), keyEquivalent: "l")
        library.target = target; file.addItem(library)
        defer { app.mainMenu = previous }
        let panel = WallpaperPanel(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.acceptsDesktopFocus = true; panel.isReleasedWhenClosed = false
        defer { panel.close() }
        func key(_ character: String = "r", modifiers: NSEvent.ModifierFlags = .command,
                 repeated: Bool = false, window: NSWindow? = nil) throws -> NSEvent {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 1, windowNumber: (window ?? panel).windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: repeated, keyCode: character == "l" ? 37 : 15) else {
                throw CorkError("No keyboard event")
            }
            return event
        }
        let command = try key()
        // Window-level key-equivalent routing must work even while another app
        // owns the menu bar; no app activation or visible test window is needed.
        try require(panel.performKeyEquivalent(with: command) && target.rolls == 1,
            "A wallpaper Command-R must reach Cork's menu once without requiring app activation.")
        try require(!panel.isVisible, "Verification windows must stay hidden.")
        print("PASS desktop Command-R routing without activation")

        target.enabled = false
        _ = panel.performKeyEquivalent(with: command)
        try require(target.rolls == 1, "A busy/disabled Roll Wall menu item must not run.")
        target.enabled = true
        for event in [try key(modifiers: []), try key(modifiers: .control),
                      try key(modifiers: [.command, .option]), try key(repeated: true)] {
            try require(!panel.performKeyEquivalent(with: event), "Plain, different-modifier or repeating keys must not roll.")
        }
        let other = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false; defer { other.close() }
        try require(!panel.performKeyEquivalent(with: try key(window: other)) && target.rolls == 1,
            "A shortcut targeted at another window must not be intercepted by the wallpaper.")
        try require(panel.performKeyEquivalent(with: try key("l")) && target.libraries == 1,
            "Other native menu shortcuts must keep their existing targets.")
        print("PASS native menu validation, exact modifiers, one action per press and window scoping")

        guard let screen = NSScreen.screens.first,
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { throw CorkError("A logged-in Mac display is required.") }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/focus-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let poster = root.appendingPathComponent("poster.png")
        guard let destination = CGImageDestinationCreateWithURL(poster as CFURL, "public.png" as CFString, 1, nil) else {
            throw CorkError("Cannot create a tiny owned PNG fixture")
        }
        CGImageDestinationAddImage(destination, image, nil)
        try require(CGImageDestinationFinalize(destination), "Could not write owned PNG fixture")
        let access = FocusWallpaperAccess(images: [id: .cover(poster)])
        let sync = SystemWallpaperSync(journalURL: root.appendingPathComponent("journal.json"), access: access)
        let widget = DesktopWidgetSurface(rect: CGRect(x: screen.frame.minX + 20, y: screen.frame.minY + 20, width: 140, height: 90), level: -1)
        let environment = DesktopEnvironment(wallpapers: root, systemWallpaper: sync, presentingWindows: false,
            widgetSurfaces: { [widget] })
        defer { environment.stop() }
        var settings = DesktopSettings(); settings.wallpaper.kind = .image; settings.wallpaper.assetFile = poster.lastPathComponent
        settings.hideDesktopFiles = false; settings.hideWidgets = true
        environment.apply(settings)
        let deadline = Date().addingTimeInterval(5)
        while environment.loading && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try require(!environment.loading && environment.problem == nil, "Injected wallpaper setup must finish.")
        guard let wallpaper = app.windows.first(where: { $0.identifier?.rawValue == "cork-wallpaper-\(id)" }) as? WallpaperPanel,
              let view = wallpaper.contentView as? WallpaperView,
              let mask = app.windows.first(where: { $0.title == "Cork Widget Cover" }),
              let maskView = mask.contentView as? WidgetWallpaperView else { throw CorkError("Missing native desktop surfaces") }
        func click(_ window: NSWindow, count: Int = 1) throws -> NSEvent {
            guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 10, y: 10),
                modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: count, pressure: 0) else { throw CorkError("No pointer event") }
            return event
        }
        view.mouseDown(with: try click(wallpaper))
        try require(wallpaper.firstResponder === view && wallpaper.styleMask.contains(.nonactivatingPanel) && view.needsPanelToBecomeKey,
            "A wallpaper click must establish keyboard focus without relying on app activation.")
        let oldLevel = wallpaper.level
        try require(wallpaper.performKeyEquivalent(with: try key(window: wallpaper)) && target.rolls == 2 && wallpaper.level == oldLevel,
            "The actual environment's wallpaper must route Command-R without changing desktop layers.")
        print("PASS actual wallpaper click, menu command and preserved desktop level")

        _ = wallpaper.makeFirstResponder(nil)
        maskView.mouseDown(with: try click(mask))
        try require(wallpaper.firstResponder === view, "Clicking a widget cover must focus the stable base wallpaper.")
        environment.refreshWidgets()
        try require(app.windows.contains(where: { $0 === wallpaper }) && wallpaper.firstResponder === view,
            "Refreshing widget masks must not discard the base wallpaper responder.")
        try require(wallpaper.performKeyEquivalent(with: try key(window: wallpaper)) && target.rolls == 3,
            "Command-R must still work after widget cover refresh.")
        var doubles = 0; view.onDoubleClick = { doubles += 1 }
        view.mouseDown(with: try click(wallpaper, count: 2))
        try require(doubles == 1 && wallpaper.firstResponder === view, "Double-click video return must preserve keyboard focus.")
        try require(app.isActive == wasActive && app.windows.filter { $0 === wallpaper || $0 === mask || $0 === panel || $0 === other }.allSatisfy { !$0.isVisible },
            "Checks must not activate the app or display verification windows.")
        print("PASS widget cover focus, refresh and video double-click coexistence")
        print("4/4 desktop focus checks passed; hidden windows and injected wallpaper access only.")
    }
}
