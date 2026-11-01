import SwiftUI
import CorkImportCore

struct ImporterView: View {
    @Bindable var model: ImporterModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Cork Importer", systemImage: "square.and.arrow.down").font(.headline)
                Spacer()
                Button("Daily Sync…", systemImage: "arrow.clockwise") {
                    model.showsDailySync = true
                }.disabled(model.busy)
                if let account = model.account {
                    Text(account.name).font(.callout).foregroundStyle(.secondary)
                    Button("Disconnect") { model.disconnect() }.disabled(model.busy).accessibilityLabel("Disconnect Pinterest")
                }
            }.padding(18)
            Divider()
            if let error = model.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { model.error = nil }
                }.font(.callout).padding(12).background(.quaternary.opacity(0.35))
            }
            switch model.step {
            case .connect: connect
            case .boards: boards
            case .review: review
            case .complete: complete
            }
            Divider()
            HStack(spacing: 10) {
                if model.busy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.busy && !model.changingDailySchedule { Button("Stop") { model.stop() } }
            }.padding(14).frame(minHeight: 42)
        }.frame(minWidth: 720, minHeight: 500)
            .sheet(isPresented: $model.showsDailySync) { DailySyncView(model: model) }
    }
    private var connect: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bring your boards to Cork").font(.title2.weight(.semibold))
                    Text("Choose boards, review the images, then keep the ones you want. Cork measures their colours and mixes images across boards.").foregroundStyle(.secondary)
                }
                if model.resumable != nil {
                    HStack {
                        Text("You have an unfinished image review.")
                        Spacer(); Button("Resume Review") { model.resume() }
                        Button("Discard", role: .destructive) { model.discardReview() }
                    }
                    Divider()
                }
                HStack {
                    Picker("Browser profile", selection: $model.profileID) {
                        ForEach(model.profiles) { Text("\($0.browser) — \($0.name)").tag($0.id) }
                    }.disabled(model.busy || model.profiles.isEmpty)
                    Menu("Choose Profile Folder…") {
                        ForEach(["Chrome", "Chromium", "Brave", "Edge", "Firefox"], id: \.self) { browser in
                            Button(browser) { model.chooseProfile(browser: browser) }
                        }
                    }.disabled(model.busy)
                }
                if model.profiles.isEmpty {
                    Text("No readable profiles were found. macOS may protect browser data. Choose a profile folder above, or sign in to a supported browser first.").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Before you connect").font(.headline)
                    Text("Cork Importer reads only Pinterest cookies from this profile, in read-only mode. For Chrome-based browsers, macOS may ask for the browser’s Safe Storage key to decrypt those cookies.")
                    Text("The key can decrypt browser cookies; this app uses it only for Pinterest. It does not read passwords, history, or other sites’ cookies. Your session stays in memory, is sent only to Pinterest, and is cleared when you disconnect or quit.")
                    Text("Images and review metadata are saved locally. Nothing is uploaded to Cork or an agent service. Only import images you have permission to use.").foregroundStyle(.secondary)
                }.font(.callout)
                Toggle("Allow this Pinterest-cookie access for this connection", isOn: $model.consent).disabled(model.busy)
                HStack {
                    Button("Connect Pinterest") { model.connect() }.buttonStyle(.borderedProminent)
                        .disabled(!model.consent || model.profileID.isEmpty || model.busy)
                    Button("Open Pinterest") { model.openPinterest() }.disabled(model.busy)
                    Button("Refresh Profiles") { model.profiles = BrowserProfile.available(); model.profileID = model.profiles.first?.id ?? "" }.disabled(model.busy)
                }
                Text("Sign in to Pinterest in Chrome, Chromium, Brave, Edge or Firefox first. Safari is not supported in this release. Cork Importer is independent of Pinterest; its website changes may require an importer update.").font(.caption).foregroundStyle(.secondary)
            }.padding(30).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    private var boards: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose your boards").font(.title2.weight(.semibold))
                    Text("20 images per board by default. Videos are skipped. All follows every available page.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review Images") { model.fetch() }.buttonStyle(.borderedProminent)
                    .accessibilityLabel("Review selected boards")
                    .disabled(model.selected.isEmpty || model.busy || model.quotaTotal > 20_000 || model.resumable != nil)
            }
            if model.resumable != nil {
                HStack {
                    Text("Resume or discard your unfinished review first.").font(.callout)
                    Spacer(); Button("Resume Review") { model.resume() }
                    Button("Discard", role: .destructive) { model.discardReview() }
                }.disabled(model.busy)
            }
            List(model.boards) { board in
                HStack(spacing: 16) {
                    Toggle(isOn: Binding(get: { model.selected.contains(board.id) }, set: { value in
                        if value { model.selected.insert(board.id) } else { model.selected.remove(board.id) }
                    })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(board.name)
                            Text("\(board.pinCount) pins").font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityLabel("Import \(board.name)").accessibilityValue("\(board.pinCount) pins")
                    Spacer()
                    Picker("Images from \(board.name)", selection: Binding(get: { model.quotas[board.id] ?? 20 }, set: { model.quotas[board.id] = $0 })) {
                        ForEach([20, 50, 100, 150, 200], id: \.self) { Text("\($0)").tag($0) }
                        Text("All").tag(0)
                    }.labelsHidden().accessibilityLabel("Image count for \(board.name)").frame(width: 100).disabled(!model.selected.contains(board.id))
                }.padding(.vertical, 6).accessibilityElement(children: .contain).accessibilityLabel(board.name)
            }.listStyle(.inset).disabled(model.busy)
            Text(model.quotaTotal > 20_000 ? "Select at most 20,000 images per review. Reduce a quota or choose fewer boards." : "\(model.selected.count) boards · up to \(model.quotaTotal) images. Full-size keepers may use about \(max(1, model.quotaTotal * 2)) MB in Cork; previews stay in memory.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Keep Selected Boards Fresh Daily…") { model.showsDailySync = true }
                .disabled(model.selected.isEmpty || model.busy)
        }.padding(22)
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Keep what feels right").font(.title2.weight(.semibold))
                    Text("\(model.review.keepers.count) keepers · \(model.review.removed.count) removed · \(Set(model.review.keepers.map(\.boardID)).count) boards").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add to Cork") { model.addToCork() }.buttonStyle(.borderedProminent).disabled(model.busy || model.review.keepers.isEmpty)
            }
            if !model.review.warnings.isEmpty {
                DisclosureGroup("Import details (\(model.review.warnings.count))") {
                    VStack(alignment: .leading, spacing: 4) { ForEach(model.review.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Picker("Board", selection: $model.filterBoard) {
                    Text("All boards").tag("")
                    ForEach(reviewBoards) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 260)
                Toggle("Show removed", isOn: $model.showRemoved)
                Spacer()
                Button("Keep All") { model.setAll(keep: true) }
                Button("Remove All") { model.setAll(keep: false) }
            }.font(.callout).disabled(model.busy)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)], spacing: 16) {
                    ForEach(model.visibleImages) { pin in
                        ImportImageCell(pin: pin, removed: model.review.removed.contains(pin.id), cache: model.previews) { model.toggle(pin.id) }.disabled(model.busy)
                    }
                }.padding(.vertical, 4)
            }
            HStack {
                Toggle("Create a collage after import", isOn: $model.createCollage).disabled(model.busy)
                Spacer()
                Button("Discard Review", role: .destructive) { model.discardReview() }.disabled(model.busy)
            }.font(.callout)
        }.padding(22)
    }
    private var reviewBoards: [PinterestBoard] {
        Dictionary(grouping: model.review.images, by: \.boardID).compactMap { id, pins in
            pins.first.map { PinterestBoard(id: id, name: $0.boardName, path: "", pinCount: pins.count) }
        }.sorted { $0.name < $1.name }
    }
    private var complete: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Ready for your wall").font(.title2.weight(.semibold))
            Text("\(model.importedCount) images added with measured colours, moods and original pin links.").foregroundStyle(.secondary)
            if let note = model.completionNote { Text(note).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Button("Open Cork") { model.perform { try await model.openCork(activate: true) } }.buttonStyle(.borderedProminent)
                Button("Import More") { model.startAnother() }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }
}

private struct ImportImageCell: View {
    let pin: PinterestImage
    let removed: Bool
    let cache: ImportPreviewCache
    let toggle: () -> Void
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Rectangle().fill(.quaternary.opacity(0.4))
                if let image { Image(nsImage: image).resizable().scaledToFit().padding(4).opacity(removed ? 0.35 : 1) }
                else if failed { Label("Preview unavailable", systemImage: "photo").font(.caption).foregroundStyle(.secondary) }
                else { ProgressView().controlSize(.small) }
            }.frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pin.title.isEmpty ? "Pinterest image" : pin.title).lineLimit(1).font(.callout)
                    Text(pin.boardName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button(removed ? "Restore" : "Remove", systemImage: removed ? "arrow.uturn.backward" : "xmark") { toggle() }
                    .labelStyle(.iconOnly).accessibilityLabel("\(removed ? "Restore" : "Remove") \(pin.title.isEmpty ? "image" : pin.title)")
            }
        }.task(id: pin.previewURL) {
            do {
                let data = try await cache.image(pin.previewURL); try Task.checkCancellation()
                image = NSImage(data: data); failed = image == nil
            } catch is CancellationError {} catch { failed = true }
        }.onDisappear { image = nil }
    }
}
