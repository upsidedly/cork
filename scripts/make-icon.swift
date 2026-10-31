import AppKit

@main enum IconGenerator {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let documentation = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let importer = CommandLine.arguments.contains("--importer")
        let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documentation, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw NSError(domain: "CorkIcon", code: 1) }
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
                let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
                NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
                NSBezierPath(roundedRect: CGRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205).fill()
                let rect = CGRect(x: 196, y: 196, width: 632, height: 632), ink = NSColor(calibratedWhite: 0.16, alpha: 1)
                if importer { CorkIcon.drawImporter(in: rect, color: ink) } else { CorkIcon.drawMark(in: rect, color: ink) }
                NSGraphicsContext.restoreGraphicsState()
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "CorkIcon", code: 2) }
                let suffix = scale == 2 ? "@2x" : ""
                try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
                if pixels == 1024 { try data.write(to: documentation.appendingPathComponent(importer ? "cork-importer-icon.png" : "cork-icon.png")) }
            }
        }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
        try FileManager.default.removeItem(at: iconset)
    }
}
