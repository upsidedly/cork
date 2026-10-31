import Foundation

public enum DisplayAdaptation {
    public static func fit(_ board: Board, displays: [DisplayInfo], collection: PhotoCollection,
                           wallpapers: WallpaperCollection) throws -> Board {
        var next = board
        for display in displays {
            try Task.checkCancellation()
            let old = board.layoutDisplays?.first { $0.id == display.id }
            guard old != display else { continue }
            func onDisplay(_ item: PrintItem) -> Bool { item.displayID == display.id || (item.displayID == 0 && display.id == displays.first?.id) }
            guard next.items.contains(where: { !$0.isHidden && onDisplay($0) }) else { continue }
            let shrinking = old.map { display.safeWidth < $0.safeWidth || display.safeHeight < $0.safeHeight } ?? false
            var fixedMoved = false
            for index in next.items.indices where onDisplay(next.items[index]) && !next.items[index].isHidden && (next.items[index].kind == .note || next.items[index].isKept) {
                var item = next.items[index]
                let scale = min(1, display.safeWidth / item.width, display.safeHeight / item.height)
                if scale < 1 { item.width = max(64, item.width * scale); item.height = max(64, item.height * scale) }
                item.x = min(max(item.x, display.safeX), max(display.safeX, display.safeX + display.safeWidth - item.width))
                item.y = min(max(item.y, display.safeY), max(display.safeY, display.safeY + display.safeHeight - item.height))
                fixedMoved = fixedMoved || item != next.items[index]; next.items[index] = item
            }
            let safe = try GreedyPacking.area(display)
            let images = next.items.filter { $0.kind == .image && !$0.isHidden && onDisplay($0) }
            let overflow = images.contains { !safe.contains(GreedyPacking.bounds($0)) }
            if shrinking || fixedMoved || overflow {
                let moving = images.filter { !$0.isKept }.map(\.id)
                if !moving.isEmpty { next = try GreedyPacking.arrange(next, ids: moving, display: display, gap: 16, preserveAngles: true) }
            }
            if !collection.eligibleThemes.isEmpty || (next.desktop.sceneOptions.colourPair != nil && next.desktop.sceneOptions.matchColours) {
                // Density depends on logical space, not notification count. Repeated
                // shrink/grow cycles therefore cannot keep accumulating tiny photos.
                let desired = min(60, max(8, Int((display.safeWidth * display.safeHeight / 78_000).rounded())))
                let remaining = max(0, min(20, desired - images.count, 500 - next.items.count))
                let theme = next.rotation?.themeID
                let eligible = collection.eligibleThemes.contains { $0.id == theme }
                next = try WallRotation.fillEmpty(next, collection: collection, display: display,
                    themeID: eligible ? theme : nil, seed: next.rotation?.seed ?? 42, wallpapers: wallpapers,
                    maximumNewPhotos: remaining, allowNoNewPhotos: true)
            }
        }
        next.layoutDisplays = displays
        try next.validate(); return next
    }
}
