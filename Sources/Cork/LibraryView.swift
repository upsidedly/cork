import SwiftUI
import AppKit
import CorkCore

struct CorkLibraryView: View {
    @Bindable var model: CorkController
    @State private var settings = false
    var body: some View {
        VStack(spacing: 0) {
            if let message = model.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss", systemImage: "xmark") { model.errorMessage = nil }.labelStyle(.iconOnly).buttonStyle(.plain)
                }.font(.callout).padding(12).background(.quaternary)
            }
            if !model.ready {
                ContentUnavailableView("Board unavailable", systemImage: "rectangle.on.rectangle.slash", description: Text("Cork could not open its saved board. Check the message above; your local files have been preserved."))
            } else if model.board.items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "pin.square").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(.secondary)
                    Text("Add something to your wall").font(.title3.weight(.medium))
                    Text("Images and notes, right on your wallpaper.").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Add Images…", systemImage: "photo.badge.plus") { model.addImages() }
                        Button("New Note", systemImage: "square.and.pencil") { model.addNote() }
                    }.padding(.top, 4)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { available in
                HSplitView {
                    List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
                        ForEach(model.board.items) { item in
                            HStack(spacing: 10) {
                                PrintThumbnail(item: item, image: model.desktop.image(for: item))
                                    .frame(width: 40, height: 48).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(model.displayTitle(for: item))
                                        .lineLimit(1)
                                    Text((item.kind == .widget ? "Widget" : item.kind == .note ? "\(item.style.title) note" : item.style.title) + (item.isHidden ? " · Hidden" : ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button {
                                    model.updateFromUI(["id": .string(item.id.uuidString), "hidden": .bool(!item.isHidden)])
                                } label: { Image(systemName: item.isHidden ? "eye.slash" : "eye") }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(item.isHidden ? "Show \(model.displayTitle(for: item))" : "Hide \(model.displayTitle(for: item))")
                                    .help(item.isHidden ? "Show on desktop" : "Hide and reflow the layout")
                            }.padding(.vertical, 3)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(model.displayTitle(for: item))
                                .accessibilityValue(item.isHidden ? "Hidden" : "Visible")
                                .accessibilityAction(named: Text(item.isHidden ? "Show on desktop" : "Hide from desktop")) {
                                    model.updateFromUI(["id": .string(item.id.uuidString), "hidden": .bool(!item.isHidden)])
                                }.tag(item.id)
                        }
                    }.listStyle(.sidebar).frame(minWidth: 210, idealWidth: 230, maxWidth: 260)
                        .frame(height: available.size.height)
                    if let item = model.selectedItem {
                        ItemInspector(model: model, item: item).id(item.id).frame(minWidth: 350, maxWidth: .infinity)
                            .frame(height: available.size.height)
                    } else {
                        ContentUnavailableView("Select an item", systemImage: "cursorarrow", description: Text("Choose a print or note to edit it."))
                            .frame(minWidth: 350, maxWidth: .infinity).frame(height: available.size.height)
                    }
                }.frame(width: available.size.width, height: available.size.height)
                }
            }
            Divider()
            HStack(spacing: 12) {
                Text(model.board.items.count == 1 ? "1 item" : "\(model.board.items.count) items").foregroundStyle(.secondary)
                if model.busy { ProgressView().controlSize(.small); Text("Saving…").foregroundStyle(.secondary) }
                else if model.editing { Text("Drag items on your desktop · Esc to finish").foregroundStyle(.secondary) }
                else { Text("Desktop locked").foregroundStyle(.secondary) }
                Spacer()
                Button("Settings", systemImage: "gearshape") { settings = true }.labelStyle(.iconOnly).buttonStyle(.plain).help("Settings and MCP setup")
            }.font(.caption).padding(.horizontal, 16).padding(.vertical, 11)
        }
        .frame(minWidth: 640, minHeight: 440)
        .toolbar {
            ToolbarItemGroup {
                Button("Add Images", systemImage: "photo.badge.plus") { model.addImages() }.help("Add Images (⌘O)")
                Button("New Note", systemImage: "square.and.pencil") { model.addNote() }.help("New Note (⌘N)")
                Button("Roll Wall", systemImage: "dice") { model.run { try await model.rollWall() } }
                    .help(model.collection.photos.isEmpty ? "Import a rotation collection in Settings" : "Roll a new wall (⌘R) · Undo with ⌘Z")
                    .disabled(!model.canRollWall)
                Button("Fill Empty", systemImage: "rectangle.badge.plus") { model.run { try await model.rollWall(fillEmpty: true) } }
                    .help("Keep existing prints and fill the gaps with matching images").disabled(!model.canRollWall)
                Menu {
                    ForEach(LayoutKind.allCases, id: \.rawValue) { layout in
                        Button(layout.title) { model.run { try await model.arrange(layout, gap: layout == .greedy ? 16 : 28) } }
                    }
                } label: { Label("Arrange", systemImage: "square.grid.2x2") }.disabled(model.board.items.isEmpty || model.busy)
                Button(model.editing ? "Done" : "Edit Desktop", systemImage: model.editing ? "checkmark" : "cursorarrow.and.square.on.square.dashed") {
                    model.setEditing(!model.editing)
                }.disabled(model.board.items.isEmpty)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let urls = providers.compactMap { $0.registeredTypeIdentifiers.contains("public.file-url") ? $0 : nil }
            guard !urls.isEmpty else { return false }
            model.run {
                var paths: [URL] = []
                for provider in urls {
                    let data: Data? = await withCheckedContinuation { continuation in
                        _ = provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in continuation.resume(returning: data) }
                    }
                    if let data, let url = URL(dataRepresentation: data, relativeTo: nil) { paths.append(url) }
                }
                if !paths.isEmpty { try await model.importImages(paths) }
            }
            return true
        }
        .sheet(isPresented: $settings) { CorkSettingsView(model: model).frame(width: 470, height: 690) }
        .onExitCommand { model.setEditing(false) }
    }
}

