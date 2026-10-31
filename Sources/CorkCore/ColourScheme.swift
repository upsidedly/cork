import Foundation

public struct ColourScheme: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var colours: [String]
    /// Two deliberate colour families, rather than a main hue with neutral accents.
    public var majorColours: [String]?
    public var colourFamilies: [ColourFamily]?
    public init(id: String, name: String, colours: [String], majorColours: [String]? = nil) {
        self.id = id; self.name = name; self.colours = colours; self.majorColours = majorColours
    }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 80, name.count <= 120, (1...8).contains(colours.count),
              colours.allSatisfy(ColourMatch.isHex), Set(colours.map { $0.uppercased() }).count == colours.count else { throw CorkError("Invalid scene palette.") }
        if let majorColours {
            guard majorColours.count == 2, Set(majorColours.map { $0.uppercased() }).count == 2,
                  majorColours.allSatisfy({ colour in colours.contains { $0.uppercased() == colour.uppercased() } }),
                  colourFamilies != nil || ColourMatch.distinctHues(majorColours) else { throw CorkError("A paired palette needs two distinct chromatic colours from its swatches.") }
        }
        if let colourFamilies {
            guard colourFamilies.count == 2, Set(colourFamilies).count == 2, majorColours == colourFamilies.map(\.hex) else { throw CorkError("Choose two different colour families.") }
        }
    }
}
public struct SceneOptions: Codable, Equatable, Sendable {
    public var matchColours = true
    public var matchWallpaper = true
    public var paletteID: String?
    public var colourPair: [ColourFamily]?
    public var colourStrength: ColourSelectionStrength?
    public var selectedStrength: ColourSelectionStrength { colourStrength ?? .strong }
    public init() {}
    public func validate() throws {
        if let paletteID, !ScenePalettes.all.contains(where: { $0.id == paletteID }) { throw CorkError("Unknown colour palette.") }
        if let colourPair {
            guard paletteID == nil else { throw CorkError("Choose a preset palette or two colours.") }
            try ScenePalettes.pair(colourPair).validate()
        }
    }
}

