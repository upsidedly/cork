import Foundation

public enum ItemKind: String, Codable, Sendable { case image, video, note, widget }

public enum NoteColor: String, Codable, CaseIterable, Sendable { case yellow, cream, sage, rose, blue, gray }

public enum PrintStyle: String, Codable, CaseIterable, Sendable {
    case tape, pushpin, polaroid, frame, flat, sticky
    public static var imageStyles: [PrintStyle] { [.tape, .pushpin, .polaroid, .frame] }
    public static var noteStyles: [PrintStyle] { [.flat, .sticky] }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self { case .tape: "bandage"; case .pushpin: "pin"; case .polaroid: "photo"; case .frame: "photo.artframe"; case .flat: "text.alignleft"; case .sticky: "note.text" }
    }
    public func printSize(imageWidth: Double, imageHeight: Double, width: Double) -> (Double, Double) {
        if Self.noteStyles.contains(self) { return (width, width * 0.85) }
        let ratio = imageHeight / max(imageWidth, 1)
        let inset: Double = self == .frame ? 0.12 : (self == .polaroid ? 0.055 : 0.018)
        let bottom: Double = self == .polaroid ? 0.20 : inset
        return (width, max(64, width * ((1 - inset * 2) * ratio + inset + bottom)))
    }
}

public struct PrintItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    public var assetFile: String
    public var title: String
    public var style: PrintStyle
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var displayID: UInt32
    public var zIndex: Int
    public var sourceURL: String?
    public var imageWidth: Double
    public var imageHeight: Double
    public var text: String
    public var noteColor: NoteColor
    public var keepInPlace: Bool?
    public var includeInLayout: Bool?
    public var hidden: Bool?
    public var matchSceneColours: Bool?
    public var matchedNoteColour: String?
    public var widget: WidgetReference?
    public var widgetState: JSONValue?
    public var colours: [String]?
    public var colourProfile: ImageColourProfile?
    public var video: VideoAttachment?
    public var isVisualPrint: Bool { kind == .image || kind == .video }
    public var isKept: Bool { kind == .widget || (keepInPlace ?? false) }
    public var isHidden: Bool { hidden ?? false }
    public var isOverlayNote: Bool { kind == .note && includeInLayout == false }

    public init(id: UUID = UUID(), assetFile: String, title: String, style: PrintStyle = .tape,
                x: Double = 80, y: Double = 100, width: Double = 260, height: Double = 320,
                rotation: Double = 0, displayID: UInt32 = 0, zIndex: Int = 0,
                sourceURL: String? = nil, imageWidth: Double = 800, imageHeight: Double = 1000,
                kind: ItemKind = .image, text: String = "", noteColor: NoteColor = .yellow,
                includeInLayout: Bool? = nil) {
        self.id = id; self.kind = kind; self.assetFile = assetFile; self.title = title; self.style = style
        self.x = x; self.y = y; self.width = width; self.height = height
        self.rotation = rotation; self.displayID = displayID; self.zIndex = zIndex
        self.sourceURL = sourceURL; self.imageWidth = imageWidth; self.imageHeight = imageHeight
        self.text = text; self.noteColor = noteColor
        self.includeInLayout = includeInLayout
    }

    public func validate() throws {
        try colourProfile?.validate()
        if isVisualPrint {
            guard !assetFile.isEmpty, assetFile == URL(fileURLWithPath: assetFile).lastPathComponent,
                  !assetFile.hasPrefix("."), assetFile.hasSuffix(".png"), PrintStyle.imageStyles.contains(style) else { throw CorkError("Invalid image filename or image style.") }
            if kind == .video {
                guard let video else { throw CorkError("A video print needs its local video and still cover.") }
                try video.validate()
            }
        } else if kind == .note {
            guard assetFile.isEmpty, PrintStyle.noteStyles.contains(style), text.count <= 20_000 else { throw CorkError("Notes need a flat/sticky style and at most 20,000 characters.") }
        } else {
            guard assetFile.isEmpty, style == .flat, rotation == 0, let widget, WidgetManifest.validID(widget.provider), WidgetManifest.validID(widget.widget) else { throw CorkError("Widgets need a registered reference and cannot be rotated.") }
            if let widgetState { guard widgetState.object != nil, try widgetState.data().count <= 64_000 else { throw CorkError("Widget state must be an object under 64 KB.") } }
        }
        guard kind == .widget || (widget == nil && widgetState == nil) else { throw CorkError("Only widgets can have widget state.") }
        guard kind == .video || video == nil else { throw CorkError("Only video prints can have a video attachment.") }
        guard title.count <= 300, (sourceURL?.count ?? 0) <= 8192 else { throw CorkError("Title or source URL is too long.") }
        guard includeInLayout == nil || kind == .note else { throw CorkError("Only notes have an include-in-layout choice.") }
        guard matchSceneColours == nil || kind == .note else { throw CorkError("Only notes can match scene colours.") }
        if let matchedNoteColour { guard kind == .note, ColourMatch.isHex(matchedNoteColour) else { throw CorkError("Invalid matched note colour.") } }
        if let colours { guard (1...8).contains(colours.count), colours.allSatisfy(ColourMatch.isHex) else { throw CorkError("Invalid image colours.") } }
        guard [x, y, width, height, rotation, imageWidth, imageHeight].allSatisfy(\.isFinite),
              abs(x) <= 100_000, abs(y) <= 100_000,
              (64...4000).contains(width), (64...6000).contains(height),
              (-180...180).contains(rotation), imageWidth > 0, imageHeight > 0 else {
            throw CorkError("Invalid geometry: print size must be 64–4000 × 64–6000 points and rotation −180…180°.")
        }
    }

    public mutating func apply(_ patch: [String: JSONValue]) throws {
        let allowed: Set<String> = ["id", "x", "y", "width", "height", "rotation", "display_id", "style", "title", "z_index", "text", "note_color", "keep_in_place", "include_in_layout", "hidden", "match_scene_colours", "widget_state"]
        guard Set(patch.keys).isSubset(of: allowed) else { throw CorkError("Unknown item property.") }
        x = try patch.optionalNumber("x", fallback: x)
        y = try patch.optionalNumber("y", fallback: y)
        rotation = try patch.optionalNumber("rotation", fallback: rotation)
        let previousWidth = width
        width = try patch.optionalNumber("width", fallback: width)
        height = try patch.optionalNumber("height", fallback: height * width / previousWidth)
        if let value = patch["style"] {
            guard let name = value.string, let style = PrintStyle(rawValue: name) else { throw CorkError("Unknown print style.") }
            self.style = style
            if patch["height"] == nil, isVisualPrint { height = style.printSize(imageWidth: imageWidth, imageHeight: imageHeight, width: width).1 }
        }
        if let value = patch["title"] {
            guard let text = value.string else { throw CorkError("title must be a string.") }; title = text
        }
        if let value = patch["text"] {
            guard kind == .note, let body = value.string else { throw CorkError("text is only valid for a text note.") }; text = body
        }
        if let value = patch["note_color"] {
            guard kind == .note, let raw = value.string, let color = NoteColor(rawValue: raw) else { throw CorkError("Unknown note color.") }; noteColor = color
        }
        if let value = patch["keep_in_place"] {
            guard isVisualPrint, let enabled = value.bool else { throw CorkError("keep_in_place applies to image and video prints.") }; keepInPlace = enabled
        }
        if let value = patch["include_in_layout"] {
            guard kind == .note, let enabled = value.bool else { throw CorkError("include_in_layout must be a Boolean for a text note.") }; includeInLayout = enabled
        }
        if let value = patch["hidden"] {
            guard let enabled = value.bool else { throw CorkError("hidden must be a Boolean.") }; hidden = enabled
        }
        if let value = patch["match_scene_colours"] {
            guard kind == .note, let enabled = value.bool else { throw CorkError("match_scene_colours must be a Boolean for a text note.") }; matchSceneColours = enabled
        }
        if let state = patch["widget_state"] { guard kind == .widget else { throw CorkError("widget_state only applies to widgets.") }; widgetState = state }
        if let value = patch["display_id"] {
            guard let number = value.number, number >= 0, number <= Double(UInt32.max), number.rounded() == number else { throw CorkError("Invalid display_id.") }
            displayID = UInt32(number)
        }
        if let value = patch["z_index"] {
            guard let number = value.number, abs(number) <= 100_000, number.rounded() == number else { throw CorkError("Invalid z_index.") }
            zIndex = Int(number)
        }
        try validate()
    }
}

