import AppKit

enum CorkIcon {
    static func drawImporter(in rect: CGRect, color: NSColor) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform(); transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 100, yBy: rect.height / 100); transform.concat()
        color.setStroke()
        let path = NSBezierPath(); path.lineWidth = 6.3; path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.move(to: CGPoint(x: 21, y: 62)); path.line(to: CGPoint(x: 21, y: 15)); path.line(to: CGPoint(x: 79, y: 15)); path.line(to: CGPoint(x: 79, y: 62))
        path.move(to: CGPoint(x: 50, y: 87)); path.line(to: CGPoint(x: 50, y: 44))
        path.move(to: CGPoint(x: 35, y: 58)); path.line(to: CGPoint(x: 50, y: 43)); path.line(to: CGPoint(x: 65, y: 58)); path.stroke()
        let line = NSBezierPath(); line.lineWidth = 5; line.lineCapStyle = .round
        line.move(to: CGPoint(x: 36, y: 30)); line.line(to: CGPoint(x: 64, y: 30)); line.stroke()
    }
    /// A pinned print, with the same ink, stroke and inset family as Tuck and Snap.
    static func drawMark(in rect: CGRect, color: NSColor) {
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform(); transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 100, yBy: rect.height / 100); transform.concat()
        color.setStroke()
        let paper = NSBezierPath()
        paper.lineWidth = 6.3; paper.lineCapStyle = .round; paper.lineJoinStyle = .round
        paper.move(to: CGPoint(x: 32, y: 76)); paper.line(to: CGPoint(x: 21, y: 76))
        paper.line(to: CGPoint(x: 21, y: 15)); paper.line(to: CGPoint(x: 79, y: 15))
        paper.line(to: CGPoint(x: 79, y: 76)); paper.line(to: CGPoint(x: 68, y: 76)); paper.stroke()
        let pin = NSBezierPath()
        pin.lineWidth = 6.3; pin.lineCapStyle = .round; pin.lineJoinStyle = .round
        pin.move(to: CGPoint(x: 50, y: 63)); pin.line(to: CGPoint(x: 50, y: 49)); pin.stroke()
        color.setFill(); NSBezierPath(ovalIn: CGRect(x: 39, y: 67, width: 22, height: 22)).fill()
        let line = NSBezierPath(); line.lineWidth = 5; line.lineCapStyle = .round
        line.move(to: CGPoint(x: 36, y: 31)); line.line(to: CGPoint(x: 64, y: 31)); line.stroke()
    }
    @MainActor static func menuBarImage() -> NSImage {
        let image = NSImage(size: CGSize(width: 18, height: 18), flipped: false) { rect in drawMark(in: rect.insetBy(dx: 0.5, dy: 0.5), color: .black); return true }
        image.isTemplate = true; image.accessibilityDescription = "Cork"; return image
    }
}
