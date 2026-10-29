import Foundation

public struct ColourScheme: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var colours: [String]
    public init(id: String, name: String, colours: [String]) { self.id = id; self.name = name; self.colours = colours }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 80, name.count <= 120, (1...8).contains(colours.count),
              colours.allSatisfy(ColourMatch.isHex), Set(colours.map { $0.uppercased() }).count == colours.count else { throw CorkError("Invalid scene palette.") }
    }
}
public struct SceneOptions: Codable, Equatable, Sendable {
    public var matchColours = true
    public var matchWallpaper = true
    public var paletteID: String?
    public init() {}
    public func validate() throws {
        if let paletteID, !ScenePalettes.all.contains(where: { $0.id == paletteID }) { throw CorkError("Unknown colour palette.") }
    }
}

public enum ScenePalettes {
    public static let all: [ColourScheme] = [
        .init(id: "open-air", name: "Moss & paper", colours: ["#2A3A2B", "#65705A", "#B7B9A3", "#E9E1CF", "#846044"]),
        .init(id: "summit-days", name: "Silver & blue", colours: ["#273747", "#647887", "#A4B1B5", "#E4E2DB", "#947E6E"]),
        .init(id: "golden-hour", name: "Honey & grain", colours: ["#3B2E21", "#85633C", "#C5A36B", "#EAD9B5", "#58614B"]),
        .init(id: "warm-rooms", name: "Lived-in light", colours: ["#352D26", "#705B46", "#A39A79", "#E5DDC9", "#486455"]),
        .init(id: "backstage", name: "After hours", colours: ["#181E24", "#3A3432", "#685245", "#A58D76", "#783F43"]),
        .init(id: "garage-wall", name: "Redline & ink", colours: ["#1D1D1D", "#6B2928", "#AB6A48", "#D5C8AD", "#697576"]),
        .init(id: "blue-hour", name: "Night blue", colours: ["#172637", "#344F68", "#6B8293", "#AFB4BF", "#936B6C"]),
        .init(id: "print-shop", name: "Faded color", colours: ["#3E3941", "#7C7284", "#AA958D", "#D8CEBA", "#657B87"]),
        .init(id: "sketchbook", name: "Soft graphite", colours: ["#383632", "#78756A", "#ADA89A", "#E7E0D3", "#8C7769"]),
        .init(id: "ink-and-paper", name: "Ink & concrete", colours: ["#14191C", "#494E52", "#858A8D", "#CFD1CD", "#EDE9DF"]),
        .init(id: "oxblood", name: "Oxblood & parchment", colours: ["#2B141C", "#6B283B", "#AA6864", "#E4D3B7", "#6E7974"]),
        .init(id: "rose-smoke", name: "Rose & smoke", colours: ["#3C2E3F", "#876D86", "#C39AA2", "#E4D4CB", "#6B8587"]),
        .init(id: "lavender-dusk", name: "Lavender dusk", colours: ["#25283F", "#615B88", "#A28BA4", "#D6C7D4", "#8A9995"]),
        .init(id: "sea-glass", name: "Sea glass & brass", colours: ["#173B3E", "#397E7A", "#85AAA0", "#D9DED1", "#A78B53"])
    ]
    public static func choose(mood: String, preferred: String?, anchors: [[String]], variation: UInt64 = 0) -> ColourScheme {
        if let preferred, let exact = all.first(where: { $0.id == preferred }) { return exact }
        let samples = anchors.filter { !$0.isEmpty }
        if !samples.isEmpty {
            return all.max { a, b in
                samples.reduce(0) { $0 + ColourMatch.score($1, against: a.colours) } < samples.reduce(0) { $0 + ColourMatch.score($1, against: b.colours) }
            } ?? all[0]
        }
        let alternatives: [String: [String]] = [
            "open-air": ["sea-glass"], "summit-days": ["sea-glass", "lavender-dusk"],
            "warm-rooms": ["rose-smoke"], "backstage": ["oxblood"],
            "garage-wall": ["oxblood"], "blue-hour": ["lavender-dusk", "sea-glass"],
            "print-shop": ["oxblood", "rose-smoke", "lavender-dusk", "sea-glass"], "sketchbook": ["rose-smoke", "lavender-dusk"]
        ]
        let ids = [mood] + (alternatives[mood] ?? [])
        let choices = ids.compactMap { id in all.first { $0.id == id } }
        return choices.isEmpty ? all[0] : choices[Int(variation % UInt64(choices.count))]
    }
}