public struct Board: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var revision = 0
    public var items: [PrintItem] = []
    public var hidden = false
    public var desktop = DesktopSettings()
    public var rotation: WallRotationState?
    public var layoutDisplays: [DisplayInfo]?
    public init() {}
    /// Overlay notes stay above every print, including photos added by later rolls.
    public var itemsBackToFront: [PrintItem] {
        items.enumerated().filter { !$0.element.isHidden }.sorted { lhs, rhs in
            if lhs.element.isOverlayNote != rhs.element.isOverlayNote { return !lhs.element.isOverlayNote }
            if lhs.element.zIndex != rhs.element.zIndex { return lhs.element.zIndex < rhs.element.zIndex }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, revision, items, hidden, desktop, rotation, layoutDisplays }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        revision = try values.decode(Int.self, forKey: .revision)
        items = try values.decode([PrintItem].self, forKey: .items)
        hidden = try values.decode(Bool.self, forKey: .hidden)
        desktop = try values.decodeIfPresent(DesktopSettings.self, forKey: .desktop) ?? DesktopSettings()
        rotation = try values.decodeIfPresent(WallRotationState.self, forKey: .rotation)
        layoutDisplays = try values.decodeIfPresent([DisplayInfo].self, forKey: .layoutDisplays)
    }
    public func validate() throws {
        guard schemaVersion == 1 else { throw CorkError("This board uses a newer Cork format. Update Cork before opening it.") }
        guard items.count <= 500, Set(items.map(\.id)).count == items.count else { throw CorkError("The board contains too many or duplicate items.") }
        guard items.filter({ $0.kind == .widget }).count <= 20 else { throw CorkError("A wall supports up to 20 interactive widgets.") }
        for item in items { try item.validate() }
        try desktop.validate()
        try rotation?.scheme?.validate()
        if let layoutDisplays {
            guard layoutDisplays.count <= 32, Set(layoutDisplays.map(\.id)).count == layoutDisplays.count else { throw CorkError("Invalid saved display geometry.") }
            for display in layoutDisplays {
                guard [display.width, display.height, display.safeX, display.safeY, display.safeWidth, display.safeHeight, display.scale].allSatisfy(\.isFinite),
                      display.width > 0, display.height > 0, display.safeWidth > 0, display.safeHeight > 0, display.scale > 0 else { throw CorkError("Invalid saved display size.") }
            }
        }
    }
    public func applying(_ patches: [[String: JSONValue]]) throws -> Board {
        guard !patches.isEmpty, patches.count <= 500 else { throw CorkError("Provide 1–500 item updates.") }
        var next = self
        var seen = Set<UUID>()
        for patch in patches {
            guard let id = UUID(uuidString: try patch.requiredString("id")), seen.insert(id).inserted,
                  let index = next.items.firstIndex(where: { $0.id == id }) else { throw CorkError("An item is missing or appears more than once. Refresh the board.") }
            try next.items[index].apply(patch)
        }
        try next.validate()
        return next
    }
}

