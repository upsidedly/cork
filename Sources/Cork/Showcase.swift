import AppKit
import CorkCore

/// Original sample art, rendered by the same native renderer as desktop items.
@MainActor enum Showcase {
    static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let images = (0..<4).map(artwork)
        for (index, image) in images.enumerated() {
            if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: directory.appendingPathComponent("sample-\(index + 1).png"))
            }
        }
        let size = CGSize(width: 1600, height: 930)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CorkError("Could not render the showcase.") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let flip = NSAffineTransform(); flip.translateX(by: 0, yBy: size.height); flip.scaleX(by: 1, yBy: -1); flip.concat()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        NSColor(calibratedRed: 0.19, green: 0.21, blue: 0.20, alpha: 1).setFill(); CGRect(origin: .zero, size: size).fill()
        let titles = ["Quiet hours", "Take the long way", "A small collection", "Room to grow"]
        let positions = [CGRect(x: 100, y: 100, width: 270, height: 350), CGRect(x: 490, y: 95, width: 265, height: 342),
                         CGRect(x: 875, y: 90, width: 265, height: 392), CGRect(x: 1250, y: 105, width: 250, height: 337)]
        for index in 0..<4 {
            let rect = positions[index]
            let style = PrintStyle.imageStyles[index]
            let size = style.printSize(imageWidth: 600, imageHeight: 800, width: rect.width)
            let item = PrintItem(assetFile: "sample.png", title: titles[index], style: style, width: size.0, height: size.1,
                                 rotation: [-4.0, 2, -3, 1][index], imageWidth: 600, imageHeight: 800)
            PrintRenderer.draw(item: item, image: images[index], in: CGRect(x: rect.minX - 30, y: rect.minY - 30, width: rect.width + 60, height: size.1 + 60))
            label(style.title, at: CGPoint(x: rect.minX, y: 535), color: .white.withAlphaComponent(0.6))
        }
        let flat = PrintItem(assetFile: "", title: "A little space", style: .flat, width: 360, height: 245, rotation: 0,
                             kind: .note, text: "For the things you want\nto keep in sight.", noteColor: .cream)
        let sticky = PrintItem(assetFile: "", title: "For later", style: .sticky, width: 360, height: 245, rotation: -3,
                               kind: .note, text: "Print something.\nMake time.\nTake the scenic route.", noteColor: .yellow)
        PrintRenderer.draw(item: flat, image: nil, in: CGRect(x: 385, y: 570, width: 420, height: 305))
        PrintRenderer.draw(item: sticky, image: nil, in: CGRect(x: 825, y: 570, width: 420, height: 305))
        label("Flat", at: CGPoint(x: 415, y: 890), color: .white.withAlphaComponent(0.6))
        label("Sticky", at: CGPoint(x: 855, y: 890), color: .white.withAlphaComponent(0.6))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CorkError("Could not encode the showcase.") }
        try png.write(to: directory.appendingPathComponent("cork-treatments.png"))
    }
    private static func label(_ text: String, at point: CGPoint, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: color])
    }
    private static func artwork(_ index: Int) -> NSImage {
        NSImage(size: CGSize(width: 600, height: 800), flipped: true) { rect in
            let cream = NSColor(calibratedRed: 0.92, green: 0.90, blue: 0.82, alpha: 1)
            cream.setFill(); rect.fill()
            switch index {
            case 0:
                NSColor(calibratedRed: 0.30, green: 0.38, blue: 0.31, alpha: 1).setFill()
                let mountain = NSBezierPath(); mountain.move(to: CGPoint(x: 0, y: 600)); mountain.line(to: CGPoint(x: 180, y: 270))
                mountain.curve(to: CGPoint(x: 600, y: 560), controlPoint1: CGPoint(x: 350, y: 330), controlPoint2: CGPoint(x: 420, y: 560))
                mountain.line(to: CGPoint(x: 600, y: 800)); mountain.line(to: CGPoint(x: 0, y: 800)); mountain.close(); mountain.fill()
                NSColor(calibratedRed: 0.72, green: 0.49, blue: 0.34, alpha: 1).setFill()
                NSBezierPath(ovalIn: CGRect(x: 365, y: 130, width: 95, height: 95)).fill()
                label("QUIET HOURS", at: CGPoint(x: 60, y: 62), color: .darkGray)
            case 1:
                NSColor(calibratedRed: 0.72, green: 0.38, blue: 0.28, alpha: 1).setFill()
                NSBezierPath(ovalIn: CGRect(x: 95, y: 115, width: 410, height: 410)).fill()
                NSColor(calibratedRed: 0.27, green: 0.33, blue: 0.35, alpha: 1).setFill()
                for offset in 0..<9 { CGRect(x: 0, y: 410 + offset * 33, width: 600, height: 13).fill() }
                label("TAKE THE LONG WAY", at: CGPoint(x: 60, y: 65), color: .darkGray)
            case 2:
                NSColor(calibratedRed: 0.33, green: 0.39, blue: 0.43, alpha: 1).setFill(); rect.fill()
                NSColor(calibratedWhite: 0.84, alpha: 1).setFill()
                for row in 0..<4 { for column in 0..<3 {
                    let x = 65 + column * 165, y = 80 + row * 160
                    NSBezierPath(roundedRect: CGRect(x: x, y: y, width: 115, height: 120), xRadius: 55, yRadius: 55).fill()
                } }
                label("COLLECT SMALL MOMENTS", at: CGPoint(x: 65, y: 740), color: .white.withAlphaComponent(0.8))
            default:
                NSColor(calibratedRed: 0.25, green: 0.33, blue: 0.28, alpha: 1).setStroke()
                let branch = NSBezierPath(); branch.lineWidth = 7; branch.lineCapStyle = .round
                branch.move(to: CGPoint(x: 285, y: 660)); branch.curve(to: CGPoint(x: 325, y: 185), controlPoint1: CGPoint(x: 350, y: 440), controlPoint2: CGPoint(x: 220, y: 330)); branch.stroke()
                NSColor(calibratedRed: 0.39, green: 0.47, blue: 0.36, alpha: 1).setFill()
                for offset in 0..<5 {
                    NSGraphicsContext.saveGraphicsState()
                    let transform = NSAffineTransform(); transform.translateX(by: CGFloat(290 + (offset % 2) * 32), yBy: CGFloat(250 + offset * 70))
                    transform.rotate(byDegrees: offset % 2 == 0 ? -32 : 32); transform.concat()
                    NSBezierPath(ovalIn: CGRect(x: offset % 2 == 0 ? -110 : 0, y: -25, width: 115, height: 50)).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
                label("ROOM TO GROW", at: CGPoint(x: 60, y: 65), color: .darkGray)
            }
            return true
        }
    }
}
