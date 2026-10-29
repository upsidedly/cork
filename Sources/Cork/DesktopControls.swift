import AppKit
import ApplicationServices
import Observation
import CorkCore

@MainActor @Observable final class DesktopControls {
    private(set) var accessibilityAllowed = AXIsProcessTrusted()
    private(set) var shortcutRegistered = false
    private(set) var randomizeShortcutRegistered = false
    private(set) var randomizeShortcutError: String?
    private(set) var shortcutError: String?
    private(set) var recordingShortcut = false
    private(set) var minimizing = false
    private(set) var lastReport: MinimizeReport?
    private(set) var actionError: String?
    private(set) var gestureMonitoring = false
    private(set) var compatibleTrackpads: Int32 = 0
    private(set) var trackpadAvailable = true
    @ObservationIgnored private let shortcut = GlobalDesktopShortcut(signature: 0x43524B4D)
    @ObservationIgnored private let randomize = GlobalDesktopShortcut(signature: 0x43524B52)
    @ObservationIgnored private let gesture = TrackpadMinimizeGesture()
    @ObservationIgnored private let worker = WindowMinimizer()
    @ObservationIgnored private var settings = DesktopControlSettings()
    @ObservationIgnored private var minimizeTask: Task<MinimizeReport, Error>?
    @ObservationIgnored private var triggerTask: Task<Void, Never>?
    @ObservationIgnored private var displayAwake = true
    @ObservationIgnored private var sessionActive = true
    @ObservationIgnored private var preparingShortcut = false
    @ObservationIgnored var onNeedsAccessibility: (() -> Void)?
    @ObservationIgnored var onRandomize: (() -> Void)?
    @ObservationIgnored var onChange: (() -> Void)?

