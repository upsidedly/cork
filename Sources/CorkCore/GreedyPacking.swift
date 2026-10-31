import Foundation

/// Maximal empty rectangles let the next print use a gap spanning several former cells.
/// Only decorated, rotated bounds are packed: images keep their native proportions.
enum GreedyPacking {
    struct Rect: Equatable, Sendable {
        var x: Double, y: Double, width: Double, height: Double
        var maxX: Double { x + width }
        var maxY: Double { y + height }
        var area: Double { max(0, width) * max(0, height) }
        func intersects(_ other: Rect) -> Bool {
            x < other.maxX - 0.01 && maxX > other.x + 0.01 && y < other.maxY - 0.01 && maxY > other.y + 0.01
        }
        func contains(_ other: Rect) -> Bool {
            x <= other.x + 0.01 && y <= other.y + 0.01 && maxX >= other.maxX - 0.01 && maxY >= other.maxY - 0.01
        }
        func expanded(_ amount: Double) -> Rect {
            Rect(x: x - amount, y: y - amount, width: width + 2 * amount, height: height + 2 * amount)
        }
    }
    struct Candidate: Sendable {
        var index: Int
        var ratio: Double
        var style: PrintStyle
        var angle: Double
        var fresh: Bool = true
        var source: String = ""
        var affinity: Double = 1
        var colourGroup: Int? = nil
        var colourWeights: [Double]? = nil
        var effectiveColourWeights: [Double]? {
            colourWeights ?? colourGroup.map { $0 == 0 ? [1, 0] : [0, 1] }
        }
    }
    struct Placement: Sendable {
        var candidate: Candidate
        var x: Double, y: Double, width: Double, height: Double
        var box: Rect
    }
    struct Result: Sendable {
        var placements: [Placement] = []
        var free: [Rect] = []
        var score: Double {
            placements.reduce(0) { $0 + $1.box.area } - (free.map(\.area).max() ?? 0) * 1.3
        }
    }

    static func area(_ display: DisplayInfo) throws -> Rect {
        guard [display.safeX, display.safeY, display.safeWidth, display.safeHeight].allSatisfy(\.isFinite),
              (130...20_000).contains(display.safeWidth), (130...20_000).contains(display.safeHeight) else {
            throw CorkError("This display is too small or has an invalid usable area.")
        }
        return Rect(x: display.safeX, y: display.safeY, width: display.safeWidth, height: display.safeHeight)
    }
    /// The usual two-widget cluster. Avoid reserving an entire grid row below it.
    static func widgets(_ display: DisplayInfo) -> Rect {
        Rect(x: display.safeX, y: display.safeY, width: display.safeWidth * 0.4, height: display.safeHeight * 0.2)
    }
    static func bounds(_ item: PrintItem) -> Rect {
        let radians = item.rotation * .pi / 180
        let width = abs(cos(radians)) * item.width + abs(sin(radians)) * item.height
        let height = abs(sin(radians)) * item.width + abs(cos(radians)) * item.height
        return Rect(x: item.x + (item.width - width) / 2, y: item.y + (item.height - height) / 2, width: width, height: height)
    }
    static func subtract(_ occupied: Rect, from spaces: [Rect]) -> [Rect] {
        var split: [Rect] = []
        for space in spaces {
            guard space.intersects(occupied) else { split.append(space); continue }
            if occupied.x > space.x { split.append(Rect(x: space.x, y: space.y, width: occupied.x - space.x, height: space.height)) }
            if occupied.maxX < space.maxX { split.append(Rect(x: occupied.maxX, y: space.y, width: space.maxX - occupied.maxX, height: space.height)) }
            if occupied.y > space.y { split.append(Rect(x: space.x, y: space.y, width: space.width, height: occupied.y - space.y)) }
            if occupied.maxY < space.maxY { split.append(Rect(x: space.x, y: occupied.maxY, width: space.width, height: space.maxY - occupied.maxY)) }
        }
        // Overlapping free rectangles are intentional; contained duplicates are not useful.
        split = split.filter { $0.width >= 1 && $0.height >= 1 }
        return split.enumerated().filter { index, rect in
            !split.enumerated().contains { other, containing in
                other != index && containing.contains(rect) && (!rect.contains(containing) || other < index)
            }
        }.map(\.element)
    }
    static func spaces(display: DisplayInfo, obstacles: [PrintItem], gap: Double, hideWidgets: Bool = false) throws -> [Rect] {
        var free = [try area(display)]
        if !hideWidgets { free = subtract(widgets(display), from: free) }
        for item in obstacles where !item.isHidden && !item.isOverlayNote && (item.displayID == display.id || item.displayID == 0) {
            free = subtract(bounds(item).expanded(gap / 2 + 4), from: free)
        }
        return free
    }
    /// Maximal free rectangles overlap. Measure their union so overlapping or
    /// offscreen notes cannot incorrectly consume all of the sizing budget.
    static func availableArea(_ spaces: [Rect]) -> Double {
        let xs = Array(Set(spaces.flatMap { [$0.x, $0.maxX] })).sorted()
        var total = 0.0
        for (left, right) in zip(xs, xs.dropFirst()) {
            var covered = 0.0, end = -Double.infinity
            for rect in spaces.filter({ $0.x < right && $0.maxX > left }).sorted(by: { $0.y < $1.y }) {
                covered += max(0, rect.maxY - max(rect.y, end)); end = max(end, rect.maxY)
            }
            total += (right - left) * covered
        }
        return total
    }

