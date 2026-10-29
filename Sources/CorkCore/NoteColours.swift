import Foundation

public enum NoteColours {
    public static func refresh(_ board: Board, displayID: UInt32? = nil) -> Board {
        var next = board
        for index in next.items.indices {
            let note = next.items[index]
            guard note.kind == .note, note.matchSceneColours == true,
                  displayID == nil || note.displayID == displayID || note.displayID == 0 else { continue }
            let palettes = next.items.filter {
                $0.kind == .image && !$0.isHidden && ($0.displayID == note.displayID || $0.displayID == 0 || note.displayID == 0)
            }.compactMap(\.colours)
            let candidates = palettes.flatMap { Array($0.prefix(3)) } + (next.rotation?.scheme?.colours ?? [])
            let base = candidates.first { ColourMatch.wallpaperHueAffinity([$0], imagePalettes: palettes) > 0.7 }
                ?? "#8C918C"
            let rgb = UInt32(base.dropFirst(), radix: 16) ?? 0x8C918C
            func paper(_ value: UInt32) -> Int { Int((Double(value) * 0.28 + 255 * 0.72).rounded()) }
            next.items[index].matchedNoteColour = String(format: "#%02X%02X%02X", paper((rgb >> 16) & 255), paper((rgb >> 8) & 255), paper(rgb & 255))
        }
        return next
    }
}
