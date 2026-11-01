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

@MainActor final class WallpaperPanel: NSPanel {
    var acceptsDesktopFocus = false
    override var canBecomeKey: Bool { acceptsDesktopFocus }
    override var canBecomeMain: Bool { false }

    func focusDesktop() {
        guard acceptsDesktopFocus else { return }
        makeKey(); makeFirstResponder(contentView)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard acceptsDesktopFocus, isKeyWindow || event.window === self, event.type == .keyDown,
              event.modifierFlags.contains(.command), !event.isARepeat else { return false }
        // A nonactivating desktop panel can own keyboard focus while another
        // app still owns the menu bar. Route through Cork's real menu so its
        // targets, modifiers and validation stay identical to the library.
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }
}

@MainActor final class WallpaperView: NSView {
    let image: NSImage
    private var videoLayer: AVPlayerLayer?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observation: NSKeyValueObservation?
    var onDone: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    private(set) var previewSurface: VideoWallpaperSurface?
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
    // Focus the desktop without raising it above prints or opening the library.
    // Hidden Finder icons remain covered, including their mouse hit targets.
    override func mouseDown(with event: NSEvent) {
        (window as? WallpaperPanel)?.focusDesktop()
        if event.clickCount == 2 { onDoubleClick?() }
    }
    override func rightMouseDown(with event: NSEvent) {}
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDone?() }
        else { super.keyDown(with: event) }
    }
    func setPlaying(_ playing: Bool) { if playing { player?.play() } else { player?.pause() } }
    var isPlaying: Bool { previewSurface?.isPlaying ?? ((player?.rate ?? 0) > 0) }
    var mediaPlayer: AVPlayer? { previewSurface?.mediaPlayer ?? player }
    var displayImage: NSImage { previewSurface?.poster ?? image }
    var loopCount: Int { previewSurface?.loopCount ?? looper?.loopCount ?? 0 }
    var playbackTime: Double { let value = previewSurface?.playbackTime ?? player?.currentTime().seconds ?? 0; return value.isFinite ? value : 0 }
    func showPreview(_ surface: VideoWallpaperSurface) {
        clearPreview(); previewSurface = surface; surface.frame = bounds
        surface.autoresizingMask = [.width, .height]; addSubview(surface)
        setAccessibilityValue("Expanded video wallpaper")
        setAccessibilityHelp("Double-click or press Escape to return the video to its print.")
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Return video to print", handler: { [weak self] in
            self?.onDone?(); return self != nil
        })])
    }
    func clearPreview() {
        previewSurface?.stop(); previewSurface?.removeFromSuperview(); previewSurface = nil
        setAccessibilityValue(nil); setAccessibilityHelp(nil); setAccessibilityCustomActions(nil)
    }
    func stop() {
        clearPreview()
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
    @ObservationIgnored private let systemWallpaper: SystemWallpaperSync
    @ObservationIgnored private var displayAwake = true
    @ObservationIgnored private var sessionActive = true
    @ObservationIgnored private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @ObservationIgnored private let motionPreference: @MainActor () -> Bool
    @ObservationIgnored private let presentingWindows: Bool
    @ObservationIgnored private let widgetSurfaces: @MainActor () -> [DesktopWidgetSurface]
    @ObservationIgnored private var preview: VideoWallpaperPreview?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onDone: (() -> Void)?

    init(wallpapers: URL, systemWallpaper: SystemWallpaperSync? = nil, presentingWindows: Bool = true,
         motionPreference: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         widgetSurfaces: @escaping @MainActor () -> [DesktopWidgetSurface] = { DesktopWidgetSurfaces.read() }) {
        self.wallpapers = wallpapers
        self.systemWallpaper = systemWallpaper ?? SystemWallpaperSync(journalURL: wallpapers.deletingLastPathComponent().appendingPathComponent("system-wallpaper.json"))
        self.presentingWindows = presentingWindows; self.motionPreference = motionPreference; reduceMotion = motionPreference()
        self.widgetSurfaces = widgetSurfaces
    }
    var previewItemID: UUID? { preview?.item.id }
    private var previewSnapshot: PrintItem? { preview?.item }
    var currentPreviewSurface: VideoWallpaperSurface? { preview.flatMap { panels[$0.displayID]?.contentView as? WallpaperView }?.previewSurface }
    var previewReturning: Bool { currentPreviewSurface?.returning ?? false }
    var windowsVisible: Bool { panels.values.contains(where: \.isVisible) || widgetMasks.contains(where: \.isVisible) }
    var menuBarSynchronized: Bool { (settings.wallpaper.kind != .system || currentPreviewSurface != nil) && systemWallpaper.synchronized }
    var windowNumbers: Set<Int> { Set(panels.values.map(\.windowNumber) + widgetMasks.map(\.windowNumber)) }
    var widgetCoverCount: Int { widgetMasks.count }
    var keyboardFocused: Bool { panels.values.contains { $0.isKeyWindow && $0.firstResponder === $0.contentView } }
    var isVideoPlaying: Bool { panels.values.contains { ($0.contentView as? WallpaperView)?.isPlaying == true } }
    var videoTime: Double { currentPreviewSurface?.playbackTime ?? (panels.values.first?.contentView as? WallpaperView)?.playbackTime ?? 0 }
    var videoLoops: Int { currentPreviewSurface?.loopCount ?? (panels.values.first?.contentView as? WallpaperView)?.loopCount ?? 0 }
    var printLevel: NSWindow.Level {
        // Focus can reorder windows within a level. Prints must stay strictly
        // above the wallpaper even after the background becomes key.
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + (widgetsCovered ? 4 : iconsCovered ? 2 : -1))
    }

    func apply(_ settings: DesktopSettings) {
        let switchingToSystem = settings.wallpaper.kind == .system && self.settings.wallpaper.kind != .system
        if let preview, self.settings.wallpaper != settings.wallpaper ||
            !NSScreen.screens.contains(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == preview.displayID }) ||
            (currentPreviewSurface != nil && panels[preview.displayID]?.frame != DesktopWindows.screen(for: preview.displayID)?.frame) {
            clearPreview(restore: false, notify: false)
        }
        self.settings = settings
        let screens = NSScreen.screens
        // A preview owns its native poster until it returns. Ordinary focus,
        // widget and settings refreshes must not overwrite it with the base image.
        if currentPreviewSurface != nil { syncPanels(); return }
        if settings.wallpaper.kind == .system {
            if switchingToSystem { mediaKey = ""; loadTask?.cancel(); loadTask = nil }
            do { try systemWallpaper.restore() }
            catch { problem = error.localizedDescription; loading = false; onChange?(); return }
        }
        if preview == nil && settings.wallpaper.kind == .system && !settings.hideDesktopFiles && !settings.widgetsHidden {
            stopPanels(); mediaKey = ""; loadTask?.cancel(); loading = false; problem = nil; iconsCovered = false; widgetsCovered = false; return
        }
        let sources: [(UInt32, URL)] = screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let url: URL?
            if settings.wallpaper.kind == .system { url = systemWallpaper.currentImageURL(for: number.uint32Value) }
            else if let filename = settings.wallpaper.posterFile ?? settings.wallpaper.assetFile { url = wallpapers.appendingPathComponent(filename) }
            else { url = nil }
            return url.map { (number.uint32Value, $0) }
        }
        let key = settings.wallpaper.kind.rawValue + ":" + sources.map { "\($0.0)=\($0.1.path)" }.joined(separator: "|")
        if key == mediaKey && !panels.isEmpty {
            if settings.wallpaper.kind != .system, let url = sources.first?.1 {
                do { try systemWallpaper.apply(url, displays: sources.map(\.0)) }
                catch { problem = error.localizedDescription }
            }
            installPreview(); syncPanels(); return
        }
        mediaKey = key; loadTask?.cancel(); loading = true; problem = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard sources.count == screens.count, !sources.isEmpty else { throw CorkError("Cork could not read this system wallpaper. Choose an image or video in Wallpaper settings.") }
                var prepared: [(UInt32, CGImage)] = []
                for (id, url) in sources { prepared.append((id, try await loader.image(at: url))); try Task.checkCancellation() }
                guard mediaKey == key else { return }
                if settings.wallpaper.kind != .system, let url = sources.first?.1 {
                    try systemWallpaper.apply(url, displays: sources.map(\.0))
                }
                // Native wallpaper loading can replace the focused panel after
                // a roll. Transfer focus only if it still belongs to that panel
                // now, so switching to another app during the load wins.
                let focusedDisplay = panels.first(where: { $0.value.isKeyWindow })?.key
                stopPanels()
                for (id, image) in prepared {
                    guard let screen = DesktopWindows.screen(for: id) else { continue }
                    let panel = WallpaperPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                    panel.acceptsDesktopFocus = true
                    panel.backgroundColor = .black; panel.isOpaque = true; panel.hasShadow = false
                    panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
                    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                    panel.title = "Cork Wallpaper"; panel.identifier = NSUserInterfaceItemIdentifier("cork-wallpaper-\(id)")
                    let video = settings.wallpaper.kind == .video ? settings.wallpaper.assetFile.map { wallpapers.appendingPathComponent($0) } : nil
                    let view = WallpaperView(image: image, video: video) { [weak self] message in
                        guard let self, self.mediaKey == key else { return }
                        self.problem = message; self.onChange?()
                    }
                    view.onDone = { [weak self] in self?.onDone?() }
                    view.onDoubleClick = { [weak self] in self?.toggleCurrentPreview() }
                    panel.contentView = view
                    panels[id] = panel
                }
                loading = false; installPreview(); syncPanels()
                if presentingWindows, let focusedDisplay { panels[focusedDisplay]?.focusDesktop() }
                onChange?()
            } catch is CancellationError {} catch {
                guard mediaKey == key else { return }
                loading = false; problem = error.localizedDescription
                clearPreview(restore: false, notify: false)
                // Keep a previously rendered wallpaper rather than flashing an empty screen.
                if panels.isEmpty { iconsCovered = false }
                onChange?()
            }
        }
    }
    private func syncPanels() {
        let hide = settings.hideDesktopFiles
        let widgets = widgetSurfaces(); detectedWidgets = widgets.count
        stopWidgetMasks()
        for (id, panel) in panels {
            if let screen = DesktopWindows.screen(for: id) { panel.setFrame(screen.frame, display: true) }
            panel.level = NSWindow.Level(rawValue: hide ? Int(CGWindowLevelForKey(.desktopIconWindow)) + (settings.widgetsHidden ? 3 : 1) : Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            // Finder icons remain above this layer when visible; empty wallpaper
            // still focuses Cork so its ordinary menu shortcuts work.
            panel.ignoresMouseEvents = false
            if presentingWindows { panel.orderFrontRegardless() }
            (panel.contentView as? WallpaperView)?.setPlaying(preview?.displayID != id && !settings.wallpaper.paused && !reduceMotion && displayAwake && sessionActive)
            (panel.contentView as? WallpaperView)?.previewSurface?.setPlaying(displayAwake && sessionActive)
            if settings.widgetsHidden && !hide, let screen = DesktopWindows.screen(for: id), let base = panel.contentView as? WallpaperView {
                for widget in widgets {
                    let rect = widget.rect.intersection(screen.frame)
                    guard !rect.isNull, rect.width > 1, rect.height > 1 else { continue }
                    let mask = WallpaperPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                    mask.backgroundColor = .clear; mask.isOpaque = true; mask.hasShadow = false; mask.isReleasedWhenClosed = false
                    mask.hidesOnDeactivate = false; mask.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                    mask.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
                    mask.title = "Cork Widget Cover"
                    let maskView = WidgetWallpaperView(image: base.displayImage, player: base.mediaPlayer,
                        canvas: CGRect(x: screen.frame.minX - rect.minX, y: screen.frame.minY - rect.minY, width: screen.frame.width, height: screen.frame.height))
                    maskView.onFocus = { [weak panel] in panel?.focusDesktop() }
                    maskView.onDoubleClick = { [weak self] in self?.toggleCurrentPreview() }; mask.contentView = maskView
                    if presentingWindows { mask.orderFrontRegardless() }; widgetMasks.append(mask)
                }
            }
        }
        iconsCovered = hide && !panels.isEmpty
        widgetsCovered = settings.widgetsHidden && !panels.isEmpty
    }
    func refreshWidgets() {
        if preview != nil || settings.wallpaper.kind != .system { apply(settings) }
        else if settings.widgetsHidden { syncPanels() }
        onChange?()
    }
    func setDisplayAwake(_ awake: Bool) { displayAwake = awake; syncPanels() }
    func setSessionActive(_ active: Bool) { sessionActive = active; syncPanels() }
    func updateMotionPreference() { reduceMotion = motionPreference(); currentPreviewSurface?.motionPreferenceChanged(); syncPanels() }
    func togglePreview(_ value: VideoWallpaperPreview) {
        if preview?.item.id == value.item.id { toggleCurrentPreview(); return }
        clearPreview(restore: preview != nil, notify: false); preview = value
        if panels[value.displayID] != nil { installPreview(); syncPanels() }
        else { apply(settings) }
        onChange?()
    }
    func reconcilePreview(board: Board, editing: Bool) {
        guard let snapshot = previewSnapshot else { return }
        if editing || board.hidden || snapshot.isHidden || board.items.first(where: { $0.id == snapshot.id }) != snapshot {
            finishPreview(animated: false)
        }
    }
    func toggleCurrentPreview() {
        guard let preview else { return }
        if let surface = currentPreviewSurface, surface.returning, let screen = DesktopWindows.screen(for: preview.displayID) {
            surface.expand(from: preview.origin.relative(to: screen.frame), resume: true); syncPanels(); onChange?()
        } else { finishPreview() }
    }
    func finishPreview(animated: Bool = true) {
        guard let preview else { return }
        guard animated, let surface = currentPreviewSurface, let screen = DesktopWindows.screen(for: preview.displayID) else {
            clearPreview(restore: true); return
        }
        surface.collapse(to: preview.origin.relative(to: screen.frame)) { [weak self] in
            guard self?.preview?.item.id == preview.item.id else { return }
            self?.clearPreview(restore: true)
        }
    }
    private func installPreview() {
        guard let preview, currentPreviewSurface == nil, let panel = panels[preview.displayID],
              let base = panel.contentView as? WallpaperView, let screen = DesktopWindows.screen(for: preview.displayID) else { return }
        do {
            try systemWallpaper.apply(preview.posterURL, displays: [preview.displayID])
            let surface = VideoWallpaperSurface(preview: preview) { [weak self] in
                guard let self, self.preview?.item.id == preview.item.id else { return }
                self.clearPreview(restore: true); self.problem = "This video could not play as wallpaper. Your previous wallpaper is restored."; self.onChange?()
            }
            surface.reduceMotion = { [weak self] in self?.reduceMotion ?? true }
            base.showPreview(surface); surface.expand(from: preview.origin.relative(to: screen.frame))
            if presentingWindows && NSApp.isActive { panel.makeKey(); panel.makeFirstResponder(base) }
        } catch {
            clearPreview(restore: true); problem = error.localizedDescription; onChange?()
        }
    }
    private func clearPreview(restore: Bool, notify: Bool = true) {
        let hadPreview = preview != nil; preview = nil
        for panel in panels.values { (panel.contentView as? WallpaperView)?.clearPreview() }
        if restore && hadPreview { apply(settings) }
        if notify && hadPreview { onChange?() }
    }
    private func stopPanels() {
        stopWidgetMasks()
        for panel in panels.values { (panel.contentView as? WallpaperView)?.stop(); panel.close() }
        panels.removeAll()
    }
    private func stopWidgetMasks() {
        for panel in widgetMasks { (panel.contentView as? WidgetWallpaperView)?.stop(); panel.close() }; widgetMasks.removeAll()
    }
    func stop() {
        preview = nil
        mediaKey = ""; loadTask?.cancel(); loadTask = nil
        do { try systemWallpaper.restore() }
        catch { problem = error.localizedDescription }
        stopPanels(); iconsCovered = false; widgetsCovered = false
    }
}