struct ItemInspector: View {
    @Bindable var model: CorkController
    let item: PrintItem
    @State private var titleDraft: String
    @State private var textDraft: String
    @State private var widthDraft: Double
    @State private var rotationDraft: Double
    @State private var geometry = false
    @FocusState private var titleFocused: Bool

    init(model: CorkController, item: PrintItem) {
        self.model = model; self.item = item
        _titleDraft = State(initialValue: item.title); _textDraft = State(initialValue: item.text)
        _widthDraft = State(initialValue: item.width); _rotationDraft = State(initialValue: item.rotation)
    }
    func update(_ values: [String: JSONValue]) {
        model.updateFromUI(values.merging(["id": .string(item.id.uuidString)]) { _, new in new })
    }
    func positionRange(horizontal: Bool) -> ClosedRange<Double> {
        let display = model.displays.first { $0.id == item.displayID } ?? model.displays.first
        let start = horizontal ? display?.safeX ?? 0 : display?.safeY ?? 0
        let length = horizontal ? display?.safeWidth ?? 1440 : display?.safeHeight ?? 900
        let size = horizontal ? item.width : item.height, value = horizontal ? item.x : item.y
        return min(start, value)...max(start + 1, start + length - size, value)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if item.kind == .widget {
                    WidgetInspectorPreview(model: model, item: item).frame(height: 240).accessibilityLabel("Interactive widget preview")
                } else {
                PrintThumbnail(item: item, image: model.desktop.image(for: item))
                    .frame(maxWidth: .infinity).frame(height: item.kind == .note ? 145 : 180)
                    .accessibilityLabel(item.kind == .note ? "Note preview" : "Print preview")
                }
                if item.kind != .widget {
                Picker("Style", selection: Binding(get: { item.style }, set: { update(["style": .string($0.rawValue)]) })) {
                    ForEach(item.kind == .note ? PrintStyle.noteStyles : PrintStyle.imageStyles, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }.pickerStyle(.segmented)
                }
                if item.kind == .image {
                    Toggle("Keep in place", isOn: Binding(get: { item.isKept }, set: { update(["keep_in_place": .bool($0)]) }))
                        .help("Randomize and automatic layouts leave this print in place. You can still move it manually.")
                } else if item.kind == .note {
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle("Include in layout", isOn: Binding(get: { !item.isOverlayNote }, set: { update(["include_in_layout": .bool($0)]) }))
                        Text("Untick to keep this note on top and let pictures fill behind it.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Match collage colours", isOn: Binding(get: { item.matchSceneColours == true }, set: { update(["match_scene_colours": .bool($0)]) }))
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(item.kind == .image ? "Title / caption" : "Title").font(.caption).foregroundStyle(.secondary)
                    TextField("Optional title", text: $titleDraft)
                        .textFieldStyle(.roundedBorder).focused($titleFocused)
                        .onSubmit { update(["title": .string(titleDraft)]) }
                        .onChange(of: titleFocused) { _, focused in
                            if !focused, titleDraft != item.title { update(["title": .string(titleDraft)]) }
                        }
                }
                if item.style == .polaroid {
                    Text("Leave the caption blank for an unmarked print. Captions use marker lettering.").font(.caption).foregroundStyle(.secondary)
                }
                if item.kind == .note {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $textDraft).font(.body).frame(minHeight: 110)
                            .padding(5).background(.background).clipShape(RoundedRectangle(cornerRadius: 5))
                            .accessibilityLabel("Note text")
                        HStack {
                            Picker("Paper", selection: Binding(get: { item.noteColor }, set: { update(["note_color": .string($0.rawValue)]) })) {
                                ForEach(NoteColor.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                            }.disabled(item.matchSceneColours == true)
                            Spacer()
                            Button("Save Note") { update(["text": .string(textDraft), "title": .string(titleDraft)]) }
                                .disabled(textDraft == item.text && titleDraft == item.title)
                        }
                    }
                }
                VStack(spacing: 12) {
                    HStack {
                        Text("Size").foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                        Slider(value: $widthDraft, in: 64...min(1400, max(600, item.width)), onEditingChanged: { active in
                            if !active { update(["width": .number(widthDraft)]) }
                        }).accessibilityLabel("Print width")
                        Text("\(Int(widthDraft)) pt").monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                    if item.kind != .widget { HStack {
                        Text("Angle").foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                        Slider(value: $rotationDraft, in: -180...180, step: 1, onEditingChanged: { active in
                            if !active { update(["rotation": .number(rotationDraft)]) }
                        }).accessibilityLabel("Clockwise rotation")
                        Button("\(Int(rotationDraft))°") { update(["rotation": .number(0)]) }
                            .buttonStyle(.plain).monospacedDigit().frame(width: 52, alignment: .trailing).help("Reset rotation")
                    } }
                }.font(.callout)
                DisclosureGroup("Position & dimensions", isExpanded: $geometry) {
                    VStack(spacing: 10) {
                        GeometryField(label: "X", value: item.x, range: positionRange(horizontal: true)) { update(["x": .number($0)]) }
                        GeometryField(label: "Y", value: item.y, range: positionRange(horizontal: false)) { update(["y": .number($0)]) }
                        HStack {
                            GeometryField(label: "Width", value: item.width) { update(["width": .number($0)]) }
                            GeometryField(label: "Height", value: item.height) { update(["height": .number($0)]) }
                        }
                        Picker("Display", selection: Binding(get: { item.displayID }, set: { update(["display_id": .number(Double($0))]) })) {
                            ForEach(model.displays) { Text($0.name).tag($0.id) }
                        }
                        HStack {
                            Button("Send to Back") { update(["z_index": .number(Double((model.board.items.map(\.zIndex).min() ?? 0) - 1))]) }
                            Button("Bring to Front") { update(["z_index": .number(Double((model.board.items.map(\.zIndex).max() ?? 0) + 1))]) }
                            Spacer()
                        }
                    }.padding(.top, 10)
                }.font(.callout)
                if let photo = model.collectionPhoto(for: item) {
                    DisclosureGroup("Photo details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(photo.title).font(.callout)
                            Text(photo.description).font(.caption).foregroundStyle(.secondary)
                            Text("From \(photo.sourceBoard)").font(.caption).foregroundStyle(.secondary)
                            Text(photo.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            Text("Palette: \(photo.palette.joined(separator: " "))").font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(model.collection.themes.filter { photo.themeIDs.contains($0.id) }.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 6).textSelection(.enabled)
                    }.font(.callout)
                }
                HStack {
                    if let source = item.sourceURL, let url = URL(string: source), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        Link("Source ↗", destination: url).font(.callout)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { model.removeFromUI(item.id) }
                }
            }.padding(22)
        }
        .disabled(model.busy)
        .onChange(of: item.width) { _, width in widthDraft = width }
        .onChange(of: item.rotation) { _, rotation in rotationDraft = rotation }
        .onChange(of: item.title) { _, title in titleDraft = title }
        .onChange(of: item.text) { _, text in textDraft = text }
    }
}

