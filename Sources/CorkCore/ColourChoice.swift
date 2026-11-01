import Foundation

/// A saved choice, distinct from the actual family selected for one collage.
public enum ColourChoice: RawRepresentable, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case random
    case colour(ColourFamily)

    public init?(rawValue: String) {
        if rawValue == "random" { self = .random }
        else if let family = ColourFamily(rawValue: rawValue) { self = .colour(family) }
        else { return nil }
    }
    public var family: ColourFamily? { if case .colour(let family) = self { family } else { nil } }
    public var rawValue: String { family?.rawValue ?? "random" }
    public var id: String { rawValue }
    public var name: String { family?.name ?? "Random" }
    public static var allCases: [Self] { [.random] + ColourFamily.allCases.map(Self.colour) }
    public func allows(_ family: ColourFamily) -> Bool { self.family == nil || self.family == family }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer(), value = try container.decode(String.self)
        guard let choice = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown colour choice.")
        }
        self = choice
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(rawValue)
    }
}

public struct ColourCandidate: Sendable {
    public var still: ImageColourProfile
    public var motion: [ImageColourProfile]
    public init(still: ImageColourProfile, motion: [ImageColourProfile] = []) { self.still = still; self.motion = motion }
    public func matches(_ pair: [ColourFamily], strength: ColourSelectionStrength) -> Bool {
        still.matches(pair, strength: strength) && motion.allSatisfy { $0.matches(pair, strength: strength) }
    }
}

public enum ColourPairSelection {
    /// Ordered pairs with enough classified images and a represented colour in
    /// each slot. `maximum: 1` supports a cheap availability check in the UI.
    public static func availablePairs(choices: [ColourChoice], profiles: [ImageColourProfile],
                                     strength: ColourSelectionStrength, maximum: Int = .max) -> [[ColourFamily]] {
        availablePairs(choices: choices, candidates: profiles.map { ColourCandidate(still: $0) }, strength: strength, maximum: maximum)
    }
    public static func availablePairs(choices: [ColourChoice], candidates: [ColourCandidate],
                                     strength: ColourSelectionStrength, maximum: Int = .max) -> [[ColourFamily]] {
        guard choices.count == 2, maximum > 0 else { return [] }
        let represented = ColourFamily.allCases.filter { family in
            candidates.contains { $0.still.coverage(family) >= strength.minimumCoverage }
        }
        var result: [[ColourFamily]] = []
        for first in represented where choices[0].allows(first) {
            for second in represented where second != first && choices[1].allows(second) {
                let pair = [first, second]
                let matches = candidates.filter { $0.matches(pair, strength: strength) }.map(\.still)
                if matches.count >= 6 && matches.contains(where: { $0.coverage(first) > $0.coverage(second) }) && pair.allSatisfy({ family in
                    matches.contains { $0.coverage(family) >= strength.minimumCoverage }
                }) {
                    result.append(pair)
                    if result.count == maximum { return result }
                }
            }
        }
        return result
    }

    static func resolve(_ choices: [ColourChoice], candidates: [ColourCandidate], strength: ColourSelectionStrength,
                        previous: [ColourFamily]?, fillEmpty: Bool, wallpapers: WallpaperCollection,
                        matchWallpaper: Bool, display: DisplayInfo, random: inout WallRotation.Generator) throws -> [ColourFamily] {
        guard choices.count == 2 else { throw CorkError("Choose a dominant and secondary colour.") }
        let fixed = choices.compactMap(\.family)
        if fixed.count == 2 { _ = try ScenePalettes.pair(fixed); return fixed }
        // Adding pictures or refitting a display must not silently change a scene's colours.
        if fillEmpty, let previous, previous.count == 2,
           zip(choices, previous).allSatisfy({ $0.0.allows($0.1) }) { return previous }
        var pairs = availablePairs(choices: choices, candidates: candidates, strength: strength)
        if matchWallpaper && !wallpapers.wallpapers.isEmpty {
            let withBackground = pairs.filter { pair in
                guard let scheme = try? ScenePalettes.pair(pair) else { return false }
                var probe = WallRotation.Generator(state: 0)
                return wallpapers.choose(scheme: scheme, mood: scheme.id, display: display, previous: nil, random: &probe) != nil
            }
            if !withBackground.isEmpty { pairs = withBackground }
        }
        if let previous, previous.count == 2 {
            let changingAll = pairs.filter { pair in
                choices.indices.allSatisfy { choices[$0].family != nil || pair[$0] != previous[$0] }
            }
            let changingAny = pairs.filter { pair in
                choices.indices.contains { choices[$0].family == nil && pair[$0] != previous[$0] }
            }
            if !changingAll.isEmpty { pairs = changingAll }
            else if !changingAny.isEmpty { pairs = changingAny }
        }
        guard let pair = pairs.randomElement(using: &random) else {
            throw CorkError("Not enough matching photos for these colour choices. Include accents or choose another colour.")
        }
        return pair
    }
}
