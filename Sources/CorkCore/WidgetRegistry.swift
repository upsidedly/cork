import Foundation

public struct WidgetReference: Codable, Equatable, Sendable {
    public var provider: String
    public var widget: String
    public init(provider: String, widget: String) { self.provider = provider; self.widget = widget }
}

public enum WidgetPlacement {
    /// Photos can reflow; fixed prints, participating notes and other widgets cannot.
    public static func position(in board: Board, display: DisplayInfo, width: Double, height: Double,
                                x: Double? = nil, y: Double? = nil) throws -> (x: Double, y: Double) {
        if let x, let y { return (x, y) }
        let fixed = board.items.filter { !$0.isVisualPrint || $0.isKept }
        let spaces = try GreedyPacking.spaces(display: display, obstacles: fixed, gap: 24, hideWidgets: board.desktop.widgetsHidden)
        let candidates = spaces.compactMap { space -> GreedyPacking.Rect? in
            let rect = GreedyPacking.Rect(x: x ?? space.x, y: y ?? space.y, width: width, height: height)
            return space.contains(rect) ? rect : nil
        }.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
        guard let chosen = candidates.first else { throw CorkError("There is no room for this widget around your fixed items. Move, resize or hide a fixed item, then add it again.") }
        return (chosen.x, chosen.y)
    }
}
public struct WidgetDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var entry: String
    public var width: Double
    public var height: Double
    public init(id: String, name: String, description: String, entry: String, width: Double = 260, height: Double = 220) {
        self.id = id; self.name = name; self.description = description; self.entry = entry; self.width = width; self.height = height
    }
}
public struct WidgetManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var version: String
    public var widgets: [WidgetDefinition]
    public func validate() throws {
        guard schemaVersion == 1, Self.validID(id), !name.isEmpty, name.count <= 120, version.count <= 80,
              (1...50).contains(widgets.count), Set(widgets.map(\.id)).count == widgets.count else { throw CorkError("Invalid widget provider manifest.") }
        for widget in widgets {
            guard Self.validID(widget.id), !widget.name.isEmpty, widget.name.count <= 120, widget.description.count <= 1000,
                  !widget.entry.hasPrefix("/"), !widget.entry.split(separator: "/").contains(".."),
                  URL(fileURLWithPath: widget.entry).pathExtension.lowercased() == "html",
                  (96...1200).contains(widget.width), (96...1200).contains(widget.height) else { throw CorkError("Invalid widget entry or size.") }
        }
    }
    public static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 120 && !value.hasPrefix(".") && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }
}
public struct RegisteredWidgetProvider: Codable, Equatable, Identifiable, Sendable {
    public var id: String { manifest.id }
    public var manifest: WidgetManifest
    public var directory: String
    public var source: String
}
public struct WidgetRegistry: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var providers: [RegisteredWidgetProvider] = []
    public init() {}
    public func definition(_ reference: WidgetReference) -> WidgetDefinition? {
        providers.first { $0.id == reference.provider }?.manifest.widgets.first { $0.id == reference.widget }
    }
    public func entryURL(_ reference: WidgetReference, root: URL) -> URL? {
        guard let provider = providers.first(where: { $0.id == reference.provider }), let definition = definition(reference) else { return nil }
        let base = root.appendingPathComponent("Widgets/" + provider.directory).resolvingSymlinksInPath()
        let entry = base.appendingPathComponent(definition.entry).resolvingSymlinksInPath()
        guard entry.pathComponents.starts(with: base.pathComponents), entry.pathComponents.count > base.pathComponents.count,
              FileManager.default.fileExists(atPath: entry.path) else { return nil }
        return entry
    }
    public func validate() throws {
        guard schemaVersion == 1, providers.count <= 100, Set(providers.map(\.id)).count == providers.count else { throw CorkError("Invalid widget registry.") }
        for provider in providers {
            try provider.manifest.validate()
            guard UUID(uuidString: provider.directory) != nil, provider.source.hasPrefix("/"), provider.source.count <= 8192 else { throw CorkError("Invalid stored widget provider.") }
        }
    }
}
extension BoardRepository {
    public func loadWidgets() throws -> WidgetRegistry {
        try prepare()
        let path = root.appendingPathComponent("widgets.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return WidgetRegistry() }
        func read(_ url: URL) throws -> WidgetRegistry {
            let data = try Data(contentsOf: url); guard data.count <= 2_000_000 else { throw CorkError("Widget registry is too large.") }
            let registry = try JSONDecoder().decode(WidgetRegistry.self, from: data); try registry.validate(); return registry
        }
        do { return try read(path) }
        catch { if let previous = try? read(root.appendingPathComponent("widgets.previous.json")) { return previous }; throw error }
    }
    public func registerWidgets(at path: String) throws -> WidgetRegistry {
        guard path.hasPrefix("/") else { throw CorkError("Choose an absolute local widget manifest path.") }
        let source = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let info = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, let size = info.fileSize, (1...500_000).contains(size) else { throw CorkError("Choose a regular widget manifest under 500 KB.") }
        let data = try Data(contentsOf: source); guard data.count <= 500_000 else { throw CorkError("Widget manifest must be under 500 KB.") }
        let manifest = try JSONDecoder().decode(WidgetManifest.self, from: data); try manifest.validate()
        let base = source.deletingLastPathComponent(), directory = UUID().uuidString
        let target = root.appendingPathComponent("Widgets/" + directory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: target) } }
        let allowed: Set<String> = ["html", "js", "css", "json", "png", "jpg", "jpeg", "svg", "webp", "woff", "woff2", "wav", "mp3"]
        guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { throw CorkError("Cannot read the widget package.") }
        var total = 0, count = 0
        for case let file as URL in files {
            try Task.checkCancellation()
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isSymbolicLink != true else { throw CorkError("Widget packages cannot contain symbolic links.") }
            guard info.isRegularFile == true else { continue }
            guard allowed.contains(file.pathExtension.lowercased()) else { throw CorkError("Unsupported widget resource type.") }
            count += 1; total += info.fileSize ?? 0
            guard count <= 200, total <= 20_000_000 else { throw CorkError("Keep widget packages under 200 files and 20 MB.") }
            let canonical = file.resolvingSymlinksInPath()
            guard canonical.pathComponents.starts(with: base.pathComponents) else { throw CorkError("Widget resources must remain inside their package.") }
            let relative = canonical.pathComponents.dropFirst(base.pathComponents.count).joined(separator: "/"), copy = target.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: copy)
        }
        for widget in manifest.widgets { guard FileManager.default.fileExists(atPath: target.appendingPathComponent(widget.entry).path) else { throw CorkError("A widget HTML entry is missing.") } }
        var registry = try loadWidgets()
        let provider = RegisteredWidgetProvider(manifest: manifest, directory: directory, source: source.path)
        if let index = registry.providers.firstIndex(where: { $0.id == manifest.id }) { registry.providers[index] = provider } else { registry.providers.append(provider) }
        try registry.validate()
        let destination = root.appendingPathComponent("widgets.json")
        if let previous = try? Data(contentsOf: destination) { try previous.write(to: root.appendingPathComponent("widgets.previous.json"), options: [.atomic]) }
        try JSONEncoder().encode(registry).write(to: destination, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        committed = true; return registry
    }
}