    /// Bounded greedy search: favor useful area, edges and aspect fit, then compare a few
    /// seeded size/placement variants by coverage and the largest remaining rectangle.
    static func pack(candidates: [Candidate], free initial: [Rect], target: Int, gap: Double,
                     availableArea: Double, variant: Int, minimum: Double = 100, mixStyles: Bool = false,
                     sourceLimit: Int? = nil, initialSources: [String: Int] = [:],
                     balanceColours: Bool = false, initialColourAreas: [Int: Double] = [:]) -> Result {
        var result = Result(free: initial)
        var unused = candidates
        var styles: [PrintStyle: Int] = [:]
        var sources = initialSources
        var colourAreas = initialColourAreas
        let diverse = sourceLimit != nil
        let minimumSources = min(4, target + initialSources.count, Set(candidates.map(\.source)).count)
        let padding = gap / 2 + 2
        let average = availableArea / Double(max(1, target))
        let areaFactor = [1.12, 1.30, 0.98, 1.42, 1.20, 0.88][variant % 6]
        let goal = average * areaFactor * (variant >= 12 ? 0.50 : variant >= 6 ? 0.78 : 1)
        for offset in 0..<target {
            var best: Placement?
            var bestScore = -Double.infinity
            // Examine large gaps first; ties retain the seeded candidate order.
            for space in result.free.sorted(by: { $0.area > $1.area }).prefix(48) {
                for candidate in unused {
                    if mixStyles && offset < 4 && candidate.style != PrintStyle.imageStyles[(offset + variant) % 4] { continue }
                    if let sourceLimit, (sources[candidate.source] ?? 0) >= max(sourceLimit, initialSources[candidate.source] ?? 0) { continue }
                    if diverse && sources.count < minimumSources && sources[candidate.source] != nil { continue }
                    let radians = abs(candidate.angle) * .pi / 180
                    let fw = cos(radians) + candidate.ratio * sin(radians)
                    let fh = sin(radians) + candidate.ratio * cos(radians)
                    let fit = min((space.width - 2 * padding) / fw, (space.height - 2 * padding) / fh,
                                  4000, 6000 / candidate.ratio)
                    guard fit >= 64 else { continue }
                    let ideal = sqrt(goal / (fw * fh))
                    var widths = [min(fit, ideal)]
                    // Snapping to a gap edge or a simple subdivision avoids long leftover strips.
                    for parts in 1...4 {
                        widths.append(min(fit, (space.width / Double(parts) - 2 * padding) / fw))
                        widths.append(min(fit, (space.height / Double(parts) - 2 * padding) / fh))
                    }
                    for width in widths {
                        let height = width * candidate.ratio
                        let bw = width * fw + 2 * padding, bh = width * fh + 2 * padding
                        guard width >= max(64, minimum), height >= max(64, minimum),
                              bw * bh >= average * 0.32, bw * bh <= goal * 1.16,
                              bw <= space.width + 0.01, bh <= space.height + 0.01 else { continue }
                        let edge = max(bw / space.width, bh / space.height)
                        let fill = bw * bh / space.area
                        let smallRemainder = ((space.width - bw > 1 && space.width - bw < minimum * 0.7) ? 0.1 : 0)
                            + ((space.height - bh > 1 && space.height - bh < minimum * 0.7) ? 0.1 : 0)
                        let variety = 1 / Double(1 + (styles[candidate.style] ?? 0))
                        let sourceVariety = diverse ? 0.18 / Double(1 + (sources[candidate.source] ?? 0)) : 0
                        var colourBalance = 1.0
                        if balanceColours, let weights = candidate.effectiveColourWeights {
                            let first = colourAreas[0] ?? 0, second = colourAreas[1] ?? 0
                            // Balance visible area, including kept prints, without defeating aspect-ratio fitting.
                            colourBalance = 1 + 0.55 * (second - first) / max(average, first + second)
                                * (weights[0] - weights[1]) / max(0.01, weights[0] + weights[1])
                        }
                        let score = bw * bh * (1 + 0.20 * edge + 0.22 * fill + 0.08 * variety
                                                + sourceVariety + (candidate.fresh ? 0.06 : 0) + candidate.affinity * 0.85 - smallRemainder) * colourBalance
                        if score > bestScore {
                            let corner = (variant + offset) % 4
                            let box = Rect(x: corner == 1 || corner == 3 ? space.maxX - bw : space.x,
                                           y: corner >= 2 ? space.maxY - bh : space.y, width: bw, height: bh)
                            bestScore = score
                            best = Placement(candidate: candidate, x: box.x + (bw - width) / 2, y: box.y + (bh - height) / 2,
                                             width: width, height: height, box: box)
                        }
                    }
                }
            }
            guard let best else { break }
            result.placements.append(best); styles[best.candidate.style, default: 0] += 1
            sources[best.candidate.source, default: 0] += 1
            if let weights = best.candidate.effectiveColourWeights {
                for group in 0..<2 { colourAreas[group, default: 0] += best.box.area * weights[group] }
            }
            unused.removeAll { $0.index == best.candidate.index }
            result.free = subtract(best.box, from: result.free)
        }
        return result
    }