public struct DisplayInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: UInt32
    public var name: String
    public var width: Double
    public var height: Double
    public var scale: Double
    public var safeX: Double
    public var safeY: Double
    public var safeWidth: Double
    public var safeHeight: Double
    public init(id: UInt32, name: String, width: Double, height: Double, scale: Double = 1,
                safeX: Double = 24, safeY: Double = 48, safeWidth: Double? = nil, safeHeight: Double? = nil) {
        self.id = id; self.name = name; self.width = width; self.height = height; self.scale = scale
        self.safeX = safeX; self.safeY = safeY; self.safeWidth = safeWidth ?? width - 48; self.safeHeight = safeHeight ?? height - 96
    }
}

public enum LayoutKind: String, CaseIterable, Sendable {
    case greedy, gallery, grid, collage
    public var title: String { self == .greedy ? "Fill Space" : rawValue.capitalized }
}

public enum BoardLayout {
    public static func reflow(_ board: Board, display: DisplayInfo) throws -> Board {
        let moving = board.items.filter { $0.isVisualPrint && !$0.isKept && !$0.isHidden && ($0.displayID == display.id || $0.displayID == 0) }.map(\.id)
        return moving.isEmpty ? board : try GreedyPacking.arrange(board, ids: moving, display: display, gap: 16, preserveAngles: true)
    }
    /// Hold coordinate edits as anchors and reflow the same photos around them.
    /// Overlay notes are independent; their movement must not disturb the wall.
    public static func applyingCoordinateEdits(_ board: Board, patches: [[String: JSONValue]], displays: [DisplayInfo]) throws -> Board {
        var next = try board.applying(patches)
        var anchors = Set<UUID>(), affected = Set<UInt32>()
        func displayID(_ item: PrintItem) -> UInt32? {
            item.displayID == 0 ? displays.first?.id : displays.first(where: { $0.id == item.displayID })?.id
        }
        for (old, edited) in zip(board.items, next.items) {
            let moved = old.x != edited.x || old.y != edited.y || old.displayID != edited.displayID
            let occupiedBefore = !old.isHidden && !old.isOverlayNote, occupiedAfter = !edited.isHidden && !edited.isOverlayNote
            let participation = occupiedBefore != occupiedAfter
            guard (occupiedAfter && moved) || participation else { continue }
            if !edited.isHidden && !edited.isOverlayNote { anchors.insert(edited.id) }
            if let id = displayID(old) { affected.insert(id) }
            if let id = displayID(edited) { affected.insert(id) }
        }
        for display in displays where affected.contains(display.id) {
            try Task.checkCancellation()
            let moving = next.items.filter {
                $0.isVisualPrint && !$0.isKept && !$0.isHidden && !anchors.contains($0.id) && displayID($0) == display.id
            }.map(\.id)
            if !moving.isEmpty { next = try GreedyPacking.arrange(next, ids: moving, display: display, gap: 16, preserveAngles: true) }
        }
        return NoteColours.refresh(next)
    }
    /// Fits each decorated print within a cell. Layout is deterministic and keeps source order.
    public static func arrange(_ board: Board, ids: [UUID]? = nil, display: DisplayInfo,
                               layout: LayoutKind, gap: Double = 28) throws -> Board {
        guard gap.isFinite, (0...200).contains(gap), display.safeWidth > 64, display.safeHeight > 64 else { throw CorkError("Invalid layout area or gap.") }
        let selected = ids.map(Set.init)
        if let ids { guard !ids.isEmpty, Set(ids).count == ids.count, ids.allSatisfy({ id in board.items.contains { $0.id == id } }) else { throw CorkError("Layout contains missing or duplicate IDs.") } }
        if layout == .greedy { return try GreedyPacking.arrange(board, ids: ids, display: display, gap: gap) }
        let indices = board.items.indices.filter { !board.items[$0].isKept && !board.items[$0].isHidden && !board.items[$0].isOverlayNote && (selected?.contains(board.items[$0].id) ?? true) }
        guard !indices.isEmpty else { return board }
        let count = indices.count
        let columns = max(1, Int(ceil(sqrt(Double(count) * display.safeWidth / display.safeHeight))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cellWidth = (display.safeWidth - Double(columns - 1) * gap) / Double(columns)
        let cellHeight = (display.safeHeight - Double(rows - 1) * gap) / Double(rows)
        guard cellWidth >= 72, cellHeight >= 72 else { throw CorkError("Too many prints for this display and spacing. Arrange fewer items or reduce the gap.") }
        var result = board
        for (offset, index) in indices.enumerated() {
            var item = board.items[index]
            let angle = layout == .collage ? [-5.0, 3.0, -2.0, 4.0, -3.0][offset % 5] : 0
            let radians = abs(angle) * .pi / 180
            let ratio = item.height / item.width
            let scale = min(cellWidth / (cos(radians) + ratio * sin(radians)),
                            cellHeight / (sin(radians) + ratio * cos(radians)))
            let printWidth = min(scale, layout == .gallery ? 380 : 600)
            let printHeight = printWidth * ratio
            guard printWidth >= 64, printHeight >= 64 else { throw CorkError("These prints cannot fit at a usable size. Arrange fewer items.") }
            let column = offset % columns, row = offset / columns
            let rowCount = min(columns, count - row * columns)
            let rowInset = Double(columns - rowCount) * (cellWidth + gap) / 2
            item.width = printWidth; item.height = printHeight; item.rotation = angle
            item.x = display.safeX + rowInset + Double(column) * (cellWidth + gap) + (cellWidth - printWidth) / 2
            item.y = display.safeY + Double(row) * (cellHeight + gap) + (cellHeight - printHeight) / 2
            item.displayID = display.id
            result.items[index] = item
        }
        try result.validate()
        return result
    }
}

public struct BoardHistory: Sendable {
    private var undoStack: [Board] = []
    private var redoStack: [Board] = []
    public init() {}
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public mutating func record(_ board: Board) { undoStack.append(board); if undoStack.count > 50 { undoStack.removeFirst() }; redoStack.removeAll() }
    public mutating func undo(current: Board) -> Board? { guard let last = undoStack.popLast() else { return nil }; redoStack.append(current); return last }
    public mutating func redo(current: Board) -> Board? { guard let last = redoStack.popLast() else { return nil }; undoStack.append(current); return last }
}
