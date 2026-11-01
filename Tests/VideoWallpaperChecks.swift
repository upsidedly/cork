import AppKit
import AVFoundation
import ImageIO
import CorkCore

// The environment only needs this display lookup; app/controller startup and
// global shortcuts are deliberately absent from the hidden native harness.
@MainActor enum DesktopWindows {
    static func screen(for id: UInt32) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
    }
}

@MainActor final class PreviewWallpaperAccess: SystemWallpaperAccess {
    var images: [UInt32: SystemWallpaperImage]
    var displayIDs: [UInt32] { Array(images.keys) }
    init(id: UInt32, original: URL) {
        images = [id: SystemWallpaperImage(url: original, scaling: NSImageScaling.scaleNone.rawValue, clipping: false, fill: [0.1,0.2,0.3,1])]
    }
    func image(for displayID: UInt32) -> SystemWallpaperImage? { images[displayID] }
    func setImage(_ image: SystemWallpaperImage, for displayID: UInt32) throws { images[displayID] = image }
}

@MainActor final class PreviewPreferences { var reduced = false }

@main @MainActor enum VideoWallpaperChecks {
    static func require(_ value: Bool, _ message: String) throws { if !value { throw CorkError(message) } }
    static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try require(predicate(), "Native preview did not reach its expected state within five seconds.")
    }
    static func main() async {
        do { try await run() } catch { print("FAIL video wallpaper: \(error.localizedDescription)"); exit(1) }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 3, let screen = NSScreen.screens.first,
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { throw CorkError("Pass a local video and PNG cover on a logged-in Mac.") }
        _ = NSApplication.shared
        let videoURL = URL(fileURLWithPath: CommandLine.arguments[1]), posterURL = URL(fileURLWithPath: CommandLine.arguments[2])
        guard let poster = NSImage(contentsOf: posterURL) else { throw CorkError("Missing PNG fixture") }
        let duration = try await AVURLAsset(url: videoURL).load(.duration).seconds
        var item = PrintItem(assetFile: posterURL.lastPathComponent, title: "", style: .polaroid, width: 320, height: 350,
            rotation: -11, displayID: id, imageWidth: poster.size.width, imageHeight: poster.size.height, kind: .video)
        item.video = VideoAttachment(file: videoURL.lastPathComponent, duration: duration, posterTime: duration * 0.25,
            colourSamples: [.init(coverages: [.blue: 1])])
        let panel = PrintPanel(contentRect: CGRect(x: screen.frame.minX + 80, y: screen.frame.minY + 120, width: 500, height: 600),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; defer { panel.close() }
        let printView = VideoPrintView(item: item, image: poster, videoURL: videoURL); panel.contentView = printView
        var captured: VideoWallpaperPreview?, requests = 0
        printView.onToggleWallpaper = { value in captured = value; requests += 1 }
        func doubleClick(_ windowNumber: Int) throws -> NSEvent {
            guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 100, y: 100), modifierFlags: [], timestamp: 1,
                windowNumber: windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 0) else { throw CorkError("No pointer event") }
            return event
        }
        func key(_ code: UInt16) throws -> NSEvent {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: panel.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code) else { throw CorkError("No keyboard event") }
            return event
        }
        for style in PrintStyle.imageStyles {
            item.style = style; printView.item = item
            printView.mouseDown(with: try doubleClick(panel.windowNumber))
            guard let request = captured else { throw CorkError("Double-click did not request wallpaper") }
            let aperture = PrintRenderer.imageRect(item: item), a = item.rotation * .pi / 180
            let dx = aperture.midX * cos(a) - aperture.midY * sin(a), dy = aperture.midX * sin(a) + aperture.midY * cos(a)
            let expected = CGPoint(x: panel.frame.midX + dx, y: panel.frame.midY - dy)
            try require(hypot(request.origin.center.x - expected.x, request.origin.center.y - expected.y) < 0.1 &&
                abs(request.origin.angle + a) < 0.001 && request.origin.size == aperture.size,
                "\(style.title) must expand from its real rotated image aperture.")
            try require(request.item == item && !printView.hasPlayer, "Expansion must retain the item and release print playback.")
        }
        let beforeReturn = requests; printView.keyDown(with: try key(36))
        try require(requests == beforeReturn + 1, "Return must expose the same action for keyboard users.")
        printView.editing = true; try require(!printView.requestWallpaper(), "Editing must keep double-click available for positioning.")
        printView.editing = false; printView.playbackPaused = true
        try require(!printView.requestWallpaper(), "Paused or hidden prints cannot expand."); printView.playbackPaused = false
        guard let preview = captured else { throw CorkError("Missing preview request") }
        print("PASS double-click/Return, editing guards and all rotated print apertures")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CorkVideoWallpaper-" + UUID().uuidString)
        let papers = root.appendingPathComponent("Wallpapers")
        try FileManager.default.createDirectory(at: papers, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let originalURL = root.appendingPathComponent("original.png"), baseURL = papers.appendingPathComponent("base.png")
        try FileManager.default.linkItem(at: posterURL, to: originalURL); try FileManager.default.linkItem(at: posterURL, to: baseURL)
        let access = PreviewWallpaperAccess(id: id, original: originalURL), original = access.images[id]
        let journal = root.appendingPathComponent("system-wallpaper.json")
        let sync = SystemWallpaperSync(journalURL: journal, access: access)
        let preferences = PreviewPreferences()
        let environment = DesktopEnvironment(wallpapers: papers, systemWallpaper: sync, presentingWindows: false, motionPreference: { preferences.reduced })
        defer { environment.stop() }
        environment.onDone = { [weak environment] in environment?.finishPreview() }
        var settings = DesktopSettings(); settings.wallpaper.kind = .image; settings.wallpaper.assetFile = "base.png"
        settings.hideDesktopFiles = true; settings.hideWidgets = false
        environment.apply(settings); try await waitUntil { !environment.loading }
        try require(access.images[id]?.url == baseURL, "The baseline wallpaper must be applied through the injected workspace.")
        environment.togglePreview(preview)
        try await waitUntil { environment.currentPreviewSurface?.isPlaying == true }
        guard let surface = environment.currentPreviewSurface, let base = surface.superview as? WallpaperView else { throw CorkError("Missing expanded surface") }
        try require(surface.muted && surface.hasPlayer && surface.animating && surface.imageBounds.size == screen.frame.size && !environment.windowsVisible,
            "The explicit preview must play silently, zoom to the display and stay out of foreground windows.")
        try require(access.images[id]?.url == posterURL && settings.wallpaper.assetFile == "base.png", "Native tint must use the video cover without changing saved wallpaper settings.")
        base.mouseDown(with: try doubleClick(base.window?.windowNumber ?? 0))
        try require(environment.previewReturning, "A second double-click must return the print.")
        environment.toggleCurrentPreview()
        try require(!environment.previewReturning, "A quick third toggle must reverse the return.")
        try await Task.sleep(for: .milliseconds(380))
        try require(environment.previewItemID == preview.item.id, "A cancelled return must not dismiss a newer expansion.")
        let mask = WidgetWallpaperView(image: poster, player: surface.mediaPlayer, canvas: screen.frame)
        mask.onDoubleClick = { [weak environment] in environment?.toggleCurrentPreview() }
        mask.mouseDown(with: try doubleClick(base.window?.windowNumber ?? 0)); mask.stop()
        try await waitUntil { environment.previewItemID == nil }
        try require(!surface.hasPlayer && access.images[id]?.url == baseURL && !environment.windowsVisible, "Returning must release decoding and restore the exact base wallpaper.")
        print("PASS reversible zoom, rapid toggles, native poster synchronization and no media copies")

        preferences.reduced = true; environment.updateMotionPreference(); environment.togglePreview(preview)
        try await waitUntil { environment.currentPreviewSurface?.isPlaying == true }
        guard let stillSurface = environment.currentPreviewSurface, let stillBase = stillSurface.superview as? WallpaperView else { throw CorkError("Missing reduced-motion surface") }
        try require(!stillSurface.animating && stillSurface.muted, "Reduce Motion removes zoom while preserving explicit playback.")
        if let path = ProcessInfo.processInfo.environment["CORK_VIDEO_WALLPAPER_RENDER"], let layer = stillSurface.layer {
            let movies = (layer.sublayers ?? []).flatMap { $0.sublayers ?? [] }.compactMap { $0 as? AVPlayerLayer }
            movies.forEach { $0.isHidden = true }; defer { movies.forEach { $0.isHidden = false } }
            let width = 900, height = Int(900 * stillSurface.bounds.height / stillSurface.bounds.width)
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CorkError("Could not render preview evidence") }
            context.cgContext.scaleBy(x: Double(width) / stillSurface.bounds.width, y: Double(height) / stillSurface.bounds.height)
            layer.render(in: context.cgContext)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        stillBase.keyDown(with: try key(53))
        try require(environment.previewItemID == nil && !stillSurface.hasPlayer && access.images[id]?.url == baseURL, "Escape must restore without an animation or a data edit.")
        print("PASS Reduce Motion and Escape")

        preferences.reduced = false; environment.updateMotionPreference()
        let movieURL = papers.appendingPathComponent("base.mp4"); try FileManager.default.linkItem(at: videoURL, to: movieURL)
        var movieSettings = settings; movieSettings.wallpaper.kind = .video; movieSettings.wallpaper.assetFile = "base.mp4"; movieSettings.wallpaper.posterFile = "base.png"
        environment.apply(movieSettings); try await waitUntil { !environment.loading }
        environment.togglePreview(preview)
        guard let movieBase = environment.currentPreviewSurface?.superview as? WallpaperView else { throw CorkError("Missing original video wallpaper") }
        environment.finishPreview(animated: false)
        guard let originalPlayer = movieBase.mediaPlayer else { throw CorkError("Original video wallpaper lost its player") }
        try await waitUntil { originalPlayer.rate > 0 && originalPlayer.currentTime().seconds > 0.1 }
        let originalTime = originalPlayer.currentTime().seconds
        environment.togglePreview(preview)
        try require(originalPlayer.rate == 0, "The original wallpaper must pause while another clip is expanded.")
        environment.finishPreview(animated: false)
        try require(movieBase.mediaPlayer === originalPlayer && originalPlayer.rate > 0 && originalPlayer.currentTime().seconds >= originalTime,
            "Returning must resume the same original wallpaper player without resetting it.")
        environment.apply(settings); try await waitUntil { !environment.loading }
        print("PASS existing video wallpaper pauses and resumes in place")

        for change in 0..<5 {
            var board = Board(); board.items = [preview.item]
            environment.togglePreview(preview)
            if change == 0 { board.items[0].x += 10 }
            if change == 1 { board.items[0].hidden = true }
            if change == 2 { board.items = [] }
            if change == 3 { board.hidden = true }
            environment.reconcilePreview(board: board, editing: change == 4)
            try require(environment.previewItemID == nil && access.images[id]?.url == baseURL,
                "Editing, layout, hiding, rolls and removal must cancel a stale preview.")
        }
        environment.togglePreview(preview)
        var system = DesktopSettings(); system.hideDesktopFiles = false; system.hideWidgets = false
        environment.apply(system)
        try require(environment.previewItemID == nil && access.images[id] == original, "A new wallpaper choice must not be overwritten by an old preview.")
        print("PASS stale layout/visibility guards and new wallpaper choices")

        environment.togglePreview(preview); environment.finishPreview(animated: false)
        try await Task.sleep(for: .milliseconds(150))
        try require(environment.previewItemID == nil && access.images[id] == original && !environment.windowsVisible, "A cancelled System preview must not reappear after loading.")
        environment.togglePreview(preview); try await waitUntil { environment.currentPreviewSurface?.isPlaying == true }
        environment.setDisplayAwake(false); try require(!environment.isVideoPlaying, "Screen sleep must pause the expanded video.")
        environment.setSessionActive(false); environment.setDisplayAwake(true)
        try require(!environment.isVideoPlaying, "An inactive session must remain paused.")
        environment.setSessionActive(true); try await waitUntil { environment.isVideoPlaying }
        let stopped = environment.currentPreviewSurface; environment.stop()
        try require(stopped?.hasPlayer == false && access.images[id] == original && !FileManager.default.fileExists(atPath: journal.path), "Quit must release playback and restore the native original.")
        print("PASS System wallpaper, cancelled loading, sleep/session pause and quit")

        environment.apply(settings); try await waitUntil { !environment.loading }
        var missing = preview; missing.videoURL = root.appendingPathComponent("missing.mp4")
        environment.togglePreview(missing)
        try await waitUntil { environment.previewItemID == nil }
        try require(environment.problem != nil && access.images[id]?.url == baseURL && !environment.windowsVisible, "Unavailable media must return to the original wallpaper and report its error.")
        print("PASS unavailable video recovery")
        print("7/7 native video wallpaper checks passed; hidden windows and injected native wallpaper access.")
    }
}
