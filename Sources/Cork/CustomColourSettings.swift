import SwiftUI
import CorkCore

struct CustomColourSettings: View {
    @Bindable var model: CorkController
    private var pair: [ColourFamily] { model.board.desktop.sceneOptions.colourPair ?? [.blue, .yellow] }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                familyPicker(0)
                Text("+").foregroundStyle(.secondary).accessibilityHidden(true)
                familyPicker(1)
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
                ForEach(pair) { family in
                    let strong = model.collection.photos.filter { ($0.colourProfile?.coverage(family) ?? 0) >= 0.18 }.count
                    let accents = model.collection.photos.filter { let share = $0.colourProfile?.coverage(family) ?? 0; return share >= 0.04 && share < 0.18 }.count
                    Text("\(family.name): \(strong) strong · \(accents) accents").font(.caption).foregroundStyle(.secondary)
                }
                let count = model.matchingColourPhotos().count
                Text("\(count) matching photos from your whole collection. Applies on the next roll.").font(.caption).foregroundStyle(.secondary)
                if !model.canRollWall { Text("Include accents or choose another pair to find more photos.").font(.caption).foregroundStyle(.secondary) }
                Button("Roll These Colours", systemImage: "dice") { model.run { try await model.rollWall() } }.disabled(!model.canRollWall)
            }
        }
    }
    private func familyPicker(_ index: Int) -> some View {
        Picker(index == 0 ? "First colour" : "Second colour", selection: Binding(get: { pair[index] }, set: { value in
            var next = pair; next[index] = value
            model.run { try await model.setDesktop(colourPair: next) }
        })) {
            ForEach(ColourFamily.allCases.filter { $0 != pair[1 - index] }) { family in
                HStack(spacing: 6) {
                    Circle().fill(Color(corkHex: family.hex)).frame(width: 10, height: 10).accessibilityHidden(true)
                    Text(family.name)
                }.tag(family)
            }
        }.labelsHidden().frame(maxWidth: .infinity)
            .accessibilityLabel(index == 0 ? "First colour" : "Second colour")
    }
}
