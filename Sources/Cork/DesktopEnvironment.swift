import AppKit
import AVFoundation
import ImageIO
import Observation
import CorkCore

private actor WallpaperLoader {
    func image(at url: URL) async throws -> CGImage {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 8192
           ] as CFDictionary) { return image }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 3840, height: 2160)
        return try await generator.image(at: .zero).image
    }
}

private enum PlaybackObservation {
    // Create the callback outside UI isolation; AVFoundation may invoke it on a worker queue.
    static func observe(_ looper: AVPlayerLooper, failure: @escaping @MainActor @Sendable (String) -> Void) -> NSKeyValueObservation {
        looper.observe(\.status, options: [.new, .initial]) { looper, _ in
            guard looper.status == .failed else { return }
            let message = looper.error?.localizedDescription ?? "The video could not be played."
            Task { await failure(message) }
        }
    }
}

@MainActor private final class WallpaperPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class WallpaperView: NSView {
    let image: NSImage
    private var videoLayer: AVPlayerLayer?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observation: NSKeyValueObservation?

    init(image: CGImage, video: URL?, failure: @escaping @MainActor @Sendable (String) -> Void) {
        self.image = NSImage(cgImage: image, size: .zero)
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true); setAccessibilityRole(.image)
        setAccessibilityLabel("Cork wallpaper")
        if let video {
            let item = AVPlayerItem(url: video)
            item.preferredForwardBufferDuration = 2
            let player = AVQueuePlayer(); player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            let videoLayer = AVPlayerLayer(player: player); videoLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(videoLayer)
            self.player = player; self.videoLayer = videoLayer
            let looper = AVPlayerLooper(player: player, templateItem: item)
            self.looper = looper
            observation = PlaybackObservation.observe(looper, failure: failure)
        }
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer?.frame = bounds
        CATransaction.commit()
    }
    // This desktop layer consumes clicks while covering files, so hidden file icons
    // cannot be opened by clicking their old positions. It never becomes key.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    func setPlaying(_ playing: Bool) { if playing { player?.play() } else { player?.pause() } }
    var isPlaying: Bool { (player?.rate ?? 0) > 0 }
    var mediaPlayer: AVPlayer? { player }
    var loopCount: Int { looper?.loopCount ?? 0 }
    var playbackTime: Double { let value = player?.currentTime().seconds ?? 0; return value.isFinite ? value : 0 }
    func stop() {
        observation?.invalidate(); observation = nil
        player?.pause(); looper?.disableLooping(); player?.removeAllItems()
        videoLayer?.player = nil; player = nil; looper = nil
    }
}

@MainActor @Observable
final class DesktopEnvironment {
    private(set) var loading = false
    private(set) var problem: String?
    private(set) var iconsCovered = false
    private(set) var widgetsCovered = false
    private(set) var detectedWidgets = 0
    @ObservationIgnored private let loader = WallpaperLoader()
    @ObservationIgnored private var panels: [UInt32: WallpaperPanel] = [:]
    @ObservationIgnored private var widgetMasks: [WallpaperPanel] = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var mediaKey = ""
    @ObservationIgnored private var settings = DesktopSettings()
    @ObservationIgnored private let wallpapers: URL
    @ObservationIgnored private var displayAwake = true
    @ObservationIgnored private var sessionActive = true
    @ObservationIgnored private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @ObservationIgnored var onChange: (() -> Void)?

