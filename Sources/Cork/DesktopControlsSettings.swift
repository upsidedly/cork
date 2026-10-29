import SwiftUI
import CorkCore

struct DesktopControlsSettings: View {
    @Bindable var model: CorkController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick randomize").font(.headline)
            Toggle("Global randomize shortcut", isOn: Binding(get: { model.board.desktop.desktopControls.wallShortcut.enabled }, set: {
                model.changeControlOptions(randomizeEnabled: $0)
            }))
            HStack {
                Text("Shortcut").foregroundStyle(.secondary)
                Spacer()
                MinimizeShortcutRecorder(shortcut: model.board.desktop.desktopControls.wallShortcut.shortcut,
                    accessibilityName: "Randomize wall shortcut", begin: { model.controls.beginRecording() },
                    finish: { model.finishShortcutRecording($0, randomize: true) }).frame(width: 155, height: 28)
                Button("Reset") { model.finishShortcutRecording(RandomizeShortcutOptions().shortcut, randomize: true) }
                    .disabled(model.controls.recordingShortcut)
            }
            Text("Roll a new palette, matching wallpaper and images from any app. Kept prints stay put.").font(.caption).foregroundStyle(.secondary)
            if let error = model.controls.randomizeShortcutError { Text(error).font(.caption).foregroundStyle(.red) }
            Divider().padding(.vertical, 5)
            Text("Minimize all windows").font(.headline)
            Text("Send open windows to the Dock. They stay minimized until you restore them.").font(.callout).foregroundStyle(.secondary)
            Toggle("Global keyboard shortcut", isOn: Binding(get: { model.board.desktop.desktopControls.shortcutEnabled }, set: {
                model.changeControlOptions(shortcutEnabled: $0)
            }))
            HStack {
                Text("Shortcut").foregroundStyle(.secondary)
                Spacer()
                MinimizeShortcutRecorder(shortcut: model.board.desktop.desktopControls.shortcut,
                    begin: { model.controls.beginRecording() }, finish: { model.finishShortcutRecording($0) })
                    .frame(width: 155, height: 28).disabled(model.controls.minimizing)
                Button("Reset") { model.finishShortcutRecording(MinimizeShortcut()) }.disabled(model.controls.recordingShortcut)
            }
            if model.controls.recordingShortcut {
                Text("Press a shortcut with Command, Option or Control. Escape cancels.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.controls.shortcutError { Text(error).font(.caption).foregroundStyle(.red) }
            Toggle("Hold two fingers, swipe down with a third", isOn: Binding(get: { model.board.desktop.desktopControls.anchoredSwipeEnabled }, set: {
                model.changeControlOptions(gestureEnabled: $0)
            }))
            Text("Keep two fingers still, then slide a third finger down. Lift all fingers to repeat.").font(.caption).foregroundStyle(.secondary)
            if !model.controls.accessibilityAllowed {
                Text("Allow Accessibility so Cork can minimize windows in other apps. Your wall and photos stay in place.").font(.caption).foregroundStyle(.secondary)
                Button("Open Accessibility Settings…") { model.controls.openAccessibilitySettings() }
            } else if !model.controls.trackpadAvailable {
                Text("Trackpad input is unavailable on this macOS version. The keyboard shortcut remains available.").font(.caption).foregroundStyle(.secondary)
            } else if model.controls.compatibleTrackpads == 0 {
                HStack {
                    Text("No compatible trackpad connected.").font(.caption).foregroundStyle(.secondary)
                    Button("Check Again") { model.controls.reconnectTrackpad() }
                }
            } else if model.controls.gestureMonitoring {
                Text("Trackpad gesture ready.").font(.caption).foregroundStyle(.secondary)
            }
            Button(model.controls.minimizing ? "Minimizing…" : "Minimize Now") { model.controls.requestMinimize() }
                .disabled(!model.controls.accessibilityAllowed || model.controls.minimizing || model.controls.recordingShortcut)
            if let error = model.controls.actionError { Text(error).font(.caption).foregroundStyle(.red) }
            if let report = model.controls.lastReport {
                Text("\(report.minimized) windows minimized\(report.failed + report.unresponsiveApps > 0 || report.timedOut ? " · Some windows did not respond" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.onAppear { model.controls.refreshAccess() }
    }
}
