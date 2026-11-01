import AppKit
import CorkCore

@MainActor
enum PrintRenderer {
    static let paper = NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.94, alpha: 1)

    static func imageRect(item: PrintItem) -> CGRect {
        let inset = item.width * (item.style == .frame ? 0.12 : item.style == .polaroid ? 0.055 : 0.018)
        let bottom = item.style == .polaroid ? item.width * 0.20 : inset
        return CGRect(x: -item.width / 2 + inset, y: -item.height / 2 + inset,
                      width: item.width - inset * 2, height: max(1, item.height - inset - bottom))
    }

    static func draw(item: PrintItem, image: NSImage?, in bounds: CGRect, selected: Bool = false, decorationsOnly: Bool = false) {
        let inset = item.width * (item.style == .frame ? 0.12 : item.style == .polaroid ? 0.055 : 0.018)
        let bottom = item.style == .polaroid ? item.width * 0.20 : inset
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.rotate(byDegrees: item.rotation)
        transform.concat()
        let rect = CGRect(x: -item.width / 2, y: -item.height / 2, width: item.width, height: item.height)
        if item.kind == .widget {
            NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
            let p = NSMutableParagraphStyle(); p.alignment = .center
            (item.title as NSString).draw(in: rect.insetBy(dx: 12, dy: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: p])
            return
        }
        if item.kind == .note {
            drawNote(item: item, in: rect)
            if selected { drawSelection(rect) }
            return
        }
        if !decorationsOnly {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.27)
        shadow.shadowBlurRadius = item.style == .frame ? 12 : 7
        shadow.shadowOffset = CGSize(width: 0, height: -4)
        shadow.set()
        (item.style == .frame ? NSColor(calibratedWhite: 0.16, alpha: 1) : paper).setFill()
        NSBezierPath(rect: rect).fill()
        NSGraphicsContext.restoreGraphicsState()

        var imageRect = imageRect(item: item)
        if item.style == .frame {
            let matte = rect.insetBy(dx: item.width * 0.038, dy: item.width * 0.038)
            paper.setFill(); NSBezierPath(rect: matte).fill()
            NSColor.black.withAlphaComponent(0.26).setStroke()
            let bevel = NSBezierPath(rect: matte.insetBy(dx: 0.5, dy: 0.5)); bevel.lineWidth = 1; bevel.stroke()
        }
        NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
        NSBezierPath(rect: imageRect).fill()
        if let image, image.size.width > 0, image.size.height > 0 {
            let fit = min(imageRect.width / image.size.width, imageRect.height / image.size.height)
            let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
            imageRect = CGRect(x: imageRect.midX - size.width / 2, y: imageRect.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            ("Image unavailable" as NSString).draw(in: imageRect.insetBy(dx: 8, dy: 16), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.darkGray, .paragraphStyle: paragraph])
        }

        }
        if item.style == .tape {
            let width = min(86, item.width * 0.31), height = max(17, min(25, item.width * 0.085))
            let tape = CGRect(x: -width / 2, y: rect.minY - height * 0.42, width: width, height: height)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: tape.minX + 2, y: tape.minY))
            path.line(to: CGPoint(x: tape.maxX - 2, y: tape.minY + 1))
            path.line(to: CGPoint(x: tape.maxX - 4, y: tape.midY - 2))
            path.line(to: CGPoint(x: tape.maxX, y: tape.maxY - 1))
            path.line(to: CGPoint(x: tape.minX, y: tape.maxY))
            path.line(to: CGPoint(x: tape.minX + 3, y: tape.midY + 2)); path.close()
            NSColor(calibratedRed: 0.86, green: 0.82, blue: 0.68, alpha: 0.84).setFill(); path.fill()
            NSColor(calibratedRed: 0.55, green: 0.50, blue: 0.35, alpha: 0.16).setStroke(); path.lineWidth = 0.7; path.stroke()
        }
        if item.style == .pushpin {
            let size = max(10, min(17, item.width * 0.057))
            let pin = CGRect(x: -size / 2, y: rect.minY + 5, width: size, height: size)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
            shadow.shadowBlurRadius = 3; shadow.shadowOffset = CGSize(width: 2, height: -3); shadow.set()
            let path = NSBezierPath(ovalIn: pin)
            NSColor(calibratedRed: 0.53, green: 0.23, blue: 0.20, alpha: 1).setFill(); path.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath(ovalIn: CGRect(x: pin.minX + size * 0.22, y: pin.minY + size * 0.16, width: size * 0.32, height: size * 0.22)).fill()
        }
        if item.style == .polaroid, !item.title.isEmpty {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            let caption = CGRect(x: rect.minX + inset, y: rect.maxY - bottom + bottom * 0.32, width: rect.width - inset * 2, height: bottom * 0.50)
            let fontSize = max(10, min(18, item.width * 0.063))
            (item.title as NSString).draw(in: caption, withAttributes: [
                .font: NSFont(name: "MarkerFelt-Thin", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1), .paragraphStyle: paragraph])
        }
        if selected {
            drawSelection(rect)
        }
    }

    static func noteColor(_ color: NoteColor) -> NSColor {
        switch color {
        case .yellow: NSColor(calibratedRed: 0.97, green: 0.90, blue: 0.57, alpha: 1)
        case .cream: NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.84, alpha: 1)
        case .sage: NSColor(calibratedRed: 0.79, green: 0.86, blue: 0.73, alpha: 1)
        case .rose: NSColor(calibratedRed: 0.93, green: 0.77, blue: 0.75, alpha: 1)
        case .blue: NSColor(calibratedRed: 0.76, green: 0.85, blue: 0.92, alpha: 1)
        case .gray: NSColor(calibratedRed: 0.86, green: 0.86, blue: 0.83, alpha: 1)
        }
    }
    private static func drawSelection(_ rect: CGRect) {
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: -4, dy: -4)); outline.lineWidth = 2; outline.stroke()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: CGRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 10, height: 10), xRadius: 2, yRadius: 2).fill()
    }
    private static func drawNote(item: PrintItem, in rect: CGRect) {
        let color: NSColor
        if item.matchSceneColours == true, let hex = item.matchedNoteColour, let rgb = UInt32(hex.dropFirst(), radix: 16) {
            color = NSColor(srgbRed: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
        } else { color = noteColor(item.noteColor) }
        let sticky = item.style == .sticky
        NSGraphicsContext.saveGraphicsState()
        if sticky {
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
            shadow.shadowBlurRadius = 9; shadow.shadowOffset = CGSize(width: 1, height: -5); shadow.set()
        }
        let curl = sticky ? min(23, item.width * 0.09) : 0
        let paper = NSBezierPath()
        paper.move(to: rect.origin); paper.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        paper.line(to: CGPoint(x: rect.maxX, y: rect.maxY - curl))
        paper.line(to: CGPoint(x: rect.maxX - curl, y: rect.maxY))
        paper.line(to: CGPoint(x: rect.minX, y: rect.maxY)); paper.close()
        color.setFill(); paper.fill(); NSGraphicsContext.restoreGraphicsState()
        if sticky {
            let gradient = NSGradient(starting: color.blended(withFraction: 0.08, of: .white) ?? color,
                                      ending: color.blended(withFraction: 0.08, of: .black) ?? color)
            gradient?.draw(in: paper, angle: 90)
            color.blended(withFraction: 0.07, of: .black)?.setFill()
            NSBezierPath(rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(18, rect.height * 0.07))).fill()
            let fold = NSBezierPath()
            fold.move(to: CGPoint(x: rect.maxX - curl, y: rect.maxY))
            fold.line(to: CGPoint(x: rect.maxX - curl + 2, y: rect.maxY - curl + 2))
            fold.line(to: CGPoint(x: rect.maxX, y: rect.maxY - curl)); fold.close()
            (color.blended(withFraction: 0.24, of: .white) ?? color).setFill(); fold.fill()
        }
        let inset = max(14, item.width * 0.08)
        let font = max(12, min(22, item.width * 0.059))
        let textRect = rect.insetBy(dx: inset, dy: inset + (sticky ? 6 : 0))
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = font * 0.25; paragraph.lineBreakMode = .byWordWrapping
        let ink = NSColor(calibratedWhite: 0.18, alpha: 1)
        var bodyRect = textRect
        if !item.title.isEmpty {
            (item.title as NSString).draw(in: CGRect(x: textRect.minX, y: textRect.minY, width: textRect.width, height: font * 1.6), withAttributes: [
                .font: NSFont.systemFont(ofSize: font, weight: .semibold), .foregroundColor: ink, .paragraphStyle: paragraph])
            bodyRect.origin.y += font * 1.9; bodyRect.size.height -= font * 1.9
        }
        let body = item.text.isEmpty ? "Write a note…" : item.text
        (body as NSString).draw(in: bodyRect, withAttributes: [.font: NSFont.systemFont(ofSize: font),
            .foregroundColor: item.text.isEmpty ? ink.withAlphaComponent(0.55) : ink, .paragraphStyle: paragraph])
    }
}

