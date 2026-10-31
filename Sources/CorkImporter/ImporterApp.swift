import AppKit
import SwiftUI
import CorkImportCore

@main enum ImporterApp {
    @MainActor static func main() { ImporterDelegate.run() }
}

@MainActor final class ImporterDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let model = ImporterModel()
    private var termination: Task<Void, Never>?
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ImporterDelegate(); app.delegate = delegate
        app.run(); withExtendedLifetime(delegate) {}
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Cork Importer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit Cork Importer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let app = NSMenuItem(); app.submenu = appMenu; main.addItem(app)
        let edit = NSMenu(), editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        for (title, selector, key) in [("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(withTitle: title, action: selector, keyEquivalent: key) }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Cork Importer"; window.minSize = CGSize(width: 720, height: 520)
        window.isReleasedWhenClosed = false; window.center()
        window.contentViewController = NSHostingController(rootView: ImporterView(model: model))
        self.window = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        model.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if termination == nil { termination = Task { await model.finish(); NSApp.reply(toApplicationShouldTerminate: true) } }
        return .terminateLater
    }
}