    init() {
        shortcut.onPress = { [weak self] in self?.requestMinimize() }
        randomize.onPress = { [weak self] in
            guard let self, !self.recordingShortcut, !self.preparingShortcut, self.displayAwake, self.sessionActive else { return }
            self.onRandomize?()
        }
        gesture.onGesture = { [weak self] in self?.requestMinimize() }
        gesture.probe(); updateGestureStatus()
    }
    func apply(_ settings: DesktopControlSettings) {
        // Selection/activation refreshes must not discard a binding reserved for a save.
        guard !preparingShortcut else { return }
        self.settings = settings; refreshAccess()
    }
    func finishConfiguration(_ settings: DesktopControlSettings, committed: Bool = true) {
        if committed { shortcut.commit(); randomize.commit() } else { shortcut.discard(); randomize.discard() }
        preparingShortcut = false; apply(settings)
    }
    func refreshAccess() {
        accessibilityAllowed = AXIsProcessTrusted()
        if !recordingShortcut && !preparingShortcut {
            do { try shortcut.register(settings.shortcutEnabled ? settings.shortcut : nil); shortcutError = nil }
            catch { shortcutError = error.localizedDescription }
            do { try randomize.register(settings.wallShortcut.enabled ? settings.wallShortcut.shortcut : nil); randomizeShortcutError = nil }
            catch { randomizeShortcutError = error.localizedDescription }
        }
        shortcutRegistered = shortcut.isRegistered
        randomizeShortcutRegistered = randomize.isRegistered
        gesture.apply(enabled: settings.anchoredSwipeEnabled && accessibilityAllowed && displayAwake && sessionActive)
        updateGestureStatus()
    }
    private func updateGestureStatus() {
        gestureMonitoring = gesture.monitoring; compatibleTrackpads = gesture.trackpads; trackpadAvailable = gesture.available
    }
    func beginRecording() {
        recordingShortcut = true; shortcut.unregister(); randomize.unregister()
        shortcutRegistered = false; randomizeShortcutRegistered = false; shortcutError = nil; randomizeShortcutError = nil
    }
    /// Reserve the new key before the asynchronous save; a collision never discards the saved choice.
    func prepare(_ next: DesktopControlSettings) throws {
        try next.validate(); preparingShortcut = true
        do {
            try shortcut.reserve(next.shortcutEnabled ? next.shortcut : nil)
            try randomize.reserve(next.wallShortcut.enabled ? next.wallShortcut.shortcut : nil)
        }
        catch { shortcut.discard(); randomize.discard(); preparingShortcut = false; throw error }
        shortcutRegistered = shortcut.isRegistered
    }
    func endRecording() { recordingShortcut = false; refreshAccess() }
    func reconnectTrackpad() { gesture.stop(); gesture.probe(); refreshAccess() }
    func setDisplayAwake(_ value: Bool) { displayAwake = value; refreshAccess() }
    func setSessionActive(_ value: Bool) { sessionActive = value; refreshAccess() }
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    func requestMinimize() {
        guard !recordingShortcut, !preparingShortcut, displayAwake, sessionActive, triggerTask == nil else { return }
        refreshAccess()
        triggerTask = Task { [weak self] in
            guard let self else { return }
            do { _ = try await minimizeAll() }
            catch is CancellationError { }
            catch {
                actionError = error.localizedDescription
                if !AXIsProcessTrusted() { onNeedsAccessibility?() }
            }
            triggerTask = nil; onChange?()
        }
    }
    func minimizeAll() async throws -> MinimizeReport {
        if let minimizeTask { return try await minimizeTask.value }
        accessibilityAllowed = AXIsProcessTrusted()
        guard accessibilityAllowed else { throw CorkError("Enable Cork in System Settings → Privacy & Security → Accessibility to minimize other apps’ windows.") }
        actionError = nil; minimizing = true
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let processes = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.processIdentifier != ownPID && $0.activationPolicy != .prohibited
        }.map(\.processIdentifier)
        let task = Task { [worker] in
            var report = try await worker.minimize(processes: processes)
            try Task.checkCancellation()
            // Desktop paper, wallpaper and sheets are not miniaturizable windows.
            for window in NSApp.windows where window.isVisible && !window.isMiniaturized && window.styleMask.contains(.miniaturizable) && window.attachedSheet == nil {
                window.miniaturize(nil); report.minimized += 1
            }
            return report
        }
        minimizeTask = task
        do {
            let report = try await task.value
            lastReport = report; minimizeTask = nil; minimizing = false; onChange?(); return report
        } catch {
            minimizeTask = nil; minimizing = false; actionError = error.localizedDescription; onChange?(); throw error
        }
    }
    func finish() async { _ = try? await minimizeTask?.value }
    func stop() {
        triggerTask?.cancel(); minimizeTask?.cancel(); triggerTask = nil; minimizeTask = nil
        shortcut.stop(); randomize.stop(); gesture.stop(); shortcutRegistered = false; randomizeShortcutRegistered = false; gestureMonitoring = false
    }
    func description() throws -> JSONValue {
        .object([
            "settings": try JSONValue.encode(settings), "shortcut_display": .string(settings.shortcut.display),
            "accessibility_allowed": .bool(AXIsProcessTrusted()), "shortcut_registered": .bool(shortcutRegistered),
            "recording_shortcut": .bool(recordingShortcut), "shortcut_error": shortcutError.map(JSONValue.string) ?? .null,
            "configuring_shortcut": .bool(preparingShortcut),
            "randomize_shortcut_display": .string(settings.wallShortcut.shortcut.display),
            "randomize_shortcut_registered": .bool(randomizeShortcutRegistered),
            "randomize_shortcut_error": randomizeShortcutError.map(JSONValue.string) ?? .null,
            "trackpad_available": .bool(trackpadAvailable), "compatible_trackpads": .number(Double(compatibleTrackpads)),
            "gesture_monitoring": .bool(gestureMonitoring), "gesture_frames_received": .number(Double(gesture.framesReceived)),
            "gestures_recognized": .number(Double(gesture.gesturesRecognized)), "minimizing": .bool(minimizing),
            "last_report": try lastReport.map(JSONValue.encode) ?? .null
        ])
    }
}