public enum ScenePalettes {
    public static func pair(_ families: [ColourFamily]) throws -> ColourScheme {
        guard families.count == 2, Set(families).count == 2 else { throw CorkError("Choose two different colours.") }
        var swatches = families.map(\.hex)
        for neutral in ["#202326", "#EEE9DD", "#8C9296"] where !swatches.contains(neutral) { swatches.append(neutral) }
        var result = ColourScheme(id: "pair-" + families.map(\.rawValue).joined(separator: "-"),
            name: families.map(\.name).joined(separator: " + "), colours: swatches, majorColours: families.map(\.hex))
        result.colourFamilies = families; return result
    }
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
        .init(id: "sea-glass", name: "Sea glass & brass", colours: ["#173B3E", "#397E7A", "#85AAA0", "#D9DED1", "#A78B53"]),
        .init(id: "blue-butter", name: "Blue & butter", colours: ["#2C6196", "#D7B54A", "#172B45", "#F1E6C7", "#A9C2D1"], majorColours: ["#2C6196", "#D7B54A"]),
        .init(id: "teal-rust", name: "Teal & rust", colours: ["#397B7A", "#AD6042", "#1B3535", "#E9D9C5", "#9FBBB0"], majorColours: ["#397B7A", "#AD6042"]),
        .init(id: "forest-rose", name: "Forest & rose", colours: ["#45634B", "#BF8796", "#243A2C", "#EEE1D5", "#9FA995"], majorColours: ["#45634B", "#BF8796"]),
        .init(id: "cobalt-vermilion", name: "Cobalt & vermilion", colours: ["#3456A0", "#BB443A", "#202838", "#E9DECB", "#91A5BF"], majorColours: ["#3456A0", "#BB443A"]),
        .init(id: "plum-ochre", name: "Plum & ochre", colours: ["#735177", "#C19A43", "#302334", "#E8DDC4", "#B19BAF"], majorColours: ["#735177", "#C19A43"]),
        .init(id: "sage-lilac", name: "Sage & lilac", colours: ["#7D9772", "#9B81AF", "#354239", "#E9E4D7", "#C5C9B3"], majorColours: ["#7D9772", "#9B81AF"]),
        .init(id: "olive-coral", name: "Olive & coral", colours: ["#757C3F", "#C77769", "#343A25", "#EEE1C5", "#AEB389"], majorColours: ["#757C3F", "#C77769"]),
        .init(id: "espresso-ice", name: "Espresso & ice", colours: ["#78503A", "#76B2CA", "#30251F", "#E7DFD1", "#A8CAD5"], majorColours: ["#78503A", "#76B2CA"])
    ]
    public static func choose(mood: String, preferred: String?, anchors: [[String]], variation: UInt64 = 0) -> ColourScheme {
        if let preferred, let exact = all.first(where: { $0.id == preferred }) { return exact }
        if let paired = all.first(where: { $0.id == mood && $0.majorColours != nil }) { return paired }
        let samples = anchors.filter { !$0.isEmpty }
        if !samples.isEmpty {
            return all.filter { $0.majorColours == nil }.max { a, b in
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
        return lab(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    static func lab(red: Double, green: Double, blue: Double) -> Lab {
        func linear(_ s: Double) -> Double { s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        let r = linear(red), g = linear(green), b = linear(blue)
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
    private static func dominantColour(_ colours: [String], minimumChroma: Double = 0.025) -> Lab? {
        // Imported swatches are ordered by pixel prevalence. A small accent later
        // in the palette must not excuse a background with a different main hue.
        colours.prefix(3).compactMap(lab).first { $0.l > 0.10 && hypot($0.a, $0.b) >= minimumChroma }
    }
    private static func hueAngle(_ a: Lab, _ b: Lab) -> Double {
        let denominator = hypot(a.a, a.b) * hypot(b.a, b.b)
        guard denominator > 0 else { return .pi }
        return acos(min(1, max(-1, (a.a * b.a + a.b * b.b) / denominator)))
    }
    static func distinctHues(_ colours: [String]) -> Bool {
        let values = colours.compactMap(lab)
        return values.count == 2 && values.allSatisfy { hypot($0.a, $0.b) >= 0.025 }
            && hueAngle(values[0], values[1]) >= .pi / 4
    }
    /// Only prevalent chromatic swatches assign a family; tiny accents and greys cannot claim a half of the pair.
    public static func majorColourIndex(_ colours: [String], scheme: ColourScheme) -> Int? {
        guard let majors = scheme.majorColours, majors.count == 2, let sample = dominantColour(colours, minimumChroma: 0.04) else { return nil }
        let targets = majors.compactMap(lab)
        guard targets.count == 2, let index = targets.indices.min(by: { hueAngle(sample, targets[$0]) < hueAngle(sample, targets[$1]) }),
              hueAngle(sample, targets[index]) <= .pi / 7 else { return nil }
        return index
    }
    /// Validate the backdrop against the photos actually selected, not just a
    /// broad preset whose neutral/accent swatches can hide a blue/purple mismatch.
    public static func wallpaperHueAffinity(_ colours: [String], imagePalettes: [[String]], majorColours: [String]? = nil) -> Double {
        guard !imagePalettes.isEmpty else { return 1 }
        let background = dominantColour(colours)
        let photos = imagePalettes.compactMap { dominantColour($0, minimumChroma: majorColours == nil ? 0.025 : 0.04) }
        if let majors = majorColours, majors.count == 2 {
            guard let background else { return 0.6 }
            let families = majors.compactMap(lab)
            guard families.count == 2, let family = families.min(by: { hueAngle(background, $0) < hueAngle(background, $1) }),
                  hueAngle(background, family) <= .pi / 5 else { return 0 }
            let represented = photos.filter { hueAngle($0, family) <= .pi / 5 }
            guard represented.count >= max(1, Int(ceil(Double(imagePalettes.count) * 0.20))) else { return 0 }
            let direction = represented.reduce(Lab(l: 0, a: 0, b: 0)) { sum, value in
                let chroma = hypot(value.a, value.b)
                return Lab(l: 0, a: sum.a + value.a / chroma, b: sum.b + value.b / chroma)
            }
            let angle = hueAngle(background, direction)
            return angle <= .pi / 8 ? 1 - angle * 0.2 : 0
        }
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
