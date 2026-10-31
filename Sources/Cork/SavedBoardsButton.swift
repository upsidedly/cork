import SwiftUI
import CorkCore

struct SavedBoardsButton: View {
    @Bindable var model: CorkController
    @State private var open = false
    var body: some View {
        Button("Saved boards", systemImage: "star") { open = true }
            .labelStyle(.iconOnly).accessibilityLabel("Favourite boards")
            .help("Favourite this collage or reload a saved board")
            .popover(isPresented: $open, arrowEdge: .top) {
                FavouriteBoardsPopover(model: model) { open = false }
            }
    }
}

private struct FavouriteBoardsPopover: View {
    @Bindable var model: CorkController
    let close: () -> Void
    @State private var name: String
    init(model: CorkController, close: @escaping () -> Void) {
        self.model = model; self.close = close
        _name = State(initialValue: model.board.rotation?.themeName ?? "My corkboard")
    }
    var body: some View {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Favourite boards").font(.headline)
                    HStack {
                        TextField("Board name", text: $name).textFieldStyle(.roundedBorder)
                        Button("Save") { model.run { try await model.saveFavourite(name: name) } }
                            .disabled(model.busy || model.board.items.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if model.favourites.boards.isEmpty {
                        Text("Save a collage you love and bring it back later.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(model.favourites.boards.reversed()) { board in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(board.name).lineLimit(1)
                                            Text(board.createdAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Load") { model.run { try await model.loadFavourite(board.id); close() } }.disabled(model.busy)
                                    }.contextMenu { Button("Remove Favourite", role: .destructive) { model.run { try await model.removeFavourite(board.id) } } }
                                }
                            }
                        }.frame(maxHeight: 280)
                    }
                }.padding(16).frame(width: 350)
    }
}
