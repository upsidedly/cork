import AppKit
import AVFoundation
import QuartzCore
import CorkCore

struct VideoWallpaperOrigin {
    var center: CGPoint
    var size: CGSize
    var angle: Double

    func relative(to screen: CGRect) -> Self {
        Self(center: CGPoint(x: center.x - screen.minX, y: center.y - screen.minY), size: size, angle: angle)
    }
}

/// A temporary presentation. The saved board and wallpaper remain the source of truth.
@MainActor struct VideoWallpaperPreview {
    var item: PrintItem
    var displayID: UInt32
    var videoURL: URL
    var posterURL: URL
    var poster: NSImage
    var origin: VideoWallpaperOrigin
    var startTime: Double
}

@MainActor final class VideoWallpaperSurface: NSView {
    let poster: NSImage
    private let canvas = CALayer()
    private let still = CALayer()
    private let movie = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observation: NSKeyValueObservation?
    private var completion: Task<Void, Never>?
    private var stopped = false
    private(set) var returning = false
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var isPlaying: Bool { (player?.rate ?? 0) > 0 }
    var playbackTime: Double { let value = player?.currentTime().seconds ?? 0; return value.isFinite ? value : 0 }
    var muted: Bool { player?.isMuted ?? true }
    var hasPlayer: Bool { player != nil }
    var mediaPlayer: AVPlayer? { player }
    var loopCount: Int { looper?.loopCount ?? 0 }
    var animating: Bool { !(canvas.animationKeys() ?? []).isEmpty }
    var imageBounds: CGRect { canvas.bounds }

    init(preview: VideoWallpaperPreview, failure: @escaping @MainActor () -> Void) {
        poster = preview.poster
        super.init(frame: .zero)
        wantsLayer = true; setAccessibilityElement(false)
        canvas.masksToBounds = true; layer?.addSublayer(canvas)
        still.contents = poster.cgImage(forProposedRect: nil, context: nil, hints: nil)
        still.contentsGravity = .resizeAspectFill; canvas.addSublayer(still)
        movie.videoGravity = .resizeAspectFill; canvas.addSublayer(movie)
        let queue = AVQueuePlayer(); queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        let item = AVPlayerItem(url: preview.videoURL); item.preferredForwardBufferDuration = 1
        let loop = AVPlayerLooper(player: queue, templateItem: item)
        player = queue; looper = loop; movie.player = queue
        observation = VideoStatusObservation.observe(loop) { [weak self] failed in
            guard let self, failed, !self.stopped else { return }; failure()
        }
        if preview.startTime > 0 {
            queue.seek(to: CMTime(seconds: preview.startTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func expand(from origin: VideoWallpaperOrigin, resume: Bool = false) {
        completion?.cancel(); completion = nil; returning = false
        if !resume { move(size: origin.size, center: origin.center, angle: origin.angle, animated: false) }
        move(size: bounds.size, center: CGPoint(x: bounds.midX, y: bounds.midY), angle: 0, animated: !reduceMotion())
    }
    func collapse(to origin: VideoWallpaperOrigin, finished: @escaping @MainActor () -> Void) {
        completion?.cancel(); returning = true
        let animate = !reduceMotion()
        move(size: origin.size, center: origin.center, angle: origin.angle, animated: animate)
        if !animate { finished(); return }
        completion = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(320)) } catch { return }
            guard let self, !Task.isCancelled, !self.stopped, self.returning else { return }
            self.completion = nil; finished()
        }
    }
    private func move(size: CGSize, center: CGPoint, angle: Double, animated: Bool) {
        func set(_ target: CALayer, size: CGSize, center: CGPoint, angle: Double) {
            let visible = target.presentation() ?? target
            let changes: [(String, Any, Any)] = [
                ("bounds", NSValue(rect: visible.bounds), NSValue(rect: CGRect(origin: .zero, size: size))),
                ("position", NSValue(point: visible.position), NSValue(point: center)),
                ("transform.rotation.z", visible.value(forKeyPath: "transform.rotation.z") ?? 0, angle)
            ]
            target.removeAllAnimations()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            target.bounds = CGRect(origin: .zero, size: size); target.position = center
            target.transform = CATransform3DMakeRotation(angle, 0, 0, 1)
            CATransaction.commit()
            if animated {
                for (key, from, to) in changes {
                    let animation = CABasicAnimation(keyPath: key); animation.fromValue = from; animation.toValue = to
                    animation.duration = 0.32; animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    target.add(animation, forKey: key)
                }
            }
        }
        set(canvas, size: size, center: center, angle: angle)
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        set(still, size: size, center: middle, angle: 0); set(movie, size: size, center: middle, angle: 0)
    }
    func setPlaying(_ playing: Bool) { if playing { player?.play() } else { player?.pause() } }
    func motionPreferenceChanged() {
        guard reduceMotion() else { return }
        for layer in [canvas, still, movie] { layer.removeAllAnimations() }
    }
    func stop() {
        stopped = true; completion?.cancel(); completion = nil; observation = nil
        player?.pause(); looper?.disableLooping(); player?.removeAllItems()
        movie.player = nil; player = nil; looper = nil
        for layer in [canvas, still, movie] { layer.removeAllAnimations() }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stop() }; super.viewWillMove(toWindow: newWindow)
    }
}
