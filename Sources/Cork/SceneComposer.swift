import SwiftUI
import CorkCore

struct SceneComposer: View {
    @Bindable var model: CorkController
    private var activePair: [ColourFamily]? { model.board.desktop.sceneOptions.matchColours ? model.board.desktop.sceneOptions.colourPair : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Choose two colours").font(.callout.weight(.medium))
                familyPicker(0)
                Text("+").foregroundStyle(.secondary).accessibilityHidden(true)
                familyPicker(1)
                Spacer(minLength: 4)
                Button("Roll Wall", systemImage: "dice") { model.run { try await model.rollWall() } }
                    .disabled(!model.canRollWall).help("Roll a new collage (⌘R). Undo with ⌘Z.")
            }
            HStack(spacing: 12) {
                if activePair != nil {
                    Picker("Colour strength", selection: Binding(get: { model.board.desktop.sceneOptions.selectedStrength }, set: { value in
                        model.run { try await model.setDesktop(colourStrength: value) }
                    })) {
                        ForEach(ColourSelectionStrength.allCases, id: \.self) { Text($0.name).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 280)
                    if model.classifyingColours { Text("Classifying colours…").font(.caption).foregroundStyle(.secondary) }
                    else { Text("\(model.matchingColourPhotos().count) matching photos").font(.caption).foregroundStyle(.secondary) }
                    Button("Automatic") { model.run { try await model.setDesktop(paletteID: "auto") } }
                        .help("Return to the saved mood and automatic palette")
                } else {
                    Text("Pick a pair, or roll from your saved mood.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                SavedBoardsButton(model: model)
                ScheduleButton(model: model)
            }
        }.padding(.horizontal, 16).padding(.vertical, 10).disabled(model.busy)
    }
    private func familyPicker(_ index: Int) -> some View {
        Picker(index == 0 ? "First colour" : "Second colour", selection: Binding<ColourFamily?>(get: { activePair?[index] }, set: { value in
            guard let value else { return }
            var pair = activePair ?? [.blue, .yellow]
            pair[index] = value
            if pair[0] == pair[1] { pair[1 - index] = value == .blue ? .yellow : .blue }
            model.run { try await model.setDesktop(colourPair: pair) }
        })) {
            Text(index == 0 ? "First colour" : "Second colour").tag(Optional<ColourFamily>.none)
            ForEach(ColourFamily.allCases.filter { $0 != activePair?[1 - index] }) { family in
                Text(family.name).tag(Optional(family))
            }
        }.labelsHidden().frame(minWidth: 105, maxWidth: 155)
            .accessibilityLabel(index == 0 ? "First colour" : "Second colour")
    }
}