    init(wallpapers: URL) { self.wallpapers = wallpapers }
    var windowNumbers: Set<Int> { Set(panels.values.map(\.windowNumber) + widgetMasks.map(\.windowNumber)) }
    var widgetCoverCount: Int { widgetMasks.count }
    var isVideoPlaying: Bool { panels.values.contains { ($0.contentView as? WallpaperView)?.isPlaying == true } }
    var videoTime: Double { (panels.values.first?.contentView as? WallpaperView)?.playbackTime ?? 0 }
    var videoLoops: Int { (panels.values.first?.contentView as? WallpaperView)?.loopCount ?? 0 }
    var printLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + (widgetsCovered ? 4 : iconsCovered ? 1 : -1))
    }

    func apply(_ settings: DesktopSettings) {
        self.settings = settings
        let screens = NSScreen.screens
        if settings.wallpaper.kind == .system && !settings.hideDesktopFiles && !settings.widgetsHidden {
            stopPanels(); mediaKey = ""; loadTask?.cancel(); loading = false; problem = nil; iconsCovered = false; widgetsCovered = false; return
        }
        let sources: [(UInt32, URL)] = screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let url: URL?
            if settings.wallpaper.kind == .system { url = NSWorkspace.shared.desktopImageURL(for: screen) }
            else if let filename = settings.wallpaper.posterFile ?? settings.wallpaper.assetFile { url = wallpapers.appendingPathComponent(filename) }
            else { url = nil }
            return url.map { (number.uint32Value, $0) }
        }
        let key = settings.wallpaper.kind.rawValue + ":" + sources.map { "\($0.0)=\($0.1.path)" }.joined(separator: "|")
        if key == mediaKey && !panels.isEmpty {
            syncPanels(); return
        }
        mediaKey = key; loadTask?.cancel(); loading = true; problem = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard sources.count == screens.count, !sources.isEmpty else { throw CorkError("Cork could not read this system wallpaper. Choose an image or video in Wallpaper settings.") }
                var prepared: [(UInt32, CGImage)] = []
                for (id, url) in sources { prepared.append((id, try await loader.image(at: url))); try Task.checkCancellation() }
                guard mediaKey == key else { return }
                stopPanels()
                for (id, image) in prepared {
                    guard let screen = DesktopWindows.screen(for: id) else { continue }
                    let panel = WallpaperPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                    panel.backgroundColor = .black; panel.isOpaque = true; panel.hasShadow = false
                    panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
                    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                    panel.title = "Cork Wallpaper"; panel.identifier = NSUserInterfaceItemIdentifier("cork-wallpaper-\(id)")
                    let video = settings.wallpaper.kind == .video ? settings.wallpaper.assetFile.map { wallpapers.appendingPathComponent($0) } : nil
                    panel.contentView = WallpaperView(image: image, video: video) { [weak self] message in
                        guard let self, self.mediaKey == key else { return }
                        self.problem = message; self.onChange?()
                    }
                    panels[id] = panel
                }
                loading = false; syncPanels(); onChange?()
            } catch is CancellationError {} catch {
                guard mediaKey == key else { return }
                loading = false; problem = error.localizedDescription
                // Keep a previously rendered wallpaper rather than flashing an empty screen.
                if panels.isEmpty { iconsCovered = false }
                onChange?()
            }
        }
    }
    private func syncPanels() {
        let hide = settings.hideDesktopFiles
        let widgets = DesktopWidgetSurfaces.read(); detectedWidgets = widgets.count
        stopWidgetMasks()
        for (id, panel) in panels {
            if let screen = DesktopWindows.screen(for: id) { panel.setFrame(screen.frame, display: true) }
            panel.level = NSWindow.Level(rawValue: hide ? Int(CGWindowLevelForKey(.desktopIconWindow)) + (settings.widgetsHidden ? 3 : 1) : Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            panel.ignoresMouseEvents = !hide
            panel.orderFrontRegardless()
            (panel.contentView as? WallpaperView)?.setPlaying(!settings.wallpaper.paused && !reduceMotion && displayAwake && sessionActive)
            if settings.widgetsHidden && !hide, let screen = DesktopWindows.screen(for: id), let base = panel.contentView as? WallpaperView {
                for widget in widgets {
                    let rect = widget.rect.intersection(screen.frame)
                    guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }
                    let mask = WallpaperPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                    mask.backgroundColor = .clear; mask.isOpaque = true; mask.hasShadow = false; mask.isReleasedWhenClosed = false
                    mask.hidesOnDeactivate = false; mask.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                    mask.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
                    mask.title = "Cork Widget Cover"
                    mask.contentView = WidgetWallpaperView(image: base.image, player: base.mediaPlayer,
                        canvas: CGRect(x: screen.frame.minX - rect.minX, y: screen.frame.minY - rect.minY, width: screen.frame.width, height: screen.frame.height))
                    mask.orderFrontRegardless(); widgetMasks.append(mask)
                }
            }
        }
        iconsCovered = hide && !panels.isEmpty
        widgetsCovered = settings.widgetsHidden && !panels.isEmpty
    }
    func refreshWidgets() { if settings.widgetsHidden { syncPanels(); onChange?() } }
    func setDisplayAwake(_ awake: Bool) { displayAwake = awake; syncPanels() }
    func setSessionActive(_ active: Bool) { sessionActive = active; syncPanels() }
    func updateMotionPreference() { reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion; syncPanels() }
    private func stopPanels() {
        stopWidgetMasks()
        for panel in panels.values { (panel.contentView as? WallpaperView)?.stop(); panel.close() }
        panels.removeAll()
    }
    private func stopWidgetMasks() {
        for panel in widgetMasks { (panel.contentView as? WidgetWallpaperView)?.stop(); panel.close() }; widgetMasks.removeAll()
    }
    func stop() { mediaKey = ""; loadTask?.cancel(); loadTask = nil; stopPanels(); iconsCovered = false; widgetsCovered = false }
}