/// Oklab math is based on the published colour-space definition. Matching is an
/// inspectable palette-distance heuristic, not an aesthetic or semantic classifier.
public enum ColourMatch {
    struct Lab: Sendable {
        var l: Double, a: Double, b: Double
        func distance(_ other: Lab) -> Double {
            sqrt(pow((l - other.l) * 0.65, 2) + pow(a - other.a, 2) + pow(b - other.b, 2))
        }
    }
    public static func isHex(_ value: String) -> Bool { value.count == 7 && value.first == "#" && value.dropFirst().allSatisfy(\.isHexDigit) }
    static func lab(_ hex: String) -> Lab? {
        guard isHex(hex), let rgb = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        func linear(_ n: UInt32) -> Double { let s = Double(n) / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        let r = linear((rgb >> 16) & 255), g = linear((rgb >> 8) & 255), b = linear(rgb & 255)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return Lab(l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                   a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                   b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }
    public static func score(_ colours: [String], against target: [String]) -> Double {
        let samples = colours.compactMap(lab), targets = target.compactMap(lab)
        guard !samples.isEmpty, !targets.isEmpty else { return 0 }
        var weighted = 0.0, weights = 0.0
        for (index, colour) in samples.enumerated() {
            let distance = targets.map { colour.distance($0) }.min() ?? 1
            let weight = index == 0 ? 2.0 : 1.0
            weighted += exp(-distance * 9) * weight; weights += weight
        }
        return weighted / weights
    }
    /// Backdrops should carry the palette's colour family, rather than winning only
    /// because grey happens to be close to a neutral swatch in every scheme.
    public static func backgroundScore(_ colours: [String], against target: [String]) -> Double {
        let forward = score(colours, against: target)
        let expressive = target.compactMap(lab).filter { hypot($0.a, $0.b) >= 0.025 }
        let samples = colours.compactMap(lab)
        guard !expressive.isEmpty, !samples.isEmpty else { return forward }
        var sum = 0.0
        for target in expressive {
            var nearest = Double.infinity
            for sample in samples { nearest = min(nearest, hypot(target.a - sample.a, target.b - sample.b)) }
            sum += exp(-nearest * 14.0)
        }
        let presence = sum / Double(expressive.count)
        return forward * 0.65 + presence * 0.35
    }
    private static func dominantColour(_ colours: [String]) -> Lab? {
        // Imported swatches are ordered by pixel prevalence. A small accent later
        // in the palette must not excuse a background with a different main hue.
        colours.prefix(3).compactMap(lab).first { $0.l > 0.10 && hypot($0.a, $0.b) >= 0.025 }
    }
    /// Validate the backdrop against the photos actually selected, not just a
    /// broad preset whose neutral/accent swatches can hide a blue/purple mismatch.
    public static func wallpaperHueAffinity(_ colours: [String], imagePalettes: [[String]]) -> Double {
        guard !imagePalettes.isEmpty else { return 1 }
        let background = dominantColour(colours)
        let photos = imagePalettes.compactMap(dominantColour)
        let minimum = max(1, Int(ceil(Double(imagePalettes.count) * 0.35)))
        if photos.count < minimum {
            return background.map { hypot($0.a, $0.b) < 0.04 ? 0.6 : 0 } ?? 0.6
        }
        guard let background else { return 0.6 } // A neutral backdrop is a quiet fallback.
        var a = 0.0, b = 0.0
        for colour in photos {
            let chroma = hypot(colour.a, colour.b)
            a += colour.a / chroma; b += colour.b / chroma
        }
        let magnitude = hypot(a, b)
        guard magnitude / Double(photos.count) >= 0.45 else {
            return hypot(background.a, background.b) < 0.04 ? 0.6 : 0
        }
        let dot = (a * background.a + b * background.b) / (magnitude * hypot(background.a, background.b))
        let angle = acos(min(1, max(-1, dot)))
        guard angle <= .pi / 8 else { return 0 } // Keep blue separate from pink/purple.
        return 1 - angle * 0.2
    }
}
