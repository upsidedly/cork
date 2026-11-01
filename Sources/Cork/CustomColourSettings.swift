import SwiftUI
import CorkCore

struct CustomColourSettings: View {
    @Bindable var model: CorkController
    private var choices: [ColourChoice] { model.board.desktop.sceneOptions.colourPair ?? [.random, .random] }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ColourSlotPicker(model: model, index: 0)
                Text("+").foregroundStyle(.secondary).accessibilityHidden(true)
                ColourSlotPicker(model: model, index: 1)
            }
            Picker("Colour strength", selection: Binding(get: { model.board.desktop.sceneOptions.selectedStrength }, set: { value in
                model.run { try await model.setDesktop(colourStrength: value) }
            })) {
                ForEach(ColourSelectionStrength.allCases, id: \.self) { value in Text(value.name).tag(value) }
            }.pickerStyle(.segmented)
                .help("Strong colours cover at least 18% of an image. Include accents also accepts colours covering at least 4%.")
            if model.classifyingColours {
                HStack { ProgressView().controlSize(.small); Text("Classifying image colours…") }.font(.caption)
            } else if let problem = model.colourClassificationError {
                Text(problem).font(.caption).foregroundStyle(.secondary)
                Button("Retry Colour Analysis") { model.classifyColours() }
            } else {
                ForEach(choices.compactMap(\.family)) { family in
                    let strong = model.collection.photos.filter { ($0.colourProfile?.coverage(family) ?? 0) >= 0.18 }.count
                    let accents = model.collection.photos.filter { let share = $0.colourProfile?.coverage(family) ?? 0; return share >= 0.04 && share < 0.18 }.count
                    Text("\(family.name): \(strong) strong · \(accents) accents").font(.caption).foregroundStyle(.secondary)
                }
                if choices.contains(.random) {
                    Text("Random changes on each roll; fixed colours stay in their selected slots. The dominant colour guides the wallpaper.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("\(model.matchingColourPhotos().count) matching prints from your whole collection. Applies on the next roll.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !model.canRollWall { Text("Include accents or choose another pair to find more photos.").font(.caption).foregroundStyle(.secondary) }
                Button("Roll These Colours", systemImage: "dice") { model.run { try await model.rollWall() } }.disabled(!model.canRollWall)
            }
        }
    }
}

struct ColourSlotPicker: View {
    @Bindable var model: CorkController
    let index: Int
    private var label: String { index == 0 ? "Dominant" : "Secondary" }
    private var choices: [ColourChoice]? { model.board.desktop.sceneOptions.matchColours ? model.board.desktop.sceneOptions.colourPair : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            Picker(label + " colour", selection: Binding<ColourChoice?>(get: { choices?[index] }, set: { choice in
                if let choice { model.chooseColour(choice, at: index) }
            })) {
                Text("Choose colour").tag(Optional<ColourChoice>.none)
                ForEach(ColourChoice.allCases.filter { $0.family == nil || $0.family != choices?[1 - index].family }) { choice in
                    Text(choice.name).tag(Optional(choice))
                }
            }.labelsHidden().accessibilityLabel(label + " colour")
                .help(index == 0 ? "Leads the collage and wallpaper. Random chooses a new dominant colour on each roll." : "Adds the secondary colour. Random changes this slot on each roll.")
        }.frame(minWidth: 105, maxWidth: 155)
    }
}
