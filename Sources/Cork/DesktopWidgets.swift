import AppKit
import AVFoundation

struct DesktopWidgetSurface {
    let rect: CGRect
    let level: Int
}
@MainActor enum DesktopWidgetSurfaces {
    static func read() -> [DesktopWidgetSurface] {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return [] }
        let icons = Int(CGWindowLevelForKey(.desktopIconWindow))
        return windows.compactMap { window in
            guard let level = window[kCGWindowLayer as String] as? Int, level >= icons, level < 0,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width > 4, rect.height > 4 else { return nil }
            let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard bundle == "com.apple.notificationcenterui" || owner == "Notification Centre" || owner == "Notification Center" else { return nil }
            // Only public owner/layer/bounds metadata is used. Never read window titles or pixels.
            return DesktopWidgetSurface(rect: CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY,
                width: rect.width, height: rect.height).insetBy(dx: -5, dy: -5), level: level)
        }
    }
}

/// A wallpaper replica clipped to one widget footprint. It shares the base video's
/// player, so hiding widgets alone does not hide file icons or desynchronise video.
@MainActor final class WidgetWallpaperView: NSView {
    let image: NSImage
    let canvas: CGRect
    private var video: AVPlayerLayer?
    init(image: NSImage, player: AVPlayer?, canvas: CGRect) {
        self.image = image; self.canvas = canvas
        super.init(frame: .zero); wantsLayer = true; layer?.masksToBounds = true
        setAccessibilityElement(false)
        if let player {
            let video = AVPlayerLayer(player: player); video.videoGravity = .resizeAspectFill
            layer?.addSublayer(video); self.video = video
        }
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(canvas.width / image.size.width, canvas.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: canvas.midX - size.width / 2, y: canvas.midY - size.height / 2, width: size.width, height: size.height),
            from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    override func layout() {
        super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); video?.frame = canvas; CATransaction.commit()
    }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    func stop() { video?.player = nil }
}