@MainActor
final class PrintPanel: NSPanel {
    var editing = false
    var interactive = false
    override var canBecomeKey: Bool { editing || interactive }
    override var canBecomeMain: Bool { false }
}

@MainActor
class PrintView: NSView {
    var item: PrintItem
    var image: NSImage?
    var editing = false {
        didSet { if !editing { dragStart = nil; original = nil } }
    }
    var selected = false
    var revision = 0
    var onSelect: (() -> Void)?
    var onChange: (([String: JSONValue], Int) -> Void)?
    var onDelete: (() -> Void)?
    var onDone: (() -> Void)?
    var onStyle: ((PrintStyle) -> Void)?
    private var dragStart: CGPoint?
    private var original: PrintItem?
    private var resizing = false
    var isDragging: Bool { dragStart != nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { editing }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { editing }

    init(item: PrintItem, image: NSImage?) {
        self.item = item; self.image = image
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.image)
        updateAccessibility()
    }
    required init?(coder: NSCoder) { nil }
    func updateAccessibility() {
        setAccessibilityElement(item.kind != .widget || editing)
        setAccessibilityLabel(item.title.isEmpty ? "\(item.style.title) print" : item.title)
        setAccessibilityValue(item.kind == .widget ? "Interactive widget" : item.kind == .note ? item.text : "\(item.style.title) image")
        setAccessibilityHelp(editing ? "Drag to move. Drag the lower-right handle to resize. Arrow keys move; brackets rotate. Use the Cork library for all controls." : "Desktop item. Choose Edit Desktop in Cork to move it.")
    }
    override func draw(_ dirtyRect: NSRect) { PrintRenderer.draw(item: item, image: image, in: bounds, selected: editing && selected) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard editing else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let angle = -item.rotation * .pi / 180
        let delta = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let local = CGPoint(x: delta.x * cos(angle) - delta.y * sin(angle), y: delta.x * sin(angle) + delta.y * cos(angle))
        let rect = CGRect(x: -item.width / 2 - 12, y: -item.height / 2 - 18, width: item.width + 24, height: item.height + 36)
        return rect.contains(local) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        guard editing, let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey(); window.makeFirstResponder(self); onSelect?()
        dragStart = window.convertPoint(toScreen: event.locationInWindow); original = item
        let point = convert(event.locationInWindow, from: nil)
        let angle = -item.rotation * .pi / 180
        let dx = point.x - bounds.midX, dy = point.y - bounds.midY
        let local = CGPoint(x: dx * cos(angle) - dy * sin(angle), y: dx * sin(angle) + dy * cos(angle))
        resizing = local.x > item.width / 2 - 20 && local.y > item.height / 2 - 20
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let original, let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
        if resizing {
            let width = max(64, min(1600, original.width + delta.x))
            item.width = width; item.height = original.height * width / original.width
            needsDisplay = true
        } else {
            var frame = window.frame
            frame.origin.x += delta.x; frame.origin.y += delta.y
            window.setFrameOrigin(frame.origin)
            item.x = original.x + delta.x; item.y = original.y - delta.y
            dragStart = point; self.original = item
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil; original = nil
        onChange?(["id": .string(item.id.uuidString), "x": .number(item.x), "y": .number(item.y),
                   "width": .number(item.width), "height": .number(item.height)], revision)
    }
    override func keyDown(with event: NSEvent) {
        guard editing else { super.keyDown(with: event); return }
        if event.keyCode == 53 { onDone?(); return }
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?(); return }
        let step: Double = event.modifierFlags.contains(.shift) ? 10 : 1
        var patch: [String: JSONValue] = ["id": .string(item.id.uuidString)]
        switch event.keyCode {
        case 123: patch["x"] = .number(item.x - step)
        case 124: patch["x"] = .number(item.x + step)
        case 125: patch["y"] = .number(item.y + step)
        case 126: patch["y"] = .number(item.y - step)
        default:
            if event.charactersIgnoringModifiers == "[" { patch["rotation"] = .number(max(-180, item.rotation - step)) }
            else if event.charactersIgnoringModifiers == "]" { patch["rotation"] = .number(min(180, item.rotation + step)) }
            else { super.keyDown(with: event); return }
        }
        onChange?(patch, revision)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard editing else { return nil }; onSelect?()
        let menu = NSMenu()
        for style in item.kind == .note ? PrintStyle.noteStyles : PrintStyle.imageStyles {
            let entry = NSMenuItem(title: style.title, action: #selector(changeStyle(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = style.rawValue
            entry.state = item.style == style ? .on : .off; menu.addItem(entry)
        }
        menu.addItem(.separator())
        let remove = NSMenuItem(title: "Remove from Wall", action: #selector(removePrint), keyEquivalent: "")
        remove.target = self; menu.addItem(remove)
        return menu
    }
    @objc private func changeStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let style = PrintStyle(rawValue: raw) { onStyle?(style) }
    }
    @objc private func removePrint() { onDelete?() }
}
