import SwiftUI
import CorkCore

struct SceneSettings: View {
    @Bindable var model: CorkController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Match image colours", isOn: Binding(get: { model.board.desktop.sceneOptions.matchColours }, set: { enabled in
                model.run { try await model.setDesktop(matchColours: enabled) }
            }))
            Picker("Colour palette", selection: Binding(get: { model.board.desktop.sceneOptions.colourPair != nil ? "custom" : model.board.desktop.sceneOptions.paletteID ?? "auto" }, set: { palette in
                model.run {
                    if palette == "custom" { try await model.setDesktop(colourPair: [.blue, .yellow]) }
                    else { try await model.setDesktop(paletteID: palette) }
                }
            })) {
                Text("From mood or kept images").tag("auto")
                Text("Choose two colours").tag("custom")
                ForEach(ScenePalettes.all) { palette in Text(palette.name).tag(palette.id) }
            }
            if model.board.desktop.sceneOptions.colourPair != nil {
                CustomColourSettings(model: model).disabled(model.busy || !model.board.desktop.sceneOptions.matchColours)
            }
            if let scheme = model.board.rotation?.scheme {
                HStack(spacing: 6) {
                    Text(scheme.name).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    ForEach(scheme.colours, id: \.self) { hex in
                        RoundedRectangle(cornerRadius: 3).fill(Color(corkHex: hex)).frame(width: 22, height: 18).accessibilityLabel(hex)
                    }
                }.accessibilityElement(children: .combine)
            }
            Toggle("Match wallpaper to palette", isOn: Binding(get: { model.board.desktop.sceneOptions.matchWallpaper }, set: { enabled in
                model.run { try await model.setDesktop(matchWallpaper: enabled) }
            }))
            let ready = model.wallpapers.wallpapers.filter { image in model.displays.contains(where: image.supports) }.count
            if ready > 0 {
                Text("\(ready) wallpapers fit this display at native resolution.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Import large wallpapers to coordinate the background. Smaller images are excluded from automatic selection.").font(.caption).foregroundStyle(.secondary)
            }
            if model.board.desktop.sceneOptions.matchWallpaper && model.board.rotation?.wallpaperMatched == false {
                Text("No matching wallpaper fits this display. The current background was kept.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Import Wallpaper Collection…") { model.chooseWallpapers() }.disabled(model.busy)
            Text("Fill Empty keeps your existing prints and adds images around them. Keep in place protects chosen photos during randomization too.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
extension Color {
    init(corkHex: String) {
        let value = UInt32(corkHex.dropFirst(), radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}
