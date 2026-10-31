import SwiftUI

struct WelcomeView: View {
    @Bindable var model: CorkController
    @State private var hideFiles = false
    @State private var login = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A wall for your Mac").font(.title2.weight(.semibold))
                    Text("Tape up photos, pin a poster, leave a note. Cork keeps your wall when you restart.").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Hide desktop files while Cork runs", isOn: $hideFiles)
                    Text("Your files stay in the Desktop folder and reappear when Cork quits.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Open Cork at login", isOn: $login).disabled(!model.installed)
                    if !model.installed { Text("Move Cork to Applications to enable Open at Login.").font(.caption).foregroundStyle(.secondary) }
                }
                HStack(spacing: 12) {
                    Button("Import from Pinterest…") { finish(importPinterest: true) }.buttonStyle(.borderedProminent)
                    Button("Add My Images…") {
                        model.run { try await model.completeWelcome(hideFiles: hideFiles, login: login, importPinterest: false); model.addImages() }
                    }
                }
                Button("Start with an empty wall") { finish(importPinterest: false) }.buttonStyle(.link)
                Text("Pinterest connection is optional. Its importer asks before reading browser cookies. Desktop screenshots and minimizing other apps request macOS permissions only when you use those features.").font(.caption).foregroundStyle(.secondary)
            }.padding(30).frame(maxWidth: 540, alignment: .leading).frame(maxWidth: .infinity)
        }.disabled(model.busy)
    }
    private func finish(importPinterest: Bool) {
        model.run { try await model.completeWelcome(hideFiles: hideFiles, login: login, importPinterest: importPinterest) }
    }
}
