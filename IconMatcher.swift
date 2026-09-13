import Foundation
import AppKit
import CoreGraphics

struct MatchResult {
    let species: Species
    /// Mean absolute RGB difference over the sprite's opaque pixels, 0...1.
    let distance: Double
    /// How much better this beat the best candidate of a *different* species.
    /// Other forms of the same species are excluded: they are near-identical
    /// art and would otherwise mask a perfectly confident match.
    let margin: Double
}

/// Identifies a species from the artwork on a battle name plate.
///
/// The game draws every sprite at a fixed size, so there is no alignment search:
/// each reference is its icon rasterized once at load, and matching is a single
/// masked comparison per candidate. Only pixels the reference sprite fully
/// covers are compared, which keeps the plate's background gradient out of it.
final class IconMatcher {

    /// Comparison resolution. Small enough to be cheap and to wash out the
    /// video codec noise measured on the capture feed, large enough to
    /// discriminate: at this size the correct species ranks 1st of 390.
    private static let grid = 48

    /// Reject a match this far off - nothing legitimate scores near it.
    private static let maxDistance = 0.10
    /// Require the winner to beat the next species by this factor. This is the
    /// stronger signal: an unoccupied slot still produces a "best" match, but a
    /// coincidental one, with a margin near 1.0.
    private static let minMargin = 1.8

    private struct Reference {
        let species: Species
        let pixels: [UInt8]
    }

    private var references: [Reference] = []
    private(set) var isReady = false

    /// Rasterizes every reference icon. Call off the main thread.
    func prepare(from store: PokedexStore) {
        var built: [Reference] = []
        built.reserveCapacity(store.species.count)
        for species in store.species {
            guard let icon = store.icon(for: species.key),
                  let pixels = IconMatcher.rasterize(icon, IconMatcher.grid)
            else { continue }
            built.append(Reference(species: species, pixels: pixels))
        }
        references = built
        isReady = true
        print("[matcher] prepared \(built.count) references")
    }

    /// Best species for a plate's sprite crop, or nil when nothing matches
    /// confidently - an empty slot, or artwork not in the library.
    func match(_ crop: CGImage) -> MatchResult? {
        guard isReady, let cap = IconMatcher.rasterize(crop, IconMatcher.grid) else { return nil }

        var best: (ref: Reference, d: Double)?
        var bestOther: (dex: Int, d: Double)?

        for ref in references {
            guard let d = IconMatcher.distance(reference: ref.pixels, capture: cap) else { continue }
            if best == nil || d < best!.d {
                // The previous winner becomes a rival only if it is a different species.
                if let prev = best, prev.ref.species.dex != ref.species.dex,
                   bestOther == nil || prev.d < bestOther!.d {
                    bestOther = (prev.ref.species.dex, prev.d)
                }
                best = (ref, d)
            } else if ref.species.dex != best!.ref.species.dex,
                      bestOther == nil || d < bestOther!.d {
                bestOther = (ref.species.dex, d)
            }
        }

        guard let winner = best, winner.d <= IconMatcher.maxDistance else { return nil }
        let rivalDistance = bestOther?.d ?? 1.0
        let margin = winner.d > 0 ? rivalDistance / winner.d : .infinity
        guard margin >= IconMatcher.minMargin else { return nil }

        return MatchResult(species: winner.ref.species, distance: winner.d, margin: margin)
    }

    // MARK: Change detection

    /// Cheap fingerprint of a slot crop, for deciding whether anything changed.
    static func signature(_ image: CGImage) -> [UInt8]? { rasterize(image, grid) }

    /// True when two fingerprints differ by more than capture noise.
    ///
    /// Measured on 20 consecutive captured frames, the same artwork varies by
    /// RMSE 0.002-0.003 (video codec noise) while different content differs by
    /// 0.19+ - about a 60x gap, so this decision is not close. It lets the
    /// expensive library search run only when a slot's occupant actually
    /// changes, rather than on every frame.
    static func differs(_ a: [UInt8], _ b: [UInt8], threshold: Double = 0.02) -> Bool {
        guard a.count == b.count else { return true }
        var sum = 0.0
        for i in 0..<a.count {
            let d = Double(a[i]) - Double(b[i])
            sum += d * d
        }
        return (sum / Double(a.count)).squareRoot() / 255 > threshold
    }

    // MARK: Pixels

    private static func rasterize(_ image: CGImage, _ n: Int) -> [UInt8]? {
        var buf = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &buf, width: n, height: n,
                                  bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        return buf
    }

    /// Compares only where the reference is fully opaque. Alpha is
    /// premultiplied, but at full opacity that equals the straight colour, so
    /// these pixels need no unpremultiply.
    private static func distance(reference: [UInt8], capture: [UInt8]) -> Double? {
        var sum = 0.0
        var counted = 0
        for i in stride(from: 0, to: reference.count, by: 4) {
            guard reference[i + 3] > 250 else { continue }
            sum += abs(Double(reference[i]) - Double(capture[i]))
                + abs(Double(reference[i + 1]) - Double(capture[i + 1]))
                + abs(Double(reference[i + 2]) - Double(capture[i + 2]))
            counted += 1
        }
        // Sprites covering almost nothing can score well by luck.
        guard counted > grid * grid / 12 else { return nil }
        return sum / (Double(counted) * 3 * 255)
    }
}
