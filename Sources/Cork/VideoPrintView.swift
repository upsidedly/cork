import AppKit
import AVFoundation
import CorkCore

enum VideoStatusObservation {
    // AVFoundation invokes KVO on worker queues; only the delivered value enters UI isolation.
    static func observe(_ player: AVPlayerLooper, change: @escaping @MainActor @Sendable (Bool) -> Void) -> NSKeyValueObservation {
        player.observe(\.status, options: [.new, .initial]) { item, _ in
            let failed = item.status == .failed
            Task { await change(failed) }
        }
    }
}

@MainActor private final class VideoClipView: NSView {
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor private final class VideoDecorationView: NSView {
    var item: PrintItem
    init(item: PrintItem) { self.item = item; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { PrintRenderer.draw(item: item, image: nil, in: bounds, decorationsOnly: true) }
}

/// Static paper at rest. Only a hovered or keyboard-activated print owns a decoder.
@MainActor final class VideoPrintView: PrintView {
    private let videoURL: URL
    private var clip: VideoClipView?
    private var decoration: VideoDecorationView?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observation: NSKeyValueObservation?
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var keyboardPlaying = false
    private var generation = UUID()
    private(set) var failed = false
    var onFailure: ((String) -> Void)?
    var onToggleWallpaper: ((VideoWallpaperPreview) -> Void)?
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var playbackPaused = false { didSet { if playbackPaused { stop() } } }
    var isPlaying: Bool { (player?.rate ?? 0) > 0 }
    var playbackTime: Double { let time = player?.currentTime().seconds ?? 0; return time.isFinite ? time : 0 }
    var hasPlayer: Bool { player != nil }
    var playbackMuted: Bool { player?.isMuted ?? true }
    var readyForDisplay: Bool { clip?.playerLayer?.isReadyForDisplay ?? false }
    override var editing: Bool { didSet { if editing { stop() } } }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(item: PrintItem, image: NSImage?, videoURL: URL) {
        self.videoURL = videoURL
        super.init(item: item, image: image)
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Play or pause video", handler: { [weak self] in
            guard let self else { return false }; self.toggleKeyboardPlayback(); return true
        }), NSAccessibilityCustomAction(name: "Use video as wallpaper", handler: { [weak self] in
            self?.requestWallpaper() ?? false
        })])
    }
    required init?(coder: NSCoder) { nil }

    override func updateAccessibility() {
        super.updateAccessibility()
        setAccessibilityLabel(item.title.isEmpty ? "\(item.style.title) video print" : item.title)
        setAccessibilityValue(failed ? "Video unavailable; still cover shown" : isPlaying ? "Playing silently" : "Still video cover")
        setAccessibilityHelp(editing ? "Drag to move or resize this video print." : "Hover to play silently. Space plays or pauses. Double-click or press Return to expand into the wallpaper; double-click the wallpaper or press Escape to return. With Reduce Motion, use Space for print playback.")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    private func imageContains(_ point: CGPoint) -> Bool {
        let dx = point.x - bounds.midX, dy = point.y - bounds.midY, angle = -item.rotation * .pi / 180
        let local = CGPoint(x: dx * cos(angle) - dy * sin(angle), y: dx * sin(angle) + dy * cos(angle))
        return PrintRenderer.imageRect(item: item).contains(local)
    }
    private func updateHover(with event: NSEvent) {
        let inside = imageContains(convert(event.locationInWindow, from: nil))
        guard inside != hovered else { return }; hovered = inside
        if inside && !reduceMotion() { startPlayback() }
        else if !keyboardPlaying { stopPlayback() }
    }
    override func mouseEntered(with event: NSEvent) { updateHover(with: event) }
    override func mouseMoved(with event: NSEvent) { updateHover(with: event) }
    override func mouseExited(with event: NSEvent) { hovered = false; if !keyboardPlaying { stopPlayback() } }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if editing { return super.hitTest(point) }
        return imageContains(point) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        if editing { stop(); super.mouseDown(with: event); return }
        if event.clickCount == 2 { _ = requestWallpaper(); return }
        NSApp.activate(ignoringOtherApps: true); window?.makeKey(); window?.makeFirstResponder(self)
    }
    @discardableResult func requestWallpaper() -> Bool {
        guard !editing, !playbackPaused, let window, let image, let video = item.video, let onToggleWallpaper else { return false }
        let aperture = PrintRenderer.imageRect(item: item), angle = item.rotation * .pi / 180
        func screenPoint(_ point: CGPoint) -> CGPoint {
            let p = CGPoint(x: bounds.midX + point.x * cos(angle) - point.y * sin(angle),
                            y: bounds.midY + point.x * sin(angle) + point.y * cos(angle))
            return window.convertPoint(toScreen: convert(p, to: nil))
        }
        let center = screenPoint(CGPoint(x: aperture.midX, y: aperture.midY))
        let edge = screenPoint(CGPoint(x: aperture.maxX, y: aperture.midY))
        let time = hasPlayer ? playbackTime : video.posterTime
        let displayID = (window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? item.displayID
        let preview = VideoWallpaperPreview(item: item, displayID: displayID, videoURL: videoURL,
            posterURL: videoURL.deletingLastPathComponent().appendingPathComponent(item.assetFile), poster: image,
            origin: VideoWallpaperOrigin(center: center, size: aperture.size, angle: atan2(edge.y - center.y, edge.x - center.x)), startTime: time)
        stop(); onToggleWallpaper(preview); return true
    }
    override func keyDown(with event: NSEvent) {
        if !editing && event.keyCode == 36 { _ = requestWallpaper(); return }
        if !editing && event.keyCode == 49 { toggleKeyboardPlayback(); return }
        if !editing && event.keyCode == 53 { stop(); onDone?(); return }
        super.keyDown(with: event)
    }
    override func resignFirstResponder() -> Bool {
        keyboardPlaying = false; if !hovered { stopPlayback() }; return super.resignFirstResponder()
    }
    private func toggleKeyboardPlayback() {
        guard !editing, !playbackPaused else { return }
        keyboardPlaying = !hasPlayer
        if keyboardPlaying { startPlayback() } else { stopPlayback() }
    }
    private func startPlayback() {
        guard !editing, !playbackPaused, player == nil, window != nil else { return }
        failed = false; generation = UUID(); let current = generation
        let item = AVPlayerItem(url: videoURL); item.preferredForwardBufferDuration = 1
        let queue = AVQueuePlayer(); queue.isMuted = true; queue.preventsDisplaySleepDuringVideoPlayback = false
        let surface = VideoClipView(frame: .zero); surface.wantsLayer = true
        surface.playerLayer?.player = queue; surface.playerLayer?.videoGravity = .resizeAspect
        addSubview(surface); clip = surface
        let overlay = VideoDecorationView(item: self.item); addSubview(overlay); decoration = overlay
        let loop = AVPlayerLooper(player: queue, templateItem: item)
        player = queue; looper = loop
        observation = VideoStatusObservation.observe(loop) { [weak self] failed in
            guard let self, self.generation == current, failed else { return }
            self.stopPlayback(); self.failed = true; self.updateAccessibility()
            self.onFailure?("This video could not play. Its still cover is preserved; re-add the original clip to try again.")
        }
        needsLayout = true; layoutSubtreeIfNeeded(); queue.play(); updateAccessibility()
    }
    private func stopPlayback() {
        generation = UUID(); observation = nil
        player?.pause(); looper?.disableLooping(); player?.removeAllItems()
        clip?.playerLayer?.player = nil; clip?.removeFromSuperview(); decoration?.removeFromSuperview()
        clip = nil; decoration = nil; looper = nil; player = nil
        updateAccessibility(); needsDisplay = true
    }
    func stop() { hovered = false; keyboardPlaying = false; stopPlayback() }
    func motionPreferenceChanged() { if reduceMotion() && !keyboardPlaying { stop() } }
    func syncPlayback() {
        if editing || playbackPaused || item.isHidden { stop() }
        decoration?.item = item; decoration?.needsDisplay = true; needsLayout = true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stop() }; super.viewWillMove(toWindow: newWindow)
    }
    override func layout() {
        super.layout()
        guard let clip else { return }
        let rect = PrintRenderer.imageRect(item: item)
        // Rotate the aperture's center around the paper center as well as its
        // axes; a Polaroid's larger bottom margin makes these centers differ.
        let angle = item.rotation * .pi / 180
        let center = CGPoint(x: bounds.midX + rect.midX * cos(angle) - rect.midY * sin(angle),
                             y: bounds.midY + rect.midX * sin(angle) + rect.midY * cos(angle))
        clip.frameCenterRotation = 0
        clip.frame = CGRect(x: center.x - rect.width / 2, y: center.y - rect.height / 2, width: rect.width, height: rect.height)
        clip.frameCenterRotation = item.rotation
        decoration?.frame = bounds
    }
}
