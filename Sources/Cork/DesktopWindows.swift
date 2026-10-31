import AppKit
import CorkCore

@MainActor
final class DesktopWindows {
    private var panels: [UUID: PrintPanel] = [:]
    private var images: [String: NSImage] = [:]
    private var widgetsPaused = false
    let assets: URL
    weak var controller: CorkController?
    init(assets: URL) { self.assets = assets }

    static var displays: [DisplayInfo] {
        NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let full = screen.frame, safe = screen.visibleFrame.insetBy(dx: 28, dy: 28)
            return DisplayInfo(id: id, name: screen.localizedName, width: full.width, height: full.height,
                               scale: screen.backingScaleFactor, safeX: safe.minX - full.minX,
                               safeY: full.maxY - safe.maxY, safeWidth: safe.width, safeHeight: safe.height)
        }
    }

    static func screen(for id: UInt32) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id } ?? NSScreen.screens.first
    }

    func refresh(board: Board, editing: Bool, selection: UUID?, baseLevel: NSWindow.Level) {
        let live = Set(board.items.filter { !$0.isHidden }.map(\.id))
        for id in Array(panels.keys) where !live.contains(id) {
            if let panel = panels.removeValue(forKey: id) { (panel.contentView as? WidgetPaperView)?.stop(); panel.close() }
        }
        let files = Set(board.items.map(\.assetFile)); images = images.filter { files.contains($0.key) }
        for item in board.itemsBackToFront {
            guard let screen = Self.screen(for: item.displayID) else { continue }
            let panel: PrintPanel
            if let existing = panels[item.id] { panel = existing }
            else {
                panel = PrintPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
                panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                panel.title = "Cork — \(item.title)"; panel.identifier = NSUserInterfaceItemIdentifier("cork-print-\(item.id)")
                if item.kind == .image, images[item.assetFile] == nil { images[item.assetFile] = NSImage(contentsOf: assets.appendingPathComponent(item.assetFile)) }
                let content: NSView
                let view: PrintView
                if item.kind == .widget {
                    let widget = WidgetPaperView(item: item, registry: controller?.widgets ?? WidgetRegistry(), root: CorkPaths.dataDirectory)
                    widget.surface?.onState = { [weak self] state in self?.controller?.persistWidgetState(item.id, state: state) }
                    content = widget; view = widget.editor
                } else { let printView = PrintView(item: item, image: images[item.assetFile]); content = printView; view = printView }
                view.onSelect = { [weak self] in self?.controller?.select(item.id) }
                view.onChange = { [weak self] patch, revision in self?.controller?.updateFromUI(patch, revision: revision) }
                view.onDelete = { [weak self] in self?.controller?.removeFromUI(item.id) }
                view.onDone = { [weak self] in self?.controller?.setEditing(false) }
                view.onStyle = { [weak self] style in self?.controller?.updateFromUI(["id": .string(item.id.uuidString), "style": .string(style.rawValue)]) }
                panel.contentView = content; panels[item.id] = panel
            }
            panel.editing = editing
            let view = (panel.contentView as? PrintView) ?? (panel.contentView as? WidgetPaperView)?.editor
            view?.editing = editing
            panel.interactive = item.kind == .widget
            panel.ignoresMouseEvents = !editing && item.kind != .widget
            panel.level = editing ? .floating : baseLevel
            let angle = item.rotation * .pi / 180
            let padding = item.kind == .widget ? 0.0 : 96.0
            let width = abs(cos(angle)) * item.width + abs(sin(angle)) * item.height + padding
            let height = abs(sin(angle)) * item.width + abs(cos(angle)) * item.height + padding
            // Temporarily clamp on reconnect; do not overwrite the saved arrangement.
            let present = Self.displays.contains { $0.id == item.displayID }
            let centerX = present ? item.x + item.width / 2 : min(max(item.x + item.width / 2, 20), screen.frame.width - 20)
            let centerY = present ? item.y + item.height / 2 : min(max(item.y + item.height / 2, 30), screen.frame.height - 20)
            if view?.isDragging != true {
                panel.setFrame(CGRect(x: screen.frame.minX + centerX - width / 2,
                                      y: screen.frame.maxY - centerY - height / 2, width: width, height: height), display: false)
                view?.item = item; view?.revision = board.revision
            }
            if let view {
                view.selected = item.id == selection
                view.updateAccessibility(); view.needsDisplay = true
            }
            (panel.contentView as? WidgetPaperView)?.surface?.updateState(item.widgetState ?? .object([:]))
            (panel.contentView as? WidgetPaperView)?.surface?.setPaused(widgetsPaused || board.hidden)
            if board.hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        }
    }
    func close() { for panel in panels.values { (panel.contentView as? WidgetPaperView)?.stop(); panel.close() }; panels.removeAll() }
    func select(_ selection: UUID?) {
        // Selection changes must not reorder windows or reset an in-progress drag.
        for (id, panel) in panels {
            if let view = (panel.contentView as? PrintView) ?? (panel.contentView as? WidgetPaperView)?.editor {
                view.selected = id == selection; view.needsDisplay = true
            }
        }
    }
    func pauseWidgets(_ paused: Bool) { widgetsPaused = paused; for panel in panels.values { (panel.contentView as? WidgetPaperView)?.surface?.setPaused(paused) } }
    func reloadWidgets() {
        for id in Array(panels.keys) where panels[id]?.contentView is WidgetPaperView {
            if let panel = panels.removeValue(forKey: id) { (panel.contentView as? WidgetPaperView)?.stop(); panel.close() }
        }
    }
    func image(for item: PrintItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        if images[item.assetFile] == nil { images[item.assetFile] = NSImage(contentsOf: assets.appendingPathComponent(item.assetFile)) }
        return images[item.assetFile]
    }
    var windowNumbers: Set<Int> { Set(panels.values.map(\.windowNumber)) }
}