private struct GeometryField: View {
    let label: String
    let value: Double
    var range: ClosedRange<Double>? = nil
    let commit: (Double) -> Void
    @State private var draft = ""
    @State private var position = 0.0
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            TextField(label, text: $draft).textFieldStyle(.roundedBorder).accessibilityLabel(label)
                .onSubmit { if let number = Double(draft), number.isFinite { commit(number) } else { draft = String(Int(value)) } }
                .frame(width: range == nil ? nil : 76)
            if let range {
                Slider(value: Binding(get: { min(range.upperBound, max(range.lowerBound, position)) }, set: {
                    position = $0; draft = String(Int($0.rounded()))
                }), in: range, step: 1, onEditingChanged: { active in if !active { commit(position) } })
                    .accessibilityLabel("\(label) position")
            }
        }.onAppear { draft = String(Int(value)); position = value }
            .onChange(of: value) { _, value in draft = String(Int(value)); position = value }
    }
}

struct CorkSettingsView: View {
    @Bindable var model: CorkController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.title3.weight(.semibold))
            if let error = model.errorMessage { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            Toggle("Open Cork at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLogin($0) }))
                .disabled(!model.installed)
            if !model.installed {
                Text("Install Cork in Applications to enable Open at Login.").font(.caption).foregroundStyle(.secondary)
            } else if model.loginStatus == "requires_approval" {
                Button("Allow Cork in Login Items…") { model.openLoginSettings() }
            }
            Toggle("Hide desktop files while Cork runs", isOn: Binding(get: { model.board.desktop.hideDesktopFiles }, set: { enabled in
                model.run { try await model.setDesktop(hideFiles: enabled) }
            }))
            Text("Files stay in your Desktop folder. Icons return when Cork quits.").font(.caption).foregroundStyle(.secondary)
            Toggle("Hide Apple widgets while Cork runs", isOn: Binding(get: { model.board.desktop.widgetsHidden }, set: { enabled in
                model.run { try await model.setDesktop(hideWidgets: enabled) }
            }))
            Text("New layouts can use the widget area. Your widgets return when Cork quits.").font(.caption).foregroundStyle(.secondary)
            Button("Open Desktop Folder") {
                if let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(url) }
            }.font(.callout)
            WidgetSettings(model: model)
            Picker("New image style", selection: Binding(get: { model.defaultStyle }, set: { style in
                model.run { try await model.setDesktop(defaultStyle: style) }
            })) {
                ForEach(PrintStyle.imageStyles, id: \.self) { Text($0.title).tag($0) }
            }
            Divider().padding(.vertical, 8)
            Text("Rotation").font(.headline)
            if model.collection.photos.isEmpty {
                Text("Add a photo collection, then roll the dice for a new wall.").foregroundStyle(.secondary)
            } else {
                Text("\(model.collection.photos.count) photos · \(model.collection.eligibleThemes.count) moods").foregroundStyle(.secondary)
                Picker("Next wall", selection: Binding(get: { model.board.desktop.rotationTheme ?? "auto" }, set: { id in
                    model.run { try await model.setRotationTheme(id) }
                })) {
                    Text("Surprise me").tag("auto")
                    ForEach(model.collection.eligibleThemes) { theme in Text(theme.name).tag(theme.id) }
                }
                if let name = model.board.rotation?.themeName { Text("On the wall: \(name)").font(.caption).foregroundStyle(.secondary) }
                Text("One visual mood across boards. Notes stay put. Undo restores the previous wall.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Import Photo Collection…") { model.chooseCollection() }.disabled(model.busy)
            SceneSettings(model: model)
            Divider()
            DesktopControlsSettings(model: model)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Wallpaper").font(.headline)
                Picker("Wallpaper", selection: Binding(get: { model.board.desktop.wallpaper.kind }, set: { kind in
                    if kind == .system { model.run { try await model.setDesktop(kind: .system) } }
                    else { model.chooseWallpaper(kind) }
                })) {
                    Text("System").tag(WallpaperKind.system)
                    Text("Image").tag(WallpaperKind.image)
                    Text("Video").tag(WallpaperKind.video)
                }.pickerStyle(.segmented).labelsHidden()
                if let name = model.board.desktop.wallpaper.sourceName {
                    Text(name).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack {
                    Button("Choose Image…") { model.chooseWallpaper(.image) }
                    Button("Choose Video…") { model.chooseWallpaper(.video) }
                }
                if model.board.desktop.wallpaper.kind == .video {
                    Toggle("Pause video", isOn: Binding(get: { model.board.desktop.wallpaper.paused }, set: { paused in
                        model.run { try await model.setDesktop(paused: paused) }
                    }))
                    Text("Loops without sound. Pauses during display sleep, screen lock, and Reduce Motion.").font(.caption).foregroundStyle(.secondary)
                }
                if model.environment.loading { ProgressView("Loading wallpaper…").controlSize(.small) }
                if let problem = model.environment.problem {
                    Text(problem + " Choose another file or use System wallpaper.").font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Desktop screenshots").font(.headline)
                Text("Screen Recording is only needed for screenshots requested by you or an agent. Adding and arranging items works without it.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(model.screenAccess ? "Screen Recording Allowed" : "Allow Screen Recording") { model.requestScreenAccess() }.disabled(model.screenAccess)
                    Button("System Settings…") { model.openScreenSettings() }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect an agent").font(.headline)
                Text("Cork includes a local MCP for images, notes, layouts, and desktop screenshots. Pair it with the Pinterest plugin to import selected pins.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Copy MCP Configuration") {
                    let path = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/cork-mcp").path
                    let config: JSONValue = .object(["mcpServers": .object(["cork": .object(["command": .string(path)])])])
                    if let data = try? config.data(pretty: true) {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
                    }
                }
            }
            }.padding(24)
            }.disabled(model.busy)
            Divider()
            HStack {
                Button("Show Local Files") { NSWorkspace.shared.open(model.repository.root) }
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(16)
        }.onAppear { model.screenAccess = CGPreflightScreenCaptureAccess(); model.refreshLoginState() }
    }
}

struct PrintThumbnail: NSViewRepresentable {
    let item: PrintItem
    let image: NSImage?
    func makeNSView(context: Context) -> ThumbnailView { ThumbnailView() }
    func updateNSView(_ view: ThumbnailView, context: Context) { view.item = item; view.image = image; view.needsDisplay = true }
}

final class ThumbnailView: NSView {
    var item: PrintItem?
    var image: NSImage?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard var item else { return }
        let angle = item.rotation * .pi / 180
        let width = abs(cos(angle)) * item.width + abs(sin(angle)) * item.height + 36
        let height = abs(sin(angle)) * item.width + abs(cos(angle)) * item.height + 42
        let scale = min(bounds.width / width, bounds.height / height)
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform(); transform.translateX(by: bounds.midX, yBy: bounds.midY)
        transform.scale(by: scale); transform.concat()
        item.x = 0; item.y = 0
        PrintRenderer.draw(item: item, image: image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
    }
}
