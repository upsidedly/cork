import AppKit
import AVFoundation
import CorkCore

@main @MainActor enum VideoHoverChecks {
    static func require(_ value: Bool, _ message: String) throws { if !value { throw CorkError(message) } }
    static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try require(predicate(), "Playback did not reach its expected state within five seconds.")
    }
    static func main() async {
        do { try await run() }
        catch { print("FAIL native video playback: \(error.localizedDescription)"); exit(1) }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 2 else { throw CorkError("Pass a local video fixture path.") }
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: CommandLine.arguments[1]), asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
        let image = try await generator.image(at: .zero).image
        let printHeight = PrintStyle.pushpin.printSize(imageWidth: Double(image.width), imageHeight: Double(image.height), width: 320).1
        var item = PrintItem(assetFile: "cover.png", title: "", style: .pushpin, width: 320, height: printHeight,
            rotation: 5, imageWidth: Double(image.width), imageHeight: Double(image.height), kind: .video)
        item.video = VideoAttachment(file: "fixture.mp4", duration: 2, posterTime: 0.5, colourSamples: [.init(coverages: [.blue: 1])])
        let panel = PrintPanel(contentRect: CGRect(x: 50, y: 100, width: 450, height: item.height + 120),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; defer { panel.close() }
        let view = VideoPrintView(item: item, image: NSImage(cgImage: image, size: .zero), videoURL: url)
        view.reduceMotion = { false }; panel.contentView = view
        var saves = 0; view.onChange = { _, _ in saves += 1 }
        func pointer(_ point: CGPoint) throws -> NSEvent {
            guard let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 1,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0) else { throw CorkError("No test pointer event") }
            return event
        }
        func space() throws -> NSEvent {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: panel.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49) else { throw CorkError("No test key event") }
            return event
        }
        try require(!view.hasPlayer && !view.isPlaying, "Static prints must not preload a decoder.")
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        view.mouseMoved(with: try pointer(center))
        try await waitUntil { view.isPlaying && view.playbackTime > 0.1 }
        try require(view.playbackMuted, "Hover playback must be muted.")
        for style in PrintStyle.imageStyles {
            var styled = item; styled.style = style; styled.rotation = -12
            styled.height = style.printSize(imageWidth: item.imageWidth, imageHeight: item.imageHeight, width: item.width).1
            view.item = styled; view.syncPlayback(); view.layoutSubtreeIfNeeded()
            guard let clip = view.subviews.first(where: { $0.layer is AVPlayerLayer }) else { throw CorkError("Missing movie surface") }
            let aperture = PrintRenderer.imageRect(item: styled), angle = styled.rotation * .pi / 180
            let expected = [CGPoint(x: aperture.minX, y: aperture.minY), CGPoint(x: aperture.maxX, y: aperture.minY),
                            CGPoint(x: aperture.maxX, y: aperture.maxY), CGPoint(x: aperture.minX, y: aperture.maxY)].map {
                CGPoint(x: view.bounds.midX + $0.x * cos(angle) - $0.y * sin(angle),
                        y: view.bounds.midY + $0.x * sin(angle) + $0.y * cos(angle))
            }
            let actual = [CGPoint.zero, CGPoint(x: clip.bounds.maxX, y: 0), CGPoint(x: clip.bounds.maxX, y: clip.bounds.maxY), CGPoint(x: 0, y: clip.bounds.maxY)].map { clip.convert($0, to: view) }
            try require(expected.allSatisfy { point in actual.contains { hypot($0.x - point.x, $0.y - point.y) < 0.1 } }, "\(style.title) movie aperture must match the rotated still cover.")
        }
        view.item = item; view.syncPlayback()
        print("PASS every print treatment keeps the movie in the rotated image aperture")
        view.mouseMoved(with: try pointer(CGPoint(x: 1, y: 1)))
        try require(!view.hasPlayer && !view.isPlaying && view.item == item && saves == 0, "Leaving must restore the cover, release decoding and preserve the model.")
        print("PASS static rest, muted hover playback, exit cleanup and unchanged model")
        view.mouseMoved(with: try pointer(center)); view.editing = true
        try require(!view.hasPlayer, "Editing must stop the movie.")
        view.editing = false; view.reduceMotion = { true }
        view.mouseMoved(with: try pointer(center)); try require(!view.hasPlayer, "Reduce Motion must suppress hover autoplay.")
        view.keyDown(with: try space()); try await waitUntil { view.isPlaying }
        view.keyDown(with: try space()); try require(!view.hasPlayer, "Space must also pause pending/active playback.")
        print("PASS editing, Reduce Motion and keyboard alternative")
        view.keyDown(with: try space()); view.playbackPaused = true
        try require(!view.hasPlayer, "Sleep/session pause must release the player.")
        view.playbackPaused = false; view.keyDown(with: try space())
        panel.contentView = nil
        try require(!view.hasPlayer, "Removing a print must release its player.")
        print("PASS sleep/session pause and removal cleanup")
        let missing = VideoPrintView(item: item, image: NSImage(cgImage: image, size: .zero), videoURL: url.deletingLastPathComponent().appendingPathComponent("missing-fixture.mp4"))
        missing.reduceMotion = { false }; panel.contentView = missing
        var reported = false; missing.onFailure = { _ in reported = true }
        missing.mouseMoved(with: try pointer(CGPoint(x: missing.bounds.midX, y: missing.bounds.midY)))
        try await waitUntil { missing.failed }
        try require(reported && !missing.hasPlayer && !missing.isPlaying && missing.item == item, "A missing source must report failure, release decoding and preserve its still print.")
        panel.contentView = nil
        print("PASS unavailable media reports failure and preserves the cover")
        print("5/5 native video playback checks passed; hidden test window.")
    }
}
