import AppKit
import ApplicationServices
import CorkCore

struct MinimizeReport: Codable, Sendable {
    var minimized = 0
    var alreadyMinimized = 0
    var unsupported = 0
    var failed = 0
    var unresponsiveApps = 0
    var timedOut = false
}

/// AX objects are created and used only inside this actor. No window titles are read.
actor WindowMinimizer {
    func minimize(processes: [Int32]) throws -> MinimizeReport {
        guard AXIsProcessTrusted() else { throw CorkError("Enable Cork in System Settings → Privacy & Security → Accessibility to minimize other apps’ windows.") }
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: .seconds(4))
        var report = MinimizeReport()
        for pid in processes {
            try Task.checkCancellation()
            guard clock.now < deadline else { report.timedOut = true; break }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.2)
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
            guard status == .success, let windows = value as? [AXUIElement] else {
                if status == .cannotComplete { report.unresponsiveApps += 1 }
                continue
            }
            for window in windows.prefix(500) {
                try Task.checkCancellation()
                guard clock.now < deadline else { report.timedOut = true; break }
                AXUIElementSetMessagingTimeout(window, 0.2)
                var minimized: CFTypeRef?
                let read = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                guard read == .success else { report.unsupported += 1; continue }
                if (minimized as? Bool) == true { report.alreadyMinimized += 1; continue }
                var modal: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXModalAttribute as CFString, &modal) == .success,
                   (modal as? Bool) == true { report.unsupported += 1; continue }
                var writable = DarwinBoolean(false)
                guard AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &writable) == .success, writable.boolValue else {
                    report.unsupported += 1; continue
                }
                // One-way operation. Never hide an app, restore a window, or invoke Show Desktop.
                guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else {
                    report.failed += 1; continue
                }
                var confirmed: CFTypeRef?
                if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &confirmed) == .success,
                   (confirmed as? Bool) == true { report.minimized += 1 }
                else { report.failed += 1 }
            }
            if report.timedOut { break }
        }
        return report
    }
}
