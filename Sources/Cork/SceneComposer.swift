import SwiftUI
import CorkCore

struct SceneComposer: View {
    @Bindable var model: CorkController
    private var activePair: [ColourChoice]? { model.board.desktop.sceneOptions.matchColours ? model.board.desktop.sceneOptions.colourPair : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Choose two colours").font(.callout.weight(.medium))
                ColourSlotPicker(model: model, index: 0)
                Text("+").foregroundStyle(.secondary).accessibilityHidden(true)
                ColourSlotPicker(model: model, index: 1)
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
                    else if activePair?.contains(.random) == true {
                        Text(model.resolvedColourPair.map { "Current: " + $0.map(\.name).joined(separator: " + ") } ?? "Random on the next roll")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else { Text("\(model.matchingColourPhotos().count) matching prints").font(.caption).foregroundStyle(.secondary) }
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
}
