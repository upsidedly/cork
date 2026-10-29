import AppKit
import SwiftUI
import CorkCore

struct MinimizeShortcutRecorder: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let shortcut: MinimizeShortcut
    var accessibilityName = "Minimize all windows shortcut"
    let begin: () -> Void
    let finish: (MinimizeShortcut?) -> Void
    func makeNSView(context: Context) -> ShortcutButton {
        let button = ShortcutButton(); button.bezelStyle = .rounded
        button.setAccessibilityLabel(accessibilityName)
        button.target = button; button.action = #selector(ShortcutButton.record)
        return button
    }
    func updateNSView(_ button: ShortcutButton, context: Context) {
        button.begin = begin; button.finish = finish
        button.setAccessibilityLabel(accessibilityName)
        button.isEnabled = isEnabled
        if !button.recording { button.title = shortcut.display }
        button.setAccessibilityValue(button.recording ? "Recording shortcut" : shortcut.display)
        button.toolTip = "Click, then press a shortcut. Escape cancels."
    }
    static func dismantleNSView(_ button: ShortcutButton, coordinator: ()) { button.cancel() }
}

@MainActor final class ShortcutButton: NSButton {
    var begin: (() -> Void)?
    var finish: ((MinimizeShortcut?) -> Void)?
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(inputFocusLost(_:)), name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(inputFocusLost(_:)), name: NSApplication.didResignActiveNotification, object: NSApp)
        } else { cancel() }
    }
    @objc private func inputFocusLost(_ notification: Notification) { cancel() }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc func record() {
        guard !recording else { cancel(); return }
        recording = true; begin?(); title = "Press shortcut…"; window?.makeFirstResponder(self)
    }
    func cancel() {
        guard recording else { return }
        recording = false; finish?(nil)
    }
    override func resignFirstResponder() -> Bool { cancel(); return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { cancel(); return }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= 1 }
        if event.modifierFlags.contains(.option) { modifiers |= 2 }
        if event.modifierFlags.contains(.control) { modifiers |= 4 }
        if event.modifierFlags.contains(.shift) { modifiers |= 8 }
        let names: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        let functionKeys: [UInt16: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        let label = names[event.keyCode] ?? functionKeys[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        let shortcut = MinimizeShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
        do { try shortcut.validate() }
        catch { title = "Include ⌘, ⌥ or ⌃"; NSSound.beep(); return }
        recording = false; title = shortcut.display; finish?(shortcut)
    }
}