    static func arrange(_ board: Board, ids: [UUID]?, display: DisplayInfo, gap: Double, preserveAngles: Bool = false) throws -> Board {
        let selected = ids.map(Set.init)
        let indices = board.items.indices.filter {
            let item = board.items[$0]
            return item.kind == .image && !item.isKept && !item.isHidden && (selected?.contains(item.id) ?? (item.displayID == display.id || item.displayID == 0))
        }
        guard !indices.isEmpty else { return board }
        let moving = Set(indices)
        let obstacles = board.items.enumerated().filter { !moving.contains($0.offset) }.map(\.element)
        let free = try spaces(display: display, obstacles: obstacles, gap: gap, hideWidgets: board.desktop.widgetsHidden)
        let area = availableArea(free)
        var best: Result?
        for variant in 0..<18 {
            if variant >= 6, best != nil { break }
            try Task.checkCancellation()
            let candidates = indices.map { index in
                let item = board.items[index]
                return Candidate(index: index, ratio: item.height / item.width, style: item.style,
                                 angle: preserveAngles ? item.rotation : [-2.0, 2.5, -1.5, 3.0, -2.5, 1.0][(index + variant) % 6])
            }
            let result = pack(candidates: candidates, free: free, target: indices.count, gap: gap,
                              availableArea: max(area, 1), variant: variant, minimum: 64)
            if result.placements.count == indices.count, best.map({ result.score > $0.score }) ?? true { best = result }
        }
        guard let best else { throw CorkError("These prints cannot fit around the notes and widgets. Arrange fewer items or reduce the gap.") }
        var next = board
        for placement in best.placements {
            let index = placement.candidate.index
            next.items[index].x = placement.x; next.items[index].y = placement.y
            next.items[index].width = placement.width; next.items[index].height = placement.height
            next.items[index].rotation = placement.candidate.angle; next.items[index].displayID = display.id
        }
        try next.validate(); return next
    }
}
